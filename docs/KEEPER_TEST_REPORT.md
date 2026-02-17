# Keeper Regression + Integration Test Report

Date: 2026-02-17

## Repo Context
- Branch: `keeper-regression-20260217-115145`
- Tested commit: `66e5557f8237b8b85c22ace0c2cc9b37aa961525`

## Tool Versions
```
forge 0.3.0 (5a8bd89 2024-12-20T08:46:21.555250780Z)
cast 0.3.0 (5a8bd89 2024-12-20T08:46:21.564365462Z)
anvil 0.3.0 (5a8bd89 2024-12-20T08:46:21.565569027Z)
rustc 1.90.0 (1159e78c4 2025-09-14)
cargo 1.90.0 (840b83a10 2025-07-30)
```

## Fixes Applied (This Branch)
- `84e179e` keeper: rustfmt
- `3b07d77` keeper: clippy fixes
- `84380c2` chore: fix keeper self-test (parse plan price; ensure `script/install_deps.sh` is executable)
- `66e5557` keeper: add force-pending test hook

## Solidity Regression (Foundry)
All green. Logs captured under `.secrets/`.
- `forge fmt --check` (PASS) — `.secrets/forge_fmt_check.log`
- `forge build -vvv` (PASS) — `.secrets/forge_build.log`
- `forge test -vvv` (PASS) — `.secrets/forge_test.log`
- Heavy run (PASS) — `.secrets/forge_test_heavy.log`
- `forge test --match-contract OpenSubSmoke -vvv` (PASS) — `.secrets/forge_test_smoke.log`
- `forge test --match-contract OpenSubReentrancy -vvv` (PASS) — `.secrets/forge_test_reentrancy.log`
- `forge test --match-path "test/invariant/*" -vvv` (PASS) — `.secrets/forge_test_invariant.log`

## Rust Keeper Quality Gates
All green after fixes. Logs captured under `.secrets/`.
- `cargo fmt --check` (PASS) — `.secrets/keeper_fmt_check.log`
- `cargo clippy -D warnings` (PASS) — `.secrets/keeper_clippy.log`
- `cargo test` (PASS) — `.secrets/keeper_test.log`
- `cargo build --release` (PASS) — `.secrets/keeper_build_release.log`

## Repo-Level Demo Targets
- `make demo-local` (PASS) — `.secrets/demo-local.log`
- `make keeper-self-test` (PASS) — `.secrets/keeper-self-test.log`

## Local Anvil Integration Battery (Scenarios 1–8)
Anvil was launched locally and seeded via DemoScenario with `PLAN_INTERVAL_SECONDS=10`.
Deployment + state artifacts written to `.secrets/`.

Scenario evidence files:
- Scenario 1: `.secrets/scenario1.txt`
- Scenario 2: `.secrets/scenario2.txt`
- Scenario 3: `.secrets/scenario3.txt`
- Scenario 4: `.secrets/scenario4.txt`
- Scenario 5: `.secrets/scenario5.txt`
- Scenario 6: `.secrets/scenario6.txt`
- Scenario 7: `.secrets/scenario7.txt`
- Scenario 8: `.secrets/scenario8.txt`

Results summary:
- Scenario 1 (happy path): PASS — due flips true -> false; access remains true.
- Scenario 2 (insufficient allowance): PASS — no tx; backoff recorded as `insufficientAllowance`.
- Scenario 3 (restore allowance + backoff): PASS — skip with backoff, then success with `--ignore-backoff`.
- Scenario 4 (insufficient balance): PASS — no tx; backoff recorded as `insufficientBalance`.
- Scenario 5 (plan inactive): PASS — no tx; backoff recorded as `planInactive`.
- Scenario 6 (dry-run side effects): PASS — retries/in-flight unchanged; scan cursor advanced only.
- Scenario 7 (max txs per cycle): PASS — one collect per run; remaining due until next run.
- Scenario 8 (reconcile/in-flight): PASS — used `--force-pending` test hook to record in-flight, then reconcile cleared it next run.

Key evidence:
- Scenario 2 state: `.secrets/keeper_s2_state.txt`
- Scenario 4 state: `.secrets/keeper_s4_state.txt`
- Scenario 5 state: `.secrets/keeper_s5_state.txt`
- Scenario 6 diff: `.secrets/keeper_s6_diff_detail.txt`
- Scenario 7 run logs: `.secrets/keeper_s7a.log`, `.secrets/keeper_s7b.log`
- Scenario 8 state: `.secrets/keeper_s8_state_a.txt`, `.secrets/keeper_s8_state_b.txt`

## Base Sepolia Dry-Run (Optional, No Tx)
- RPC selected: see `.secrets/base_sepolia_rpc.txt`
- Chain ID check: `84532` — `.secrets/base_sepolia_chainid.txt`
- Keeper dry-run: PASS (no tx) — `.secrets/base_sepolia_dryrun.log`
- Live testnet txs were NOT executed (RUN_BASE_SEPOLIA_LIVE not set).

## Notes / Recommendations
- Scenario 8 relied on the `--force-pending` test hook to simulate delayed receipts on Anvil; consider re-validating on a network with naturally delayed receipts when convenient.
- Dry-run was verified to avoid retry/backoff mutations; only `lastScannedBlock` advanced.
