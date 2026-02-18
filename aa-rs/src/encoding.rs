use crate::types::UserOperation;
use ethers::types::{Address, Bytes, H256, U256};

pub fn fmt_address(addr: Address) -> String {
    format!("0x{}", hex::encode(addr.as_bytes()))
}

pub fn fmt_h256(h: H256) -> String {
    format!("0x{}", hex::encode(h.as_bytes()))
}

/// JSON-RPC "quantity" encoding.
pub fn fmt_u256(v: U256) -> String {
    if v.is_zero() {
        "0x0".to_string()
    } else {
        format!("0x{:x}", v)
    }
}

pub fn fmt_bytes(b: &Bytes) -> String {
    format!("0x{}", hex::encode(b.as_ref()))
}

pub fn user_op_to_json(op: &UserOperation) -> serde_json::Value {
    serde_json::json!({
        "sender": fmt_address(op.sender),
        "nonce": fmt_u256(op.nonce),
        "initCode": fmt_bytes(&op.init_code),
        "callData": fmt_bytes(&op.call_data),
        "callGasLimit": fmt_u256(op.call_gas_limit),
        "verificationGasLimit": fmt_u256(op.verification_gas_limit),
        "preVerificationGas": fmt_u256(op.pre_verification_gas),
        "maxFeePerGas": fmt_u256(op.max_fee_per_gas),
        "maxPriorityFeePerGas": fmt_u256(op.max_priority_fee_per_gas),
        "paymasterAndData": fmt_bytes(&op.paymaster_and_data),
        "signature": fmt_bytes(&op.signature),
    })
}

pub fn parse_u256_quantity(s: &str) -> anyhow::Result<U256> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    if s.is_empty() {
        return Ok(U256::zero());
    }
    Ok(U256::from_str_radix(s, 16)?)
}

pub fn parse_h256(s: &str) -> anyhow::Result<H256> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    let bytes = hex::decode(s)?;
    if bytes.len() != 32 {
        anyhow::bail!("expected 32-byte hex, got {} bytes", bytes.len());
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(H256(arr))
}
