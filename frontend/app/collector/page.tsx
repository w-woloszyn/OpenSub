"use client";

import { useMemo, useState } from "react";
import { useAccount, useChainId, usePublicClient, useReadContract, useWriteContract } from "wagmi";

import { openSubAbi } from "@/abi/openSubAbi";
import { tokens } from "@/config/tokens";
import { chainForKey, defaultToken, isConfiguredAddress, openSubAddress } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { fmtTs, fmtUnits } from "@/lib/format";

export default function CollectorPage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);
  const openSub = openSubAddress(chainKey);
  const configured = isConfiguredAddress(openSub);
  const token = defaultToken(chainKey);
  const tokenList = tokens[chainKey];

  const { isConnected } = useAccount();
  const walletChainId = useChainId();
  const mismatch = isConnected && walletChainId !== chain.id;

  const publicClient = usePublicClient({ chainId: chain.id });
  const { writeContractAsync } = useWriteContract();

  const [subId, setSubId] = useState<string>("1");
  const subIdBig = useMemo(() => {
    try {
      return BigInt(subId);
    } catch {
      return 1n;
    }
  }, [subId]);

  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [lastTx, setLastTx] = useState<string>("");

  const sub = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "subscriptions",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const planId = (sub.data?.[0] as bigint | undefined) ?? 0n;

  const plan = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "plans",
    args: [planId],
    chainId: chain.id,
    query: { enabled: configured && planId !== 0n },
  });

  const planTokenAddr = (plan.data?.[1] as string | undefined) ?? token.address;
  const tokenMeta = useMemo(() => {
    const byAddr = tokenList.find((t) => t.address.toLowerCase() === planTokenAddr.toLowerCase());
    return byAddr ?? token;
  }, [planTokenAddr, tokenList, token]);
  const subscriber = (sub.data?.[1] as string | undefined) ?? "";
  const statusNum = (sub.data?.[2] as bigint | undefined) ?? 0n;
  const startTime = (sub.data?.[3] as bigint | undefined) ?? 0n;
  const paidThrough = (sub.data?.[4] as bigint | undefined) ?? 0n;
  const lastChargedAt = (sub.data?.[5] as bigint | undefined) ?? 0n;

  const isDue = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "isDue",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const hasAccess = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "hasAccess",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const collectorFee = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "computeCollectorFee",
    args: [planId],
    chainId: chain.id,
    query: { enabled: configured && planId !== 0n },
  });

  async function runTx(
    label: string,
    args: Parameters<typeof writeContractAsync>[0]
  ) {
    if (!publicClient) {
      setErrMsg("No public client available.");
      return;
    }
    setBusy(true);
    setErrMsg("");
    setLastTx("");
    try {
      const hash = await writeContractAsync({ ...args, chainId: chain.id });
      setLastTx(`${label}: ${hash}`);
      await publicClient.waitForTransactionReceipt({ hash });
      await Promise.all([sub.refetch(), isDue.refetch(), hasAccess.refetch(), collectorFee.refetch()]);
    } catch (e: any) {
      setErrMsg(e?.shortMessage ?? e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!configured) {
    return (
      <main className="card">
        <h2 style={{ marginTop: 0 }}>Collector</h2>
        <p className="muted">This chain is not configured yet.</p>
      </main>
    );
  }

  const isDueBool = (isDue.data as boolean | undefined) ?? false;
  const hasAccessBool = (hasAccess.data as boolean | undefined) ?? false;
  const feeAmt = (collectorFee.data as bigint | undefined) ?? 0n;

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Collector</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          Anyone can call <code>collect(subscriptionId)</code> when a subscription is due, and earn the configured
          collector fee.
        </p>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Collect for a subscription</h3>
        <div className="row">
          <div>
            <div className="muted">subscriptionId</div>
            <input className="input" value={subId} onChange={(e) => setSubId(e.target.value)} />
          </div>
          <button className="btn" disabled={busy} onClick={() => sub.refetch()}>
            Refresh
          </button>
        </div>

        <div className="row" style={{ marginTop: 12 }}>
          <div>
            <div className="muted">planId</div>
            <div>
              <b>{planId.toString()}</b>
            </div>
          </div>
          <div>
            <div className="muted">plan token</div>
            <code>{planTokenAddr}</code>
          </div>
          <div>
            <div className="muted">subscriber</div>
            <code>{subscriber || "-"}</code>
          </div>
          <div>
            <div className="muted">status (raw)</div>
            <div>{statusNum.toString()}</div>
          </div>
          <div>
            <div className="muted">paidThrough</div>
            <div>{fmtTs(paidThrough)}</div>
          </div>
          <div>
            <div className="muted">isDue</div>
            <div>{String(isDueBool)}</div>
          </div>
          <div>
            <div className="muted">hasAccess</div>
            <div>{String(hasAccessBool)}</div>
          </div>
          <div>
            <div className="muted">collectorFee (per collect)</div>
            <div>
              {fmtUnits(feeAmt, tokenMeta.decimals)} {tokenMeta.symbol}
            </div>
          </div>
          <div>
            <div className="muted">lastChargedAt</div>
            <div>{fmtTs(lastChargedAt)}</div>
          </div>
          <div>
            <div className="muted">startTime</div>
            <div>{fmtTs(startTime)}</div>
          </div>
        </div>

        <div className="row" style={{ marginTop: 14 }}>
          <button
            className="btn btnPrimary"
            disabled={!isConnected || mismatch || busy || !isDueBool}
            onClick={() =>
              runTx("collect", {
                address: openSub,
                abi: openSubAbi,
                functionName: "collect",
                args: [subIdBig],
              })
            }
          >
            Collect
          </button>
          {!isConnected && <span className="muted">Connect a wallet to send a collect tx.</span>}
          {mismatch && (
            <span className="muted">
              Switch wallet to chainId <code>{chain.id}</code>.
            </span>
          )}
          {isConnected && !mismatch && !isDueBool && (
            <span className="muted">Not due right now. (Contract will revert NotDue if you try.)</span>
          )}
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Debug</h3>
        <p className="muted">
          Last tx: <code>{lastTx || "-"}</code>
        </p>
        {errMsg && (
          <p>
            <b>Error:</b> <span className="muted">{errMsg}</span>
          </p>
        )}
      </div>
    </main>
  );
}
