# Since M5 Test Report

Date: 2026-02-18T06:11:15

## Repo Context
- Branch: `since-m5-regression-20260218-055117`
- BASELINE_M5: `a66917d6003af38c3da8af280b1067208def854e` (2026-02-17T20:26:40+01:00)
- Tested commit: `198e68b03d12865c6eb552f6d1628cd0e9d81a59` (2026-02-18T06:09:51+01:00)
- Current HEAD: `95fefa03e8d5e28ded68640180d7279b467512dd` (2026-02-18T06:11:28+01:00, docs-only update)
- Change summary: see `docs/SINCE_M5_CHANGES.md`

## Tool Versions
```
forge 0.3.0 (5a8bd89 2024-12-20T08:46:21.555250780Z)
cast 0.3.0 (5a8bd89 2024-12-20T08:46:21.564365462Z)
anvil 0.3.0 (5a8bd89 2024-12-20T08:46:21.565569027Z)
rustc 1.90.0 (1159e78c4 2025-09-14)
cargo 1.90.0 (840b83a10 2025-07-30)
```

## Solidity Regression (Foundry)
All PASS. Logs:
- install deps: `.secrets/sol_install_deps.log`
- fmt check: `.secrets/sol_fmt_check.log`
- build: `.secrets/sol_build.log`
- test: `.secrets/sol_test.log`
- heavy fuzz/invariants: `.secrets/sol_heavy.log`
- targeted smoke: `.secrets/sol_smoke.log`
- targeted reentrancy: `.secrets/sol_reentrancy.log`
- invariants: `.secrets/sol_invariants.log`

## Keeper Rust Quality Gates
All PASS. Logs:
- fmt: `.secrets/keeper_fmt.log`
- clippy: `.secrets/keeper_clippy.log`
- test: `.secrets/keeper_test.log`
- build (release): `.secrets/keeper_build.log`

## AA Rust Quality Gates (Milestone 6A)
All PASS. Logs:
- fmt: `.secrets/aa_fmt.log`
- clippy: `.secrets/aa_clippy.log`
- test: `.secrets/aa_test.log`
- build (release): `.secrets/aa_build.log`
- CLI help: `.secrets/aa_help.log`
- CLI account help: `.secrets/aa_account_help.log`
- CLI subscribe help: `.secrets/aa_subscribe_help.log`

Flag sanity (present in help output): `--new-owner`, `--json`, `--print-owner`, `--print-smart-account`, `--print-owner-env-path`.

## Local Anvil E2E (Keeper)
Repo demo targets:
- `make demo-local`: PASS — `.secrets/demo_local.log`
- `make keeper-self-test`: PASS — `.secrets/keeper_self_test.log`

Deep scenario battery (via `.secrets/run_keeper_battery.sh`):
- Scenario 1 (happy path): `.secrets/scenario1.txt`
- Scenario 2 (insufficient allowance): `.secrets/scenario2.txt` + `.secrets/keeper_s2_state.txt`
- Scenario 3 (restore allowance/backoff): `.secrets/scenario3.txt` + `.secrets/keeper_s3_state.txt`
- Scenario 4 (insufficient balance): `.secrets/scenario4.txt` + `.secrets/keeper_s4_state.txt`
- Scenario 5 (plan inactive): `.secrets/scenario5.txt` + `.secrets/keeper_s5_state.txt`
- Scenario 6 (dry-run side-effect safety): `.secrets/scenario6.txt` + `.secrets/keeper_s6_diff_detail.txt`
- Scenario 7 (max-txs-per-cycle cap): `.secrets/scenario7.txt`
- Scenario 8 (reconcile/in-flight): `.secrets/scenario8.txt` + `.secrets/keeper_s8_state_a.txt` + `.secrets/keeper_s8_state_b.txt`

## Base Sepolia (Dry-Run Only)
- RPC: `.secrets/base_sepolia_rpc.txt`
- ChainId check: `.secrets/base_sepolia_chainid.txt` (expected 84532)
- Keeper dry-run: `.secrets/base_sepolia_dryrun.log`
- State file: `.secrets/base-sepolia-keeper-state.json`

No live transactions were sent (RUN_BASE_SEPOLIA_LIVE not set).

## Fixes Applied During This Run
- `198e68b` milestone6a: add AA CLI and docs

## Remaining Risks / Next Steps
- Live testnet AA flow (bundler + EntryPoint + factory) not exercised here.
- Base Sepolia keeper live run is intentionally skipped (dry-run only).
