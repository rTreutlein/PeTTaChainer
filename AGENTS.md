Run MeTTa code with the repository-pinned `.venv/bin/petta` executable.

Run the MeTTa suite through `scripts/test_metta.sh`. The runner preserves the
runtime working directory required by PeTTa library imports.

Before changing compiler, backward-chainer, forward-chainer, proof-merging, or
cache behavior, read `docs/metta/runtime_design_assumptions.md`. It records the
logical model and performance constraints that these components must preserve.
When writing metta code take care not to introduce unintended non determinism.
Example:
(= (f  a) a)
(= (f $var) b)

!(f a)
=>
(a b)

If you change something never leave any old code around for backwards compatibility.
Always delete all old code. If the old code was good we would't have needed the new one.

If you have to choose between 2 ways to do something always pick the one that is cleaner and better in the long term.
Don't take any shortcuts. Hard things are worth doing right. And the best solution is usually the simplest but getting there takes effort.

Write code in the cleaned-up style from the start instead of adding helpers and removing them later.
If a helper becomes unused or survives only because tests still call it, delete it and rewrite the tests.
Do not keep dead helpers around as test scaffolding.

Prefer fewer named functions.
Inline single-use wrappers, trivial aliases, and helpers that only rename one match, one constructor, or one expression.
Only introduce a helper when it materially improves readability, is reused enough to justify its existence, or marks a real semantic boundary.

Do not add defensive code when the underlying indexed match already fails cleanly.
If a missing match naturally becomes `()`, prefer that over extra `if` guards.
The best code is no code.

Prefer `let*` for sequential bindings instead of nested `let`.
Keep destructuring exact and simple.
Do not add extra staging variables unless they make the code easier to read.

Prefer `fold-flat` or `map-flat` over hand-written recursive list walkers when the semantics are the same.
Do not keep recursive helper functions whose only job is to iterate over a list once.

For state stores, design the representation for first-argument indexing in the generated Prolog.
Prefer dedicated spaces keyed by the real lookup key over tagged tuples in one mixed store.
Keep the external user-facing term shape separate from the internal runtime shape when that improves indexing and search performance.

Be careful around MeTTa reduction and compiler boundaries.
Some helpers should stay if inlining them changes specialization, leaves partial lets unreduced, or changes search semantics.
This is the main exception to the "prefer fewer functions" rule.
Do not keep a helper just because it feels tidy, but do keep it if direct inlining is observably worse in compiled behavior.

When simplifying code, rerun the relevant tests immediately.
If a cleanup changes behavior, revert it instead of rationalizing it.

The public API is documented in `docs/metta/API.md`. Never remove or change the signature
of anything listed there during an internal cleanup, even if only a test calls it.
Everything not listed is internal and may be inlined or removed once it has no
caller; a reference from a unit test alone does not make a helper public — rewire
or drop the test with it. Always grep tests/ before removing a function so you know
what the change touches.

## Working as a delegated agent

Details and the exact commands are in `docs/agent_workflow.md`. Read it first.

- Work in your own worktree branched from current `master`. Give it its own
  `.venv` (copy, then repoint, as the doc shows). A plain copy tests the
  main checkout's code.
- Memory and CPU are shared, and an OOM in this pane kills everyone: run
  every PeTTa, test or benchmark process through
  `/nexus/Dev/OpenCog/bench/capped [--slots N]`. It waits for the
  machine-wide admission pool, which starts a job only when memory and CPU
  allow it, then runs the job in the memory-capped slice. Give a parallel job
  its worker count, e.g. `capped --slots 8 env PETTA_JOBS=8
  scripts/test_metta.sh`. Run every PeTTa or benchmark process under
  `ulimit -v 16000000` with `DISPLAY` unset.
- Gates: `scripts/test_metta.sh`, `.venv/bin/python -m unittest discover -s tests`,
  and `scripts/verify.sh` before hand-back.
- Benchmarks: `/nexus/Dev/OpenCog/bench/compare.sh master <worktree> --quick`
  while iterating, `--full` before hand-back. Results are stored by the code
  that ran, so a rerun of unchanged code is free. Do not improvise runners,
  seeds or frozen builds.
- Git: never run a bare `git stash`, never `rm -rf` a variable path, and do
  not push or merge. The coordinator merges. Commit trailers come from the
  brief.
- PeTTa traps that fail silently (Atom-typed args, `add-atom`, clause-wide
  variables, strict `and`, undefined calls as data, and others) are listed in
  the doc.
- Hand back commits, diagnosis, design, the `compare.sh` summary, moved test
  values with reasons, and limits.
