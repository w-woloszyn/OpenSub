"use client";

import { useMemo, useState } from "react";
import { usePublicClient } from "wagmi";

import { chainForKey, deployBlock, isConfiguredAddress, openSubAddress } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { OpenSubEventList } from "@/lib/openSubEvents";
import { getLogsChunked } from "@/lib/logScan";

function stringify(obj: any) {
  return JSON.stringify(
    obj,
    (_k, v) => (typeof v === "bigint" ? v.toString() : v),
    2
  );
}

export default function EventsPage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);
  const openSub = openSubAddress(chainKey);
  const configured = isConfiguredAddress(openSub);
  const startBlockDefault = deployBlock(chainKey);

  const publicClient = usePublicClient({ chainId: chain.id });

  const [fromBlock, setFromBlock] = useState<string>(startBlockDefault.toString());
  const [toBlock, setToBlock] = useState<string>("latest");
  const [chunk, setChunk] = useState<string>(chainKey === "baseTestnet" ? "500" : "2000");

  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [progress, setProgress] = useState<string>("");
  const [logs, setLogs] = useState<any[]>([]);

  const fromBlockBig = useMemo(() => {
    try {
      return BigInt(fromBlock);
    } catch {
      return startBlockDefault;
    }
  }, [fromBlock, startBlockDefault]);

  async function scan() {
    if (!publicClient) {
      setErrMsg("No public client available.");
      return;
    }
    setBusy(true);
    setErrMsg("");
    setProgress("");
    setLogs([]);

    try {
      const latest = await publicClient.getBlockNumber();
      const to = toBlock === "latest" ? latest : BigInt(toBlock);
      const chunkSize = BigInt(chunk);

      const fetched = await getLogsChunked({
        client: publicClient,
        address: openSub,
        events: OpenSubEventList,
        fromBlock: fromBlockBig,
        toBlock: to,
        chunkSize,
        onProgress: ({ currentFrom, currentTo, done, total }) => {
          setProgress(
            `Scanning blocks ${currentFrom} → ${currentTo} (${done}/${total})`
          );
        },
      });

      const sorted = [...fetched].sort((a, b) => {
        const ab = a.blockNumber ?? 0n;
        const bb = b.blockNumber ?? 0n;
        if (ab === bb) return 0;
        return ab < bb ? -1 : 1;
      });

      setLogs(sorted);
      setProgress(`Done. Found ${sorted.length} logs.`);
    } catch (e: any) {
      setErrMsg(e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!configured) {
    return (
      <main className="card">
        <h2 style={{ marginTop: 0 }}>Events</h2>
        <p className="muted">This chain is not configured yet.</p>
      </main>
    );
  }

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Events (log scanning)</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          This page demonstrates the recommended <b>chunked eth_getLogs</b> pattern for Base Sepolia.
          If an RPC rejects a range, the scanner automatically shrinks the chunk size and retries.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Scan range</h3>
        <div className="row">
          <div>
            <div className="muted">fromBlock</div>
            <input className="input" value={fromBlock} onChange={(e) => setFromBlock(e.target.value)} />
          </div>
          <div>
            <div className="muted">toBlock</div>
            <input className="input" value={toBlock} onChange={(e) => setToBlock(e.target.value)} />
          </div>
          <div>
            <div className="muted">chunk size</div>
            <input className="input" value={chunk} onChange={(e) => setChunk(e.target.value)} />
          </div>
        </div>

        <div className="row" style={{ marginTop: 14 }}>
          <button className="btn" disabled={busy} onClick={() => setFromBlock(startBlockDefault.toString())}>
            Use deploy block
          </button>
          <button
            className="btn"
            disabled={busy || !publicClient}
            onClick={async () => {
              if (!publicClient) return;
              const latest = await publicClient.getBlockNumber();
              const from = latest > 5000n ? latest - 5000n : 0n;
              setFromBlock(from.toString());
              setToBlock("latest");
            }}
          >
            Use last 5000 blocks
          </button>
          <button className="btn btnPrimary" disabled={busy} onClick={scan}>
            {busy ? "Scanning…" : "Scan"}
          </button>
        </div>

        {progress && <p className="muted">{progress}</p>}
        {errMsg && (
          <p>
            <b>Error:</b> <span className="muted">{errMsg}</span>
          </p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Results</h3>
        {logs.length === 0 ? (
          <p className="muted">No logs loaded yet.</p>
        ) : (
          <div style={{ overflowX: "auto" }}>
            <table style={{ borderCollapse: "collapse", width: "100%" }}>
              <thead>
                <tr>
                  <th style={{ textAlign: "left", borderBottom: "1px solid #e5e7eb", padding: "8px" }}>Block</th>
                  <th style={{ textAlign: "left", borderBottom: "1px solid #e5e7eb", padding: "8px" }}>Event</th>
                  <th style={{ textAlign: "left", borderBottom: "1px solid #e5e7eb", padding: "8px" }}>Tx</th>
                  <th style={{ textAlign: "left", borderBottom: "1px solid #e5e7eb", padding: "8px" }}>Args</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((l, i) => (
                  <tr key={`${l.transactionHash ?? ""}-${i}`}>
                    <td style={{ padding: "8px", verticalAlign: "top" }}>
                      <code>{(l.blockNumber ?? 0n).toString()}</code>
                    </td>
                    <td style={{ padding: "8px", verticalAlign: "top" }}>
                      <b>{l.eventName ?? "?"}</b>
                    </td>
                    <td style={{ padding: "8px", verticalAlign: "top" }}>
                      <code>{(l.transactionHash ?? "").slice(0, 10)}…</code>
                    </td>
                    <td style={{ padding: "8px" }}>
                      <pre style={{ margin: 0, whiteSpace: "pre-wrap" }}>{stringify(l.args ?? {})}</pre>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </main>
  );
}
