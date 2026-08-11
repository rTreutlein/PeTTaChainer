#!/usr/bin/env bash

set -u

# PeTTaChainer's arrows carry explicit determinism commitments. Run the
# supported suite in strict determinism mode by default; set PETTA_STRICT_DET=0
# only when auditing compatibility with PeTTa's uncommitted-arrow mode.
PETTA_STRICT_DET=${PETTA_STRICT_DET:-1}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
metta_dir="$repo_root/pettachainer/metta"
tests_dir="$repo_root/tests/metta"
examples_dir="$repo_root/examples/metta"
petta_bin="$repo_root/.venv/bin/petta"
cd "$metta_dir"
if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

pass=0
fail=0
fail_files=()

run_petta() {
  local args=("$@")

  if [[ ${PETTA_STRICT:-0} == 1 ]]; then
    args+=(--strict)
  fi
  if [[ ${PETTA_STRICT_DET:-0} == 1 ]]; then
    args+=(--strict-det)
  fi

  "$petta_bin" "${args[@]}"
}

run_file() {
  local file=$1

  if run_petta "$file" >/tmp/petta-last.log 2>&1; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$file"
  else
    fail=$((fail + 1))
    fail_files+=("$file")
    printf 'FAIL %s\n' "$file"
  fi
}

for file in "$tests_dir"/test*.metta; do
  run_file "$file"
done

while IFS= read -r file || [ -n "$file" ]; do
  case "$file" in
    ''|'#'*) continue ;;
  esac
  if [[ ( ${PETTA_STRICT:-0} == 1 || ${PETTA_STRICT_DET:-0} == 1 ) &&
        $file == *_libpln.metta ]]; then
    printf 'SKIP %s (libPLN is outside strict scope)\n' "$file"
    continue
  fi
  run_file "$examples_dir/$file"
done < "$examples_dir/supported.txt"

printf '\nSummary: %d passed, %d failed\n' "$pass" "$fail"

if [ "$fail" -gt 0 ]; then
  printf 'Failing files:\n'
  for file in "${fail_files[@]}"; do
    printf ' - %s\n' "$file"
  done
fi

exit "$fail"
