"use client";

import { useEffect, useState } from "react";
import type { ChainKey } from "@/lib/demoChains";
import { AA_ONLY_DEMO } from "@/lib/constants";

const STORAGE_KEY = "opensub.demo.chain";

export function useSelectedChain(): [ChainKey, (k: ChainKey) => void] {
  const [chainKey, setChainKey] = useState<ChainKey>(
    AA_ONLY_DEMO ? "baseTestnet" : "baseTestnet"
  );

  useEffect(() => {
    if (AA_ONLY_DEMO) {
      setChainKey("baseTestnet");
      return;
    }
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
    if (AA_ONLY_DEMO) return;
    setChainKey(k);
    try {
      window.localStorage.setItem(STORAGE_KEY, k);
    } catch {
      // ignore
    }
  };

  return [chainKey, set];
}
