#!/usr/bin/env bash

set -u

pass=0
fail=0
fail_files=()

run_file() {
  local file=$1

  if uv run petta "$file" >/tmp/petta-last.log 2>&1; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$file"
  else
    fail=$((fail + 1))
    fail_files+=("$file")
    printf 'FAIL %s\n' "$file"
  fi
}

for file in tests/test*.metta; do
  run_file "$file"
done

while IFS= read -r file || [ -n "$file" ]; do
  case "$file" in
    ''|'#'*) continue ;;
  esac
  run_file "$file"
done < examples/supported.txt

printf '\nSummary: %d passed, %d failed\n' "$pass" "$fail"

if [ "$fail" -gt 0 ]; then
  printf 'Failing files:\n'
  for file in "${fail_files[@]}"; do
    printf ' - %s\n' "$file"
  done
fi

exit "$fail"
