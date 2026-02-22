export default function DevNotesPage() {
  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Dev notes (for non-blockchain frontend devs)</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          This page is intentionally verbose and practical. It’s here so a frontend engineer can work without having to
          read Solidity.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Where things are</h3>
        <ul className="muted">
          <li>
            Contract ABIs: <code>frontend/abi/*.ts</code>
          </li>
          <li>
            Addresses per chain: <code>frontend/config/addresses.ts</code>
          </li>
          <li>
            Token list per chain: <code>frontend/config/tokens.ts</code>
          </li>
          <li>
            UI state machine: <code>docs/UI_STATE_MACHINE.md</code>
          </li>
          <li>
            Allowance policy (why we approve price×N): <code>docs/ALLOWANCE_POLICY.md</code>
          </li>
          <li>
            Base Sepolia deployment: <code>deployments/base-sepolia.json</code>
          </li>
        </ul>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Subscription semantics (the only 3 things to remember)</h3>
        <ol className="muted">
          <li>
            <b>Subscribe charges immediately</b> for the first period.
          </li>
          <li>
            If a subscription is <b>Active</b> but expired (<code>now ≥ paidThrough</code>), you must call
            <b> collect()</b> to renew. <b>Resubscribe is intentionally blocked</b> and will revert
            <code>AlreadySubscribed</code>.
          </li>
          <li>
            Pattern A cancellation = <code>cancel(subId, true)</code> → NonRenewing. Access remains until
            <code>paidThrough</code>, then it naturally expires (no cleanup tx required).
          </li>
        </ol>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Local demo (recommended dev loop)</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          In repo root:
        </p>
        <pre>
          <code>{`make demo-local

# demo-local prints OpenSub/Token/PlanId/StartBlock
# paste those into frontend/config/addresses.ts and frontend/config/tokens.ts
`}</code>
        </pre>
        <p className="muted" style={{ marginBottom: 0 }}>
          Then in another terminal:
        </p>
        <pre>
          <code>{`cd frontend
npm i
npm run dev
`}</code>
        </pre>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Gasless demo</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          The <b>Gasless (AA)</b> page calls the Rust CLI on the server side. If it errors, it’s usually one of:
        </p>
        <ul className="muted">
          <li>
            missing env vars in <code>frontend/.env.local</code> (see <code>frontend/env.example</code>)
          </li>
          <li>
            AA binary not built (<code>cargo build --release --manifest-path aa-rs/Cargo.toml</code>)
          </li>
          <li>
            Gas Manager policy too restrictive (e.g. doesn’t allow <code>mint</code> selector)
          </li>
        </ul>
        <p className="muted" style={{ marginTop: 10 }}>
          Demo security: the gasless page stores an AA owner key in <code>localStorage</code>. This is not production
          safe — it’s just to keep the demo frictionless.
        </p>
      </div>
    </main>
  );
}
