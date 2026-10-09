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

Keep scratch files in your scratchpad or worktree, not in `/tmp`: `/tmp` is
wiped on reboot.

## Commands

Run from the worktree root.

| Step | Command |
|---|---|
| One MeTTa file | `(ulimit -v 16000000; .venv/bin/petta file.metta)` |
| MeTTa suite (strict det) | `scripts/test_metta.sh` |
| Python tests | `.venv/bin/python -m unittest discover -s tests` |
| All gates | `scripts/verify.sh` (MeTTa, Python, import scaling, ConceptNet) |
| Benchmarks | `/nexus/Dev/OpenCog/bench/compare.sh master <worktree> --quick` |

`scripts/test_metta.sh` runs `PETTA_JOBS=$(nproc)` (32) files at once; set
`PETTA_JOBS=8` when other agents are benchmarking.

### Benchmarks: `bench/compare.sh`

`compare.sh` is the benchmark step. Do not freeze builds by hand, pick your
own seeds or write runner scripts.

```bash
/nexus/Dev/OpenCog/bench/compare.sh <base> <candidate> [--quick|--full] [--jobs N]
```

- `<base>`, `<candidate>`: a PeTTaChainer ref or commit (`master`, `a1980394`),
  a frozen build name under `bench/chainers/`, or a worktree path. A worktree
  is frozen as its HEAD plus its uncommitted diff and its untracked files
  under `pettachainer/`.
- `--quick` (default) while iterating, about 2.5 min. Run `--full` before
  hand-back, about 18 min at 4 jobs.
- The report goes to
  `bench/results/compare/<base>_vs_<candidate>_<profile>/report.md`. Its
  first line is `PASS` or `REGRESSIONS (n): ...`, and the next line says
  whether any accuracy number changed at all.
- Accuracy numbers are deterministic, so any change in them is real. Time
  is not. A single seconds flag just over 10% on one run can be noise; rerun
  before you explain it.

See `bench/README.md` for the suites and thresholds.

## Memory

WSL has 29 GB. A runaway run has frozen the whole machine before, and other
agents share it.

- Start a job only while `free -g` shows at least 8 GB available.
- Run at most 4 jobs in parallel unless the coordinator says otherwise.
- Run every PeTTa or benchmark process under `ulimit -v 16000000`, with
  `DISPLAY` unset so no profiler GUI opens.
- Do not run SupplyNet scale size `xl` at 16 steps per query (about 14 GB)
  while anyone else is benchmarking.

`compare.sh` follows these rules itself.

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
