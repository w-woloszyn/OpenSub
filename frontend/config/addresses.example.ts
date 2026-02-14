/**
 * Example addresses/config.
 * Rename to addresses.ts and fill in.
 */

export const addresses = {
  local: {
    chainName: "anvil",
    openSub: "0x0000000000000000000000000000000000000000",
    // Start block for event log scanning. Safe to set earlier than the true deploy block.
    deployBlock: 0n,
  },
  baseTestnet: {
    chainName: "base-sepolia (or chosen Base testnet)",
    openSub: "0x0000000000000000000000000000000000000000",
    // Start block for event log scanning. Safe to set earlier than the true deploy block.
    deployBlock: 0n,
  },
} as const;
