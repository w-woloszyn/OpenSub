# OpenSub AA (Milestone 6A + 6B) — Rust CLI

This folder implements:

- **Milestone 6A**: ERC-4337 (Account Abstraction) subscribe flow in Rust.
- **Milestone 6B**: optional **gas sponsorship** via a paymaster web service (ERC-7677).

Goal:
- Create (counterfactual) smart account (e.g., `SimpleAccount`)
- (Optionally) fund it with ETH + mint demo `mUSDC` to it
- Send a single **UserOperation** that batches:
  0) *(Optional demo-only)* `MockERC20.mint(smartAccount, amount)`
  1) `ERC20.approve(OpenSub, allowance)`
  2) `OpenSub.subscribe(planId)`

Milestone 6B is implemented as an **optional** mode (`--sponsor-gas`) so you can keep using pure 6A flows.

---

## Requirements

- Rust toolchain (stable)
- Access to an ERC-4337 **bundler RPC** for your target chain (Base Sepolia recommended)
- EntryPoint + SimpleAccountFactory addresses for that bundler stack

> This repo ships a Base Sepolia deployment artifact at `deployments/base-sepolia.json` for OpenSub + mUSDC.

---

## Setup

From repo root:

```bash
cd aa-rs
cp env.example .env
# edit .env
```

Do **not** commit `.env`.

---

## Run

### 1) Build

```bash
cargo build --release
```

### 2) Print the counterfactual smart account address

```bash
cargo run --release -- account \
  --deployment ../deployments/base-sepolia.json \
  --salt 0
```

If you want a fresh demo owner without handling keys manually, you can generate one locally:

```bash
cargo run --release -- account \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --salt 0
```

This writes the private key to a local file under `../.secrets/` (never printed).
Fund the owner address with a small amount of test ETH if you plan to send **regular EOA transactions**
(e.g., using `--fund-eth` in Milestone 6A flows). For Milestone 6B sponsored flows, the owner can have
0 ETH (they only sign; the paymaster covers the UserOperation gas).

If you want **stdout-only** machine output (for scripts), use one of:

- `--print-owner` → prints only the owner address
- `--print-smart-account` → prints only the counterfactual smart account address

In these modes, all other logs are written to stderr.

### JSON output (jq-friendly)

If you prefer a single structured output for scripts, use `--json`. It prints exactly one JSON object to stdout:

```json
{ "owner": "0x...", "smartAccount": "0x...", "envPath": "/abs/path" }
```

- `envPath` is `null` unless you pass `--new-owner`.
- All other logs are written to **stderr** (so stdout stays clean).

Example:

```bash
cd aa-rs
BIN=./target/release/opensub-aa

INFO_JSON="$($BIN account \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --json \
  --salt 0)"

echo "$INFO_JSON" | jq -r .owner
echo "$INFO_JSON" | jq -r .smartAccount

ENV_PATH="$(echo "$INFO_JSON" | jq -r .envPath)"
source "$ENV_PATH"
```


If you want a *script-friendly* way to capture the generated owner env file path (single line on stdout), use `--print-owner-env-path`:

```bash
cd aa-rs
# Prints ONLY the env file path on stdout; all other logs go to stderr
OWNER_ENV_PATH="$(cargo run --quiet --release -- account \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --print-owner-env-path \
  --salt 0)"

# Load the generated owner key into your shell
source "$OWNER_ENV_PATH"

# (Optional) capture addresses without parsing logs
OWNER_ADDR="$(cargo run --quiet --release -- account --deployment ../deployments/base-sepolia.json --print-owner --salt 0)"
SMART_ACCOUNT_ADDR="$(cargo run --quiet --release -- account --deployment ../deployments/base-sepolia.json --print-smart-account --salt 0)"
echo "owner=$OWNER_ADDR"
echo "smartAccount=$SMART_ACCOUNT_ADDR"

# Now you can run subscribe without --new-owner
cargo run --quiet --release -- subscribe \
  --deployment ../deployments/base-sepolia.json \
  --salt 0 \
  --allowance-periods 12 \
  --fund-eth 0.002 \
  --mint 10000000
```

### 3) Subscribe via ERC-4337

This will:
- compute account address
- optionally fund it with ETH (for prefund)
- optionally mint mUSDC to it (demo-only)
- estimate gas via bundler
- send UserOperation
- wait for receipt

```bash
cargo run --release -- subscribe \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --salt 0 \
  --allowance-periods 12 \
  --fund-eth 0.002 \
  --mint 10000000
```

Notes:
- `--fund-eth` is in **ETH** (decimal string).
- `--mint` is a raw integer in token base units. For mUSDC (6 decimals):
  - `10_000_000` = 10.0 mUSDC
 - `--mint` executes **inside the UserOperation** (it is *not* a standalone EOA transaction), so it can be sponsored
   when `--sponsor-gas` is enabled. It will revert on real tokens.

### 4) Sponsored subscribe (Milestone 6B)

If you have an ERC-7677 paymaster web service configured (recommended: Alchemy Gas Manager on Base Sepolia),
you can make the subscriber flow *gasless*:

```bash
cargo run --release -- subscribe \
  --deployment ../deployments/base-sepolia.json \
  --new-owner \
  --salt 0 \
  --mint 10000000 \
  --allowance-periods 12 \
  --sponsor-gas
```

Notes:
- With `--sponsor-gas`, `--fund-eth` is usually unnecessary.
- You must set `OPENSUB_AA_PAYMASTER_URL` and `OPENSUB_AA_GAS_MANAGER_POLICY_ID`.

If you only want to build + estimate (no send):

```bash
cargo run --release -- subscribe \
  --deployment ../deployments/base-sepolia.json \
  --dry-run
```

---

## Environment variables

The CLI reads these (can be in `aa-rs/.env`):

- `OPENSUB_AA_RPC_URL` (optional; otherwise uses deployment JSON)
- `OPENSUB_AA_BUNDLER_URL` (**required**)
- `OPENSUB_AA_ENTRYPOINT` (**required**)
- `OPENSUB_AA_FACTORY` (**required**)
- `OPENSUB_AA_OWNER_PRIVATE_KEY` (**required unless you use `--new-owner`**)

When using `--sponsor-gas` (Milestone 6B):

- `OPENSUB_AA_PAYMASTER_URL` (**required**) — paymaster RPC URL (ERC-7677)
- `OPENSUB_AA_GAS_MANAGER_POLICY_ID` (**required**) — Alchemy Gas Manager policy id
- `OPENSUB_AA_GAS_MANAGER_WEBHOOK_DATA` (optional)

---

## Notes

- The paymaster integration uses the ERC-7677 methods `pm_getPaymasterStubData` and `pm_getPaymasterData`.
- The UserOperation struct is EntryPoint v0.6.

