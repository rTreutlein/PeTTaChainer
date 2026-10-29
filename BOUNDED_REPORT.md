# Bounded cleanup and specialization report

Branch: `bounded-cleanup`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/bounded-cleanup`.
Starting commit: `f1ca759fc68af833a94e35038c185e1c1a617cbc`.

## Commits

- `35d302fb9b4f60850896bc1586997afd795ae859`: Part A, shared collection operations, compact datatype declarations, and shared premise assembly.
- `6c6a9f03875970ca0d413b56c1ff894437605a54`: Part B, preserve complete normalized rule specifications through specialization, with characterization/regression tests.

Both implementation commits have the two trailers required by the brief. No push, merge, GitHub write, master update, or edit of another checkout was performed.

## Part A: design and evidence

Replaced the four compiler-specific collection walkers with `reverse-onto` and `append-flat`. Deleted all four definitions. The proper-list operations already have strict determinism declarations.

Converted 22 genuine type/constructor declaration groups in the touched compiler and forward-schema files to `datatype`. Kept functions returning those types as function declarations. Constructors and their field signatures are unchanged.

Generalized `append-premise-bundle` by its binary formula. `lower-all` now maps its existing reader over the source parts and folds the resulting bundles through the same assembler used for conjunctions. The assembler initializes from the first nonempty executable bundle, inserts the formula between subsequent bundles, and accumulates goals/proofs in reverse before one final reversal. Existing `lower` versus `lower-part` versus `inline-reading` policies are unchanged; source order and left association are preserved. All actual lowering readers supply nonempty executable bundles. Removed `lower-all-step`.

The requested specialized base-rate descriptor reduction was already present at the starting commit: its descriptor and identity each contain KB and pattern, with no extractor, step, finish or mode fields. `fa-premise-subscriptions` already restricts registration to the standard base-rate fold and its `BaseRateEvidence` initializer. The baseline identity does not contain the initializer itself either; this round preserves that existing representation and does not broaden initialization semantics. The general `finish-aggregate` dispatcher remains intact. The only edit to `aggregates.metta` is its subscription datatype declaration.

Updated the abstraction review to describe the completed collection migration. No API listed in `docs/metta/API.md` changed. The compiler-boundary helpers still needed by their callers remain.

The strict MeTTa suite passed after the walker change, after the datatype conversion, after the shared-assembly change, and on corrected final Part A: **162 passed, 0 failed**. No expected result, proof shape or scheduler score was updated.

Part A full comparison: **PASS**, `accuracy changed in 0 cases`; report says `accuracy identical in all 22 cases`. Both StationOps replay belief streams (200 beliefs each) are identical, maximum shift 0. The comparison ran 23 cases in 281 seconds, including the fuzzer. One preliminary timing flag did not repeat in the runner's paired rerun and was not counted.

Report: `/nexus/Dev/OpenCog/bench/results/compare/f1ca759f_vs_f1ca759f-da34e9ef3_full/report.md`.
Runtime tree: `b85faf446019`, compared with baseline `b170e090577c`.
Log: `scratch/bounded/part-a-full-final.log`.

## Part B: diagnosis, fix and moved results

The suspicion is confirmed. `compile-rule` rebuilt a plain `Implication` for the specialization job, and `emit-specialization` reentered `compile_` with that stripped statement. The second compilation could not recover the original ForAll parameters or WithPrior instance prior.

`compile-specialization` now carries the complete normalized rule specification: parameter variables, prior, and the annotated implication (source proof, sides and TV). Trigger grounding copies that specification together, preserving variable sharing. The emitter invokes `compile-rule` with those retained parameters and prior instead of reentering the source dispatcher with a stripped statement. Its deduplication key is the entire specification. Rule withdrawal removes both templates and completed jobs using the new shape; the existing indexes are unchanged. Ordinary rule compilation keeps its original signature. No alternative specialization path, compatibility implementation, extra store or new helper was added.

An earlier implementation threaded the original source as an extra argument through ordinary compilation. Its full comparison had identical accuracy in 17 judged cases but repeated a stage-4 extension slowdown (20.9 to 24.3 seconds, paired rerun 21.03 to 23.28); it was rejected. The report for that superseded implementation remains at `/nexus/Dev/OpenCog/bench/results/compare/f1ca759f_vs_c07c2cc6_full/report.md`. It is not the final gate result. The final representation keeps the additional metadata inside specialization jobs only.

New tests: `tests/test_specialization_wrappers.py`. They cover structural facts before and after the rule, a universally quantified conclusion-only parameter, an instance prior alone and under ForAll, cohort-specific population priors, and withdrawal/reinstatement both before and after a job emits. The value regressions compare the specialized rule with a corresponding ground, nonspecializing control; proofs must retain the sensor or instance-prior source as appropriate. Withdrawal checks both template removal and completed-job removal by requiring absence after withdrawal and successful reinstatement.

Characterization before the fix is retained in `scratch/bounded/specialization-before.log`: six failing subcases across the first two test methods, for both insertion orders.

| Case | Before | After / ground control | Derivation |
| --- | --- | --- | --- |
| ForAll conclusion parameter | No answer for `(Result cohort a)` | `(STV 0.7300000000000001 0.9103924428821892)` | The parameter is universal rather than a Skolem witness. Modus ponens gives `.8*.9 + .1*(1-.9) = .73`. The same result holds for another parameter value. |
| WithPrior, either alone or inside ForAll | `(STV 0.8181818181818181 0.005026685681629035)` | `(STV 0.33333416192646625 0.9996618432151261)` | The old job lost the instance prior `.1`, using a population fallback. Bayes with the retained prior gives `.9*.1 / (.9*.1 + .2*.9) = 1/3`. The unchanged compound-node pipeline gives the ground control's value, about `8.3e-7` above `1/3`; the regression requires exact equality with that control, not a new posterior/confidence formula. |

The population-prior test additionally requires each ForAll instance to equal its plain rule with the parameter fixed. Two cohorts have different observed cause rates (2/4 and 1/4); the higher-rate cohort must have the higher posterior. This checks the per-parameter base-rate policy separately from universal conclusion handling.

The four new regression methods pass. The final strict MeTTa suite also passes: **162 passed, 0 failed**. Existing expected test values and `EXPECTED_FAILURES` declarations are unchanged. The confidence values above are evidence of agreement with the existing ground-rule implementation, not a new calibration claim.

## Token accounting

Measured with the provided `scratch/core_count.py` / its `o200k_base` encoding over its defined core scope. Detailed snapshots are in `scratch/bounded/part-a-tokens.json` and `scratch/bounded/final-tokens.json`.

| Core file | Before | After Part A | Final | Final delta |
| --- | ---: | ---: | ---: | ---: |
| `compiler/source_lowering.metta` | 14033 | 13486 | 13486 | -547 |
| `compiler/query_lowering.metta` | 6279 | 6245 | 6245 | -34 |
| `compiler/rules.metta` | 19441 | 19349 | 19352 | -89 |
| `runtime/knowledge_store.metta` | 5302 | 5302 | 5318 | +16 |
| `runtime/forward/aggregates.metta` | 5529 | 5519 | 5519 | -10 |
| `runtime/forward/schema.metta` | 1869 | 1802 | 1802 | -67 |
| **Entire core** | **325081** | **324331** | **324350** | **-731** |

Part A saves 750 tokens; Part B adds 19. Prolog and production Python are unchanged (delta 0 in each language). Third-party scope is unchanged at 17685 tokens; combined core plus third-party total goes from 342766 to 342035. The new regression file is under `tests/`, outside the specified core count.

Deleted-symbol audit over `pettachainer/`, `third_party/`, `tests/`, and `docs/`: **zero hits** for all five deleted functions. Audit log: `scratch/bounded/deleted-symbol-audit.log`.

The four reserved files have no diff from `f1ca759f`: `runtime/backward/evaluation.metta`, `prolog/event_graph.pl`, `prolog/event_node.pl`, and `prolog/runtime_helpers.pl`.

## Final gates and limits

Final Python suite: **PASS**, 973 tests in 61 files (588 units), eight workers, 431.0 seconds; 125 expected failures and one skip. Log: `scratch/bounded/final-python.log`.

Final master full comparison: **PASS**, `accuracy changed in 0 cases`; report says `accuracy identical in all 22 cases`. The complete run covers 23 cases, with 43 runs executed and two of 45 results reused, in 399 seconds. Both 200-belief replay streams are identical, maximum shift 0. No timing flags remain. The stage-4 extension timing that blocked the rejected implementation is 22.41 to 23.80 seconds on the final comparison (about +6.2%, below the flag threshold).

Report: `/nexus/Dev/OpenCog/bench/results/compare/f1ca759f_vs_6c6a9f03_full/report.md`.
Log: `scratch/bounded/final-full.log`.
Provenance: base runtime tree `b170e090577c`, candidate runtime tree `68251425116d`; ChainerGame supply `3daf989e93`, replay `d274b45767`; PeTTa runtime `eec735bf4d1d3e31`.

Both final comparison JSON verdicts are PASS, with empty blocking regression lists; all selected base/candidate/reference runs have exit 0 and no unsupported marker.

Final canary: **PASS**, `accuracy changed in 4 cases` relative to anchor `b4065459` (six cases total). The runner applied its comparison with master `f1ca759f` and reported seven inherited, nonblocking deficits also on master; no blocking regressions or accepted exceptions. The final candidate runtime tree is `68251425116d`.

Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_6c6a9f03_canary/report.md`.
Log: `scratch/bounded/final-canary.log`.

| Canary case | Anchor error | Final error |
| --- | ---: | ---: |
| live b50, five shifts, seed 1 | 0.09813 | 0.105 |
| conflict pln-stated, l, spq4, seed 1 | 0.3895 | 0.03181 |
| conflict pln-reliable, l, spq4, seed 1 | 0.107 | 0.05407 |
| scale m, spq4, r10, seed 1 | 0.003034 | 0.002647 |

These are the canary's anchor comparisons, not test expectation changes caused by the specialization fix. Its report includes the remaining metrics and inherited timing flags.

Completed additional gates, each exit 0:

- `scripts/lint_metta.sh`: pass (the runner reports existing warnings without treating them as errors).
- `scripts/check_import_scaling.sh`: pass; late/early median ratio 1.043, limit 1.500.
- `.venv/bin/python scripts/check_judgment_scaling.py`: status PASS.
- `benchmarks/metta/run_conceptnet_own_pet_query.sh`: one summary declaring exactly 2 results.

All PeTTa/test/benchmark invocations used `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, unset DISPLAY and stdin from `/dev/null`. MeTTa suites used `scripts/test_metta.sh` and the worktree-pinned `.venv/bin/petta`; benchmark calls set `PETTACHAINER_REPO` to this worktree. No improvised benchmark runner, seed or frozen build was used.

The mandatory `scripts/verify.sh` has a scope conflict: `scripts/verify_cache.py:62` hardcodes its result store under the main checkout's `.claude/verify-cache/records.jsonl`. The brief also says never touch the main checkout. An explicit question about permitting only that runner-managed cache write is pending; the aggregate wrapper has not been run without that authorization. Individual component results above do not substitute for a recorded verify PASS.

Early interrupted benchmark/Python runs and rejected implementation attempts are not counted as validation. No curves were requested or needed: scheduling, budgets and anytime policies are unchanged. The small compound-node discrepancy against exact Bayes above predates this fix and is outside this bounded round.
