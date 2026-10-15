# Issue 54: cached exclusion branches after review

This follows the review of `8fdf269c`. The branch was rebased onto current
master `22bd1a09` after the context-overlay work landed. The original fix is
now `32435d97`; the cache follow-up is its next commit. No push, merge or tag
was performed. The earlier [report](report.md) describes the first fix and
its historical results, including behavior superseded here.

## Mechanism

In `pettachainer/metta/runtime/backward/evaluation.metta`, `sk-admits?`
(line 1365) rejects a view whose dependencies meet the reader's exclusions.
`sk-value` (line 2354) selects exclusion-filtered views, and `sk-admit-step`
(line 1386) tries `sk-rebuild-view` (line 1407) before the older-compatible-view
fallback (line 1398). Cache lookup/publication is at lines 1460/1483; branch
invalidation is in `runtime/backward/skeleton.metta` at line 1879.

Rebuilt row views now live in a separate bounded cache, indexed by a scalar
digest of the owner key hash and row hash, with full key checks. Each entry
contains its cuts, freshness and value. A settled entry serves E exactly when
its dependencies miss E and its cuts are contained in E. Successful and empty
branches are reusable within and across queries. Cuts record actual rejected
branches, including cuts propagated from reused children; irrelevant members
of the original exclusion set do not prevent reuse under a weaker set.

Cuts are immutable ordered hash lists. They cannot use interned dependency
nodes: forgetting can remove keys from those nodes, which would erase a
necessary reuse restriction. Cached value dependencies remain ordinary
dependency nodes. Both the proof collector and the dependency collector retain
cached values. Proof publication uses the same implementation as ordinary
views, without installing a cut branch as an ordinary latest view.

Each cached row subscribes to its direct inputs. An input change invalidates
only its cached readers and their cached consumers, retaining compatible stale
values as incumbents. A stale row unsubscribes once, then subscribes again
after a settled refresh. Stale values cannot satisfy settled cache lookups.
New contexts prune dominated entries; each row retains at most eight entries.
Dropping a row's views also drops its cache and input subscriptions. The four
durable cache stores use master's scoped store interface, so overlay writes
and invalidation do not mutate borrowed MAIN entries.

A cache miss still pays `sk-take! sk_eval_budget` before evaluating a row.
If any nested rebuild is unpaid or conditioning is pending, the result is not
published as settled. Unpaid rebuilding marks the active ordinary **reader**
stale through `sk-stale-reader-step`, respecting `sk_holding`; it does not
stale the owner of an otherwise valid ordinary view. Holding is released
after answers have been read. The mandatory direct-premise exclusion check
remains; no transitive reachability prewalk or new allowance was added.

## Regression coverage and changed expectations

The focused MeTTa regression covers zero-budget hits across queries, stronger
and weaker exclusion sets, irrelevant original exclusions, dependency
intersection, empty cached branches, input invalidation, unsubscribe/relink,
reader holding, collector roots, the eight-entry bound and subscription
retirement. The Python campaign keeps both C1 insertion orders at
`0.888849375588311`, with proof `revision(xf, bx(mb(mf)))`, exercises all
six/24 permutations of three-/four-node cycles, and rejects unsupported
self-support. C1 also checks that Assuming M strengthens the local answer
without changing the cached MAIN branch or MAIN's answer.

Relative to the reviewed commit:

| Existing fixture | Reviewed value | Cached value | Explanation |
| --- | --- | --- | --- |
| near-root C1 B1, budget 25, confidence | 0.8999998199501539 | 0.8999998721576475 | Reuse restores master's finite-budget result. The computation-count bound is unchanged. |
| nested conditioning, budget 300, Degraded plant t5 | (0.138655, 0.9999359441308396) | (0.12665003790915424, 0.9999312324523072) | Cache reuse and retry change the finite-budget allocation. At budget 3000 the candidate reaches master's original (0.14626802934111227, 0.9999620912647443). The budget-300 computation-count bound remains unchanged. |
| smokes shared subproof label | 305 | 307 | Additional cached proof publication changes the printed identifier. Proof structure and truth value are unchanged from the reviewed fix. |

The first fix's other changed expectations remain, including the overlap
recovery budget of 200. A budget-20 probe still falls short; the cache does
not justify reverting that recovery budget. No PLN truth formula changed.
Master independently fixed the collector test's old fixed-5000-unit setup;
that upstream test is retained without a local change.

## Gates and full comparison

- `scripts/test_metta.sh`: **136 passed, 0 failed**.
- `.venv/bin/python -m unittest discover -s tests`: **160 passed** after rebase.
- `scripts/verify.sh`: **all six gates PASS**, 119 seconds; 877 Python query rows, zero aborts; three judgment-scaling query rows, zero aborts.
- The isolated three-test history campaign, including the added overlay checks, passes.

The final full comparison reports **REGRESSIONS (17): nine accuracy and eight confirmed timing flags**; accuracy changes in 13 cases. All runs exit zero. This does **not** meet the expected performance recovery. One original starvation flag is removed, while the two scale spq16 flags and all four original timing flags remain. There is one new accuracy flag and four new timing flags.

Full report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_07889721-d0737c9f3_full/report.md`.

Production tree: `874c4d29d581a706df817286fa94aa9866dc8974`. Frozen candidate build `07889721-d0737c9f3` has the same production tree as the committed follow-up. The report uses a pre-amend commit label because the snapshot includes the scoped-store integration as a working-tree diff. The run executed 72 jobs and reused 1 results in 219.8 seconds. No benchmark scripts, stored results, seeds or thresholds were edited.

### Every original flag: before and after

The reviewed numbers are from the original cca2b333 comparison; the current master column is 22bd1a09. Timing measurements were taken at different loads, so compare each candidate with its accompanying base and the paired rerun, rather than treating the two candidate times as a controlled direct speed comparison. Errors are mean absolute error; seconds are chainer time. Timing rows use the final comparison's measured base time; its confirmed reruns are listed below.

| Original flag | Reviewed candidate | Cached candidate | Current master | Status |
| --- | ---: | ---: | ---: | --- |
| supplynet stage 3 timed b50 s3, previous_storm | 0.0029672571 | 0.000978718283 | 2.39971832e-10 | Recovered below the flag threshold; still above master. |
| supplynet stage 3 untimed b25 s4, degraded | 0.00584272953 | 0.00584272953 | 0.00267607657 | KEEP: reviewed cold/converged PLN answer. |
| scale l spq16 s1, front | 0.00843695256 | 0.00843695256 | 0.00300934308 | Remains; identical to the reviewed candidate. |
| scale l spq16 s1, storm | 0.00386378764 | 0.00386378764 | 0.00149882374 | Remains; identical to the reviewed candidate. |
| conflict pln-sources m spq1 s2, error | 0.0843503821 | 0.0842077308 | 0.0749686521 | Remains; slightly better than reviewed. |
| conflict pln-sources m spq1 s2, system | 0.0519459738 | 0.0519459738 | 0.0355480383 | Remains; unchanged. |
| conflict pln-sources m spq4 s2, error | 0.0897497524 | 0.0866573256 | 0.0765604439 | Remains; improved from reviewed. |
| conflict pln-sources m spq4 s2, component | 0.128180161 | 0.121272131 | 0.11390325 | Remains; improved from reviewed. |
| conflict pln-sources m spq4 s2, system | 0.051319344 | 0.0520425198 | 0.0392176382 | Remains; worse than reviewed. |
| supplynet stage 3 untimed b50 s4, seconds | 12.316 | 12.897 | 9.614 | Remains. |
| supplynet stage 3 untimed b100 s4, seconds | 17.286 | 16.045 | 10.6 | Remains. |
| learned stage 3 timed learned b50 r200 s1, seconds | 18.316 | 19.128 | 14.88 | Remains. |
| learned stage 3 timed learned b50 r200 s2, seconds | 19.551 | 20.406 | 15.7 | Remains. |

The five conflict s2 flags were classified by the review as non-converged allocation effects. The cache reduces three of their errors, leaves one unchanged and worsens one. They remain flags at the listed budgets; that classification is not a claim that they have disappeared.

### All final flags and paired timing evidence

- supplynet stage 3 timed b50 s3 producing_unstocked error 0.001184 -> 0.003226
- supplynet stage 3 untimed b25 s4 degraded error 0.002676 -> 0.005843
- scale l spq16 s1 front error 0.003009 -> 0.008437
- scale l spq16 s1 storm error 0.001499 -> 0.003864
- conflict pln-sources m spq1 s2 error 0.07497 -> 0.08421
- conflict pln-sources m spq1 s2 system error 0.03555 -> 0.05195
- conflict pln-sources m spq4 s2 error 0.07656 -> 0.08666
- conflict pln-sources m spq4 s2 component error 0.1139 -> 0.1213
- conflict pln-sources m spq4 s2 system error 0.03922 -> 0.05204
- supplynet stage 3 untimed b25 s4 seconds 5.854 -> 7.889 (rerun 5.663 -> 7.309)
- supplynet stage 3 untimed b50 s4 seconds 9.614 -> 12.9 (rerun 9.241 -> 12.93)
- supplynet stage 3 untimed b100 s4 seconds 10.6 -> 16.05 (rerun 10.81 -> 14.89)
- conflict pln-sources m spq4 s2 seconds 10.73 -> 13.88 (rerun 10.84 -> 12.35)
- conflict pln-sources m spq4 s3 seconds 11 -> 12.35 (rerun 10.49 -> 12.33)
- learned stage 3 timed learned b50 r50 s1 seconds 14.85 -> 18.95 (rerun 13.54 -> 16.73)
- learned stage 3 timed learned b50 r200 s1 seconds 14.88 -> 19.13 (rerun 11.98 -> 16.56)
- learned stage 3 timed learned b50 r200 s2 seconds 15.7 -> 20.41 (rerun 11.79 -> 15.67)

The new accuracy flag is timed b50 s3 `producing_unstocked`: the reviewed candidate was 0.00224665618; the cached candidate is 0.00322605604; master is 0.001184. It is a finite-budget changed prediction in the same cyclic/conditioning model, not an accepted accuracy improvement. This run does not establish its individual warm/cold or exhaustion behavior.

### All changed aggregate errors

| Case | Master | Reviewed candidate | Cached candidate |
| --- | ---: | ---: | ---: |
| supplynet stage 3 timed b50 s3 | 0.00157910134 | 0.00257855987 | 0.00222555841 |
| supplynet stage 3 timed b100 s3 | 0.00279861439 | 0.00293057965 | 0.00251484157 |
| supplynet stage 3 untimed b25 s4 | 0.000598539557 | 0.00113063383 | 0.00112912238 |
| supplynet stage 3 untimed b50 s4 | 0.001018352 | 0.0012066625 | 0.0011747343 |
| supplynet stage 3 untimed b100 s4 | 0.00095319232 | 0.00117473409 | 0.00117473428 |
| scale l spq16 s1 | 0.000928412642 | 0.0024159978 | 0.0024159978 |
| conflict pln-sources m spq1 s2 | 0.0749686521 | 0.0843503821 | 0.0842077308 |
| conflict pln-sources m spq4 s2 | 0.0765604439 | 0.0897497524 | 0.0866573256 |
| conflict pln-sources m spq1 s3 | 0.223341784 | 0.223394351 | 0.223394351 |
| conflict pln-sources m spq4 s3 | 0.217989735 | 0.217827266 | 0.218002422 |
| learned stage 3 timed learned b50 r50 s1 | 0.0813132003 | 0.0813132003 | 0.0813778131 |
| learned stage 3 timed learned b50 r200 s1 | 0.0813132003 | 0.0813132003 | 0.0813778131 |
| learned stage 3 timed learned b50 r200 s2 | 0.0625477745 | 0.0630138899 | 0.0625827807 |

These models contain cycles introduced by inversion, completion, persistence or rule refinement. The admissible-branch correction and the changed budget allocation both affect their answers. The review establishes the untimed b25 s4 change as correct convergence; the remaining changed means alone do not distinguish convergence corrections from incomplete search.

Coverage is unchanged. The fuzzer, replay and other unchanged cases remain recorded in the full comparison; no newly failed candidate process or memory regression is reported. Cached values have bounded entry counts, but the implementation adds proof roots and invalidation bookkeeping, so a bounded cache does not imply zero runtime overhead.

## Curves and higher-budget conflict probe

Complete seven-family `--curves` report: `/nexus/Dev/OpenCog/bench/results/compare/22bd1a09_vs_f9f2e4f5_curves/curves.md` (310 seconds wall). All requested ladder runs completed without unsupported cases or timeouts; the official stability stopping rule ended the conflict ladder at spq8. No custom ladder or seed was substituted.

| Curve | Last budget | Master error | Reviewed error at this budget | Cached error | Master / cached seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| scale l s1 | 32 | 1.8469663e-05 | 1.8469663e-05 | 1.8469663e-05 | 132.855 / 149.673 |
| scale m s1 | 32 | 0.000108449761 | 0.000108449761 | 0.000108449761 | 64.323 / 59.080 |
| stage 3 timed s2 | 200 | 0.00298625966 | 0.00162344775 | 0.00168029999 | 18.500 / 18.897 |
| stage 3 untimed s3 | 200 | 0.00140559526 | 0.00172607449 | 0.00140559525 | 19.001 / 21.654 |
| stage 2 r10 s1 | 200 | 3.90905978e-17 | 3.90905978e-17 | 3.90905978e-17 | 10.419 / 9.080 |
| conflict m s1 | 8 | 0.110876054 | 0.111634222 | 0.110996363 | 15.379 / 13.519 |
| replay s3 | 200 | 0.140378451 | 0.140378451 | 0.140378451 | 12.315 / 9.970 |

At untimed s3 b200, the cache matches master's error within 2e-11 and reduces candidate time from the reviewed **26.790 to 21.654 seconds**. Current master takes 19.001 seconds: about **14% overhead**, versus roughly 41% in the reviewed comparison. These are separate runs with different loads, not a paired before/after speed trial.

The scale l spq16 errors remain unchanged, but both builds reach approximately 0.000018469663 at spq32. That establishes recovery at a larger budget for this fixture; it does not satisfy the requested spq16 recovery. Timed s2 b200 improves error relative to current master, while the conflict s1 ladder has small allocation differences.

The review's conflict m s2 spq64 CLI probe was repeated for the final candidate and current master, using the exact workload arguments and the official frozen builds. Results are under `/nexus/Dev/OpenCog/bench/results/history-bug/cache_conflict64_{base,candidate}.{out,err}`.

| spq64 metric | Current master | Cached candidate |
| --- | ---: | ---: |
| aggregate error | 0.0976327924 | 0.0839155643 |
| component error | 0.120008987 | 0.115391141 |
| system error | 0.0752565981 | 0.0524399872 |
| coverage | 0.9875 | 0.9875 |
| chainer seconds | 42.575 | 48.599 |

The cached candidate is more accurate on all three listed errors at spq64, consistent with the review's allocation-noise diagnosis at spq1/spq4. It is **slower** in this probe (48.599 versus 42.575 seconds), so the earlier review's speed advantage does not carry over. This probe was not a paired timing-confirmation run.

## Remaining limits

The requested cache and unpaid-reader mechanisms are implemented and regression-tested, but performance recovery is incomplete. The full suite still has the two scale spq16 flags, five low-budget conflict flags, eight timing flags, and the new producing_unstocked flag, in addition to the deliberately retained correct-convergence flag. No claim of a clean benchmark gate or readiness for `parity-target-1` is made.

The cache removes repeated walks of settled compatible branches. It cannot reuse a stale entry as settled after an input changes, and an incomplete rebuild is retried with metered work. The measured residual costs have not been attributed to a single remaining hot path; further changes to allocation, mandatory-transitive dependency tracking or conditioning would need their own evidence. The current regression family proves C1 and the tested small-cycle permutations, not arbitrary history independence for every PLN graph.

All task-owned test, verification, comparison and probe processes completed before hand-back; no process is intentionally left running.
