// Token lists per chain.
//
// For the demo, we use MockERC20 as mUSDC (6 decimals).
// Base Sepolia values are pre-filled from deployments/base-sepolia.json.

export const tokens = {
  local: [
    {
      symbol: "mUSDC",
      name: "Mock USD Coin",
      address: "0x0000000000000000000000000000000000000000",
      decimals: 6,
    },
  ],
  baseTestnet: [
    {
      symbol: "mUSDC",
      name: "Mock USD Coin",
      address: "0x310fE8788dCa65134bC750AF9080138B1fD4F2e1",
      decimals: 6,
    },
  ],
} as const;
