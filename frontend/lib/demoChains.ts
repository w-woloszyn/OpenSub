import { anvil, baseSepolia } from "wagmi/chains";
import { addresses } from "@/config/addresses";
import { tokens } from "@/config/tokens";

export type ChainKey = keyof typeof addresses;

export function chainForKey(key: ChainKey) {
  switch (key) {
    case "local":
      return anvil;
    case "baseTestnet":
      return baseSepolia;
    default: {
      // Exhaustive check
      const _exhaustive: never = key;
      return _exhaustive;
    }
  }
}

export function openSubAddress(key: ChainKey): `0x${string}` {
  return addresses[key].openSub as `0x${string}`;
}

export function deployBlock(key: ChainKey): bigint {
  return addresses[key].deployBlock;
}

export function defaultToken(key: ChainKey) {
  return tokens[key][0];
}

export function isConfiguredAddress(addr: string) {
  return /^0x[0-9a-fA-F]{40}$/.test(addr) && addr !== "0x0000000000000000000000000000000000000000";
}
