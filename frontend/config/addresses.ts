// Demo chain configuration for the frontend.
//
// ✅ Base Sepolia is pre-filled from deployments/base-sepolia.json.
// 🛠 Local Anvil values are placeholders: run `make demo-local` and paste the printed addresses here.

export const addresses = {
  local: {
    chainName: "anvil",
    chainId: 31337,
    openSub: "0x0000000000000000000000000000000000000000",
    // Start block for event log scanning.
    deployBlock: 0n,
  },
  baseTestnet: {
    chainName: "base-sepolia",
    chainId: 84532,
    openSub: "0x27eD037baB2A178dCDD600Abb78E3C6165C3B57c",
    // Safe lower bound from deployments/base-sepolia.json
    deployBlock: 37718658n,
  },
} as const;
