# Independent review: query-local proof eligibility cache

Reviewed against `docs/metta/runtime_design_assumptions.md` in `3ada65a7`.
The validation archive contains that revision plus the corrected eligibility
patch, with no shorter-path scheduler changes. The runtime source is identical
to compact-demand `94a52ce9` before this patch. Source hashes and frozen dependency
revisions are recorded in `manifest.json`; nothing was fetched or rebuilt.

## Correctness finding and correction

The proposed PID/GID-only cache was unsound on the original compact branch.
`ensure-goal-at-depth` can strengthen an existing unexpanded goal when a later,
shallower occurrence supplies a constrained proof/TV pattern. It reuses the
incoming `$stored-goal` variable when matching and reinserting the existing row.
Goal identity does not include proof or TV constraints, so the GID remains equal.

A concrete probe registered an open proof pattern at depth 4, cached acceptance
of proof `accepted`, and then registered proof pattern `rejected` at depth 0.
The stored goal became `rejected`; the proposed cache returned true while the
fresh uncached calculation returned false. The corrected cache returns false
both before and after explicitly clearing the cache.

The corrected key includes the complete copied stored goal. A hit requires
native Prolog `=@=/2` through the existing `callPredicate` boundary. It is
nonbinding and includes attributed constraints, unlike MeTTa `=alpha`. The
supported PeTTa atom-space implementation uses `assertz`, which erases variable
attributes; the stored-goal contract is therefore the asserted term, not every
constraint originally attached to a caller variable. A TV-versus-STV attribute
probe produced equal cached and uncached results after storage. Native variant
comparison avoids introducing an additional attribute-erasure assumption at the
cache comparison boundary.

The first check still materializes the complete result, copies the result and
goal, and performs full unification. It caches true and false separately from
lookup failure. Failed proof materialization/missing proof IDs remain uncached.
Proof rows and their children are append-only. Liveness, consumer compatibility,
evidence accounting, and current-source selection remain outside this cache and
are still computed by the existing callers. Query reset clears the new table.
All internal callers were updated; no documented public API was changed.

Durable tests explicitly rewrite a goal row under the same GID with stricter
proof and TV constraints, independently of scheduler rewrite policy. Existing
new cache tests also cover complete proof patterns, shared variables, caller
isolation, cache hit multiplicity, missing proof IDs, CPU result constraints,
and query reset. The real ensure-goal counterexample remains an untracked probe
in the validation archive.

## Exact result screening

`exact-comparison.json` records three seeds against prior compact-demand runs:
7/budget 600, 11/budget 300, 23/budget 300; all use two shifts, four modules, action
budget 1, and the same frozen supported runtime and ChainerGame.

All normalized complete proof strings, every non-timing episode result field,
and every non-timing query metric match for all three seeds. The seed-7 repeat
also matches exactly. New per-goal scoring targets are omitted when comparing
legacy result schemas; their capture occurs only during the game's final
scoring and does not change inference inputs.

| Seed | Prior compact diagnosis seconds | Corrected cache seconds | Comment |
|---|---:|---:|---|
| 7 | 87.6363 | 75.0813 | Isolated repeat; first cache run 75.6421 may overlap a strict import |
| 11 | 6.7007 | 6.4371 | Single screening observation |
| 23 | 4.8062 | 4.4270 | Single screening observation |

Seed 7 inferences fall from 68.94m to 51.70m in shift 1 and 429.51m to 345.68m in
shift 2. The isolated repetition has identical inference counts. Timing compares
against retained prior compact runs, not newly interleaved pairs, so it is
screening evidence rather than final performance acceptance.

This change preserves compact-demand's existing answer quality. It does not
recover the missing useful seed 7 derivation or satisfy the broader original
accuracy objective on its own.

## Validation

The earlier exact-goal-alpha variant passed full `scripts/verify.sh` (75 MeTTa
files, 57 Python tests, 46 metric rows/zero aborts, import ratio 1.001, ConceptNet 2).
After replacing alpha with native variant equality and fixing explicit test-row
construction, the focused strict DAG helper suite passed. Full verification of
that final source passed in `verify-final.log`: 75 MeTTa files, 57 Python
tests, 46 metric rows with zero aborts, import ratio 1.004, ConceptNet exactly
2 results, 184 seconds. The final source and patch hashes still match the
manifest captured before those checks.
