use ethers::contract::abigen;

// Minimal ABI for the keeper bot.
//
// Note: we intentionally declare the `uint40` / `uint16` return values as `uint256` in the binding
// to keep decoding simple and avoid edge cases. ABI encoding is still 32-byte words, so decoding as
// uint256 is safe.
abigen!(
    OpenSub,
    r#"[
        function isDue(uint256 subscriptionId) view returns (bool)
        function collect(uint256 subscriptionId) returns (uint256 merchantAmount, uint256 collectorFee)

        function subscriptions(uint256) view returns (
            uint256 planId,
            address subscriber,
            uint8 status,
            uint256 startTime,
            uint256 paidThrough,
            uint256 lastChargedAt
        )

        // Auto-generated getter for `mapping(uint256 => Plan) public plans;`
        function plans(uint256) view returns (
            address merchant,
            address token,
            uint256 price,
            uint256 interval,
            uint256 collectorFeeBps,
            bool active,
            uint256 createdAt
        )
    ]"#
);
