#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/file.metta" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
petta_bin="$repo_root/.venv/bin/petta"
if [[ ! -x "$petta_bin" ]]; then
  printf 'Missing pinned PeTTa executable: %s\n' "$petta_bin" >&2
  exit 2
fi
target="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
runner="$(mktemp "$repo_root/tools/metta-linter/.lint_runner_XXXXXX.metta")"
trap 'rm -f "$runner"' EXIT

printf '%s\n' "!(import! &self \"$repo_root/tools/metta-linter/metta_linter\")" > "$runner"
printf '%s\n' "!(println! (lint-file-report \"$target\"))" >> "$runner"
printf '%s\n' "!(println! (lint-file-fix-report \"$target\"))" >> "$runner"

cd "$repo_root/tools/metta-linter"
"$petta_bin" "$runner" silent
