#!/usr/bin/env bash
# Tests scripts/land.sh in throwaway repositories under /tmp, with stubs for
# verify.sh, capped, compare.sh, the project .venv and the ChainerGame Python.
# Worktree preservation, explicit cleanup, report approvals and waiter
# diagnostics are exercised without running a real benchmark or landing.

set -euo pipefail

land=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/land.sh
tmp=$(mktemp -d /tmp/land-test.XXXXXX)
trap 'python3 - "$tmp" <<"PY_CLEANUP"
import shutil
import sys
shutil.rmtree(sys.argv[1])
PY_CLEANUP
' EXIT
export GIT_AUTHOR_NAME=land-test GIT_AUTHOR_EMAIL=land-test@example.invalid
export GIT_COMMITTER_NAME=land-test GIT_COMMITTER_EMAIL=land-test@example.invalid

mkdir "$tmp/stubs"
cat >"$tmp/stubs/capped" <<'EOF'
#!/usr/bin/env bash
[[ $1 != --slots ]] || shift 2
exec "$@"
EOF
cat >"$tmp/stubs/compare" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$1" "$3" >>"$LAND_TEST_DIR/compare-calls"
dir=$(mktemp -d "$LAND_TEST_DIR/report.XXXXXX")
printf 'summary for %s\nThresholds:\n' "$2" >"$dir/report.md"
if [[ $1 == anchor && -n ${LAND_TEST_ANCHOR_REPORT:-} ]]; then
  cp "$LAND_TEST_ANCHOR_REPORT" "$dir/compare.json"
elif [[ -n ${LAND_TEST_REPORT:-} ]]; then
  cp "$LAND_TEST_REPORT" "$dir/compare.json"
else
  printf '{"verdict": "%s", "regressions": [], "records": []}\n' "${LAND_TEST_VERDICT:-PASS}" >"$dir/compare.json"
fi
printf 'report: %s (1 s wall)\n' "$dir/report.md"
EOF
printf '#!/bin/sh\nexit 0\n' >"$tmp/stubs/cg-python"
chmod +x "$tmp/stubs"/*
export LAND_TEST_DIR=$tmp LAND_CAPPED=$tmp/stubs/capped LAND_COMPARE=$tmp/stubs/compare
export LAND_CG_PYTHON=$tmp/stubs/cg-python

failures=0
fail() { printf 'FAIL %s: %s\n' "$name" "$*"; failures=$((failures + 1)); }

# A main checkout at $pc on master with a pushed origin, a stub .venv whose
# python reports the pettachainer of the checkout it was copied into, and a
# branch feat with one commit, checked out at $wt. With cg=1 also a
# ChainerGame checkout at $cg on supply-network with a branch cgfeat at $cgwt.
fixture() {
  name=$1
  root=$tmp/$name
  pc=$root/PeTTaChainer
  wt=$pc/.claude/worktrees/feat
  cg=$root/ChainerGame-supply
  cgwt=$root/cg-feat
  git init -q --bare -b master "$root/origin.git"
  git clone -q "$root/origin.git" "$pc" 2>/dev/null
  mkdir -p "$pc/scripts"
  cp "$land" "$pc/scripts/land.sh"
  cp "${land%/*}/list_waiters.py" "$pc/scripts/list_waiters.py"
  printf '#!/usr/bin/env bash\nexit "${LAND_TEST_VERIFY_STATUS:-0}"\n' >"$pc/scripts/verify.sh"
  chmod +x "$pc/scripts/verify.sh"
  printf '.venv\nscratch/\n__pycache__/\n' >"$pc/.gitignore"
  echo base >"$pc/x"
  git -C "$pc" add -A
  git -C "$pc" commit -qm base
  git -C "$pc" push -q origin master
  mkdir -p "$pc/.venv/bin" "$pc/.venv/lib/python3.10/site-packages"
  printf "MAPPING = {'pettachainer': '%s/pettachainer'}\n" "$pc" \
    >"$pc/.venv/lib/python3.10/site-packages/__editable___pettachainer_0_1_0_finder.py"
  ln -s /bin/sh "$pc/.venv/bin/sh"
  printf '#!%s/.venv/bin/sh\n[ "$1" != -c ] || echo "$(cd "$(dirname "$0")/../.." && pwd)/pettachainer/__init__.py"\n' \
    "$pc" >"$pc/.venv/bin/python"
  chmod +x "$pc/.venv/bin/python"
  git -C "$pc" worktree add -q "$wt" -b feat
  echo feat >"$wt/y"
  git -C "$wt" add y
  git -C "$wt" commit -qm feat
  export LAND_CG_MAIN=$cg
  if (( ${2:-0} )); then
    git init -q --bare -b supply-network "$root/cg-origin.git"
    git clone -q "$root/cg-origin.git" "$cg" 2>/dev/null
    printf 'scratch/\n' >"$cg/.gitignore"
    git -C "$cg" add -A
    git -C "$cg" commit -qm base
    git -C "$cg" push -q origin supply-network
    git -C "$cg" worktree add -q "$cgwt" -b cgfeat
    echo cg >"$cgwt/z"
    git -C "$cgwt" add z
    git -C "$cgwt" commit -qm cgfeat
  fi
}

# Every path under a directory with its size, mode and content hash.
snapshot() {
  (cd "$1" && find . -printf '%p %s %m\n' | sort && find . -type f -print0 | sort -z | xargs -0 sha1sum)
}

run_land() {
  set +e
  out=$("$pc/scripts/land.sh" "$@" 2>&1)
  status=$?
  set -e
}

expect_status() {
  if [[ $1 == 0 ]]; then
    (( status == 0 )) || fail "land.sh exited $status: $out"
  else
    (( status != 0 )) || fail "land.sh succeeded: $out"
  fi
}

expect_untouched() {
  [[ $(snapshot "$1") == "$2" ]] || fail "$1 changed"
  git -C "$3" rev-parse --verify --quiet "refs/heads/$4" >/dev/null || fail "branch $4 was deleted"
}

expect_retired() {
  [[ ! -e $1 ]] || fail "$1 was not removed"
  ! git -C "$2" rev-parse --verify --quiet "refs/heads/$3" >/dev/null || fail "branch $3 was not deleted"
}

expect_master() {
  [[ $(git -C "$pc" rev-parse master) == "$1" ]] || fail "master is $(git -C "$pc" rev-parse --short master)"
  [[ $(git -C "$pc" rev-parse origin/master) == "$1" ]] || fail "origin/master differs from master"
}

expect_landing_gone() {
  [[ ! -e $pc/.claude/worktrees/land-feat ]] || fail "the landing worktree was left"
  [[ ! -e $root/ChainerGame-land-cgfeat ]] || fail "the ChainerGame landing worktree was left"
  [[ $(git -C "$pc" worktree list --porcelain | grep -c '^worktree ') == "$1" ]] || fail "worktree list: $(git -C "$pc" worktree list)"
}

# A landed branch's worktree with something besides its checkout stays whole
# and keeps its branch, while master lands.
for kind in ignored untracked modified; do
  fixture "keep-$kind"
  case $kind in
    ignored) mkdir -p "$wt/scratch/runs"; echo '{"score": 1}' >"$wt/scratch/runs/result.json"; echo log >"$wt/scratch/run.log" ;;
    untracked) echo note >"$wt/notes.txt" ;;
    modified) echo edited >>"$wt/y" ;;
  esac
  before=$(snapshot "$wt")
  run_land feat --push
  expect_status 0
  expect_untouched "$wt" "$before" "$pc" feat
  [[ $out == *"kept $wt and branch feat"* ]] || fail "no reason printed: $out"
  expect_master "$(git -C "$pc" rev-parse feat)"
  expect_landing_gone 2
done

fixture retire-clean
run_land feat --push
expect_status 0
expect_retired "$wt" "$pc" feat
expect_landing_gone 1
[[ $(git -C "$pc" show master:y) == feat ]] || fail "master does not hold the branch"

# A clean PeTTaChainer worktree goes; a ChainerGame worktree with an ignored
# scratch file stays.
fixture chainergame 1
mkdir "$cgwt/scratch"
echo log >"$cgwt/scratch/run.log"
cg_before=$(snapshot "$cgwt")
run_land feat --chainergame cgfeat --push
expect_status 0
expect_retired "$wt" "$pc" feat
expect_untouched "$cgwt" "$cg_before" "$cg" cgfeat
[[ $(git -C "$cg" rev-parse supply-network) == $(git -C "$cg" rev-parse cgfeat) ]] || fail "supply-network did not land"
[[ $(git -C "$cg" worktree list --porcelain | grep -c '^worktree ') == 2 ]] || fail "ChainerGame worktrees: $(git -C "$cg" worktree list)"
expect_landing_gone 1

# A failed check changes nothing but the script's own landing worktree.
for failure in verify benchmark conflict dry-run; do
  fixture "stop-$failure"
  mkdir "$wt/scratch"
  echo log >"$wt/scratch/run.log"
  master=$(git -C "$pc" rev-parse master)
  case $failure in
    conflict)
      echo master >"$pc/y"
      git -C "$pc" add y
      git -C "$pc" commit -qm master
      git -C "$pc" push -q origin master
      master=$(git -C "$pc" rev-parse master)
      ;;
  esac
  before=$(snapshot "$wt")
  case $failure in
    verify) LAND_TEST_VERIFY_STATUS=1 run_land feat --push; expect_status 1 ;;
    benchmark) LAND_TEST_VERDICT=FAIL run_land feat --push; expect_status 1 ;;
    conflict) run_land feat --push; expect_status 1 ;;
    dry-run) run_land feat; expect_status 0 ;;
  esac
  expect_untouched "$wt" "$before" "$pc" feat
  expect_master "$master"
  expect_landing_gone 2
done

# A directory at the landing worktree's path is not the script's own.
fixture stale-landing
mkdir -p "$pc/.claude/worktrees/land-feat"
echo keep >"$pc/.claude/worktrees/land-feat/file"
run_land feat --push
expect_status 1
[[ $(cat "$pc/.claude/worktrees/land-feat/file" 2>/dev/null) == keep ]] || fail "the existing directory was touched"

# --clean removes only named disposable extras, and requires patch equivalence.
fixture clean-extras
mkdir -p "$wt/.venv/bin" "$wt/pkg/__pycache__" "$wt/scratch/runs"
echo interpreter >"$wt/.venv/bin/python"
echo bytecode >"$wt/pkg/__pycache__/cache.pyc"
echo result >"$wt/scratch/runs/result.json"
run_land feat --push --clean
expect_status 0
expect_retired "$wt" "$pc" feat
expect_landing_gone 1

for kind in untracked modified ignored; do
  fixture "clean-keep-$kind"
  mkdir "$wt/scratch"
  echo log >"$wt/scratch/run.log"
  case $kind in
    untracked) echo note >"$wt/notes.txt" ;;
    modified) echo edited >>"$wt/y" ;;
    ignored) echo notes.txt >>"$pc/.git/info/exclude"
             echo note >"$wt/notes.txt" ;;
  esac
  before=$(snapshot "$wt")
  run_land feat --push --clean
  expect_status 0
  expect_untouched "$wt" "$before" "$pc" feat
  [[ $out == *notes.txt* || $out == *' M y'* ]] || fail "kept files not listed: $out"
done

# An earlier landing may have rebased the commit; git cherry proves the
# original patch is landed even though merge-base cannot prove ancestry.
fixture clean-old-rebased
mkdir "$wt/scratch"
echo log >"$wt/scratch/run.log"
echo master >"$pc/z"
git -C "$pc" add z
git -C "$pc" commit -qm advance
LAND_TEST_VERDICT=PASS run_land feat --push
expect_status 0
! git -C "$pc" merge-base --is-ancestor feat master || fail "fixture was not rebased"
LAND_TEST_VERIFY_STATUS=1 LAND_TEST_VERDICT=FAIL run_land feat --clean
expect_status 0
expect_retired "$wt" "$pc" feat
[[ $out != *'Gates:'* ]] || fail "cleanup reran gates"
expect_landing_gone 1

fixture clean-unlanded
mkdir "$wt/scratch"
echo log >"$wt/scratch/run.log"
before=$(snapshot "$wt")
master=$(git -C "$pc" rev-parse master)
run_land feat --clean
expect_status 0
expect_untouched "$wt" "$before" "$pc" feat
expect_master "$master"

fixture clean-unlanded-merge
mkdir "$wt/scratch"
echo log >"$wt/scratch/run.log"
git -C "$pc" cherry-pick feat >/dev/null
git -C "$pc" switch -q -c side master
echo side >"$pc/side"
git -C "$pc" add side
git -C "$pc" commit -qm side
git -C "$pc" switch -q master
git -C "$pc" cherry-pick side >/dev/null
git -C "$wt" merge -q --no-ff side -m merge
before=$(snapshot "$wt")
run_land feat --clean
expect_status 0
expect_untouched "$wt" "$before" "$pc" feat
[[ $out == *'unlanded merge'* ]] || fail "merge not protected: $out"

# Failure/nondeterminism cannot be approved. Exact case+metric matching
# includes accuracy and per-kind error flags, and excludes false timing flags.
report_json=$tmp/flags.json
approval=$tmp/approved.tsv
printf 'suite case\tseconds\tUser accepted repeatable timing cost\nsuite case\terror\tUser accepted known accuracy tradeoff\nsuite case\tInheritance error\tUser accepted this kind error\n' >"$approval"
for scenario in approved strict extra wrong-case wrong-metric no-reason duplicate missing-file ambiguous overlapping-cases unsupported failed nondeterministic malformed pass-failure kind-error; do
  fixture "flags-$scenario"
  python3 - "$report_json" "$scenario" <<'PY_REPORT'
import json
import sys

scenario = sys.argv[2]
flags = ['suite case seconds 1 -> 2 (rerun 1 -> 2)', 'suite case error 0 -> 0.1']
records = [{'suite': 'suite', 'case': 'case', 'base': {'exit': 0}, 'candidate': {'exit': 0}}]
if scenario == 'extra':
    flags.append('suite case peak_mb 100 -> 200')
elif scenario == 'wrong-case':
    flags[0] = 'suite case-other seconds 1 -> 2'
elif scenario == 'wrong-metric':
    flags[0] = 'suite case error-extra 0 -> 0.1'
elif scenario == 'unsupported':
    records[0]['candidate'] = {'unsupported': 'feature'}
elif scenario == 'failed':
    records[0]['candidate']['exit'] = 1
elif scenario == 'nondeterministic':
    flags = ['suite case: NONDETERMINISTIC (accuracy differs from an earlier run of the same code)']
elif scenario == 'pass-failure':
    records[0]['base']['exit'] = 1
    flags = []
elif scenario == 'overlapping-cases':
    flags = ['suite case Inheritance error 0 -> 0.1']
    records.append({'suite': 'suite', 'case': 'case Inheritance', 'base': {'exit': 0}, 'candidate': {'exit': 0}})
elif scenario == 'kind-error':
    flags = ['suite case Inheritance error 0 -> 0.1']
verdict = f"REGRESSIONS ({len(flags)}): " + '; '.join(flags) if flags else 'PASS'
if scenario == 'malformed':
    verdict = 'REGRESSIONS (99): missing flags'
with open(sys.argv[1], 'w') as stream:
    json.dump({'verdict': verdict, 'regressions': flags, 'records': records,
               'false_flags': ['suite other seconds 1 -> 3']}, stream)
PY_REPORT
  master=$(git -C "$pc" rev-parse master)
  before=$(snapshot "$wt")
  args=(feat --push --accept-flags "$approval")
  if [[ $scenario == strict ]]; then args=(feat --push); fi
  case $scenario in
    no-reason) printf 'suite case\tseconds\n' >"$tmp/no-reason.tsv"
               args=(feat --push --accept-flags "$tmp/no-reason.tsv") ;;
    duplicate) cat "$approval" "$approval" >"$tmp/duplicate.tsv"
               args=(feat --push --accept-flags "$tmp/duplicate.tsv") ;;
    missing-file) args=(feat --push --accept-flags "$tmp/absent.tsv") ;;
    ambiguous) printf 'suite\tcase seconds\tNot the case/metric approved\n' >"$tmp/ambiguous.tsv"
               args=(feat --push --accept-flags "$tmp/ambiguous.tsv") ;;
    failed|unsupported|nondeterministic)
      cp "$approval" "$tmp/non-waivable.tsv"
      printf 'suite case\texit\tUser attempted to approve failure\nsuite case\tNONDETERMINISTIC\tUser attempted to approve nondeterminism\nsuite case\tunsupported\tUser attempted to approve missing feature\n' >>"$tmp/non-waivable.tsv"
      args=(feat --push --accept-flags "$tmp/non-waivable.tsv") ;;
  esac
  LAND_TEST_REPORT=$report_json run_land "${args[@]}"
  case $scenario in
    approved|kind-error)
      expect_status 0
      expect_retired "$wt" "$pc" feat
      [[ $out == *'Accepted flags'* && $out == *'Reason: User accepted'* ]] || fail "accepted flags/reasons missing: $out"
      grep -q 'Reason: User accepted' "$pc"/.claude/land-logs/*/accepted-flags.log || fail "approval audit missing"
      ;;
    *) expect_status 1
       expect_untouched "$wt" "$before" "$pc" feat
       expect_master "$master" ;;
  esac
done

# Against the anchor (compare.json "anchor": true) a case the anchor cannot
# run is no failure and its flags are approved as "<metric> vs anchor"; a
# candidate failure still stops the landing. The canary against the anchor
# runs first, the full profile against master and the anchor after it.
anchor_json=$tmp/anchor.json
for scenario in cannot-run approved master-approval candidate-failed; do
  fixture "anchor-$scenario"
  python3 - "$anchor_json" "$scenario" <<'PY_REPORT'
import json
import sys

scenario = sys.argv[2]
records = [{'suite': 'suite', 'case': 'case', 'base': {'exit': 0}, 'candidate': {'exit': 0}}]
flags = []
if scenario in ('cannot-run', 'candidate-failed'):
    records[0]['base']['exit'] = 1
    records[0]['candidate']['exit'] = 1 if scenario == 'candidate-failed' else 0
else:
    flags = ['suite case seconds vs anchor 1 -> 2']
verdict = f"REGRESSIONS ({len(flags)}): " + '; '.join(flags) if flags else 'PASS'
with open(sys.argv[1], 'w') as stream:
    json.dump({'verdict': verdict, 'regressions': flags, 'records': records, 'anchor': True}, stream)
PY_REPORT
  metric='seconds vs anchor'
  [[ $scenario != master-approval ]] || metric=seconds
  printf 'suite case\t%s\tUser accepted the slowdown since the anchor\n' "$metric" >"$tmp/anchor-approval.tsv"
  master=$(git -C "$pc" rev-parse master)
  : >"$tmp/compare-calls"
  LAND_TEST_ANCHOR_REPORT=$anchor_json run_land feat --push --accept-flags "$tmp/anchor-approval.tsv"
  case $scenario in
    cannot-run|approved)
      expect_status 0
      expect_retired "$wt" "$pc" feat
      [[ $(cat "$tmp/compare-calls") == $'anchor --canary\nmaster --full\nanchor --full' ]] || fail "comparisons: $(cat "$tmp/compare-calls")" ;;
    *) expect_status 1
       expect_master "$master" ;;
  esac
done

fixture flags-dry-run
master=$(git -C "$pc" rev-parse master)
python3 - "$report_json" <<'PY_REPORT'
import json, sys
json.dump({'verdict': 'REGRESSIONS (1): suite case seconds 1 -> 2',
           'regressions': ['suite case seconds 1 -> 2'],
           'records': [{'suite': 'suite', 'case': 'case', 'base': {'exit': 0}, 'candidate': {'exit': 0}}]}, open(sys.argv[1], 'w'))
PY_REPORT
before=$(snapshot "$wt")
LAND_TEST_REPORT=$report_json run_land feat --accept-flags "$approval" --clean
expect_status 0
expect_untouched "$wt" "$before" "$pc" feat
expect_master "$master"

# Deterministic ps snapshot: stale shells match themselves, live targets and
# live guarded log waiters stay out. Listing must not invoke kill.
cat >"$tmp/stubs/ps" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${LAND_TEST_PS:-} ]]; then cat "$LAND_TEST_PS"; else exec /bin/ps "$@"; fi
EOF
chmod +x "$tmp/stubs/ps"
cat >"$tmp/processes" <<'EOF'
101 1 bash -c until ! pgrep -f "gone-job"; do sleep 30; done
102 101 sleep 30
103 1 bash -c while pgrep -f "live-job"; do sleep 30; done
104 1 live-job --run
105 1 bash -c until grep -q DONE run.log; do sleep 30; done
106 105 sleep 30
107 1 bash -c until grep -q DONE active.log || ! kill -0 104; do sleep 30; done
108 1 bash -c until grep -q DONE dead.log || ! kill -0 999999; do sleep 30; done
EOF
fixture waiters
LAND_TEST_PS=$tmp/processes PATH="$tmp/stubs:$PATH" run_land feat
expect_status 0
for pid in 101 105 108; do
  [[ $out == *"PID $pid ("* ]] || fail "stale waiter $pid not listed: $out"
done
for pid in 103 107; do
  [[ $out != *"PID $pid ("* ]] || fail "live waiter $pid listed: $out"
done
[[ $out == *'no processes killed'* ]] || fail "diagnostic-only notice absent"

if (( failures )); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'land.sh: all cases passed\n'
