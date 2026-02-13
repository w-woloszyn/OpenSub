# Threat Model (Draft for Milestone 3)

This is a starter threat model to guide tests and invariants.

## Assets
- Subscriber funds (ERC20 balances / allowances)
- Merchant revenue stream
- Correct access window (`paidThrough`)
- Subscription pointer correctness (`activeSubscriptionOf`)

## Actors
- Malicious collector (front-runs / griefs)
- Malicious merchant (pauses plan, weird params)
- Malicious subscriber (tries to evade payment / abuse fees)
- Non-standard ERC20 token behavior (returns false, reverts, fee-on-transfer)

## Key risks & mitigations (Milestone 2)

### R1: Reentrancy during token transfers
- Mitigation: `nonReentrant` + CEI (state updated before transfers)

### R2: Charging when not due
- Mitigation: `NotDue` check

### R3: State corruption when token transfer fails
- Mitigation: transaction revert (SafeERC20) should roll back state.
- Milestone 3 tests: ensure `paidThrough` does not change on failure.

### R4: Plan misconfiguration (non-contract token)
- Mitigation: `token.code.length != 0` + minimal `totalSupply()` shape check

### R5: Denial of service via paused plan
- Mitigation: pause blocks charges, but subscriber cancellation remains possible.

### R6: Subscriber self-collects to claim fee
- Mitigation: disable fee when `collector == subscriber` (best effort)

## Non-goals (Milestone 2)
- Slashing / dispute resolution
- Partial payments
- Automatic retries / delinquency state
- Handling fee-on-transfer / rebasing tokens


## Test mapping (Milestone 3)

- **R1 Reentrancy during token transfers**: `test/OpenSubReentrancy.t.sol`
- **R2 Charging when not due**: `test/OpenSubCollect.t.sol::test_collect_reverts_whenNotDue`
- **R3 State corruption on token transfer failure**: `test/OpenSubTokenFailures.t.sol`
- **R4 Plan misconfiguration**: `test/OpenSubPlan.t.sol`
- **R5 DoS via paused plan**: `test/OpenSubPlan.t.sol::test_pause_blocksSubscribe_and_collect_but_cancelStillWorks`
- **R6 Subscriber self-collects**: `test/OpenSubCollect.t.sol::test_collect_disablesFee_whenCollectorIsSubscriber`

Stateful invariants for ongoing consistency live in: `test/invariant/OpenSubInvariant.t.sol`.
