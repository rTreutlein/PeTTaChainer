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

run_file() {
  local index=$1
  local file=$2
  local args=("$file")

  if [[ ${PETTA_STRICT:-0} == 1 ]]; then
    args+=(--strict)
  fi
  if [[ ${PETTA_STRICT_DET:-0} == 1 ]]; then
    args+=(--strict-det)
  fi

  if (cd "$metta_dir" && "$petta_bin" "${args[@]}") \
      >"$run_dir/$index.log" 2>&1; then
    printf 'PASS\n' >"$run_dir/$index.status"
  else
    printf 'FAIL\n' >"$run_dir/$index.status"
  fi
}

active=0
for index in "${!files[@]}"; do
  run_file "$index" "${files[$index]}" &
  active=$((active + 1))
  if (( active >= PETTA_JOBS )); then
    wait -n
    active=$((active - 1))
  fi
done
wait

pass=0
fail=0
fail_files=()
for index in "${!files[@]}"; do
  status=$(<"$run_dir/$index.status")
  if [[ $status == PASS ]]; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "${files[$index]}"
  else
    fail=$((fail + 1))
    fail_files+=("${files[$index]}")
    printf 'FAIL %s\n' "${files[$index]}"
    sed 's/^/  /' "$run_dir/$index.log"
  fi
done

printf '\nSummary: %d passed, %d failed\n' "$pass" "$fail"

if (( fail > 0 )); then
  printf 'Failing files:\n'
  for file in "${fail_files[@]}"; do
    printf ' - %s\n' "$file"
  done
fi

exit "$fail"
