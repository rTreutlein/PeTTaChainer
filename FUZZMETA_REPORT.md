# Differential and metamorphic builder fuzzer

Branch `fuzzmeta`; worktree
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/fuzzmeta`.
Core snapshot: master `9884ae6de607e726d16221110284fdcb5430d72e`.
Only tests, tooling, documentation and retained evidence change. No core fixes,
expected-value changes, pushes, merges, main-core edits or live routedel2
worktree execution.

## Design and coverage

Extended the existing `tests/fuzz/{kb,generator,run,shrink}.py`, its existing
worker, and `scripts/fuzz_vs_problog.py`. There is one entry point and transport;
the ProbLog feature mode remains. `--quick` adds 19 event shapes and three
ProbLog cases; `--long` runs twenty consecutive seeds, more CTV shapes and
fifty ProbLog cases. `--chainer` selects an independently repointed interpreter
and verifies its imported package location. `CHAINER_PYTHON` remains supported.
The worker source comes from the fuzzer, never from the target's tests directory.

Shapes cover atomic stored facts; uncertain CTV branches; STV and FTV producer
rules; one, two, three, seven and eight independent origins feeding two
consequents; nested And/Or/Not reports over atoms including otherwise unused
leaves; neutral descendants; explicit ground base rates; ground and existential
identity/judgment conjunctions with hard contradicting Not; and Member /
Inheritance chains with a transitivity schema and inactive/active licensed-link
obligations. Seed variation changes rates, connective choices and origin counts.

Reference strength uses independent Boolean-world enumeration with one bit per
atom and shared source parameters, at their analytic means. Stored counts are
Beta(ns+1,n(1-s)+1); propagated views are Beta(ns,n(1-s)) or Bernoulli(s) at c=0;
c=1 is a point. Reports are Pearl likelihoods at their predictive probabilities.
Certain-positive producer families activate the OR of their antecedents plus
one independent fallback per consequent, respecting an explicit base. These
are the documented event-node roles, not ProbLog noisy-OR substituted for an
unspecified multi-rule law.

For constant normalization, variance is an exact polynomial moment (two Beta
nodes). Posterior variance with reports is a labeled 12/24-node numerical
integral. Its discrepancy is retained; convergence is not called a certificate.
An independent analytic variance lower bound, E[(N-sZ)^2]/(E[Z]*max likelihood),
uses only degree-two moments and certifies overconfidence. Numerical-only
variance concerns remain FOLLOW-UPs. Output confidence is decoded to variance;
wrong/lost answers, certified overconfidence, impossible support and invariant
failures are BLOCKERs. The strength tolerance is .001, and the error must fit
two claimed standard deviations within that tolerance.

Metamorphic obligations cover neutral extension; relevant-observation flips in
the direction established by a normalized control; known-false constraints;
renaming; installation/connective reordering; repeated source identities and
query atoms; inactive producers; class-link obligations; Fréchet bounds through
origin scaling; and larger-budget error/answer preservation. Quick applies syntactic mutations
to origin families through three sources; long additionally mutates the
seven/eight-origin families. Catalog scaling
uses deterministic Prolog inference counts, retaining CPU seconds as diagnostics.
Its two supported catalog signatures are probed at runtime, allowing the same
fuzzer to test both required source revisions.

Shrinks rebuild references and paired mutations, retain the same query and
severity/invariant (including a numerical variant's identity), try chunk and
single deletions, prune unused modeled roots, and halve cost-probe sizes. JSON
replays and paired standalone MeTTa files retain expected values and the broken
invariant. A trial limit is reported honestly, not called global minimality.

## Validation and findings

The fuzzer's eleven new self-tests and eleven existing generator/transport tests
pass. A standalone emitted MeTTa repro ran through the pinned `.venv/bin/petta`
and reproduced O = .8912891216043766. The first full verify passed all six gates
but did not cache its result because tooling was still being refined; the second
run passes every gate in 313 seconds and records PASS under verify-cache key
`8c410a6c8e43`. It includes 163 MeTTa files, 1,070 Python tests (24 expected
failures, one skip), 4,607 query rows with zero aborts, import/judgment scaling
and ConceptNet. No test value was moved.

Benchmark commands used the standard `compare.sh` and this worktree's runtime:

- Quick: **PASS; accuracy changed in 0 cases**, 10/10 stored results reused.
  `/nexus/Dev/OpenCog/bench/results/compare/9884ae6d_vs_9884ae6d-d1c6b1205_quick/report.md`.
- Full: **PASS; accuracy changed in 0 cases**, 23 cases, 22 stored results reused,
  one standard ProbLog fuzz run executed (exit 0).
  `/nexus/Dev/OpenCog/bench/results/compare/9884ae6d_vs_9884ae6d-d2b8d4413_full/report.md`
  (repeated after the final tooling changes; one fuzz run, exit 0, 61.08 seconds).
- Canary: **PASS; accuracy changed in 4 cases**, 12 fresh timing runs, every
  exit 0, using the documented `BENCH_TIMING_HOST= ... --canary --retime`.
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_9884ae6d-d2eb44f4e_canary-retime-20261104T103400/report.md`.
  The first remote attempt could not find this worktree's interpreter (exit 127);
  its printed PASS is not validation. A local forced retime supersedes it.
  The four anchor differences are pre-existing on master: live error
  .09813 -> .105; stated conflict .3895 -> .03181; reliable conflict
  .107 -> .05407; scale-m .003034 -> .002647. The candidate/master core is
  unchanged, and its comparison has no changed accuracy.

Complete durable campaign evidence is under
[experiments/fuzzmeta](experiments/fuzzmeta/README.md).

No existing test expectation was changed. `--quick` is intentionally excluded
from `verify.sh`: it discovers open defects and the measured run exceeds two
minutes. All PeTTa, test and benchmark processes used the required capped pool,
address-space limit and unset DISPLAY, with top-level stdin from `/dev/null`.


## Final campaigns

Both used seed 1, eight capped slots, budgets 100/500, k=800 and tolerance .001.
Their input digests are identical
`8e7d97cd23a4dca9fe1e88938cadb17110e141a2c3015f2835c902d06e8093ef`;
`inputs_changed` is false. Wall times below start after admission to the shared
pool; queue waiting is outside those measurements.

| target core | seconds | event cases | worker runs | violations | deletion fixed points | ProbLog failures |
|---|---:|---:|---:|---:|---:|---:|
| master `9884ae6d` | 71.08 | 19 | 224 | 47 | 47/47 | 0/3 |
| routedel2 `3a990295` | 162.84 | 19 | 187 | 37 | 37/37 | 0/3 |

The master worker records tooling commit `b694e193`; its `pettachainer` tree is
identical to master (`230a9ea20834f5a27a9602f7778ebe131c942341`). The detached
routedel2 target records `3a990295e5eace9c735911d501440b4a15fc09c9`, with tree
`4443a1c5fc000115bd9df5b1e8a8955e5cedddee`, and has no tracked modifications.
All final repros reached a fixed point within the 24-trial quick limit. Counts
are per query/invariant, not independent defects. Both commands exit 1 because
they found BLOCKERs; the fuzzer itself completed successfully.

An exploratory pilot repeated nested compound queries at seven/eight origins;
that older campaign was stopped at ten minutes. Quick now checks exact moments,
Fréchet bounds and budgets at those widths, and covers syntactic transformations
through three origins. Long retains the expensive wider transformations. The
final measurements above include all reductions and the ProbLog subset.

## Rediscovery on routedel2 3a990295

All seven historical KE blocker classes were rediscovered. Original cases and
all minimal reproductions are in
[routedel2/summary.md](experiments/fuzzmeta/routedel2/summary.md).

| review class | live evidence |
|---|---|
| Compound report hidden behind a supposed leaf | Flipping And/Or/Not reports leaves C at .4 instead of changing it in the control's direction. |
| Neutral descendant changes a count law | O moves .8912891216043766 -> .9999999999997257; C moves .9347284013035543 -> .9877900084672666. The added report has strength .5. |
| False identity still gets support | Adding hard Not(identity) leaves ground and existential answers at .0562265722615577 instead of zero/absence. |
| Single producer loses the ground consequent base | A=.9761764813930421 instead of .9598430255509199; a certainly inactive extra producer changes it to the reference. C likewise changes .9761617868557364 -> .9681894529889391. |
| Quadratic uncharged producer normalization | For 64/128/256/512 sources: 11,065 / 38,457 / 142,393 / 546,873 Prolog inferences per template call. CPU times are diagnostic, not the gate. |
| Eight origins have inconsistent joints | A=B=.7885474013232553, but A∧B=.9989261166352451; references are .9992848612556800 and .9989272918835200. |
| A derived class-link obligation hides a stored classification | Pilot/person strengths 1 disappear when the licensed-link rule is added, with or without its Licensed fact. |

The moment reference additionally finds certified variance underclaims in origin
families and in the neutral extension. These are retained as separate
query/invariant violations, not counted as additional historical classes.

## Master findings, left unfixed

[master/summary.md](experiments/fuzzmeta/master/summary.md) lists every result:

- Compound report flips leave C=.4 unchanged (three connective shapes).
- Neutral extension changes O .8912891216043766 -> .9762111390395556 and C
  .9347284013035544 -> .9878048780487805, with certified confidence concerns.
- Explicit ground-base producer cases disagree with the finite-world reference;
  an inactive producer changes A .9797376479439993 -> .9771459198487928 and C
  .9744685694201395 -> .972609500798931. STV and FTV variants both flag.
- Origin families have wrong strengths, error beyond claimed uncertainty and
  inconsistent marginal/joint bounds. Eight-origin values match the residual
  failure above. Fréchet violations occur at two, three, seven and eight origins.
- Repeating identical source identities/query atoms changes or loses answers
  in smaller origin families and compound CTV queries (seven violations).
- A hard false identity constraint still leaves positive ground/existential
  support .0562265722615577.
- No class-rule preservation failure, quadratic catalog-work failure,
  rename/reorder failure or budget regression appeared in this bounded master
  campaign. The ProbLog subset had no disagreements.

All 47 master violations and 37 routedel2 violations have committed JSON and
MeTTa repros. No reported core defect was fixed in this branch.

## Commits and hand-back

- `b694e193` — shared event model, independent reference, metamorphic checks,
  target selection, shrinking, self-tests and workflow documentation.
- The following evidence/report commit retains both complete campaigns and this
  hand-back report; `git log --oneline master..fuzzmeta` is the authoritative list.

## Limits

Long mode was implemented but not run. This is a bounded shape lattice, not
exhaustive coverage of arbitrary judgments, cyclic models or arbitrary uncertain
multi-producer combination laws. The count/view source role is declared in the
reference; unsupported normalization shapes use invariants only. Numerical
variance integration is not a certified exact posterior integral, and can fall
back to the analytic lower bound above 150,000 parameter cells. Shrink fixed
points are relative to supported reductions, not globally smallest expressions.
The cost probe measures catalog normalization, not complete-query wall time.
