# Fix #154 / #151

Branch: `fix154`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fix154`.
Base: `709a703ec4ed3c225b08ef47cedb56f38ef31bd2`.

## Commits

Implementation, tests and runtime documentation:

```text
2a76e168 fix: preserve reader bindings in compound settling
```

This is followed by a report-only commit, `docs: record fix154 validation`.
Both commits carry the brief's required co-author and session trailers.
`git log --oneline 709a703e..fix154` lists the complete hand-back.

## Cause

`settled-reading` rejected a certain branch at compilation whenever that
branch omitted any variable of its compound. For #154, the comparison mentions
`$count`, while the other branch mentions `$collection`. The outer conjunction
has already bound both when it reads the Or, but compilation had discarded
both settling readings. The remaining complete reading required a proof of
the unavailable `(Cardinality ParkCats (PointMass 2))`, so it produced nothing.
The shared variables themselves survive lowering and the count computation
runs correctly when read without the Or.

#151 has the same cause. Fold member abstraction replaces fixed predicate
arguments with independent variables. Thus `(Or (About $r (A X))
(Part $r (A X)))` compiles with separate argument variables in its branches.
The static coverage test discards both settling readings before narrowing
restores `(A X)`. The certain Part fact consequently cannot settle the Or.

Both failures were reproduced against the unmodified base using the pinned
worktree runtime. `scratch/repro-master.log` shows the #154 direct and ground
controls succeeding and the Or failing. `scratch/report-master.log` shows
#151's direct-Part control succeeding and its Or failing. The retained KE
artifacts were read without running or modifying their probe.

## Fix and design

Compound readings retain a settling branch with a CPU guard over exactly the
variables absent from that branch. The existing `vars-covered?` operation
checks those variables after the reader supplies its bindings. No comparison,
cardinality, witness, predicate or fixture-specific rule is added. No runtime
store, scheduler policy, public API or helper function is added.

The structural guard executes during application construction even when its
arguments remain open. Failed guards are pruned by the ordinary application
prefilter and by CPU join advancement, before any rejected row can consume
numerical evaluation allowance. Treating the guard like a deferred truth-value
formula passed the unit suite but changed small-budget replay; the focused
standard replay comparison now passes with zero accuracy changes.

Whole conjunctive rule-antecedent shortcuts keep their existing coverage
requirement. They have no enclosing premise join to select omitted relation
tuples. Extending the new permission to those shortcuts allowed a historical
false observation to bypass a temporal predecessor join; the ordinary temporal
regressions caught this. The final implementation makes this binding boundary
explicit in the existing settling functions. The affected temporal tests pass
with their original values.

Open readers still cannot enumerate an unconstrained missing variable. The
same mechanism handles Or's certain-true branch, And's certain-false branch,
and computations whose bundle already carries its truth value.

Specializing and installing more producers at every runtime key read would
duplicate work and interfere with the existing bounded producer lifecycle.
Changing fold abstraction would miss #154 and discard its compilation reuse.
Neither is necessary: the error is the timing of the branch-coverage check.

Production change: two MeTTa files, net **+81 lexical tokens** excluding comments
(parentheses and non-whitespace atoms counted separately); the suggested net
zero target was not reached. There is no retained alternate implementation.

## Tests and moved values

`tests/metta/test_exists_or_binding.metta` contains 12 assertions covering:

- #154, both Or branch orders, count 3 versus threshold 2;
- count 1 with both branch orders, still no proof;
- direct comparison, ground Or, and existential comparison without Or;
- #151's report join, both branch orders across its A and B leaves;
- an unsupported C leaf and a source belonging to a different report, both
  still without a proof.

`tests/metta/test_connective_settling.metta` adds checks for bound and unbound
readers, false And settling under Not, and an ordinary arithmetic Compute
branch. Existing temporal completion and certain-merge regressions also ran
unchanged. Focused strict-determinism checks passed (`scratch/focused-narrow.log`).

The only pre-existing expected value changed is `openKb`'s `(C t v)` in
`test_connective_settling.metta`:

```text
() -> (: (by r (settled a)) (C t v) (STV 1.0 0.9998000399670116))
```

The reader fixes `v`, and the certain `(A t)` settles `(Or (A t) (B t v))`.
The corresponding open `(C t $u)` and open Or remain unanswered.

Newly recovered issue answers (full outputs: `scratch/answers.log`):

| Query | Before | After |
|---|---|---|
| #154, either Or order, count 3 | no proof | STV(1, 0.999500249625312) |
| #151, either tested Or order/leaf | no proof | STV(1, 0.9996001597861454) |

The direct and ground controls retain their values. No other existing test
expectation was changed.

## Gates and benchmarks

`scripts/verify.sh`: **PASS**, 233 seconds, recorded under key `104e331831bc`.
All six gates passed: lint, MeTTa, Python, import scaling, judgment scaling and
the ConceptNet query. MeTTa: **163 passed, 0 failed**. Python: **1045 tests**
in 74 files / 634 units, 24 expected failures, one skip; 4554 measured query
rows and zero aborts. Judgment scaling recorded three query rows and zero
aborts. Log: `scratch/verify-eager-final.log`.

`compare.sh master <worktree> --full`: **PASS**, **accuracy changed in 0 cases**,
411 seconds, 46 runs executed and three stored results reused. Every recorded
base/candidate/reference run succeeded. Report:
`/nexus/Dev/OpenCog/bench/results/compare/709a703e_vs_709a703e-dc828b8d5_full/report.md`.

`compare.sh anchor <worktree> --canary`: **PASS**, **accuracy changed in 4 cases**
against the older anchor: live b50 5 shifts s1; conflict pln-stated l spq4 s1;
conflict pln-reliable l spq4 s1; scale m spq4 r10 s1. The harness's comparison
with master admits no new blocking regression. Existing anchor deficits are
listed in that report. Every recorded run succeeded. Report:
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_709a703e-d9c338bd1_canary/report.md`.

The final canary used the documented `BENCH_TIMING_HOST=` local-timing override:
the remote timing host lacks this worktree's `.venv/bin/python` (exit 127).
The initial remote attempt is retained in `scratch/compare-canary.log`; the
successful local run is in `scratch/compare-canary-final.log`. Both final
comparisons used runtime tree `dc00b604cab3be631652356d67eac11535849567`; their
build labels differ because documentation changed while the harness resolved
the worktree.

**RSS gate: PASS.** Across every full-comparison case with both measurements,
the largest increase over master is **+0.7096%**, SupplyNet stage 3 timed b25 s3,
197.3 MB to 198.7 MB. The largest workload, scale l spq16 s1, moves from
1499.0 MB to 1497.6 MB. All per-case increases are below +5%; details are in
`scratch/rss-audit.json`. No benchmark accuracy value moved against master.

The final revision also passes the strict #154/#151 regressions
(`scratch/eager-binding.log`) and the focused standard replay comparison:
`PASS`, `accuracy changed in 0 cases`, report
`/nexus/Dev/OpenCog/bench/results/compare/709a703e_vs_709a703e-d73a133d3_quick-replay_b25_s4/report.md`.

Commands use `DISPLAY` unset, `ulimit -v 16000000`, and stdin from `/dev/null`.
Verification uses `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`.
The standard comparisons use `PETTACHAINER_REPO` set to this worktree;
`compare.sh` admits and caps its own runs.

An initial, discarded broader settling change failed seven MeTTa files and
quick replay b25 s4 (Brier 0.07750714699026715 to 0.08645842886638855).
Its report is
`/nexus/Dev/OpenCog/bench/results/compare/709a703e_vs_709a703e-dbec607d9_quick/report.md`.
Those results describe the discarded code, not the final candidate.
The intermediate revision with deferred binding guards also failed full replay
b25 s4 (Brier 0.07750714699026715 to 0.08451; runtime suffix `d258ffaba`).
Its six verification gates passed, but the benchmark exposed the construction
phase error described above. Neither revision is retained in the final code.

## Limits

Only this brief's fix and validation round are included. The change does not
add uncertain-branch bounds or enumeration of unconstrained domains. No
scheduling, budget or anytime policy changed, so no curves run was requested.
The KE repository, master, shared environment and other worktrees were not
modified. Nothing was pushed, merged or written to GitHub.
