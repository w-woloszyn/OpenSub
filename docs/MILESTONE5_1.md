# Milestone 5.1 — Keeper reliability (prechecks + backoff)

Milestone 5.1 hardens the Milestone 5 keeper so it behaves like production-grade automation:

- avoids wasting gas on `collect()` transactions that would revert
- avoids hammering RPCs when a subscription can’t be collected yet
- persists retry state so restarts don’t reset failure throttling

This is **backend-only** and does **not** touch any Milestone 6A / 6B (ERC‑4337) plans.

---

## Why Milestone 5 needed 5.1

On-chain, `collect(subscriptionId)` can revert even when `isDue(subscriptionId)` is true, for example:

- the plan was paused (`PlanInactive`)
- the subscriber doesn’t have enough token balance
- the subscriber doesn’t have enough token allowance to the OpenSub contract

A naive keeper would:

- send a transaction anyway
- pay gas
- revert
- repeat every poll

Milestone 5.1 prevents that.

---

## What changed

### 1) Prechecks before sending `collect()`
For each due subscription, the keeper now checks:

- subscription is still `Active`
- plan is still `active`
- ERC20 `allowance(subscriber, openSub) >= price`
- ERC20 `balanceOf(subscriber) >= price`

If any check fails, **no transaction is sent**.

### 2) Optional `eth_call` simulation
Even after prechecks, there can be races (another keeper collected, plan paused, etc.).

By default the keeper runs a final guardrail:

- `eth_call` simulate `collect(subscriptionId)`

If simulation reverts, the keeper backs off instead of sending a reverting tx.

Disable (not recommended):

```bash
--no-simulate
```

Debug override (not recommended for normal operation):

```bash
--ignore-backoff
```

### 3) Per-subscription backoff persisted to disk
Failures are recorded under `retries` in:

- `keeper-rs/state/state.json`

Backoff is exponential with a max cap + deterministic jitter.

Defaults:

- base backoff: `300s`
- plan inactive backoff: `1800s`
- rpc error backoff: `30s`
- max backoff: `21600s`
- jitter: `30s`

Override with flags:

- `--backoff-base-seconds`
- `--plan-inactive-backoff-seconds`
- `--rpc-error-backoff-seconds`
- `--backoff-max-seconds`
- `--jitter-seconds`

---

## Definition of done

Milestone 5.1 is complete when:

1) A subscription that is due but **unpayable** (no allowance or balance) does **not** produce a reverted on-chain tx.
2) The keeper logs a failure and records a future `nextRetryAt` in its state file.
3) After the subscriber fixes the issue (approve/fund), the keeper retries after backoff and successfully collects.
4) A paused plan does not cause repeated reverted txs.

---

## Local demo

Use the one-command demo:

```bash
make demo-local
```

To test backoff behavior manually:

1) Run demo once to deploy + subscribe.
2) Re-run with subscriber allowance intentionally reduced (or skip approve in your script).
3) Confirm keeper does not send a reverting tx and records backoff.


---

## Automated self-test

To prove Milestone 5.1’s safety properties end-to-end (no reverted tx spam + backoff + eventual success), run:

```bash
make keeper-self-test
```

This will:

1) Start Anvil and run `DemoScenario` to deploy + create a plan + subscribe.
2) Warp time so the subscription becomes due.
3) **Break allowance** (`approve(openSub, 0)`) and run the keeper once.
   - Asserts: `isDue` remains `true`, merchant token balance is unchanged, and the keeper state records a `retries` entry with `lastFailureKind = insufficientAllowance`.
4) **Restore allowance** (approve exactly the plan price), wait for the short self-test backoff to elapse, and run the keeper again.
   - Asserts: `isDue` becomes `false` (collected) and the `retries` entry is cleared.

By default, this uses a tiny backoff window (`SELFTEST_BACKOFF_SECONDS=2`) so the test completes quickly.

You can override:

```bash
PLAN_INTERVAL_SECONDS=10 SELFTEST_BACKOFF_SECONDS=1 make keeper-self-test
```
