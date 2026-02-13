#!/usr/bin/env bash
set -euo pipefail

# Installs Foundry dependencies into ./lib
# Run from the repo root (the folder containing foundry.toml)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OZ_DIR="$ROOT_DIR/lib/openzeppelin-contracts/contracts"
FORGE_STD_DIR="$ROOT_DIR/lib/forge-std/src"

if [[ -d "$OZ_DIR" && -d "$FORGE_STD_DIR" ]]; then
  echo "Deps already vendored in ./lib"
  exit 0
fi

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Install Foundry first: https://book.getfoundry.sh/getting-started/installation" >&2
  exit 1
fi

forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit

echo "Deps installed in ./lib"
