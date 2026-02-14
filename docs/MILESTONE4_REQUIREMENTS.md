# Milestone 4 Requirements (Reference App)

Target networks:
- Local Anvil (dev)
- Base testnet (demo)

## Pages (minimum)
1) `/merchant`
   - Create plan
   - List my plans (filter PlanCreated by merchant address)
2) `/merchant/plan/[planId]`
   - Show plan details (plans(planId))
   - Pause/unpause (setPlanActive)
   - Show recent activity from events:
     - Subscribed
     - Charged
3) `/checkout/[planId]`
   - Subscriber checkout
   - Handles allowance + subscribe + state machine
4) `/me`
   - My subscriptions:
     - Query Subscribed events where subscriber==me (or store locally)
     - Show current status by reading subscriptions(id)
5) `/subscription/[subscriptionId]`
   - Details + actions (renew/cancel/resume)

## Required UI components
- Wallet connect + network guard
- Transaction status UI (pending/confirmed/reverted)
- Amount formatting with token decimals
- Allowance panel (see `docs/ALLOWANCE_POLICY.md`)
  - Recommended default: approve `price * 12` periods
- State machine rendering (see `docs/UI_STATE_MACHINE.md`)

## Data sources
- Reads:
  - plans(planId)
  - subscriptions(subscriptionId)
  - activeSubscriptionOf(planId, user)
  - hasAccess(subscriptionId)
  - isDue(subscriptionId)
  - computeCollectorFee(planId) (optional display)
- Events (via RPC `getLogs`):
  - PlanCreated (filter by merchant)
  - Subscribed (filter by planId or subscriber)
  - Charged (filter by planId or subscriptionId)

Note:
- Implement **chunked log scanning** for events on public RPCs (Base testnet), otherwise `eth_getLogs` may fail on large ranges.
- See `docs/LOG_SCANNING.md`.

## Acceptance criteria (E2E demo)

### Local Anvil
- Deploy mUSDC + OpenSub
- Merchant creates a plan
- Subscriber approves + subscribes
- Warp time / advance, then renew via collect
- Cancel at period end (NonRenewing) and verify access stays until paidThrough
- Unschedule cancel to resume

### Base testnet
- Deploy mUSDC + OpenSub
- Merchant creates a plan
- Subscriber approves + subscribes
- Confirm event log queries work (PlanCreated + Charged visible in UI)

Optional (recommended for demos):
- If you want to demo renewals on Base testnet without waiting 30 days, deploy a plan with a short interval.
  - Example: set `PLAN_INTERVAL_SECONDS=300` when running `DeployDemo`.

## Non-goals (Milestone 4)
- ERC-4337 / gasless
- Automation bot / Gelato
- Mainnet deployment
- Full analytics pipeline

## Notes
- The contract intentionally blocks resubscribe when existing subscription is Active (even if expired).
  UI must route to Renew (collect) instead.
