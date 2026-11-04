# Master KE R3

Branch: `master-ke-r3`. Worktree:
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/master-ke-r3`.
Base: `6c8e27ad`. No pushes, merges, or source edits outside this worktree.
The worktree Python imported its own `pettachainer/__init__.py` from `/tmp`.
All PeTTa, test and benchmark jobs used `bench/capped`, matching worker slots,
`ulimit -v 16000000`, DISPLAY unset, and stdin `/dev/null`.

## Commits

- `25616ce4 Read refined CTV counts and fold co-occurring graph roots`:
  live RuleTruth parameters, exact block folding, regressions and contract.
- `f0d19026 Read learned-rule fuzz references under the stored-count law`:
  correct the shared independent oracle, its regression and documentation.
- `878af10b Keep refined proof metadata out of numerical graph cache keys`:
  retain a ground indexed numerical key and add a native regression.
- This report is the final documentation-only commit.

Both required trailers are recognized by Git on each code commit. The first
two commits were originally `714d8790` and `9ca9f80c`; correcting their trailer
paragraph formatting changed only their commit metadata. Their Git trees are
identical to `25616ce4` and `f0d19026`. Intermediate benchmark paths retain
those immutable original labels. The final runtime is `878af10b`.

## Diagnosis and design

Refinement left a source catalog role's truth variable unbound. Template
admission required a ground truth, so the graph rejected the rule and the
ordinary route could not recover its antecedent's constituents. A refined CTV
now retains its RuleTruth key and reads both current branches through the
ordinary reader with the caller's exclusions. The branches use the specified
stored-count law: n=k*c/(1-c), Beta(ns+1,n(1-s)+1), reported at its mean.
The truth's proof and dependencies accompany the answer. No instance expansion
is bought by this read. With no samples, refinement preserves the unrefined TV.

The 19-part claim exceeded the 12-atom enumeration cap. Numerical inputs now
fold independent roots only when their complete occurrence signatures match:
the same signed literal under the same And/Or at every path in the goal,
observations and conditional antecedents. A literal goal, separate occurrence,
other connective/polarity, or another producer prevents an unsafe fold.
Repeated literals remain one Boolean event. Products, complemented for Or,
retain exact rational first and second moments. This preserves the original
kernel's strength and conservative variance bound, rather than approximating
the product with a Beta. It does not claim equality of a full posterior
variance integral that the kernel does not compute. Original source reads,
proofs, filters, exclusions, dependencies and watches precede numerical folding.
Discovery admits 24 atoms; enumeration still admits at most 12 folded atoms
and 12 parameters. Raising enumeration's cap was rejected as exponential.

A native regression also exposed nonground numerical memo keys: generic
RuleTruth/proof variables left `term_hash/2` unbound, losing first-argument
indexing. Numerical folding now drops proof-only model/factor fields after
reading the sources and their dependencies. The numerical key contains Boolean
structure, observation TVs and resolved parameters; proof construction still
uses the original model. The regression fails before the cleanup and produces
an integer hash afterward. No public signature or compatibility path changed.

Net core growth: **1,139 o200k_base tokens**, including comments, versus base
6c8e27ad (`scratch/token-diff.log`). This exceeds the approximate +600 estimate.
The added work covers signed/nested occurrences, exact moments, safe admission
and indexed numerical keys. No dead helpers or compatibility scaffolding remain.

## Independent references and moved values

All six saved KE artifacts were read without modification, using their original
declarations (`scratch/ke-acceptance.log`). Refined two-part Unveiling:
**.8056768558951966 / .00023291534128248875**, equal to unrefined, strength
369/458. Refined 19-part Unveiling:
**.5000060005753694 / .001051172863958929**; whole claim:
**.000013908476481344897 / 0**, strength 649/46662192. Neutral 19-part joint:
2^-19. The reviewer's final KE tests recheck these on the final runtime.

The folding tests compare full world enumeration against folding within 1e-12
for signed And/Or, nested formulas, repeats/reordering, separate observations
and incompatible occurrences. Public 19-part queries also match independent
closed forms, refinement on/off. The reviewer adds overlapping blocks, own
sources/producers, sub-block goals and wider Or/negative cases.

Three runtime TV/proof pins move from inversion/completion's centres to graph
reads of stored counts:

| Test | Before strength / confidence | After strength / confidence | Independent reference |
|---|---|---|---|
| MeTTa rule refinement, P alice | .9266167719065028 / .02683127865840225 | .8905767996309657 / .0031242495874902842 | Root Beta(2.46,1.24), branches Beta(5761.504,1441.81), Beta(721.216,6481), report mean 2881/3202. Independent source enumeration matches strength and variance bound. |
| MeTTa antecedent completion, A q | .9308779221070141 / .690902642185726 | .8749963543545393 / .3429267227111237 | Ideal certain samples: root Beta(7,3), branches Beta(6,2), Beta(2,6), strength .875 and bound confidence .3429433360206223. The ordinary compound samples' finite confidence explains the <4e-6 strength difference. |
| Python learned branch counts | .8130081300813008 (strength only) | .7692307692307692 | Uniform axiom plus ten samples gives Beta(10,2), Beta(3,9), symmetric root: posterior 10/13. |

The proof pins now name the graph, RuleTruth revision and population prior.
`scratch/count_references.py` and `.log` record the independent source model;
run the script with `PYTHONPATH=.` through the standard capped wrapper.

The oracle unit pin's negative branch moves from **1/3 to 2/5**: the stated
axiom plus one failure gives Beta(2,3), not Beta(1,2). Its positive branch
remains 1/2. A new five-failure regression is **2/9**, from Beta(2,7).
The original endpoint-confidence assertion remains unchanged and passes.

## Gates and reviewer

Final `scripts/verify.sh`: **PASS**, all six gates, exit 0, 273 seconds;
recorded key **d6c60a0f45e8** (`scratch/verify-cache.log`).

- MeTTa: **163 passed, zero failed**, strict determinism.
- Python: **1,094 tests**, 79 files, 606 units, eight workers, 194.7 seconds;
  24 expected failures and one configured skip.
- Lint, import scaling, judgment scaling and ConceptNet: PASS.
- Query aborts: zero in 4,672 Python query rows; judgment rows also clean.
- Focused folding/dependence/prior tests: **55 passed**.

All six reviewer files reran through the supplied `run_tests.sh` against the
final code (`scratch/reviewer-cache/`, evidence in
`scratch/reviewer-cache-evidence.jsonl`). Width 12, KE 7, refinement on/off 8,
neutral/order 7 and reference 3 tests pass. Three strict subtests in the
five-test learned file remain **class A**, verified on archived master:

- Ordinary forward branches are byte-identical to master: strengths
  .763901549680948 and .16317228805834094, confidences
  .013661780639328696 and .01366178063931342. These no-observation models still
  use the ordinary forward route, outside this round's graph admission change.
- The conjunctive-sample result improves from master .7414630966463501 to
  .6929435051975108 against ideal .6929419348403887. The residual 1.57e-6 is
  the ordinary fold's finite-confidence conjunction weighting; the strict
  1e-10 reference assumes unit sample weights.

No reviewer test was edited. Baseline evidence is
`scratch/reviewer-master-refined.log`. No newly introduced class B reviewer failure.

## Quick fuzzer

Final tree's quick campaign (`scratch/fuzz-quick-cache/summary.md`): seed 1,
budgets 100/500, 21 cases, 61 worker runs, 32.86 seconds, k=800.
**Three BLOCKER:flip flags, all class A**, exactly matching archived master
with the same fuzzer and inputs. The command exits 1 for these existing
uncertain-STV leaf-report-And/Or/Not limitations. Families have zero violations;
all three independent ProbLog cases pass. No class B flag.

The run used this worktree's runtime immediately before the cache commit,
with exactly the committed 878af10b source tree; inputs did not change during
execution. JSON/MeTTa repros are under `scratch/fuzz-quick-cache/repros/`.
All three shrinks are deletion fixed points, zero attempts, not trial limits.
Master evidence:
`/nexus/Dev/OpenCog/bench/results/fresh-design/master-ke-r3-review/master-fuzz/summary.md`.

## Benchmarks

Final quick, master 6c8e27ad versus **878af10b**: **PASS**, accuracy unchanged
in all nine measured cases (ten profile cases), nine runs executed, 10/19
store results reused, 68 seconds. Report:
`/nexus/Dev/OpenCog/bench/results/compare/6c8e27ad_vs_878af10b_quick/report.md`.
No quick metric flag.

Final full, master 6c8e27ad versus **878af10b**: **PASS**. Accuracy changes
in one of 22 measured cases (23 profile cases): the shared-reference fuzz
benchmark improves. All 21 other accuracy cases are identical. No timing,
coverage, unsupported-run or other regression was flagged, and there are no
false timing flags. All selected base/candidate/reference runs exit 0.
It executed 35 runs, reused 10/45 store results, and took 1,382 seconds,
including the shared queue. Report:
`/nexus/Dev/OpenCog/bench/results/compare/6c8e27ad_vs_878af10b_full/report.md`.

| Fuzz metric, same cases/seeds/reference for both arms | Master | R3 |
|---|---|---|
| Flagged KBs | 9 | 8 |
| Flagged queries | 13 | 12 |
| Mean absolute error | .008455793413959455 | .008164426746968437 |
| Answered queries | 364 | 365 |
| Unsupported / crashes / budget regressions | 0 / 0 / 0 | 0 / 0 / 0 |

Seed **22000165**, query index 3, is the removed error. There are **no new
flagged seeds or queries**; the candidate's flagged set is a strict subset
of master's. Every retained error query is **class A**: seed 22000086
(indices 2,3), 22000092 (1,2), 22000098 (3), 22000131 (1), 22000138 (1,4),
22000153 (1), 22000159 (2), and 22000164 (0,4). The per-seed audit is saved
in `scratch/final-full-{base,candidate}-flags.json`; full query-level evidence
is in the benchmark's `runs/{base,candidate}/fuzz/all_n100_s22.fuzz/cases.jsonl`.

Final anchor canary, b4065459 versus **878af10b**: **PASS**. Accuracy changes
in four of six cases versus the old anchor; all seven flagged metric pairs
are **class A**, also present on master, with no blocking class B regression.
It executed 12 attempts, reused 6/12 stored results and took 535 seconds,
including timing-host waits. Report:
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_878af10b_canary/report.md`.

| Anchor flag | Anchor to candidate (harness-normalized seconds) | Class |
|---|---|---|
| ONA conditioning seconds | 4.498 to 5.932 | A |
| ONA identitymatching seconds | 5.696 to 8.291 | A |
| Live error | .09813 to .105 | A |
| Live Brier | .02632 to .03195 | A |
| Live regret | 59.78 to 72.78 | A |
| Conflict stated seconds | 8.957 to 17.05 | A |
| Conflict reliable seconds | 8.769 to 39.2 | A |

Other anchor accuracy movements improve: stated error .3895 to .03181,
reliable error .107 to .05407, scale error .003034 to .002647. The harness
also labels four timings as progress toward the anchor relative to master;
these are local, load-qualified measurements, not dedicated-host speedups.
All six timing-host attempts returned exit 127. All six local candidate
runs exited 0 and supply the selected results; no remote timing evidence
was obtained.

Final comparison runtime tree: `615ae83e3c37`; pinned PeTTa runtime
`eec735bf4d1d3e31`; unchanged ChainerGame supply `3daf989e93` and replay
`d274b45767`, as recorded by the runner.

All comparisons use the standard runner and store. Shared full-size queue and
timing-host waits were respected; no runner, seed, case, threshold, frozen
build or stored result was improvised or altered. No curves: scheduling and
budgets are unchanged.

### Learned-reference correction exposed by the first full run

The first full run against 714d8790 reported **REGRESSIONS (1): fuzz all n100
s22 flagged 5 -> 6**, one changed accuracy case. Every other accuracy case was
identical and no timing regression was flagged. The extra detector flag was
seed **22000165**, E a: old reference 1/7, runtime .22222222221790125.

This was a **B detector flag caused by the stale reference**. The stated axiom
contributes n=2, ns=1; five negative samples yield n=7, ns=1. The specified law
is Beta(2,7), mean **2/9**, which the runtime already returned. The old oracle
used (S+1)/(N+2), treating the axiom as the whole prior. The shared classical
oracle now uses (S+2)/(N+4), with independent regression tests and matching docs.
`compare.sh` runs both arms with that same candidate harness; cases, seeds and
thresholds stay identical.

Original report (preserved):
`/nexus/Dev/OpenCog/bench/results/compare/6c8e27ad_vs_714d8790_full/report.md`.
Original case: `scratch/full-seed22000165-original.json`. Its final-code replay
with the corrected reference (`scratch/replay-22000165-count-law.log`) matches
ProbLog on all five queries at budgets 100/2000 and has **no flags**. E is
.22222222221790125 versus 2/9; F is .645336333333363 versus .6453363333333333.
Intermediate queued comparisons for the superseded 9ca9f80c tree were stopped
and reaped before replacing them with the cache-corrected build.

## Checkpoints and limits

Patches and one-line descriptions are in
`/nexus/Dev/OpenCog/bench/results/fresh-design/master-ke-r3-checkpoints/`:
cp1 refined truth, cp2 exact folding, cp3 green gates, cp4 oracle correction,
cp5 its green gates, cp6 cache-key correction, cp7 final green gates. Coordinator
notes were checked before each transition and throughout benchmark waits; none
was present. The temporary endpoint variable collision was fixed before the
green checkpoints; its original assertion was retained.

The 24-atom/statement discovery bound still applies. Only identical,
same-connective, same-polarity occurrence blocks fold; more general Boolean
equivalences retain the ordinary route. Variance remains the documented
conservative polynomial bound. Ordinary forward count semantics and the three
uncertain-STV flip limitations are unchanged class A work. Core growth exceeds
the approximate token estimate, as disclosed above. No push or merge occurred.
