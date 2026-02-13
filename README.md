# OpenSub (Milestone 2 — Expert hardened, M3-ready)

Minimal on-chain subscription primitive (Solidity) with a Milestone 3 test scaffold.

## Milestone 1 (market + product definition)

Milestone 1 is captured in `docs/MILESTONE1.md` (problem statement, market tailwinds, competitor scan, positioning, requirements, validation plan).

## What’s included
- `createPlan(token, price, interval, collectorFeeBps)`
- `setPlanActive(planId, active)`
- `subscribe(planId)` (charges immediately for first period)
- `cancel(subscriptionId, atPeriodEnd)`
- `unscheduleCancel(subscriptionId)`
- `collect(subscriptionId)` (anyone can call; earns optional collector fee)
- `hasAccess(subscriptionId)` view helper

## Key semantics
- `paidThrough` = end timestamp of the currently-paid access period.
- If `status == Active`, the subscription auto-renews when `block.timestamp >= paidThrough`.
- If `status == NonRenewing`, auto-renew is disabled but access remains valid until `paidThrough`.
  - **Pattern A cancellation**: no on-chain “finalize cancel” transaction is required later.

See `docs/SPEC.md` for the frozen behavior that Milestone 3 tests should enforce.

## Quick start (Foundry)

### 1) Install deps

```bash
./script/install_deps.sh
```

This installs:
- OpenZeppelin contracts (SafeERC20, ReentrancyGuard)
- forge-std (tests & scripts)

### 2) Build & test

```bash
forge build
forge test
```

## Remappings

`foundry.toml` includes:

```toml
remappings = [
  "@openzeppelin/=lib/openzeppelin-contracts/",
  "forge-std/=lib/forge-std/src/"
]
```

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

## Notes / MVP behavior
- `collectorFeeBps` is taken out of the plan price (merchant receives `price - fee`).
- **Initial charge on `subscribe()` does NOT pay a collector fee**.
- Collector fee is **not paid** when the collector is the subscriber (best-effort mitigation).
- Plan pause stops new subscriptions and charging for existing subscriptions.
- `paidThrough` is advanced using `max(oldPaidThrough, now) + interval` so it does not remain in the past after a successful charge.
- Payments are transferred directly from subscriber to merchant/collector (contract does not custody funds during collection).

⚠️ Not audited. Use at your own risk.
