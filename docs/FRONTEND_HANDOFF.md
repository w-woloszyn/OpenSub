# OpenSub Frontend Handoff

This repo contains everything a frontend developer needs to build **Milestone 4 (Reference App)** on top of the OpenSub Foundry repo.

## Goal
Deliver a small web app that works end-to-end on:
- **Local Anvil** (fast dev + time travel)
- **Base testnet** (demo)

The app must support:
- Merchant: create & pause plans; view plan activity
- Subscriber: approve allowance, subscribe, view status/access, cancel (Pattern A), resume (unschedule), renew (collect)
- Collector: manually call `collect()` for due subs (Milestone 5 automation comes later)

## What you need from the backend repo
- `src/OpenSub.sol` (already present)
- Deployed contract addresses (per chain)
- A token contract to use on each chain:
  - Local: deploy `MockERC20` as “mUSDC” (6 decimals)
  - Base testnet: deploy the same `MockERC20` (recommended for reliable demo)

## Inputs the backend (you) must provide to the frontend dev
Put these into `.env.local` (preferred) **or** `frontend/config/addresses.ts` / `frontend/config/tokens.ts`:

**Addresses / start blocks**
- `NEXT_PUBLIC_OPENSUB_ADDRESS_LOCAL`
- `NEXT_PUBLIC_OPENSUB_DEPLOY_BLOCK_LOCAL`
- `NEXT_PUBLIC_OPENSUB_ADDRESS_BASE_TESTNET`
- `NEXT_PUBLIC_OPENSUB_DEPLOY_BLOCK_BASE_TESTNET`

Notes:
- The “deploy block” is effectively a **start block for log scanning**.
- It is safe (and sometimes safer) to set it **slightly earlier** than the true deployment block.

**Default tokens (optional, but recommended)**
- `NEXT_PUBLIC_DEFAULT_TOKEN_LOCAL`
- `NEXT_PUBLIC_DEFAULT_TOKEN_BASE_TESTNET`

See `env.example` for the exact variable names.

---

## Install deps (if you downloaded a ZIP)

```bash
./script/install_deps.sh
```

Notes:
- The script uses `forge install --no-git` so it works even if this folder is **not** a git repo.
- You still need `git` installed because `forge install` clones dependencies.

---

## Deploying demo contracts (recommended)

Use `script/DeployDemo.s.sol` to deploy everything the frontend needs on a chain:

- Demo token: `MockERC20` deployed as **mUSDC** (6 decimals)
- `OpenSub`
- A **default plan** (price + interval + collector fee)

The script prints:
- OpenSub address
- token address
- a **safe log-scan start block**
- default `planId`

It also prints a **paste-ready snippet** for:
- `frontend/config/addresses.ts`
- `frontend/config/tokens.ts`

### Optional: mint to a second “subscriber” wallet

So a frontend dev can test merchant vs subscriber flows without building a faucet UI:

- Set `SUBSCRIBER=0x...` before running the script (or `SUBSCRIBER_PK=<uint256>` to derive an address)

### Optional: demo-friendly plan params (especially for Base testnet)

Defaults:
- `PLAN_PRICE=10_000_000` (10.000000 mUSDC)
- `PLAN_INTERVAL_SECONDS=2592000` (30 days)
- `PLAN_COLLECTOR_FEE_BPS=100` (1%)

On public testnets you can’t warp time, so if you want to demo renewals quickly, set a shorter interval:

```bash
PLAN_INTERVAL_SECONDS=300 \
forge script script/DeployDemo.s.sol --rpc-url ... --private-key ... --broadcast -vvv
```

### Local Anvil (dev loop)

1) Start Anvil:

```bash
anvil
```

2) Deploy demo contracts (in another terminal):

```bash
./script/install_deps.sh
SUBSCRIBER=0xYourSubscriberAddressHere \
forge script script/DeployDemo.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_ACCOUNT_PRIVATE_KEY> \
  --broadcast -vvv
```

### Base testnet (demo)

```bash
./script/install_deps.sh
forge script script/DeployDemo.s.sol \
  --rpc-url <BASE_TESTNET_RPC_URL> \
  --private-key <YOUR_PRIVATE_KEY> \
  --broadcast -vvv
```

Copy the printed values into:
- `env.example` / `.env.local` (preferred), or
- `frontend/config/addresses.ts` + `frontend/config/tokens.ts`

Tip: look for the section titled **"Paste-ready config snippets"** in the script output.

---

## Demo scenario (recommended for frontend devs)

If you want the frontend dev to have **real on-chain events** (Subscribed + Charged, and optionally a second Charged from renewal), use:

- `script/DemoScenario.s.sol`

This script:
- deploys `mUSDC` + `OpenSub`
- creates a default plan
- mints tokens to merchant + subscriber
- has the subscriber **approve + subscribe** (creates `Subscribed` + initial `Charged`)
- on local Anvil, it can also **advance time + renew** (creates another `Charged`) if you enable FFI

### Local Anvil (best UX, generates events automatically)

```bash
anvil
```

In another terminal:

```bash
export ETH_RPC_URL=http://127.0.0.1:8545

./script/install_deps.sh

# Use an Anvil pre-funded account as the subscriber
export SUBSCRIBER_PK=<ANVIL_SUBSCRIBER_PRIVATE_KEY>

# Optional but recommended: let the script advance time + mine on Anvil
export USE_FFI=1
export DO_RENEWAL=1

forge script script/DemoScenario.s.sol \
  --rpc-url $ETH_RPC_URL \
  --private-key <ANVIL_MERCHANT_PRIVATE_KEY> \
  --broadcast --ffi -vvv
```

### Base testnet (deploy + subscribe only)

On public networks you cannot advance time. The script will still deploy + subscribe if you provide a funded subscriber key:

```bash
./script/install_deps.sh
export SUBSCRIBER_PK=<FUNDED_SUBSCRIBER_PRIVATE_KEY>

forge script script/DemoScenario.s.sol \
  --rpc-url <BASE_TESTNET_RPC_URL> \
  --private-key <MERCHANT_PRIVATE_KEY> \
  --broadcast -vvv
```

If you don’t want the script to subscribe on testnet, omit `SUBSCRIBER_PK` and it will only deploy + create the plan.

---

## Print config snippets only (no deploy)

If you already deployed OpenSub + token and just want paste-ready config blocks, use:

- `script/PrintFrontendConfig.s.sol`

Example:

```bash
OPENSUB_ADDRESS=0x... \
OPENSUB_DEPLOY_BLOCK=123456 \
TOKEN_ADDRESS=0x... \
forge script script/PrintFrontendConfig.s.sol --rpc-url <RPC_URL> -vvv
```

This prints the `addresses.ts` + `tokens.ts` blocks (and an optional `.env.local` snippet).

---

## Core contract semantics the UI MUST match

### SubscriptionStatus enum values
The ABI returns `status` as a `uint8`. Map it as:
- `0 = None` (unused)
- `1 = Active`
- `2 = NonRenewing`
- `3 = Cancelled`

### Time semantics
- `paidThrough`: end timestamp of paid access
- Status:
  - `Active`: auto-renew enabled; due if `now >= paidThrough`
  - `NonRenewing`: auto-renew disabled; access remains until `paidThrough`
  - `Cancelled`: ended immediately

### Safe resubscribe rule (important)
- If an existing subscription is `Active`, **resubscribe is blocked even if access expired**.
- The user should renew via `collect()` (or cancel and then subscribe again).

See: `docs/UI_STATE_MACHINE.md` for exact UI behavior per state.

---

## Recommended stack
- Next.js + TypeScript
- wagmi/viem for wallet + contract calls
- A minimal component library (optional)
- No backend required for Milestone 4 (use on-chain reads + event logs)


---

## Log scanning (important for Base testnet)
This UI relies on on-chain events (`PlanCreated`, `Subscribed`, `Charged`) via `eth_getLogs`.

Public RPCs often reject large log ranges. Implement **chunked log scanning** and retries.

See: `docs/LOG_SCANNING.md`

## BigInt handling (viem/wagmi)
If you use **viem**, all integer values return as `bigint`:
- token balances / allowances (`uint256`)
- timestamps (`uint40`) like `paidThrough`, `startTime`
- `collectorFeeBps` (`uint16`)

UI guidance:
- Keep amounts as `bigint` in state
- Convert for display with helpers (e.g., `formatUnits(amount, decimals)`)
- Convert timestamps with `new Date(Number(tsBigInt) * 1000)` (safe for uint40)
## Definition of done for Milestone 4

Milestone 4 is complete when:
- Merchant can create a plan and share a checkout link
- Subscriber can approve + subscribe and see access data update
- After `paidThrough` passes, subscriber can renew via `collect()`
- Subscriber can cancel at period end (Pattern A) and resume
- Works on Local Anvil + Base testnet
