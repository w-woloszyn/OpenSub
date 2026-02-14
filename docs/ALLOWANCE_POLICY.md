# Allowance UX Policy (Decision)

## What problem we are solving
Subscriptions require the OpenSub contract to call `transferFrom(subscriber, merchant, price)` at each renewal.
That means the subscriber must grant an ERC20 allowance to the OpenSub contract.

The allowance UX must:
- Minimize repeated approvals (friction)
- Avoid the default “infinite approval” footgun
- Still allow power users to choose unlimited

## Decision (recommended default)
**Default approval amount: cover 12 intervals** (≈ 1 year for monthly plans).

The UI should show:
- “Approve for 12 periods (recommended)”
- Advanced options: 1, 3, 12, Unlimited
- A “Revoke (set to 0)” action under advanced settings

### Why 12 intervals?
- Smooth UX (no monthly approvals)
- Still caps downside if OpenSub contract has a bug or merchant is malicious
- Common mental model for subscriptions (“annual allowance”)

## How to compute approval amount
Let:
- `price` = plan.price (base units)
- `N` = chosen number of periods (default 12)

Then:
- `targetAllowance = price * N`

Note:
- Subscribing charges immediately (consumes `price` from allowance).
- Approving `price * N` covers **N total charges** (initial + up to N-1 renewals).

Read:
- `currentAllowance = allowance(user, OpenSub)`

If `currentAllowance >= targetAllowance`: no approve needed.
Else: approve `targetAllowance`.

## Handling “approve must be 0 first” tokens
Some ERC20s require allowance to be set to 0 before changing it.

Implementation approach:
1) Try `approve(spender, targetAllowance)`
2) If tx fails with an “allowance change” error, prompt:
   - “This token requires resetting allowance to 0 first.”
   - Provide a 2-step flow:
     1) `approve(spender, 0)`
     2) `approve(spender, targetAllowance)`

For the demo tokens (MockERC20 / USDC-like), the 1-step path should work.

## Renewal action requires at least `price` allowance
Before showing “Renew now”, check:
- `allowance >= price`
- `balance >= price`

If not:
- show “Approve” / “Add funds” guidance instead of letting the tx revert.

## Note on collector fee
OpenSub mitigates the obvious rebate by disabling collector fee when collector == subscriber.
However, a user can still collect from another wallet they control. This cannot be fully prevented.
So merchants should treat collectorFeeBps as an optional incentive, not a guaranteed protocol fee.
