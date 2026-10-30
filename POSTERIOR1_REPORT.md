# POSTERIOR1: atomic posterior checkpoint, not ready to land

Worktree `posterior1`, branch `posterior1`, base `2b6c42a8`. The earlier checkpoint is
`dcf69289`. This report is written by the implementing agent. The step-1 acceptance
criteria are **not yet met**: numerical fixture audits, final gates, and the required
net deletion remain outstanding. Do not merge this checkpoint as completed step 1.

## Design as built

Atomic reports now enter the source-owned event graph without a compound seed.
Live conclusion/premise indexes discover the component; input snapshots are keyed
by input epoch and overlay frame. Skeleton row creation does not change that input
snapshot. Sources with confidence zero, materialized copies, forward copies and
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
monomials are combined. Gauss-Jacobi rules are cached within the existing evaluator
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
* `EXPECTED_FAILURES` shrinks from 61 to 44 by removing the 17 validated P16
  entries. No expected failure was added. Additional unexpected successes in the
  broad diagnostic run require a fresh stable-tree audit before ledger removal.
* No old numerical fixture pin was changed. The changed proof/TV fixtures remain
  failing until independently derived and audited; their current failures are not
  treated as evidence that their new values are acceptable.

The most recent focused stable checks are `scratch/posterior1-final-focused.log`
(24 tests, PASS: atomic/dependence/bridge lifecycle) and
`scratch/posterior1-bounded-focused.log` (22 tests, PASS: atomic/dependence after
adding the original-atom cap to separable fallback). The isolated exact #150 request
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

Replacing the separable message integrator with the generic world-node integrator
passed 43 focused numerical/dependence/posterior tests, but changed bridge-judgment
variance from its .8177 confidence pin to the floor. A complement-oriented variance
experiment passed all 21 direct numerical tests but made the bridge sweep exceed
its 100 s bound. Both speculative rewrites were reverted. The safeguarded fallback
integrator remains; no claim of one numerical engine or completed legacy deletion
is made. A follow-up must carry the fallback's compressed parameter model and thin
likelihood treatment through the shared integrator, with independent variance and
performance evidence, before deleting it.

Exact o200k count (`scratch/posterior1_counts.py`, same scope as supplied counter):

| tree | core | formulas/lowering | total | nonblank noncomment lines |
|---|---:|---:|---:|---:|
| 2b6c42a8 | 318919 | 17685 | 336604 | 16635 |
| current checkpoint | 320655 | 17685 | 338340 | 16714 |

Net **+1736 tokens, +79 lines**: this fails both required reduction gates. Line
count excludes blank and full-line comments; it is not a full language parser.
No base-tree named function was deleted. Internal signatures changed for
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

* Fresh full comparison: running; `scratch/posterior1-full.log`. The first attempt
  raced a simultaneous canary freeze and rejected the incomplete shared frozen
  build; it was rerun through the unchanged standard runner after canary completed.
* Anchor canary: runner PASS, accuracy changed in four cases; attribution and
  strict RSS audit pending. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_dcf69289-db4d81904_canary/report.md`.
* Final capped slots-16 verify: not yet run. This report is committed before it.
* Earlier broad Python sweep: 1000 tests, 127 failures, 3 errors, 42 unexpected
  successes, 5 expected failures, 1 skip; diagnostic only, included intermediate
  edits and is not a final-tree result (`scratch/posterior1-python-second.log`).
* Earlier MeTTa sweeps contain unaudited old pins and intermediate regressions;
  none is claimed green. Nested conditional-consequent projection remained passing.

Outstanding: complete the numerical/route deletion without breaking FTV roles;
audit every moved fixture against its model/oracle; rerun all D0 cases on one stable
tree and shrink only confirmed ledger entries; pass verify, full accuracy/RSS and
canary, and retime every final flagged case on the timing host. The checkpoint
provides implemented and focused-tested admission/completion work, not completed
step-1 acceptance.
