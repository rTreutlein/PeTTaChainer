#!/usr/bin/env bash

set -u

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
metta_dir="$repo_root/pettachainer/metta"
petta_bin="$repo_root/.venv/bin/petta"

if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

files=("$@")
if (( ${#files[@]} == 0 )); then
  files=(
    "$repo_root/tests/metta/test_frontier_pooling.metta"
    "$repo_root/tests/metta/test_inheritance_query_proof.metta"
  )
fi

for index in "${!files[@]}"; do
  files[$index]=$(realpath "${files[$index]}")
done

PETTA_JOBS=${PETTA_JOBS:-$(nproc)}
if [[ ! $PETTA_JOBS =~ ^[1-9][0-9]*$ ]]; then
  printf 'PETTA_JOBS must be a positive integer, got: %s\n' "$PETTA_JOBS" >&2
  exit 2
fi

PETTA_FORK_TEST_FILES=$(IFS=:; printf '%s' "${files[*]}")
PETTA_FORK_LOG_DIR=$(mktemp -d /tmp/petta-fork-suite.XXXXXX)
trap 'rm -rf "$PETTA_FORK_LOG_DIR"' EXIT
export PETTA_FORK_TEST_FILES PETTA_FORK_LOG_DIR PETTA_JOBS

cd "$metta_dir"
"$petta_bin" "$script_dir/fork_test_runner.metta" --strict-det --silent
