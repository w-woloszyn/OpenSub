# Log Scanning Notes (Milestone 4)

Milestone 4 intentionally avoids a backend indexer. That means the UI must query on-chain events via `eth_getLogs`.

On L2s and public RPC providers, `eth_getLogs` often has **range limits** (e.g., a maximum number of blocks per query) or can time out if you request too large of a block window.

This doc provides the recommended approach for a reliable demo on:
- Local Anvil
- Base testnet (Base Sepolia recommended)

## Inputs
The frontend needs:
- `openSub` contract address
- a **start block** for scanning (`deployBlock` in config)

**Important:** `deployBlock` is a *start block*, not necessarily the exact deployment block. It is safe to set it slightly earlier than the true deployment block.

## Recommended strategy

### 1) Always scan in chunks
Instead of scanning from `deployBlock` to `latest` in one call, scan in **fixed-size ranges**:

- Choose an initial `chunkSize` (start with **20,000** blocks)
- For each chunk:
  - `from = start + i * chunkSize`
  - `to = min(from + chunkSize - 1, latest)`
  - call `getLogs({ fromBlock: from, toBlock: to, ... })`

If the RPC errors, **reduce** `chunkSize` and retry.

### 2) Cache results
For the demo app:
- Cache fetched logs in memory (React state)
- Optionally persist to `localStorage` keyed by:
  - chainId
  - openSub address
  - event signature
  - filter args (merchant/subscriber/planId)

### 3) Use indexed topics for filtering
Prefer filtering by indexed event params to reduce RPC load:

- `PlanCreated(planId indexed, merchant indexed, token indexed, ...)`
- `Subscribed(subscriptionId indexed, planId indexed, subscriber indexed, ...)`
- `Charged(subscriptionId indexed, planId indexed, subscriber indexed, ...)`

## Example chunked scanner (viem)

Below is a small pattern your frontend dev can copy.

```ts
import type { PublicClient } from "viem";
import { parseAbiItem } from "viem";

const subscribedEvent = parseAbiItem(
  "event Subscribed(uint256 indexed subscriptionId, uint256 indexed planId, address indexed subscriber, uint40 startTime, uint40 paidThrough)"
);

export async function getSubscribedLogsChunked(params: {
  client: PublicClient;
  openSub: `0x${string}`;
  subscriber: `0x${string}`;
  fromBlock: bigint;
  toBlock: bigint;
  chunkSize?: bigint;
}) {
  const { client, openSub, subscriber } = params;
  let from = params.fromBlock;
  const end = params.toBlock;
  let step = params.chunkSize ?? 20_000n;

  const out: any[] = [];

  while (from <= end) {
    let to = from + step - 1n;
    if (to > end) to = end;

    try {
      const logs = await client.getLogs({
        address: openSub,
        event: subscribedEvent,
        args: { subscriber },
        fromBlock: from,
        toBlock: to,
      });
      out.push(...logs);
      from = to + 1n;

      // Optional: slowly increase step again after success
      if (step < 50_000n) step += 5_000n;
    } catch (e) {
      // Back off on failures
      if (step <= 1_000n) throw e;
      step = step / 2n;
    }
  }

  return out;
}
```

## What to do if a public RPC is flaky
If your frontend dev hits repeated errors, the easiest fixes are:

- Use a reputable RPC provider (Alchemy/Infura/QuickNode/etc.)
- Reduce `chunkSize`
- Increase retries / add a short delay

For Milestone 4, a lightweight indexer is **not required**, but it becomes attractive for Milestone 5+.
