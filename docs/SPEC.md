# OpenSub – Milestone 2 Specification (M3-Ready)

This document freezes the intended behavior for Milestone 3 tests.

## Terminology

- **Plan**: merchant-defined pricing & schedule (token, price, interval).
- **Subscription**: a subscriber's enrollment in a plan.
- **Collector**: any address calling `collect()` to execute a renewal.

## Plan semantics

- `createPlan(token, price, interval, collectorFeeBps)` creates an active plan.
- `setPlanActive(planId, false)` pauses the plan:
  - new subscriptions are blocked
  - `collect()` is blocked
  - subscriber cancellations remain possible (they do not depend on plan status)

### Token assumptions (MVP)
OpenSub targets "normal" ERC20s (e.g., USDC-like stablecoins).

Known non-goals for Milestone 2:
- fee-on-transfer tokens
- rebasing tokens
- tokens with nonstandard return values (other than OZ SafeERC20 handling)

## Subscription semantics

### Statuses
- `Active`: auto-renew enabled.
- `NonRenewing`: Pattern A cancel-at-period-end. Auto-renew disabled; access remains until `paidThrough`.
- `Cancelled`: ended immediately (access ends at cancel time).

### Access
- A subscription grants access when:
  - `status` is `Active` or `NonRenewing`, AND
  - `block.timestamp < paidThrough`

### paidThrough / renewal
- `paidThrough` is the end of the currently-paid access period.
- A renewal is **due** when `block.timestamp >= paidThrough` and status is `Active`.

**Late renewal policy (expert default):**

On a successful renewal, the next paid period starts at:

- `base = max(oldPaidThrough, now)`
- `newPaidThrough = base + interval`

This ensures `paidThrough` is never "stuck" in the past after a charge and prevents rapid multi-charge catch-up.

### One active subscription per plan per subscriber (MVP invariant)
- At most one "current" subscription exists per `(planId, subscriber)`.
- `activeSubscriptionOf[planId][subscriber]` points to that subscription.
- A new subscription is blocked when the existing subscription still grants access.

## Cancellation (Pattern A)

`cancel(subscriptionId, atPeriodEnd)`:

- `atPeriodEnd=false`: immediate cancellation.
  - status becomes `Cancelled`
  - access ends immediately
  - `activeSubscriptionOf` pointer is cleared (defensively)

- `atPeriodEnd=true`: disable auto-renew **without** requiring a later "finalize" transaction.
  - if access is still active (`now < paidThrough`), status becomes `NonRenewing`
  - if already due/overdue (`now >= paidThrough`), treated as immediate cancellation

`unscheduleCancel(subscriptionId)`:
- only valid when status is `NonRenewing` AND `now < paidThrough`
- sets status back to `Active`

## Collector fee

- Collector fee is a percentage of `price`, paid from subscriber funds.
- Initial charge on `subscribe()` has collector fee **disabled**.
- Best-effort mitigation: if `collector == subscriber`, collector fee is disabled.
  - (This cannot prevent "rebate" behavior if subscriber routes through a second address.)

## Events

- `subscribe()` emits `Charged` (initial payment) and then `Subscribed`.
- `collect()` emits `Charged`.



## Test mapping (Milestone 3)

This repo includes a Foundry suite that encodes the above spec:

- Plan semantics: `test/OpenSubPlan.t.sol`
- Subscribe semantics + events: `test/OpenSubSubscribe.t.sol`
- Cancellation semantics (Pattern A): `test/OpenSubCancel.t.sol`
- Collector / renewals + late renewal policy: `test/OpenSubCollect.t.sol`
- Token failure rollback: `test/OpenSubTokenFailures.t.sol`
- Stateful invariants (pointer + paidThrough invariants): `test/invariant/OpenSubInvariant.t.sol`
