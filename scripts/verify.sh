#!/usr/bin/env bash

set -u

# Where bench.slice exists (see docs/agent_workflow.md), run inside it: its
# memory cap is shared by all jobs, so an OOM kills a test, not the pane.
if systemctl --user cat bench.slice >/dev/null 2>&1 && ! grep -q bench.slice /proc/self/cgroup; then
  exec systemd-run --user --scope --quiet --collect --slice=bench.slice -p OOMPolicy=continue -- "$0" "$@"
fi

if (( $# != 0 )); then
  printf 'Usage: %s\n' "${0##*/}" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
python_bin="$repo_root/.venv/bin/python"

if [[ ! -x "$python_bin" ]]; then
  printf 'Missing project interpreter: %s\n' "$python_bin" >&2
  printf 'Run uv sync --frozen first.\n' >&2
  exit 2
fi

run_dir=$(mktemp -d /tmp/pettachainer-verify.XXXXXX)
cleanup() {
  rm -rf "$run_dir"
}
trap cleanup EXIT

gate_ids=(lint metta python import_scaling conceptnet)
declare -A gate_names=(
  [lint]='MeTTa lint'
  [metta]='MeTTa suite'
  [python]='Python unittest'
  [import_scaling]='Import scaling'
  [conceptnet]='ConceptNet query'
)
declare -A gate_status
declare -A defect_status

run_gate() {
  local gate_id=$1
  shift
  local log_file="$run_dir/$gate_id.log"
  local metrics_file="$run_dir/$gate_id.metrics.jsonl"
  local command_status=0
  local metric_status=0
  local metric_summary

  printf '\n== %s ==\n' "${gate_names[$gate_id]}"
  (
    cd "$repo_root"
    PETTACHAINER_QUERY_METRICS_PATH="$metrics_file" "$@"
  ) 2>&1 | tee "$log_file"
  command_status=${PIPESTATUS[0]}

  if [[ -s "$metrics_file" ]]; then
    metric_summary=$(
      "$python_bin" - "$metrics_file" <<'PY'
import json
import math
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = 0
aborts = 0
try:
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        row = json.loads(line)
        # An engine without an abort path reports none.
        value = row.get("search_aborts", 0)
        if not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(f"line {line_number} has invalid search_aborts")
        if value < 0 or int(value) != value:
            raise ValueError(f"line {line_number} has invalid search_aborts")
        rows += 1
        aborts += int(value)
except (OSError, ValueError, json.JSONDecodeError) as error:
    print(f"invalid metric stream: {error}")
    raise SystemExit(2)

print(f"{rows} query row(s), {aborts} abort(s)")
raise SystemExit(1 if aborts else 0)
PY
    )
    metric_status=$?
    defect_status[$gate_id]="$metric_summary"
  else
    case $gate_id in
      metta)
        defect_status[$gate_id]='every child log checked for aborts'
        ;;
      python)
        defect_status[$gate_id]='metric stream missing'
        metric_status=1
        ;;
      import_scaling)
        defect_status[$gate_id]='no backward queries'
        ;;
      lint)
        defect_status[$gate_id]='no queries'
        ;;
      *)
        defect_status[$gate_id]='counter unavailable; abort marker scan'
        ;;
    esac
  fi

  if grep -Fq 'backward-search-aborted' "$log_file"; then
    printf 'STRICT DEFECT FAILURE: backward-search-aborted was printed.\n' >&2
    metric_status=1
    defect_status[$gate_id]="${defect_status[$gate_id]}; abort marker seen"
  fi

  if (( command_status == 0 && metric_status == 0 )); then
    gate_status[$gate_id]=PASS
  else
    gate_status[$gate_id]=FAIL
  fi
}

started=$SECONDS

run_gate lint "$repo_root/scripts/lint_metta.sh"
run_gate metta "$repo_root/scripts/test_metta.sh"
run_gate python "$python_bin" -m unittest discover -s tests
run_gate import_scaling "$repo_root/scripts/check_import_scaling.sh"
run_gate conceptnet "$repo_root/benchmarks/metta/run_conceptnet_own_pet_query.sh"

conceptnet_log="$run_dir/conceptnet.log"
conceptnet_summaries=$(grep -Ec 'CONCEPTNET_OWN_PET_RESULT_COUNT [0-9]+ RESULTS' "$conceptnet_log" || true)
conceptnet_exact=$(grep -Ec 'CONCEPTNET_OWN_PET_RESULT_COUNT 2 RESULTS' "$conceptnet_log" || true)
if (( conceptnet_summaries != 1 || conceptnet_exact != 1 )); then
  printf 'ConceptNet result-row check failed: expected one summary declaring 2 results.\n' >&2
  gate_status[conceptnet]=FAIL
fi

elapsed=$((SECONDS - started))
failed=0
printf '\n%-18s %-6s %s\n' GATE STATUS 'STRICT DEFECT CHECK'
printf '%-18s %-6s %s\n' '------------------' '------' '-------------------'
for gate_id in "${gate_ids[@]}"; do
  printf '%-18s %-6s %s\n' \
    "${gate_names[$gate_id]}" "${gate_status[$gate_id]}" \
    "${defect_status[$gate_id]}"
  if [[ ${gate_status[$gate_id]} != PASS ]]; then
    failed=1
  fi
done
printf 'Total wall time: %ss\n' "$elapsed"

exit "$failed"
