# E3: event-node dependence

Branch: `e3-dependence`; worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/e3-dependence`.
Base: `d1ee51a7`. Implementation commit: **`9e4e96d2`**, "Model event-node dependence
with shared conditional parents". It contains the implementation, focused tests,
calibration-ledger shrink and consolidated contract. **`55fe12de`**, "Cache
event-node discovery within each evaluation", adds scoped structural-plan caching
and preserves compiler-owned readers. A separate report commit follows both;
`git log --oneline master..e3-dependence` lists the local commits.

## Diagnosis and design as built

E2 summarized each sibling independently before applying a compound likelihood.
P4's proof, for example, used a prior for A already carrying an inversion from B's
node message, then applied the compound message again. That discarded the common
parent's joint distribution and made confidence far too low. Ground compound
readers also needed to distinguish a conditional conclusion's own raw reports
from an independent marginal parameter.

`event_graph.pl` discovers observed compounds through existing skeleton structure
and instantiates fixed CTV templates through the conclusion index. It enumerates
one bit per event and selects each rule's positive or negative parameter with the
same parent bit everywhere. Roots and both rule branches are independent count
parameters. Raw reports on conditional conclusions and compound observations are
likelihood factors, multiplied once inside each world. Zero-confidence sources
are omitted before factor construction. Roots without counts remain uniform;
template discovery does not depend on a zero-confidence fact creating a join.

The graph reads authored sources through the existing leaf/scope interface.
Forward copies, materialized outputs and frozen summaries are excluded. Evidence
uses scoped source identities and owner-bearing rule proof references. Output
subscriptions include children without a report, so adding a child report wakes
the node. Dependencies retain primitive roots and observations rather than
internal inferred marginals. The evaluation-local caches hold source data rather
than output proof DAGs and clear with forcing state. Scope visibility is cached per overlay; structural plans,
including unsupported results, also use the skeleton row generation. Current
reader exclusions are checked after plan lookup. This avoids repeated discovery
without reusing one world's sources in another or hiding newly admitted rows.

The tensor rule uses fewer points for concentrated Betas when there are more than
three free dimensions, retaining convergence checks and conservative fallback.
This makes weak roots plus narrow rule branches affordable, notably P4/F0 and
P17/F0. The original rules are retained for up to three free dimensions, so
independent E2 readers retain their numerical snapshots.

The source contract is consolidated in `docs/metta/event_node_contract.md`.
Long duplicated reader/numerics comments moved there, contributing to the core
token reduction. A native rewrite of the existing message/Jeffrey merge helpers
was rejected and restored: it failed the ground-negated-implication test despite
looking equivalent. The tested MeTTa reduction boundary remains.

## Derivation of moved answers

All means use the D0 posterior: `s = E[N]/E[Z] = N(mu)/Z(mu)`. Variance is
`E[N^2/Z]/E[Z] - s^2`, using the same independent count parameters and likelihoods.
The oracle is `tests/tv_calibration_oracles.py`; an observation's predictive
strength is `m = (n*s+1)/(n+2)`, with `n=800*c/(1-c)`.

- **P3:** write `a=P(A)`, `r1=P(B|A)`, `r0=P(B|not A)`.
  `Z=m*a+(1-a)*((1-m)+(2*m-1)*r0)`, `N_A=m*a`, and
  `N_B=m*(a*r1+(1-a)*r0)`. Both branches remain parameters.
- **P4:** write `q=P(C)`, `a_i=P(A|C=i)`, `b_i=P(B|C=i)`.
  `z_i=(1-m)+(2*m-1)*(a_i+b_i-a_i*b_i)`,
  `Z=q*z_1+(1-q)*z_0`, `N_C=q*z_1`, and
  `N_A=m*(q*a_1+(1-q)*a_0)`. One C bit branches both children.
- **P10:** with independent B at b, use
  `z_i=(1-m)+(2*m-1)*(a_i+b-a_i*b)`,
  `Z=q*z_1+(1-q)*z_0`, `N_C=q*z_1`, `N_CA=q*a_1*m`.
- **P17:** given B=i, `p_i=a*x_i+c*y_i-a*c*x_i*y_i`.
  `z_i=(1-m)+(2*m-1)*p_i`, `Z=b*z_1+(1-b)*z_0`, `N_B=b*z_1`.
  `N_A=a*sum_i P(B=i)*((1-m)+(2*m-1)*(x_i+(1-x_i)*c*y_i))`.
  The shared B source is one parameter, counted once.
- **P5/P6:** their existing repeated-atom enumerations remain calibrated;
  no expected numerical constants were changed.

The H-setting oracle targets are P3 A/B `.920963/.907758`, P4 A/C
`.796993/.681064`, P10 C/CA `.599964/.562421`, P17 A/B `.843250/.812551`.
The F0 targets use uniform omitted roots, rather than retaining their written
zero-confidence strengths. New lifecycle tests also compare raw child reports
against this oracle, including two observed children of one parent.

## Calibration ledger

The complete D0 run before ledger maintenance ran **528 tests**: **61 expected
failures and 61 unexpected successes**, with no failures or errors. Only those
61 newly passing entries were removed: **44 main, 14 Assuming, 3 omission**;
by probe: **P3 20, P4 20, P10 8, P17 13**. The ledger shrinks **122 -> 61**.
It grows nowhere. P3/P4/P5/P6/P10 have no remaining expected main failures.

No pre-existing numerical assertion was edited. The exact removed ledger entries
and their recorded old values are listed in the appendix; main rows include the
D0 oracle targets. The 14 Assuming and 3 omission removals mean equality is exact,
not merely within a calibration tolerance.

## Verification and comparisons

`scripts/verify.sh`: **PASS**, all six gates, **526 s wall**. MeTTa: 161 files,
zero failures. Python: **971 tests in 60 files / 587 units**, eight workers,
64 expected failures (61 D0 plus three pre-existing repeated-query cases),
one nightly skip. Python query metrics: **4,448 rows, zero aborts**; judgment
scaling: three query rows, zero aborts. Import/judgment scaling and ConceptNet
also pass. Log: `scratch/e3_verify_cached.log`; recorded key **`8a37e6acccca`**.
This run validates the final source tree in `55fe12de`.

Fresh-process regression checks passed five tests in 251.6 s, including bridge
query-order preservation and individually selected P4/P17 F0 omission/calibration
cases (`scratch/e3_fresh_process.log`). The parallel gate exposed a raw native
lookup of an as-yet undefined empty summary store; replacing it with the existing
`sk-summary-fact?` classifier fixed this, without adding store-initialization state.

Final comparisons, both **PASS**:

| Comparison | Result | Accuracy | Wall | Present run exits |
|---|---|---|---:|---|
| `compare.sh master <worktree> --full` | PASS | identical in all 22 compared cases | 250 s | 45/45 zero |
| `compare.sh anchor <worktree> --canary` | PASS | four inherited differences from the old anchor | 167 s | 12/12 zero |

Master advanced to **`9102bd1c`** during the parallel work. The final full run
compares that master with the final E3 source tree; the branch remains based on
`d1ee51a7` and was not merged or rebased. The runner froze the final source tree
under label `9e4e96d2-d67789e9a` before the performance commit. Its source is the
same as `55fe12de`, so these are the final implementation's results.

Reports:

- `/nexus/Dev/OpenCog/bench/results/compare/9102bd1c_vs_9e4e96d2-d67789e9a_full/report.md`
- `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_9e4e96d2-d67789e9a_canary/report.md`

Logs: `scratch/e3_full_cached.log`, `scratch/e3_canary_cached.log`.
All present base/candidate/reference records were checked for exit zero and no
unsupported marker. The full run includes the ProbLog fuzzer and scale-l/spq16.
The canary's four differences from the anchor were already on master, and are
not E3 accuracy changes.

The corrected stage-4 path also passed a focused paired full comparison against
original base `d1ee51a7` (candidate 19.41 s, base 19.77 s; unchanged accuracy).
That standard filtered run is recorded at
`/nexus/Dev/OpenCog/bench/results/compare/d1ee51a7_vs_9e4e96d2-d3b9d28e4_full-supplynet_stage_4_extend_b50_s2/report.md`.

The focused E3 lifecycle suite passed all four tests: correlated observed children,
a late raw child report on the same KB, zero-confidence addition to a warm node,
and forward-copy exclusion with repeated reads. The strict MeTTa suite passed
**161 files, zero failures**, including nested consequent projection. The moment
numerics suite passed **20 tests** during development and in final verification.

The first quick comparison and first full comparison had no accuracy changes but
confirmed timing regressions. Investigation found an overbroad observation
precheck: unrelated private contexts enabled graph walks in MAIN. The final
precheck uses only visible scopes and active Assuming seeds. A later full run
still caught repeated structural discovery; evaluation-local scope/plan caches
removed that repeated work. The final full and canary comparisons above pass.
Replaced comparison results are diagnostic, not final acceptance evidence.

## Token and symbol audit

Baseline core: **326,924** o200k tokens; third party: **17,685**.
Final core: **326,318**, a reduction of **606 tokens**. Third party remains
**17,685**; final total **344,003**. The supplied `scratch/core_count.py` was used
unchanged; results are in `scratch/e3_tokens_cached_final.txt`.

At baseline, ground marginal-projection and pooling code was already absent.
`marginal-proj`, `sk-pool-part`, and `sk-same-pool?` have zero hits over
`pettachainer/`, `third_party/`, `tests/`, and `docs/`. Stale dispatch-audit entries
for `compile-output-children`, `frontier-parts-join-pool`,
`frontier-parts-same-pool`, and `frontier-pool-potential` were removed; their same
four-tree symbol audit is empty. `AndMarginalProjection` remains only in its
third-party definition and the rule-level conditional-consequent export's STV
and CTV branches, as required by the brief's FTV exception.

No public signature changed. No obsolete implementation or compatibility shim
was retained. The independent-message and predicted-compound paths still serve
semantics outside the supported conditional graph.

## Limits

The new graph accepts acyclic, explicit, single-parent CTV templates, at most
twelve atoms/parameters, and bounded discovery of twenty-four statements. Other
rules and over-cap graphs use the prior evaluator. This does not implement E5's
general graph merge/separator/cap policy. Pure prediction queries without a
compound observation retain their previous conditioning path. Remaining Assuming
failures and plain observations without a compound remain in the ledger for
later steps. No broader calibration claim is made for those paths.

All actual PeTTa, test, and benchmark jobs used `bench/capped`, virtual-memory
limit 16,000,000 KiB, unset DISPLAY, and `/dev/null` stdin. No master/other-worktree
code, GitHub state, push, or merge was changed. All background jobs are reaped
before hand-back.

## Appendix: removed expected failures

| Probe | Setting | Goal | Kind | Previous recorded failure |
|---|---|---|---|---|
| P3 | H | `(A a)` | main | s .8668 c .0299 ; s* .9210 c* .9339 ; z 0.8 var 698 |
| P3 | H | `(A a)` | assuming | Assuming s .8235 c .0235 ; MAIN s .8668 c .0299 |
| P3 | H | `(B a)` | main | s .8323 c .0693 ; s* .9078 c* .9075 ; z 1.6 var 216 |
| P4 | H | `(A a)` | main | s .7536 c .0179 ; s* .7970 c* .9373 ; z 0.4 var 882 |
| P4 | H | `(A a)` | assuming | Assuming s .7309 c .9328 ; MAIN s .7536 c .0179 |
| P4 | H | `(C a)` | main | s .6344 c .0257 ; s* .6811 c* .8900 ; z 0.5 var 313 |
| P10 | H | `(And (C a) (A a))` | main | s .3125 c .0127 ; s* .5624 c* .8968 ; z 1.8 var 538 |
| P17 | H | `(A a)` | main | s .8509 c .9228 ; s* .8433 c* .9214 ; z 2.1 var 0.941 |
| P17 | H | `(B a)` | main | s .8031 c .0229 ; s* .8126 c* .9134 ; z 0.1 var 444 |
| P3 | L | `(A a)` | main | s .8666 c .0300 ; s* .9206 c* .9340 ; z 0.8 var 695 |
| P3 | L | `(A a)` | assuming | Assuming s .8233 c .0236 ; MAIN s .8666 c .0300 |
| P3 | L | `(B a)` | main | s .8321 c .0695 ; s* .9074 c* .9078 ; z 1.6 var 216 |
| P4 | L | `(A a)` | main | s .7534 c .0179 ; s* .7966 c* .9373 ; z 0.4 var 879 |
| P4 | L | `(A a)` | assuming | Assuming s .7306 c .9328 ; MAIN s .7534 c .0179 |
| P4 | L | `(C a)` | main | s .6344 c .0257 ; s* .6808 c* .8900 ; z 0.5 var 313 |
| P10 | L | `(And (C a) (A a))` | main | s .3124 c .0127 ; s* .5623 c* .8968 ; z 1.8 var 538 |
| P17 | L | `(A a)` | main | s .8506 c .9228 ; s* .8430 c* .9213 ; z 2.1 var 0.941 |
| P17 | L | `(B a)` | main | s .8027 c .0230 ; s* .8121 c* .9134 ; z 0.1 var 441 |
| P3 | X | `(A a)` | main | s .8669 c .0299 ; s* .9210 c* .9339 ; z 0.8 var 699 |
| P3 | X | `(A a)` | assuming | Assuming s .8235 c .0235 ; MAIN s .8669 c .0299 |
| P3 | X | `(B a)` | main | s .8323 c .0693 ; s* .9078 c* .9074 ; z 1.6 var 216 |
| P4 | X | `(A a)` | main | s .7537 c .0179 ; s* .7970 c* .9372 ; z 0.4 var 882 |
| P4 | X | `(A a)` | assuming | Assuming s .7309 c .9328 ; MAIN s .7537 c .0179 |
| P4 | X | `(C a)` | main | s .6344 c .0257 ; s* .6811 c* .8900 ; z 0.5 var 313 |
| P10 | X | `(And (C a) (A a))` | main | s .3125 c .0127 ; s* .5624 c* .8968 ; z 1.8 var 538 |
| P17 | X | `(A a)` | main | s .8509 c .9228 ; s* .8433 c* .9214 ; z 2.1 var 0.941 |
| P17 | X | `(B a)` | main | s .8031 c .0229 ; s* .8126 c* .9134 ; z 0.1 var 445 |
| P3 | K1 | `(A a)` | main | s .8647 c .0309 ; s* .9178 c* .9346 ; z 0.8 var 670 |
| P3 | K1 | `(A a)` | assuming | Assuming s .8219 c .0244 ; MAIN s .8647 c .0309 |
| P3 | K1 | `(B a)` | main | s .8307 c .0713 ; s* .9046 c* .9106 ; z 1.6 var 213 |
| P4 | K1 | `(A a)` | main | s .7511 c .0186 ; s* .7931 c* .9380 ; z 0.4 var 853 |
| P4 | K1 | `(A a)` | assuming | Assuming s .7282 c .9331 ; MAIN s .7511 c .0186 |
| P4 | K1 | `(C a)` | main | s .6344 c .0257 ; s* .6782 c* .8905 ; z 0.4 var 314 |
| P10 | K1 | `(And (C a) (A a))` | main | s .3116 c .0126 ; s* .5609 c* .8971 ; z 1.8 var 541 |
| P17 | K1 | `(A a)` | main | s .8481 c .9227 ; s* .8405 c* .9213 ; z 2.1 var 0.942 |
| P17 | K1 | `(B a)` | main | s .7990 c .1124 ; s* .8085 c* .9137 ; z 0.2 var 85.9 |
| P3 | F0 | `(A a)` | assuming | Assuming s .6666 c .0021 ; MAIN s .7361 c .0034 |
| P3 | F0 | `(B a)` | main | s .8000 c .0050 ; s* .9165 c* .2065 ; z 0.7 var 86.8 |
| P4 | F0 | `(A a)` | main | s .7536 c .0103 ; s* .7970 c* .0917 ; z 0.3 var 10 |
| P4 | F0 | `(A a)` | assuming | Assuming s .7309 c .0126 ; MAIN s .7536 c .0103 |
| P10 | F0 | `(And (C a) (A a))` | main | s .3333 c .0000 ; s* .5999 c* .0027 ; z 0.6 var 2.91 |
| P10 | F0 | `(And (C a) (A a))` | omission | MAIN s .3333 c .0000 ; without the compound s .6000 c .0030 |
| P17 | F0 | `(A a)` | main | s .7098 c .0000 ; s* .6961 c* .0023 ; z 0.0 var 2.77 |
| P17 | F0 | `(A a)` | omission | MAIN s .7098 c .0000 ; without the compound s .7142 c .0000 |
| P17 | F0 | `(B a)` | omission | MAIN s .7384 c .0048 ; without the compound s .6917 c .0086 |
| P3 | F1 | `(A a)` | main | s .8666 c .0254 ; s* .9194 c* .2414 ; z 0.7 var 18.3 |
| P3 | F1 | `(A a)` | assuming | Assuming s .8205 c .0199 ; MAIN s .8666 c .0254 |
| P3 | F1 | `(B a)` | main | s .8314 c .0573 ; s* .9079 c* .8860 ; z 1.4 var 210 |
| P4 | F1 | `(A a)` | main | s .7536 c .0173 ; s* .7970 c* .7372 ; z 0.4 var 171 |
| P4 | F1 | `(A a)` | assuming | Assuming s .7309 c .2960 ; MAIN s .7536 c .0173 |
| P4 | F1 | `(C a)` | main | s .6344 c .0232 ; s* .6811 c* .1150 ; z 0.4 var 5.6 |
| P10 | F1 | `(And (C a) (A a))` | main | s .3129 c .0118 ; s* .5632 c* .1074 ; z 1.8 var 8.05 |
| P17 | F1 | `(B a)` | main | s .8030 c .0215 ; s* .8111 c* .1475 ; z 0.1 var 7.74 |
| P3 | F5 | `(A a)` | main | s .8668 c .0294 ; s* .9208 c* .7252 ; z 0.8 var 133 |
| P3 | F5 | `(A a)` | assuming | Assuming s .8232 c .0230 ; MAIN s .8668 c .0294 |
| P3 | F5 | `(B a)` | main | s .8322 c .0679 ; s* .9078 c* .9053 ; z 1.6 var 215 |
| P4 | F5 | `(A a)` | main | s .7536 c .0178 ; s* .7970 c* .9119 ; z 0.4 var 613 |
| P4 | F5 | `(A a)` | assuming | Assuming s .7309 c .7667 ; MAIN s .7536 c .0178 |
| P4 | F5 | `(C a)` | main | s .6344 c .0254 ; s* .6811 c* .5280 ; z 0.5 var 43.8 |
| P10 | F5 | `(And (C a) (A a))` | main | s .3125 c .0126 ; s* .5625 c* .5125 ; z 1.8 var 65.6 |
| P17 | F5 | `(B a)` | main | s .8031 c .0227 ; s* .8124 c* .5990 ; z 0.1 var 63.3 |

## Review fix round (2026-10-29; after c0a1e33b)

This round addresses all six findings in `review-e3-codex.md`. The branch and
worktree remain `e3-dependence`; there is no rebase, merge, push or GitHub write.
The implementation commit is **`6a157f7d`**, "Fix event graph completeness, priors and compatible reads". These fixes supersede the earlier
empty-root and structural-cache descriptions in this report.

### Root fixes and exact regressions

1. Observation discovery now retains every authored observation reached through
   admitted rows, including atomic children outside the observed compound.
   All their atoms seed the joint model; an unsupported or over-cap closure
   rejects the graph. P3/H plus `D|A=(1,0)` and certain D returns **A=1** with
   zero variance (the existing STV endpoint convention prints c=.9999).
   The derivation is immediate: D excludes every A=0 world.
2. A root without authored counts reads `sk-part-prior` after plan lookup.
   Configured and empirical cavity priors therefore use exactly the ordinary
   reader, with the graph's evidence and excluded keys; their proofs and fold
   dependencies accompany the graph answer without becoming observations.
   Certain `Or(A,B)`, fixed B|A=.9/.2, and configured `(STV 0 1)` for A now
   returns **A=0**, since its prior gives every A=1 world zero mass.
   An additional empirical-population test checks the answer against that same
   cavity reader and `mu/(mu+.2*(1-mu))`.
3. Both the scope-availability and structural-plan caches include
   `(sk-input-epoch, sk_row_seq)`, retaining their scope/overlay separation.
   A P3/H raw B report `(STV .75 .9)` changes the native graph answer without
   another evaluation or row admission; its mean equals the D0 oracle with
   that report added. A separate test caches absence before the first compound,
   adds that compound, then admits real rows without resetting the evaluation;
   all reads see the changed inputs and row generations.
4. Template discovery enumerates all live visible authored producers before
   accepting the single supported CTV producer. P3 plus an observed D and an
   STV-valued D->B rule returns the ordinary evaluator's value unchanged;
   the graph cannot hide that producer behind B's supported CTV rule.
5. `sk-node-apply` passes the proof/TV filter and excluded evidence to the native
   graph reader. A replacement must have disjoint evidence and match the filter;
   otherwise its already compatible alternative survives. P3 plus raw B at
   `(STV .75 .9)`, excluding k0, retains that raw report with no k0 overlap.
   Separate proof and TV filter checks retain the same report. An additional
   population test verifies that the cavity prior also excludes the consumer's
   evidence, not only the graph observations. Failed graph
   integration also falls back through the same exclusive read.
6. Concentrated axes now use `1+floor((N+7)/8)` points; the larger-grid
   comparison uses nominal 7/9 passes, followed by 9->17->33 refinement.
   Every compared Beta axis therefore strictly refines. For the exact eight
   `Beta(3601,3601)` parameters, the compared grids are **2^8 and 3^8** rather
   than identical 2^8 grids. Instrumentation asserts the actual grid sizes
   and an integrated answer. Initial 17-pass sizing skips integration when
   it exceeds 5,000 points; refinement retains the 70,000-point cap and the
   existing unresolved bound. This retains enough resolution for mixed
   broad/concentrated P17/F0/F5 parameters without weakening calibration.

Ten new tests cover the six findings: nine graph/source/filter/cache tests
and one quadrature regression. No production helper or public API was removed;
internal signatures changed together with all callers. There are no obsolete
arities or compatibility wrappers. No name was deleted in this round. The existing four-tree audit for all
previously deleted E3 names was rerun and remains empty.

### Calibration, gates and comparisons

`EXPECTED_FAILURES` diff against c0a1e33b: **empty (61 -> 61)**. No existing
numerical assertion, proof-shape expectation or scheduler-score pin changed.
P3/P4/P5/P6/P10 retain no expected main failures. The initial uniform-axis
attempt was rejected when the gate caught P17/F0 bounds. A subsequent low-order mixed-grid attempt was also rejected when it
made P17/F5 B claim the bound. The final 7/9 mixed-grid comparison passes those
cases and preserves omission equality. Interrupted diagnostic gates and their
queued full comparisons are not acceptance evidence; they were stopped and
reaped. The earlier diagnostic canaries passed but do not validate the final
source tree.

Focused graph/source/filter/cache validation passed all **13 tests**, including
the four existing dependence tests. Final numerical regression validation covers
the eight concentrated Betas plus P17/F0 A/B and P17/F5 B calibration.

Final validation: **PASS**, all six `scripts/verify.sh` gates in **424 s**; recorded key
`d52c72d1f287`. Strict MeTTa: **161 files, zero failures**. Python: **981
tests in 60 files / 588 units**, sixteen workers, **64 expected failures**
(61 D0 plus the three existing repeated-query cases), one nightly skip.
Python metrics: **4,457 rows, zero aborts**; judgment scaling: three query
rows, zero aborts. Import scaling and ConceptNet passed.
Logs: `scratch/e3_fix_verify_complete.log`, `scratch/e3_fix_full_complete.log`,
`scratch/e3_fix_canary_complete.log`.

Both required comparisons **PASS** on the final runtime tree
`5f0c99ad4566`, frozen as `c0a1e33b-d40380ac2` before `6a157f7d` was committed.
There were no source changes between that freeze and the implementation commit.

| Comparison | Verdict | Accuracy | Wall | Present run exits |
|---|---|---|---:|---|
| master `9102bd1c` --full | PASS | identical in all 22 compared cases | 962 s | 45/45 zero |
| anchor `b4065459` --canary | PASS | four inherited differences, also on master | 153 s | 12/12 zero |

The full comparison executed 45 runs and reused two records; the canary
executed 12 runs and reused six records. No present run is unsupported.
Both StationOps belief streams are identical to master's. The ProbLog fuzzer
retains **6 -> 6 flagged KBs**, with no newly flagged KB, unsupported KB or
crash. One initial conflict timing flag did not repeat in the paired rerun
(47.31 -> 47.97 seconds), so the standard runner rejected it as a regression.
The full wall time includes the shared full-run queue and CPU admission waits
for its two eight-slot fuzzer jobs; no runner or admission policy was bypassed.

Reports:

- `/nexus/Dev/OpenCog/bench/results/compare/9102bd1c_vs_c0a1e33b-d40380ac2_full/report.md`
- `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_c0a1e33b-d40380ac2_canary/report.md`

### Tokens and limits

`scratch/core_count.py` reports core **326,314**, third party **17,685**, total
**343,999** (`scratch/e3_fix_tokens.txt`). The original E3 baseline is 326,924:
**net -610 core o200k tokens**, within the brief's <=0 budget. The fix round
alone reduces the previous 326,318 by 4 tokens. Repeated reader comments now refer to
`docs/metta/event_node_contract.md`; the actual source/prior/filter/cache and
quadrature contracts are documented there.

Every actual PeTTa, test and benchmark command in this round used `bench/capped`,
`ulimit -v 16000000`, unset DISPLAY and `/dev/null` stdin. The pinned worktree
runtime and the standard suite/comparison runners were used. No source or Git
state in master, the main checkout or another worktree was changed. The standard
runners' shared benchmark/result and validation-cache artifacts are their usual
outputs. All started jobs are reaped before hand-back.

The supported graph remains the bounded, acyclic, single-parent CTV graph
described above; unsupported producers retain the ordinary evaluator. This
round adds no general E5 graph merge or new universal numerical-enclosure claim.

### D0 moment changes against reviewed HEAD

An isolated copy of c0a1e33b's moment module and the fixed module evaluated the
same D0 terms, using `probe_node` and `event_oracle`. All **48 means are exactly
unchanged**. The table lists every variance that changed in floating point;
all differences above 1e-9 relative move closer to the oracle. Other changes
are below that scale. The largest relative movement is 2.295e-7, for P17/F5 B.
All values use `V=E[N^2/Z]/E[Z]-s^2`; the STV conversion is unchanged.
Data: `scratch/e3_fix_moment_diff.jsonl`; the comparison completed without errors.

| Probe | Setting | Goal | Reviewed V | Fixed V | D0 oracle V |
|---|---|---|---:|---:|---:|
| P4 | H | `(A a)` | 1.3537501053262346e-05 | 1.353750105681506e-05 | 1.3537501056481993e-05 |
| P4 | H | `(C a)` | 3.3563516703638552e-05 | 3.3563516758206013e-05 | 3.3563516758872147e-05 |
| P10 | H | `(C a)` | 3.5646034725389519e-05 | 3.5646034734326815e-05 | 3.5646034734382326e-05 |
| P10 | H | `(And (C a) (A a))` | 3.5408189998753503e-05 | 3.5408190008301421e-05 | 3.5408190008023865e-05 |
| P4 | L | `(A a)` | 1.3538812732916128e-05 | 1.353881273591373e-05 | 1.3538812736024752e-05 |
| P4 | L | `(C a)` | 3.3559462073451396e-05 | 3.3559462128296413e-05 | 3.3559462128740503e-05 |
| P10 | L | `(C a)` | 3.5641439300126976e-05 | 3.5641439309397338e-05 | 3.5641439309286316e-05 |
| P10 | L | `(And (C a) (A a))` | 3.5398303808054088e-05 | 3.5398303817435472e-05 | 3.5398303817213428e-05 |
| P4 | X | `(A a)` | 1.3537357649751058e-05 | 1.3537357652859683e-05 | 1.3537357653414794e-05 |
| P4 | X | `(C a)` | 3.3563981447937152e-05 | 3.3563981503614837e-05 | 3.3563981503004214e-05 |
| P10 | X | `(C a)` | 3.5646558721069699e-05 | 3.5646558730229039e-05 | 3.5646558730173528e-05 |
| P10 | X | `(And (C a) (A a))` | 3.5409316378909317e-05 | 3.5409316388124168e-05 | 3.5409316388179679e-05 |
| P4 | K0 | `(A a)` | 2.1518281917376481e-05 | 2.1518281917598525e-05 | 2.1518281917654036e-05 |
| P4 | K0 | `(C a)` | 3.4707760655339204e-05 | 3.4707760655283693e-05 | 3.4707760655450226e-05 |
| P10 | K0 | `(C a)` | 3.4707760655394715e-05 | 3.4707760655228181e-05 | 3.4707760655339204e-05 |
| P4 | K1 | `(A a)` | 1.3554459223019677e-05 | 1.3554459226128301e-05 | 1.3554459226683413e-05 |
| P4 | K1 | `(C a)` | 3.3525701843617473e-05 | 3.3525701896297555e-05 | 3.3525701895908977e-05 |
| P10 | K1 | `(C a)` | 3.5601320968248196e-05 | 3.5601320976796913e-05 | 3.5601320976796913e-05 |
| P10 | K1 | `(And (C a) (A a))` | 3.5311379413593968e-05 | 3.5311379422253708e-05 | 3.5311379422253708e-05 |
| P4 | F0 | `(A a)` | 0.0019782839738808899 | 0.0019782839739949099 | 0.0019782839739900249 |
| P4 | F0 | `(C a)` | 0.068381283397003112 | 0.068381283397016657 | 0.068381283396826309 |
| P10 | F0 | `(C a)` | 0.081896986537895733 | 0.081896986537952909 | 0.08189698007902918 |
| P10 | F0 | `(And (C a) (A a))` | 0.07629206013265194 | 0.076292060132708617 | 0.076292053685851124 |
| P17 | F0 | `(A a)` | 0.074486964965528091 | 0.074486965046944409 | 0.074486965046968334 |
| P17 | F0 | `(B a)` | 0.058108457858280005 | 0.058108458243412597 | 0.058108458243508077 |
| P4 | F1 | `(A a)` | 7.2069865008406175e-05 | 7.2069865009516398e-05 | 7.2069865009627421e-05 |
| P4 | F1 | `(C a)` | 0.0020698327942136885 | 0.0020698327942182404 | 0.0020698327942173522 |
| P10 | F1 | `(C a)` | 0.0027616361781814813 | 0.0027616361781813703 | 0.002761636178182203 |
| P10 | F1 | `(And (C a) (A a))` | 0.0025294138250381848 | 0.0025294138250396281 | 0.002529413825039295 |
| P17 | F1 | `(A a)` | 0.0010915106213127412 | 0.0010915106238689187 | 0.0010915106238641448 |
| P17 | F1 | `(B a)` | 0.0010988646229045385 | 0.0010988646568534932 | 0.0010988646568532712 |
| P4 | F5 | `(A a)` | 1.9543281000844459e-05 | 1.954328100184366e-05 | 1.954328100184366e-05 |
| P4 | F5 | `(C a)` | 0.00024249771050793845 | 0.00024249771051026991 | 0.00024249771051210178 |
| P10 | F5 | `(C a)` | 0.0003164973532112092 | 0.00031649735321304107 | 0.00031649735321187533 |
| P10 | F5 | `(And (C a) (A a))` | 0.00029225544862326869 | 0.00029225544862421238 | 0.00029225544862471198 |
| P17 | F5 | `(A a)` | 0.00012206908082568191 | 0.00012206908295719909 | 0.00012206908296708008 |
| P17 | F5 | `(B a)` | 0.000127438145466785 | 0.00012743817470739494 | 0.00012743817471183583 |

## R2 follow-up: exclude imported population-prior dependencies (2026-10-29)

Implementation commit: **6e682473** (`Reject excluded prior dependencies in
event graph replacements`), on `e3-dependence`, following reviewed HEAD
`1f8cab43`. This addendum is committed separately. The worktree remains
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/e3-dependence`.

### Diagnosis and fix

The review's new P2 is reproduced. A graph with the configured `(A $x)`
population prior `(STV 0 1)`, the rule
`A -> B = CTV((.9,1),(.2,1))`, and a certain observation of `Or(A,B)`
returns `A=(STV 0 .9999)`. Its dependencies include A's population-fold hash
F. Excluding F previously still returned that graph value, although the
ordinary `sk-admits?` rule rejects it. The initial graph exclusion test
preceded the import of the prior's dependencies.

The graph now uses **`sk-admits?` on its completed value**, after joining
the source and population-prior dependencies. This replaces the final
proof/TV-only `sk-fact-matches?` check. A rejected dependency retains the
caller's existing fallback through the same conditional branch. Proof/TV
filtering remains part of the admission test. No new production helper,
compatibility path, public signature change or deleted name is involved.

The new `test_excluded_population_fold_keeps_the_graph_fallback` constructs
the actual base-rate fold key and its hash F, verifies that the unrestricted
graph returns zero and depends on F, verifies ordinary admission rejects
that value with F excluded, and asserts the graph returns the supplied
fallback. A subsequent unrestricted read still returns the original zero
answer. This also covers exclusion after a warm graph answer. The regression
failed against `1f8cab43` with an actual `sk-val` instead of `fallback`,
then passed with the fix. All **14 event-dependence tests pass**.

### Validation and numerical expectations

`capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS**, all six
gates, **363 seconds**, recorded key **9db366f864e5**.

- Strict MeTTa: **161 passed, zero failed**.
- Python: **982 tests**, 60 files / 588 units, sixteen workers;
  **64 expected failures**, one nightly skip; **4,458 query rows, zero aborts**.
- Import scaling, judgment scaling (three query rows, zero aborts), lint
  and ConceptNet passed.

Existing numerical assertions and proof/score expectations are unchanged.
`EXPECTED_FAILURES` diff against `1f8cab43`: **empty (61 -> 61)**. The only
changed expectation is the newly tested excluded read: invalid graph value
`A=0` -> caller's fallback. Unrestricted A remains zero because its prior
assigns no mass to A=true; `P(B=true | A=false)=.2` leaves positive mass
consistent with the Or observation. Moment formulas and D0 oracles are unchanged.

Logs: `scratch/e3_r2_red.log`, `scratch/e3_r2_focused.log`,
`scratch/e3_r2_verify.log`, `scratch/e3_r2_full.log`,
`scratch/e3_r2_canary.log`.

### Required comparisons

The standard runner froze the final production tree as
**1f8cab43-dfde66846**, runtime tree **2136b598f089**, before the implementation
commit. No production change occurred between that snapshot and `6e682473`.
The comparison uses master **c2f342a7** and anchor **b4065459**.

Master full comparison: **PASS**, accuracy **identical in all 22 compared
cases** (23 records including the separate CombiNet reference). The runner
executed **43 runs** and reused **two of 45 results**; all 45 result records
exit zero. Wall time was **1,794 seconds**, including the shared full-size
queue behind a landing. Both StationOps replay belief streams are identical.
The ProbLog fuzzer retains **6 -> 6 flagged KBs**, no newly flagged KB,
zero unsupported KBs and zero crashes. There are no confirmed timing flags.
The reused reliable-conflict candidate timing is marked `load differs`, so
that pair provides no timing-regression conclusion.

Full report:
`/nexus/Dev/OpenCog/bench/results/compare/c2f342a7_vs_1f8cab43-dfde66846_full/report.md`.

Anchor canary: **PASS**, six cases, **138 seconds** wall, 12 runs executed
and six stored results reused. Accuracy differs from the anchor in four
cases (live, stated conflict, reliable conflict and scale), inherited on
master too; the anchor's master-relative gate reports no new blocking
regression. Timing-host attempts could not find the worktree interpreter and
exited 127; the standard runner retried locally and all six candidate cases
exited zero.

Canary report:
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_1f8cab43-dfde66846_canary/report.md`.

### Tokens and scope

The unchanged `scratch/core_count.py` reports **326,324 core** o200k tokens,
**17,685 third party**, **344,009 total** (`scratch/e3_r2_tokens.txt`). This
follow-up adds ten core tokens to `1f8cab43`'s 326,314; against the original
E3 baseline of 326,924 the net remains **-600**, satisfying the <=0 budget.
No symbol was deleted in this follow-up, so there is no additional deleted-name
audit to perform.

Every PeTTa, test and benchmark command used `bench/capped`,
`ulimit -v 16000000`, unset DISPLAY and `/dev/null` stdin. The worktree's
pinned runtime and standard runners were used. Only this worktree and branch
were edited; shared benchmark and validation-cache outputs are produced by
the standard runners. No master, other worktree, push, merge or GitHub write
was performed. All started jobs completed and were reaped. The bounded
supported graph and numerical-enclosure limits documented above remain unchanged.
