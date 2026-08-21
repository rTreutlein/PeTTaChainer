#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s <base-ref> [member|durable] [--pairs N]\n' "${0##*/}" >&2
}

if (( $# < 1 )); then
  usage
  exit 2
fi

base_ref=$1
shift
workload=member
pairs=8

if (( $# > 0 )) && [[ $1 != -* ]]; then
  workload=$1
  shift
fi

while (( $# > 0 )); do
  case $1 in
    --pairs)
      if (( $# < 2 )); then
        usage
        exit 2
      fi
      pairs=$2
      shift 2
      ;;
    --pairs=*)
      pairs=${1#*=}
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ $workload != member && $workload != durable ]]; then
  printf 'Unknown workload: %s\n' "$workload" >&2
  usage
  exit 2
fi
if [[ ! $pairs =~ ^[1-9][0-9]*$ ]]; then
  printf 'Pair count must be a positive integer, got: %s\n' "$pairs" >&2
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

if ! base_commit=$(git -C "$repo_root" rev-parse --verify "$base_ref^{commit}"); then
  printf 'Base ref does not resolve to a commit: %s\n' "$base_ref" >&2
  exit 2
fi

temp_root=$(mktemp -d /tmp/pettachainer-ab.XXXXXX)
temp_repo="$temp_root/repository"
base_worktree="$temp_root/base"
base_added=0

cleanup() {
  if [[ $base_added == 1 ]]; then
    git -C "$temp_repo" worktree remove --force "$base_worktree" >/dev/null 2>&1 || true
  fi
  rm -rf "$temp_root"
}
trap cleanup EXIT

# A private shared clone lets the harness create a real temporary worktree
# without modifying the candidate checkout's worktree registry.
git clone --quiet --shared --no-checkout "$repo_root" "$temp_repo"
git -C "$temp_repo" worktree add --quiet --detach "$base_worktree" "$base_commit"
base_added=1
ln -s "$repo_root/.venv" "$base_worktree/.venv"

case $workload in
  member)
    module=pettachainer.benchmarks.member_inheritance
    workload_args=(
      --initial-members 48
      --deltas 4
      --query-steps 400
      --forward-steps 1
    )
    ;;
  durable)
    module=pettachainer.benchmarks.durable_query_many
    workload_args=(
      --roots 8
      --stable-roots 2
      --shifts 5
      --steps 300
    )
    ;;
esac

run_one() {
  local side=$1
  local pair=$2
  local checkout=$3
  local json_file="$temp_root/${side}-${pair}.json"
  local log_file="$temp_root/${side}-${pair}.log"
  local run_started=$SECONDS

  printf 'pair %d/%d %-9s start\n' "$pair" "$pairs" "$side"
  if ! (
    cd "$checkout"
    PYTHONPATH="$checkout/pettachainer/benchmarks" \
      .venv/bin/python -m "$module" \
      "${workload_args[@]}" --json-out "$json_file"
  ) >"$log_file" 2>&1; then
    printf 'pair %d/%d %s FAILED\n' "$pair" "$pairs" "$side" >&2
    sed -n '1,240p' "$log_file" >&2
    return 1
  fi
  printf 'pair %d/%d %-9s done (%ss)\n' \
    "$pair" "$pairs" "$side" "$((SECONDS - run_started))"
}

printf 'workload: %s\n' "$workload"
printf 'base:      %s (%s)\n' "$base_ref" "${base_commit:0:12}"
printf 'candidate: %s\n' "$repo_root"
printf 'pairs:     %d\n' "$pairs"

# Alternate which side runs first each pair: a fixed order gives the
# second side a small systematic penalty on short workloads.
for ((pair = 1; pair <= pairs; pair++)); do
  if (( pair % 2 )); then
    run_one base "$pair" "$base_worktree"
    run_one candidate "$pair" "$repo_root"
  else
    run_one candidate "$pair" "$repo_root"
    run_one base "$pair" "$base_worktree"
  fi
done

json_files=()
for ((pair = 1; pair <= pairs; pair++)); do
  json_files+=("$temp_root/base-$pair.json" "$temp_root/candidate-$pair.json")
done

"$python_bin" - "$pairs" "${json_files[@]}" <<'PY'
import json
import math
import statistics
import sys
from pathlib import Path

pairs = int(sys.argv[1])
paths = [Path(value) for value in sys.argv[2:]]
base_rows = []
candidate_rows = []
for index in range(pairs):
    base_rows.append(json.loads(paths[index * 2].read_text(encoding="utf-8")))
    candidate_rows.append(
        json.loads(paths[index * 2 + 1].read_text(encoding="utf-8"))
    )

def second_metrics(row):
    return {
        key: float(value)
        for key, value in row.items()
        if key.endswith("_seconds")
        and isinstance(value, (int, float))
        and math.isfinite(value)
    }

base_metrics = [second_metrics(row) for row in base_rows]
candidate_metrics = [second_metrics(row) for row in candidate_rows]
keys = sorted(base_metrics[0])
if not keys:
    raise SystemExit("benchmark emitted no scalar *_seconds metrics")
for pair, (base, candidate) in enumerate(
    zip(base_metrics, candidate_metrics), 1
):
    if sorted(base) != keys or sorted(candidate) != keys:
        raise SystemExit(f"pair {pair} emitted a different seconds schema")

failed = False
print()
print(f"{'METRIC':42} {'BASE MEDIAN':>13} {'CAND MEDIAN':>13} {'DELTA':>9} STATUS")
print(f"{'-' * 42} {'-' * 13} {'-' * 13} {'-' * 9} ------")
for key in keys:
    base_values = [row[key] for row in base_metrics]
    candidate_values = [row[key] for row in candidate_metrics]
    base_median = statistics.median(base_values)
    candidate_median = statistics.median(candidate_values)
    if base_median == 0.0:
        delta = 0.0 if candidate_median == 0.0 else math.inf
    else:
        delta = (candidate_median / base_median - 1.0) * 100.0
    status = "FAIL" if delta > 5.0 else "PASS"
    failed = failed or status == "FAIL"
    delta_text = f"{delta:+.2f}%" if math.isfinite(delta) else "+inf%"
    print(
        f"{key:42} {base_median:13.6f} {candidate_median:13.6f} "
        f"{delta_text:>9} {status}"
    )

raise SystemExit(1 if failed else 0)
PY
