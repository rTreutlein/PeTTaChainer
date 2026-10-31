# CONFVAR: stop after measurement

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
