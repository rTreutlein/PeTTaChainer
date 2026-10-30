# Structure step 1: vocabulary and runtime policy

Worktree: `.claude/worktrees/struct1`, branch `struct1`, base `575420f4cae42b83d892f4ecc803a58ab669023e`.
Implementation commit: `c3198082` (Move shared syntax and rule policy out of the compiler).
This report and the graph-script revision are committed before final verification.

## Design as built

- `core/vocabulary.metta` owns pure variable traversal, nonbinding head tests, conjunction views, negation canonicalization, context construction, implication classification, computation-head classification, and witness-to-query-pattern conversion, including their local dependencies. It depends on types and primitive collection operations, with no compiler or runtime-policy dependency.
- `core/logic_config.metta` owns the configuration-dependent compound and bidirectional classifiers. They cannot belong to dependency-free vocabulary because they read the selected logic configuration.
- `runtime/rule_policy.metta` owns rule names, evidence registration, given/deterministic/equivalence flags, positive-only/complete predicates, instance-sampling eligibility, refinement policy and context-polymorphic-fact policy.
- `runtime/rate_plans.metta` owns base-rate fold/read plans, variable-sharing partitions, compound-rate composition, antecedent/prior reads and population-prior conversion, including `RatePlan`, `RateUse` and local plan constructors.
- Bootstrap loads vocabulary after collections, then configuration; runtime policy and rate plans load after native declarations and formulas, before the compiler. Actual source/rule/query emitters and encoding remain in the compiler. Early runtime owner modules avoid importing the whole later evaluator/evidence/cache implementation before lowering.

All equations, type signatures and datatypes are unchanged, including per-head clause order. Old definitions were removed in the same change; no aliases or compatibility implementations were added. Public API documentation and signatures are unchanged. No store schema, indexing, reset, scheduling, numerical policy or instruction layout changed. Existing helper boundaries remain because this is an ownership extraction, not an inlining round.

## Static measurement

The retained `scratch/reference_graph.py` and `scratch/reference_terms.pl` build the static name-resolved graph described in the analysis: tracked `.metta`/`.pl` files under `pettachainer/metta`; equation-body expression heads and named collection callbacks; Prolog body calls and standard meta-call goal positions; names resolve across languages; repeated references are deduplicated per caller/callee file. Imports, dynamic calls, generated predicates and store accesses are excluded. The Prolog reader parses terms without consulting project code. This script requires unchanged native sources for a historical baseline, which it checks explicitly.

Reproduce from this worktree:

```sh
python3 scratch/reference_graph.py --revision 575420f4 > scratch/graph-before.json
python3 scratch/reference_graph.py > scratch/graph-after.json
```

| Metric | Base 575420f4 | Extracted |
|---|---:|---:|
| Tracked MeTTa/Prolog files | 47 | 50 |
| Defined names | 1,698 | 1,698 |
| File-to-file edges | 300 | 326 |
| External callee references | 1,330 | 1,367 |
| Reciprocal file pairs | 15 | 13 |
| Largest file SCC | 32 | 33 |
| Runtime/native to compiler file edges | 39 | 9 |
| Runtime/native to compiler callee references | 101 | 14 |
| Runtime/native to source_lowering/rules file edges | 32 | 2 |
| Runtime/native to source_lowering/rules callee references | 89 | 2 |

**87 upward callee references and 30 upward file edges are removed.** The two remaining references into source_lowering/rules are the real emitters `producers` and `compile-implication-instance-adds`, both called from the skeleton. The other 12 references are compiler entry points, query construction/read helpers and runtime/public encoding.

Replacement owner dependencies increase total edges; this round does not claim a global cycle reduction. `compiler/runtime_encoding.metta` leaves the largest SCC, but both runtime owner modules join it, making it 33 files. Vocabulary is outside the SCC. The analysis used an earlier master (4443fe99) and reported 299 edges / 1,325 external references / 100 upward references. The table uses one retained method on this task's actual base and candidate, rather than mixing that historical baseline with current results. The initial exploratory graph omitted some meta-call goal positions; the final retained reader handles them consistently on both sides.

## Behavior checks and moved values

- `scripts/test_metta.sh`: **162 passed, 0 failed**, strict determinism enabled. This includes `test_canonical_keys.metta` and `test_positive_only_user_rate.metta`. Log: `scratch/metta-first.log`.
- `test_specialization_wrappers.py`: **4 tests passed**. Log: `scratch/specialization.log`.
- `scratch/compiled_additions.py`: **28 compiler calls / 134 products identical modulo alpha-renaming**, across five KB configurations: plain, positive-only, complete, refined and query. Covers facts, negation, STV/CTV implications, conjunctions, bidirectional rules, ForAll, existential premises/conclusions, compound queries, implication queries and Assuming. Calls both `compile_` and `mm2compile`, plus `mm2compileQuery`; preserves product order and all constants/instructions. This is a sample, not an exhaustive compiler-equivalence proof.
- Captures: `scratch/compiled-before.json`, `scratch/compiled-after.json`, identical SHA-256 `e5f07d4280e8212876b64efa421a9ee6d429ed8d2b9fcc1ad8eb5427cce90423`.
- A static comparison of all equations/declarations/datatypes against the base confirms identical forms and per-head order.
- **No answer or test fixture value moved.** `tests/` and `EXPECTED_FAILURES` have no diff. There are no numerical derivations to update.
- Existing native `/` import and `sk-merge-facts` forward-use warnings occur on the base too. No new import-order or `unproven_closure` failure was observed.

## Token counts

`scratch/core_count.py`, project `.venv/bin/python`, `o200k_base`:

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core (including Python, as supplied counter defines it) | 321,460 | 321,567 | +107 |
| Third party | 17,685 | 17,685 | 0 |
| Total | 339,145 | 339,252 | +107 |

The small increase is module-interface/load-order documentation and three import declarations. No executable equations were added. Compiler rules shrink from 18,716 to 13,036 tokens; source_lowering from 13,527 to 11,288. Tokens moved to their owners rather than being deleted.

## Benchmark and final gates

All project execution uses `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, `DISPLAY` unset, stdin from `/dev/null`, and this worktree's runtime. Comparisons use the prescribed `compare.sh`, with `PETTACHAINER_REPO` set to this worktree. No custom seeds, frozen builds or runners are substituted.

- Quick comparison: **PASS, accuracy changed in 0 cases**. Report: `/nexus/Dev/OpenCog/bench/results/compare/575420f4_vs_575420f4-dd1164693_quick/report.md`; 69 seconds wall. Log: `scratch/compare-quick.log`.
- `compare.sh master <worktree> --full`: running; final result will be recorded after completion.
- `compare.sh anchor <worktree> --canary`: running; final result will be recorded after completion. Any flagged case requires the brief's paired dev-server retime.
- Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: to run after committing this report. It includes the complete Python and MeTTa suites, lint, scaling and ConceptNet gates.

No scheduling/budget/anytime behavior changed, so curves are outside this brief. The old anchor can differ numerically from the task's master; the no-answer-movement requirement is judged against this task's base. No master/main-checkout/other-worktree code changes, pushes, merges or GitHub writes were made.
