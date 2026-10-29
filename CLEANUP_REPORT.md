# Core cleanup campaign — round 1 report

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/cleanup-1`

Branch: `cleanup-1`; baseline: `6b66c506` (`Document the event moment node`).
Runtime code under final validation: `05503518`; subsequent changes are report/inventory documentation only.

## Result and diagnosis

Written contract and inventory completed. Three internal helpers were removed,
with a strict MeTTa-suite gate after each deletion. Core size is **327,439 ->
327,208 o200k tokens: 231 saved (0.071%)**. Third-party remains **17,685**;
combined size is **345,124 -> 344,893**.

This is groundwork and a small safe cleanup. Neither the 220K checkpoint nor
the 160K campaign target is attained. `evaluation.metta` (100,831 tokens) and
`runtime_helpers.pl` (55,976) still exceed the 40K file target. Most large
“duplicate” paths still provide distinct evidence, reader policy or lifecycle
semantics; no shared replacement currently proves them redundant.

The contract describes stores/keys, values/merging, reader policies, incremental
folds, hypothetical and Assuming worlds, budgets, invalidation, retirement and
proof retention. The inventory covers every counted file, construct × path,
evaluator section/reader ownership, and a risk-ordered deletion/regeneration ledger.

## Commits

Each commit is local on `cleanup-1` and carries both brief-specified trailers:

- `b17cfacf` — written evaluator contract and per-file/construct deletion inventory.
- `dd68c82c` — remove the test-only conclusion prefilter; retain missing-input checks under their own test filename.
- `0d420a6a` — inline the one-call context branding helper.
- `05503518` — inline the map-only proof externalization helper at its two calls.
- Final documentation commit — this report plus measured inventory results.

No push, merge, rebase or GitHub write was performed.

## Design and deleted mechanisms

1. `prefilter-head-concludable?`: grep over production, tests and API showed
   its declaration/definition and two direct unit assertions, with **no runtime
   call**. Delete its conclusion lookup (146 core tokens), both assertions and
   their unused Pair-rule fixture. Keep the two live `prefilter-prunes-walk`
   checks in `tests/metta/test_missing_input_prefilter.metta`. The runtime still
   subscribes to missing facts, as the fact-absorption regressions require.
2. `existing-kb-context`: its entire implementation was `brand KBContext`.
   Inline that expression at the sole `kbctx` call (32 tokens). It is absent
   from the public API and has no direct test callers.
3. `externalize-proof-structure-list-core`: its entire implementation mapped
   `externalize-proof-structure` over its argument. Put the same map at both
   callers and delete the wrapper (53 tokens). It has no API/test callers.

No compatibility aliases, dead helpers or new production helpers were added.
Every public API signature is unchanged. No compiler lowering, cache policy,
merge formula or scheduler policy was redesigned.

Rejected for this round: removing the implication namespaces, `compile-outputs`,
`AndProjection`, joint permutations or the 0.99 factor without a replacement.
They are live: output lowering supplies event-node messages/updates, conditional
judgments need their quotient, permutations currently bridge distinct ordered
keys, and 0.99 changes search priority. Their removal now would have unsupported
semantic or finite-budget consequences. The inventory spells out the required
replacement evidence. Typed/reduction boundaries with real compiler semantics
remain in place.

## Token counts per file

Counts use the brief's existing `scratch/core_count.py` and the same
`tiktoken.get_encoding("o200k_base")` per-file calculation. Before counts were
saved before edits; final counts were recomputed from the worktree. Documentation,
tests, scratch and nested Python benchmarks/simulations are outside the core.

| File | Before | After | Saved |
| --- | ---: | ---: | ---: |
| `pettachainer/__init__.py` | 131 | 131 | 0 |
| `pettachainer/metta/bootstrap.metta` | 1,522 | 1,522 | 0 |
| `pettachainer/metta/compiler/compiler.metta` | 295 | 295 | 0 |
| `pettachainer/metta/compiler/query_lowering.metta` | 7,746 | 7,746 | 0 |
| `pettachainer/metta/compiler/rules.metta` | 19,542 | 19,542 | 0 |
| `pettachainer/metta/compiler/runtime_encoding.metta` | 1,111 | 1,058 | 53 |
| `pettachainer/metta/compiler/source_lowering.metta` | 14,570 | 14,538 | 32 |
| `pettachainer/metta/core/logic_config.metta` | 1,203 | 1,203 | 0 |
| `pettachainer/metta/core/logic_configs/pln.metta` | 102 | 102 | 0 |
| `pettachainer/metta/core/logic_configs/predicate_logic.metta` | 75 | 75 | 0 |
| `pettachainer/metta/core/types.metta` | 4,220 | 4,220 | 0 |
| `pettachainer/metta/petta_chainer.metta` | 243 | 243 | 0 |
| `pettachainer/metta/prolog/context_overlay.pl` | 4,488 | 4,488 | 0 |
| `pettachainer/metta/prolog/event_node.pl` | 6,991 | 6,991 | 0 |
| `pettachainer/metta/prolog/ingestion.pl` | 4,559 | 4,559 | 0 |
| `pettachainer/metta/prolog/runtime_helpers.pl` | 55,976 | 55,976 | 0 |
| `pettachainer/metta/prolog/sorts.pl` | 2,518 | 2,518 | 0 |
| `pettachainer/metta/runtime/backward/diagnostics.metta` | 1,494 | 1,494 | 0 |
| `pettachainer/metta/runtime/backward/evaluation.metta` | 100,831 | 100,831 | 0 |
| `pettachainer/metta/runtime/backward/forgetting.metta` | 3,732 | 3,732 | 0 |
| `pettachainer/metta/runtime/backward/skeleton.metta` | 32,688 | 32,542 | 146 |
| `pettachainer/metta/runtime/backward/upward.metta` | 5,701 | 5,701 | 0 |
| `pettachainer/metta/runtime/base_rates.metta` | 1,804 | 1,804 | 0 |
| `pettachainer/metta/runtime/evidence.metta` | 7,074 | 7,074 | 0 |
| `pettachainer/metta/runtime/forward/aggregates.metta` | 6,012 | 6,012 | 0 |
| `pettachainer/metta/runtime/forward/schema.metta` | 1,926 | 1,926 | 0 |
| `pettachainer/metta/runtime/hypothesis_mining.metta` | 4,792 | 4,792 | 0 |
| `pettachainer/metta/runtime/hypothesis_review.metta` | 2,875 | 2,875 | 0 |
| `pettachainer/metta/runtime/ingest.metta` | 530 | 530 | 0 |
| `pettachainer/metta/runtime/kb_index.metta` | 608 | 608 | 0 |
| `pettachainer/metta/runtime/knowledge_store.metta` | 5,238 | 5,238 | 0 |
| `pettachainer/metta/runtime/observed_predicates.metta` | 486 | 486 | 0 |
| `pettachainer/metta/runtime/query.metta` | 3,477 | 3,477 | 0 |
| `pettachainer/metta/runtime/scheduling.metta` | 1,118 | 1,118 | 0 |
| `pettachainer/metta/runtime/skeleton_journal.metta` | 8,514 | 8,514 | 0 |
| `pettachainer/metta/runtime/values.metta` | 2,857 | 2,857 | 0 |
| `pettachainer/pettachainer.py` | 8,149 | 8,149 | 0 |
| `pettachainer/pln_validator.py` | 758 | 758 | 0 |
| `pettachainer/query_diagnostics.py` | 1,483 | 1,483 | 0 |
| **Core** | **327,439** | **327,208** | **231** |
| Third-party | 17,685 | 17,685 | 0 |
| **Combined** | **345,124** | **344,893** | **231** |

## Gates

All commands ran from this worktree. Each command was wrapped in `timeout`,
with `ulimit -v 16000000`, DISPLAY unset, stdin `</dev/null` and the exact
`/nexus/Dev/OpenCog/bench/capped` admission wrapper.

| Check | Result | Evidence |
| --- | --- | --- |
| Baseline `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh` | PASS, 336 s | `scratch/verify-baseline.log` |
| After prefilter deletion: capped strict `scripts/test_metta.sh` | 161 passed, 0 failed | `scratch/metta-dead-prefilter.log` |
| After context-wrapper deletion: same MeTTa suite | 161 passed, 0 failed | `scratch/metta-context-wrapper.log` |
| After encoding-wrapper deletion: same MeTTa suite | 161 passed, 0 failed | `scratch/metta-encoding-wrapper.log` |
| Focused pinned Python bridge suite (`test_pettachainer.py`) | 39 tests, OK | `scratch/python-public-bridge.log` |
| Final `capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh` | **PASS**, 358 s | `scratch/verify-final.log` |
| Final `git diff --check` | PASS | Worktree diff inspection |

Final verification: lint PASS; MeTTa **161 passed, 0 failed**; Python **967 tests
in 59 files**, 125 expected failures and one skip; import scaling PASS; judgment
scaling PASS; ConceptNet PASS (exactly two results). Python query metrics:
**4,430 rows, zero aborts**; judgment scaling: three rows, zero aborts.
The complete suites run inside `verify.sh`; no test runner was substituted.

## Benchmarks

The candidate runtime tree is `514ac095dc01d7e849fa96e940484b6f6d3ce3ac`;
baseline runtime tree `7800d16ea590`; pinned PeTTa runtime `eec735bf4d1d3e31`.
Candidate label `05503518-d2dc7a9ca` includes the documentation diff present when
the standard comparison froze it; the executed runtime is the final committed
production code. `PETTACHAINER_REPO` pointed at this worktree throughout.

**Full comparison with master: PASS.** Exact report line: **“accuracy identical
in all 22 cases.”** There are 23 profile cases: 22 base/candidate comparisons
and one combinet reference. The machine-readable summary reports **accuracy
changed in 0 cases**, 45 executed runs, two stored results reused, 343 s wall.
All 22 base records, 22 candidate records and the reference record exit zero;
none is unsupported. Replay belief streams are identical (200 beliefs each at
b25/s1 and b25/s4). Fuzzer seed 22 / 100 KBs: **6 -> 6 flagged, no new flags,
zero unsupported KBs and zero crashes**.

Full report:
`/nexus/Dev/OpenCog/bench/results/compare/6b66c506_vs_05503518-d2dc7a9ca_full/report.md`

One initial timing flag did not repeat: SupplyNet stage 3 timed b25/s3
**6.324 -> 8.322 s**, paired rerun **5.874 -> 5.579 s**. It is classified as
noise, not a regression. Large-scale spq16/s1 reported **161.8 -> 151.6 s**;
scale suite totals **242.2 -> 227.5 s**. These timings do not establish a
broad speedup: several stored timings were taken at differing pool loads.
The full report's apparent conflict suite increase **81.6 -> 120.5 s** is
dominated by a pln-reliable candidate timing borrowed from the first canary
at a different load. That unresolved comparison prompted the additional
standard-runner targeted paired retime recorded below.

**Anchor canary, local timing: PASS**, six cases, 12/12 successful records
reused. Exact report line: **“accuracy changed in 4 of 6 cases”** (relative
to anchor `b4065459`, not master). The current master has the same differences;
the canary's nested comparison against master reports no blocking regressions.
The anchor rule explicitly treats existing master deficits as non-blocking.
There are nine existing accuracy/timing deficits shared with master, and no
progress-toward-anchor claim.

Canary report:
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_05503518-d2dc7a9ca_canary/report.md`

The first default canary attempted six remote timings on `roman@dev-server`;
they exited 127 because this worktree's `.venv/bin/python` does not exist on
that server. Local workload runs succeeded, but I did not use the nominal
first PASS as complete timing evidence. I reran the **same standard canary**
with the documented `BENCH_TIMING_HOST=` override; its selected base/candidate
records all exit zero and none is unsupported. Initial remote report/JSON are
preserved in `scratch/canary-remote-report.md` and
`scratch/canary-remote-compare.json`. No service or remote environment was edited.

**Focused standard paired retime: PASS, accuracy changed in 0 cases.**
Command suffix:
`--full --only 'conflict pln-reliable l spq4 s1' --retime`.
Both builds ran anew at the **same load (2 slots)**. Chainer seconds:
**45.12 -> 44.93** (-0.191 s); wall seconds **46.24 -> 46.06**; peak MB
**315.8 -> 315.6**; error **0.05407 -> 0.05407** and coverage **1 -> 1**.
The apparent large conflict slowdown did not survive a comparable pair.
No confirmed timing regression remains; this establishes preservation within
the standard benchmark gates, not a general performance improvement.

Focused report:
`/nexus/Dev/OpenCog/bench/results/compare/6b66c506_vs_05503518-d2dc7a9ca_full-conflict_pln-reliable_l_spq4_s1-retime-20261029T075214/report.md`

No test, PeTTa, comparison or wait job started by this run remains active;
the admission pool reported zero rows at hand-back preparation. The final
report/inventory commit changes documentation only after the code gates.

## Moved test values and possible bugs

**No expected truth value, confidence or proof was changed.** The two deleted
assertions expected `true` / `false` from an unused internal helper; they are
removed scaffolding, not moved answers. The live missing-input assertions keep
their original expected `false`. `tests/test_tv_calibration.py` is byte-for-byte
unchanged from baseline: its `EXPECTED_FAILURES` dictionary has **122 entries**.
The complete Python run has **125 expected failures**, including three existing
repeated-query expected failures outside that dictionary.

Existing issues observed in documentation/tests, not repaired or newly isolated:

- The brief's `docs/metta/LANGUAGE_SPEC.md` path is absent. The actual source is
  `pettachainer/LANGUAGE_SPEC.md`; its old blanket statement rejecting direct
  Exists queries disagrees with current compiler support and Exists tests.
- Calibration's expected failures already record MAIN/Assuming mismatches and
  zero-confidence omission problems. For example, the existing P16/K0/A omission
  entry records .7025 in MAIN versus .5000 without the zero-confidence compound.
  This is an existing recorded failure, not an oracle correction made here.
- Runtime design assumptions already record variable-head forward-copy
  evidence overcount, compound implication-part overlap, duplicate-equivalence
  loss and connected joint-rate precedence limits. They need independent
  oracle-backed work if corrected.
- The baseline and final runs emit the existing yall `/` import warning and
  `sk-merge-facts` defined-after-use warning. Passing gates do not establish
  those warnings as harmless in every possible workload; no new failure was
  attributed to either in this round.

## Regeneration work next and limits

1. Give commutative And/Or internal keys a canonical identity across ingestion,
   compilation, fold members, scoped caches and queries while restoring written
   output. Only then delete permutation joint-row generation completely.
2. Define one construct-lowering contract with explicit producer kind, scope
   and lifetime; migrate implication source/judgment/empirical paths and compound
   output/projection/conditional adapters into it. Preserve each independent
   support channel and necessary-assumption restrictions.
3. Regenerate one value/row kernel with explicit exclusions, filter, pins,
   policy and payment. Preserve the proven writable-row compiler boundary,
   root cap, deferred rebuilding, quiescence and scoped aggregate maintenance.
   Separate merge, folds, evaluation and query lifecycle below 40K tokens each.
4. Separate native event adapters, identity/index services, proof/collection,
   regimes and pending graph at ownership boundaries. Retain delta indexing,
   exact variable sharing and cache replay behavior.

The detailed ledger includes footprints, callers, regression families and the
proof required before each larger deletion. No whole large mechanism is proved
redundant in this baseline. This round makes no claim of full-path construct
parity beyond the existing gates, numerical calibration, or broad speedup.
The optional construct-matrix generator was inspected but not run; no new
language construct was introduced. Scheduling/budgets are unchanged, so curves
were not requested or run. Nightly-only tests were not enabled.

All executed PeTTa/test/benchmark commands were admitted through
`/nexus/Dev/OpenCog/bench/capped`, with `ulimit -v 16000000`, DISPLAY unset,
and stdin from `/dev/null`. Tests used this worktree's pinned `.venv` and the
repository runners. No service changes or custom benchmark runners were used.
