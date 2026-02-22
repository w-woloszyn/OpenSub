"use client";

import { useAccount, useChainId, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { chainForKey, type ChainKey } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { AA_ONLY_DEMO } from "@/lib/constants";

export function Nav() {
  const [selected, setSelected] = useSelectedChain();
  const selectedChain = chainForKey(selected);

  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { connect, connectors, isPending: isConnecting } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const mismatch = isConnected && chainId !== selectedChain.id;

  return (
    <div style={{ marginBottom: 20 }} className="card">
      <div className="row" style={{ alignItems: "center", justifyContent: "space-between" }}>
        <div className="row" style={{ alignItems: "center" }}>
          <strong>OpenSub Demo</strong>
          <span className="muted">(minimal UI, full functionality)</span>
        </div>

        <div className="row" style={{ alignItems: "center" }}>
          <label className="muted" htmlFor="chain">
            Chain
          </label>
          {AA_ONLY_DEMO ? (
            <span className="badge">Base Sepolia (AA-only)</span>
          ) : (
            <select
              id="chain"
              className="input"
              value={selected}
              onChange={(e) => setSelected(e.target.value as ChainKey)}
            >
              <option value="baseTestnet">Base Sepolia</option>
              <option value="local">Local Anvil</option>
            </select>
          )}

          {!AA_ONLY_DEMO && (isConnected ? (
            <>
              <span className="badge">{address?.slice(0, 6)}…{address?.slice(-4)}</span>
              {mismatch ? (
                <button
                  className="btn btnPrimary"
                  disabled={isSwitching}
                  onClick={() => switchChain({ chainId: selectedChain.id })}
                  title="Switch your wallet to the selected chain"
                >
                  {isSwitching ? "Switching…" : "Switch chain"}
                </button>
              ) : (
                <span className="badge">chainId {chainId}</span>
              )}

              <button className="btn" onClick={() => disconnect()}>
                Disconnect
              </button>
            </>
          ) : (
            <button
              className="btn btnPrimary"
              disabled={isConnecting || connectors.length === 0}
              onClick={() => connect({ connector: connectors[0] })}
              title="Connect an injected wallet (MetaMask, Coinbase Wallet extension, etc.)"
            >
              {isConnecting ? "Connecting…" : "Connect wallet"}
            </button>
          ))}
        </div>
      </div>

      {mismatch && !AA_ONLY_DEMO && (
        <p className="muted" style={{ marginTop: 10 }}>
          Your wallet is on <code>{chainId}</code> but the UI is set to <code>{selectedChain.id}</code>. Click
          <b> Switch chain</b>.
        </p>
      )}

      
    </div>
  );
}
