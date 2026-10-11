#!/usr/bin/env bash
# Land an agent branch on master: rebase it onto master in a worktree of its
# own, run every gate and the full benchmark comparison, and only then
# fast-forward master. With --chainergame, merge a ChainerGame branch into
# supply-network the same way (no rebase) and run its tests against the
# rebased PeTTaChainer. See docs/agent_workflow.md ("Landing a branch").
#
# Without --push this is a dry run: it runs every check and prints what it
# would change. With --push, and only when every check passed, it
# fast-forwards master (and supply-network), pushes both, and removes the
# landed worktrees and branches.

set -euo pipefail

usage() {
  printf 'Usage: %s <branch> [--chainergame <branch>] [--push]\n' "${0##*/}" >&2
  exit 2
}

branch=
cg_branch=
push=0
while (( $# )); do
  case $1 in
    --chainergame) (( $# >= 2 )) || usage; cg_branch=$2; shift 2 ;;
    --push) push=1; shift ;;
    -*) usage ;;
    *) [[ -z $branch ]] || usage; branch=$1; shift ;;
  esac
done
[[ -n $branch && $branch != master ]] || usage

main=$(dirname "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir)")
cg_main=/nexus/Dev/OpenCog/ChainerGame-supply
cg_python=/nexus/Dev/OpenCog/ChainerGame-problog/.venv-problog/bin/python
capped=/nexus/Dev/OpenCog/bench/capped
compare=/nexus/Dev/OpenCog/bench/compare.sh

step() { printf '\n== %s\n' "$*"; }
die() { printf '\nland: STOP: %s\n' "$*" >&2; exit 1; }
# Runs a landing command with --push, prints it otherwise.
act() {
  if (( push )); then
    printf '+ %s\n' "$*"
    "$@"
  else
    printf 'dry run, would run: %s\n' "$*"
  fi
}

# The worktree a branch is checked out in, empty when there is none.
worktree_of() {
  git -C "$1" worktree list --porcelain |
    awk -v ref="refs/heads/$2" '/^worktree /{wt=substr($0, 10)} $0 == "branch " ref {print wt}'
}

# Refuses a checkout with uncommitted changes to tracked files or on the
# wrong branch. Untracked files stay: a fast-forward refuses to overwrite one.
require_clean() {
  local dir=$1 want=$2
  [[ $(git -C "$dir" branch --show-current) == "$want" ]] || die "$dir is not on $want"
  [[ -z $(git -C "$dir" status --porcelain --untracked-files=no) ]] || {
    git -C "$dir" status --short --untracked-files=no >&2
    die "$dir has uncommitted changes"
  }
}

git -C "$main" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || die "no branch $branch"
require_clean "$main" master
if [[ -n $cg_branch ]]; then
  git -C "$cg_main" rev-parse --verify --quiet "refs/heads/$cg_branch" >/dev/null || die "no ChainerGame branch $cg_branch"
  require_clean "$cg_main" supply-network
fi

name=${branch//\//-}
land_wt=$main/.claude/worktrees/land-$name
logs=$main/.claude/land-logs/$name-$(date +%Y%m%d-%H%M%S)
cg_land=
[[ -z $cg_branch ]] || cg_land=/nexus/Dev/OpenCog/ChainerGame-land-${cg_branch//\//-}
for dir in "$land_wt" $cg_land; do
  [[ ! -e $dir ]] || die "$dir exists from an earlier landing; remove it with git worktree remove"
done
mkdir -p "$logs"

# The landing worktrees are this script's own; git removes them on any exit.
cleanup() {
  if [[ -d $land_wt ]]; then git -C "$main" worktree remove --force "$land_wt"; fi
  if [[ -n $cg_land && -d $cg_land ]]; then git -C "$cg_main" worktree remove --force "$cg_land"; fi
}
trap cleanup EXIT

step "Rebase $branch onto master ($(git -C "$main" rev-parse --short master))"
git -C "$main" worktree add --quiet --detach "$land_wt" "$branch"
if ! git -C "$land_wt" rebase master; then
  printf '\nConflicted files:\n' >&2
  git -C "$land_wt" diff --name-only --diff-filter=U >&2
  git -C "$land_wt" rebase --abort
  die "$branch does not rebase cleanly onto master; the agent rebases it"
fi
rebased=$(git -C "$land_wt" rev-parse HEAD)
git -C "$main" log --oneline "master..$rebased"

# The main checkout's .venv, pointed at the landing worktree's code.
cp -a "$main/.venv" "$land_wt/.venv"
sed -i "s|'$main/pettachainer'|'$land_wt/pettachainer'|" \
  "$land_wt"/.venv/lib/python3.*/site-packages/__editable___pettachainer_*_finder.py
for bin in "$land_wt"/.venv/bin/*; do
  [[ -f $bin && ! -L $bin ]] || continue
  first=
  IFS= read -r first <"$bin" || true
  if [[ $first == "#!$main/.venv/"* ]]; then
    sed -i "1s|^#!$main/.venv/|#!$land_wt/.venv/|" "$bin"
  fi
done
imported=$(cd / && "$land_wt/.venv/bin/python" -c 'import pettachainer; print(pettachainer.__file__)')
[[ $imported == "$land_wt/"* ]] || die "the landing venv imports $imported"

if [[ -n $cg_branch ]]; then
  step "Merge $cg_branch into supply-network ($(git -C "$cg_main" rev-parse --short supply-network))"
  git -C "$cg_main" worktree add --quiet --detach "$cg_land" supply-network
  if ! git -C "$cg_land" merge --no-edit "$cg_branch"; then
    printf '\nConflicted files:\n' >&2
    git -C "$cg_land" diff --name-only --diff-filter=U >&2
    git -C "$cg_land" merge --abort
    die "$cg_branch does not merge cleanly into supply-network"
  fi
  cg_merged=$(git -C "$cg_land" rev-parse HEAD)
fi

step "Gates: scripts/verify.sh (log $logs/verify.log)"
if ! ( cd "$land_wt" && unset DISPLAY && ulimit -v 16000000 &&
       "$capped" --slots 8 env PETTA_JOBS=8 scripts/verify.sh ) >"$logs/verify.log" 2>&1; then
  tail -n 20 "$logs/verify.log" >&2
  die "scripts/verify.sh failed"
fi
tail -n 9 "$logs/verify.log"

if [[ -n $cg_branch ]]; then
  step "ChainerGame tests (log $logs/chainergame.log)"
  if ! ( cd "$cg_land" && unset DISPLAY && ulimit -v 16000000 &&
         PYTHONPATH=src "$capped" "$cg_python" -m pytest -q tests ) >"$logs/chainergame.log" 2>&1; then
    tail -n 30 "$logs/chainergame.log" >&2
    die "ChainerGame tests failed"
  fi
  tail -n 3 "$logs/chainergame.log"

  step "Live SupplyNet tests on the rebased PeTTaChainer (log $logs/supplynet_live.log)"
  if ! ( cd "$cg_land" && unset DISPLAY && ulimit -v 16000000 &&
         PYTHONPATH=src SUPPLYNET_LIVE_PETTACHAINER=1 PETTACHAINER_PYTHONPATH="$land_wt" \
         "$capped" "$land_wt/.venv/bin/python" -m unittest tests.test_supplynet ) >"$logs/supplynet_live.log" 2>&1; then
    tail -n 30 "$logs/supplynet_live.log" >&2
    die "live SupplyNet tests failed"
  fi
  tail -n 3 "$logs/supplynet_live.log"
fi

step "Benchmarks: compare.sh master ${rebased:0:8} --full (log $logs/compare.log)"
"$compare" master "$rebased" --full >"$logs/compare.log" 2>&1 || {
  tail -n 20 "$logs/compare.log" >&2
  die "compare.sh failed"
}
report=$(sed -n 's/^report: \(.*\) ([0-9]* s wall)$/\1/p' "$logs/compare.log")
[[ -f $report ]] || die "compare.sh printed no report"
sed -n '/^Thresholds:/q;p' "$report"
verdict=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["verdict"])' "${report%/*}/compare.json")
[[ $verdict == PASS ]] || die "benchmark $verdict; see $report"

step "Land"
act git -C "$main" merge --ff-only "$rebased"
[[ -z $cg_branch ]] || act git -C "$cg_main" merge --ff-only "$cg_merged"
act git -C "$main" push origin master
[[ -z $cg_branch ]] || act git -C "$cg_main" push origin supply-network

# Removes a landed branch's worktree, points the branch at the commit that
# landed (a rebased branch's own commits are not in master) and deletes it,
# each step only when the previous one held.
retire() {
  local repo=$1 br=$2 tip=$3 target=$4 wt
  git -C "$repo" merge-base --is-ancestor "$tip" "$target" || die "$target does not contain $tip"
  wt=$(worktree_of "$repo" "$br")
  if [[ -n $wt ]] && ! git -C "$repo" worktree remove "$wt"; then
    printf 'kept %s (uncommitted or untracked files) and branch %s\n' "$wt" "$br"
    return
  fi
  git -C "$repo" branch -f "$br" "$tip"
  git -C "$repo" merge-base --is-ancestor "$br" "$target"
  git -C "$repo" branch -d "$br"
}

step "Retire landed worktrees and branches"
if (( push )); then
  retire "$main" "$branch" "$rebased" master
  [[ -z $cg_branch ]] || retire "$cg_main" "$cg_branch" "$cg_branch" supply-network
else
  printf 'dry run, would remove the worktree of %s and delete it once master contains it\n' "$branch"
  [[ -z $cg_branch ]] || printf 'dry run, would remove the worktree of %s and delete it once supply-network contains it\n' "$cg_branch"
fi

step "Done: every check passed$( (( push )) || printf ' (dry run, nothing changed)')"
