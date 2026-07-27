#!/usr/bin/env bash

set -euo pipefail

benchmark_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$benchmark_dir/../../.." && pwd)
strict_export=$(dirname "$repo_root")/cnet/exports/typecheck-v2-strict
if [[ -z ${CNET_DIR:-} && -f "$strict_export/rules_dump.pl" ]]; then
  export CNET_DIR=$strict_export
fi
export PETTACHAINER_BENCHMARK=${PETTACHAINER_BENCHMARK:-"$benchmark_dir/../conceptnet_revision_stress_query.metta"}
export PETTACHAINER_EXPECTED_RESULT=${PETTACHAINER_EXPECTED_RESULT:-merge/revision}

exec "$benchmark_dir/run_conceptnet_own_pet_query.sh" "$@"
