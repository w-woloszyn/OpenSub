import type { PublicClient } from "viem";
import type { AbiEvent } from "viem";

// Chunked log scanning helper.
//
// Why this exists:
// - Public RPCs often reject large eth_getLogs ranges.
// - Even paid RPCs may have maximum block ranges.
// - This makes the UI reliable on Base Sepolia.

export async function getLogsChunked(params: {
  client: PublicClient;
  address: `0x${string}`;
  events: readonly AbiEvent[];
  fromBlock: bigint;
  toBlock: bigint;
  chunkSize: bigint;
  onProgress?: (p: { currentFrom: bigint; currentTo: bigint; done: bigint; total: bigint }) => void;
}) {
  const { client, address, events } = params;
  let { fromBlock, toBlock, chunkSize } = params;

  if (toBlock < fromBlock) {
    return [];
  }

  const total = toBlock - fromBlock + 1n;
  let done = 0n;
  const out: any[] = [];

  let cursor = fromBlock;
  while (cursor <= toBlock) {
    let end = cursor + chunkSize - 1n;
    if (end > toBlock) end = toBlock;

    try {
      const logs = await client.getLogs({
        address,
        events,
        fromBlock: cursor,
        toBlock: end,
      });
      out.push(...logs);

      done += end - cursor + 1n;
      params.onProgress?.({ currentFrom: cursor, currentTo: end, done, total });

      cursor = end + 1n;
      // restore chunk size after a successful call (if we had to shrink earlier)
      chunkSize = params.chunkSize;
    } catch (e: any) {
      // If a provider rejects the range, shrink the chunk and retry.
      if (chunkSize > 10n) {
        chunkSize = chunkSize / 2n;
        if (chunkSize < 10n) chunkSize = 10n;
        continue;
      }
      // Re-throw after we can't reasonably shrink further.
      throw new Error(
        `getLogs failed for range [${cursor}, ${end}] (chunkSize=${chunkSize}): ${e?.message ?? String(e)}`
      );
    }
  }

  return out;
}
