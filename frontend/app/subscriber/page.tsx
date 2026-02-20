"use client";

import { useMemo, useState } from "react";
import { useAccount, useChainId, usePublicClient, useWriteContract, useReadContract } from "wagmi";

import { openSubAbi } from "@/abi/openSubAbi";
import { erc20Abi } from "@/abi/erc20Abi";
import { tokens } from "@/config/tokens";
import { chainForKey, defaultToken, isConfiguredAddress, openSubAddress } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { fmtTs, fmtUnits, nowSec } from "@/lib/format";
import { ZERO_ADDRESS } from "@/lib/constants";

type SubStatus = "None" | "Active" | "NonRenewing" | "Cancelled";

function decodeStatus(n?: bigint): SubStatus {
  switch (Number(n ?? 0n)) {
    case 1:
      return "Active";
    case 2:
      return "NonRenewing";
    case 3:
      return "Cancelled";
    default:
      return "None";
  }
}

export default function SubscriberPage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);
  const openSub = openSubAddress(chainKey);
  const token = defaultToken(chainKey);
  const tokenList = tokens[chainKey];

  const configured = isConfiguredAddress(openSub);

  const { address, isConnected } = useAccount();
  const walletChainId = useChainId();
  const mismatch = isConnected && walletChainId !== chain.id;

  const [planId, setPlanId] = useState<string>("1");
  const planIdBig = useMemo(() => {
    try {
      return BigInt(planId);
    } catch {
      return 1n;
    }
  }, [planId]);

  const [periods, setPeriods] = useState<string>("12");
  const periodsBig = useMemo(() => {
    try {
      const n = BigInt(periods);
      return n <= 0n ? 12n : n;
    } catch {
      return 12n;
    }
  }, [periods]);

  const publicClient = usePublicClient({ chainId: chain.id });
  const { writeContractAsync } = useWriteContract();

  const [lastTx, setLastTx] = useState<string>("");
  const [busy, setBusy] = useState<boolean>(false);
  const [errMsg, setErrMsg] = useState<string>("");

  const plan = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "plans",
    args: [planIdBig],
    chainId: chain.id,
    query: { enabled: configured },
  });

  const planTokenAddr = (plan.data?.[1] as string | undefined) ?? token.address;
  const planPrice = (plan.data?.[2] as bigint | undefined) ?? 0n;
  const planInterval = (plan.data?.[3] as bigint | undefined) ?? 0n;
  const planFeeBps = (plan.data?.[4] as bigint | undefined) ?? 0n;
  const planActive = (plan.data?.[5] as boolean | undefined) ?? false;

  const tokenMeta = useMemo(() => {
    const byAddr = tokenList.find((t) => t.address.toLowerCase() === planTokenAddr.toLowerCase());
    return byAddr ?? token;
  }, [planTokenAddr, tokenList, token]);

  const planTokenConfigured = isConfiguredAddress(planTokenAddr);

  const targetAllowance = useMemo(() => planPrice * periodsBig, [planPrice, periodsBig]);

  const allowance = useReadContract({
    address: planTokenAddr as `0x${string}`,
    abi: erc20Abi,
    functionName: "allowance",
    args: [(address ?? ZERO_ADDRESS) as `0x${string}`, openSub],
    chainId: chain.id,
    query: { enabled: configured && !!address && planTokenConfigured },
  });

  const balance = useReadContract({
    address: planTokenAddr as `0x${string}`,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [(address ?? ZERO_ADDRESS) as `0x${string}`],
    chainId: chain.id,
    query: { enabled: configured && !!address && planTokenConfigured },
  });

  const subId = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "activeSubscriptionOf",
    args: [planIdBig, (address ?? ZERO_ADDRESS) as `0x${string}`],
    chainId: chain.id,
    query: { enabled: configured && !!address && planTokenConfigured },
  });

  const subIdBig = (subId.data as bigint | undefined) ?? 0n;

  const sub = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "subscriptions",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const statusNum = (sub.data?.[2] as bigint | undefined) ?? 0n;
  const status = decodeStatus(statusNum);
  const startTime = (sub.data?.[3] as bigint | undefined) ?? 0n;
  const paidThrough = (sub.data?.[4] as bigint | undefined) ?? 0n;
  const lastChargedAt = (sub.data?.[5] as bigint | undefined) ?? 0n;

  const hasAccess = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "hasAccess",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const isDue = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "isDue",
    args: [subIdBig],
    chainId: chain.id,
    query: { enabled: configured && subIdBig !== 0n },
  });

  const allowanceBig = (allowance.data as bigint | undefined) ?? 0n;
  const balanceBig = (balance.data as bigint | undefined) ?? 0n;
  const hasAccessBool = (hasAccess.data as boolean | undefined) ?? false;
  const isDueBool = (isDue.data as boolean | undefined) ?? false;

  const now = nowSec();

  // UI state machine (docs/UI_STATE_MACHINE.md)
  const state = useMemo(() => {
    if (subIdBig === 0n || status === "Cancelled" || status === "None") return "S0";
    if (status === "Active" && now < paidThrough) return "S1";
    if (status === "Active" && now >= paidThrough) return "S2";
    if (status === "NonRenewing" && now < paidThrough) return "S3";
    if (status === "NonRenewing" && now >= paidThrough) return "S4";
    return "S0";
  }, [subIdBig, status, now, paidThrough]);

  const needsApprove = allowanceBig < targetAllowance;
  const canPayOne = allowanceBig >= planPrice && balanceBig >= planPrice;

  async function runTx(
    label: string,
    args: Parameters<typeof writeContractAsync>[0]
  ) {
    if (!publicClient) {
      setErrMsg("No public client available.");
      return;
    }
    setErrMsg("");
    setBusy(true);
    setLastTx("");
    try {
      const hash = await writeContractAsync({ ...args, chainId: chain.id });
      setLastTx(`${label}: ${hash}`);
      await publicClient.waitForTransactionReceipt({ hash });
      // Refresh reads
      await Promise.all([
        plan.refetch(),
        allowance.refetch(),
        balance.refetch(),
        subId.refetch(),
        sub.refetch(),
        hasAccess.refetch(),
        isDue.refetch(),
      ]);
    } catch (e: any) {
      setErrMsg(e?.shortMessage ?? e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!configured) {
    return (
      <main className="card">
        <h2 style={{ marginTop: 0 }}>Subscriber</h2>
        <p className="muted">
          This chain is not configured yet. Update <code>frontend/config/addresses.ts</code> and
          <code>frontend/config/tokens.ts</code>.
        </p>
      </main>
    );
  }

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Subscriber</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          Implements <code>docs/UI_STATE_MACHINE.md</code>. If a subscription is <b>Active</b> but expired, the correct
          action is <b>Renew (collect)</b> — not resubscribe.
        </p>

        <div className="row">
          <div>
            <div className="muted">PlanId</div>
            <input className="input" value={planId} onChange={(e) => setPlanId(e.target.value)} />
          </div>
          <div>
            <div className="muted">Allowance periods (N)</div>
            <input className="input" value={periods} onChange={(e) => setPeriods(e.target.value)} />
          </div>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Plan</h3>
        <div className="row">
          <div>
            <div className="muted">OpenSub</div>
            <code>{openSub}</code>
          </div>
          <div>
            <div className="muted">Token</div>
            <code>{planTokenAddr}</code>
          </div>
          <div>
            <div className="muted">Price</div>
            <div>
              <b>{fmtUnits(planPrice, tokenMeta.decimals)}</b> {tokenMeta.symbol}
            </div>
          </div>
          <div>
            <div className="muted">Interval</div>
            <div>{planInterval.toString()} sec</div>
          </div>
          <div>
            <div className="muted">Collector fee</div>
            <div>{planFeeBps.toString()} bps</div>
          </div>
          <div>
            <div className="muted">Active</div>
            <div>{String(planActive)}</div>
          </div>
        </div>
        {!planActive && (
          <p className="muted" style={{ marginTop: 10 }}>
            Plan is paused. Subscribe and renew are disabled (contract will revert <code>PlanInactive</code>).
          </p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Your wallet</h3>
        {!isConnected ? (
          <p className="muted">Connect a wallet to interact.</p>
        ) : mismatch ? (
          <p className="muted">
            Wallet is on chainId <code>{walletChainId}</code>. Switch to <code>{chain.id}</code> using the button in the
            top nav.
          </p>
        ) : (
          <div className="row">
            <div>
              <div className="muted">Balance</div>
              <div>
                {fmtUnits(balanceBig, tokenMeta.decimals)} {tokenMeta.symbol}
              </div>
            </div>
            <div>
              <div className="muted">Allowance → OpenSub</div>
              <div>
                {fmtUnits(allowanceBig, tokenMeta.decimals)} {tokenMeta.symbol}
              </div>
            </div>
            <div>
              <div className="muted">Target allowance (price × N)</div>
              <div>
                {fmtUnits(targetAllowance, tokenMeta.decimals)} {tokenMeta.symbol}
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Subscription</h3>
        {!isConnected ? (
          <p className="muted">Connect a wallet to load your subscription status.</p>
        ) : (
          <>
            <div className="row">
              <div>
                <div className="muted">activeSubscriptionOf(planId, you)</div>
                <div>
                  <b>{subIdBig.toString()}</b>
                </div>
              </div>
              <div>
                <div className="muted">status</div>
                <div>
                  <b>{status}</b> <span className="badge">{state}</span>
                </div>
              </div>
              <div>
                <div className="muted">paidThrough</div>
                <div>
                  <b>{fmtTs(paidThrough)}</b>
                </div>
              </div>
              <div>
                <div className="muted">hasAccess</div>
                <div>{String(hasAccessBool)}</div>
              </div>
              <div>
                <div className="muted">isDue</div>
                <div>{String(isDueBool)}</div>
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
                className="btn"
                disabled={!isConnected || mismatch || busy || !needsApprove}
                onClick={() =>
                  runTx("approve", {
                    address: planTokenAddr as `0x${string}`,
                    abi: erc20Abi,
                    functionName: "approve",
                    args: [openSub, targetAllowance],
                  })
                }
                title="Approve price × N to avoid repeated approvals"
              >
                {busy ? "Working…" : needsApprove ? "Approve" : "Approved"}
              </button>

              {/* Subscribe */}
              <button
                className="btn btnPrimary"
                disabled={
                  !isConnected ||
                  mismatch ||
                  busy ||
                  !planActive ||
                  (state !== "S0" && state !== "S4") ||
                  allowanceBig < planPrice
                }
                onClick={() =>
                  runTx("subscribe", {
                    address: openSub,
                    abi: openSubAbi,
                    functionName: "subscribe",
                    args: [planIdBig],
                  })
                }
                title="Subscribe charges immediately for the first period"
              >
                Subscribe
              </button>

              {/* Renew */}
              <button
                className="btn btnPrimary"
                disabled={
                  !isConnected ||
                  mismatch ||
                  busy ||
                  !planActive ||
                  state !== "S2" ||
                  !canPayOne
                }
                onClick={() =>
                  runTx("collect", {
                    address: openSub,
                    abi: openSubAbi,
                    functionName: "collect",
                    args: [subIdBig],
                  })
                }
                title="Renew an Active subscription after paidThrough"
              >
                Renew (collect)
              </button>

              {/* Cancel at period end (Pattern A) */}
              <button
                className="btn"
                disabled={!isConnected || mismatch || busy || (state !== "S1" && state !== "S2")}
                onClick={() =>
                  runTx("cancel(period end)", {
                    address: openSub,
                    abi: openSubAbi,
                    functionName: "cancel",
                    args: [subIdBig, true],
                  })
                }
              >
                Cancel at period end
              </button>

              {/* Resume */}
              <button
                className="btn"
                disabled={!isConnected || mismatch || busy || state !== "S3"}
                onClick={() =>
                  runTx("unscheduleCancel", {
                    address: openSub,
                    abi: openSubAbi,
                    functionName: "unscheduleCancel",
                    args: [subIdBig],
                  })
                }
              >
                Resume auto-renew
              </button>

              {/* Cancel now */}
              <button
                className="btn"
                disabled={!isConnected || mismatch || busy || state === "S0"}
                onClick={() =>
                  runTx("cancel(now)", {
                    address: openSub,
                    abi: openSubAbi,
                    functionName: "cancel",
                    args: [subIdBig, false],
                  })
                }
              >
                Cancel now
              </button>
            </div>

            {state === "S2" && !canPayOne && (
              <p className="muted" style={{ marginTop: 12 }}>
                Renewal requires <code>allowance ≥ price</code> and <code>balance ≥ price</code>. Approve and/or mint
                more {tokenMeta.symbol}.
              </p>
            )}
          </>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Debug</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          Last tx: <code>{lastTx || "-"}</code>
        </p>
        {errMsg && (
          <p style={{ marginTop: 6 }}>
            <b>Error:</b> <span className="muted">{errMsg}</span>
          </p>
        )}
      </div>
    </main>
  );
}
