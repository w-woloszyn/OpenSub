/**
 * Example token list per chain.
 * For Milestone 4, we recommend deploying MockERC20 as "MockUSDC" (6 decimals) on:
 * - Local Anvil
 * - Base testnet
 */
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
      address: "0x0000000000000000000000000000000000000000",
      decimals: 6,
    },
  ],
} as const;
