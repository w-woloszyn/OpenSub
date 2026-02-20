# OpenSub Demo Frontend

This is a **minimal, functional** frontend intended for demos and for onboarding a non-blockchain frontend developer.

Goals:
- Demonstrate **full OpenSub flows** (plan, subscribe, cancel/resume, renew/collect, manual collector).
- Be easy to modify (low magic, little abstraction).
- Work on **Base Sepolia** out-of-the-box.
- Support a **demo-only** “gasless subscribe” button by calling the Rust AA CLI from a Next.js API route.

## Quick start

```bash
cd frontend
npm i
npm run dev
```

Open: http://localhost:3000

## Chains

### Base Sepolia (default)

`frontend/config/addresses.ts` and `frontend/config/tokens.ts` are pre-filled from `deployments/base-sepolia.json`.

So the UI can load state immediately.

To send transactions, connect MetaMask and switch to Base Sepolia.

### Local Anvil

1) In repo root:

```bash
make demo-local
```

2) Copy the printed addresses into:
- `frontend/config/addresses.ts` (OpenSub + deployBlock)
- `frontend/config/tokens.ts` (mUSDC token address)

3) Switch chain dropdown in the UI to **Local Anvil**.

## Gasless demo (Milestone 6B)

This is optional.

1) Build the AA binary once:

```bash
cargo build --release --manifest-path aa-rs/Cargo.toml
```

2) Configure env vars:

```bash
cd frontend
cp env.example .env.local
# edit .env.local
```

3) Use the **Gasless (AA)** page.

Notes:
- This is **demo-only**: it generates a fresh owner key and stores it under `.secrets/`.
- It requires an Alchemy Gas Manager policy on Base Sepolia.

## Where to look in code

- `frontend/app/*` — Next.js pages
- `frontend/config/*` — addresses + token lists
- `frontend/abi/*` — viem ABIs
- `frontend/lib/*` — helpers (log scanning, formatting)
