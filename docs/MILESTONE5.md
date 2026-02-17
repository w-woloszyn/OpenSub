# Milestone 5 — Keeper bot (automation)

Milestone 5 makes OpenSub **feel like a real subscription system** by adding a backend “keeper” that can execute renewals.

OpenSub’s core on-chain design is permissionless:
- **Anyone** can call `collect(subscriptionId)`.
- A keeper is therefore an **off-chain reliability component**, not a privileged admin.

This milestone is intentionally designed so it does **not** conflict with Milestone 6 (ERC‑4337 / Account Abstraction).

---

## Definition of done

Milestone 5 is complete when:

1) The keeper discovers subscriptions by scanning `Subscribed` logs.
2) It maintains durable state (last scanned block + known subscription IDs).
3) It calls `collect()` when a subscription is due.
4) It is safe and operable:
   - chainId mismatch check (won’t run against the wrong chain)
   - chunked log scanning
   - tx rate limiting / max txs per cycle
   - in-flight tx tracking (no duplicate collects while a tx is pending)
   - dry-run mode
5) It runs successfully on:
   - local Anvil
   - Base Sepolia

Milestone 5.1 (recommended) further hardens the keeper with prechecks + persisted backoff:

- `docs/MILESTONE5_1.md`

---

## Implementation

The keeper lives in:

- `keeper-rs/` — Rust implementation using `ethers-rs`

It reads deployment artifacts such as:

- `deployments/base-sepolia.json`

Recommended: store provider URLs in an env var instead of committing API keys:

```json
{
  "rpcEnvVar": "BASE_SEPOLIA_RPC_URL"
}
```

---

## Running the keeper

From repo root:

```bash
export KEEPER_PRIVATE_KEY="<funded EOA key>"
export OPENSUB_KEEPER_RPC_URL="https://sepolia.base.org"  # or a dedicated provider

cargo run --release --manifest-path keeper-rs/Cargo.toml -- \
  --deployment deployments/base-sepolia.json \
  --poll-seconds 30 \
  --confirmations 2 \
  --log-chunk 2000
```

Useful flags:

- `--dry-run` : never sends transactions
- `--once` : run one scan+collect cycle and exit
- `--max-txs-per-cycle` : safety cap to avoid draining ETH
- `--tx-timeout-seconds` : receipt wait timeout
- `--pending-ttl-seconds` : drop “stuck” pending txs after TTL

---

## Why this doesn’t conflict with Milestone 6

Milestone 6 (ERC‑4337) focuses on **user onboarding UX**:
- batching `approve + subscribe`
- gas sponsorship via paymaster

Milestone 5 uses a standard EOA signer to call permissionless `collect()`.

If you later want a keeper that submits `collect()` via AA, you can add a second submission backend without changing:
- `OpenSub.sol`
- the keeper’s indexing/state logic

## One-command local demo

From repo root:

```bash
make demo-local
```

This runs: **Anvil → DemoScenario → time-warp → keeper (once)** and prints a quick sanity check.

