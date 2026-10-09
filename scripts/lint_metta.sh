#!/usr/bin/env bash
# Lint MeTTa files; without arguments, run the linter's own tests and lint
# every production file. Prints one warning report and one fix report per
# file and fails only when the linter itself fails.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
petta_bin="$repo_root/.venv/bin/petta"
if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  exit 2
fi
linter_dir="$repo_root/tools/metta-linter"
if (( $# == 0 )); then
  (cd "$linter_dir" && "$petta_bin" tests/test_metta_linter.metta silent)
  mapfile -t targets < <(find "$repo_root/pettachainer/metta" -name '*.metta' | sort)
else
  targets=()
  for file in "$@"; do
    targets+=("$(cd "$(dirname "$file")" && pwd)/$(basename "$file")")
  done
fi
runner="$(mktemp "$linter_dir/.lint_runner_XXXXXX.metta")"
trap 'rm -f "$runner"' EXIT

printf '%s\n' "!(import! &self \"$linter_dir/metta_linter\")" > "$runner"
for target in "${targets[@]}"; do
  printf '%s\n' "!(lint-file-report \"$target\")" >> "$runner"
  printf '%s\n' "!(lint-file-fix-report \"$target\")" >> "$runner"
done

cd "$linter_dir"
"$petta_bin" "$runner" silent
