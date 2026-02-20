# Extensive Test Report

## Context
- Date: 2026-02-20T00:52:00+01:00
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
Status: PASS

Evidence:
- install: `.secrets/frontend_install.log`
- typecheck: `.secrets/frontend_typecheck.log`
- lint: `.secrets/frontend_lint.log`
- build: `.secrets/frontend_build.log`

## Base Sepolia (Dry-Run)
Status: PASS (dry-run only)

Evidence:
- chain-id: `.secrets/base_chainid.log`
- keeper dry-run: `.secrets/keeper_base_dry_run.log`
- AA sponsored dry-run: `.secrets/aa_sponsor_dry_run.out`, `.secrets/aa_sponsor_dry_run.err`

## Fixes Applied
- Frontend lint/build fix: add Next.js ESLint config and escape unescaped quotes in `frontend/app/page.tsx`.

## Next Steps
1. Optional: Run live Base Sepolia transactions only if explicitly enabled and funded.
