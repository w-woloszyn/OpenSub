# Milestone 6A — ERC-4337 Account Abstraction subscribe flow (Rust)

## Goal
Make OpenSub usable from a **smart account** (ERC-4337) so a subscriber can subscribe using a **UserOperation**.

Milestone 6A focuses on **AA without sponsorship**:
- No paymaster
- The smart account pays gas (prefund)

Milestone 6B will later add a paymaster / sponsorship policy.

---

## Deliverables

- `aa-rs/` Rust CLI:
  - Computes a counterfactual smart account address using a factory (`getAddress(owner, salt)`)
  - Optionally funds the smart account with ETH (for prefund)
  - Optionally mints demo tokens to it (MockERC20 only)
  - Sends a single ERC-4337 UserOperation that batches:
    1) `ERC20.approve(OpenSub, allowance)`
    2) `OpenSub.subscribe(planId)`
  - Waits for `eth_getUserOperationReceipt` and prints the resulting on-chain state

---

## Inputs

The CLI reads:

- Deployment artifact (already in this repo):
  - `deployments/base-sepolia.json` (OpenSub + token + planId)

- ERC-4337 parameters (env or flags):
  - `OPENSUB_AA_BUNDLER_URL` — bundler endpoint supporting ERC-4337 JSON-RPC
  - `OPENSUB_AA_ENTRYPOINT` — EntryPoint address
  - `OPENSUB_AA_FACTORY` — SimpleAccountFactory address
  - `OPENSUB_AA_OWNER_PRIVATE_KEY` — EOA key controlling the smart account (unless using `--new-owner`)

---

## Acceptance criteria

✅ On Base Sepolia (recommended):

1. CLI prints the counterfactual smart account address.
2. Smart account receives demo tokens (`mUSDC`) and ETH prefund.
3. CLI sends a UserOperation and obtains a receipt.
4. `activeSubscriptionOf(planId, smartAccount) != 0`.
5. `hasAccess(subscriptionId) == true`.

---

## How to run (Base Sepolia)

From repo root:

```bash
cd aa-rs
cp .env.example .env
# edit .env with bundler/entrypoint/factory/owner key
cargo build --release

# Print account address
cargo run --release -- account --deployment ../deployments/base-sepolia.json --salt 0

# Or generate a fresh owner key locally (key saved under ../.secrets/; never printed)
cargo run --release -- account --deployment ../deployments/base-sepolia.json --new-owner --salt 0

```


### Script-friendly owner generation

If you want to generate a new owner key and **capture the env file path as a single stdout line** (so you can `source "$(...)"`), use `--print-owner-env-path`:

```bash
cd aa-rs
OWNER_ENV_PATH="$(cargo run --quiet --release -- account \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --print-owner-env-path \
  --salt 0)"

source "$OWNER_ENV_PATH"
```

In this mode, the CLI prints only the env file path on stdout; all other logs are written to stderr.

### Stdout-only address capture

For scripting, you can also print **only** the address you care about (single-line stdout):

```bash
# prints only the owner address
cargo run --quiet --release -- account --deployment ../deployments/base-sepolia.json --print-owner --salt 0

# prints only the smart account address
cargo run --quiet --release -- account --deployment ../deployments/base-sepolia.json --print-smart-account --salt 0
```

In these modes, all other logs are written to stderr.

### JSON output (jq-friendly)

For scripting, you can also ask the CLI to print **one JSON object** to stdout:

```json
{ "owner": "0x...", "smartAccount": "0x...", "envPath": "/abs/path" }
```

- `envPath` is `null` unless you pass `--new-owner`.
- All other logs go to stderr.

Example:

```bash
cd aa-rs
INFO_JSON="$(cargo run --quiet --release -- account \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --json \
  --salt 0)"

OWNER_ADDR="$(echo "$INFO_JSON" | jq -r .owner)"
SMART_ACCOUNT_ADDR="$(echo "$INFO_JSON" | jq -r .smartAccount)"
ENV_PATH="$(echo "$INFO_JSON" | jq -r .envPath)"

echo "owner=$OWNER_ADDR"
echo "smartAccount=$SMART_ACCOUNT_ADDR"
source "$ENV_PATH"
```

### Subscribe (demo)

```bash
cargo run --release -- subscribe --deployment ../deployments/base-sepolia.json --salt 0 \
  --new-owner \
  --allowance-periods 12 \
  --fund-eth 0.002 \
  --mint 10000000
```

Notes:
- `--fund-eth` is in ETH.
- `--mint` is token base units (mUSDC is 6 decimals).

---

## Why this won’t conflict with Milestone 6B

- UserOperation struct already includes `paymasterAndData`.
- Bundler client is isolated.
- Sponsorship can be added by populating `paymasterAndData` + (optionally) calling a paymaster endpoint.

