use crate::erc20::Erc20;
use crate::opensub::OpenSub;
use crate::state::FailureKind;
use ethers::providers::Middleware;
use ethers::types::{Address, U256, U64};
use eyre::Result;
use futures::stream;
use futures::StreamExt;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct PendingTx {
    pub subscription_id: u64,
    pub tx_hash: ethers::types::H256,
}

#[derive(Debug, Clone)]
pub struct FailureRecord {
    pub subscription_id: u64,
    pub kind: FailureKind,
    pub reason: Option<String>,
}

#[derive(Debug, Default, Clone)]
pub struct CollectOutcome {
    pub stats: CollectStats,
    /// Transactions that were sent but did not produce a receipt within the configured timeout.
    /// These should be tracked as "in-flight" to avoid duplicate collects.
    pub pending: Vec<PendingTx>,

    /// Subscriptions that were successfully collected this cycle.
    pub successes: Vec<u64>,

    /// Failures that should be backoff-tracked by the caller.
    pub failures: Vec<FailureRecord>,
}

#[derive(Debug, Default, Clone)]
#[allow(dead_code)]
pub struct CollectStats {
    pub checked: usize,
    pub due: usize,
    pub sent: usize,
    pub succeeded: usize,
    pub failed: usize,
    pub precheck_failed: usize,
    pub throttled: usize,
    pub pending: usize,
}

#[allow(clippy::too_many_arguments)]
pub async fn collect_due<M: Middleware + 'static>(
    opensub: OpenSub<M>,
    opensub_address: Address,
    client: Arc<M>,
    subscription_ids: Vec<u64>,
    max_concurrency: usize,
    gas_limit: Option<u64>,
    max_txs_per_cycle: usize,
    tx_timeout: Duration,
    force_pending: bool,
    simulate: bool,
    dry_run: bool,
) -> Result<CollectOutcome> {
    let stats = Arc::new(AtomicStats::default());

    // Safety valve: cap tx submissions per cycle.
    //
    // IMPORTANT: this is a *total submissions* cap, not just a concurrency cap.
    // We intentionally do not "release" budget after a tx completes.
    let remaining_budget = Arc::new(AtomicUsize::new(max_txs_per_cycle));

    // Collect pending txs for persistence.
    let pending_out = Arc::new(tokio::sync::Mutex::new(Vec::<PendingTx>::new()));

    // Collect successes/failures for backoff accounting.
    let successes_out = Arc::new(tokio::sync::Mutex::new(Vec::<u64>::new()));
    let failures_out = Arc::new(tokio::sync::Mutex::new(Vec::<FailureRecord>::new()));

    let opensub = Arc::new(opensub);
    let client = client;

    stream::iter(subscription_ids)
        .for_each_concurrent(max_concurrency, |id| {
            let opensub = opensub.clone();
            let client = client.clone();
            let stats = stats.clone();
            let remaining_budget = remaining_budget.clone();
            let pending_out = pending_out.clone();
            let successes_out = successes_out.clone();
            let failures_out = failures_out.clone();
            async move {
                stats.checked.fetch_add(1, Ordering::Relaxed);

                let id_u256 = U256::from(id);

                // Cheap pre-check to avoid revert/gas waste.
                let due = match opensub.is_due(id_u256).call().await {
                    Ok(v) => v,
                    Err(err) => {
                        stats.failed.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!(subscription_id = id, error = %err, "isDue call failed");
                        failures_out
                            .lock()
                            .await
                            .push(FailureRecord {
                                subscription_id: id,
                                kind: FailureKind::RpcError,
                                reason: Some(err.to_string()),
                            });
                        return;
                    }
                };

                if !due {
                    return;
                }

                stats.due.fetch_add(1, Ordering::Relaxed);

                // Prechecks (Milestone 5.1): avoid spending gas on collect() that will revert.
                //
                // 1) Read subscription -> get planId/subscriber.
                let (plan_id, subscriber, status, _start, _paid_through, _last) = match opensub
                    .subscriptions(id_u256)
                    .call()
                    .await
                {
                    Ok(v) => v,
                    Err(err) => {
                        stats.failed.fetch_add(1, Ordering::Relaxed);
                        failures_out
                            .lock()
                            .await
                            .push(FailureRecord {
                                subscription_id: id,
                                kind: FailureKind::RpcError,
                                reason: Some(err.to_string()),
                            });
                        tracing::warn!(subscription_id = id, error = %err, "subscriptions() call failed");
                        return;
                    }
                };

                // Status enum: 1 == Active.
                // If it changed between isDue() and now, skip (another actor may have cancelled).
                if status != 1u8 {
                    tracing::info!(subscription_id = id, status, "subscription no longer Active; skipping");
                    return;
                }

                // 2) Read plan -> active/token/price.
                let (_merchant, token, price, _interval, _fee_bps, plan_active, _created_at) =
                    match opensub.plans(plan_id).call().await {
                        Ok(v) => v,
                        Err(err) => {
                            stats.failed.fetch_add(1, Ordering::Relaxed);
                            failures_out
                                .lock()
                                .await
                                .push(FailureRecord {
                                    subscription_id: id,
                                    kind: FailureKind::RpcError,
                                    reason: Some(err.to_string()),
                                });
                            tracing::warn!(subscription_id = id, plan_id = ?plan_id, error = %err, "plans() call failed");
                            return;
                        }
                    };

                if !plan_active {
                    stats.precheck_failed.fetch_add(1, Ordering::Relaxed);
                    failures_out
                        .lock()
                        .await
                        .push(FailureRecord {
                            subscription_id: id,
                            kind: FailureKind::PlanInactive,
                            reason: Some("plan inactive".to_string()),
                        });
                    tracing::info!(subscription_id = id, plan_id = ?plan_id, "plan inactive; backing off");
                    return;
                }

                // 3) Check allowance/balance for the total price.
                // Note: OpenSub performs two transferFrom calls, but the same spender (OpenSub).
                // Total allowance needed is at least `price`.
                let erc20 = Erc20::new(token, client.clone());
                let spender = opensub_address;

                let allowance = match erc20.allowance(subscriber, spender).call().await {
                    Ok(v) => v,
                    Err(err) => {
                        stats.failed.fetch_add(1, Ordering::Relaxed);
                        failures_out
                            .lock()
                            .await
                            .push(FailureRecord {
                                subscription_id: id,
                                kind: FailureKind::RpcError,
                                reason: Some(err.to_string()),
                            });
                        tracing::warn!(subscription_id = id, error = %err, "allowance() call failed");
                        return;
                    }
                };

                if allowance < price {
                    stats.precheck_failed.fetch_add(1, Ordering::Relaxed);
                    failures_out
                        .lock()
                        .await
                        .push(FailureRecord {
                            subscription_id: id,
                            kind: FailureKind::InsufficientAllowance,
                            reason: Some(format!("allowance {} < price {}", allowance, price)),
                        });
                    tracing::info!(subscription_id = id, allowance = %allowance, price = %price, "insufficient allowance; backing off");
                    return;
                }

                let balance = match erc20.balance_of(subscriber).call().await {
                    Ok(v) => v,
                    Err(err) => {
                        stats.failed.fetch_add(1, Ordering::Relaxed);
                        failures_out
                            .lock()
                            .await
                            .push(FailureRecord {
                                subscription_id: id,
                                kind: FailureKind::RpcError,
                                reason: Some(err.to_string()),
                            });
                        tracing::warn!(subscription_id = id, error = %err, "balanceOf() call failed");
                        return;
                    }
                };

                if balance < price {
                    stats.precheck_failed.fetch_add(1, Ordering::Relaxed);
                    failures_out
                        .lock()
                        .await
                        .push(FailureRecord {
                            subscription_id: id,
                            kind: FailureKind::InsufficientBalance,
                            reason: Some(format!("balance {} < price {}", balance, price)),
                        });
                    tracing::info!(subscription_id = id, balance = %balance, price = %price, "insufficient balance; backing off");
                    return;
                }

                if dry_run {
                    tracing::info!(subscription_id = id, "DRY RUN: would call collect()");
                    return;
                }


                // Quick check: if the per-cycle tx budget is already exhausted, skip early.
                // (We still enforce the budget atomically right before sending.)
                if remaining_budget.load(Ordering::Relaxed) == 0 {
                    stats.throttled.fetch_add(1, Ordering::Relaxed);
                    tracing::warn!(
                        subscription_id = id,
                        "tx budget exhausted; skipping collect this cycle"
                    );
                    return;
                }

                if simulate {
                    // Final guardrail: simulate collect() via eth_call.
                    // This avoids spending gas on transactions that would revert.
                    match opensub.collect(id_u256).call().await {
                        Ok((_merchant_amount, _collector_fee)) => {
                            // ok
                        }
                        Err(err) => {
                            stats.precheck_failed.fetch_add(1, Ordering::Relaxed);
                            failures_out
                                .lock()
                                .await
                                .push(FailureRecord {
                                    subscription_id: id,
                                    kind: FailureKind::SimulationRevert,
                                    reason: Some(err.to_string()),
                                });
                            tracing::warn!(subscription_id = id, error = %err, "collect() simulation reverted; backing off");
                            return;
                        }
                    }
                }

                // Enforce per-cycle tx cap (total submissions).
                // Failed sends still count against the budget; this is a safety feature.
                let budget_ok = remaining_budget
                    .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |cur| {
                        if cur == 0 { None } else { Some(cur - 1) }
                    })
                    .is_ok();

                if !budget_ok {
                    stats.throttled.fetch_add(1, Ordering::Relaxed);
                    tracing::warn!(
                        subscription_id = id,
                        "tx budget exhausted; skipping collect this cycle"
                    );
                    return;
                }


                // Build collect tx.
                let mut call = opensub.collect(id_u256);
                if let Some(gl) = gas_limit {
                    call = call.gas(U256::from(gl));
                }

                // Send.
                let pending = match call.send().await {
                    Ok(p) => p,
                    Err(err) => {
                        stats.failed.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!(subscription_id = id, error = %err, "collect send failed");
                        failures_out
                            .lock()
                            .await
                            .push(FailureRecord {
                                subscription_id: id,
                                kind: FailureKind::RpcError,
                                reason: Some(err.to_string()),
                            });
                        return;
                    }
                };

                stats.sent.fetch_add(1, Ordering::Relaxed);

                let tx_hash = pending.tx_hash();

                if force_pending {
                    stats.pending.fetch_add(1, Ordering::Relaxed);
                    tracing::info!(
                        subscription_id = id,
                        tx = ?tx_hash,
                        "force-pending enabled; skipping receipt wait"
                    );
                    pending_out
                        .lock()
                        .await
                        .push(PendingTx { subscription_id: id, tx_hash });
                    return;
                }

                // Wait for receipt.
                let receipt_res = tokio::time::timeout(tx_timeout, pending).await;

                match receipt_res {
                    Ok(Ok(Some(rcpt))) => {
                        let ok = rcpt.status == Some(U64::from(1));
                        if ok {
                            stats.succeeded.fetch_add(1, Ordering::Relaxed);
                            tracing::info!(subscription_id = id, tx = ?tx_hash, "collect succeeded");
                            successes_out.lock().await.push(id);
                        } else {
                            stats.failed.fetch_add(1, Ordering::Relaxed);
                            tracing::warn!(subscription_id = id, tx = ?tx_hash, "collect mined but reverted");
                            failures_out
                                .lock()
                                .await
                                .push(FailureRecord {
                                    subscription_id: id,
                                    kind: FailureKind::MinedRevert,
                                    reason: Some("mined but reverted".to_string()),
                                });
                        }
                    }
                    Ok(Ok(None)) => {
                        // Uncommon: provider returned no receipt.
                        stats.pending.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!(subscription_id = id, tx = ?tx_hash, "collect sent but receipt not available yet; tracking as in-flight");
                        pending_out
                            .lock()
                            .await
                            .push(PendingTx { subscription_id: id, tx_hash });
                    }
                    Ok(Err(err)) => {
                        // We successfully submitted the tx, but failed while waiting for the receipt.
                        // Conservatively treat as "pending" and track it as in-flight to avoid duplicate collects.
                        stats.pending.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!(subscription_id = id, tx = ?tx_hash, error = %err, "collect receipt error; tracking as in-flight");
                        pending_out
                            .lock()
                            .await
                            .push(PendingTx { subscription_id: id, tx_hash });
                    }
                    Err(_) => {
                        // Timed out waiting for receipt; treat as pending.
                        stats.pending.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!(subscription_id = id, tx = ?tx_hash, timeout_s = tx_timeout.as_secs(), "collect still pending after timeout; tracking as in-flight");
                        pending_out
                            .lock()
                            .await
                            .push(PendingTx { subscription_id: id, tx_hash });
                    }
                }
            }
        })
        .await;

    let pending = pending_out.lock().await.clone();
    let successes = successes_out.lock().await.clone();
    let failures = failures_out.lock().await.clone();
    Ok(CollectOutcome {
        stats: stats.into_collect_stats(),
        pending,
        successes,
        failures,
    })
}

#[derive(Debug, Default)]
struct AtomicStats {
    checked: AtomicUsize,
    due: AtomicUsize,
    sent: AtomicUsize,
    succeeded: AtomicUsize,
    failed: AtomicUsize,
    precheck_failed: AtomicUsize,
    throttled: AtomicUsize,
    pending: AtomicUsize,
}

impl AtomicStats {
    fn into_collect_stats(self: Arc<Self>) -> CollectStats {
        CollectStats {
            checked: self.checked.load(Ordering::Relaxed),
            due: self.due.load(Ordering::Relaxed),
            sent: self.sent.load(Ordering::Relaxed),
            succeeded: self.succeeded.load(Ordering::Relaxed),
            failed: self.failed.load(Ordering::Relaxed),
            precheck_failed: self.precheck_failed.load(Ordering::Relaxed),
            throttled: self.throttled.load(Ordering::Relaxed),
            pending: self.pending.load(Ordering::Relaxed),
        }
    }
}
