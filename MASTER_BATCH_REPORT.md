# MASTER_BATCH round report

Branch `master-batch` (worktree `.claude/worktrees/master-batch`), from master 0fa2dafe.

## Commits

- efcf3032 Factor population base-rate updates across the rate's snapshots (fix, doc, regression test)
- this report

## Diagnosis

`pettachainer/metta/runtime/evaluator/values.metta:469-470` (`sk-factored-merge`, before the fix):
two views that both update the population base rate (`cpu`) were factored only when their
recorded prior TVs matched to 1e-12. In a batch, the other roots' search adds members to
the shared `(Front $t)` base-rate fold during the one evaluation, so rows built at
different moments read different snapshots of that one base rate. One Front t1 answer held
.0357@.444 (n=4), .0466@.5 (n=5) and .0599@.545 (n=6). At the Front t2 node, an
inverted-storm view and an antecedent-completion view failed the identity test and fell
through to `merge/revision`, which is plain revision. Front t1 came out at .271 for the
exact .642, and Front t2 at .615 for .831. The smallest repro is batch {t1, t3}; batch
{t1, t2} is exact. Single queries happen to read one snapshot.

## Design

An update over `cpu` is a likelihood ratio. Its value does not depend on the base-rate
snapshot it was read under, and `sk-factored-tv` already takes both priors. So `cpu`
updates now factor whatever values they read. The independence and distinct-witness
gates still apply. The merged view records the snapshot with the larger confidence (more
members). The merge reuses the existing population swap, so the result does not depend
on pair order. Non-`cpu` priors keep the strict 1e-12 identity, because there a
different value means different evidence.

Rejected: freezing base rates for the duration of a query. Rows from earlier queries
still hold older snapshots by design, because deep stale rows keep their values. The
merge would still have to handle mixed snapshots.

Size: +8/-3 lines of code and comments, plus documentation in
`docs/metta/prior_factored_merge.md`.

## Gates

- `scripts/verify.sh`: all 7 gates PASS (277 s).
- New test `tests/test_batch_base_rate_snapshots.py` checks batch and sequential runs at
  budgets 400, 1600 and 4000 against the 16-path oracle (delta 1e-9, c = .9999). It
  passes on this branch. On master it fails 6 subtests: t1 and t2 in batch mode, at each
  budget.
- Quick fuzzer (seed 1, 43 s): only the 3 known `leaf-report-{And,Or,Not}-1` flip
  BLOCKERs, which master also has. 0 ProbLog flags.
- Reviewer suite `master-batch-review`: 39 failures on base, 4 on this build, all of them
  neutral subtests. The reviewer's cp1 verdict confirms the fix.
- `compare.sh master --quick`: PASS, accuracy changed in 0 cases.
- `compare.sh master --full`: PASS. Accuracy changed in 1 of 22 cases, supplynet stage 3 untimed soft0.9 b100 s4, by a 1e-17 rounding difference. Fuzz n100 s22 flagged 8 KBs on both sides. Report: `bench/results/compare/0fa2dafe_vs_efcf3032_full/report.md`.
- Canary (`compare.sh anchor --canary`, against anchor b4065459): PASS. Report: `bench/results/compare/anchor-b4065459_vs_efcf3032_canary/report.md`.

## Moved test values

None.

## Limits

- **Inherited, deferred to #106.** A neutral Alarm a3 channel with .5@.9 reports changes
  all four answers, at c = .9999 and budget 4000. Batch and sequential runs also
  disagree. Master has the same failure. The likely cause is that an inversion reads a
  stored soft fact under its implied prior (the Jeffrey fallback), so its ratio depends
  on the base-rate snapshot.

  | Goal | exact | batch | sequential |
  |---|---:|---:|---:|
  | Front t1 | .6418 | .8015 | .7814 |
  | Front t2 | .8313 | .9481 | .9373 |
  | Front t3 | .8808 | .9734 | .9650 |
  | Front t4 | .8722 | .9609 | .9524 |

- The 3 compound-report flips are inherited from master and left as a follow-up.
- Snapshot interchangeability rests on the views' likelihood ratios being
  prior-invariant. That holds for inversions and completions of hard observations. It
  does not hold for soft observations read under an implied prior (see the first item).
