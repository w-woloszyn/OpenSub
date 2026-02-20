import { formatUnits } from "viem";

export function shortAddr(addr?: string) {
  if (!addr) return "-";
  if (addr.length < 10) return addr;
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function fmtUnits(amount: bigint | undefined, decimals: number) {
  if (amount === undefined) return "-";
  try {
    return formatUnits(amount, decimals);
  } catch {
    return amount.toString();
  }
}

export function fmtTs(ts: bigint | undefined) {
  if (ts === undefined) return "-";
  const n = Number(ts);
  if (!Number.isFinite(n)) return ts.toString();
  // uint40 fits safely in JS number
  return new Date(n * 1000).toLocaleString();
}

export function nowSec(): bigint {
  return BigInt(Math.floor(Date.now() / 1000));
}
