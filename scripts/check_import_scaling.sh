#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
python_bin="$repo_root/.venv/bin/python"

if [[ ! -x "$python_bin" ]]; then
  printf 'Missing project interpreter: %s\n' "$python_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

cd "$repo_root"
exec "$python_bin" "$script_dir/check_import_scaling.py" "$@"
