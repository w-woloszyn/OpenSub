use ethers::types::{Address, Bytes, U256};

/// ERC-4337 UserOperation (EntryPoint v0.6 layout).
///
/// Note: EntryPoint v0.7 uses a *different* packed struct layout.
///
/// Milestone 6A uses no paymaster (so `paymaster_and_data` is empty).
/// Milestone 6B optionally populates `paymaster_and_data` via an ERC-7677 paymaster web service.
#[derive(Clone, Debug)]
pub struct UserOperation {
    pub sender: Address,
    pub nonce: U256,
    pub init_code: Bytes,
    pub call_data: Bytes,
    pub call_gas_limit: U256,
    pub verification_gas_limit: U256,
    pub pre_verification_gas: U256,
    pub max_fee_per_gas: U256,
    pub max_priority_fee_per_gas: U256,
    pub paymaster_and_data: Bytes,
    pub signature: Bytes,
}

impl UserOperation {
    /// Returns a tuple matching the Solidity struct layout, suitable for
    /// calling `EntryPoint.getUserOpHash((...))`.
    pub fn as_abi_tuple(
        &self,
    ) -> (
        Address,
        U256,
        Bytes,
        Bytes,
        U256,
        U256,
        U256,
        U256,
        U256,
        Bytes,
        Bytes,
    ) {
        (
            self.sender,
            self.nonce,
            self.init_code.clone(),
            self.call_data.clone(),
            self.call_gas_limit,
            self.verification_gas_limit,
            self.pre_verification_gas,
            self.max_fee_per_gas,
            self.max_priority_fee_per_gas,
            self.paymaster_and_data.clone(),
            self.signature.clone(),
        )
    }
}
