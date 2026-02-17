#!/usr/bin/env bash
set -euo pipefail

# Installs/updates Foundry dependencies into ./lib
# Run from the repo root (the folder containing foundry.toml)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OZ_ROOT="$ROOT_DIR/lib/openzeppelin-contracts"
FORGE_ROOT="$ROOT_DIR/lib/forge-std"

NEED_INSTALL=0

# We consider forge-std "installed" if console2 exists (used by scripts) and the folder looks complete.
if [[ ! -f "$FORGE_ROOT/src/console2.sol" ]]; then
  NEED_INSTALL=1
fi

# We consider OpenZeppelin "installed" if SafeERC20 exists.
if [[ ! -f "$OZ_ROOT/contracts/token/ERC20/utils/SafeERC20.sol" ]]; then
  NEED_INSTALL=1
fi

if [[ "$NEED_INSTALL" -eq 0 ]]; then
  echo "Deps already installed in ./lib"
  exit 0
fi

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Install Foundry first: https://book.getfoundry.sh/getting-started/installation" >&2
  exit 1
fi

# forge install uses git to clone dependencies.
if ! command -v git >/dev/null 2>&1; then
  echo "git not found. 'forge install' requires git to clone dependencies. Please install git and re-run." >&2
  exit 1
fi

echo "Installing/updating deps in ./lib ..."

# Pick a python interpreter (some systems only have python3).
PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python >/dev/null 2>&1; then
    PYTHON_BIN=python
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN=python3
  else
    echo "python/python3 not found. Please install Python to run this script." >&2
    exit 1
  fi
fi

# Remove any partial vendoring (common when sharing zip snapshots).
rm -rf "$OZ_ROOT" "$FORGE_ROOT"

# NOTE: Use --no-git so this works even if this project directory is NOT a git repo
# (e.g., you downloaded a zip snapshot instead of cloning).
forge install OpenZeppelin/openzeppelin-contracts --no-git --no-commit

# OpenZeppelin's foundry.toml may set an EVM fork that older Foundry versions
# don't recognize (e.g., "osaka"). This causes forge to panic when it scans
# dependency configs. Strip the setting since we don't run OZ's own tests here.
if [[ -f "$OZ_ROOT/foundry.toml" ]]; then
  "${PYTHON_BIN}" - <<'PY' "$OZ_ROOT/foundry.toml"
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
raw = p.read_text()
lines = raw.splitlines()
kept = [ln for ln in lines if not re.match(r"^\s*evm_version\s*=", ln)]
out = "\n".join(kept).rstrip("\n") + "\n"
p.write_text(out)
PY
fi

forge install foundry-rs/forge-std --no-git --no-commit

echo "Deps installed in ./lib"
