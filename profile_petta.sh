#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PETTA_DIR="${PETTA_DIR:-$(cd "$ROOT_DIR/../PeTTa" && pwd)}"
MAIN_PL="$PETTA_DIR/src/main.pl"
METTA_PL="$PETTA_DIR/src/metta.pl"
MORK_LIB="$PETTA_DIR/mork_ffi/target/release/libmork_ffi.so"
STACK_LIMIT="${STACK_LIMIT:-8g}"
MODE="${MODE:-swi-profile}"
TOP_N="${TOP_N:-30}"
CALLERS_OF="${CALLERS_OF:-}"
METTA_BASE_DIR="${METTA_BASE_DIR:-$ROOT_DIR/pettachainer/metta}"

usage() {
  cat <<'EOF'
Usage:
  ./profile_petta.sh [--mode time|swi-profile|perf] [--top N] [--callers PI] [--no-mork] path/to/file.metta

Modes:
  time         Run with /usr/bin/time -v around the standard petta SWI invocation.
  swi-profile  Use SWI-Prolog's built-in deterministic profiler around load_metta_file/2.
  perf         Use Linux perf sampling around the standard petta SWI invocation.

Environment overrides:
  PETTA_DIR        Path to the PeTTa checkout. Default: ../PeTTa relative to this repo.
  METTA_BASE_DIR   Base directory used to resolve relative .metta paths.
                   Default: ./pettachainer/metta
  STACK_LIMIT      SWI-Prolog stack limit. Default: 8g
  MODE             Default mode if --mode is omitted. Default: swi-profile
  TOP_N            Rows shown by show_profile/1 in swi-profile mode. Default: 30
  CALLERS_OF       Predicate indicator to inspect after profiling, e.g. lists:member/2

Examples:
  ./profile_petta.sh tests/testmining.metta
  ./profile_petta.sh --mode time benchmarks/demo_benchgen_forward_backward_compare.metta
  ./profile_petta.sh --callers lists:member/2 tests/testmining.metta
  ./profile_petta.sh --mode perf /abs/path/to/x.metta
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

mode="$MODE"
top_n="$TOP_N"
callers_of="$CALLERS_OF"
use_mork=1
metta_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode requires a value"
      mode="$2"
      shift 2
      ;;
    --top)
      [[ $# -ge 2 ]] || die "--top requires a value"
      top_n="$2"
      shift 2
      ;;
    --callers)
      [[ $# -ge 2 ]] || die "--callers requires a predicate indicator such as lists:member/2"
      callers_of="$2"
      shift 2
      ;;
    --no-mork)
      use_mork=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$metta_arg" ]] || die "Only one .metta path is supported"
      metta_arg="$1"
      shift
      ;;
  esac
done

[[ -n "$metta_arg" ]] || {
  usage
  exit 1
}

[[ -f "$MAIN_PL" ]] || die "Missing SWI entrypoint: $MAIN_PL"
[[ -f "$METTA_PL" ]] || die "Missing SWI library file: $METTA_PL"

if [[ "$metta_arg" = /* ]]; then
  metta_file="$metta_arg"
else
  metta_file="$METTA_BASE_DIR/$metta_arg"
fi

[[ -f "$metta_file" ]] || die "MeTTa file not found: $metta_file"

metta_file="$(cd "$(dirname "$metta_file")" && pwd)/$(basename "$metta_file")"
metta_dir="$(dirname "$metta_file")"
metta_base="$(basename "$metta_file")"

swipl_args=(--stack_limit="$STACK_LIMIT" -q)
if [[ $use_mork -eq 1 && -f "$MORK_LIB" ]]; then
  export LD_PRELOAD="$MORK_LIB"
fi

run_standard() {
  swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file" "$@"
}

run_swi_profile() {
  cd "$metta_dir"
  if [[ -n "$callers_of" ]]; then
    swipl "${swipl_args[@]}" -s "$METTA_PL" \
      -g "use_module(library(prolog_profile)),assertz(working_dir('.')),profile(load_metta_file('$metta_base', Results), [top($top_n)]),maplist(writeln, Results),show_profile([top($top_n)]),term_string(PI, '$callers_of'),profile_data(P),forall(member(N, P.nodes),(N.predicate = PI -> (format('~nCALLERS OF ~q~n', [PI]),maplist(writeln, N.callers),format('~nCALLEES OF ~q~n', [PI]),maplist(writeln, N.callees)) ; true))" \
      -t halt
  else
    swipl "${swipl_args[@]}" -s "$METTA_PL" \
      -g "assertz(working_dir('.')),profile(load_metta_file('$metta_base', Results)),maplist(writeln, Results),show_profile([top($top_n)])" \
      -t halt
  fi
}

case "$mode" in
  time)
    cd "$metta_dir"
    /usr/bin/time -v swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file"
    ;;
  swi-profile)
    run_swi_profile
    ;;
  perf)
    cd "$metta_dir"
    perf record --call-graph dwarf -- swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file"
    ;;
  *)
    die "Unsupported mode: $mode"
    ;;
esac
