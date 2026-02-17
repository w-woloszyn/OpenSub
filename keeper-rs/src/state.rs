use ethers::providers::Middleware;
use ethers::types::H256;
use eyre::{eyre, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::Path,
    str::FromStr,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FailureKind {
    RpcError,
    PlanInactive,
    InsufficientAllowance,
    InsufficientBalance,
    SimulationRevert,
    MinedRevert,
    Unknown,
}

impl Default for FailureKind {
    fn default() -> Self {
        FailureKind::Unknown
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RetryInfo {
    pub consecutive_failures: u32,
    pub next_retry_at: u64,
    #[serde(default)]
    pub last_failure_kind: FailureKind,
    #[serde(default)]
    pub last_failure_reason: Option<String>,
}

impl Default for RetryInfo {
    fn default() -> Self {
        Self {
            consecutive_failures: 0,
            next_retry_at: 0,
            last_failure_kind: FailureKind::Unknown,
            last_failure_reason: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InFlightTx {
    pub tx_hash: String,
    pub sent_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeeperState {
    /// The highest block number we have fully scanned for `Subscribed` events.
    pub last_scanned_block: u64,

    /// Set of discovered subscription IDs.
    /// Stored as a sorted list for deterministic diffs.
    pub subscription_ids: Vec<u64>,

    /// In-flight collect() txs keyed by subscriptionId.
    ///
    /// This prevents duplicate collect calls while a previous tx is still pending.
    #[serde(default)]
    pub in_flight: BTreeMap<u64, InFlightTx>,

    /// Per-subscription retry/backoff state.
    ///
    /// This is a Milestone 5.1 guardrail: if collect() would revert (plan inactive, insufficient
    /// allowance/balance, RPC errors, etc.), we back off to avoid repeatedly wasting gas or
    /// hammering RPCs.
    #[serde(default)]
    pub retries: BTreeMap<u64, RetryInfo>,
}

#[derive(Debug, Clone, Default)]
pub struct ReconcileOutcome {
    pub cleared: usize,
    pub finalized_success: Vec<u64>,
    pub finalized_revert: Vec<u64>,
}

impl KeeperState {
    pub fn load_or_init(path: impl AsRef<Path>, start_block: u64) -> Result<Self> {
        let path = path.as_ref();
        if path.exists() {
            let raw = fs::read_to_string(path)
                .map_err(|e| eyre!("failed to read state file {}: {e}", path.display()))?;
            let st: KeeperState = serde_json::from_str(&raw)
                .map_err(|e| eyre!("failed to parse state file {}: {e}", path.display()))?;
            return Ok(st);
        }

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| eyre!("failed to create state directory {}: {e}", parent.display()))?;
        }

        let init = KeeperState {
            last_scanned_block: start_block.saturating_sub(1),
            subscription_ids: Vec::new(),
            in_flight: BTreeMap::new(),
            retries: BTreeMap::new(),
        };
        init.save(path)?;
        Ok(init)
    }

    pub fn save(&self, path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| eyre!("failed to create state directory {}: {e}", parent.display()))?;
        }

        let json = serde_json::to_string_pretty(self)
            .map_err(|e| eyre!("failed to serialize keeper state: {e}"))?;

        // Atomic-ish write: write to a temp file then rename.
        // This reduces the chance of a corrupted state file if the process is interrupted.
        let tmp_path = path.with_extension("json.tmp");
        fs::write(&tmp_path, json).map_err(|e| {
            eyre!(
                "failed to write temp state file {}: {e}",
                tmp_path.display()
            )
        })?;

        // Atomic-ish replace:
        // - On Unix, rename replaces the destination if it exists.
        // - On Windows, rename fails if the destination exists; in that case we remove then rename.
        if let Err(err) = fs::rename(&tmp_path, path) {
            if cfg!(windows) {
                let _ = fs::remove_file(path);
                fs::rename(&tmp_path, path)
                    .map_err(|e| eyre!("failed to replace state file {}: {e}", path.display()))?;
            } else {
                return Err(eyre!(
                    "failed to replace state file {}: {err}",
                    path.display()
                ));
            }
        }
        Ok(())
    }

    pub fn ids_set(&self) -> BTreeSet<u64> {
        self.subscription_ids.iter().copied().collect()
    }

    pub fn set_ids_from_set(&mut self, ids: BTreeSet<u64>) {
        self.subscription_ids = ids.into_iter().collect();
    }

    pub fn mark_in_flight(&mut self, subscription_id: u64, tx_hash: H256) {
        let now = now_unix();
        self.in_flight.insert(
            subscription_id,
            InFlightTx {
                tx_hash: format!("{:#x}", tx_hash),
                sent_at: now,
            },
        );
    }

    pub fn should_skip_due_to_backoff(&self, subscription_id: u64, now: u64) -> bool {
        self.retries
            .get(&subscription_id)
            .map(|r| now < r.next_retry_at)
            .unwrap_or(false)
    }

    pub fn note_success(&mut self, subscription_id: u64) {
        // On success, clear any previous backoff.
        self.retries.remove(&subscription_id);
    }

    pub fn note_failure(
        &mut self,
        subscription_id: u64,
        kind: FailureKind,
        next_retry_at: u64,
        reason: Option<String>,
    ) {
        let entry = self.retries.entry(subscription_id).or_default();
        entry.consecutive_failures = entry.consecutive_failures.saturating_add(1);
        entry.next_retry_at = next_retry_at;
        entry.last_failure_kind = kind;
        // Keep the reason small to avoid bloating state.
        entry.last_failure_reason = reason.map(|s| {
            const MAX: usize = 240;
            // Avoid slicing by bytes (can panic on non-UTF8-boundary indices).
            let mut out: String = s.chars().take(MAX).collect();
            if out.len() < s.len() {
                out.push_str("...");
            }
            out
        });
    }

    pub async fn reconcile_in_flight<M: Middleware>(
        &mut self,
        client: &M,
        ttl: Duration,
    ) -> Result<ReconcileOutcome> {
        if self.in_flight.is_empty() {
            return Ok(ReconcileOutcome::default());
        }

        let now = now_unix();
        let ttl_s = ttl.as_secs();

        let mut kept = BTreeMap::new();
        let mut cleared = 0usize;
        let mut finalized_success = Vec::<u64>::new();
        let mut finalized_revert = Vec::<u64>::new();

        for (sub_id, inflight) in self.in_flight.iter() {
            // Drop very old pending txs so the keeper can retry.
            if ttl_s > 0 && now.saturating_sub(inflight.sent_at) > ttl_s {
                tracing::warn!(
                    subscription_id = *sub_id,
                    tx = %inflight.tx_hash,
                    age_s = now.saturating_sub(inflight.sent_at),
                    ttl_s,
                    "in-flight tx expired; dropping"
                );
                cleared += 1;
                continue;
            }

            let tx_hash = match H256::from_str(&inflight.tx_hash) {
                Ok(h) => h,
                Err(_) => {
                    tracing::warn!(
                        subscription_id = *sub_id,
                        tx = %inflight.tx_hash,
                        "invalid tx hash in state; dropping"
                    );
                    cleared += 1;
                    continue;
                }
            };

            match client.get_transaction_receipt(tx_hash).await {
                Ok(Some(rcpt)) => {
                    let status = rcpt.status.unwrap_or_default().as_u64();
                    tracing::info!(
                        subscription_id = *sub_id,
                        tx = %inflight.tx_hash,
                        status,
                        block = rcpt.block_number.map(|b| b.as_u64()),
                        "in-flight tx finalized; clearing"
                    );
                    if status == 1 {
                        finalized_success.push(*sub_id);
                    } else {
                        finalized_revert.push(*sub_id);
                    }
                    cleared += 1;
                }
                Ok(None) => {
                    kept.insert(*sub_id, inflight.clone());
                }
                Err(err) => {
                    tracing::warn!(
                        subscription_id = *sub_id,
                        tx = %inflight.tx_hash,
                        error = %err,
                        "failed to fetch receipt for in-flight tx; keeping"
                    );
                    kept.insert(*sub_id, inflight.clone());
                }
            }
        }

        self.in_flight = kept;
        Ok(ReconcileOutcome {
            cleared,
            finalized_success,
            finalized_revert,
        })
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_secs()
}
