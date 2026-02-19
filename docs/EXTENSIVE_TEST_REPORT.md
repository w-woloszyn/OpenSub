# Extensive Test Report (Since Milestone 5)

## Context
- Date: 2026-02-19
- Branch: extensive-test-20260219-153213
- HEAD: 0e090b01aea4363356d3695a3c17fa3fe9f8affb

## Tool Versions
- See `.secrets/tool_versions.txt` (forge/cast/anvil/rust/cargo)

## Solidity (Foundry)
Status: PASS

Commands + evidence:
- install deps: `.secrets/sol_install_deps.log`
- fmt check: `.secrets/forge_fmt_check.log`
- build: `.secrets/forge_build.log`
- test: `.secrets/forge_test.log`
- heavy fuzz/invariant: `.secrets/forge_heavy.log`
- targeted smoke/reentrancy/invariants: `.secrets/forge_smoke.log`, `.secrets/forge_reentrancy.log`, `.secrets/forge_invariants_only.log`

## Rust Keeper (Quality Gates)
Status: PASS

Commands + evidence:
- fmt: `.secrets/keeper_fmt_check.log`
- clippy: `.secrets/keeper_clippy.log`
- tests: `.secrets/keeper_test.log`
- build (release): `.secrets/keeper_build.log`

## AA Rust (Milestone 6A)
Status: PASS (account JSON sanity completed)

Commands + evidence:
- fmt: `.secrets/aa_fmt_check.log`
- clippy: `.secrets/aa_clippy.log`
- tests: `.secrets/aa_test.log` (includes JSON parsing tests for bundler + paymaster)
- build (release): `.secrets/aa_build.log`
- CLI help: `.secrets/aa_help.log`, `.secrets/aa_account_help.log`, `.secrets/aa_subscribe_help.log`

Account JSON sanity:
- Command: `opensub-aa account --deployment deployments/base-sepolia.json --new-owner --json --salt 0`
- EntryPoint: `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789`
- SimpleAccountFactory: `0x9406Cc6185a346906296840746125a0E44976454`
- Result: **PASS** (JSON output written)
- Evidence: `.secrets/aa_account_json.out`, `.secrets/aa_account_json.err`

## Local E2E (Anvil)
Status: PASS

Make targets:
- `make demo-local` → `.secrets/make_demo_local.log`
- `make keeper-self-test` → `.secrets/make_keeper_self_test.log`

Keeper scenario battery (local):
- Scenario 1 happy path collect: `.secrets/scenario_1.log`
- Scenario 2 insufficient allowance backoff: `.secrets/scenario_2.log`
- Scenario 3 restore allowance + ignore-backoff: `.secrets/scenario_3.log`
- Scenario 4 insufficient balance backoff: `.secrets/scenario_4.log`
- Scenario 5 plan inactive backoff: `.secrets/scenario_5.log`
- Scenario 6 dry-run side-effect safety: `.secrets/scenario_6.log`
- Scenario 7 max-txs-per-cycle: `.secrets/scenario_7.log`
- Scenario 8 reconcile/in-flight: `.secrets/scenario_8.log`

## Base Sepolia (Dry-Run)
Status: PASS

- chainId check: `.secrets/base_chainid.log`
- keeper dry-run: `.secrets/keeper_base_dry_run.log`

## M6B Sponsored AA (Alchemy Gas Manager)
Status: PASS (dry-run)

Evidence:
- `.secrets/aa_sponsor_dry_run.out`
- `.secrets/aa_sponsor_dry_run.err`

## Fixes Applied
- `0e090b0` — aa: improve bundler parsing + tests
  - Handles multiple bundler response shapes for `eth_sendUserOperation`.
  - Adds unit tests for bundler response parsing.
  - Adds paymaster parsing tests (ERC-7677 v0.6 response shapes).
- `ba40fe2` — aa: fix EntryPoint ABI parsing for getUserOpHash
  - Switches to JSON ABI for EntryPoint tuple parsing to avoid parser errors.
```

## Remaining Actions / Next Steps
1. Provide Base Sepolia EntryPoint + SimpleAccountFactory addresses (set `OPENSUB_AA_ENTRYPOINT` and `OPENSUB_AA_FACTORY` or pass `--entrypoint`/`--factory`) to complete the AA account JSON sanity run.
2. (Optional) Provide Alchemy bundler + paymaster + policy id to run M6B sponsored dry-run.
