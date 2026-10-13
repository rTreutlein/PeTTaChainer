# Working as a delegated agent

A coordinator hands work to agents that each run in their own worktree, while
other agents run on the same machine at the same time. This page holds the
rules and commands that every brief would otherwise repeat. The short form is
in `AGENTS.md`.

## Worktree and environment

Branch from current `master`. The coordinator keeps `origin/master` equal to
it, so an isolation worktree made from `origin/master` is current too; check
with `git log -1 --oneline master origin/master`.

```bash
git worktree add .claude/worktrees/<name> -b <name> master
```

A fresh worktree has no `.venv`. Copy the main checkout's and point it at the
worktree; a plain copy still imports `pettachainer` from the main checkout,
which silently tests the wrong code:

```bash
M=/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer
W=$M/.claude/worktrees/<name>
cp -a $M/.venv $W/.venv
sed -i "s|'$M/pettachainer'|'$W/pettachainer'|" $W/.venv/lib/python3.10/site-packages/__editable___pettachainer_0_1_0_finder.py
grep -l "^#!$M/.venv/bin/python" $W/.venv/bin/* | xargs sed -i "1s|^#!$M/.venv/|#!$W/.venv/|"
cd /tmp && $W/.venv/bin/python -c 'import pettachainer; print(pettachainer.__file__)'   # must print $W/...
```

Do not run `uv sync` in a worktree: `pyproject.toml` finds PeTTa at
`../../PeTTa`, which from `.claude/worktrees/<name>` is the wrong directory.
PeTTa changes go to a branch in `/nexus/Dev/OpenCog/PeTTa`, never into
`.venv`.

The shared `.venv` runs PeTTa fork branch `pettachainer-runtime-main-4`
(worktree `/nexus/Dev/OpenCog/PeTTa-runtime-main-4`): upstream main plus the
specialized-call-exceptions change (#237 proposal), `nb_current` global
reads (#248) and chunked load-cache replay (#249). To test a PeTTa change, install its tree into your worktree's
copied `.venv`, never into the shared one:

```bash
uv pip install --python $W/.venv/bin/python --reinstall --no-deps <PeTTa tree>
```

`compare.sh` reads the runtime from `$PETTACHAINER_REPO/.venv`, so run it with
`PETTACHAINER_REPO=$W` to benchmark that runtime.

Keep scratch files in your worktree (or a scratchpad subdirectory named after
your branch), not in `/tmp`: `/tmp` is
wiped on reboot.

## Commands

Run from the worktree root.

| Step | Command |
|---|---|
| One MeTTa file | `(ulimit -v 16000000; .venv/bin/petta file.metta)` |
| MeTTa suite (strict det) | `scripts/test_metta.sh` |
| Python tests | `.venv/bin/python -m unittest discover -s tests` |
| All gates | `scripts/verify.sh` (MeTTa lint, MeTTa, Python, import scaling, ConceptNet) |
| Benchmarks | `/nexus/Dev/OpenCog/bench/compare.sh master <worktree> --quick` |

`scripts/test_metta.sh` runs `PETTA_JOBS=$(nproc)` (32) files at once.
Run it, and `scripts/verify.sh`, through the admission pool with a matching
slot count, so it shares the machine with other agents' jobs:
`/nexus/Dev/OpenCog/bench/capped --slots 8 env PETTA_JOBS=8 scripts/test_metta.sh`.

### Benchmarks: `bench/compare.sh`

`compare.sh` is the benchmark step. Do not freeze builds by hand, pick your
own seeds or write runner scripts.

```bash
/nexus/Dev/OpenCog/bench/compare.sh <base> <candidate> [--quick|--full] [--timing|--no-timing]
/nexus/Dev/OpenCog/bench/compare.sh <base> <candidate> --curves [--only <case>]
```

- `<base>`, `<candidate>`: a PeTTaChainer ref or commit (`master`, `a1980394`),
  a frozen build name under `bench/chainers/`, or a worktree path. A worktree
  counts as its HEAD plus its uncommitted diff and its untracked files under
  `pettachainer/`.
- `--quick` (default, about 75 s: one point per behaviour) while iterating. Run `--full` (about 3 min: each behaviour as a budget curve, plus the ProbLog fuzzer gate) before hand-back.
  `bench/README.md` lists what each profile runs and how long it takes.
- **Results are stored by the code that ran.** The store key is the
  `pettachainer/` tree (uncommitted changes included), the PeTTa runtime, the
  ChainerGame source and the case. A run whose key is stored is never
  repeated: a rebase, an amend, a docs-only commit or a rerun reuses every
  result, and `master`'s results are shared by all agents. A
  comparison that needs a result another agent is running waits for it.
  Accuracy always comes from the store. In `--full` (`--timing`), a case
  that runs for one build also runs for the other next to it, so the two
  timings share a load. `--quick` (`--no-timing`) reuses stored results of
  either build.
- `--curves` sweeps each curve case up its budget ladder for both builds,
  stops once the error flattens, and reports the best error each build
  reaches within t seconds.
- The report goes to
  `bench/results/compare/<base>_vs_<candidate>_<profile>/report.md`. Below
  its title, the verdict is `**PASS**` or `**REGRESSIONS (n): ...**`, and
  the next line says whether any accuracy number changed at all
  (`compare.json` beside it has the verdict as data). The header says how many
  runs executed and how many results were reused.
- Accuracy numbers are deterministic, so any change in them is real, and a
  result that differs from an earlier run of the same code is reported as
  `NONDETERMINISTIC`. Time is not deterministic. A timing flag counts only
  if a paired rerun of both builds repeats it. Timing not taken side by side
  at comparable load is marked `load differs` and not flagged.
- Every comparison appends its cost and catches to
  `bench/results/suite_metrics.jsonl`. `python3 bench/suite_report.py` shows
  the trends.

See `bench/README.md` for the suites, thresholds and the admission pool.

## Spending time well

Agents have spent about half their wall time waiting on jobs and a sixth on
benchmark and probe runs. Most of both is avoidable:

- Iterate on the smallest check that shows the effect: a minimal repro file,
  the unit tests of the code you change, or one fuzzer seed. Each takes
  seconds.
- Run `compare.sh --quick` only at checkpoints, when a change works, and
  `--full` once before hand-back.
- While a long job runs (the suite, `verify.sh`, `compare.sh`), do other
  work: the unit tests, the docs, the next change. Start the job in the
  background, tied to its PID (see "Waiting for your own jobs"), and read
  its result when you need it instead of blocking on it.

## Memory and CPU

WSL has 48 GB and 32 hardware threads (16 cores). A runaway run has frozen
the whole machine before, and other agents share it. Worse, the tmux pane
Claude runs in has `OOMPolicy=stop`: one OOM kill of any process started
from it stops the whole pane, the coordinator and every agent included.

- Run every PeTTa, test or benchmark process through
  `/nexus/Dev/OpenCog/bench/capped [--slots N] [--peak-mb M] <command>`.
  It waits for a slot in the machine-wide admission pool, then runs the
  command inside `bench.slice`, whose memory cap (75% of RAM) is shared by
  all jobs, so an OOM kills only the job. The pool starts a job only when:
  - the slots in use plus the job's own stay within the CPU target (24, set
    from a concurrency calibration);
  - available memory, less what the running jobs may still grow and less an
    8 GB reserve, covers the job's expected peak.

  Agents share the pool evenly, so nobody needs to throttle by hand. Pass
  `--slots N` for a job that runs N workers, and `--peak-mb M` for one
  expected to use much more than 1.5 GB. `python3
  /nexus/Dev/OpenCog/bench/admission.py status` shows who holds what.
- `compare.sh` takes one slot per run itself. `scripts/test_metta.sh` and
  `scripts/verify.sh` put themselves in the slice but not in the pool: run
  them through `capped --slots N` with `PETTA_JOBS=N`. Run anything else (a
  `supplynet` sweep, a single `petta` file, a probe, the fuzzer with
  `--jobs N`) through `capped` too.
- Run every PeTTa or benchmark process under `ulimit -v 16000000`, with
  `DISPLAY` unset so no profiler GUI opens.
- Give SupplyNet scale size `xl` at 16 steps per query (about 14 GB)
  `--peak-mb 15000`, so the pool keeps room for it.

`compare.sh` follows these rules itself.

## Waiting for your own jobs

Every wait loop must run under `timeout N` and use `while kill -0 <PID>`,
with the job PID captured from `$!`. Use `wait "$pid"` afterward to collect
its exit status. A timeout ends the waiter, not the job: if it expires,
stop the job and reap it before hand-back. Keep one waiter per job and stop
every process you started before handing back.

Never use `pgrep -f` in a wait loop: it matches the waiting shell's own
command line and can match another agent's job. Never wait for a log
marker: a job that dies before writing it leaves the waiter running forever.
Read logs after the PID wait completes.

Copy-pasteable example, run from your worktree root (600 seconds is the
wait limit; adjust it for the job):

```bash
mkdir -p scratch
set +m  # Disable shell job control so setsid keeps the PID captured below.
# A separate process group makes timeout cleanup include the workers.
setsid bash -c '
  unset DISPLAY
  ulimit -v 16000000
  exec /nexus/Dev/OpenCog/bench/capped --slots 8 env PETTA_JOBS=8 scripts/verify.sh
' >scratch/verify.log 2>&1 &
pid=$!
if timeout 600 bash -c 'while kill -0 "$1" 2>/dev/null; do sleep 1; done' _ "$pid"; then
  if wait "$pid"; then status=0; else status=$?; fi
else
  kill -TERM -- "-$pid" 2>/dev/null || true
  sleep 2
  kill -KILL -- "-$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  status=124
fi
cat scratch/verify.log
printf 'verify exit status: %s\n' "$status"
```

When you kill or replace a job, stop its waiter in the same command.

All agents of a session share one scratchpad directory, so a generic name
such as `grid.log` in it can be another agent's file. Put scripts and logs
under your worktree, or in a scratchpad subdirectory named after your
branch.

## Git

- Never run a bare `git stash`. Other work in the checkout ends up in it.
  Commit to your branch instead, or `git stash push -- <paths>` for your own
  files only.
- Never `rm -rf` a variable path (`rm -rf "$dir"`). Name the directory
  literally, or let the tool that made it remove it.
- Commit trailers (`Co-Authored-By`, `Claude-Session`) come from the
  coordinator's brief for each session. Do not hardcode them in scripts or
  docs.
- Do not push and do not merge. The coordinator reviews and merges.
- Do not touch other agents' worktrees or uncommitted files.

## PeTTa pitfalls

Each of these has cost a debugging session. Most fail silently.

- **`Atom`-typed parameters get their argument unevaluated.** `(g (f 1) 2)`
  with `(: g (-> Atom Atom Bool))` compares the expression `(f 1)`. Bind the
  value with `let` first.
- **`add-atom` / `remove-atom` store nested calls unevaluated.**
  `(add-atom &s (k (+ 1 $n)))` stores the literal `(+ 1 $n)`. Bind computed
  cells in `let*` before the `add-atom`.
- **Variables are clause-wide.** A `$x` in a `case` pattern or a `let*` is the
  same variable as any other `$x` in that definition. Reusing a name for a new
  value turns the second binding into an equality test, which fails.
- **`and` / `or` never short-circuit.** Both arguments are always evaluated.
  Guard an expensive probe with a nested `if`.
- **An undefined function call silently stays data.** A call to a helper that
  does not exist on this branch, or is defined in a module loaded later,
  compiles as a constructor. Grep the definition, and test the effect, not just
  the answers.
- **A user `get-type` equation disables static type checks** for everything
  loaded after it. Never add one.
- **Strict mode rejects a type-variable result type** on a function with
  concrete clauses. Declare the result `Atom`. Pin tuple-destructured `let*`
  bindings that flow into typed parameters with `(the T $x)`.
- **The strict determinism checker rejects the library `map-flat` /
  `fold-flat` over a semidet step**, such as a `case`-based helper that can
  fail. Use `map-semidet` / `fold-semidet` from
  `runtime/backward/skeleton.metta`. The checker also proves a fold over a
  parameter list, not over a function result. Bind the list first and pass it
  in as a parameter.
- **`superpose` takes a literal tuple.** `(superpose (f $x))` superposes the
  atoms `f` and `$x`. Bind the list first.
- A plain `petta file.metta` run skips the strict checks.
  `scripts/test_metta.sh` runs them (`PETTA_STRICT_DET=1`).

## Landing a branch (coordinator)

The coordinator lands a branch with `scripts/land.sh`, run from any checkout
of the repository; it always works on the main checkout's `master`:

```bash
scripts/land.sh <branch> [--chainergame <cg-branch>] [--push] [--accept-flags <file>] [--clean]
```

It stops at the first failure and changes nothing before every check has
passed:

1. It refuses a main checkout that is not on `master` or has uncommitted
   changes to tracked files (and the same for `ChainerGame-supply` on
   `supply-network` with `--chainergame`).
2. It rebases the branch onto `master` in a detached worktree of its own
   (`.claude/worktrees/land-<branch>`, with a repointed `.venv`). On a
   conflict it prints the conflicted files, aborts the rebase and stops: the
   agent rebases, nobody resolves conflicts by hand here.
3. With `--chainergame`, it merges the ChainerGame branch into
   `supply-network` in a detached worktree (`ChainerGame-land-<branch>`;
   no rebase, fast-forward or merge commit), stopping the same way on a
   conflict.
4. It runs `scripts/verify.sh` through `capped --slots 8`.
5. With `--chainergame`, it runs the ChainerGame tests
   (`PYTHONPATH=src <ChainerGame-problog>/.venv-problog/bin/python -m pytest
   -q tests`) and the live SupplyNet tests
   (`SUPPLYNET_LIVE_PETTACHAINER=1`, the rebased PeTTaChainer's `.venv`
   running `unittest tests.test_supplynet`).
6. It runs `compare.sh master <rebased> --full` and stops unless the report
   says `PASS`, printing the summary either way. `--accept-flags <file>`
   allows only the exact case and metric pairs explicitly approved by the
   user. Every regression must match; any new flag, unapproved accuracy
   regression, failed/unsupported run or nondeterminism stops the landing.
   False timing flags that a paired rerun did not repeat are not regressions.
7. Only with `--push`: it fast-forwards `master` (and `supply-network`),
   pushes both to `origin`, then retires each landed branch's worktree and
   branch. It checks ancestry or patch equivalence with `git cherry`
   (no `+` commits); an unlanded merge commit cannot pass on patch
   equivalence alone. By default, a worktree holding modified, untracked
   or ignored files is kept with its branch and its files are listed.
   `--clean` also removes worktrees holding only `.venv`, `__pycache__`
   directories (at any depth), and root `scratch/` extras. It uses
   `git worktree remove --force` only for that explicit allowance; any
   tracked changes or other extra files keep the worktree and branch.

Approval files use three tab-separated columns: the full case name
(`suite case`, exactly as in `compare.json`), metric, and a one-line reason
recording the user's approval. No wildcards or partial names; ambiguous
report names are refused. Blank lines and `#` comments are allowed. A per-kind metric is named, for example,
`Inheritance error`. Each budget point is a separate case. Example:

```bash
printf 'supplynet example-case\tseconds\tUser approved known timing cost\n' >approved-flags.tsv
scripts/land.sh <branch> --accept-flags approved-flags.tsv  # check first
# Only after authorization to land/push:
scripts/land.sh <branch> --accept-flags approved-flags.tsv --clean --push
```

Accepted flags, their measured before/after values and reasons are printed
and saved in `accepted-flags.log` beside the verify and compare logs under
`.claude/land-logs/<branch>-<time>.<unique>/` in the main checkout. This is the
landing audit log; copy it with the landing report when handing back.

Without `--push`, checks run and landing commands are printed. One exception:
`scripts/land.sh <already-landed-branch> --clean` cleans an earlier landing
without rerunning gates or pushing, after checking patch equivalence.
It keeps any unsafe worktree and lists why. An unlanded branch still gets
only a dry run. Adding `--accept-flags` requests the usual gate run even
with `--clean`. The script's own temporary worktrees are removed on exit.

On exit it lists suspected leftover shell wait loops; it never kills them.
It checks literal `pgrep -f` targets against the process snapshot, excluding
waiting shells, and recognizes numeric PID guards on log waiters. For log
waiters without a PID, a missing job under the parent shell is only a
heuristic and is labelled as such. Dynamic shell expressions and jobs
launched elsewhere cannot reliably be resolved from command lines.

`scripts/test_land.sh` runs the script end to end in throwaway repositories
under `/tmp`, with stubs for `verify.sh`, `capped`, `compare.sh` and the
ChainerGame Python (the `LAND_*` variables at the top of `land.sh`). Run it
after changing `land.sh`; it takes a few seconds.

## Hand-back report

The coordinator reads the report, not your transcript. Include:

1. **Commits**: branch, worktree path, and `git log --oneline master..` with
   one line on what each commit does.
2. **Diagnosis**: what was wrong or missing, with the evidence (a failing
   test, a probe, numbers).
3. **Design**: what you changed and why this shape, plus the alternatives you
   rejected and why.
4. **Gates**: `scripts/verify.sh` result.
5. **Benchmarks**: the `compare.sh --full` summary line (`PASS` or the
   regression list), the accuracy-changed line, the report path, and the
   numbers that moved.
6. **Moved test values**: every expected value you changed in a test, old to
   new, with the reason it is correct now.
7. **Limits**: what is not done or not verified, and known weaknesses.
