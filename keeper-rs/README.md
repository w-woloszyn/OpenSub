# OpenSub Keeper (Milestone 5)

This folder contains a **Rust keeper bot** that makes recurring payments "real" by:

1. Scanning `Subscribed` events from an OpenSub deployment.
2. Tracking discovered `subscriptionId`s in a local state file.
3. Polling `isDue(subscriptionId)` and calling `collect(subscriptionId)` when due.

It is intentionally **backend-only** (no UI required) and is designed to be **non-conflicting** with upcoming Milestone 6 (ERC-4337):

- The keeper sends normal EOA transactions for `collect()`.
- Milestone 6 (AA) will focus on **user onboarding / subscribe flows**; `collect()` remains permissionless.

Milestone 5.1 adds "elite ops" guardrails:

- **Prechecks** before sending `collect()`:
  - plan is active
  - subscriber has enough token allowance to OpenSub for the plan price
  - subscriber has enough token balance for the plan price
- Optional **eth_call simulation** of `collect()` (enabled by default) to avoid sending txs that would revert.
- **Per-subscription backoff** persisted in the state file, so the keeper won’t spam retries for paused plans or unpaid subscribers.

---

## Quick start

### Prereqs
- Rust stable + Cargo
- A funded keeper EOA private key (Base Sepolia ETH for gas)
- A deployment artifact JSON (e.g., `deployments/base-sepolia.json`) that contains:
  - `chainId`
  - `openSub`
  - `startBlock`

Optional (recommended):
- `rpcEnvVar` instead of `rpc`, so you don't commit provider API keys.

### Run (Base Sepolia)
From the **repo root**:

```bash
export KEEPER_PRIVATE_KEY="<your funded key>"
# optional override if your deployments file doesn't include RPC
export OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org"

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/base-sepolia.json \
  --poll-seconds 30 \
  --confirmations 2 \
  --log-chunk 2000
```

- State will be written to `keeper-rs/state/state.json` by default.
- Use `RUST_LOG=info` (or `debug`) for more logs.

### Run once (single cycle)

```bash
export KEEPER_PRIVATE_KEY="<your funded key>"
export OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org"

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/base-sepolia.json \
  --once
```

### Dry run

```bash
export KEEPER_PRIVATE_KEY="<your funded key>"
export OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org"

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/base-sepolia.json \
  --dry-run --once
```

---

## Local Anvil demo

1) Start Anvil

```bash
anvil
```

2) Deploy and seed subscriptions (example)

```bash
# in another terminal
export ETH_RPC_URL=http://127.0.0.1:8545
export PLAN_INTERVAL_SECONDS=60
export SUBSCRIBER_PK=<anvil subscriber pk>

forge script script/DemoScenario.s.sol \
  --rpc-url $ETH_RPC_URL \
  --private-key <anvil merchant pk> \
  --broadcast -vvv
```

3) Run keeper against Anvil

Create (or edit) a deployment artifact for anvil, e.g. `deployments/anvil.json`, then:

```bash
export KEEPER_PRIVATE_KEY=<anvil collector pk>

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/anvil.json \
  --rpc-url http://127.0.0.1:8545 \
  --poll-seconds 5 \
  --confirmations 0 \
  --log-chunk 500
```

---

## Operational notes

- **Chunked log scanning:** Many RPC providers limit `eth_getLogs` ranges. If you see timeouts, reduce `--log-chunk`.
- **Confirmations:** On testnets, `--confirmations 1-2` is usually enough.
- **Gas limit:** If gas estimation is flaky with your RPC, set `--gas-limit 500000`.
- **Safety valves:**
  - `--max-txs-per-cycle` caps how many `collect()` txs are submitted per loop.
  - `--tx-timeout-seconds` controls how long we wait for a receipt before treating a tx as in-flight.
  - `--pending-ttl-seconds` drops very old in-flight txs so the keeper can retry.

### Milestone 5.1 backoff

When a subscription is due but cannot be charged, the keeper records a failure and backs off.
The backoff state is persisted in `keeper-rs/state/state.json` under `retries`.

Defaults (override via CLI flags):

- `--backoff-base-seconds 300` (5 minutes) for insufficient allowance/balance or generic failures
- `--plan-inactive-backoff-seconds 1800` (30 minutes) for paused plans
- `--rpc-error-backoff-seconds 30` for transient RPC errors
- `--backoff-max-seconds 21600` (6 hours) cap
- `--jitter-seconds 30` deterministic jitter window to avoid thundering herd

To disable the simulation guardrail (not recommended):

```bash
... --no-simulate
```

To temporarily ignore the persisted backoff state (debugging only):

```bash
... --ignore-backoff
```

---

## Next: Milestone 6 (ERC-4337)

Milestone 6 will add an **AA subscribe flow** (approve + subscribe batched in a UserOperation and optionally sponsored).

This keeper is independent:
- It only calls `collect()`, which remains permissionless.
- If you later want the keeper to submit `collect()` via ERC-4337, you can add a second tx backend without changing the on-chain protocol.

---

## Docker

Build from repo root:

```bash
docker build -f keeper-rs/Dockerfile -t opensub-keeper:local .
```

Run (mount your repo so it can read `deployments/` and write `keeper-rs/state/`):

```bash
docker run --rm -it \
  -e KEEPER_PRIVATE_KEY="<key>" \
  -e OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org" \
  -e RUST_LOG=info \
  -v "$PWD:/work" \
  opensub-keeper:local \
  --deployment deployments/base-sepolia.json
```
