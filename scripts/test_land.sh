#!/usr/bin/env bash
# Tests scripts/land.sh in throwaway repositories under /tmp, with stubs for
# verify.sh, capped, compare.sh, the project .venv and the ChainerGame Python.
# Every case checks that an agent's worktree holding anything besides its
# clean checkout survives byte for byte, and that only the script's own
# landing worktrees go.

set -euo pipefail

land=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/land.sh
tmp=$(mktemp -d /tmp/land-test.XXXXXX)
trap 'case $tmp in /tmp/land-test.??????) rm -rf -- "$tmp" ;; esac' EXIT
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
dir=$(mktemp -d "$LAND_TEST_DIR/report.XXXXXX")
printf 'summary for %s\nThresholds:\n' "$2" >"$dir/report.md"
printf '{"verdict": "%s"}\n' "${LAND_TEST_VERDICT:-PASS}" >"$dir/compare.json"
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
  printf '#!/usr/bin/env bash\nexit "${LAND_TEST_VERIFY_STATUS:-0}"\n' >"$pc/scripts/verify.sh"
  chmod +x "$pc/scripts/verify.sh"
  printf '.venv\nscratch/\n' >"$pc/.gitignore"
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

if (( failures )); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'land.sh: all cases passed\n'
