# Base Sepolia Handoff Bundle (OpenSub)

Date: 2026-02-16

## Network
- Chain: Base Sepolia (chainId 84532)
- RPC: https://sepolia.base.org  (rate-limited; set BASE_SEPOLIA_RPC_URL for a dedicated provider)
- Explorer: https://sepolia-explorer.base.org

## Core Addresses
- OpenSub: 0x27eD037baB2A178dCDD600Abb78E3C6165C3B57c
- Token (mUSDC): 0x310fE8788dCa65134bC750AF9080138B1fD4F2e1

## Plan + Subscription
- PlanId: 1
- Plan interval: 300 seconds
- Start block (log scan lower bound): 37718658

## Test Wallets (public addresses only)
- Merchant: 0x82ab8001d335260C2B201aaB1db1a7816B55b6Bb
- Subscriber: 0x49d478b113B87400B8960D749835950e79607d32
- Collector (optional): 0x1cdD59E3025c2526A52E462E96ed123CaD35D964

## Transactions (Base Sepolia)
- Token deploy: 0xeb2e6133b2d65b39c35d0c69db9e638f77a08e46be8b57f347b053b60c02db50
- OpenSub deploy: 0xd360b41fc926be9a55527d7539df3aacc0632313bc7810a40b74c8fa46bba474
- Create plan: 0x329fa9f2fcf7a38e0641a46ef082dc7ffc83e35ec23e630a4f42a138c27bf70e
- Mint merchant: 0xbaf607be842ca9f008844d9fa461b35133aa28cb316aa282276a09f0d6c7ef07
- Mint subscriber: 0xde5a6704d9877beab524e4462b7ff03315f36e8fc0eb34cf28d3d860ac4bb7f2
- Approve: 0xc6de8f7bf1c89f3cd9ba3c6a2c8c18aaf54ffb67169eabc6ff5414878c57a871
- Subscribe: 0x15050b5d91a530c7841e6ab5921e6be3f38d1cddf2426fe770610e23c14c2ff5
- Collect (renewal): 0xa9d81f9e393342b35ff6dc3a6423195069ebfde065d38faacc062c3db2532881

## Frontend Config Snippets
### frontend/config/addresses.ts
```ts
export const addresses = {
  baseTestnet: {
    chainName: "base-sepolia",
    openSub: "0x27eD037baB2A178dCDD600Abb78E3C6165C3B57c",
    deployBlock: 37718658n,
  },
} as const;
```

### frontend/config/tokens.ts
```ts
export const tokens = {
  baseTestnet: [
    {
      symbol: "mUSDC",
      name: "Mock USD Coin",
      address: "0x310fE8788dCa65134bC750AF9080138B1fD4F2e1",
      decimals: 6,
    },
  ],
} as const;
```

## Notes
- Log scans on free-tier RPCs may require 10-block chunking.
- Subscription renewal verified via `collect(1)` after interval elapsed.
