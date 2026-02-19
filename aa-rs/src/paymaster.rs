use crate::encoding;
use anyhow::{anyhow, Context, Result};
use ethers::types::{Address, Bytes, U256};
use serde_json::Value;

/// Minimal ERC-7677 paymaster web service client.
///
/// Milestone 6B uses this with Alchemy Gas Manager on Base Sepolia.
///
/// We intentionally implement the ERC-7677 methods (`pm_getPaymasterStubData` and
/// `pm_getPaymasterData`) so the CLI remains vendor-portable.
#[derive(Debug, Clone)]
pub struct PaymasterClient {
    url: String,
    http: reqwest::Client,
}

impl PaymasterClient {
    pub fn new(url: String) -> Self {
        Self {
            url,
            http: reqwest::Client::new(),
        }
    }

    pub async fn get_paymaster_stub_data(
        &self,
        user_op: Value,
        entrypoint: Address,
        chain_id: u64,
        policy_id: &str,
        webhook_data: Option<&str>,
    ) -> Result<Bytes> {
        let params = build_params(user_op, entrypoint, chain_id, policy_id, webhook_data);
        let res = self
            .rpc("pm_getPaymasterStubData", params)
            .await
            .context("pm_getPaymasterStubData RPC failed")?;
        parse_v06_paymaster_and_data(&res)
    }

    pub async fn get_paymaster_data(
        &self,
        user_op: Value,
        entrypoint: Address,
        chain_id: u64,
        policy_id: &str,
        webhook_data: Option<&str>,
    ) -> Result<Bytes> {
        let params = build_params(user_op, entrypoint, chain_id, policy_id, webhook_data);
        let res = self
            .rpc("pm_getPaymasterData", params)
            .await
            .context("pm_getPaymasterData RPC failed")?;
        parse_v06_paymaster_and_data(&res)
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

fn build_params(
    user_op: Value,
    entrypoint: Address,
    chain_id: u64,
    policy_id: &str,
    webhook_data: Option<&str>,
) -> Value {
    let mut ctx = serde_json::json!({
        "policyId": policy_id,
    });

    if let Some(wd) = webhook_data {
        // context is free-form; Alchemy Gas Manager expects `webhookData`.
        if let Some(obj) = ctx.as_object_mut() {
            obj.insert("webhookData".to_string(), Value::String(wd.to_string()));
        }
    }

    serde_json::json!([
        user_op,
        encoding::fmt_address(entrypoint),
        encoding::fmt_u256(U256::from(chain_id)),
        ctx
    ])
}

fn parse_v06_paymaster_and_data(result: &Value) -> Result<Bytes> {
    // ERC-7677 examples return v0.6 data at the top level:
    //   { "paymasterAndData": "0x..." }
    // Alchemy currently returns a wrapped object:
    //   { "entrypointV06Response": { "paymasterAndData": "0x..." }, "entrypointV07Response": { ... } }
    // Be liberal in what we accept so the CLI stays vendor-portable.

    // 1) Spec-style: top-level paymasterAndData
    if let Some(s) = result.get("paymasterAndData").and_then(|x| x.as_str()) {
        let hex_str = s.strip_prefix("0x").unwrap_or(s);
        let bytes = hex::decode(hex_str).context("invalid hex in paymasterAndData")?;
        return Ok(Bytes::from(bytes));
    }

    // 2) Alchemy-style: nested entrypointV06Response.paymasterAndData
    let v06 = result
        .get("entrypointV06Response")
        .or_else(|| result.get("entryPointV06Response"))
        .ok_or_else(|| {
            anyhow!(
                "missing paymasterAndData (expected top-level paymasterAndData or entrypointV06Response.paymasterAndData)"
            )
        })?;

    let s = v06
        .get("paymasterAndData")
        .and_then(|x| x.as_str())
        .ok_or_else(|| anyhow!("missing paymasterAndData field"))?;

    let hex_str = s.strip_prefix("0x").unwrap_or(s);
    let bytes = hex::decode(hex_str).context("invalid hex in paymasterAndData")?;
    Ok(Bytes::from(bytes))
}

#[cfg(test)]
mod tests {
    use super::parse_v06_paymaster_and_data;
    use ethers::types::Bytes;
    use serde_json::json;

    const PM_DATA: &str = "0xdeadbeef";

    fn expected_bytes() -> Bytes {
        Bytes::from(vec![0xde, 0xad, 0xbe, 0xef])
    }

    #[test]
    fn parse_paymaster_and_data_top_level() {
        let res = json!({ "paymasterAndData": PM_DATA });
        let out = parse_v06_paymaster_and_data(&res).unwrap();
        assert_eq!(out, expected_bytes());
    }

    #[test]
    fn parse_paymaster_and_data_nested_entrypoint_v06() {
        let res = json!({ "entrypointV06Response": { "paymasterAndData": PM_DATA } });
        let out = parse_v06_paymaster_and_data(&res).unwrap();
        assert_eq!(out, expected_bytes());
    }

    #[test]
    fn parse_paymaster_and_data_nested_entry_point_v06() {
        let res = json!({ "entryPointV06Response": { "paymasterAndData": PM_DATA } });
        let out = parse_v06_paymaster_and_data(&res).unwrap();
        assert_eq!(out, expected_bytes());
    }

    #[test]
    fn parse_paymaster_and_data_missing_fields() {
        let res = json!({ "entrypointV07Response": { "paymasterAndData": PM_DATA } });
        assert!(parse_v06_paymaster_and_data(&res).is_err());
    }
}
