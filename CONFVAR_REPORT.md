# CONFVAR report

Round 1 below is a historical stop decision. The **Round 2** section at the end
records the implemented closed-form replacement and its acceptance evidence.

## Round 1: stop after measurement

The requested diagonal first-order variance plus broad-parameter widening does
not pass the conservative-confidence requirement. **Stop at brief step 2.**
Production integration, strengths, confidence conversion, and the event-node
contract are unchanged. No fallback or second production path was added.

## Commits and scope

- Branch: `confvar`.
- Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/confvar`.
- Base: master `23d62195dc4be48676e3d5b35beef6a52e39bfaf`.
- `git log --oneline master..` before this report commit:
  `81d8f5e2 Measure posterior first-order variance before confidence replacement`.
  This commits the numbers, raw captured models, reproducible measurement
  tools, and methodology before any proposed production replacement.
- A separate report commit follows it. Neither commit is pushed or merged.

The pinned venv already imported this worktree and its `petta` shebang pointed
here. Only this worktree was edited. All numerical/test processes used
`bench/capped`; the standard benchmark runner acquires its own admission slots.
DISPLAY was unset, virtual memory limited to 16,000,000 KiB, and test/benchmark
stdin was `/dev/null`. The benchmark capture's temporary local-venv .pth was
removed. No routes, compiler files, main checkout, other worktrees, or shared
venv were changed.

## Measurement

The candidate uses the **exact posterior marginal parameter means and
variances** under prior(theta) Z(theta), then the requested sum of squared
N/Z derivatives times those marginal variances. Strength remains exact
E_prior[N]/E_prior[Z]. Posterior correlations are omitted by the requested
diagonal sum. Details and commands are in
`experiments/confvar/README.md`; inputs and numerical provenance are in
`input/` and `manifest.json` there.

There are 1,713 goal measurements. Populations overlap; these counts are
diagnostics, not independent statistical samples. Ratios below are
first-order/reference variance; understatement uses ratio < 1 - 1e-9.

| Population | Goals (positive variance) | Understated | Min | 5th percentile | Median | 95th percentile | Max |
|---|---:|---:|---:|---:|---:|---:|---:|
| D0, all eight settings | 240 (240) | 202 | .0212087 | .761772 | .999847 | 1.000000 | 1.000238 |
| D0 within 12 parameters | 224 (224) | 186 | .314947 | .766132 | .999848 | 1.000000 | 1.000238 |
| D0 broad | 30 (30) | 29 | .0212087 | .178974 | .829088 | .973829 | 1.000000 |
| D0 narrow | 210 (210) | 173 | .958690 | .989000 | .999871 | 1.000003 | 1.000238 |
| Authored posterior fixtures | 64 (56) | 45 | .00620328 | .0174262 | .998243 | 1.002345 | 1.199381 |
| Captured unit-call goals | 1,386 (1,355) | 1,235 | 0 | .511825 | .965852 | 1.000006 | 2.099946 |
| Captured standard benchmark goals | 9 (0) | 0 | — | — | — | — | — |

Broad for these trials means a Bernoulli parameter or a Beta shape sum <= 10.
Among D0 goals, 43 understate by more than 1%, including 15 in the narrow
subset. At K=800, first-order would report greater confidence on 202/240 D0
goals. The worst narrow D0 case needs a multiplier of at least 1.04309;
1.05 covers that subset but still cannot handle stationary interactions.

Selected shapes and failures:

- **Many parameters:** P13/F0, 20 uniforms, first-order `6.0632980e-12`
  versus the exact product variance `2.8588770e-10`, ratio `.0212087`.
  P14/F0, 15 uniforms, ratio `.0677223`. These wide D0 diagnostics exceed
  the admitted graph's 12-parameter cap; they are not claimed as admitted
  production models. Within the cap, P16/F0's ratio is `.314947`.
- **Concentrated parameters:** P16/F1 has `7.0144082e-4` versus numerical
  reference `7.3166599e-4`, ratio `.958690`.
- **Near an endpoint:** a uniform A, fixed B=1e-6, hard A-or-B, goal A,
  has first-order `2.8125056e-13`, exact variance `2.3631097e-11`, ratio
  `.0119017`. The analytic reference integrates the complement to avoid
  cancellation. Across the endpoint diagnostic subset, 117/142 positive
  references are understated; 15 goals have unresolved numerical references.
- **Stationary interaction:** the existing XOR case at
  `tests/test_event_node.py:311` has first-order zero and exact variance
  `1/36`. The same failure persists with concentrated Betas, as below.

Numerical limits: non-polynomial references use independent centered NumPy
Gauss-Jacobi tensor passes with their refinement gaps recorded. Five authored
fixture goals and 21 captured unit goals have gaps above 1%; excluding these
leaves 40 and 1,214 observed understatements respectively. No D0 reference
has a gap above 1% (maximum approximately .605%). Agreement is not a certified
integration error bound. Small numerical differences are therefore not a
proof of overconfidence. The stop decision instead rests on closed forms.
Production answers, including `bound` results, are stored separately and are
never treated as exact reference truth. The diagnostic confidence-conversion
counts use K=800; variance comparisons do not depend on that choice.

## Widening decision

No widening was selected. Measured trial failures across the complete set:

| Trial | Goals still understated |
|---|---:|
| 2 x first-order | 97 |
| 64 x first-order | 26 |
| Broad 64x; narrow 1.05x | 47 |
| Broad Bernoulli variance bound; narrow 1.05x | 29 |

These counts include exploratory numerical references. Every trial also fails
analytic cases, so its rejection does not depend on those numerical limits.

For independent X,Y ~ Beta(a,a), let
g = X + Y - 2XY = P(XOR). There is no observation, so Z=1 and posterior=prior.
At their means X=Y=1/2 both derivatives vanish. The exact variance is

    V = 4 Var(X) Var(Y) = 1 / [4 (2a+1)^2] > 0.

| a | First-order V | Exact V | Exact confidence (K=800) | Zero-V confidence |
|---:|---:|---:|---:|---:|
| 1 | 0 | .0277777778 | .0099009901 | .9999 |
| 100 | 0 | 6.18796564e-6 | .9805825243 | .9999 |
| 1000 | 0 | 6.24375468e-8 | .9998002397 | .9999 |
| 3601 | 0 | 4.81851460e-9 | .9999845810 | .9999 |

The last row illustrates the zero-V sentinel's limit: it happens to be less
confident there, but it does not rescue the first three rows. Beta(1000,1000)
is concentrated even under the existing integrator's criterion.

A finite multiplicative widening leaves zero unchanged. Returning a bound
only for broad parameters leaves the concentrated counterexample unchanged.
Special-casing exactly zero derivatives is insufficient: with both means
shifted to .500001 at shape sum 2000, the first-order/exact ratio is
`1.60080e-8`; at .50000001 it is `1.60080e-12`. The needed multiplier is
unbounded as the stationary point is approached.

Thus a useful replacement needs explicit interaction uncertainty, including
for concentrated parameters, beyond the proposed broad-only correction. A
Bernoulli bound for every nonconstant model is trivially conservative but
collapses all such confidences to zero; it was not adopted as a first-order
confidence estimate. This is a stop with numbers, not a claim that no other
closed-form interaction bound can exist.

## Gates and benchmarks

- `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS**, 278 s,
  recorded under verify key `bed23d188b00`. MeTTa: 162 files passed, zero
  failed. Python: 1,040 tests, 24 existing expected failures, one skip,
  16 workers; 4,554 query rows with zero aborts. Lint, import scaling,
  judgment scaling, and ConceptNet passed. Log: `scratch/confvar/verify.log`.
- Separate instrumented posterior/calibration unit collection: **PASS**,
  580 tests, 21 existing expected failures, 481.389 s. Three independent
  polynomial checks verified the posterior parameter-moment calculation.
- `compare.sh master <worktree> --full --retime --no-fail-fast`:
  **PASS**, `accuracy changed in 0 cases`; 23 cases, 22 executed runs, one
  reused result, 187 s wall. This diagnostic capture used the standard
  runner and its existing seeds. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/23d62195_vs_23d62195_full-retime-20261031T124912/report.md`.
- Required ordinary `compare.sh master <worktree> --full`: **PASS**,
  `accuracy changed in 0 cases`, reused verdict `445a552d1a3b` of that
  identical runtime comparison. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/23d62195_vs_23d62195_full/report.md`.
- `compare.sh anchor <worktree> --canary`: **PASS**,
  `accuracy changed in 4 cases`, reused same-runtime verdict `5ef2de229e80`
  from 2026-10-31 07:40:12. Existing changes against the anchor are live
  b50/5 shifts/s1, conflict pln-stated l/spq4/s1, conflict pln-reliable
  l/spq4/s1, and scale m/spq4/r10/s1. All are already on master; this round
  changes none. Nine anchor flags remain nonblocking because master has
  them too. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_23d62195_canary/report.md`.

The base and candidate use the same runtime tree `6ff8d0d26c24`, frozen build
`05c7a6ad`, PeTTa runtime `eec735bf4d1d3e31`. Full comparison peak RSS is
identical for both sides: +0%, within +5%; maximum suite peak is 1,498 MB.
These are the same stored run records, not independent evidence of a speed
or memory improvement. Instrumented timings are not improvement claims.
The nine captured benchmark calls have only point parameters and constant
folded terms, hence exact zero variance: this benchmark sample provides no
uncertain-confidence coverage. That limitation is explicit rather than
inferred from a green benchmark verdict.

## Moved values, deletion, and limits

- **Pinned strengths moved:** none.
- **Pinned confidences moved (file:line, old, new):** none; no test file was
  edited. No expected-failure list grew.
- **Runtime executable-line/token delta:** zero. No integration deletion
  occurred because step 2 rejected the candidate. The net-negative deletion
  condition applies if step 3 is undertaken; it is not claimed here.
- The contract is unchanged because runtime semantics did not change.
- Only experiment artifacts and this report were added. All final gate
  inputs remain identical to the validated base; the later measurement
  and report commits do not alter them.
- No nightly 300-case extension or curves were run. Default event-node
  units include 60 seeded fuzz nodes and 40 random multilinear cases.
- No universal conservative guarantee is claimed for the existing numerical
  integrator. Replacing or repairing that implementation was not justified
  by this failed first-order candidate.


## Round 2

**Implemented:** exact closed-form polynomial variance when Z is constant,
and a proved conservative closed-form bound when Z varies. Production has no
quadrature, refinement, HDMR, reduced-axis integration, rule cache or numerical
fallback. Strength evaluation and variance-to-confidence conversion are unchanged.
The zero-variance confidence remains .9999. No routes or compiler files changed.

### Commits and design

Continued the requested `confvar` worktree from `ffb9e720` without rebasing or
changing master (`23d62195`):

- `51c9a706`: commit all 1,713 round-2 measurements and the bound proof before
  changing production.
- `dc459bdd`: replace integration, remove its cache reset/export and its two
  implementation-specific tests, update the contract, audit confidence pins,
  and commit the production replay of the same measured set.
- A final validation/report commit adds this section, the manifest and strict
  bitwise-mean replay assertions. It also preserves .9999 at zero variance
  in the independent bound oracle, checked on forced false/true goals and
  an all-point fractional probability. Nothing is pushed or merged.

For e=E_prior[Z], s=E_prior[N]/e, D=N-sZ, Q=E_prior[D^2],
T=Var_prior(Z), and b=max(s,1-s), use

    V_claim = min(s(1-s), (Q + b sqrt(T Q))/e^2).

All Q/T moments are closed polynomial moments under the independent prior;
there is no assumption that posterior parameters remain independent. The
proof is short: |D/Z|<=b, with zero contribution at Z=0, and

    e^2 Var_post(N/Z) = Q - E_prior[(Z-e) D (D/Z)]
                     <= Q + b sqrt(T Q)

by Cauchy-Schwarz. The Bernoulli bound can also be taken. At constant Z, T=0
and Q/e^2 is exactly Var(f), including all XOR/product interaction terms.
A proportional numerator has Q=0 and retains the zero-variance sentinel.
For varying Z the numeric bound is tagged `conservative`; the existing
`bound` sentinel still means confidence zero in the over-cap callers.

The kernel expands negative literals, folds points and combines equal
positive monomials. All 1,203 captured calls were separately checked for the
multilinear invariant: each term uses a parameter at most once. E[f g] uses each shared parameter's second moment and
all unshared parameters' means. Beta and Bernoulli moments are analytic.
Rational arithmetic over the supplied numeric inputs preserves cancellations
and small endpoint moments, before the final square root/float output.
This removes the need for complement selection or subtraction of inexact
near-one integrated second moments. The independent measurement uses float
pair covariances instead; production replay checks agreement within numerical
precision and conservativeness against the retained round-1 references.

This candidate was selected because it handles concentrated stationary
interactions without a fitted multiplier, has a direct ratio-bound proof,
and remains informative on most measured cases. A Bernoulli bound for every
nonconstant model would discard all their confidence. Adding a special exact
rational integrator for endpoints would restore a second numerical path and
was not adopted. No Beta-mixture enumeration or empirical first-order
widening is needed.

### Measurements and limits

`experiments/confvar/round2-measurements.jsonl` and `round2-summary.json`
preserve the same 1,713 goals, inputs and references as round 1. The separate
`round2-runtime.jsonl` replays every model through the replacement kernel.
All 1,395 captured unit/benchmark goal strengths equal their old production
strengths **bit-for-bit**; all 1,713 agree with the independent mean evaluation.
There is no material variance understatement (relative tolerance 1e-9) and
no overconfident converted confidence on the measured set.

| Population | Goals | Z constant / varying | Positive references above 1e-28 | Min ratio | Median | 95th percentile | Max |
|---|---:|---:|---:|---:|---:|---:|---:|
| D0 | 240 | 65 / 175 | 240 | 1.000000 | 1.577411 | 3.163428 | 16.477343 |
| Authored posterior fixtures | 64 | 5 / 59 | 56 | 1.000003 | 2.560790 | 126.865237 | 361.051903 |
| Captured unit goals | 1,386 | 86 / 1,300 | 1,348 | 1.000000 | 1.837318 | 6.667536 | 44,334,835 |
| Captured benchmark goals | 9 | 9 / 0 | 0 | — | — | — | — |
| Analytic XOR/endpoint diagnostics | 14 | 7 / 7 | 14 | 1.000000 | 1.199326 | 6,249,444 | 17,803,162 |

Ratios are candidate/reference variance. Constant-Z classification uses the
independent polynomial coefficients, including any supplied-float residuals;
forced goals can have Q=0 even with varying Z. Runtime `exact` counts are 65,
8, 98 and 9 for D0, fixtures, units and benchmarks respectively. The previous
numerical references retain their refinement/error labels: five authored
fixtures and 21 unit goals have refinement gaps above 1%. No D0 reference
does. Those references are diagnostics, not certified integration error bounds.

Seven old unit reference variances are below 1e-28 (squared rounding noise);
five would appear understated in a raw zero-versus-positive relative count.
They are exposed separately rather than dropped from the data. No converted
confidence exceeds its reference there. Exact polynomial cases agree to
floating-point accuracy (worst relative difference approximately 3.2e-12).
The mathematical proof supplies conservativeness in the model; final float
rounding is not an interval-arithmetic certificate.

Thin boundary layers remain the main cost of simplification. The uniform
OR example with fixed sibling 1e-9 widens by 17.8 million, and the tiny
complement captured unit by 44.3 million. These are positive finite
variances, not invented zero variance. Confidence saturates to zero for
3/64 fixture and 51/1,386 unit goals, and for no D0 or analytic goal.
The nine round-1 benchmark captures still have point parameters/zero variance,
so passing benchmarks does not establish tight uncertain-confidence accuracy.
KE's query-order fixture retains its exact strength and source evidence;
its pinned confidence changes from .9984709741264072 to .9984709284253547,
identically in cold, warm, diagnostic and retained-history cases.

Polynomial expansion can grow with literal count and the second-moment
product is quadratic in collected polynomial size. Existing atom/component
caps are unchanged. The measured maximum sum of normalization/numerator
polynomial sizes is 32; the long-product diagnostics remain sparse. No
new unbounded benchmark/KE ingestion run was started.

### Validation and benchmark provenance

- `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS**,
  **187 s**, cache key `f31ee6f463e0`. MeTTa: **162 files, zero failures**.
  Python: **1,040 tests**, 24 existing expected failures, one existing skip,
  73 files / 648 units / 16 workers, 133.4 s. The 4,554 query rows have
  zero aborts. Lint, import scaling, judgment scaling and ConceptNet pass.
  Log: `scratch/confvar/round2-verify-zero-bound.log`.

- Focused event-node tests: **PASS**, 23 tests, 34.053 s. The old quadrature
  generator/grid-inspection tests were replaced by exact concentrated XOR
  and analytic varying-Z product-bound tests. The 20-parameter product
  tests and all independent numerical oracles remain.
- Production replay: **PASS**, all 1,713 models. Commands are below; data
  includes runtime variances/tags, old outputs and reference refinement gaps.
- `compare.sh master <worktree> --quick`: **PASS**, accuracy changed in zero
  cases, 114 s, nine runs executed. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/23d62195_vs_51c9a706-d1e89c835_quick/report.md`.
- `compare.sh master <worktree> --full --no-fail-fast`: **PASS**, accuracy
  changed in zero cases (22 accuracy-bearing cases, 23 profile cases),
  44 runs executed, one reused, 180 s wall. The final tree's required rerun
  reused the identical comparison's verdict `29acf112f1e0` through the
  standard runner. Original/final reports:
  `/nexus/Dev/OpenCog/bench/results/compare/23d62195_vs_51c9a706-d377f7208_full/report.md`,
  `/nexus/Dev/OpenCog/bench/results/compare/23d62195_vs_51c9a706-d93dbbb3e_full/report.md`.
- `compare.sh anchor <worktree> --canary`: **PASS**, accuracy changed in the
  same four pre-existing cases: live b50/5 shifts/s1, conflict pln-stated
  l/spq4/s1, conflict pln-reliable l/spq4/s1, scale m/spq4/r10/s1.
  Master comparison on that profile has no changes; seven anchor flags
  are also on master and nonblocking. Six profile cases, 118 s wall.
  Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_51c9a706-d76cabaed_canary/report.md`.
  Initial launcher exit-127 records were retried by the standard runner;
  every final base/candidate run in both required comparison JSONs exits
  zero and has no unsupported marker.
- Peak RSS: worst paired full-case increase **+0.56%** (learned/mined,
  626.0 -> 629.5 MB), within the brief's +5% limit. Suite maximum remains
  approximately 1,498 MB. These are ordinary stored/paired runner measurements;
  no speed improvement is claimed for the all-point benchmark sample.

All processes used the pinned worktree environment, capped admission,
`ulimit -v 16000000`, DISPLAY unset and stdin `/dev/null`. Standard compare
acquired its own slots. The production replay consults the local native
kernel; MeTTa acceptance uses `scripts/test_metta.sh` through verify, with
strict determinism. The pin capture prints from diagnostic copies in this
worktree's scratch directory; it does not replace acceptance tests or their
results. No shared venv, master, other worktree or compiler/route file changed.

The first exploratory full verification deliberately exposed the old policy:
21 MeTTa files and 79 Python units failed old confidence pins/factor-two
criteria; it also detected one invalid confidence-monotonicity assumption.
Its 273 s result was not cached because edits occurred during that run.
A subsequent MeTTa iteration caught the remaining direct last-bit variance
pin in a proof. All are resolved in the final gates; no xfail list grew.

Reproduce the no-integration measurement/replay with the usual capped wrapper:

```bash
unset DISPLAY
ulimit -v 16000000
/nexus/Dev/OpenCog/bench/capped env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  .venv/bin/python experiments/confvar/round2_runtime.py \
  --captures 'experiments/confvar/input/unit.*.jsonl' \
             'experiments/confvar/input/benchmark.*.jsonl' \
  --output experiments/confvar/round2-runtime.jsonl </dev/null
```

Use `round2.py` with output `round2-measurements.jsonl` for the independent
float implementation, then `round2_summary.py` for its distributions.
`capture_pins.py` documents the separate diagnostic pin capture; raw captures,
the full moved-value list and SHA-256 provenance are committed alongside it.

### Deletion and moved test expectations

`event_node.pl` shrinks from **370 to 156 lines**, 297 to 127 nonblank
noncomment lines, 18,462 to 7,558 characters, and 2,958 to 1,068 whitespace
tokens (**1,890 fewer, -64%**). The numerical-rule reset loses one further
line. `dist_rule/3` and every integration-only helper are deleted after
checking all test callers and the public API. Coupling and output conversion
retain their implementations. Numerical integration remains only in
independent test/reference oracles, never as a production path.

No existing pinned strength changed. Direct oracle-facing tests now compare
confidence to the independently evaluated polynomial/Cauchy bound, retaining
their strength/source/lifecycle checks. D0's general calibration gate retains
its existing strength and lower-variance checks and caps permitted widening
at the independent Cauchy bound (or its previous factor-two tolerance), so
an uninformative confidence-zero answer cannot pass an informative bound.

The dormant-rule test now checks its complete awakened source proof and
posterior (s=.9333009326760628, c=.8852647097239573), replacing the invalid
assumption that c must exceed its prior .9. Runtime design assumptions
explicitly permit confidence to decrease. Its strength had no old numeric
pin, and no existing strength pin was edited.

The following audit lists every changed numeric confidence expectation,
including last-bit changes, plus that changed confidence predicate and the
single conditional-variance value embedded in a proof. Dynamic oracle checks
change their mathematical target from exact variance to the proved bound;
their old/new values for measured models are retained in `round2-runtime.jsonl`.
Full reasons and raw pin captures are in `experiments/confvar/round2-pins.json`,
`round2-pin-capture.json`, and `round2-extra-pin-capture.json`.

| File:line | Old | New |
|---|---:|---:|
| `tests/metta/test_antecedent_completion.metta:100` | 0.8848264468765935 | 0.8276403501035767 |
| `tests/metta/test_antecedent_completion.metta:116` | 0.9642719007058969 | 0.8758368140834801 |
| `tests/metta/test_antecedent_completion.metta:129` | 0.9642719007058969 | 0.8758368140834801 |
| `tests/metta/test_antecedent_completion.metta:146` | 0.8784730745954683 | 0.8369869032375173 |
| `tests/metta/test_antecedent_completion.metta:162` | 0.8838276042026711 | 0.849294580857932 |
| `tests/metta/test_antecedent_completion.metta:223` | 0.9403166306602331 | 0.7583386828839901 |
| `tests/metta/test_antecedent_completion.metta:306` | 0.957915290831156 | 0.8801455591446746 |
| `tests/metta/test_base_rate_cache.metta:19` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_base_rate_cache.metta:31` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_base_rate_cache.metta:43` | 0.006210815399461902 | 0.002318882706019336 |
| `tests/metta/test_base_rate_cache.metta:56` | 0.601122168834573 | 0.3711428437146867 |
| `tests/metta/test_base_rate_cache.metta:121` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_base_rate_smoothing.metta:42` | 0.8127525165795743 | 0.6461336828309306 |
| `tests/metta/test_base_rate_smoothing.metta:45` | 0.7757318147185712 | 0.5773644637910565 |
| `tests/metta/test_canonical_keys.metta:48` | 0.0024922760534972026 | 0.0018959138091212229 |
| `tests/metta/test_compound_key_reads.metta:108` | 0.6441674789749815 | 0.41289069125729083 |
| `tests/metta/test_compound_key_reads.metta:120` | 0.9716743561550458 | 0.8286414873667223 |
| `tests/metta/test_compound_key_reads.metta:123` | 0.6441674789749815 | 0.41289069125729083 |
| `tests/metta/test_dormant_rules.metta:24` | > 0.9 | 0.8852647097239573 |
| `tests/metta/test_double_negation_evidence.metta:72` | 0.8177594758263098 | 0.817759475826309 |
| `tests/metta/test_double_negation_evidence.metta:77` | 0.8177594758263098 | 0.817759475826309 |
| `tests/metta/test_e2_review.metta:15` | 0.09497509861321828 | 0.000626947514199894 |
| `tests/metta/test_e2_review.metta:29` | 0.018103233391136595 | 0.0006477854325506413 |
| `tests/metta/test_e2_review.metta:36` | 0.018103233391136595 | 0.0006477854325506413 |
| `tests/metta/test_e2_review.metta:47` | 0.5394407432441399 | 0.3832524998016349 |
| `tests/metta/test_e2_review.metta:96` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_e2_review.metta:99` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_e2_review.metta:107` | 0.03740954158120962 | 0.02080511773903594 |
| `tests/metta/test_e2_review.metta:120` | 0.0 | 0.0006184187895021472 |
| `tests/metta/test_e2_review.metta:131` | 0.13535810664671122 | 0.0 |
| `tests/metta/test_e2_review.metta:134` | 0.13535810664671122 | 0.0 |
| `tests/metta/test_e2_review.metta:144` | 0.0043849664310933005 | 0.0007868745546970322 |
| `tests/metta/test_e2_review.metta:156` | 0.9963732804835199 | 0.9821452875091857 |
| `tests/metta/test_e2_review.metta:166` | 0.9900002499933779 | 0.9900002178660449 |
| `tests/metta/test_e2_review.metta:309` | 0.9327469934863087 | 0.8475288093413195 |
| `tests/metta/test_e2_review.metta:312` | 0.9005244246969157 | 0.8510264324080095 |
| `tests/metta/test_e2_review.metta:315` | 0.8961652412342394 | 0.8540993689943807 |
| `tests/metta/test_e2_review.metta:425` | 0.01783579105080321 | 0.008068530748583989 |
| `tests/metta/test_e2_review.metta:443` | 0.990635962167288 | 0.00249377304868248 |
| `tests/metta/test_e2_review.metta:508` | 0.002482796838492276 | 0.0003136464033718647 |
| `tests/metta/test_evidence_semantics.metta:71` | 0.9000312488859047 | 0.8571556229033463 |
| `tests/metta/test_exists_queries.metta:1049` | 0.0046785124518373385 | 0.0008328962009328018 |
| `tests/metta/test_exists_queries.metta:1050` | 0.0046785124518373385 | 0.0008328962009328018 |
| `tests/metta/test_exists_queries.metta:1062` | 0.0046785124518373385 | 0.0008328962009328018 |
| `tests/metta/test_exists_queries.metta:1065` | 0.0046785124518373385 | 0.0008328962009328018 |
| `tests/metta/test_explicit_exists.metta:281` | 0.04096823867399197 | 0.04096823867399199 |
| `tests/metta/test_fact_absorption.metta:33` | 0.695952316239105 | 0.37282530478545584 |
| `tests/metta/test_fact_absorption.metta:39` | 0.7782723605026735 | 0.350377682390757 |
| `tests/metta/test_fact_absorption.metta:50` | 0.9024793221355061 | 0.5898285722031854 |
| `tests/metta/test_foldall_merged_outputs.metta:16` | 0.9157521344935795 | 0.8321481456356352 |
| `tests/metta/test_forall_rules.metta:33` | 0.01120920246771997 | 0.004075945312161419 |
| `tests/metta/test_forall_rules.metta:36` | 0.007292928897821183 | 0.002951085759576529 |
| `tests/metta/test_forall_rules.metta:61` | 0.014852330918539098 | 0.006037200700960572 |
| `tests/metta/test_forall_rules.metta:64` | 0.014852330918539098 | 0.006037200700960572 |
| `tests/metta/test_forward_incremental_base_rates.metta:54` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_forward_incremental_base_rates.metta:180` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_forward_incremental_base_rates.metta:270` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_implication_inversion.metta:17` | 0.005314296401577442 | 0.001904354383499667 |
| `tests/metta/test_implication_inversion.metta:31` | 0.880278809263728 | 0.6571823212282056 |
| `tests/metta/test_implication_inversion.metta:49` | 0.9235006438119177 | 0.7702295732572509 |
| `tests/metta/test_implication_projection.metta:16` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:24` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:32` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:37` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:41` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:51` | 0.23668266416564468 | 0.14919732114575335 |
| `tests/metta/test_implication_projection.metta:55` | 0.23668266416564468 | 0.14919732114575335 |
| `tests/metta/test_implication_projection.metta:66` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:70` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_implication_projection.metta:83` | 0.04861111111111113 | 0.04861111111111111 |
| `tests/metta/test_implication_projection.metta:87` | 0.2366826641505106 | 0.14919732113904566 |
| `tests/metta/test_lifting_merge.metta:58` | 0.9000312488859047 | 0.8571556229033463 |
| `tests/metta/test_logic_config.metta:31` | 0.13535810664666598 | 0.0 |
| `tests/metta/test_logic_config.metta:39` | 0.3947855706242057 | 0.000624869674253918 |
| `tests/metta/test_population_prior_factoring.metta:15` | 0.9402892159691107 | 0.688997980090257 |
| `tests/metta/test_population_prior_factoring.metta:27` | 0.8417622371195731 | 0.6977029631309438 |
| `tests/metta/test_population_prior_factoring.metta:37` | 0.9961412800750794 | 0.6411204420413348 |
| `tests/metta/test_population_prior_factoring.metta:48` | 0.9383094569023933 | 0.6790956542814797 |
| `tests/metta/test_population_prior_factoring.metta:68` | 0.9942636244655746 | 0.7808070767909777 |
| `tests/metta/test_population_prior_factoring.metta:71` | 0.9914124106210676 | 0.6640326831301038 |
| `tests/metta/test_problog_fuzz_regressions.metta:134` | 0.949452306332817 | 0.6671844436773675 |
| `tests/test_ke_query_order.py:29` | .9984709741264072 | .9984709284253547 |
