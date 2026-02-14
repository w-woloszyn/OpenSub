# UI State Machine (Must match OpenSub.sol)

Inputs:
- `plan = plans(planId)`
- `subId = activeSubscriptionOf(planId, user)`
- if `subId != 0`: `sub = subscriptions(subId)`
- `hasAccess = hasAccess(subId)` (contract view)
- `isDue = isDue(subId)` (contract view)

Allowance inputs (recommended):
- `price = plan.price`
- Choose `N` billing periods to pre-approve (default **12**) — see `docs/ALLOWANCE_POLICY.md`
- `targetAllowance = price * N`

## Plan-level state

### Plan Active
- Normal behavior.

### Plan Inactive
- Disable:
  - Subscribe
  - Renew (collect)
- Merchant should show “Plan paused” badge
- Subscriber should see: “This plan is paused; renewals are disabled.”

## Subscription-level state

### State S0: No current subscription
Condition:
- `subId == 0` OR subscription.status == Cancelled

UI:
- Show plan details
- Primary CTA (recommended flow):
  - If `allowance < targetAllowance`: “Approve” (approve `targetAllowance`)
  - Then: “Subscribe”

Notes:
- The contract only requires `allowance >= price` to subscribe, but pre-approving `price * N` avoids repeated approvals.

### State S1: Active + has access
Condition:
- `status == Active` AND `now < paidThrough`

UI:
- Show “Active (auto-renewing)”
- Show “Access until: paidThrough”
- Actions:
  - “Cancel at period end” => `cancel(subId, true)` (Pattern A => NonRenewing)
  - “Cancel now” => `cancel(subId, false)`
- Hide/disable Subscribe CTA (will revert AlreadySubscribed)

### State S2: Active + due (access expired)
Condition:
- `status == Active` AND `now >= paidThrough`

UI:
- Show “Payment due / access expired”
- Primary CTA: “Renew now” => `collect(subId)`
  - Enable if:
    - `allowance >= price` AND `balance >= price`
  - Otherwise show “Approve” first
- Secondary: “Cancel now” => `cancel(subId, false)`

IMPORTANT:
- Do not show “Subscribe” here; resubscribe is intentionally blocked for Active subs.

### State S3: NonRenewing + has access
Condition:
- `status == NonRenewing` AND `now < paidThrough`

UI:
- Show “Cancels at period end (won’t renew)”
- Show “Access until: paidThrough”
- Actions:
  - “Resume auto-renew” => `unscheduleCancel(subId)`
  - “Cancel now” => `cancel(subId, false)`
- Subscribe disabled (blocked until expiry)

### State S4: NonRenewing + expired
Condition:
- `status == NonRenewing` AND `now >= paidThrough`

UI:
- Show “Expired”
- Primary CTA: Approve (if needed) + Subscribe
- Note: contract will clear stale pointer automatically inside subscribe()

### State S5: Cancelled
Condition:
- `status == Cancelled`

UI:
- Same as S0 (No current subscription)
