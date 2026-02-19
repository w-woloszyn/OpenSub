# Extensive Test Report

## Context
- Date: 2026-02-19T21:51:32+01:00
- Branch: extensive-test-20260219-203946
- HEAD: bc996968e81086b7f61ab7ef565e0814718779d3

## Tool Versions
- See: `.secrets/tool_versions.txt`

## Solidity (Foundry)
Status: PASS

Evidence:
- deps: `.secrets/install_deps.log`
- fmt: `.secrets/forge_fmt_check.log`
- build: `.secrets/forge_build.log`
- test: `.secrets/forge_test.log`
- heavy fuzz/invariant: `.secrets/forge_heavy.log`
- targeted: `.secrets/forge_smoke.log`, `.secrets/forge_reentrancy.log`, `.secrets/forge_invariants_only.log`

## Rust Keeper
Status: PASS

Evidence:
- fmt: `.secrets/keeper_fmt_check.log`
- clippy: `.secrets/keeper_clippy.log`
- tests: `.secrets/keeper_test.log`
- build: `.secrets/keeper_build.log`

## Rust AA CLI (Milestone 6A + 6B)
Status: PASS (local quality gates)

Evidence:
- fmt: `.secrets/aa_fmt_check.log`
- clippy: `.secrets/aa_clippy.log`
- tests: `.secrets/aa_test.log`
- build: `.secrets/aa_build.log`
- help: `.secrets/aa_help.log`, `.secrets/aa_subscribe_help.log`

## Local E2E (Keeper)
Status: PASS

Evidence:
- demo-local: `.secrets/make_demo_local.log`
- keeper-self-test: `.secrets/make_keeper_self_test.log`
- scenario battery: `.secrets/scenario_1.log` through `.secrets/scenario_8.log`

## Frontend (Next.js)
Status: FAIL (dependency install blocked)

Details:
- `npm install` failed with DNS errors (EAI_AGAIN) to the npm registry.
- Logs: `.secrets/frontend_install.log`
- Typecheck/build skipped due to missing deps.

## Base Sepolia (Dry-Run)
Status: SKIPPED (RPC DNS failure)

Details:
- `cast chain-id` failed with DNS resolution errors for RPC.
- Logs: `.secrets/base_chainid.log`
- Keeper dry-run and AA sponsored dry-run skipped.

## Fixes Applied
- None in this run.

## Next Steps
1. Resolve npm registry DNS/network access, then rerun frontend: install → typecheck → build.
2. Restore RPC DNS/network access to run Base Sepolia dry-runs.
