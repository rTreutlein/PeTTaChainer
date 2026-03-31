#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 path/to/file.metta" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
runner="$(mktemp "$repo_root/pettachainer/metta/linter/.lint_runner_XXXXXX.metta")"
trap 'rm -f "$runner"' EXIT

printf '%s\n' "!(import! &self \"$repo_root/pettachainer/metta/linter/metta_linter\")" > "$runner"
printf '%s\n' "!(println! (lint-file-summary-report \"$target\"))" >> "$runner"

cd "$repo_root/pettachainer/metta/linter"
petta "$runner" silent
