#!/usr/bin/env bash

set -u

PETTA_STRICT_DET=${PETTA_STRICT_DET:-1}
PETTA_JOBS=${PETTA_JOBS:-$(nproc)}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
metta_dir="$repo_root/pettachainer/metta"
tests_dir="$repo_root/tests/metta"
examples_dir="$repo_root/examples/metta"
petta_bin="$repo_root/.venv/bin/petta"

if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

if [[ ! $PETTA_JOBS =~ ^[1-9][0-9]*$ ]]; then
  printf 'PETTA_JOBS must be a positive integer, got: %s\n' "$PETTA_JOBS" >&2
  exit 2
fi

files=()
for file in "$tests_dir"/test*.metta; do
  files+=("$file")
done

while IFS= read -r file || [[ -n $file ]]; do
  case "$file" in
    ''|'#'*) continue ;;
  esac
  if [[ ( ${PETTA_STRICT:-0} == 1 || ${PETTA_STRICT_DET:-0} == 1 ) &&
        $file == *_libpln.metta ]]; then
    printf 'SKIP %s (libPLN is outside strict scope)\n' "$file"
    continue
  fi
  files+=("$examples_dir/$file")
done < "$examples_dir/supported.txt"

run_dir=$(mktemp -d /tmp/petta-suite.XXXXXX)
trap 'rm -rf "$run_dir"' EXIT
manifest="$run_dir/files"
printf '%s\n' "${files[@]}" >"$manifest"

args=("$script_dir/fork_test_runner.metta" --silent)
if [[ ${PETTA_STRICT:-0} == 1 ]]; then
  args+=(--strict)
fi
if [[ ${PETTA_STRICT_DET:-0} == 1 ]]; then
  args+=(--strict-det)
fi

export PETTA_FORK_TEST_MANIFEST="$manifest"
export PETTA_FORK_LOG_DIR="$run_dir"
export PETTA_JOBS

cd "$metta_dir"
"$petta_bin" "${args[@]}"
