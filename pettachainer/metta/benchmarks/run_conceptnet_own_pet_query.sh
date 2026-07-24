#!/usr/bin/env bash

set -euo pipefail

benchmark_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$benchmark_dir/../../.." && pwd)
benchmark="$benchmark_dir/../conceptnet_own_pet_query.metta"
export_link="$benchmark_dir/../.conceptnet_export"
created_link=0
output_file=$(mktemp /tmp/pettachainer-conceptnet-benchmark.XXXXXX.log)

cleanup() {
  rm -f "$output_file"
  if [[ $created_link == 1 ]]; then
    rm -f "$export_link"
  fi
}
trap cleanup EXIT

if [[ -z ${CNET_DIR:-} ]]; then
  common_dir=$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)
  canonical_repo=$(dirname "$common_dir")
  CNET_DIR=$(cd "$canonical_repo/.." && pwd)/cnet
fi

if [[ ! -f "$CNET_DIR/rules_dump.pl" ]]; then
  printf 'Missing ConceptNet export: %s/rules_dump.pl\n' "$CNET_DIR" >&2
  printf 'Set CNET_DIR to the cnet checkout containing rules_dump.pl.\n' >&2
  exit 2
fi

if [[ ${CNET_REFRESH:-0} != 1 &&
      -f "$CNET_DIR/dumppln.txt" &&
      "$CNET_DIR/dumppln.txt" -nt "$CNET_DIR/rules_dump.pl" ]]; then
  printf 'ConceptNet source dump is newer than rules_dump.pl.\n' >&2
  printf 'Retry with CNET_REFRESH=1 to rebuild the exported rules.\n' >&2
  exit 2
fi

if [[ ${CNET_REFRESH:-0} == 1 ]]; then
  (
    cd "$CNET_DIR"
    uv run cnet export-rules dumppln.txt --out rules_dump.pl
    swipl -q -g "qcompile('rules_dump.pl'),halt"
  )
elif [[ ! -f "$CNET_DIR/rules_dump.qlf" ||
        "$CNET_DIR/rules_dump.pl" -nt "$CNET_DIR/rules_dump.qlf" ]]; then
  printf 'Refreshing stale compiled export %s/rules_dump.qlf\n' "$CNET_DIR" >&2
  (
    cd "$CNET_DIR"
    swipl -q -g "qcompile('rules_dump.pl'),halt"
  )
fi

if [[ -e "$export_link" || -L "$export_link" ]]; then
  if [[ ! -L "$export_link" ||
        $(readlink -f "$export_link") != $(readlink -f "$CNET_DIR") ]]; then
    printf 'Refusing to replace existing benchmark export path: %s\n' "$export_link" >&2
    exit 2
  fi
else
  ln -s "$CNET_DIR" "$export_link"
  created_link=1
fi

if [[ -n ${PETTA_DIR:-} ]]; then
  if [[ ! -f "$PETTA_DIR/mork_ffi/target/release/libmork_ffi.so" ]]; then
    printf 'The selected PETTA_DIR has no built MORK runtime: %s\n' "$PETTA_DIR" >&2
    printf 'Build or link mork_ffi before running this benchmark.\n' >&2
    exit 2
  fi
  runner=(sh "$PETTA_DIR/run.sh")
else
  runner=(petta)
fi

set +e
"${runner[@]}" "$benchmark" -s "$@" 2>&1 | tee "$output_file"
run_status=${PIPESTATUS[0]}
set -e

if [[ $run_status != 0 ]]; then
  exit "$run_status"
fi

if ! grep -Eq 'CONCEPTNET_OWN_PET_RESULT_COUNT [1-9][0-9]* RESULTS' "$output_file" ||
   ! grep -Fq '(And (Own (i max)) (Pet max))' "$output_file"; then
  printf 'ConceptNet benchmark produced no proof. The export may need refreshing.\n' >&2
  printf 'Retry with CNET_REFRESH=1, then verify the exported KB identifier.\n' >&2
  exit 1
fi
