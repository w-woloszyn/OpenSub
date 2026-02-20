"use client";

import { useEffect, useState } from "react";
import type { ChainKey } from "@/lib/demoChains";

const STORAGE_KEY = "opensub.demo.chain";

export function useSelectedChain(): [ChainKey, (k: ChainKey) => void] {
  const [chainKey, setChainKey] = useState<ChainKey>("baseTestnet");

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (raw === "local" || raw === "baseTestnet") {
        setChainKey(raw);
      }
    } catch {
      // ignore
    }
  }, []);

  const set = (k: ChainKey) => {
    setChainKey(k);
    try {
      window.localStorage.setItem(STORAGE_KEY, k);
    } catch {
      // ignore
    }
  };

  return [chainKey, set];
}
