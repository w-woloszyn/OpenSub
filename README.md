# OpenSub — Minimal on-chain subscriptions (Foundry)

OpenSub is a small, auditable subscription primitive:

- Merchants create plans `(token, price, interval, collectorFeeBps)`
- Subscribers authorize recurring charges via ERC20 allowance
- Anyone can execute renewals via `collect()` (optionally earning a collector fee)
- No custody during collection: tokens move directly from subscriber → merchant/collector

This repo is organized as a set of milestones:
- **Milestone 1 (market research + product definition):** `docs/MILESTONE1.md`
- **Milestone 2 (protocol implementation):** `src/OpenSub.sol`
- **Milestone 3 (Foundry tests: unit + fuzz + invariants):** `test/` + `docs/SPEC.md` + `docs/THREAT_MODEL.md`
- **Milestone 4 (frontend handoff / demo deploy UX):** `docs/FRONTEND_HANDOFF.md` + `frontend/` + `script/DeployDemo.s.sol`
- **Milestone 5 (keeper bot / automation):** `keeper-rs/` (Rust)
- **Milestone 6A (ERC-4337 AA subscribe CLI):** `aa-rs/` (Rust)

⚠️ Not audited. Use at your own risk.

---

## What’s included (contract surface)
- `createPlan(token, price, interval, collectorFeeBps)`
- `setPlanActive(planId, active)`
- `subscribe(planId)` (charges immediately for first period)
- `cancel(subscriptionId, atPeriodEnd)`
- `unscheduleCancel(subscriptionId)`
- `collect(subscriptionId)` (anyone can call; earns optional collector fee)
- `hasAccess(subscriptionId)` view helper

## Key semantics
- `paidThrough` = end timestamp of the currently-paid access period.
- If `status == Active`, the subscription is due when `block.timestamp >= paidThrough`.
- If `status == NonRenewing`, auto-renew is disabled but access remains valid until `paidThrough`.
  - **Pattern A cancellation**: no on-chain “finalize cancel” transaction is required later.

See `docs/SPEC.md` for the frozen behavior that Milestone 3 tests enforce.

---

## Quick start (Foundry)

### 1) Install deps

```bash
./script/install_deps.sh
```

Notes:
- This uses `forge install --no-git` so it works even if you downloaded a zip snapshot.
- You still need `git` installed because `forge install` clones dependencies.

### 2) Build & test

```bash
forge build
forge test
```

---

## Deploy demo (Milestone 4)

This repo includes demo deployment scripts that are useful for frontend developers.

### DeployDemo (deploy + plan + optional subscriber mint)

- Deploys `MockERC20` as **mUSDC** (6 decimals)
- Deploys `OpenSub`
- Creates a default plan
- Mints demo tokens to the plan merchant
- Optionally mints demo tokens to a second wallet address (set `SUBSCRIBER=0x...`)
- Prints contract addresses + a **paste-ready snippet** for:
  - `frontend/config/addresses.ts`
  - `frontend/config/tokens.ts`

Local Anvil:

```bash
anvil

./script/install_deps.sh
SUBSCRIBER=0xYourSubscriberAddressHere \
forge script script/DeployDemo.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_MERCHANT_PRIVATE_KEY> \
  --broadcast -vvv
```

Base testnet:

```bash
./script/install_deps.sh
forge script script/DeployDemo.s.sol \
  --rpc-url <BASE_TESTNET_RPC_URL> \
  --private-key <YOUR_PRIVATE_KEY> \
  --broadcast -vvv
```

### DemoScenario (deploy + plan + subscribe + optional renewal on Anvil)

`DemoScenario` is especially useful because it creates real on-chain events (`PlanCreated`, `Subscribed`, `Charged`) that the UI can query via logs.

Local Anvil (seeded scenario):

```bash
anvil

export ETH_RPC_URL=http://127.0.0.1:8545
./script/install_deps.sh

# required to perform approve+subscribe
export SUBSCRIBER_PK=<ANVIL_SUBSCRIBER_PRIVATE_KEY>

# optional: auto-advance time + mine on Anvil (requires --ffi)
export USE_FFI=1

forge script script/DemoScenario.s.sol \
  --rpc-url $ETH_RPC_URL \
  --private-key <ANVIL_MERCHANT_PRIVATE_KEY> \
  --broadcast --ffi -vvv
```

Base testnet (deploy + subscribe only):

```bash
./script/install_deps.sh
export SUBSCRIBER_PK=<FUNDED_SUBSCRIBER_PRIVATE_KEY>

forge script script/DemoScenario.s.sol \
  --rpc-url <BASE_TESTNET_RPC_URL> \
  --private-key <MERCHANT_PRIVATE_KEY> \
  --broadcast -vvv
```

### Demo-friendly plan parameters (recommended for testnet)

On public testnets you can’t warp time. If you want to demo renewals quickly, override the default plan interval.

Both `DeployDemo` and `DemoScenario` accept optional env overrides:

- `PLAN_PRICE` (uint256)
- `PLAN_INTERVAL_SECONDS` (uint40)
- `PLAN_COLLECTOR_FEE_BPS` (uint16)

Example (5 minute interval):

```bash
PLAN_INTERVAL_SECONDS=300 \
forge script script/DeployDemo.s.sol --rpc-url ... --private-key ... --broadcast -vvv
```

---

## Frontend handoff

Frontend handoff docs + ABI/config templates live in:
- `docs/FRONTEND_HANDOFF.md`
- `docs/MILESTONE4_REQUIREMENTS.md`
- `docs/UI_STATE_MACHINE.md`
- `docs/ALLOWANCE_POLICY.md`
- `frontend/abi/*` and `frontend/config/*`

---

## Keeper bot (Milestone 5)

Milestone 5 adds a backend **keeper** that scans `Subscribed` logs and calls `collect()` when subscriptions are due.

Milestone 5.1 hardens the keeper with:
- allowance/balance/plan-active **prechecks** (no gas wasted on obvious reverts)
- optional `eth_call` simulation of `collect()` (enabled by default)
- persisted per-subscription **backoff** (so paused plans / unpaid users don’t get spammed)

See:
- `docs/MILESTONE5.md`
- `docs/MILESTONE5_1.md`
- `keeper-rs/README.md`

Quick run (Base Sepolia):

```bash
export KEEPER_PRIVATE_KEY="<funded EOA key>"
export OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org"

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/base-sepolia.json \
  --poll-seconds 30 \
  --confirmations 2 \
  --log-chunk 2000
```

## Remappings

`foundry.toml` includes:

```toml
remappings = [
  "@openzeppelin/=lib/openzeppelin-contracts/",
  "forge-std/=lib/forge-std/src/"
]
```

---

## Tests & mocks

Unit + fuzz + invariant tests live in `test/`:

- `test/OpenSubPlan.t.sol` (plan creation / pause semantics)
- `test/OpenSubSubscribe.t.sol` (subscribe semantics + OpenSub event ordering)
- `test/OpenSubCollect.t.sol` (renewals, fee logic, late renewal policy)
- `test/OpenSubCancel.t.sol` (Pattern A cancellation + unschedule)
- `test/OpenSubTokenFailures.t.sol` (rollback on token failures)
- `test/OpenSubReentrancy.t.sol` (reentrancy attempt blocked)
- `test/invariant/OpenSubInvariant.t.sol` (stateful invariants)
- `test/OpenSubSmoke.t.sol` (simple end-to-end smoke test)

Mocks in `src/mocks/`:

- `MockERC20.sol` (mintable ERC20)
- `ToggleFailERC20.sol` (can revert / return false after toggling)
- `ReentrantERC20.sol` (attempts to re-enter OpenSub during transferFrom)
- `ReturnsFalseERC20.sol` (always returns false)
- `RevertingERC20.sol` (always reverts)

## One-command local demo (Anvil → DemoScenario → keeper)

Run:

```bash
make demo-local
```

This will:
- start a local Anvil node
- deploy + seed a subscription via `DemoScenario`
- warp time so it becomes due
- run the Rust keeper once so it calls `collect()` and emits a renewal `Charged` event

Artifacts are written under `./.secrets/` (gitignored).

## Keeper self-test (Milestone 5.1)

Run:

```bash
make keeper-self-test
```

This is an automated proof that the keeper:

1) **Does not** send a reverting `collect()` tx when allowance is insufficient (it records backoff instead).
2) Retries after backoff and successfully collects once allowance is restored.

All temporary artifacts are written under `./.secrets/` (gitignored).
