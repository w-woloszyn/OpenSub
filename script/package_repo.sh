#!/usr/bin/env bash
set -euo pipefail

# Package the repo into a ZIP archive for sharing/auditing.
# Usage: ./script/package_repo.sh [output_path_or_dir]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ARG="${1:-$ROOT_DIR/opensub.zip}"

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

"${PYTHON_BIN}" - <<'PY' "$ROOT_DIR" "$OUTPUT_ARG"
import os
import sys
import zipfile

root = os.path.abspath(sys.argv[1])
out_arg = sys.argv[2]

# If the output is a directory, place the zip inside it.
if os.path.isdir(out_arg):
    out_path = os.path.join(out_arg, "opensub.zip")
else:
    out_path = out_arg

out_path = os.path.abspath(out_path)

exclude_dirs = {
    ".git",
    "out",
    "cache",
    "broadcast",
    ".secrets",
    "node_modules",
    "target",
    ".next",
    "build",
    "dist",
    "coverage",
}
exclude_prefixes = {"keeper-rs/state"}
exclude_files = {
    os.path.basename(out_path),
    ".DS_Store",
    ".env",
}

# Exclude .env.* files as well.
def is_excluded_file(name: str) -> bool:
    if name in exclude_files:
        return True
    if name.startswith(".env."):
        return True
    lower = name.lower()
    if lower.endswith((".zip", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tar.xz")):
        return True
    return False

with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        rel_dir_slash = rel_dir.replace(os.sep, "/")
        if any(rel_dir_slash == p or rel_dir_slash.startswith(p + "/") for p in exclude_prefixes):
            dirnames[:] = []
            continue
        parts = [] if rel_dir == "." else rel_dir.split(os.sep)
        if any(part in exclude_dirs for part in parts):
            dirnames[:] = []
            continue

        # Prune excluded dirs from traversal.
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]

        for filename in filenames:
            if is_excluded_file(filename):
                continue
            full_path = os.path.join(dirpath, filename)
            if os.path.abspath(full_path) == out_path:
                continue
            rel_path = os.path.relpath(full_path, root)
            zf.write(full_path, rel_path)

print(f"Wrote {out_path}")
PY
