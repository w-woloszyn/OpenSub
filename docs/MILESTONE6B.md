# Milestone 6B — Gasless subscribe (Option A: Alchemy Gas Manager, Base Sepolia)

## Goal
Make the Milestone 6A AA flow **gasless for the subscriber** by using a third-party paymaster.

This milestone intentionally uses **Option A**:
- **Paymaster-as-a-service** (Alchemy Gas Manager)
- No new Solidity paymaster contracts
- No backend signer service

Implementation is done in Rust inside `aa-rs/` and is designed to be **vendor-portable** by using
ERC-7677 paymaster RPC methods:
- `pm_getPaymasterStubData`
- `pm_getPaymasterData`

(Alchemy Gas Manager supports ERC-7677.)

---

## Deliverables

- `aa-rs/`:
  - `opensub-aa subscribe` supports a new flag: `--sponsor-gas`
  - When enabled, the CLI:
    1) calls the paymaster web service for **stub** paymaster data
    2) estimates gas via the bundler
    3) calls the paymaster web service for **final** paymaster data
    4) signs + submits the sponsored UserOperation

- Docs updates:
  - `env.example` for `aa-rs/` so founders/PMs can run the demo quickly.

---

## New inputs (6B)

Set these env vars when using `--sponsor-gas`:

- `OPENSUB_AA_PAYMASTER_URL`
  - Example (Base Sepolia):
    - `https://base-sepolia.g.alchemy.com/v2/<ALCHEMY_API_KEY>`

- `OPENSUB_AA_GAS_MANAGER_POLICY_ID`
  - The Gas Manager Policy ID from your Alchemy dashboard.

Optional:

- `OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA`
  - Only needed if you enabled custom webhook rules.

---

## Acceptance criteria

✅ On Base Sepolia:

1. `opensub-aa subscribe --sponsor-gas ...` succeeds.
2. The resulting on-chain state matches Milestone 6A:
   - `activeSubscriptionOf(planId, smartAccount) != 0`
   - `hasAccess(subscriptionId) == true`
3. The smart account can be **unfunded** (0 ETH) and still successfully subscribe
   (paymaster covers prefund).

---

## How to run (Base Sepolia)

From repo root:

```bash
cd aa-rs
cp env.example .env
# edit .env
cargo build --release
```

### 1) Print the counterfactual account

```bash
cargo run --release -- account --deployment ../deployments/base-sepolia.json --salt 0
```

### 2) Sponsored subscribe

```bash
cargo run --release -- subscribe \
  --deployment ../deployments/base-sepolia.json \
  --salt 0 \
  --new-owner \
  --mint 10000000 \
  --allowance-periods 12 \
  --sponsor-gas
```

Notes:
- With `--sponsor-gas`, `--fund-eth` is usually unnecessary.
 - `--mint` only works with the repo's `MockERC20` and is executed **inside** the sponsored UserOperation.
   If your Gas Manager policy uses selector-level restrictions, ensure it allows `mint(address,uint256)` too,
   or omit `--mint` and pre-seed the smart account with tokens.

---

## Security & limitations

Option A shifts risk to the paymaster provider:
- Your policy must restrict what gets sponsored (target contracts, selectors, spend limits).
- If your policy is too permissive, you can unintentionally sponsor arbitrary calls.

Milestone 6B intentionally does **not** implement:
- your own paymaster contracts
- backend signing / quotas
- ERC20 paymaster flows

Those can be added later without changing the OpenSub contracts.
