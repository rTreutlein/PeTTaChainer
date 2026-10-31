# Confidence replacement measurements

The confvar round stops before replacement. The production runtime and its
contract remain unchanged. `CONFVAR_REPORT.md` at the worktree root records the
decision and acceptance gates.

The statement above describes round 1. Round 2 measures a different candidate
in `round2.py`, preserving the round-1 inputs and references. It runs the same
command as `measure.py` with `round2.py` and output `round2-measurements.jsonl`;
then run `round2_summary.py`. No integration runs in the round-2 measurement.

### Round 2 formula and proof

All moments in the implementation are under the independent **prior**. Let
`e = E[Z]`, `s = E[N]/e`, `D = N-sZ`, `Q = E[D^2] = Var(D)`,
`T = Var(Z)`, and `b = max(s,1-s)`. Since `0 <= N <= Z`,
`|D/Z| <= b` wherever Z is positive. Zero-Z points contribute zero. Then

    e^2 Var_post(N/Z) = e E[D^2/Z]
                      = Q - E[(Z-e) D (D/Z)]
                     <= Q + b sqrt(T Q).

The last step is Cauchy-Schwarz. Therefore the candidate is

    min(s(1-s), (Q + b sqrt(T Q))/e^2).

There is no posterior-independence assumption, derivative approximation,
integration order or empirical multiplier. If Z is constant, T=0 and this is
the exact polynomial variance, including XOR and arbitrary products. Expanding
literal terms into ordinary multilinear monomials combines cancellations in Z
before second moments. The pair-monomial covariance uses the exact independent
Beta/Bernoulli first two moments and a product-difference recurrence, avoiding
subtraction of near-one raw second moments. Points are folded algebraically.

The candidate is conservative on all 1,713 measured goals, using the round-1
1e-9 relative variance comparison. Seven old numerical references below 1e-28
are explicitly separated in the summary (five give a raw zero/nonzero
comparison); all seven are at the squared-roundoff scale. No confidence after
conversion exceeds its reference, including these seven. Unresolved numerical
references keep their original refinement labels: the proof, rather than
numerical agreement, establishes the mathematical bound. Exact polynomial
rows agree to floating-point accuracy (worst relative deviation about 3.2e-12).

The bound can be loose: the uniform OR endpoint at fixed sibling 1e-9 gives
17.8 million times the exact variance; the worst captured endpoint gives
44.3 million. Median factors are 1.577 (D0), 2.561 (authored fixtures), and
1.837 (units). Only 3/64 fixture and 51/1,386 unit goals saturate to confidence
zero; no D0 or analytic goal does. The nine captured benchmark goals still
have point parameters and zero variance. Round 2 therefore admits replacement
with an explicitly conservative bound rather than claiming exact rational
posterior variance for varying Z.

`measurements.jsonl` contains 1,713 goal measurements: 240 D0 goals (including
the P13/P14 wide diagnostics), 64 authored posterior fixture models, 14 analytic
cases, 1,386 goals from captured unit-test calls, and nine goals from captured
standard benchmark calls. These are overlapping diagnostic populations, not
independent samples. `summary.json` records distributions and widening trials.
`input/` preserves every captured call, including its original production
answer. Capture deduplication uses the full call and answer within each process;
measurement deduplication uses the full serialized node across input files.

## Candidate and reference

For each independent prior parameter, compute its first three moments. Because
Z is multilinear, with prior mean mu, variance v, third central moment t, and
q = (partial Z / partial theta_i)(mu) / Z(mu), its exact posterior marginal
moments under prior(theta) Z(theta) are:

    posterior_mean_i = mu_i + v_i q_i
    posterior_variance_i = v_i + t_i q_i - v_i^2 q_i^2

The candidate is exactly the proposed diagonal sum, evaluated at those
posterior means:

    sum_i [(partial N_i - (N/Z) partial Z_i) / Z]^2 posterior_variance_i

The posterior generally correlates parameters. The proposed diagonal sum omits
these covariances as well as higher-order interactions. Strength stays
E_prior[N]/E_prior[Z], evaluated at the prior means. The diagnostic also records
the delta estimate evaluated at prior means for comparison.

Coefficients are normalized before evaluation. Point and Bernoulli parameters
retain their contract distributions. The fixture adapter reads authored source
models, including their evidence-confidence K; it does not recover models from
runtime outputs. Existing D0 definitions, settings, and the fixture audit are
used unchanged. The independent parameter-moment formulas were checked against
three-point polynomial quadrature for a tilted uniform, two tilted Betas, and
a mixed Bernoulli/Beta model; see `measurement-check.txt`.

Analytic references are closed-form product moments, XOR moments, and a uniform
parameter against a disjunction with a fixed sibling. The latter integrates
the complement to avoid subtracting near-one second moments. All-point captured
models have exact zero variance.

Other references are independent NumPy Gauss-Jacobi tensor passes. The finest
order is selected from 65, 33, 17, 9, 7, 5, 3, 2 with at most 200,000 points;
the coarse order is max(2, (fine+1)//2). Centered integration computes
E_prior[(N-s Z)^2/Z]/E_prior[Z], avoiding second-moment subtraction. The raw
refinement gap is recorded, including failures. Agreement is **not an error
bound**. Five authored fixture goals and 21 captured unit goals have gaps above
1%; their ratios are exploratory, not exact claims. No D0 reference has a gap
above 1%. Production `exact`/`bound` tags are retained as observations and are
never used as independent reference truth.

The decisive XOR counterexamples have analytic references and do not depend on
quadrature convergence or any production approximation.

## Reproduce

From this worktree, with the pinned environment:

```bash
unset DISPLAY
ulimit -v 16000000
/nexus/Dev/OpenCog/bench/capped env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  .venv/bin/python experiments/confvar/measure.py \
  --captures 'experiments/confvar/input/unit.*.jsonl' \
             'experiments/confvar/input/benchmark.*.jsonl' \
  --output experiments/confvar/measurements.jsonl </dev/null
/nexus/Dev/OpenCog/bench/capped env OPENBLAS_NUM_THREADS=1 \
  .venv/bin/python experiments/confvar/summarize.py </dev/null
```

To collect units again, set CONFVAR_CAPTURE to an absolute prefix in this
worktree and run `capture_units.py` with the same capped/unset/ulimit/stdin
wrapper. It runs six existing unittest modules and instruments after loading
the runtime library, preserving the PeTTa load-cache boundary. The recorded run
passed 580 tests with 21 existing expected failures in 481.389 seconds.

The benchmark capture used the standard `compare.sh master <worktree> --full
--retime --no-fail-fast` with PETTACHAINER_REPO pointing at this worktree. It
executed 22 runs and reused one result. A temporary .pth in **this worktree's**
venv added this experiment directory and imported `capture_bootstrap` with
CONFVAR_CAPTURE set. The hook removes its profiler at the first chainer
constructor return, then loads `capture.pl`. The wrapper calls the original
predicate and records its successful answers. It never replaces results.
The .pth was deleted after that run. No production source or shared venv was
modified. Timing from the instrumented run is diagnostic, not evidence of a
performance improvement. The ordinary full gate reused its identical-tree
verdict; the anchor canary reused an earlier identical-runtime verdict.

The nine benchmark calls all contain point parameters and constant folded
terms. They provide no positive-variance coverage. Uncertain calibration
evidence comes from the D0 harness, authored fixtures, and captured units.

Broad for these widening trials means a Bernoulli parameter or a Beta whose
shape sum is at most ten. The decisive Beta(1000,1000) case is concentrated
under the existing runtime's own criterion too. No production cutoff changes.
