#!/usr/bin/env bash
set -euo pipefail

# Package the repo into a ZIP archive for sharing/auditing.
# Usage: ./script/package_repo.sh [output_path_or_dir]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ARG="${1:-$ROOT_DIR/opensub.zip}"

python - <<'PY' "$ROOT_DIR" "$OUTPUT_ARG"
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

exclude_dirs = {".git", "out", "cache", "broadcast", ".secrets", "node_modules"}
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
    return False

with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
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
