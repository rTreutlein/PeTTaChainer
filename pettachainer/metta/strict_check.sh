#!/usr/bin/env bash
set -euo pipefail

metta_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$metta_dir/../.." && pwd)
if [[ -z ${PETTA_DIR:-} && -f "$(dirname "$repo_root")/PeTTa/run.sh" ]]; then
  PETTA_DIR=$(dirname "$repo_root")/PeTTa
fi
if [[ -z ${PETTA_DIR:-} ]]; then
  echo "PETTA_DIR must point to a PeTTa typecheck-v2 checkout" >&2
  exit 2
fi

petta_dir=$(cd "$PETTA_DIR" && pwd)

# Load every dependency and production module under strict determinism mode so
# no import boundary can hide a type or determinism error. Plain -> arrows are
# deterministic commitments; genuinely nondeterministic functions must say so.
goal="assertz(working_dir('$metta_dir')),
load_metta_file('$petta_dir/lib/lib_roman.metta',_),
load_metta_file('$petta_dir/lib/lib_spaces.metta',_),
load_metta_file('$metta_dir/chainer_types.metta',_),
load_metta_file('$metta_dir/logic_config.metta',_),
load_metta_file('$metta_dir/dist_formulas.metta',_),
load_metta_file('$metta_dir/tv_formulas.metta',_),
load_metta_file('$metta_dir/compile.metta',_),
load_metta_file('$metta_dir/chainer_utils.metta',_),
load_metta_file('$metta_dir/forward_chainer.metta',_),
load_metta_file('$metta_dir/compiled_query_runtime.metta',_),
load_metta_file('$metta_dir/backward_proof_store.metta',_),
load_metta_file('$metta_dir/backward_chainer.metta',_),
load_metta_file('$metta_dir/query_runtime.metta',_),
halt"

swipl -q -s "$petta_dir/src/metta.pl" -g "$goal" -- --strict-det --silent

# The public entry module owns its imports. Check it in a fresh process so the
# same libraries are not deliberately loaded twice by this script.
entry_goal="assertz(working_dir('$metta_dir')),
load_metta_file('$metta_dir/petta_chainer.metta',_),
halt"

swipl -q -s "$petta_dir/src/metta.pl" -g "$entry_goal" -- --strict-det --silent
