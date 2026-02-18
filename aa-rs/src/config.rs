use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::{env, fs, path::Path};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploymentRaw {
    pub chain_id: u64,
    pub rpc: String,
    #[serde(default)]
    pub rpc_env_var: Option<String>,
    pub open_sub: String,
    pub token: String,
    pub decimals: u8,
    pub plan_id: u64,
    pub start_block: u64,

    #[serde(default)]
    #[allow(dead_code)]
    pub merchant_addr: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    pub subscriber_addr: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    pub collector_addr: Option<String>,

    #[serde(default)]
    #[allow(dead_code)]
    pub tx_hashes: Option<serde_json::Value>,
}

#[derive(Debug, Clone)]
pub struct Deployment {
    pub chain_id: u64,
    pub rpc_url: String,
    pub open_sub: ethers::types::Address,
    pub token: ethers::types::Address,
    #[allow(dead_code)]
    pub decimals: u8,
    pub plan_id: ethers::types::U256,
    #[allow(dead_code)]
    pub start_block: u64,
}

pub fn load_deployment(path: &Path, rpc_override: Option<String>) -> Result<Deployment> {
    let raw = fs::read_to_string(path)
        .with_context(|| format!("failed to read deployment json at {}", path.display()))?;
    let raw: DeploymentRaw = serde_json::from_str(&raw)
        .with_context(|| format!("failed to parse deployment json at {}", path.display()))?;

    let rpc_url = if let Some(rpc) = rpc_override {
        rpc
    } else if let Some(env_var) = raw.rpc_env_var.clone() {
        env::var(&env_var).unwrap_or(raw.rpc.clone())
    } else {
        raw.rpc.clone()
    };

    let open_sub = parse_addr(&raw.open_sub).context("invalid openSub address")?;
    let token = parse_addr(&raw.token).context("invalid token address")?;

    Ok(Deployment {
        chain_id: raw.chain_id,
        rpc_url,
        open_sub,
        token,
        decimals: raw.decimals,
        plan_id: ethers::types::U256::from(raw.plan_id),
        start_block: raw.start_block,
    })
}

fn parse_addr(s: &str) -> Result<ethers::types::Address> {
    s.parse::<ethers::types::Address>()
        .map_err(|e| anyhow!("{e}"))
}
