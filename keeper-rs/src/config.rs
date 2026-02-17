use crate::deployments::DeploymentArtifact;
use ethers::types::Address;
use eyre::{eyre, Result};
use std::{path::PathBuf, str::FromStr, time::Duration};

#[derive(Debug, Clone)]
pub struct KeeperConfig {
    pub chain_id: u64,
    pub rpc_url: String,
    pub opensub: Address,
    pub start_block: u64,

    pub poll_interval: Duration,
    pub log_chunk_size: u64,
    pub confirmations: u64,

    pub state_file: PathBuf,
    pub max_concurrency: usize,

    pub private_key_env: String,

    pub gas_limit: Option<u64>,

    /// Max number of collect() txs to submit per cycle.
    pub max_txs_per_cycle: usize,

    /// How long to wait for a transaction receipt before considering it "still pending".
    pub tx_timeout: Duration,

    /// How long to keep an in-flight tx in the state file before dropping it and allowing a retry.
    pub pending_ttl: Duration,

    /// Milestone 5.1: backoff base duration for retryable failures (e.g., insufficient allowance/balance).
    pub backoff_base: Duration,

    /// Milestone 5.1: maximum backoff duration.
    pub backoff_max: Duration,

    /// Milestone 5.1: backoff base duration for PlanInactive.
    pub plan_inactive_backoff: Duration,

    /// Milestone 5.1: backoff base duration for transient RPC errors.
    pub rpc_error_backoff: Duration,

    /// Milestone 5.1: deterministic jitter window to avoid thundering herd.
    pub jitter: Duration,

    /// Whether to simulate collect() via eth_call before sending a transaction.
    ///
    /// This avoids wasting gas on transactions that would revert.
    pub simulate: bool,

    pub once: bool,
    pub dry_run: bool,
}

impl KeeperConfig {
    #[allow(clippy::too_many_arguments)]
    pub fn from_cli_and_deployment(
        deployment: &DeploymentArtifact,
        rpc_override: Option<String>,
        private_key_env: String,
        poll_seconds: u64,
        log_chunk: u64,
        confirmations: u64,
        state_file: PathBuf,
        max_concurrency: usize,
        gas_limit: Option<u64>,
        max_txs_per_cycle: usize,
        tx_timeout_seconds: u64,
        pending_ttl_seconds: u64,
        backoff_base_seconds: u64,
        backoff_max_seconds: u64,
        plan_inactive_backoff_seconds: u64,
        rpc_error_backoff_seconds: u64,
        jitter_seconds: u64,
        simulate: bool,
        once: bool,
        dry_run: bool,
    ) -> Result<Self> {
        let rpc_url = rpc_override
            .or_else(|| std::env::var("OPENSUB_KEEPER_RPC_URL").ok())
            .or_else(|| {
                deployment
                    .rpc_env_var
                    .as_ref()
                    .and_then(|k| std::env::var(k).ok())
            })
            .or_else(|| deployment.rpc.clone())
            .ok_or_else(|| {
                eyre!(
                    "no rpc url provided. pass --rpc-url, set OPENSUB_KEEPER_RPC_URL, set deployment.rpcEnvVar, or include rpc in deployment json"
                )
            })?;

        let opensub = Address::from_str(&deployment.open_sub)
            .map_err(|e| eyre!("invalid openSub address '{}': {e}", deployment.open_sub))?;

        if log_chunk == 0 {
            return Err(eyre!("log chunk size must be > 0"));
        }
        if max_concurrency == 0 {
            return Err(eyre!("max concurrency must be > 0"));
        }

        if max_txs_per_cycle == 0 {
            return Err(eyre!("max txs per cycle must be > 0"));
        }

        if rpc_url.contains("alchemy.com/v2/") || rpc_url.contains("infura.io/v3/") {
            tracing::warn!("RPC URL looks like it may contain an API key; consider using OPENSUB_KEEPER_RPC_URL env instead of committing it.");
        }

        if backoff_max_seconds > 0 && backoff_base_seconds > backoff_max_seconds {
            tracing::warn!(
                base = backoff_base_seconds,
                max = backoff_max_seconds,
                "backoff base > max; clamping base to max"
            );
        }

        if plan_inactive_backoff_seconds > 0 && plan_inactive_backoff_seconds > backoff_max_seconds
        {
            tracing::warn!(
                plan_inactive = plan_inactive_backoff_seconds,
                max = backoff_max_seconds,
                "plan inactive backoff > max; clamping to max"
            );
        }

        Ok(Self {
            chain_id: deployment.chain_id,
            rpc_url,
            opensub,
            start_block: deployment.start_block,
            poll_interval: Duration::from_secs(poll_seconds.max(1)),
            log_chunk_size: log_chunk,
            confirmations,
            state_file,
            max_concurrency,
            private_key_env,
            gas_limit,
            max_txs_per_cycle,
            tx_timeout: Duration::from_secs(tx_timeout_seconds.max(5)),
            pending_ttl: Duration::from_secs(pending_ttl_seconds.max(30)),
            backoff_max: Duration::from_secs(backoff_max_seconds.max(1)),
            backoff_base: Duration::from_secs(
                backoff_base_seconds.max(1).min(backoff_max_seconds.max(1)),
            ),
            plan_inactive_backoff: Duration::from_secs(
                plan_inactive_backoff_seconds
                    .max(1)
                    .min(backoff_max_seconds.max(1)),
            ),
            rpc_error_backoff: Duration::from_secs(rpc_error_backoff_seconds.max(1)),
            jitter: Duration::from_secs(jitter_seconds),
            simulate,
            once,
            dry_run,
        })
    }
}
