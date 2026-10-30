# POSTERIOR1: atomic posterior checkpoint, not ready to land

Worktree `posterior1`, branch `posterior1`, base `2b6c42a8`. Earlier checkpoints are
`dcf69289`, `765bcda2`, `29e74cf3` and `50213418`. This report is written by the implementing agent. The step-1 acceptance
criteria are **not yet met**: numerical fixture audits, final gates, and the required
net deletion remain outstanding. Do not merge this checkpoint as completed step 1.


## Finishing round: correctness checkpoint

The requested simplification and RSS work have not started yet. This checkpoint
finishes the prerequisite fixture/oracle audit and fixes concrete prior and
variance regressions before deleting routes.

* MeTTa: **162/162 pass**, `scratch/posterior1-finish-metta-12.log`.
* The preceding slots-16 verify has Python **1003/1003 passing** (24 expected
  failures, one skip), 4527 query rows and no aborts; lint, both scaling gates
  and ConceptNet pass. Its remaining two MeTTa failures have subsequently been
  fixed. Log: `scratch/posterior1-finish-verify-3.log`, 239 seconds.
* The 47 focused numerical/atomic/soft-report/fixture-audit checks pass
  (`scratch/posterior1-finish-reduction-focused.log`). An additional closed-form
  thin-boundary regression passes (`scratch/posterior1-finish-weak-boundary.log`).
* A fresh full verify follows this committed report. It is an intermediate
  correctness gate; final verification and comparisons still follow deletion.

Graph cavity priors now retain the compiler's population pattern, including
ForAll cohort parameters and scalar atoms. Positive-only roots without a user
prior decline admission. Uninformative compounds already settled by root facts
do not invent sibling answers; zero-weight contradictory factors remain.
Consistent hard source facts retain their original proof and exact confidence.
Roots without likelihoods retain their stored counts even when unrelated root
sources occur in the discovered component.

The variance encoder now inverts the public clipped-mean decoder. For example,
the source-gate fixture keeps mean .9999997023811048 and variance approximately
1.17e-13; encoding that variance changes confidence .999686126673656 to
.9999065647289087. Deterministic fallback siblings are integrated exactly before
the atom cap, restoring the opposed-likelihood fixture's original uniform
variance. Tensor exhaustion can integrate out weak nuisance axes with a certified
conditional-variance remainder, accepted only below 1e-6 of the retained variance.
The thin-boundary test derives the remaining integral as
`-log(p)/(1-p)` and checks its variance independently. Its MeTTa confidence moves
.9906359623604194 to .990635962167288 after adding that certified remainder.

Every moved ground-event MeTTa reference, including its old/new term, complete
authored sources, rates, K and independent oracle answer, is recorded in
`tests/fixtures/posterior1_oracle_audit.json`. `test_posterior_fixture_audit.py`
rechecks those records without consulting the runtime graph. Python soft-report,
completion, prior and Assuming tests calculate their references directly from
`tv_calibration_oracles.py` or its independent source adapter. Finite reports use
`m=(n*s+1)/(n+2)` and Pearl odds; distinct reports remain distinct factors.
No expected failure was added or removed in this finishing checkpoint.

Two predicted-joint references also improve against independent 33/65-node
quadrature of the decided Jeffrey model. The .9 prediction's confidence moves
.23668185541661188 to .2366826641505106 (converged oracle .23668266307594024);
the .5 prediction moves .03740952260211322 to .03740954158120962 (oracle
.037409541348889054). Sources and integral are in
`scratch/posterior1_jeffrey_oracle.py` and
`scratch/posterior1_jeffrey_half_oracle.py`. Exact proof/statement patterns remain;
last-bit numerical comparisons use 1e-12. No substantive tolerance was widened.
The raw-ingestion recipe test now publishes the complete compiled source,
so its graph and directly compiled control represent the same model.

Pre-deletion count: **321460 core + 17685 formulas = 339145 tokens**, versus
336604 at 2b6c42a8; **16731 executable-count lines**, versus 16635. Net **+2541
tokens, +96 lines**, still failing the simplification gate. Counter output:
`scratch/posterior1-finish-predelete-counts.log`. No performance result below is
claimed current for this checkpoint. Route removal, negative footprint, paired
RSS retimes and final comparisons remain required.

## Design as built

Atomic reports now enter the source-owned event graph without a compound seed.
Live conclusion/premise indexes discover the component; input snapshots are keyed
by input epoch and overlay frame. Skeleton row creation does not change that input
snapshot. An input epoch change retires older snapshots for that KB/frame, rather
than accumulating them across a long forward export. Producer discovery collects
ids/names before fetching premise payloads for an admitted source. Sources with confidence zero, materialized copies, forward copies and
frozen summaries never become new likelihoods. All visited keys are watched for
late observations, including descendants not needed as numerical parameters.

Public root reads and forward exports select the event posterior before their
ordinary answer fallback. Internal statistical/frequency readers retain their
ordinary values: intercepting every internal merge polluted those roles and
regressed scale performance. Consequently the ordinary evaluation can still do
work before an answer is exported; the brief's deletion of redundant inference
routes is not finished.

The native internal read now distinguishes `no-event-model` from
`(event-posterior sk-none)`: inconsistent admitted evidence must not fall back to a
confident stored source. The internal native's old arity was removed; all callers
and tests use its new tagged result. No documented public API was removed.

A supported template is one explicit CTV source per head, with ground Boolean
antecedents. Its complete compiler TV dataflow reconstructs And/Or/Not parents;
settling rows cannot be mistaken for complete antecedents. Cycles, multiple
producers, STV-derived/contextual likelihoods, no_inverse, instance-prior templates,
compound consequents and frozen summaries retain the ordinary fallback. Discovery
is capped at 24 statements, models at 12 atoms/parameters. Evidence-free predictions
continue through the ordinary evaluator. A root source with no likelihoods keeps
its original stored counts.

Point parameters are folded into world coefficients and identical remaining
monomials are combined. Separable fallback messages retain their compressed
product-moment parameter model, but now compile it into the shared event-node
integrator. The separate variance/tensor/refinement implementation was deleted.
A single broad Beta uses independently refined endpoint panels. A fixed
parameter vector has exact zero variance without evaluating a cancelling second
moment; the strengthened fractional/endpoint report test checks confidence .9999. The integrator
handles forced goals exactly and integrates each goal's smaller event/complement
to avoid cancellation at endpoints. A new closed-form tiny-complement regression
checks a positive variance around 3.7e-17 on both sides of the event. Gauss-Jacobi rules are cached within the existing evaluator
workspace and cleared at reset. A proposed second numerical path for fixed-branch
trees was removed after a quick comparison showed that the answer boundary and
quadrature cache were sufficient.

For #150 a certain positive authored And keeps its original source and materializes
its conjunct views with `joint-source`, mapping each view back to the same original
evidence entry. It creates no joint node. The exact public request, declarations,
30-atom source and query are in `tests/fixtures/issue150.json`. Finite-confidence
Ands retain their node. The fallback's exponential sibling-settlement and joint
world enumeration now stop at 12 atoms; separable over-cap messages return a
variance bound, retaining their analytic independent mean.

## Semantic evidence

`tests/test_atomic_posterior.py` checks every P16 setting against the independent
D0 oracle, MAIN/Assuming parity, confidence-zero omission, Boolean antecedent
completions with fixed and uncertain branches, fractional-certain and finite
endpoint Pearl reports, impossible cold/warm evidence, exact constant goals,
stored-count preservation and unsupported-shape fallback.

* Prior .3 and confidence-one report .8 give `12/19`, rather than .8.
* Prior .5 and endpoint report `(STV 1 .5)` give `801/802`, rather than 1.
* Boolean completion models have independent roots (.4,.9), (.3,.9), CTV
  branches (.9,c), (.1,c), and child report (.8,.9), for c=1 and .9. Means match
  the oracle to 1e-12; variance ratios are between .5 and 2.
* `EXPECTED_FAILURES` shrinks from 61 to 21: the 17 validated P16 entries plus
  23 further confirmed unexpected successes from the stable `765bcda2` verify run.
  No expected failure was added. Removed keys are recorded in
  `scratch/posterior1-d0-ledger-removed.json` (the later 23). Fresh verification of
  the shared integrator and reduced ledger remains pending below.
* Two lifecycle fixtures now compare their original TV references within 1e-12,
  rather than requiring identical last floating bits. The references are unchanged:
  nested projection (.9331614438710613, .0846757387459353), source gate wrapped
  (.8655786350145539, .03980772466060817), and unwrapped
  (.8657957244652751, .04001674008863015). Observed confidence differences were
  2-4e-17. Proof patterns, evidence, borrowing, withdrawal and materialization
  checks remain in place. Both full lifecycle fixtures pass. No substantive
  changed mean/variance fixture was repinned or relaxed. Those failures remain
  unaudited and are not treated as acceptable merely because the new engine
  produced them.

The shared integrator passes all **47** direct numerical, atomic, dependence and
bridge lifecycle checks (`scratch/posterior1-shared-final-focused.log`). After
changing producer payload lookup, **23** atomic/dependence tests pass
(`scratch/posterior1-compact-producers.log`). The uncertain 30-atom And returns
(STV .5000033527387862 0) in 1.50 s, matching its analytic independent mean and
claiming the cap bound (`scratch/posterior1-wide-uncertain.log`). The isolated exact #150 request
passes in 1.09 s with one evidence entry (`scratch/posterior1-issue150-6.log`).
Fresh library compilation in earlier iterations took longer than 10 s; the 1.09 s
result uses the repository's normal compiled-library cache.

## Early paired performance checkpoint

Before legacy deletion, `scratch/posterior1-answer-boundary-quick.log` passed all
quick comparisons. Report:
`/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_dcf69289-d5b287e2b_quick/report.md`.
Scale time 40.6 -> 40.3 s and peak RSS 914 -> 907 MB; other suite totals remained
near baseline. Only SupplyNet stage 1 accuracy changed: error .01379 -> .009574,
Brier .04316 -> .04020. That accuracy movement still needs explicit oracle attribution.

Its stage-1 timing exceeded 10% individually. A paired timing-host rerun used the
standard quick profile because the prescribed canary profile contains no stage-1
case (both attempted canary selections were rejected by the runner). Report:
`/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_dcf69289-d1277eb3e_quick-stage_1_b25_s2-retime-20261030T102826/report.md`.
Measured time 1.440 -> 1.576 s (+9.4%), RSS 150.5 -> 162.3 MB (+7.8%). Thus the
10% early checkpoint passes; the stricter final +5% RSS condition is not established.
The no-tree quick run also passed (`scratch/posterior1-no-tree-quick.log`).

## Deletion experiment and remaining blocker

An initial direct substitution of the world-node integrator changed bridge
variance and exceeded a 100 s bound. It was reverted. The accepted replacement
preserves the fallback's compressed parameter model, uses the shared integrator,
and passes bridge lifecycle checks. This removes the second quadrature engine,
but not the compiler/evaluator's redundant inference-route generation: internal
frequency readers still require the ordinary machinery. That route deletion and
the required net reduction remain unfinished.

Deleted base-tree functions: `graded_points/2`, `second_moment/5`, `first_rule/2`,
`separable_refined/9`, `separable_variance/7`, `agree_variance/2`, `second_tensor/6`,
`sized_rule/3`, `tensor_point/4`, `second_term/6`, `point_ws/3`. Their exact names
have zero references under production, tests, third_party and docs. Endpoint
panels now belong to `event_node.pl`; this is a shared numerical implementation,
not retention of an old callable compatibility entrypoint.

Exact o200k count (`scratch/posterior1_counts.py`, same scope as supplied counter):

| tree | core | formulas/lowering | total | nonblank noncomment lines |
|---|---:|---:|---:|---:|
| 2b6c42a8 | 318919 | 17685 | 336604 | 16635 |
| current checkpoint | 320298 | 17685 | 337983 | 16684 |

Net **+1379 tokens, +49 lines**: this fails both required reduction gates. Line
count excludes blank and full-line comments; it is not a full language parser.
The deleted functions are listed above. Internal signatures changed for
`event-network-read`, `sk-forward-store!`, `sk-node-apply`, `separable` and
`separable_moments`; obsolete signatures have no callers. There are no profiling
hooks in production. Removing functions introduced and then abandoned during this
work is not counted as a base-tree deletion.

## Gate status

All PeTTa, test and benchmark executions used `/nexus/Dev/OpenCog/bench/capped`,
`ulimit -v 16000000`, unset DISPLAY, and /dev/null stdin. Only this worktree's
source was changed; no push, merge or GitHub write occurred. Read-only issue #150
was retrieved with gh. Benchmark/verification runners own their normal shared
result and frozen-build artifacts.

* Pre-refactor full comparison PASS (`scratch/posterior1-full.log`):
  `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_dcf69289-db4d81904_full/report.md`.
  Fuzzer flagged KBs 6 -> 5, no newly flagged KB; seed 22000140 is no longer flagged.
  This is independent oracle evidence of an improvement. Scale time +4%, global
  peak RSS 1358 -> 1359 MB. Learned/mined RSS 606.2 -> 786.6 MB required a fix.
  The first attempt raced a simultaneous canary freeze; the standard rerun passed.
* After epoch retirement and shared numerical conversion, a paired timing-host
  learned/mined retime passes with unchanged accuracy, 62.81 -> 62.89 s and
  607.7 -> 608.1 MB. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_765bcda2-dabab1a49_full-untimed_learned_mined-retime-20261030T111015/report.md`.
  A later full comparison at `29e74cf3` also passes:
  `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_29e74cf3_full/report.md`.
  Fuzzer 6 -> 5 flagged KBs, no new flag; global peak 1358 -> 1359 MB.
  Learned/mined RSS 606.7 -> 604.4 MB. Per-case RSS still exceeds +5% for
  stage 1 b100 s3 and CombiNet. Quiet paired retimes after the fixed-parameter
  change preserve accuracy and time but confirm those memory deltas:
  stage 1 160.7 -> 172 MB; CombiNet 135.8 -> 147 MB. Reports:
  `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_29e74cf3-de65995f5_full-stage_1_b100_s3-retime-20261030T114920/report.md`,
  `/nexus/Dev/OpenCog/bench/results/compare/c873c6c3_vs_29e74cf3-de65995f5_full-combinet_n2_s1-retime-20261030T114752/report.md`.
  These are full-profile cases, absent from the canary profile.
* Anchor canary at `29e74cf3`: runner PASS, four accuracy differences against
  the older anchor; candidate also checked against master. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_29e74cf3_canary/report.md`.
* Capped slots-16 verify at `765bcda2`: FAIL, cache key `bb9e56d91319`,
  260 s. Lint/import scaling/judgment scaling/ConceptNet pass; MeTTa 143/162 pass;
  Python 1000 tests: 88 failures, 1 error, 23 unexpected successes, 24 expected
  failures, 1 skip, 4486 query rows and no aborts. The ledger's 23 successes were
  subsequently removed.
* Shared-integrator verify at `29e74cf3`: FAIL, 285 s. D0: 520 checks with
  21 expected failures and no new ordinary failures; P16 18/18. MeTTa 139 passed,
  23 failed; Python 1002 tests, 93 failures, 1 error, 24 expected failures and
  1 skip, no unexpected successes, 4487 query rows and zero aborts. The cache
  record was rejected because a report typo was edited during the run. This
  checkout's verify-cache.py hashes documentation, contrary to the newer runner
  behavior described in the brief. No source or tests changed during that run.
* After the lifecycle FP assertions were made precise at 1e-12, MeTTa is
  141 passed, 21 failed; both projection/withdrawal and source-gate fixtures pass
  (`scratch/posterior1-projection-lifecycle-metta.log`). The final fixed-parameter
  change also passes 23 atomic/dependence checks
  (`scratch/posterior1-point-variance-focused.log`).
* This updated report is committed before the final unchanged-tree gate repeat.
  Its completed outcomes and exact result paths will be written to
  [the final gate status](scratch/POSTERIOR1_GATE_STATUS.md). That ignored artifact
  can record results without changing the verified tree.
* Earlier broad Python sweep: 1000 tests, 127 failures, 3 errors, 42 unexpected
  successes, 5 expected failures, 1 skip; diagnostic only, included intermediate
  edits and is not a final-tree result (`scratch/posterior1-python-second.log`).
* Earlier MeTTa sweeps contain unaudited old pins and intermediate regressions;
  none is claimed green. The latest projection lifecycle checks pass as described above.

Outstanding: complete route deletion without breaking FTV roles;
audit every moved fixture against its model/oracle; rerun all D0 cases on one stable
tree and shrink only confirmed ledger entries; pass verify, the strict per-case RSS gate and the final comparisons. The
identified RSS cases have been retimed and remain above +5%. The checkpoint
provides implemented and focused-tested admission/completion work, not completed
step-1 acceptance.
