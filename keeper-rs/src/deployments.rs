use eyre::{eyre, Result};
use serde::Deserialize;
use std::{fs, path::Path};

/// Minimal subset of `deployments/base-sepolia.json` used by the keeper.
///
/// We intentionally keep this loose: extra fields are ignored.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentArtifact {
    pub chain_id: u64,
    #[serde(default)]
    pub rpc: Option<String>,
    /// Optional name of an environment variable that contains the RPC URL.
    /// Useful to avoid committing provider API keys.
    #[serde(default)]
    pub rpc_env_var: Option<String>,
    pub open_sub: String,
    pub start_block: u64,

    // Optional conveniences (not required by the keeper)
    #[serde(default)]
    pub plan_id: Option<u64>,
    #[serde(default)]
    pub token: Option<String>,
}

impl DeploymentArtifact {
    pub fn load(path: impl AsRef<Path>) -> Result<Self> {
        let path = path.as_ref();
        let raw = fs::read_to_string(path)
            .map_err(|e| eyre!("failed to read deployment artifact {}: {e}", path.display()))?;
        let art: DeploymentArtifact = serde_json::from_str(&raw).map_err(|e| {
            eyre!(
                "failed to parse deployment artifact {}: {e}",
                path.display()
            )
        })?;

        if art.open_sub.trim().is_empty() {
            return Err(eyre!("deployment artifact openSub is empty"));
        }
        if art.start_block == 0 {
            // Not strictly invalid, but almost always wrong for log scanning.
            tracing::warn!(
                "deployment artifact startBlock is 0; this will scan from genesis and may be slow"
            );
        }

        Ok(art)
    }
}
