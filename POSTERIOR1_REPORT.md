# POSTERIOR1: atomic posterior checkpoint, not ready to land

Worktree `posterior1`, branch `posterior1`, base `2b6c42a8`. Earlier checkpoints are
`dcf69289` and `765bcda2`. This report is written by the implementing agent. The step-1 acceptance
criteria are **not yet met**: numerical fixture audits, final gates, and the required
net deletion remain outstanding. Do not merge this checkpoint as completed step 1.

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
A single broad Beta uses independently refined endpoint panels. The integrator
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
* No old numerical fixture pin was changed. The changed proof/TV fixtures remain
  failing until independently derived and audited; their current failures are not
  treated as evidence that their new values are acceptable.

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
`separable_refined/9`, `separable_variance/8`, `agree_variance/2`, `second_tensor/6`,
`sized_rule/3`, `tensor_point/4`, `second_term/6`, `point_ws/3`. Their exact names
have zero references under production, tests, third_party and docs. Endpoint
panels now belong to `event_node.pl`; this is a shared numerical implementation,
not retention of an old callable compatibility entrypoint.

Exact o200k count (`scratch/posterior1_counts.py`, same scope as supplied counter):

| tree | core | formulas/lowering | total | nonblank noncomment lines |
|---|---:|---:|---:|---:|
| 2b6c42a8 | 318919 | 17685 | 336604 | 16635 |
| current checkpoint | 320266 | 17685 | 337951 | 16682 |

Net **+1347 tokens, +47 lines**: this fails both required reduction gates. Line
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
  The final producer/variance changes need fresh full/canary checks.
* Anchor canary: runner PASS, accuracy changed in four cases; attribution and
  strict RSS audit pending. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_dcf69289-db4d81904_canary/report.md`.
* Capped slots-16 verify at `765bcda2`: FAIL, cache key `bb9e56d91319`,
  260 s. Lint/import scaling/judgment scaling/ConceptNet pass; MeTTa 143/162 pass;
  Python 1000 tests: 88 failures, 1 error, 23 unexpected successes, 24 expected
  failures, 1 skip, 4486 query rows and no aborts. The ledger's 23 successes were
  subsequently removed. Final shared-integrator verify is pending; this updated
  report is committed before it.
* Earlier broad Python sweep: 1000 tests, 127 failures, 3 errors, 42 unexpected
  successes, 5 expected failures, 1 skip; diagnostic only, included intermediate
  edits and is not a final-tree result (`scratch/posterior1-python-second.log`).
* Earlier MeTTa sweeps contain unaudited old pins and intermediate regressions;
  none is claimed green. Nested conditional-consequent projection remained passing.

Outstanding: complete route deletion without breaking FTV roles;
audit every moved fixture against its model/oracle; rerun all D0 cases on one stable
tree and shrink only confirmed ledger entries; pass verify, full accuracy/RSS and
canary, and retime every final flagged case on the timing host. The checkpoint
provides implemented and focused-tested admission/completion work, not completed
step-1 acceptance.
