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
