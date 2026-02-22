import { http, createConfig } from "wagmi";
import { injected } from "@wagmi/core";
import { anvil, baseSepolia } from "wagmi/chains";

// NOTE: This is a demo app. We keep configuration explicit and minimal.
// - Injected connector = MetaMask / Coinbase Wallet extension / etc.
// - transports provide the RPC URL for reads.

const anvilRpc =
  process.env.NEXT_PUBLIC_ANVIL_RPC_URL ?? "http://127.0.0.1:8545";
const baseSepoliaRpc =
  process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL ?? "https://sepolia.base.org";

export const wagmiConfig = createConfig({
  chains: [anvil, baseSepolia],
  connectors: [injected()],
  transports: {
    [anvil.id]: http(anvilRpc),
    [baseSepolia.id]: http(baseSepoliaRpc),
  },
  ssr: true,
});
