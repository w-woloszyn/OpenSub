"use client";

import { useMemo, useState } from "react";
import { useAccount, useChainId, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { parseUnits } from "viem";

import { openSubAbi } from "@/abi/openSubAbi";
import { chainForKey, defaultToken, isConfiguredAddress, openSubAddress } from "@/lib/demoChains";
import { useSelectedChain } from "@/lib/selectedChain";
import { fmtUnits, fmtTs } from "@/lib/format";
import { tokens } from "@/config/tokens";

export default function MerchantPage() {
  const [chainKey] = useSelectedChain();
  const chain = chainForKey(chainKey);
  const openSub = openSubAddress(chainKey);
  const configured = isConfiguredAddress(openSub);
  const defaultTok = defaultToken(chainKey);

  const { address, isConnected } = useAccount();
  const walletChainId = useChainId();
  const mismatch = isConnected && walletChainId !== chain.id;

  const publicClient = usePublicClient({ chainId: chain.id });
  const { writeContractAsync } = useWriteContract();

  const [planId, setPlanId] = useState<string>("1");
  const planIdBig = useMemo(() => {
    try {
      return BigInt(planId);
    } catch {
      return 1n;
    }
  }, [planId]);

  const plan = useReadContract({
    address: openSub,
    abi: openSubAbi,
    functionName: "plans",
    args: [planIdBig],
    chainId: chain.id,
    query: { enabled: configured },
  });

  const planMerchant = (plan.data?.[0] as string | undefined) ?? "";
  const planToken = (plan.data?.[1] as string | undefined) ?? defaultTok.address;
  const planPrice = (plan.data?.[2] as bigint | undefined) ?? 0n;
  const planInterval = (plan.data?.[3] as bigint | undefined) ?? 0n;
  const planFeeBps = (plan.data?.[4] as bigint | undefined) ?? 0n;
  const planActive = (plan.data?.[5] as boolean | undefined) ?? false;
  const createdAt = (plan.data?.[6] as bigint | undefined) ?? 0n;

  // Create plan form
  const [tokenAddr, setTokenAddr] = useState<string>(defaultTok.address);
  const [priceHuman, setPriceHuman] = useState<string>("10");
  const [intervalSec, setIntervalSec] = useState<string>("300");
  const [feeBps, setFeeBps] = useState<string>("100");
  const [busy, setBusy] = useState(false);
  const [errMsg, setErrMsg] = useState<string>("");
  const [lastTx, setLastTx] = useState<string>("");

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
      await plan.refetch();
    } catch (e: any) {
      setErrMsg(e?.shortMessage ?? e?.message ?? String(e));
    } finally {
      setBusy(false);
    }
  }

  if (!configured) {
    return (
      <main className="card">
        <h2 style={{ marginTop: 0 }}>Merchant</h2>
        <p className="muted">
          This chain is not configured yet. Update <code>frontend/config/addresses.ts</code>.
        </p>
      </main>
    );
  }

  const availableTokens = tokens[chainKey];
  const tokenMeta = availableTokens.find((t) => t.address.toLowerCase() === tokenAddr.toLowerCase()) ?? defaultTok;

  const planTokenMeta =
    availableTokens.find((t) => t.address.toLowerCase() === planToken.toLowerCase()) ?? defaultTok;

  return (
    <main className="row" style={{ flexDirection: "column", gap: 16 }}>
      <div className="card">
        <h2 style={{ marginTop: 0 }}>Merchant</h2>
        <p className="muted" style={{ marginTop: 6 }}>
          Merchant features: create plans and pause/unpause plans. (A real product would likely have a dedicated
          dashboard + pricing UI.)
        </p>
        {!isConnected ? (
          <p className="muted">Connect a wallet to manage plans.</p>
        ) : mismatch ? (
          <p className="muted">
            Wallet is on chainId <code>{walletChainId}</code>. Switch to <code>{chain.id}</code> in the nav.
          </p>
        ) : (
          <p className="muted">Connected wallet: {address}</p>
        )}
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>View / manage existing plan</h3>
        <div className="row">
          <div>
            <div className="muted">PlanId</div>
            <input className="input" value={planId} onChange={(e) => setPlanId(e.target.value)} />
          </div>
        </div>

        <div className="row" style={{ marginTop: 12 }}>
          <div>
            <div className="muted">Merchant</div>
            <code>{planMerchant}</code>
          </div>
          <div>
            <div className="muted">Token</div>
            <code>{planToken}</code>
          </div>
          <div>
            <div className="muted">Price</div>
            <div>
              {fmtUnits(planPrice, planTokenMeta.decimals)} {planTokenMeta.symbol}
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
          <div>
            <div className="muted">Created</div>
            <div>{fmtTs(createdAt)}</div>
          </div>
        </div>

        <div className="row" style={{ marginTop: 14 }}>
          <button
            className="btn"
            disabled={!isConnected || mismatch || busy}
            onClick={() => plan.refetch()}
          >
            Refresh
          </button>
          <button
            className="btn"
            disabled={!isConnected || mismatch || busy || !planActive}
            onClick={() =>
              runTx("pause", {
                address: openSub,
                abi: openSubAbi,
                functionName: "setPlanActive",
                args: [planIdBig, false],
              })
            }
          >
            Pause plan
          </button>
          <button
            className="btn"
            disabled={!isConnected || mismatch || busy || planActive}
            onClick={() =>
              runTx("unpause", {
                address: openSub,
                abi: openSubAbi,
                functionName: "setPlanActive",
                args: [planIdBig, true],
              })
            }
          >
            Unpause plan
          </button>
        </div>
      </div>

      <div className="card">
        <h3 style={{ marginTop: 0 }}>Create a new plan</h3>
        <p className="muted" style={{ marginTop: 6 }}>
          Calls <code>createPlan(token, price, interval, collectorFeeBps)</code>. On testnet, prefer small intervals
          (e.g. 300s) so you can demo renewals quickly.
        </p>

        <div className="row">
          <div>
            <div className="muted">Token</div>
            <select className="input" value={tokenAddr} onChange={(e) => setTokenAddr(e.target.value)}>
              {availableTokens.map((t) => (
                <option key={t.address} value={t.address}>
                  {t.symbol} ({t.address.slice(0, 6)}…{t.address.slice(-4)})
                </option>
              ))}
            </select>
          </div>
          <div>
            <div className="muted">Price ({tokenMeta.symbol})</div>
            <input className="input" value={priceHuman} onChange={(e) => setPriceHuman(e.target.value)} />
          </div>
          <div>
            <div className="muted">Interval seconds</div>
            <input className="input" value={intervalSec} onChange={(e) => setIntervalSec(e.target.value)} />
          </div>
          <div>
            <div className="muted">Collector fee (bps)</div>
            <input className="input" value={feeBps} onChange={(e) => setFeeBps(e.target.value)} />
          </div>
        </div>

        <div className="row" style={{ marginTop: 14 }}>
          <button
            className="btn btnPrimary"
            disabled={!isConnected || mismatch || busy}
            onClick={() => {
              // Validate + parse form
              let priceRaw: bigint;
              let intervalRaw: bigint;
              let feeRaw: bigint;
              try {
                priceRaw = parseUnits(priceHuman, tokenMeta.decimals);
                intervalRaw = BigInt(intervalSec);
                feeRaw = BigInt(feeBps);
              } catch (e) {
                setErrMsg(`Invalid inputs: ${String(e)}`);
                return;
              }
              runTx("createPlan", {
                address: openSub,
                abi: openSubAbi,
                functionName: "createPlan",
                args: [tokenAddr as `0x${string}`, priceRaw, intervalRaw, feeRaw],
              });
            }}
          >
            Create plan
          </button>
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
