#!/usr/bin/env bash

set -u

pass=0
fail=0
fail_files=()

for file in tests/test*.metta; do
  if petta "$file" >/tmp/petta-last.log 2>&1; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$file"
  else
    fail=$((fail + 1))
    fail_files+=("$file")
    printf 'FAIL %s\n' "$file"
  fi
done

printf '\nSummary: %d passed, %d failed\n' "$pass" "$fail"

if [ "$fail" -gt 0 ]; then
  printf 'Failing files:\n'
  for file in "${fail_files[@]}"; do
    printf ' - %s\n' "$file"
  done
fi

exit "$fail"
