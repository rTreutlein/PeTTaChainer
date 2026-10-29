# Forward chaining and learning cleanup

Branch: `simplify-forward`. Worktree:
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/simplify-forward`.
Base: `9102bd1c`.

## Commits

- `35a5b067` — requirements, state inventory, token baseline and replacement design.
- `30d951d0` — direct forward base-rate tally; remove generic sampling intermediates.
- Hand-back documentation commit: `Record forward learning cleanup validation
  and benchmark limits` (contains this report; runtime tree unchanged).

## Diagnosis and design as built

Forward chaining already shares the backward skeleton, joins, value selection,
evaluation and proof storage. The agenda's seed, changed-key and rest states
have different budget/lifetime contracts. Mining/review likewise keep distinct
observation windows, candidate sightings, live rules and screening reasons.
Removing these distinctions would change tested behavior.

The removable mechanism was the forward aggregate sampling framework. A numeric
subscription always used the same extractor, evidence accumulator, step,
finish and TV mode. Class-link subscriptions only dirty ordinary instance
folds. The implementation now recognizes those fixed numeric operations at the
subscription boundary and carries just KB and pattern in its identity and
descriptor. Updates match a copied pattern, convert the fact directly into a
weighted positive contribution and replace that member's observation. Removals
select the same member directly. Publication finishes the numeric state as a
base rate, with the same smoothing and unchanged-cache suppression.

Deleted `fa-rate-subscription`, `fa-acc`, `FAggSample`/`fa-sample`,
`fa-sample-for`, `fa-item` and `fa-store-cache!`. No old sampling implementation,
fallback or compatibility entry points remain. None were public or called by
tests; both production and test trees were searched before removal.

Preserved selective indexes, stable subtraction/arithmetic order, member count,
observation provenance, source exclusion edges, context facades, user override,
class-link dirtying, cache notification, contribution replacement and seeding.
The agenda, scheduling, budgets, join construction, mining decisions and
withdrawal/forgetting behavior are unchanged.

The first implementation incorrectly passed an unreduced `BaseRateTv` call to
the Atom-typed smoothing boundary; its suite failed with a type mismatch.
It was replaced by a sequential binding that computes the TV before smoothing.
The corrected implementation passed all 162 strict MeTTa files. Existing
generic fold finalization helpers remain because non-base-rate folds and the
reserved evaluator use them; they are real reduction/type boundaries.

`pettachainer/metta/repos/PLN/` and its tracked files are already absent at the
base commit. The remaining historical libPLN comparison examples import an
external library and are excluded from strict scope by the existing runner.
The formula library used by this runtime is already in `third_party/pln_formulas/`.
There was no vendored libPLN tree to delete or relocate.

## Validation

All PeTTa/test/benchmark commands use `/nexus/Dev/OpenCog/bench/capped`,
`ulimit -v 16000000`, unset DISPLAY and `</dev/null`. The supplied `.venv`
finder points at this worktree. MeTTa suites use `scripts/test_metta.sh`.

- Baseline strict MeTTa suite: **162 passed, 0 failed** (`scratch/baseline-metta.log`).
- Corrected direct tally strict MeTTa suite: **162 passed, 0 failed**
  (`scratch/direct-tally-metta-v2.log`).
- `scripts/verify.sh`: **PASS**, all six gates, 492 s wall
  (`scratch/direct-tally-verify.log`): lint; strict MeTTa **162/0**;
  Python **969 tests**, 60 files, 125 existing expected failures, one skip;
  import scaling **0.994** late/early ratio (limit 1.5); judgment scaling
  **PASS**; ConceptNet **2 results**. Python metrics: **4,430 query rows,
  0 aborts**; judgment scaling metrics: **3 query rows, 0 aborts**.
- Quick comparison: **PASS; accuracy changed in 0 cases** (10 cases, 122 s wall).
  Report: `/nexus/Dev/OpenCog/bench/results/compare/9102bd1c_vs_30d951d0_quick/report.md`.
  Log: `scratch/direct-tally-quick.log`.
- Full comparison with local timing and `--no-fail-fast`: **PASS;
  accuracy changed in 0 cases**. All **22 accuracy cases** are identical
  (23 cases including the independent reference); **36 runs** executed,
  11/45 stored results reused, 336 s wall. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/9102bd1c_vs_30d951d0_full/report.md`.
  Log: `scratch/direct-tally-full-local.log`.
  All selected base/candidate/reference exits are zero, with no unsupported
  marker. StationOps replay beliefs are identical (200 beliefs for each seed).
  The fuzzer retains the same 6 flagged KBs, with no new flags, unsupported
  KBs or crashes. One timing flag did not repeat: SupplyNet stage 3 timed
  b25 s3, initially 7.330 → 8.925 s; paired rerun **7.555 → 7.580 s**.
- Initial anchor canary: **PASS; accuracy changed in 4 cases**, all changes
  relative to the older anchor, with no regressions relative to master.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_30d951d0_canary/report.md`.
  Fresh local paired timing pass: **PASS; accuracy changed in 4 cases**
  relative to the anchor, 12 successful runs, 105 s wall. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_30d951d0_canary-retime-20261029T134202/report.md`.
  Log: `scratch/direct-tally-canary-local.log`.
  All selected base/candidate exits are zero. The same four anchor accuracy
  differences and nine behind-anchor metrics are present on master too;
  the harness accepted no regression of this branch against master.
  Separate stored-result comparison of master and this branch: **PASS;
  accuracy changed in 0 cases**, all six cases identical, all 12 results
  reused. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/9102bd1c_vs_30d951d0_canary/report.md`.
  Log: `scratch/direct-tally-canary-master.log`.

The initial canary's six timing-host attempts exited 127: `/usr/bin/time`
could not run this worktree's `.venv/bin/python` because that path is absent
on `roman@dev-server`. Its local accuracy runs succeeded. The initial full
comparison with remote timing was terminated while still queued, before its
benchmark jobs ran (`scratch/direct-tally-full.log`, exit 143). Both replacements
use the harness's documented `BENCH_TIMING_HOST=` setting, retaining the
same cases, seeds, frozen trees, capped processes and ordinary timing gates.
The local canary also uses the standard `--retime` option so its timings are
fresh paired runs rather than the failed remote attempts. No benchmark
infrastructure, remote environment or shared service was edited.

This report was written while verification ran. Its changing documentation
tree prevented the standard verification cache from recording in the main
checkout (the log confirms "result not recorded"); gate logs in this worktree
are the evidence for this round. Runtime code did not change during the gates.

## Full-profile timing details

Seconds from the standard full report (the harness selects the timing record
separately from the immutable accuracy record). These are end-to-end chainer
workloads; all accuracy metrics and replay belief streams are unchanged.

| Workload | Master s | Branch s | Harness note |
| --- | ---: | ---: | --- |
| supplynet stage 1 b100 s3 | 4.676 | 4.487 | — |
| supplynet stage 3 timed b25 s3 | 7.33 | 8.925 | noise (rerun) |
| supplynet stage 3 timed b50 s3 | 12.33 | 12.22 | — |
| supplynet stage 3 timed b100 s3 | 15.47 | 16.06 | reused |
| supplynet stage 3 untimed b25 s4 | 11.28 | 9.807 | — |
| supplynet stage 3 untimed b100 s4 | 16.15 | 16.11 | — |
| supplynet stage 3 timed soft0.9 b100 s3 | 30.97 | 31.46 | — |
| supplynet stage 3 untimed soft0.9 b100 s4 | 42.33 | 44.09 | — |
| scale l spq4 s1 | 58.5 | 60.8 | reused |
| scale l spq16 s1 | 130.5 | 127.1 | — |
| scale s spq1 s1 | 3.279 | 3.223 | — |
| conflict pln-sources m spq4 s2 | 17.27 | 17.7 | — |
| conflict pln-sources m spq4 s3 | 16.65 | 16.39 | — |
| conflict pln-reliable l spq4 s1 | 64.15 | 69.89 | reused load differs |
| learned stage 3 timed learned b50 r200 s1 | 21.36 | 20.51 | — |
| supplynet stage 4 extend b50 s2 | 19.11 | 19.09 | — |
| learned stage 3 timed learned b50 r200 s2 | 23.22 | 21.89 | — |
| learned stage 3 untimed learned mined b50 r50 h10 s3 | 82.36 | 82.17 | — |
| replay b25 s1 | 4.937 | 4.826 | — |
| replay b25 s4 | 5.713 | 6.004 | reused |
| combinet n2 s1 | 0.947 | 0.937 | reused |
| fuzz all n100 s22 | 60 | 58 | — |

## Moved values and failures

No test expectations, proof shapes, scheduler scores or TVs changed. No tests
were rewired or removed. `EXPECTED_FAILURES` is unchanged. Public API signatures
are unchanged. Full, quick and master-canary comparisons all report exact
accuracy identity. The older anchor's four differences are baseline differences,
not moved answers from this cleanup.

## Token accounting

Counter: `scratch/core_count.py`, o200k_base, whole source/comments/declarations.
Baseline per-file snapshot: `scratch/core-before.json`.

Before: core **326,388**, third-party **17,685**, total **344,073**.
After direct tally: core **325,886**, third-party **17,685**, total **343,571**.
Net **−502**; no new library or counting exclusion.

| File under `pettachainer/metta/runtime/` | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `backward/upward.metta` | 5,701 | 5,701 | 0 |
| `forward/aggregates.metta` | 6,012 | 5,567 | −445 |
| `forward/schema.metta` | 1,926 | 1,869 | −57 |
| `base_rates.metta` | 1,734 | 1,734 | 0 |
| `hypothesis_mining.metta` | 4,792 | 4,792 | 0 |
| `hypothesis_review.metta` | 2,875 | 2,875 | 0 |
| `knowledge_store.metta` | 5,238 | 5,238 | 0 |
| `backward/forgetting.metta` | 3,732 | 3,732 | 0 |
| **Subsystem** | **32,010** | **31,508** | **−502** |

All other counted files, including native files and third-party formulas,
are byte-for-byte unchanged. Documentation/report tokens are outside the
provided code counter; there is no code moved into documentation or a library.

## Limits

Reserved evaluator/compiler/scheduler/native files were not edited. Further
consolidation of registry/tally shapes or the mining and regime implementation
would cross the reserved `evaluation.metta`/`runtime_helpers.pl` interfaces and
belongs to a later round. This round specializes the avoidable sampling design;
it does not claim the remaining subsystem is globally minimal.

All required gates completed. The standard timing gate reports no confirmed
regressions. This is a source simplification with preserved measured behavior;
it does not establish a uniform speedup: full-profile totals are SupplyNet +2%,
StationOps replay +2%, scale −1%, learned −2%, conflict +6%, fuzzer −3%.
Conflict's largest row is marked `load differs`; its timing is not comparable.
The full report retains all per-case numbers and the timing-noise rerun.
No separate forward-only timing claim is made from these end-to-end workloads.
Curves were not required: scheduling, budgets and anytime behavior did not change.
All processes started for this round have finished or, for the superseded queued
remote full comparison, been terminated and reaped. No push, merge or GitHub write.
