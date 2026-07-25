#!/usr/bin/env bash

set -euo pipefail

benchmark_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export PETTACHAINER_BENCHMARK="$benchmark_dir/../conceptnet_revision_stress_query.metta"
export PETTACHAINER_EXPECTED_RESULT='merge/revision'

exec "$benchmark_dir/run_conceptnet_own_pet_query.sh" "$@"
