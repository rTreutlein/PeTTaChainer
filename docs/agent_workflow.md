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

Wait on something only your job produces: its PID (`wait`, `kill -0 $pid`),
its own output file, or the background task's completion notification. Never
wait on a global condition such as `until ! pgrep -f "compare.sh master"`:
other agents run the same commands, so the loop may never end, and it keeps
your worktree locked after you hand back. Stop every loop you started before
handing back.
`pgrep -f "<pattern>"` inside a loop also matches the loop's own command line,
so such a loop never ends: wait on the PID you started instead.

A waiter that looks for a marker in a log never ends if the job dies or is
replaced before writing it. Tie every waiter to the job's PID, so it ends
with the job either way:

```bash
until grep -q "GRID DONE" "$log" || ! kill -0 "$pid" 2>/dev/null; do sleep 30; done
```

When you kill or replace a job, kill its waiter in the same command. Keep
one waiter per job.

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
scripts/land.sh <branch> [--chainergame <cg-branch>] [--push]
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
   says `PASS`, printing the summary either way.
7. Only with `--push`: it fast-forwards `master` (and `supply-network`),
   pushes both to `origin`, then removes each landed branch's worktree
   (`git worktree remove`, which keeps a worktree with uncommitted or
   untracked files) and deletes the branch, each only after
   `git merge-base --is-ancestor` shows the target contains it.

Without `--push` it is a dry run: every check runs, and it prints the
commands it would run instead of landing. Its own worktrees are removed on
every exit. Logs go to `.claude/land-logs/<branch>-<time>/` in the main
checkout.

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
