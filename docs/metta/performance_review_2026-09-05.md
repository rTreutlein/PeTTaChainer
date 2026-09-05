# Runtime and benchmark review — 2026-09-05

Baseline: `26a04bc0`. Public API signatures and proof history are preserved.

## Runtime changes

- `extract-vars` returns immediately for ground terms. Open terms retain the
  existing traversal, including variable order, duplicates, and the treatment
  of native closures as opaque source values.
- The derivation index contains current rule candidates. Removing a candidate
  removes its index entry; losing the merged-result role does not. Full goal
  keys and derivation comparisons reject hash collisions. Historical proof
  records remain available after query reset.
- Removed `proof-current-in-key?`: derivation lookup no longer visits historical
  entries to test whether each is current. The three affected MeTTa files have
  one fewer named function and 22 additional source lines, including clearer
  formatting and comments. This is a lookup-cost improvement with a small
  source-size tradeoff.

## Tests and benchmarks

The old backward agenda fixture had only impossible premises, which the
structural prefilter rejected before scheduling. It now has a checked
productive path and alternatives with intermediate producers. Timing requires
the expected proof and TV, agenda work, and multiple expanded hubs in the
many-small mode. Forward timing requires complete groups of exact derived
facts without assuming an order for equal-priority seeds. Four separate
benchmark execution paths now share one runner.

The core agenda workloads measure agenda growth at fanout 500. A dedicated
MeTTa regression checks the actual pruning boundary at 64000/64001 entries,
the retained best entry and size, and disabled pruning. Three tiny heap tests
that never entered the pruning branch were removed.

The Member benchmark requires exactly one correctly targeted outer answer;
a matching TV embedded in the proof cannot satisfy it. Forward population
confidence is `n / (n + 800)`. The cache is validated before backward reasoning
can fill missing work. Cache-read and public-query costs are separate, and the
population query budget is explicit and recorded (default: 1000 objects,
two query steps).

`refinement_query.py` repeats one Map2Dist query 25 times with fixed evidence.
It checks complete proofs, TVs, fresh distribution IDs, and final distribution
mass and mean. This adds coverage for history-dependent work within one
derivation, which the existing multi-root workload did not exercise.

The forked MeTTa runner now checks every child log for engine aborts, even when
the child exits successfully. A regression verifies that such a child fails
the suite. The forward/backward comparison validates stored forward facts
directly; a backward query can no longer hide absent forward work. A trivial
JSON-format snapshot test was replaced with wrong-checkout import rejection.

Core JSON schema 2 rejects old fixtures and mismatched parameters. The duplicate
lifting-merge total/per-repetition timing was removed from the core report.

## Validation

- `scripts/test_metta.sh`: 69 passed, 0 failed, strict determinism enabled.
- `.venv/bin/python -m unittest discover -s tests`: 48 passed.
- Python query metrics: 43 rows, 0 search aborts.
- `scripts/check_import_scaling.sh`: PASS; late/early ratio 1.002 over 8000 rules.
- ConceptNet own/pet query: two complete expected proofs; no engine abort.
- `git diff --check`: clean.

## Performance method

Three alternating baseline/candidate pairs use isolated processes, 1000-member
population workloads and identical benchmark source on both revisions. The
baseline snapshot contains the original runtime and the repaired benchmark
files. Per-workload medians are compared; setup and query costs remain separate.

All six runs passed their semantic checks. Core workload medians in seconds:

| Workload / measured window | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Backward agenda | 2.863642 | 2.763609 | -3.49% |
| Forward agenda | 0.620654 | 0.619640 | -0.16% |
| Durable multi-root queries, total | 0.416624 | 0.419879 | +0.78% |
| Incremental Member delta queries | 0.479813 | 0.478539 | -0.27% |
| Forward population build | 19.522514 | 19.560473 | +0.19% |
| Forward population cache read | 0.000814 | 0.000821 | +0.82% |
| Forward population public query | 0.022069 | 0.022593 | +2.38% |
| Lifting merge, cold query | 0.374993 | 0.381929 | +1.85% |
| Lifting merge, warm queries | 3.815323 | 3.830440 | +0.40% |
| Repeated refinement, 25 queries | 3.836902 | 3.717160 | -3.12% |
| Refinement, last ten-query median | 0.257983 | 0.248407 | -3.71% |

Negative changes are faster. These are modest local improvements, not evidence
of a large general speedup. No core metric regressed by more than 2.38%; that
largest relative regression was approximately half a millisecond. Runtime
setup costs changed by less than 0.4%. Full values, including every shift and
setup measurement, are in `comparison.json`.

Raw runs and comparison output are retained under
`/tmp/pettachainer-goal-ab.Km4W14/`. The comparison driver is `run_pairs.py` in
that directory. These are local run artifacts, not permanent repository data.

## Remaining investigation

Small populations can have a correct forward cache without exposing the whole
estimate at a tiny query budget: 12 members give no answer at two steps and a
five-observation estimate at 20 steps; 100 steps completes all 12. Larger
budgets trigger live refolding, so they are a separate workload from cache
reuse. No general population-to-completion-budget formula is assumed.

Further candidates identified by source review are redundant copied-key
columns in backward hash indexes, repeated replay of historical CPU draws,
and inverse-plan construction for compiler outputs that disable inversion.
They are not implemented in this pass.
