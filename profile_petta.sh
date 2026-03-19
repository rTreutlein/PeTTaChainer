#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PETTA_DIR="${PETTA_DIR:-$(cd "$ROOT_DIR/../PeTTa" && pwd)}"
MAIN_PL="$PETTA_DIR/src/main.pl"
METTA_PL="$PETTA_DIR/src/metta.pl"
MORK_LIB="$PETTA_DIR/mork_ffi/target/release/libmork_ffi.so"
PROFILE_HOOK_PL="$ROOT_DIR/profile_no_show_hook.pl"
STACK_LIMIT="${STACK_LIMIT:-8g}"
MODE="${MODE:-swi-profile}"
TOP_N="${TOP_N:-30}"
CALLERS_OF="${CALLERS_OF:-}"
METTA_BASE_DIR="${METTA_BASE_DIR:-$ROOT_DIR/pettachainer/metta}"

usage() {
  cat <<'EOF'
Usage:
  ./profile_petta.sh [--mode time|swi-profile|perf] [--top N] [--callers PI] [--expr '!(...)'] [--no-mork] path/to/file.metta

Modes:
  time         Run with /usr/bin/time -v around the standard petta SWI invocation.
  swi-profile  Use SWI-Prolog's built-in deterministic profiler.
               Default profiles load_metta_file/2.
               With --expr, first loads the file unprofiled, then profiles process_metta_string/2.
  perf         Use Linux perf sampling around the standard petta SWI invocation.

Environment overrides:
  PETTA_DIR        Path to the PeTTa checkout. Default: ../PeTTa relative to this repo.
  METTA_BASE_DIR   Base directory used to resolve relative .metta paths.
                   Default: ./pettachainer/metta
  STACK_LIMIT      SWI-Prolog stack limit. Default: 8g
  MODE             Default mode if --mode is omitted. Default: swi-profile
  TOP_N            Rows shown by show_profile/1 in swi-profile mode. Default: 30
  CALLERS_OF       Predicate indicator to inspect after profiling, e.g. lists:member/2
  EXPR             MeTTa expression to profile after preloading the file, e.g.
                   '!(query 100 kb (: $prf (Goal) $tv))'

Examples:
  ./profile_petta.sh tests/testmining.metta
  ./profile_petta.sh --mode time benchmarks/demo_benchgen_forward_backward_compare.metta
  ./profile_petta.sh --callers lists:member/2 tests/testmining.metta
  ./profile_petta.sh --mode perf /abs/path/to/x.metta
  ./profile_petta.sh --expr '!(query 100 kb (: $prf (Goal) $tv))' x2.metta
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
expr_arg="${EXPR:-}"

normalize_callers_pi() {
  local raw="$1"
  local module_part=""
  local pred_part="$raw"
  local name_part=""
  local arity_part=""

  if [[ "$raw" == *:* ]]; then
    module_part="${raw%%:*}"
    pred_part="${raw#*:}"
  fi

  if [[ "$pred_part" != */* ]]; then
    printf '%s\n' "$raw"
    return
  fi

  name_part="${pred_part%/*}"
  arity_part="${pred_part##*/}"

  if [[ "$name_part" == \'*\' ]]; then
    :
  elif [[ "$name_part" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    :
  else
    name_part="'$name_part'"
  fi

  if [[ -n "$module_part" ]]; then
    printf '%s:%s/%s\n' "$module_part" "$name_part" "$arity_part"
  else
    printf '%s/%s\n' "$name_part" "$arity_part"
  fi
}

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
    --expr)
      [[ $# -ge 2 ]] || die "--expr requires a MeTTa expression such as '!(query 100 kb (: \$prf (Goal) \$tv))'"
      expr_arg="$2"
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
[[ -f "$PROFILE_HOOK_PL" ]] || die "Missing profile hook file: $PROFILE_HOOK_PL"

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
  swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file" "$@" -s
}

run_swi_profile() {
  cd "$metta_dir"
  local profile_goal
  local expr_file=""
  local summary_goal="profile_data(D), get_dict(summary, D, S), get_dict(ticks, S, Ticks), (Ticks =:= 0 -> format('~nNo profiler ticks collected. Goal finished too quickly for SWI deterministic profiling.~n', []) ; show_profile([top($top_n)]))"
  if [[ -n "$expr_arg" ]]; then
    expr_file="$(mktemp "$metta_dir/profile_petta_expr.XXXXXX.metta")"
    printf '%s\n' "$expr_arg" > "$expr_file"
    local expr_base
    expr_base="$(basename "$expr_file")"
    profile_goal="assertz(working_dir('.')),load_metta_file('$metta_base', _),asserta(profile_no_show),profile(load_metta_file('$expr_base', Results), [top($top_n)]),retractall(profile_no_show),maplist(writeln, Results),$summary_goal"
  else
    profile_goal="assertz(working_dir('.')),asserta(profile_no_show),profile(load_metta_file('$metta_base', Results), [top($top_n)]),retractall(profile_no_show),maplist(writeln, Results),$summary_goal"
  fi
  if [[ -n "$callers_of" ]]; then
    local callers_pi
    callers_pi="$(normalize_callers_pi "$callers_of")"
    local callers_escaped="${callers_pi//\\/\\\\}"
    callers_escaped="${callers_escaped//\"/\\\"}"
    swipl "${swipl_args[@]}" -s "$PROFILE_HOOK_PL" -s "$METTA_PL" \
      -g "use_module(library(prolog_profile)),$profile_goal,term_string(PI, \"$callers_escaped\"),(profile_procedure_data(PI, D) -> get_dict(callers, D, Callers), get_dict(callees, D, Callees), format('~nCALLERS OF ~q~n', [PI]), writeln('------------------------------------------------------------------------'), format('~w~t~24|~t~8+~w~t~38|~t~8+~w~t~52|~t~8+~w~t~66|~t~8+~w~n', ['Predicate', 'Calls', 'Redos', 'Self', 'Children']), writeln('------------------------------------------------------------------------'), forall(member(node(Pred,_Cycle,Self,Children,Calls,Redos,_Exits), Callers), format('~w~t~24|~t~8+~D~t~38|~t~8+~D~t~52|~t~8+~D~t~66|~t~8+~D~n', [Pred, Calls, Redos, Self, Children])), (Callers == [] -> writeln('(none)') ; true), format('~nCALLEES OF ~q~n', [PI]), writeln('------------------------------------------------------------------------'), format('~w~t~24|~t~8+~w~t~38|~t~8+~w~t~52|~t~8+~w~t~66|~t~8+~w~n', ['Predicate', 'Calls', 'Redos', 'Self', 'Children']), writeln('------------------------------------------------------------------------'), forall(member(node(Pred,_Cycle,Self,Children,Calls,Redos,_Exits), Callees), format('~w~t~24|~t~8+~D~t~38|~t~8+~D~t~52|~t~8+~D~t~66|~t~8+~D~n', [Pred, Calls, Redos, Self, Children])), (Callees == [] -> writeln('(none)') ; true) ; format('~nNo profile node found for ~q~n', [PI]))" \
      -t halt
  else
    swipl "${swipl_args[@]}" -s "$PROFILE_HOOK_PL" -s "$METTA_PL" \
      -g "$profile_goal" \
      -t halt
  fi
  if [[ -n "$expr_file" ]]; then
    rm -f "$expr_file"
  fi
}

case "$mode" in
  time)
    cd "$metta_dir"
    /usr/bin/time -v swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file" -s
    ;;
  swi-profile)
    run_swi_profile
    ;;
  perf)
    cd "$metta_dir"
    perf record --call-graph dwarf -- swipl "${swipl_args[@]}" -s "$MAIN_PL" -- "$metta_file" -s
    ;;
  *)
    die "Unsupported mode: $mode"
    ;;
esac
