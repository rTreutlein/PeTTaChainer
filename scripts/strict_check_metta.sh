#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
metta_dir="$repo_root/pettachainer/metta"
petta_bin="$repo_root/.venv/bin/petta"

if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

# bootstrap.metta owns the dependency order and runtime helper imports. Loading
# the public entry checks every production module without a second, drifting
# copy of that initialization sequence in the checker.
cd "$metta_dir"
"$petta_bin" "$metta_dir/petta_chainer.metta" --strict --strict-det --silent
