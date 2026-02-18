# Changes Since Milestone 5 (Baseline)

## Baseline Reference
- BASELINE_M5: `a66917d6003af38c3da8af280b1067208def854e` (2026-02-17T20:26:40+01:00)
- HEAD: `198e68b03d12865c6eb552f6d1628cd0e9d81a59` (2026-02-18T06:09:51+01:00)

## High-Level Summary

### Keeper (Milestone 5/5.1)
- No keeper code changes in commits after the Milestone 5 baseline. The baseline already includes the Milestone 5.1 hardening and test harnesses.

### AA (Milestone 6A)
- New Rust CLI under `aa-rs/` for ERC-4337 account abstraction flows.
- Provides `account` and `subscribe` subcommands.
- Supports scripted outputs (`--json`, `--print-owner`, `--print-smart-account`, `--print-owner-env-path`) and `--new-owner` key generation under `.secrets/`.
- Implements the UserOperation flow to approve + subscribe via `SimpleAccount.executeBatch` and waits for userOp receipt.

### Repo Docs / Hygiene
- README updated to list Milestone 6A.
- `.gitignore` expanded to ignore `.env*`, `target/`, and `node_modules/`.
- New documentation: `docs/MILESTONE6A.md` and the test prompt used for this run.

## Concrete Diff Evidence

### Commit Log (since baseline)
```
198e68b milestone6a: add AA CLI and docs
```

### Diff Stat (since baseline)
```
 .gitignore                         |    8 +-
 README.md                          |    2 +-
 aa-rs/Cargo.lock                   | 4543 ++++++++++++++++++++++++++++++++++++
 aa-rs/Cargo.toml                   |   20 +
 aa-rs/README.md                    |  188 ++
 aa-rs/src/bundler.rs               |  140 ++
 aa-rs/src/config.rs                |   77 +
 aa-rs/src/encoding.rs              |   58 +
 aa-rs/src/main.rs                  |  889 +++++++
 aa-rs/src/types.rs                 |   55 +
 docs/CODEX_SINCE_M5_TEST_PROMPT.md |  101 +
 docs/MILESTONE6A.md                |  155 ++
 12 files changed, 6234 insertions(+), 2 deletions(-)
```

### Top Changed Files by Lines (since baseline)
```
4543	0	aa-rs/Cargo.lock
889	0	aa-rs/src/main.rs
188	0	aa-rs/README.md
155	0	docs/MILESTONE6A.md
140	0	aa-rs/src/bundler.rs
101	0	docs/CODEX_SINCE_M5_TEST_PROMPT.md
77	0	aa-rs/src/config.rs
58	0	aa-rs/src/encoding.rs
55	0	aa-rs/src/types.rs
20	0	aa-rs/Cargo.toml
7	1	.gitignore
1	1	README.md
```

## New Binaries / Scripts / Targets
- New binary (built locally): `opensub-aa` from `aa-rs/`.
- No new Make targets in the diff.

## Risk Assessment
- **Consensus-critical**: None (no Solidity contract changes since baseline).
- **Tooling-only**: AA CLI (`aa-rs/`), docs, and `.gitignore` updates.
