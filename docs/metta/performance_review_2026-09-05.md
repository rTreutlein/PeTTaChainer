# Runtime and benchmark review — 2026-09-05

Initial baseline: `26a04bc0`. First checkpoint: `aa63ea0b`.
Public API signatures and proof history are preserved.

## Runtime changes

- `extract-vars` returns immediately for ground terms. Open terms retain the
  existing traversal, including variable order, duplicates, and the treatment
  of native closures as opaque source values.
- The derivation index contains current rule candidates. Removing a candidate
  removes its index entry; losing the merged-result role does not. Full goal
  keys and derivation comparisons reject hash collisions. Historical proof
  records remain available after query reset.
- Removed `proof-current-in-key?`: derivation lookup no longer visits historical
  entries to test whether each is current. At the first checkpoint, the three
  affected MeTTa files have
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
benchmark execution paths now share one runner; the script shrank from 293 to
209 lines.

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
- `scripts/check_import_scaling.sh`: PASS; late/early ratio 1.008 over 8000 rules.
- ConceptNet own/pet query: two complete expected proofs; no engine abort.
- `git diff --check`: clean.

The final `scripts/verify.sh` ran all four gates in 168 seconds; its log is
`/tmp/pettachainer-goal-followup-verify.log`. The earlier checkpoint passed the
same gates, with import-scaling ratio 1.002.

## First checkpoint performance

Local environment: AMD Ryzen 7 5700X3D (8 cores / 16 threads), WSL2 Linux,
Python 3.10.16, and the repository-pinned PeTTa 0.1.0 environment. Measurements
use one benchmark process at a time; no test suites run concurrently with them.

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

An additional three alternating pairs increased repeated refinement to 50
queries. Total query time decreased from 22.377038 s to 20.655591 s (-7.69%);
the final ten-query median decreased from 0.991257 s to 0.893081 s (-9.90%).
The first ten-query median rose 1.83%. Every run preserved 50 fresh results,
the exact final proof/TV, distribution mass 1 and mean 50, and 1329 durable
proof rows. Derivation-index rows decreased from 1274 to 1. The removed index
scan matters more with longer history, but repeated replay still creates
quadratically many durable rule records; this patch does not solve that cost.
Full per-query timings are in `refinement50-comparison.json`.

Raw runs and comparison output are retained under
`/tmp/pettachainer-goal-ab.Km4W14/`. The comparison driver is `run_pairs.py` in
that directory. These are local run artifacts, not permanent repository data.

## Follow-up: smaller index rows and exact removal

The follow-up removes eight `copy_term` calls and the unused detached-key fields
from five backward index row shapes. Full actual keys remain available for
alpha checks; their sharing with output keys is preserved. Protective copies
at real unification boundaries remain.

A new lifecycle regression exposed a pre-existing deletion bug on both the
checkpoint and the cleanup. Two open keys with different variable-sharing
patterns can share a hash and a concrete output. The old alpha guard selected
the right row, but `remove-atom` then unified its open pattern with the other
row too. Result-key and dirty-key removal now enumerate indexed clauses with
fresh saved fields, apply the same alpha checks, and erase the exact selected
clause reference. No extra identity state or helper is needed. The regression
checks surviving colliding entries, renamed-key lookup, stable result order,
durable history, unbound input variables, and empty/absent removals.

Across the four changed MeTTa implementation files, the combined pass adds 51
source lines and removes one named function. It simplifies stored data and
lookup work, not total line count; exact collision-safe deletion accounts for
most of the follow-up's added lines. Tests and documentation grow to cover the
previously untested boundaries.

### Follow-up performance

Three more alternating pairs compare the final frozen working tree against
the clean `aa63ea0b` snapshot, again using identical benchmark source. All six
runs passed. Medians in seconds:

| Workload / measured window | Checkpoint | Final | Change |
| --- | ---: | ---: | ---: |
| Backward agenda | 2.792545 | 2.787413 | -0.18% |
| Forward agenda | 0.615644 | 0.617308 | +0.27% |
| Durable multi-root queries, total | 0.422419 | 0.416306 | -1.45% |
| Incremental Member delta queries | 0.488233 | 0.479858 | -1.72% |
| Forward population build | 19.738591 | 19.536635 | -1.02% |
| Forward population cache read | 0.000804 | 0.000817 | +1.62% |
| Forward population public query | 0.022237 | 0.022391 | +0.70% |
| Lifting merge, cold query | 0.384178 | 0.386826 | +0.69% |
| Lifting merge, warm queries | 3.843853 | 3.808294 | -0.93% |
| Repeated refinement, 25 queries | 3.725525 | 3.742868 | +0.47% |
| Refinement, last ten-query median | 0.247988 | 0.247667 | -0.13% |

No metric regressed by more than 1.62%. These small differences do not establish
a further general speedup: this follow-up primarily simplifies storage and
fixes collision handling without a material measured performance penalty.
Raw runs, all metrics, and the comparison driver are under
`/tmp/pettachainer-key-ab.JPcr4k/` (`comparison.json`, `run_pairs.py`). The 50-query
scaling figures above measure the first checkpoint; this follow-up comparison
uses the core suite's 25-query workload.

## Remaining investigation

Small populations can have a correct forward cache without exposing the whole
estimate at a tiny query budget: 12 members give no answer at two steps and a
five-observation estimate at 20 steps; 100 steps completes all 12. Larger
budgets trigger live refolding, so they are a separate workload from cache
reuse. No general population-to-completion-budget formula is assumed.

Repeated replay of historical CPU draws remains a separate candidate. Generic
pruning of old CPU outputs is unsafe: different nondeterministic results can
satisfy different later premises. A further change needs to distinguish exact
completed-derivation replay from new computation alternatives.

The attempted early inversion-plan gate was rejected. A rule whose Compute
function comes from another premise exposed a hidden binding dependency:
the old planner binds it to `+`; skipping that work allows the intended `-`
through but then raises a runtime type error (numeric result versus TV).
Neither behavior is accepted as a correct forward result. The compiler guard
remains at its original position. New passing regressions retain coverage for
non-inverted fixed-function Compute and independent conjunction completion.
The separate dynamic-function defect needs its own reproducer-driven fix.
Diagnostic inputs and logs are retained as
`/tmp/pettachainer-open-compute-{baseline,current}.{metta,log}`; the `current`
error log describes the rejected candidate, not the final code.
