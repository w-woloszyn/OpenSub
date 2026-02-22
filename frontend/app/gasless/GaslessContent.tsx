"use client";

import { useEffect, useMemo, useState } from "react";
import { createPublicClient, getAddress, http } from "viem";
import { baseSepolia } from "viem/chains";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { useSelectedChain } from "@/lib/selectedChain";
import { addresses } from "@/config/addresses";
import { openSubAbi } from "@/abi/openSubAbi";
import { erc20Abi } from "@/abi/erc20Abi";
import { tokens } from "@/config/tokens";
import { fmtTs, fmtUnits } from "@/lib/format";

export function GaslessContent() {
  const [chainKey] = useSelectedChain();

  const STORAGE_KEY = "opensub.aa.owner.pk";
  const [ownerPk, setOwnerPk] = useState<string>("");
  const [ownerAddr, setOwnerAddr] = useState<string>("");
  const [smartAccount, setSmartAccount] = useState<string>("");
  const [acctBusy, setAcctBusy] = useState<boolean>(false);
  const [acctErr, setAcctErr] = useState<string>("");
  const [planPrice, setPlanPrice] = useState<bigint>(0n);
  const [planInterval, setPlanInterval] = useState<bigint>(0n);
  const [tokenBalance, setTokenBalance] = useState<bigint>(0n);
  const [tokenAllowance, setTokenAllowance] = useState<bigint>(0n);
  const [subStatusNum, setSubStatusNum] = useState<bigint>(0n);
  const [paidThrough, setPaidThrough] = useState<bigint>(0n);
  const [lastChargedAt, setLastChargedAt] = useState<bigint>(0n);
  const [isDue, setIsDue] = useState<boolean>(false);
  const [nowTs, setNowTs] = useState<bigint>(0n);

  const [salt, setSalt] = useState<string>("0");
  const [periods, setPeriods] = useState<string>("12");
  const [mint, setMint] = useState<string>("0");
  const [mintTouched, setMintTouched] = useState<boolean>(false);

  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [resp, setResp] = useState<any>(null);
  const [elapsed, setElapsed] = useState<number>(0);
  const [stage, setStage] = useState<string>("Idle");
  const [subStatus, setSubStatus] = useState<string>("Not checked yet");
  const [subId, setSubId] = useState<string>("");
  const [hasRun, setHasRun] = useState<boolean>(false);
  const [actionBusy, setActionBusy] = useState<boolean>(false);
  const [actionStage, setActionStage] = useState<string>("Idle");
  const [actionErr, setActionErr] = useState<string>("");
  const [actionTxHash, setActionTxHash] = useState<string | null>(null);
  const [actionUserOpHash, setActionUserOpHash] = useState<string | null>(null);
  const [actionLogs, setActionLogs] = useState<string>("");
  const [hasActionRun, setHasActionRun] = useState<boolean>(false);
  const [userOpStatus, setUserOpStatus] = useState<string>("");
  const [hasPolled, setHasPolled] = useState<boolean>(false);
  const [refreshTick, setRefreshTick] = useState<number>(0);
  const [chainOffsetSec, setChainOffsetSec] = useState<number>(0);

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (raw) setOwnerPk(raw);
    } catch {
      // ignore
    }
  }, []);

  useEffect(() => {
    if (!ownerPk) {
      setOwnerAddr("");
      setSmartAccount("");
      return;
    }
    try {
      const acct = privateKeyToAccount(ownerPk as `0x${string}`);
      setOwnerAddr(acct.address);
    } catch {
      setOwnerAddr("");
    }
  }, [ownerPk]);

  const rpcUrl =
    process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL ?? "https://sepolia.base.org";
  const client = useMemo(
    () =>
      createPublicClient({
        chain: baseSepolia,
        transport: http(rpcUrl),
      }),
    [rpcUrl]
  );

  const openSub = addresses.baseTestnet.openSub as `0x${string}`;
  const planId = (addresses.baseTestnet.defaultPlanId ?? 1n) as bigint;
  const tokenMeta = tokens.baseTestnet[0];
  const tokenAddr = tokenMeta.address as `0x${string}`;
  const explorerBase = "https://sepolia-explorer.base.org";

  function decodeStatus(n?: bigint) {
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

  function fmtDuration(secondsInput: bigint | number) {
    const seconds = typeof secondsInput === "bigint" ? secondsInput : BigInt(secondsInput);
    if (seconds <= 0n) return "due now";
    const total = Number(seconds);
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    if (mins > 0) return `${mins}m ${secs}s`;
    return `${secs}s`;
  }

  function toBigInt(value: bigint | number) {
    return typeof value === "bigint" ? value : BigInt(value);
  }

  function computeNextDue(paidThrough: bigint, interval: bigint, now: bigint) {
    if (paidThrough <= 0n || interval <= 0n || now <= 0n) {
      return { nextDue: 0n, overdueBy: 0n };
    }
    if (now <= paidThrough) {
      return { nextDue: paidThrough, overdueBy: 0n };
    }
    const elapsed = now - paidThrough;
    const cycles = (elapsed + interval - 1n) / interval;
    const nextDue = paidThrough + cycles * interval;
    return { nextDue, overdueBy: elapsed };
  }

  const hasAnyRun = hasRun || hasActionRun;
  const respPending = Boolean(resp?.pending);
  const isSubscribePending = stage.includes("Submitted");
  const isActionPending = actionStage.includes("Submitted");
  const isPending = busy || actionBusy || respPending || isSubscribePending || isActionPending;
  const hasAccount = smartAccount.length === 42;
  const now = toBigInt(nowTs);
  const { nextDue, overdueBy } = computeNextDue(paidThrough, planInterval, now);

  useEffect(() => {
    const shouldWatch = hasAccount;
    if (!shouldWatch) return;

    let stopped = false;
    let active = true;
    const poll = async () => {
      try {
        const block = await client.getBlock({ blockTag: "latest" });
        const chainNow = Number(block.timestamp);
        if (Number.isFinite(chainNow)) {
          const localNow = Math.floor(Date.now() / 1000);
          setChainOffsetSec(chainNow - localNow);
        }

        const plan = (await client.readContract({
          address: openSub,
          abi: openSubAbi,
          functionName: "plans",
          args: [planId],
        })) as readonly [
          `0x${string}`,
          `0x${string}`,
          bigint,
          number,
          number,
          boolean,
          number
        ];
        if (!active) return;
        setPlanPrice(plan?.[2] ?? 0n);
        setPlanInterval(BigInt(plan?.[3] ?? 0));

        const bal = (await client.readContract({
          address: tokenAddr,
          abi: erc20Abi,
          functionName: "balanceOf",
          args: [smartAccount as `0x${string}`],
        })) as bigint;
        if (!active) return;
        setTokenBalance(bal ?? 0n);

        const allowance = (await client.readContract({
          address: tokenAddr,
          abi: erc20Abi,
          functionName: "allowance",
          args: [smartAccount as `0x${string}`, openSub],
        })) as bigint;
        if (!active) return;
        setTokenAllowance(allowance ?? 0n);

        const sub = (await client.readContract({
          address: openSub,
          abi: openSubAbi,
          functionName: "activeSubscriptionOf",
          args: [planId, smartAccount as `0x${string}`],
        })) as bigint;
        if (!active) return;

        if (sub && sub !== 0n) {
          setHasRun(true);
          setSubStatus("Subscription active");
          setSubId(sub.toString());
          const subRow = (await client.readContract({
            address: openSub,
            abi: openSubAbi,
            functionName: "subscriptions",
            args: [sub],
          })) as readonly [bigint, `0x${string}`, number, number, number, number];
          if (!active) return;
          setSubStatusNum(BigInt(subRow?.[2] ?? 0));
          setPaidThrough(BigInt(subRow?.[4] ?? 0));
          setLastChargedAt(BigInt(subRow?.[5] ?? 0));
          const due = (await client.readContract({
            address: openSub,
            abi: openSubAbi,
            functionName: "isDue",
            args: [sub],
          })) as boolean;
          if (!active) return;
          setIsDue(Boolean(due));
          return;
        }
        setSubId("");
        setSubStatusNum(0n);
        setPaidThrough(0n);
        setLastChargedAt(0n);
        setIsDue(false);
        const pending = isPending;
        setSubStatus(
          pending
            ? "Waiting for on-chain confirmation…"
            : hasAnyRun
              ? "No active subscription found"
              : "Not checked yet"
        );
      } catch (e: any) {
        if (!active) return;
        const msg = e?.shortMessage ?? e?.message ?? "";
        if (msg.includes("Address") || msg.includes("checksum")) {
          setSubStatus("Waiting for smart account address…");
        } else {
          const pending = isPending;
          setSubStatus(
            pending
              ? "Waiting for on-chain confirmation…"
              : hasAnyRun
                ? "No active subscription found"
                : "Not checked yet"
          );
        }
      } finally {
        if (active) setHasPolled(true);
      }
    };

    poll();
    const intervalMs = isPending ? 3000 : 8000;
    const id = setInterval(() => {
      if (!stopped) poll();
    }, intervalMs);

    return () => {
      stopped = true;
      active = false;
      clearInterval(id);
    };
  }, [smartAccount, client, openSub, planId, tokenAddr, hasAnyRun, busy, actionBusy, respPending, hasAccount, isPending, refreshTick]);

  useEffect(() => {
    if (!subId) {
      setNowTs(0n);
      return;
    }
    const tick = () => {
      setNowTs(BigInt(Math.floor(Date.now() / 1000) + chainOffsetSec));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [subId, chainOffsetSec]);

  async function refreshAccount() {
    if (!ownerPk) return;
    setAcctBusy(true);
    setAcctErr("");
    try {
      const r = await fetch("/api/aa-account", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ ownerPrivateKey: ownerPk, salt: Number(salt) }),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) {
        throw new Error(j.error ?? `Request failed (${r.status})`);
      }
      const raw = (j.result?.smartAccount ?? "").trim();
      if (!raw) {
        setSmartAccount("");
      } else {
        try {
          setSmartAccount(getAddress(raw as `0x${string}`));
        } catch {
          setSmartAccount(raw);
        }
      }
    } catch (e: any) {
      setAcctErr(e?.message ?? String(e));
    } finally {
      setAcctBusy(false);
    }
  }

  useEffect(() => {
    refreshAccount();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ownerPk, salt]);

  useEffect(() => {
    if (!mintTouched && planPrice > 0n) {
      setMint((planPrice * 10n).toString());
    }
  }, [planPrice, mintTouched, smartAccount]);

  useEffect(() => {
    if (!busy) {
      setElapsed(0);
      return;
    }
    const start = Date.now();
    const id = setInterval(() => {
      setElapsed(Math.floor((Date.now() - start) / 1000));
    }, 1000);
    return () => clearInterval(id);
  }, [busy]);

  function generateOwner() {
    resetAccountState();
    const pk = generatePrivateKey();
    try {
      window.localStorage.setItem(STORAGE_KEY, pk);
    } catch {
      // ignore
    }
    setOwnerPk(pk);
  }

  function resetOwner() {
    resetAccountState();
    try {
      window.localStorage.removeItem(STORAGE_KEY);
    } catch {
      // ignore
    }
    setOwnerPk("");
    setOwnerAddr("");
    setSmartAccount("");
  }

  function resetAccountState() {
    setAcctErr("");
    setAcctBusy(false);
    setSmartAccount("");
    setTokenBalance(0n);
    setTokenAllowance(0n);
    setSubStatusNum(0n);
    setPaidThrough(0n);
    setLastChargedAt(0n);
    setIsDue(false);
    setSubStatus("Not checked yet");
    setSubId("");
    setResp(null);
    setErrMsg("");
    setStage("Idle");
    setHasRun(false);
    setElapsed(0);
    setBusy(false);
    setNowTs(0n);
    setMintTouched(false);
    setMint("0");
    setActionBusy(false);
    setActionStage("Idle");
    setActionErr("");
    setActionTxHash(null);
    setActionUserOpHash(null);
    setActionLogs("");
    setHasActionRun(false);
    setUserOpStatus("");
    setHasPolled(false);
  }

  useEffect(() => {
    if (!smartAccount) {
      setSubStatus("Not checked yet");
      setSubId("");
      setTokenBalance(0n);
      setTokenAllowance(0n);
      setSubStatusNum(0n);
      setPaidThrough(0n);
      setLastChargedAt(0n);
      setIsDue(false);
      return;
    }
    setResp(null);
    setErrMsg("");
    setStage("Idle");
    setHasRun(false);
    setElapsed(0);
    setActionBusy(false);
    setActionStage("Idle");
    setActionErr("");
    setActionTxHash(null);
    setActionUserOpHash(null);
    setActionLogs("");
    setHasActionRun(false);
    setUserOpStatus("");
    setHasPolled(false);
  }, [smartAccount]);

  async function run() {
    setBusy(true);
    setErrMsg("");
    setUserOpStatus("");
    setResp(null);
    setHasRun(true);
    setStage("Submitting UserOperation…");
    setHasPolled(false);
    try {
      if (!ownerPk) {
        throw new Error("Generate an owner key first.");
      }
      if (!smartAccount || smartAccount.length !== 42) {
        throw new Error("Smart account address not ready yet. Wait a moment and retry.");
      }
      const r = await fetch("/api/gasless-subscribe", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          salt: Number(salt),
          allowancePeriods: Number(periods),
          mintAmountRaw: mint,
          ownerPrivateKey: ownerPk,
          smartAccount,
        }),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) {
        throw new Error(j.error ?? `Request failed (${r.status})`);
      }
      setResp(j);
      if (j.result?.userOpHash || j.userOpHash) {
        setUserOpStatus("UserOp submitted; waiting for confirmation…");
      }
      setStage(j.pending ? "Submitted (pending confirmation)" : "Confirmed");
    } catch (e: any) {
      setErrMsg(e?.message ?? String(e));
      setStage("Error");
    } finally {
      setBusy(false);
    }
  }

  async function runAction(kind: "cancel_now" | "cancel_end" | "resume" | "collect") {
    setActionBusy(true);
    setActionErr("");
    setActionStage("Submitting UserOperation…");
    setActionTxHash(null);
    setActionUserOpHash(null);
    setUserOpStatus("");
    setActionLogs("");
    setHasActionRun(true);
    setHasPolled(false);
    try {
      if (!ownerPk) {
        throw new Error("Generate an owner key first.");
      }
      if (!smartAccount || smartAccount.length !== 42) {
        throw new Error("Smart account address not ready yet. Wait a moment and retry.");
      }
      if (!subId) {
        throw new Error("No active subscription id yet.");
      }

      const endpoint =
        kind === "collect"
          ? "/api/gasless-collect"
          : kind === "resume"
            ? "/api/gasless-resume"
            : "/api/gasless-cancel";

      const body: any = {
        salt: Number(salt),
        ownerPrivateKey: ownerPk,
        smartAccount,
        subscriptionId: Number(subId),
      };
      if (kind === "cancel_end") body.atPeriodEnd = true;

      const r = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) {
        throw new Error(j.error ?? `Request failed (${r.status})`);
      }
      const tx = j.txHash ?? j.result?.txHash ?? null;
      const uo = j.userOpHash ?? j.result?.userOpHash ?? null;
      setActionTxHash(tx);
      setActionUserOpHash(uo);
      if (j.logs) setActionLogs(String(j.logs));
      if (uo) {
        setUserOpStatus("Action UserOp submitted; waiting for confirmation…");
      }
      setActionStage(j.pending ? "Submitted (pending confirmation)" : "Confirmed");
    } catch (e: any) {
      setActionErr(e?.message ?? String(e));
      setActionStage("Error");
    } finally {
      setActionBusy(false);
    }
  }

  const subscribeTxHash = resp?.result?.txHash ?? resp?.txHash ?? null;
  const subscribeUserOpHash = resp?.result?.userOpHash ?? resp?.userOpHash ?? null;
  const actionPending = actionStage.includes("Submitted");
  const hasAction = actionBusy || actionStage !== "Idle" || Boolean(actionUserOpHash);
  const txHash = hasAction ? actionTxHash ?? null : subscribeTxHash ?? null;
  const userOpHash = hasAction ? actionUserOpHash ?? null : subscribeUserOpHash ?? null;

  async function checkUserOpStatus() {
    if (hasAction && !actionUserOpHash) {
      setUserOpStatus("Waiting for action UserOp hash…");
      return;
    }
    if (!userOpHash) return;
    setUserOpStatus("Checking bundler status…");
    try {
      const r = await fetch("/api/userop-status", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userOpHash }),
      });
      const j = await r.json();
      if (!r.ok || !j.ok) {
        throw new Error(j.error ?? `Request failed (${r.status})`);
      }
      if (j.receipt && j.receipt.transactionHash) {
        const tx = j.receipt.transactionHash as string;
        setUserOpStatus(`Included in tx ${tx}`);
        if (actionUserOpHash && actionUserOpHash === userOpHash) {
          setActionStage("Confirmed");
          setActionTxHash(tx);
        } else {
          setStage("Confirmed");
          setResp((prev) => (prev ? { ...prev, result: { ...prev.result, txHash: tx } } : prev));
        }
        setRefreshTick((t) => t + 1);
        setHasPolled(false);
        return;
      }
      if (j.userOp && j.userOp.userOperation) {
        const isAction = actionUserOpHash && actionUserOpHash === userOpHash;
        if (!isAction && subId) {
          setStage("Confirmed");
          setUserOpStatus("On-chain state updated; bundler receipt still pending.");
          setRefreshTick((t) => t + 1);
          return;
        }
        setUserOpStatus("Pending in bundler mempool (not mined yet).");
        return;
      }
      setUserOpStatus("Bundler has no record of this UserOp (dropped or expired).");
    } catch (e: any) {
      setUserOpStatus(e?.message ?? String(e));
    }
  }

  useEffect(() => {
    const hasPending = Boolean(userOpHash) && !txHash;
    if (!hasPending) return;
    let stopped = false;
    const tick = async () => {
      if (stopped) return;
      await checkUserOpStatus();
    };
    tick();
    const id = setInterval(tick, 15000);
    return () => {
      stopped = true;
      clearInterval(id);
    };
  }, [userOpHash, txHash]);

  return (
    <>
      <div className="card banner">
        <h2 style={{ marginTop: 0 }}>⚠ Demo-only security warning</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          This page stores a <b>private key in your browser</b> (localStorage) to create a smart account.
          This is <b>not safe for production</b>. It is only for demo / onboarding.
        </p>
        <p className="muted" style={{ marginBottom: 0 }}>
          Production options: wallet-as-owner AA, passkeys/WebAuthn, or secure backend key management.
        </p>
      </div>

      <div className="card">
        <h2 style={{ marginTop: 0 }}>Gasless subscribe (AA) — demo mode</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          This page is a <b>demo convenience</b>: it calls the Rust AA CLI (<code>aa-rs/opensub-aa</code>) from a
          Next.js API route, which:
        </p>
        <ol className="muted" style={{ marginTop: 6 }}>
          <li>Uses a locally generated <b>AA owner key</b> stored in your browser,</li>
          <li>Creates a sponsored ERC-4337 UserOperation (Alchemy Gas Manager, Base Sepolia),</li>
          <li>Mints demo tokens + approves + subscribes inside the UserOp,</li>
          <li>Returns the owner/smartAccount + on-chain subscription id.</li>
        </ol>
        <p className="muted" style={{ marginTop: 6 }}>
          Demo plan: <b>planId {planId.toString()}</b>, interval{" "}
          <b>{planInterval ? `${planInterval.toString()}s` : "loading…"}</b>.
        </p>
        <p className="muted" style={{ marginBottom: 0 }}>
          ⚠️ Not production architecture. It’s just a one-click demo so non-blockchain frontend devs don’t need to
          learn ERC-4337 before they can ship UI.
        </p>
      </div>

      {chainKey !== "baseTestnet" && (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>
            Gasless demo is only wired for <b>Base Sepolia</b>. Switch chain in the header.
          </p>
        </div>
      )}

      <div className="split">
        <div className="stack">
          <div className="card">
            <h3 style={{ marginTop: 0 }}>Your actions</h3>
            <div className="row" style={{ alignItems: "center" }}>
              <button className="btn" onClick={generateOwner}>
                {ownerPk ? "Regenerate smart account" : "Create smart account"}
              </button>
              {ownerPk && (
                <button className="btn" onClick={resetOwner} data-testid="clear-owner">
                  Reset account
                </button>
              )}
              <button
                className="btn btnPrimary"
                disabled={busy || chainKey !== "baseTestnet" || !ownerPk || smartAccount.length !== 42}
                onClick={run}
                data-testid="run-subscribe"
              >
                {busy ? "Running…" : "Run sponsored subscribe"}
              </button>
              {busy && (
                <span className="row" style={{ alignItems: "center", gap: 8 }}>
                  <span className="spinner" />
                  <span className="muted">Elapsed: {elapsed}s</span>
                </span>
              )}
            </div>
            {acctBusy && <p className="muted">Deriving smart account…</p>}
            {acctErr && (
              <p style={{ marginTop: 6 }}>
                <b>Error:</b> <span className="muted">{acctErr}</span>
              </p>
            )}
            {ownerPk && (
              <p className="muted" style={{ marginTop: 6 }}>
                This owner key lives in your browser storage. If you clear storage, you lose access to this smart
                account.
              </p>
            )}
            <div className="row" style={{ marginTop: 12 }}>
              <div>
                <div className="muted">Stage</div>
                <div>
                  <b data-testid="stage">{stage}</b>
                </div>
              </div>
              <div>
                <div className="muted">Subscription status</div>
                <div data-testid="sub-status">
                  {hasAccount && !hasPolled && !subId ? "Loading on-chain state…" : subStatus}
                </div>
              </div>
              <div>
                <div className="muted">subscriptionId</div>
                <div data-testid="sub-id">{subId || "-"}</div>
              </div>
            </div>
            {errMsg && (
              <p style={{ marginTop: 10 }}>
                <b>Error:</b> <span className="muted">{errMsg}</span>
              </p>
            )}
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Story (what just happened)</h3>
            <ul className="muted">
              <li>
                1) Generate a local AA owner key (stored in your browser): <b>{ownerAddr ? "done" : "pending"}</b>
              </li>
              <li>
                2) Derive your smart account address: <b>{smartAccount.length === 42 ? "done" : "pending"}</b>
              </li>
              <li>
                3) Sponsor a UserOp to mint ~10× the plan price to the smart account:{" "}
                <b>{!hasRun ? "-" : busy ? "in progress" : resp ? "done" : "pending"}</b>
              </li>
              <li>
                4) Grant OpenSub allowance to spend those tokens:{" "}
                <b>{!hasRun ? "-" : tokenAllowance > 0n ? "done" : "pending"}</b>
              </li>
              <li>
                5) Subscription created and active on-chain: <b>{!hasRun ? "-" : subId ? "done" : "pending"}</b>
              </li>
              <li>
                6) Next renewal (paidThrough): <b>{!hasRun ? "-" : subId ? fmtTs(paidThrough) : "pending"}</b>
              </li>
            </ul>
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Active subscription</h3>
            {!hasAccount ? (
              <p className="muted">Create a smart account to load subscription state.</p>
            ) : !hasPolled && !subId ? (
              <p className="muted">Loading on-chain state…</p>
            ) : !subId ? (
              <p className="muted">No active subscription yet.</p>
            ) : (
              <>
                <div className="row">
                  <div>
                    <div className="muted">subscriptionId</div>
                    <div>{subId}</div>
                  </div>
                  <div>
                    <div className="muted">status</div>
                    <div data-testid="sub-status-label">
                      {isActionPending ? "Action pending…" : decodeStatus(subStatusNum)}
                    </div>
                  </div>
                  <div>
                    <div className="muted">paidThrough (current period end)</div>
                    <div>{fmtTs(paidThrough)}</div>
                  </div>
                  <div>
                    <div className="muted">next scheduled renewal</div>
                    <div>{nextDue > 0n ? fmtTs(nextDue) : "-"}</div>
                  </div>
                  <div>
                    <div className="muted">due in</div>
                    <div>
                      {nextDue > 0n && now > 0n
                        ? isDue
                          ? "due now"
                          : fmtDuration(nextDue > now ? nextDue - now : 0n)
                        : "-"}
                    </div>
                  </div>
                  {isDue && overdueBy > 0n ? (
                    <div>
                      <div className="muted">overdue by</div>
                      <div>{fmtDuration(overdueBy)}</div>
                    </div>
                  ) : null}
                  <div>
                    <div className="muted">isDue</div>
                    <div data-testid="sub-is-due">{String(isDue)}</div>
                  </div>
                  <div>
                    <div className="muted">lastChargedAt</div>
                    <div>{fmtTs(lastChargedAt)}</div>
                  </div>
                </div>
                {!hasPolled && (
                  <p className="muted" style={{ marginTop: 6 }}>
                    Refreshing on-chain state…
                  </p>
                )}
              </>
            )}
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Manage subscription</h3>
            {!subId ? (
              <p className="muted">Run a gasless subscribe first to create a subscription.</p>
            ) : (
              <>
                <p className="muted" style={{ marginTop: 0 }}>
                  Note: in production, <b>renewals are handled by the keeper</b> (or any third-party collector), not the
                  subscriber. Cancels/resumes are user actions.
                </p>
                <div className="row" style={{ gap: 10 }}>
                  <button
                    className="btn"
                    disabled={actionBusy || busy || actionPending || chainKey !== "baseTestnet"}
                    onClick={() => runAction("collect")}
                    data-testid="action-collect"
                  >
                    {actionBusy ? "Working…" : "Collect now"}
                  </button>
                  <button
                    className="btn"
                    disabled={actionBusy || busy || actionPending || chainKey !== "baseTestnet"}
                    onClick={() => runAction("cancel_now")}
                    data-testid="action-cancel-now"
                  >
                    Cancel now
                  </button>
                  <button
                    className="btn"
                    disabled={actionBusy || busy || actionPending || chainKey !== "baseTestnet"}
                    onClick={() => runAction("cancel_end")}
                    data-testid="action-cancel-end"
                  >
                    Cancel at period end
                  </button>
                  <button
                    className="btn"
                    disabled={actionBusy || busy || actionPending || chainKey !== "baseTestnet"}
                    onClick={() => runAction("resume")}
                    data-testid="action-resume"
                  >
                    Resume auto-renew
                  </button>
                </div>
                {actionPending && (
                  <p className="muted" style={{ marginTop: 8 }}>
                    Action pending on-chain. Wait for confirmation before sending another action.
                  </p>
                )}
                <div className="row" style={{ marginTop: 12 }}>
                  <div>
                    <div className="muted">Action stage</div>
                    <div>
                      <b data-testid="action-stage">{actionStage}</b>
                    </div>
                  </div>
                  {actionBusy && (
                    <span className="row" style={{ alignItems: "center", gap: 8 }}>
                      <span className="spinner" />
                      <span className="muted">Working…</span>
                    </span>
                  )}
                </div>
                {actionErr && (
                  <p style={{ marginTop: 10 }}>
                    <b>Error:</b> <span className="muted">{actionErr}</span>
                  </p>
                )}
                {actionLogs && (
                  <details style={{ marginTop: 8 }}>
                    <summary data-testid="action-logs-toggle">Action CLI logs (stderr)</summary>
                    <pre style={{ whiteSpace: "pre-wrap" }} data-testid="action-logs">
                      {actionLogs}
                    </pre>
                  </details>
                )}
              </>
            )}
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Your balance</h3>
            {!hasAccount ? (
              <p className="muted">Create a smart account to see balances.</p>
            ) : !hasPolled && tokenBalance === 0n && tokenAllowance === 0n && planPrice === 0n && planInterval === 0n ? (
              <p className="muted">Loading on-chain state…</p>
            ) : (
              <>
                <div className="row">
                  <div>
                    <div className="muted">Balance</div>
                    <div>
                      {fmtUnits(tokenBalance, tokenMeta.decimals)} {tokenMeta.symbol}
                    </div>
                  </div>
                  <div>
                    <div className="muted">Spending allowance</div>
                    <div>
                      {fmtUnits(tokenAllowance, tokenMeta.decimals)} {tokenMeta.symbol}
                    </div>
                  </div>
                  <div>
                    <div className="muted">Plan price</div>
                    <div>
                      {fmtUnits(planPrice, tokenMeta.decimals)} {tokenMeta.symbol}
                    </div>
                  </div>
                  <div>
                    <div className="muted">Interval</div>
                    <div>{planInterval ? `${planInterval.toString()}s` : "-"}</div>
                  </div>
                </div>
                {!hasPolled && (
                  <p className="muted" style={{ marginTop: 6 }}>
                    Refreshing on-chain state…
                  </p>
                )}
              </>
            )}
          </div>
        </div>

        <div className="stack">
          <div className="card">
            <h3 style={{ marginTop: 0 }}>Web3 details (under the hood)</h3>
            <div className="row">
              <div>
                <div className="muted">Chain</div>
                <div>Base Sepolia (AA-only)</div>
              </div>
              <div>
                <div className="muted">planId</div>
                <div>{planId.toString()}</div>
              </div>
              <div>
                <div className="muted">OpenSub</div>
                <code>{openSub}</code>
              </div>
              <div>
                <div className="muted">Token</div>
                <code>{tokenAddr}</code>
              </div>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <div>
                <div className="muted">AA owner (local)</div>
                <code data-testid="owner-addr">{ownerAddr || "not generated"}</code>
              </div>
              <div>
                <div className="muted">Smart account</div>
                <code data-testid="smart-account">{smartAccount || "-"}</code>
              </div>
            </div>
            <div className="row" style={{ marginTop: 10 }}>
              <div>
                <div className="muted">salt</div>
                <input className="input" value={salt} onChange={(e) => setSalt(e.target.value)} />
              </div>
              <div>
                <div className="muted">allowance periods</div>
                <input className="input" value={periods} onChange={(e) => setPeriods(e.target.value)} />
              </div>
              <div>
                <div className="muted">mint (raw units, default = 10× plan price)</div>
                <input
                  className="input"
                  value={mint}
                  onChange={(e) => {
                    setMintTouched(true);
                    setMint(e.target.value);
                  }}
                />
              </div>
            </div>
            <p className="muted" style={{ marginTop: 8 }}>
              These settings are intentionally exposed for demo/testing. In production they would live in a backend or
              be user-hidden.
            </p>
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Explorer links</h3>
            <div className="row">
              <div>
                <div className="muted">OpenSub</div>
                <a href={`${explorerBase}/address/${openSub}`} target="_blank" rel="noreferrer">
                  View on explorer
                </a>
              </div>
              <div>
                <div className="muted">Token</div>
                <a href={`${explorerBase}/address/${tokenAddr}`} target="_blank" rel="noreferrer">
                  View on explorer
                </a>
              </div>
              <div>
                <div className="muted">Smart account</div>
                {smartAccount ? (
                  <a href={`${explorerBase}/address/${smartAccount}`} target="_blank" rel="noreferrer">
                    {smartAccount}
                  </a>
                ) : (
                  <span className="muted">-</span>
                )}
              </div>
              <div>
                <div className="muted">Transaction</div>
                {!hasAnyRun ? (
                  <span className="muted">-</span>
                ) : txHash ? (
                  <a href={`${explorerBase}/tx/${txHash}`} target="_blank" rel="noreferrer">
                    View tx
                  </a>
                ) : (
                  <span className="muted">pending</span>
                )}
              </div>
            </div>
            {hasAnyRun && userOpHash && (
              <p className="muted" style={{ marginTop: 8 }}>
                UserOp hash: <code data-testid="userop-hash">{userOpHash}</code>
              </p>
            )}
            {hasAnyRun && userOpHash && (
              <div style={{ marginTop: 8 }}>
                <p className="muted" style={{ marginTop: 0 }} data-testid="userop-status">
                  {userOpStatus ||
                    (txHash
                      ? `Included in tx ${txHash}`
                      : "Checking bundler status automatically…")}
                </p>
              </div>
            )}
            {resp?.logs && (
              <details style={{ marginTop: 8 }}>
                <summary>CLI logs (stderr)</summary>
                <pre style={{ whiteSpace: "pre-wrap" }}>{resp.logs}</pre>
              </details>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
