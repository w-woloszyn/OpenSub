"use client";

import { addresses } from "@/config/addresses";
import { tokens } from "@/config/tokens";
import { chainForKey, isConfiguredAddress, openSubAddress, type ChainKey } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { AA_ONLY_DEMO } from "@/lib/constants";
import { GaslessContent } from "@/app/gasless/GaslessContent";

export default function HomePage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);

  const cfg = addresses[chainKey];
  const token = tokens[chainKey][0];
  const configured = isConfiguredAddress(openSubAddress(chainKey));

  if (AA_ONLY_DEMO) {
    return (
      <main className="row" style={{ flexDirection: "column", gap: 16 }}>
        <div className="card">
          <h2 style={{ marginTop: 0 }}>AA-only demo (gasless subscriptions)</h2>
          <p className="muted" style={{ marginTop: 6 }}>
            This UI is in <b>AA-only mode</b>. No wallet is needed. You will generate a local AA owner key and create a
            sponsored subscription on Base Sepolia.
          </p>
        </div>
        <GaslessContent />
      </main>
    );
  }

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

      <div className="card">
        <h3 style={{ marginTop: 0 }}>How to demo (wallet-based, real payment flow)</h3>
        <ol className="muted" style={{ marginTop: 6 }}>
          <li>Connect a wallet and switch it to Base Sepolia.</li>
          <li>Go to <b>Subscriber</b>, set planId = 1.</li>
          <li>Mint demo tokens (mUSDC) to your wallet, then click <b>Approve</b>.</li>
          <li>Click <b>Subscribe</b> (first charge happens immediately).</li>
          <li>Wait until due, then click <b>Renew (collect)</b> or use the <b>Collector</b> page.</li>
        </ol>
        <p className="muted" style={{ marginBottom: 0 }}>
          You will pay gas (ETH) for wallet-based actions. The token used here is a testnet MockERC20.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Gasless demo (AA)</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          The <b>Gasless (AA)</b> page uses a smart account and a paymaster to sponsor gas.
          It still pays the subscription in tokens — but those tokens are minted to the smart account in the same
          UserOperation for demo convenience.
        </p>
        <p className="muted" style={{ marginBottom: 0 }}>
          This is a demo UX, not production security. See the warning banner on the Gasless page.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Glossary (plain English)</h3>
        <ul className="muted">
          <li>
            <b>Plan</b> = price + interval + token + collector fee. Merchants create plans.
          </li>
          <li>
            <b>Subscription</b> = your active plan membership (has <code>paidThrough</code> timestamp).
          </li>
          <li>
            <b>Approve</b> = allow OpenSub to pull tokens for future charges.
          </li>
          <li>
            <b>Collect / Renew</b> = charge the next period when a subscription is due.
          </li>
          <li>
            <b>isDue</b> = the subscription has expired and needs collect to continue.
          </li>
        </ul>
      </div>
    </main>
  );
}
