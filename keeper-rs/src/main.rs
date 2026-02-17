mod collector;
mod config;
mod deployments;
mod erc20;
mod opensub;
mod scanner;
mod state;

use clap::Parser;
use collector::collect_due;
use config::KeeperConfig;
use deployments::DeploymentArtifact;
use ethers::middleware::NonceManagerMiddleware;
use ethers::prelude::{Http, LocalWallet, Provider, SignerMiddleware};
use ethers::providers::Middleware;
use ethers::signers::Signer;
use eyre::{eyre, Result};
use opensub::OpenSub;
use state::{FailureKind, KeeperState, ReconcileOutcome};
use std::fs::OpenOptions;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use fs2::FileExt;

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_secs()
}

fn compute_backoff_seconds(
    cfg: &KeeperConfig,
    kind: FailureKind,
    consecutive_failures: u32,
    subscription_id: u64,
) -> u64 {
    // Exponential backoff with deterministic jitter.
    //
    // Important: this must remain fast even if `consecutive_failures` grows large over time.
    let base = match kind {
        FailureKind::PlanInactive => cfg.plan_inactive_backoff.as_secs().max(1),
        FailureKind::RpcError => cfg.rpc_error_backoff.as_secs().max(1),
        FailureKind::InsufficientAllowance
        | FailureKind::InsufficientBalance
        | FailureKind::SimulationRevert
        | FailureKind::MinedRevert
        | FailureKind::Unknown => cfg.backoff_base.as_secs().max(1),
    };

    let max = cfg.backoff_max.as_secs().max(1);

    // Clamp base to max so the cap remains meaningful.
    let base = base.min(max);

    // base * 2^(consecutive_failures - 1), then clamped to max.
    let exp = consecutive_failures.saturating_sub(1).min(63);
    let mut backoff = base.saturating_mul(1u64 << exp).min(max);

    // Deterministic jitter in [0, jitter_max) to reduce thundering herd,
    // clamped so backoff_max remains a hard cap.
    let jitter_max = cfg.jitter.as_secs();
    if jitter_max > 0 {
        backoff = backoff
            .saturating_add(subscription_id % jitter_max)
            .min(max);
    }

    backoff
}

#[derive(Parser, Debug)]
#[command(
    name = "opensub-keeper",
    version,
    about = "OpenSub Milestone 5 keeper bot (Rust)"
)]
struct Args {
    /// Path to a deployment artifact JSON (e.g., deployments/base-sepolia.json)
    #[arg(long, default_value = "deployments/base-sepolia.json")]
    deployment: PathBuf,

    /// Override RPC URL. If omitted, uses OPENSUB_KEEPER_RPC_URL or deployment.rpc.
    #[arg(long)]
    rpc_url: Option<String>,

    /// Environment variable name that contains the keeper's private key.
    #[arg(long, default_value = "KEEPER_PRIVATE_KEY")]
    private_key_env: String,

    /// Polling interval in seconds.
    #[arg(long, default_value_t = 30)]
    poll_seconds: u64,

    /// Block confirmations to wait before scanning logs.
    #[arg(long, default_value_t = 2)]
    confirmations: u64,

    /// Log scan chunk size (blocks per eth_getLogs request).
    #[arg(long, default_value_t = 2000)]
    log_chunk: u64,

    /// Max concurrent RPC calls/tx sends.
    #[arg(long, default_value_t = 10)]
    max_concurrency: usize,

    /// Optional fixed gas limit for collect() calls.
    #[arg(long)]
    gas_limit: Option<u64>,

    /// Max number of collect() transactions to submit per cycle.
    ///
    /// This is a safety valve to avoid draining the keeper wallet if something goes wrong.
    #[arg(long, default_value_t = 25)]
    max_txs_per_cycle: usize,

    /// How many seconds to wait for a transaction receipt before treating it as "still pending".
    #[arg(long, default_value_t = 120)]
    tx_timeout_seconds: u64,

    /// How many seconds to keep an in-flight tx recorded before dropping it and allowing a retry.
    #[arg(long, default_value_t = 900)]
    pending_ttl_seconds: u64,

    /// Milestone 5.1: base backoff (seconds) for retryable failures.
    #[arg(long, default_value_t = 300)]
    backoff_base_seconds: u64,

    /// Milestone 5.1: maximum backoff (seconds).
    #[arg(long, default_value_t = 21600)]
    backoff_max_seconds: u64,

    /// Milestone 5.1: base backoff (seconds) when plan is inactive.
    #[arg(long, default_value_t = 1800)]
    plan_inactive_backoff_seconds: u64,

    /// Milestone 5.1: base backoff (seconds) for transient RPC errors.
    #[arg(long, default_value_t = 30)]
    rpc_error_backoff_seconds: u64,

    /// Milestone 5.1: add deterministic jitter in [0, jitterSeconds) to spread retries.
    #[arg(long, default_value_t = 30)]
    jitter_seconds: u64,

    /// Disable collect() eth_call simulation guardrail.
    #[arg(long)]
    no_simulate: bool,

    /// Ignore persisted per-subscription backoff and check everything every cycle.
    ///
    /// Useful for debugging. Not recommended for normal operation.
    #[arg(long)]
    ignore_backoff: bool,

    /// Where to store keeper state (last scanned block, subscription IDs).
    #[arg(long, default_value = "keeper-rs/state/state.json")]
    state_file: PathBuf,

    /// Run a single scan+collect cycle and exit.
    #[arg(long)]
    once: bool,

    /// Don't send transactions; only print what would be done.
    #[arg(long)]
    dry_run: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    let deployment = DeploymentArtifact::load(&args.deployment)?;

    let ignore_backoff = args.ignore_backoff;

    let cfg = KeeperConfig::from_cli_and_deployment(
        &deployment,
        args.rpc_url,
        args.private_key_env,
        args.poll_seconds,
        args.log_chunk,
        args.confirmations,
        args.state_file,
        args.max_concurrency,
        args.gas_limit,
        args.max_txs_per_cycle,
        args.tx_timeout_seconds,
        args.pending_ttl_seconds,
        args.backoff_base_seconds,
        args.backoff_max_seconds,
        args.plan_inactive_backoff_seconds,
        args.rpc_error_backoff_seconds,
        args.jitter_seconds,
        !args.no_simulate,
        args.once,
        args.dry_run,
    )?;

    let private_key = std::env::var(&cfg.private_key_env).map_err(|_| {
        eyre!(
            "missing private key env var '{}'. Set it in your shell before running.",
            cfg.private_key_env
        )
    })?;

    let wallet: LocalWallet = private_key
        .parse::<LocalWallet>()
        .map_err(|e| eyre!("invalid private key in {}: {e}", cfg.private_key_env))?
        .with_chain_id(cfg.chain_id);

    // Provider + signer.
    let provider =
        Provider::<Http>::try_from(cfg.rpc_url.as_str())?.interval(Duration::from_millis(800));

    // Hard safety check: ensure we're connected to the expected chain.
    let remote_chain_id = provider.get_chainid().await?.as_u64();
    if remote_chain_id != cfg.chain_id {
        return Err(eyre!(
            "RPC chainId mismatch: deployment expects {}, but RPC reports {}. Refusing to run.",
            cfg.chain_id,
            remote_chain_id
        ));
    }

    // Ensure OpenSub has code at the configured address.
    let code = provider.get_code(cfg.opensub, None).await?;
    if code.0.is_empty() {
        return Err(eyre!(
            "no contract code found at OpenSub address {:?}. Check deployments JSON and RPC.",
            cfg.opensub
        ));
    }

    let signer = SignerMiddleware::new(provider, wallet.clone());
    let client = NonceManagerMiddleware::new(signer, wallet.address());
    let client = Arc::new(client);

    // Ensure the state directory exists before we create/lock the lockfile.
    //
    // Without this, a first-time run can fail when the state parent directory
    // (e.g. keeper-rs/state/) does not yet exist.
    if let Some(parent) = cfg.state_file.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)
                .map_err(|e| eyre!("failed to create state directory {}: {e}", parent.display()))?;
        }
    }

    // Single-instance guard: lock alongside the state file.
    // This prevents two keepers from running concurrently with the same signer/state.
    let lock_path = cfg.state_file.with_extension("lock");
    let lock_file = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .truncate(false)
        .open(&lock_path)
        .map_err(|e| eyre!("failed to open lock file {}: {e}", lock_path.display()))?;
    lock_file.try_lock_exclusive().map_err(|e| {
        eyre!(
            "keeper already running or lock unavailable ({}): {e}",
            lock_path.display()
        )
    })?;
    // Keep file handle alive.
    let _lock_guard = lock_file;

    tracing::info!(
        chain_id = cfg.chain_id,
        opensub = ?cfg.opensub,
        start_block = cfg.start_block,
        signer = ?wallet.address(),
        dry_run = cfg.dry_run,
        simulate = cfg.simulate,
        ignore_backoff,
        once = cfg.once,
        "keeper starting"
    );

    let mut state = KeeperState::load_or_init(&cfg.state_file, cfg.start_block)?;

    let opensub = OpenSub::new(cfg.opensub, client.clone());

    loop {
        // 0) Reconcile any in-flight txs from previous cycles (or restarts).
        let reconcile = state
            .reconcile_in_flight(client.as_ref(), cfg.pending_ttl)
            .await?;

        let ReconcileOutcome {
            cleared,
            finalized_success,
            finalized_revert,
        } = reconcile;

        if cleared > 0 {
            tracing::info!(cleared, "cleared in-flight txs");
        }

        // If a previously pending tx finalized, treat it as a success/failure so we don't keep
        // stale backoff state forever.
        //
        // In dry-run mode, we do not persist these updates.
        if !cfg.dry_run {
            let now = now_unix();
            let mut dirty = cleared > 0;

            for id in finalized_success {
                dirty = true;
                state.note_success(id);
            }

            for id in finalized_revert {
                dirty = true;

                let prev = state
                    .retries
                    .get(&id)
                    .map(|r| r.consecutive_failures)
                    .unwrap_or(0);
                let consecutive = prev.saturating_add(1);
                let backoff_s =
                    compute_backoff_seconds(&cfg, FailureKind::MinedRevert, consecutive, id);
                let next_retry_at = now.saturating_add(backoff_s);

                tracing::warn!(
                    subscription_id = id,
                    kind = ?FailureKind::MinedRevert,
                    consecutive,
                    backoff_s,
                    next_retry_at,
                    "in-flight collect tx mined but reverted; backing off"
                );

                state.note_failure(
                    id,
                    FailureKind::MinedRevert,
                    next_retry_at,
                    Some("in-flight tx mined but reverted".to_string()),
                );
            }

            if dirty {
                state.save(&cfg.state_file)?;
            }
        }

        // 1) Scan for new subscriptions.
        let newly = scanner::scan_new_subscriptions(
            client.as_ref(),
            cfg.opensub,
            cfg.start_block,
            cfg.confirmations,
            cfg.log_chunk_size,
            &mut state,
        )
        .await?;

        state.save(&cfg.state_file)?;

        // 2) Collect due payments.
        // Skip ids that have an in-flight tx; prevents duplicate collects while a tx is pending.
        let now = now_unix();
        let total_known = state.subscription_ids.len();
        let mut skipped_in_flight = 0usize;
        let mut skipped_backoff = 0usize;

        let ids: Vec<u64> = state
            .subscription_ids
            .iter()
            .copied()
            .filter(|id| {
                if state.in_flight.contains_key(id) {
                    skipped_in_flight += 1;
                    return false;
                }
                if !ignore_backoff && state.should_skip_due_to_backoff(*id, now) {
                    skipped_backoff += 1;
                    return false;
                }
                true
            })
            .collect();
        if total_known == 0 {
            tracing::info!("no subscriptions known yet");
        } else if ids.is_empty() {
            tracing::info!(
                total_known,
                skipped_in_flight,
                skipped_backoff,
                "no subscriptions eligible this cycle"
            );
        } else {
            tracing::info!(
                total_known,
                checking = ids.len(),
                newly,
                skipped_in_flight,
                skipped_backoff,
                "checking subscriptions"
            );
            let outcome = collect_due(
                opensub.clone(),
                cfg.opensub,
                client.clone(),
                ids,
                cfg.max_concurrency,
                cfg.gas_limit,
                cfg.max_txs_per_cycle,
                cfg.tx_timeout,
                cfg.simulate,
                cfg.dry_run,
            )
            .await?;

            let pending_len = outcome.pending.len();
            let successes_len = outcome.successes.len();
            let failures_len = outcome.failures.len();

            let collector::CollectOutcome {
                stats,
                pending,
                successes,
                failures,
            } = outcome;

            // In dry-run mode, we intentionally do not persist pending txs or backoff updates.
            // This keeps `--dry-run` side-effect free (beyond advancing scan progress).
            if !cfg.dry_run {
                // Record any txs that are still pending.
                for p in pending {
                    state.mark_in_flight(p.subscription_id, p.tx_hash);
                }

                // Successes clear backoff.
                for id in successes {
                    state.note_success(id);
                }

                // Failures set/update backoff.
                if !failures.is_empty() {
                    for f in failures {
                        let prev = state
                            .retries
                            .get(&f.subscription_id)
                            .map(|r| r.consecutive_failures)
                            .unwrap_or(0);
                        let consecutive = prev.saturating_add(1);
                        let backoff_s =
                            compute_backoff_seconds(&cfg, f.kind, consecutive, f.subscription_id);
                        let next_retry_at = now.saturating_add(backoff_s);

                        tracing::warn!(
                            subscription_id = f.subscription_id,
                            kind = ?f.kind,
                            consecutive,
                            backoff_s,
                            next_retry_at,
                            reason = f.reason.as_deref().unwrap_or(""),
                            "collect failed; backing off"
                        );

                        state.note_failure(f.subscription_id, f.kind, next_retry_at, f.reason);
                    }
                }

                state.save(&cfg.state_file)?;
            }

            tracing::info!(
                ?stats,
                pending = pending_len,
                successes = successes_len,
                failures = failures_len,
                "cycle complete"
            );
        }

        if cfg.once {
            break;
        }

        tokio::time::sleep(cfg.poll_interval).await;
    }

    Ok(())
}
