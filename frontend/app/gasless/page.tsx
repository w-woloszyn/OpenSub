"use client";

import { useState } from "react";
import { useSelectedChain } from "@/lib/selectedChain";

export default function GaslessPage() {
  const [chainKey] = useSelectedChain();

  const [salt, setSalt] = useState<string>("0");
  const [periods, setPeriods] = useState<string>("12");
  const [mint, setMint] = useState<string>("10000000");

  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [resp, setResp] = useState<any>(null);

  async function run() {
    setBusy(true);
    setErrMsg("");
    setResp(null);
    try {
      const r = await fetch("/api/gasless-subscribe", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          salt: Number(salt),
          allowancePeriods: Number(periods),
          mintAmountRaw: mint,
        }),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) {
        throw new Error(j.error ?? `Request failed (${r.status})`);
      }
      setResp(j);
    } catch (e: any) {
      setErrMsg(e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Gasless subscribe (AA) — demo mode</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          This page is a <b>demo convenience</b>: it calls the Rust AA CLI (<code>aa-rs/opensub-aa</code>) from a
          Next.js API route, which:
        </p>
        <ol className="muted" style={{ marginTop: 6 }}>
          <li>Generates a fresh owner key locally (saved under repo <code>.secrets/</code>, never printed),</li>
          <li>Creates a sponsored ERC-4337 UserOperation (Alchemy Gas Manager, Base Sepolia),</li>
          <li>Mints demo tokens + approves + subscribes inside the UserOp,</li>
          <li>Returns the new owner/smartAccount + on-chain subscription id.</li>
        </ol>
        <p className="muted" style={{ marginBottom: 0 }}>
          ⚠️ Not production architecture. It’s just a one-click demo so non-blockchain frontend devs don’t need to
          learn ERC-4337 before they can ship UI.
        </p>
      </div>

      {chainKey !== "baseTestnet" && (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Gasless demo is only wired for <b>Base Sepolia</b>. Switch chain in the top nav.
          </p>
        </div>
      )}

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Run gasless subscribe</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          Prereqs:
          <br />
          1) <code>cargo build --release --manifest-path aa-rs/Cargo.toml</code>
          <br />
          2) set env vars in <code>frontend/.env.local</code> (copy from <code>frontend/env.example</code>)
        </p>
        <div className="row">
          <div>
            <div className="muted">salt</div>
            <input className="input" value={salt} onChange={(e) => setSalt(e.target.value)} />
          </div>
          <div>
            <div className="muted">allowance periods</div>
            <input className="input" value={periods} onChange={(e) => setPeriods(e.target.value)} />
          </div>
          <div>
            <div className="muted">mint (raw units)</div>
            <input className="input" value={mint} onChange={(e) => setMint(e.target.value)} />
          </div>
        </div>
        <div className="row" style={{ marginTop: 14 }}>
          <button className="btn btnPrimary" disabled={busy || chainKey !== "baseTestnet"} onClick={run}>
            {busy ? "Running…" : "Run sponsored subscribe"}
          </button>
        </div>
        {errMsg && (
          <p style={{ marginTop: 10 }}>
            <b>Error:</b> <span className="muted">{errMsg}</span>
          </p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Result</h3>
        {!resp ? (
          <p className="muted">No result yet.</p>
        ) : (
          <>
            <pre style={{ whiteSpace: "pre-wrap" }}>{JSON.stringify(resp.result, null, 2)}</pre>
            <details>
              <summary>CLI logs (stderr)</summary>
              <pre style={{ whiteSpace: "pre-wrap" }}>{resp.logs}</pre>
            </details>
          </>
        )}
      </div>
    </main>
  );
}
