#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
metta_dir="$repo_root/pettachainer/metta"
python_bin="${PYTHON_BIN:-$repo_root/.venv/bin/python}"
if [[ ! -x "$python_bin" ]]; then
  printf 'Missing project interpreter: %s\n' "$python_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

petta_dir=$($python_bin -c 'from petta import _resolve_petta_path; print(_resolve_petta_path())')
cd "$metta_dir"

# Load every dependency and production module under strict determinism mode so
# no import boundary can hide a type or determinism error. Every arrow carries
# an explicit det, semidet, or nondet commitment.
goal="assertz(working_dir('$metta_dir')),
load_metta_file('$petta_dir/lib/lib_roman.metta',_),
load_metta_file('$petta_dir/lib/lib_spaces.metta',_),
load_metta_file('$metta_dir/core/types.metta',_),
load_metta_file('$metta_dir/core/logic_config.metta',_),
load_metta_file('$metta_dir/core/formulas/distributions.metta',_),
load_metta_file('$metta_dir/core/formulas/fold_inverse.metta',_),
load_metta_file('$metta_dir/core/formulas/compute_inverse.metta',_),
load_metta_file('$metta_dir/core/formulas/truth_values.metta',_),
load_metta_file('$metta_dir/compiler/compiler.metta',_),
load_metta_file('$metta_dir/runtime/values.metta',_),
load_metta_file('$metta_dir/runtime/scheduling.metta',_),
load_metta_file('$metta_dir/runtime/evidence.metta',_),
load_metta_file('$metta_dir/runtime/base_rates.metta',_),
load_metta_file('$metta_dir/runtime/forward/canonical.metta',_),
load_metta_file('$metta_dir/runtime/forward/aggregates.metta',_),
load_metta_file('$metta_dir/runtime/forward/engine.metta',_),
load_metta_file('$metta_dir/runtime/knowledge_store.metta',_),
load_metta_file('$metta_dir/runtime/ingest.metta',_),
load_metta_file('$metta_dir/runtime/backward/metrics.metta',_),
load_metta_file('$metta_dir/runtime/backward/proof_store.metta',_),
load_metta_file('$metta_dir/runtime/backward/proof_merge.metta',_),
load_metta_file('$metta_dir/runtime/backward/search.metta',_),
load_metta_file('$metta_dir/runtime/backward/rule_matching.metta',_),
load_metta_file('$metta_dir/runtime/backward/aggregates.metta',_),
load_metta_file('$metta_dir/runtime/backward/engine.metta',_),
load_metta_file('$metta_dir/runtime/query.metta',_),
halt"

swipl -q -s "$petta_dir/src/main.pl" -g "$goal" -- --strict-det --silent

# The public entry module owns its imports. Check it in a fresh process so the
# same libraries are not deliberately loaded twice by this script.
entry_goal="assertz(working_dir('$metta_dir')),
load_metta_file('$metta_dir/petta_chainer.metta',_),
halt"

swipl -q -s "$petta_dir/src/main.pl" -g "$entry_goal" -- --strict-det --silent
