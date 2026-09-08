# Rule priority without a base-rate success prior

Ordinary backward rule priority now uses bounded marginal confidence gain
divided by the number of remaining premises. It no longer multiplies that
score by cached premise strength times confidence, or by 0.5 for missing
base rates. Statement probability does not estimate whether a proof with any
truth value can be found. A confident low-strength proof remains useful.

Depth bands, shared-root demand aggregation, path caps, marginal-gain floors,
cached-fold refinement scoring, proof acceptance, and truth-value formulas are
unchanged. The previous fold-startup retention experiment is not included.

The change deletes the five now-unused prior/lookup helpers and removes the
success-prior field from frontier state. No compatibility path or new tuning
parameter is added. Public API signatures are unchanged.

## Validation

- Strict MeTTa suite through `PETTA_STRICT=1 PETTA_JOBS=8 scripts/test_metta.sh`:
  **72 passed, 0 failed**.
- Full Python suite: **49 passed**, including the new bounded-search regression.
- Import-scaling ratio **1.011** (limit 1.5) and ConceptNet checks passed;
  the Python metric stream contains **46 queries, zero aborts**.
- The new regression swaps opposite cached base-rate strengths and also runs
  without cached rates. All three runs select the same confident zero-strength
  proof. Against the archived baseline, setting that premise's rate to zero
  selects the other proof and fails the regression.
- The materialization example's 100-step refined point changes from
  `(STV 0.46265034325181975 2.9999940000119994e-06)` to
  `(STV 0.47191878015453864 3.999988000035998e-06)`. Its fresh-handler point is
  unchanged. Zero-budget retention, shared-evidence reconstruction, zero-abort,
  and second-versus-third 200-step settling checks pass.
- Shared-root tests now express unequal branch values through rule confidence
  instead of base-rate strength. They retain checks that distinct roots add
  demand, alternative paths from one root do not, and unanswered roots receive
  work before further refinement. An equal-confidence tie chooses the other
  rule; the complete expected proof order is updated.
- The incident-response example still retains its incumbent at two steps and
  reaches the same refined proof with a larger budget. Its old two-step
  base-rate-guided ordering assertion is removed along with its wrapper.

The first verification exposed the obsolete policy expectations above; these
were assessed rather than interpreted as proof-validity failures. The final
MeTTa run follows the last fixture edit. Python, import-scaling and ConceptNet
checks were run through `scripts/verify.sh`; its earlier MeTTa failure remains
in that combined log, so this report does not describe that command as passing.

## Controlled StationOps comparison

The baseline is `1bfbf539`. Candidate and baseline runtime sources are isolated
archives, using the same repository-pinned interpreter and PeTTa runtime.
ChainerGame is `99fc56e`; the workload is seed 7, two shifts, four modules,
diagnosis budget 600 and action budget 1. No fetching or rebuilding occurred.
Timing runs start after validation has completed.

Local raw evidence and the exact candidate patch are retained under
`scratch/stationops-no-prior-2026-09-08/`.

Two interleaved pairs (baseline/candidate, candidate/baseline) produce:

| Diagnosis metric | Baseline | Without success prior |
| --- | ---: | ---: |
| Shift-one median seconds | 18.848 | 16.671 |
| Shift-two median seconds | 92.528 | 31.154 |
| Shift-two inferences | 489,087,282 | 123,031,434 |
| Shift-two agenda pops | 842 | 824 |
| Shift-two demand evaluations | 139,235 | 99,437 |
| Shift-two Brier error | 0.03103582 | 0.16358112 |
| Shift-two log loss | 0.14247159 | 0.43887040 |

All four episodes have full coverage, score 637, zero regret, and zero search
aborts. Within each side, inference counts, complete normalized proof answers,
and belief metrics repeat exactly. Answers differ across sides. The first
second-shift estimate changes from strength 0.7222996590 and confidence
0.0001815568 to strength 0.2205079337 and confidence 0.000001.

This is approximately a threefold second-shift speedup, but not an equivalent
quality result. The game applies confidence adjustment and further decision
processing, so matching final score is insufficient to assess raw diagnosis.
The cheaper search reaches substantially weaker estimates at the same step
budget. Passing proof-correctness tests does not establish good allocation of
a finite search budget.

A separate candidate-only screening run doubled the diagnosis budget to 1200.
Shift-one diagnosis took **188.04 seconds and 688,888,117 inferences**;
the complete first shift took **204.43 seconds**. The process then reached its
300-second wall limit during shift two (exit 124), so there is no complete
episode result or second-shift quality measurement for this run. It must not
be counted as another successful pair. Simply doubling the step budget did
not fit within the original episode's runtime. This does not establish whether
a different budget or scheduler would recover the lost quality efficiently.

The candidate is retained on the local branch
`experiment/no-base-rate-success-prior`; it is not merged into `master`.
Removing this unjustified multiplier simplifies the policy and passes the
semantic checks, but its equal-budget application results do not justify
calling it a general improvement.

Compact evidence: [no-success-prior-results-2026-09-08.json](../../benchmarks/stationops/no-success-prior-results-2026-09-08.json).
