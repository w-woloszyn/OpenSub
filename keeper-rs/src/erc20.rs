use ethers::contract::abigen;

// Minimal ERC20 ABI for keeper-side prechecks.
//
// We only need reads to avoid wasting gas on collect() calls that would revert
// due to insufficient allowance/balance.
abigen!(
    Erc20,
    r#"[
        function allowance(address owner, address spender) view returns (uint256)
        function balanceOf(address owner) view returns (uint256)
    ]"#
);
