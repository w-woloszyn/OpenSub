use crate::encoding::{parse_h256, parse_u256_quantity};
use anyhow::{anyhow, Context, Result};
use ethers::types::{Address, H256, U256};
use serde_json::Value;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct BundlerClient {
    url: String,
    http: reqwest::Client,
}

#[derive(Debug, Clone)]
pub struct GasEstimates {
    pub call_gas_limit: U256,
    pub verification_gas_limit: U256,
    pub pre_verification_gas: U256,
}

impl BundlerClient {
    pub fn new(url: String) -> Self {
        Self {
            url,
            http: reqwest::Client::new(),
        }
    }

    pub async fn estimate_user_operation_gas(
        &self,
        user_op: Value,
        entrypoint: Address,
    ) -> Result<GasEstimates> {
        let params = serde_json::json!([user_op, fmt_addr(entrypoint)]);
        let res = self
            .rpc("eth_estimateUserOperationGas", params)
            .await
            .context("eth_estimateUserOperationGas failed")?;

        let call_gas_limit = parse_u256_field(&res, "callGasLimit")?;
        let verification_gas_limit = parse_u256_field(&res, "verificationGasLimit")?;
        let pre_verification_gas = parse_u256_field(&res, "preVerificationGas")?;

        Ok(GasEstimates {
            call_gas_limit,
            verification_gas_limit,
            pre_verification_gas,
        })
    }

    pub async fn send_user_operation(&self, user_op: Value, entrypoint: Address) -> Result<H256> {
        let params = serde_json::json!([user_op, fmt_addr(entrypoint)]);
        let res = self
            .rpc("eth_sendUserOperation", params)
            .await
            .context("eth_sendUserOperation failed")?;

        let hash_str = res
            .as_str()
            .ok_or_else(|| anyhow!("expected result string from eth_sendUserOperation"))?;
        parse_h256(hash_str)
    }

    /// Poll for a receipt until timeout.
    pub async fn wait_user_operation_receipt(
        &self,
        user_op_hash: H256,
        timeout: Duration,
    ) -> Result<Value> {
        let start = std::time::Instant::now();
        loop {
            if start.elapsed() > timeout {
                return Err(anyhow!(
                    "timed out waiting for userOp receipt after {:?}",
                    timeout
                ));
            }

            let params = serde_json::json!([crate::encoding::fmt_h256(user_op_hash)]);
            let res = self.rpc("eth_getUserOperationReceipt", params).await;

            match res {
                Ok(v) => {
                    if !v.is_null() {
                        return Ok(v);
                    }
                }
                Err(e) => {
                    // transient errors are common on free-tier bundlers; keep polling
                    tracing::warn!(error = %e, "bundler receipt poll error");
                }
            }

            tokio::time::sleep(Duration::from_millis(1500)).await;
        }
    }

    async fn rpc(&self, method: &str, params: Value) -> Result<Value> {
        let req = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });

        let resp = self
            .http
            .post(&self.url)
            .json(&req)
            .send()
            .await
            .with_context(|| format!("POST {} failed", self.url))?;

        let status = resp.status();
        let body: Value = resp.json().await.context("failed to decode JSON")?;

        if !status.is_success() {
            return Err(anyhow!("HTTP {}: {}", status, body));
        }

        if let Some(err) = body.get("error") {
            return Err(anyhow!("RPC error: {}", err));
        }

        body.get("result")
            .cloned()
            .ok_or_else(|| anyhow!("missing result field"))
    }
}

fn fmt_addr(a: Address) -> String {
    format!("0x{}", hex::encode(a.as_bytes()))
}

fn parse_u256_field(v: &Value, key: &str) -> Result<U256> {
    let s = v
        .get(key)
        .and_then(|x| x.as_str())
        .ok_or_else(|| anyhow!("missing or invalid field {key}"))?;
    parse_u256_quantity(s)
}
