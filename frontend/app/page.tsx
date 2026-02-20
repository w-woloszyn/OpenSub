"use client";

import { addresses } from "@/config/addresses";
import { tokens } from "@/config/tokens";
import { chainForKey, isConfiguredAddress, openSubAddress, type ChainKey } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";

export default function HomePage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);

  const cfg = addresses[chainKey];
  const token = tokens[chainKey][0];
  const configured = isConfiguredAddress(openSubAddress(chainKey));

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>What this demo is</h2>
        <p className="muted">
          Minimal UI that demonstrates <b>full OpenSub functionality</b> (plans, subscribe, renew, cancel/resume,
          manual collect) on <b>Local Anvil</b> and <b>Base Sepolia</b>.
        </p>
        <p className="muted" style={{ marginBottom: 0 }}>
          This is intentionally &ldquo;unsexy&rdquo;. It’s meant to be easy for a non-blockchain frontend developer to
          modify.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Current chain selection</h3>
        <div className="row">
          <div>
            <div className="muted">UI chain</div>
            <div>
              <b>{cfg.chainName}</b> (chainId {chain.id})
            </div>
          </div>
          <div>
            <div className="muted">OpenSub</div>
            <div>
              <code>{cfg.openSub}</code>
            </div>
          </div>
          <div>
            <div className="muted">Token</div>
            <div>
              <code>{token.address}</code> ({token.symbol}, {token.decimals} decimals)
            </div>
          </div>
          <div>
            <div className="muted">Log start block</div>
            <div>
              <code>{cfg.deployBlock.toString()}</code>
            </div>
          </div>
        </div>

        {!configured && chainKey === "local" && (
          <p className="muted" style={{ marginTop: 12 }}>
            Local Anvil config is not set yet. Run <code>make demo-local</code> from the repo root, then paste the
            printed OpenSub/token addresses into <code>frontend/config/addresses.ts</code> and
            <code>frontend/config/tokens.ts</code>.
          </p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Fast setup checklist</h3>
        <ol className="muted" style={{ marginTop: 6 }}>
          <li>
            Install deps: <code>cd frontend &amp;&amp; npm i</code>
          </li>
          <li>
            Copy env: <code>cp env.example .env.local</code> (optional, mostly for Gasless page)
          </li>
          <li>
            Start UI: <code>npm run dev</code>
          </li>
          <li>
            For local E2E demo: run <code>make demo-local</code> in another terminal (repo root).
          </li>
        </ol>
      </div>
    </main>
  );
}
