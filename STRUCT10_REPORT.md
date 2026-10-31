# Structure round 10 hand-back

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct10`.
Branch: `struct10`; base: `c1a4bb99f3c5ffa9c197c16c402eeec54c83855a`.

## Commits

- `a735893d`: separate generic term deduplication, configuration validation, existential decoding and evaluator cache admission from stores.
- `dedb0c38`: narrow interfaces around terms, compiler plans and caller-local selectors; document every entry point.
- Final documentation/report commit: see `git log --oneline c1a4bb99..HEAD`.

## Diagnosis and design

The fixed map counts lexical references, including data and diagnostics. The API/Native stores pair combined a generic variant-deduplication call with native error-context labels naming the public API. The Installation/Search state pair mixed lowered-fold decoding with configuration validation. Value store recognized an evaluator instruction to decide summary-cache eligibility.

Generic `alpha_unique_keys` now belongs to Runtime terms, in `core/runtime_terms.pl`, with identical native clauses. API no longer depends on Native stores; the two native API diagnostic labels remain unchanged. Base-rate validation lives with configuration in `runtime/configuration_validation.pl`; existential fold-source decoding is owned by the compiler. Cache eligibility and the evaluation-only pending-search walk moved verbatim into the new `runtime/backward/eval_cache.metta`. It is a separate evaluator adjunct; no protected evaluator file was edited.

Pure forward/search key adapters and record projections now belong to Runtime terms. Fold descriptor classification belongs to Compiler plans. Compiler-only sampling/refinement admission stays inside lowering; proof expansion/classification stays with Proofs; late activation and CPU gating selectors used only by proof search stay there. Aggregate-to-fold registration belongs to Statistics. No forwarding aliases, extra state, changed indexes, new runtime equations or alternate implementation paths were added.

Three single-use projections were deleted and inlined: context-polymorphic configuration reading, specializing-predicate reading and statement-prefix projection. The test of the surviving indexed premise selector builds its prefixes directly. Two compound-mode readers remain named inside the compiler: an attempted direct inline changed compiled behavior and was reverted immediately after the suite caught it. Both original bodies were restored; subsequent suites pass.

Public API signatures, proof identities, budgets and expected calibration failures are unchanged. Static equation comparison finds exactly the three deleted helpers and exactly their three changed callers; every other equation body is identical after parsing, including moved definitions. Protected `runtime/evaluator/*`, `prolog/runtime_helpers.pl`, `hypothesis_mining.metta`, `prolog/event_*.pl` and `source_catalog.pl` are byte-for-byte unchanged. The coupling map and its tests are unchanged.

## Structural measurements

Measured with the repository `scripts/coupling.py`, unchanged, at base and the final code commit. The [layer inventory](docs/metta/layers.md) lists every externally referenced name in the required order.

| Metric | Before | After |
| --- | ---: | ---: |
| Two-way subsystem pairs | 5 | 2 |
| Cross-boundary names summed per directed pair | 642 | 636 |
| Directed subsystem edges | 117 | 117 |
| Widest interface overall | 41 | 39 |
| Widest interface outside Evaluator/Posterior | 41 | 33 |
| Largest file SCC (same static reference parser) | 11 | 11 |

| Interface | Before | After |
| --- | ---: | ---: |
| API | 6 | 6 |
| Executor | 8 | 8 |
| Installation | 6 | 4 |
| Proof search | 15 | 15 |
| Evaluator | 39 | 39 |
| Posterior | 2 | 2 |
| Statistics | 40 | 33 |
| Compiler plans | 12 | 19 |
| Compiler | 12 | 13 |
| Search state | 39 | 32 |
| Allowances | 16 | 16 |
| Value store | 23 | 22 |
| Proofs | 24 | 28 |
| Input journal | 6 | 6 |
| Fact store | 41 | 29 |
| Runtime terms | 21 | 30 |
| Native stores | 27 | 26 |
| Core types | 35 | 28 |
| Bootstrap/ABI | 0 | 0 |

Largest unprotected width falls 19.5%, from Fact store 41 to Statistics 33. Runtime terms grows as pure data boundaries move there. These remain broad interfaces, especially the unchanged evaluator callers; this round does not claim a three-function interface for every owner.

| Reciprocal pair, directions as written | Before | After |
| --- | ---: | ---: |
| API → Native stores / reverse | 1 / 2 | 0 / 2 |
| Evaluator → Posterior / reverse | 1 / 4 | 1 / 4 |
| Evaluator → Value store / reverse | 21 / 1 | 20 / 0 |
| Installation → Search state / reverse | 1 / 1 | 0 / 0 |
| Native stores → Posterior / reverse | 2 / 4 | 2 / 4 |

Only Evaluator/Posterior and Native stores/Posterior remain reciprocal. The 11-file SCC has the same members before and after; it contains only the protected evaluator/posterior/mining component.

## Upward references

An upward reference has its source below its target in the brief's exact layer order. Counts use the fixed map's lexical names, not execution frequencies or resolved dynamic calls. Bootstrap is shown separately because it is the composition root.

- Including Bootstrap: 22 → 20 directed upward edges, 76 → 77 names summed by pair.
- Excluding Bootstrap: 15 → 12 directed upward edges, 34 → 35 names summed by pair.

| Lower source → upper target | Before | After |
| --- | ---: | ---: |
| Proof search → Installation | 1 | 1 |
| Posterior → Evaluator | 4 | 4 |
| Statistics → Posterior | 1 | 1 |
| Compiler → Installation | 1 | 0 |
| Compiler → Evaluator | 7 | 7 |
| Compiler → Statistics | 1 | 0 |
| Compiler → Compiler plans | 7 | 8 |
| Search state → Installation | 1 | 0 |
| Search state → Statistics | 1 | 0 |
| Search state → Compiler plans | 0 | 2 |
| Search state → Compiler | 0 | 1 |
| Value store → Evaluator | 1 | 0 |
| Value store → Search state | 3 | 3 |
| Fact store → Proofs | 1 | 3 |
| Fact store → Input journal | 1 | 1 |
| Native stores → API | 2 | 2 |
| Native stores → Posterior | 2 | 2 |
| Bootstrap/ABI → API | 5 | 5 |
| Bootstrap/ABI → Executor | 8 | 8 |
| Bootstrap/ABI → Installation | 1 | 1 |
| Bootstrap/ABI → Proof search | 1 | 1 |
| Bootstrap/ABI → Evaluator | 5 | 5 |
| Bootstrap/ABI → Allowances | 11 | 11 |
| Bootstrap/ABI → Runtime terms | 0 | 1 |
| Bootstrap/ABI → Native stores | 11 | 10 |

Configuration and value-store back edges disappear. Compiler-to-plan descriptor use and fact-reader-to-proof expansion become explicit, so fewer upward pairs do not imply fewer upward names. Native `compileadd`/`query` error labels account for two names; they invoke neither operation. No claim of complete downward layering is made.

## Tokens

Counts use `o200k_base` and the existing `scratch/core_count.py` scope: core is `pettachainer/metta/**/*.{metta,pl}` excluding benchmark/simulation files, plus `pettachainer/*.py`.

| Scope | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Core | 325803 | 325759 | −44 |
| Third-party formula/lowering source | 17685 | 17685 | 0 |
| Ownership/layer documentation | 3659 | 3658 | −1 |
| Rewired Python selector test | 1592 | 1633 | +41 |
| Net core + changed docs + changed test | 331054 | 331050 | −4 |

This required hand-back report and ignored scratch evidence are reporting artifacts, excluded from those totals.

## Validation and comparisons

All runtime/test/benchmark invocations use `ulimit -v 16000000`, unset `DISPLAY` and closed stdin. MeTTa runs use the pinned worktree `.venv/bin/petta` through `scripts/test_metta.sh`. Suite processes use `capped --slots 16` with `PETTA_JOBS=16`; `compare.sh` manages per-run admission itself.

- Step 1 MeTTa suite: **162 passed, 0 failed**.
- Final narrowing MeTTa suite: **162 passed, 0 failed**.
- `scripts/verify.sh`: **PASS**, 272 s; 162 MeTTa checks, 1043 Python tests in 74 files (24 expected failures, 1 nightly skip), lint, import scaling, judgment scaling and ConceptNet. 4554 Python query metric rows, zero aborts. Verify-cache key `c5eca924f35c`.
- `compare.sh master <worktree> --quick`: **PASS**, 130 s; accuracy identical in all 9 measured cases, 0 changed. Both StationOps streams (200 beliefs each) are identical. Report: `/nexus/Dev/OpenCog/bench/results/compare/c1a4bb99_vs_dedb0c38_quick/report.md`.
- `BENCH_TIMING_FULL=1 compare.sh master <worktree> --full`: **PASS**, reserved-host retry 1512 s, 41 runs executed, 4 of 45 selected results reused. Accuracy identical in all 22 measured cases (0 changed); both 200-belief replay streams are identical. Fuzzer: 5 → 5 flagged KBs, no newly flagged seeds, no crashes or unsupported KBs. Report: `/nexus/Dev/OpenCog/bench/results/compare/c1a4bb99_vs_dedb0c38-d56019645_full/report.md`.
- `compare.sh anchor <worktree> --canary`: **PASS**, reserved-host retry 451 s, 6 timing runs, 6 stored accuracy results reused. Accuracy changed in 4 of 6 cases against anchor `b4065459`; the harness's master comparison passes. Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_dedb0c38-d56019645_canary/report.md`.

Anchor error changes are pre-existing on master: live 0.09813 → 0.105, pln-stated 0.3895 → 0.03181, pln-reliable 0.107 → 0.05407, scale m 0.003034 → 0.002647. The report lists nine nonblocking anchor flags shared by master; none is accepted as a new branch regression. No test expectation was changed to obtain this verdict.

The final JSON audit finds no failed or unsupported selected base/candidate/reference record in either full or canary comparison. The strict per-case RSS gate against round baseline master passes: maximum selected increase **0.277%** (216.6 → 217.2 MB, timed b50 s3); no case exceeds +5%. The reliable-case refreshed host comparison is 316.4 → 314.3 MB (−0.66%). Overall full-suite peak rounds to 1501 → 1501 MB. These are the final selected host measurements, not an inference from the harness's looser generic memory threshold.

The initial timing-host attempts used `PETTACHAINER_REPO=<worktree>`, but that host lacks the worktree interpreter path (exit 127). Local accuracy runs completed successfully. Retried with the benchmark's standard interpreter path after verifying its pinned PeTTa hash matches the worktree (`eec735bf4d1d3e31`); candidate code still comes from this worktree's frozen runtime tree `a55c2e63e6d5`. No runner, remote installation or code was changed to handle that path issue.

Scratch evidence: `scratch/struct10-{verify,quick,full,canary}.log` and `struct10-{full,canary}-retry.log`, `struct10-coupling-final.json`, `struct10-reference-{before,after}.json`, `struct10-equations.json`, `struct10-tokens-{before,final}.txt` and `struct10-doc-tokens.json` and `struct10-final-bench-audit.json`.

## Moved test values and limits

The initial mixed local/stored full comparison measured reliable-case RSS at 290.2 → 325.8 MB (+12.27%), above the brief's per-case +5% target despite the harness PASS. That preliminary result was retained in `scratch/struct10-initial-full.json` and motivated the reserved-host refresh; it is not used to claim the strict memory gate.

Against the older anchor, selected case RSS is 32–49% higher; the canary report preserves those measurements and returns PASS under its historical-anchor rules. The strict +5% statement above is against the round's master baseline, not this older anchor.

No expected numeric answer, proof value, budget, assertion strength, or expected-failure marker changed. Only the selector test's construction of the same prefix probes changed.

The external coupling-map artifact could not be fetched; the brief supplies the full layer order, and all reported coupling uses its fixed local script. No evaluator/posterior numerical work, scheduling change, curves, nightly run, push, merge or GitHub write is part of this round. Stop after this hand-back.
