#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
python_bin="$repo_root/.venv/bin/python"
benchmark="$repo_root/pettachainer/benchmarks/core_suite.py"

if [[ ! -x "$python_bin" ]]; then
  printf 'Missing project interpreter: %s\n' "$python_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

has_repository=false
has_json_out=false
for argument in "$@"; do
  case "$argument" in
    --repository|--repository=*) has_repository=true ;;
    --json-out|--json-out=*) has_json_out=true ;;
  esac
done

arguments=("$@")
if [[ "$has_repository" == false ]]; then
  arguments=(--repository "$repo_root" "${arguments[@]}")
fi
if [[ "$has_json_out" == false ]]; then
  arguments+=(--json-out /tmp/pettachainer-performance.json)
fi

exec "$python_bin" "$benchmark" "${arguments[@]}"
