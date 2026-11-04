# Builder fuzzer validation, 2026-11-04

These are evidence from `scripts/fuzz_vs_problog.py --quick --jobs 8 --seed 1`.
`master/` tests the unchanged core at `9884ae6d`; `routedel2/` tests a scratch
detached checkout of `3a990295`, never the live routedel2 worktree.

Each directory contains the complete original cases, summary, ProbLog subset,
and reduced JSON/MeTTa repros. JSON replay preserves the paired transformation
and the producer-cost measurement; the MeTTa files exercise the corresponding
public KB/query. Original absolute import paths identify the trees that ran;
use `--chainer` to select a currently available checkout when replaying JSON.

```bash
( unset DISPLAY; ulimit -v 16000000
  /nexus/Dev/OpenCog/bench/capped --slots 1 .venv/bin/python \
    scripts/fuzz_vs_problog.py --jobs 1 --chainer /path/to/build \
    --replay experiments/fuzzmeta/routedel2/repros/CASE.json </dev/null )
```

`one_minimal` records a fixed point under the implemented deletions. A false
value means the trial limit was reached; the repro still reproduces the named
violation. Numerical variance estimates are labeled separately from exact
polynomial variances and certified analytic lower bounds. All original worker
answers, proofs, budgets, runtime paths and target commits are in `cases.jsonl`
and `summary.json`. A BLOCKER count is a count of query/invariant violations,
not independent root causes.
