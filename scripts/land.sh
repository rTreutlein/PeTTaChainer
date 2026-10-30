#!/usr/bin/env bash
export BENCH_PRIORITY=landing # Landings jump the shared pool's queue.
# Land an agent branch on master: rebase it onto master in a worktree of its
# own, run every gate and the full benchmark comparison, and only then
# fast-forward master. With --chainergame, merge a ChainerGame branch into
# supply-network the same way (no rebase) and run its tests against the
# rebased PeTTaChainer. See docs/agent_workflow.md ("Landing a branch").
#
# Without --push this is a dry run: it runs every check and prints what it
# would change (except --clean can retire an already landed branch).
# With --push, and only when every check passed or flags were accepted, it
# fast-forwards master (and supply-network), pushes both, and removes the
# landed worktrees and branches.

set -euo pipefail

usage() {
  printf 'Usage: %s <branch> [--chainergame <branch>] [--push] [--accept-flags <file>] [--clean]\n' "${0##*/}" >&2
  exit 2
}

branch=
cg_branch=
push=0
clean=0
accept_flags=
while (( $# )); do
  case $1 in
    --chainergame) (( $# >= 2 )) || usage; cg_branch=$2; shift 2 ;;
    --push) push=1; shift ;;
    --clean) clean=1; shift ;;
    --accept-flags) (( $# >= 2 )) || usage; accept_flags=$2; shift 2 ;;
    -*) usage ;;
    *) [[ -z $branch ]] || usage; branch=$1; shift ;;
  esac
done
[[ -n $branch && $branch != master ]] || usage

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
main=$(dirname "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir)")
# The machine's ChainerGame checkout and bench tools; scripts/test_land.sh
# points them at stubs.
cg_main=${LAND_CG_MAIN:-/nexus/Dev/OpenCog/ChainerGame-supply}
cg_python=${LAND_CG_PYTHON:-/nexus/Dev/OpenCog/ChainerGame-problog/.venv-problog/bin/python}
capped=${LAND_CAPPED:-/nexus/Dev/OpenCog/bench/capped}
compare=${LAND_COMPARE:-/nexus/Dev/OpenCog/bench/compare.sh}

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

trap 'python3 "$script_dir/list_waiters.py" || true' EXIT

# Rebasing changes commit IDs. Check patch equivalence before deleting the
# original branch; git cherry alone ignores merge commits, so keep those
# unless the branch itself is already an ancestor.
retire() {
  local repo=$1 br=$2 target=$3 wt extra
  if ! git -C "$repo" merge-base --is-ancestor "$br" "$target"; then
    if [[ -n $(git -C "$repo" cherry "$target" "$br" | sed -n '/^+/p') ||
          -n $(git -C "$repo" rev-list --merges "$target..$br") ]]; then
      printf 'kept branch %s: not fully landed in %s (git cherry or unlanded merge)\n' "$br" "$target"
      return
    fi
  fi
  wt=$(worktree_of "$repo" "$br")
  if [[ -n $wt ]]; then
    extra=$(git -C "$wt" status --porcelain --ignored)
    if [[ -n $extra ]]; then
      if (( ! clean )) || ! python3 - "$wt" <<'PY_CHECK'
import subprocess
import sys

entries = subprocess.check_output([
    'git', '-C', sys.argv[1], 'status', '--porcelain', '-z',
    '--ignored', '--untracked-files=all',
]).split(b'\0')
for entry in filter(None, entries):
    status, path = entry[:2], entry[3:].decode('utf-8', 'surrogateescape')
    parts = path.rstrip('/').split('/')
    if status not in (b'??', b'!!') or not (
        parts[0] in ('.venv', 'scratch') or '__pycache__' in parts
    ):
        raise SystemExit(1)
PY_CHECK
      then
        printf 'kept %s and branch %s: the worktree holds files outside the cleanup allowance (or --clean was not given):\n%s\n' "$wt" "$br" "$extra"
        return
      fi
      printf 'cleaning %s: only .venv, __pycache__ or scratch extras:\n%s\n' "$wt" "$extra"
      git -C "$repo" worktree remove --force "$wt"
    else
      git -C "$repo" worktree remove "$wt"
    fi
  fi
  # Original rebased commits may not be ancestors; cherry checked their
  # patches above. No need to rewrite the branch just to delete it.
  git -C "$repo" branch -D "$br"
}

git -C "$main" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null || die "no branch $branch"
require_clean "$main" master
if [[ -n $cg_branch ]]; then
  git -C "$cg_main" rev-parse --verify --quiet "refs/heads/$cg_branch" >/dev/null || die "no ChainerGame branch $cg_branch"
  require_clean "$cg_main" supply-network
fi

if (( clean && ! push )) && [[ -z $accept_flags ]]; then
  if [[ -z $(git -C "$main" cherry master "$branch" | sed -n '/^+/p') ]]; then
    step "Clean previously landed worktrees and branches"
    retire "$main" "$branch" master
    [[ -z $cg_branch ]] || retire "$cg_main" "$cg_branch" supply-network
    exit 0
  fi
fi

name=${branch//\//-}
land_wt=$main/.claude/worktrees/land-$name
cg_land=
[[ -z $cg_branch ]] || cg_land=$(dirname "$cg_main")/ChainerGame-land-${cg_branch//\//-}
for dir in "$land_wt" $cg_land; do
  [[ ! -e $dir ]] || die "$dir exists from an earlier landing; remove it with git worktree remove"
done
mkdir -p "$main/.claude/land-logs"
logs=$(mktemp -d "$main/.claude/land-logs/$name-$(date +%Y%m%d-%H%M%S).XXXXXX")

# The landing worktrees are this script's own: each is marked once this run
# has created it, and git removes the marked ones on any exit. A worktree at
# the same path made by anyone else (a concurrent landing) is never touched.
land_made=
cg_made=
cleanup() {
  [[ -z $land_made ]] || git -C "$main" worktree remove --force "$land_wt"
  [[ -z $cg_made ]] || git -C "$cg_main" worktree remove --force "$cg_land"
  python3 "$script_dir/list_waiters.py" || true
}
trap cleanup EXIT

step "Rebase $branch onto master ($(git -C "$main" rev-parse --short master))"
git -C "$main" worktree add --quiet --detach "$land_wt" "$branch"
land_made=1
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
  cg_made=1
  if ! git -C "$cg_land" merge --no-edit "$cg_branch"; then
    printf '\nConflicted files:\n' >&2
    git -C "$cg_land" diff --name-only --diff-filter=U >&2
    git -C "$cg_land" merge --abort
    die "$cg_branch does not merge cleanly into supply-network"
  fi
  cg_merged=$(git -C "$cg_land" rev-parse HEAD)
fi

# What this landing reused from earlier runs of the same code and what it
# ran, for the summary at the end.
reused=()
ran=()

# A PASS of verify.sh on exactly this tree and environment (recorded by any
# run, an agent's in its worktree included) stands; see scripts/verify_cache.py.
if verified=$(python3 "$script_dir/verify_cache.py" lookup "$land_wt"); then
  step "Gates: scripts/verify.sh reused: $verified"
  reused+=("verify ($verified)")
else
  step "Gates: scripts/verify.sh (log $logs/verify.log)"
  if ! ( cd "$land_wt" && unset DISPLAY && ulimit -v 16000000 &&
         "$capped" --slots 8 env PETTA_JOBS=8 scripts/verify.sh ) >"$logs/verify.log" 2>&1; then
    tail -n 20 "$logs/verify.log" >&2
    die "scripts/verify.sh failed"
  fi
  tail -n 10 "$logs/verify.log"
  ran+=("verify (log $logs/verify.log)")
fi

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

# Runs compare.sh with the arguments after the log name, then accepts its
# compare.json only when every flag is approved. compare.json is the
# authoritative report. Match whole case+metric keys, never substrings or
# globs, and refuse failure/nondeterminism regardless of the approval file.
# Reasons go beside the other landing logs.
bench() {
  local name=$1 report
  shift
  step "Benchmarks: compare.sh $* (log $logs/$name.log)"
  "$compare" "$@" >"$logs/$name.log" 2>&1 || {
    tail -n 20 "$logs/$name.log" >&2
    die "compare.sh $* failed"
  }
  report=$(sed -n 's/^report: \(.*\) ([0-9]* s wall)$/\1/p' "$logs/$name.log")
  [[ -f $report ]] || die "compare.sh $* printed no report"
  # compare.sh reuses the verdict of an identical comparison that passed with
  # trusted timing (bench README "Verdicts"); it is checked below like any.
  verdict=$(sed -n 's/^reused: //p' "$logs/$name.log")
  if [[ -n $verdict ]]; then
    reused+=("$name ($verdict, report $report)")
  else
    ran+=("$name (report $report)")
  fi
  sed -n '/^Thresholds:/q;p' "$report"
  if ! python3 - "${report%/*}/compare.json" "$accept_flags" >>"$logs/accepted-flags.log" <<'PY_FLAGS'
import json
from pathlib import Path
import re
import sys

try:
    data = json.loads(Path(sys.argv[1]).read_text())
    approved = {}
    if sys.argv[2]:
        for number, line in enumerate(Path(sys.argv[2]).read_text().splitlines(), 1):
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) != 3 or any(not field.strip() for field in fields):
                raise ValueError(f'approval line {number}: expected case<TAB>metric<TAB>reason')
            case, metric, reason = (field.strip() for field in fields)
            key = (case, metric)
            if key in approved:
                raise ValueError(f'duplicate approval: {key}')
            approved[key] = reason
    verdict = data['verdict']
    flags = data['regressions']
    # A failure can exist in records even when compare labels it PASS (for
    # example when both sides failed). Approvals cannot waive failed runs.
    # Against the anchor, a case the anchor cannot run is not compared.
    for row in data['records']:
        for side in ('candidate', 'reference') if data.get('anchor') else ('base', 'candidate', 'reference'):
            if side in row and (row[side].get('exit') != 0 or 'unsupported' in row[side]):
                raise ValueError(f"failed/unsupported run: {row['suite']} {row['case']} {side}")
    if verdict == 'PASS':
        if flags:
            raise ValueError('PASS report contains regressions')
    elif verdict != f"REGRESSIONS ({len(flags)}): " + '; '.join(flags) or not flags:
        raise ValueError(f'unrecognized verdict: {verdict}')
    cases = {f"{row['suite']} {row['case']}" for row in data['records']}
    accepted = []
    for flag in flags:
        # Ordinary accuracy, per-kind error, and confirmed timing flags all
        # end in numeric before/after values. Failure flags do not.
        match = re.fullmatch(r'(.+) [-+0-9.eE]+ -> [-+0-9.eE]+(?: \(rerun [-+0-9.eE]+ -> [-+0-9.eE]+\))?', flag)
        keys = [(case, match[1][len(case) + 1:]) for case in cases
                if match and match[1].startswith(case + ' ')]
        if len(keys) != 1 or keys[0] not in approved:
            raise ValueError(f'unapproved, ambiguous or non-waivable flag: {flag}')
        accepted.append(f'{flag}\n  Reason: {approved[keys[0]]}')
    # Anchor flags master shares do not block; they and the progress stay visible.
    for title, field in (('Behind the anchor, on master too (not blocking)', 'behind_anchor'),
                         ('Progress toward the anchor', 'progress')):
        if data.get(field):
            print(f'{title} ({sys.argv[1]}):')
            print('\n'.join(f'  {line}' for line in data[field]))
    if accepted:
        print(f'Report: {sys.argv[1]}')
        print('Accepted flags (explicit coordinator approvals):')
        print('\n'.join(accepted))
except (OSError, ValueError, KeyError, TypeError) as error:
    print(f'land: STOP: {error}', file=sys.stderr)
    raise SystemExit(1)
PY_FLAGS
  then
    die "benchmark report not accepted; see $report"
  fi
}

# The canary against the anchor build (bench/anchor.txt) first: a few
# minutes, and it holds the presentation workloads and the slowdown
# accumulated since the anchor, which a comparison with master cannot see.
# An anchor flag blocks only where the candidate is also worse than master.
master_sha=$(git -C "$main" rev-parse master)
bench anchor-canary anchor "$rebased" --canary --master "$master_sha"
# Every case, past the first regression: a landing's report lists all its
# flags, and its approvals must name every one.
bench compare master "$rebased" --full --no-fail-fast
# Against the anchor and master the runs above are reused.
bench anchor-full anchor "$rebased" --full --master "$master_sha"
cat "$logs/accepted-flags.log"

step "Reused and ran"
printf -v line '%s; ' "${reused[@]:-nothing}"
printf 'reused: %s\n' "${line%; }"
printf -v line '%s; ' "${ran[@]:-nothing}"
printf 'ran: %s\n' "${line%; }"

step "Land"
act git -C "$main" merge --ff-only "$rebased"
[[ -z $cg_branch ]] || act git -C "$cg_main" merge --ff-only "$cg_merged"
act git -C "$main" push origin master
[[ -z $cg_branch ]] || act git -C "$cg_main" push origin supply-network

if (( push )); then
  python3 "$script_dir/round_metrics.py" "$main" "$branch" "$master_sha" "$rebased" ||
    printf 'round metrics: warning: logger failed\n' >&2
fi

step "Retire landed worktrees and branches"
if (( push )); then
  retire "$main" "$branch" master
  [[ -z $cg_branch ]] || retire "$cg_main" "$cg_branch" supply-network
else
  printf 'dry run, would remove the worktree of %s and delete it once master contains it\n' "$branch"
  [[ -z $cg_branch ]] || printf 'dry run, would remove the worktree of %s and delete it once supply-network contains it\n' "$cg_branch"
fi

step "Done: every check passed$( (( push )) || printf ' (dry run, nothing changed)')"
