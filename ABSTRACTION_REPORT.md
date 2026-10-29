# Abstraction cleanup report

## Commits and scope

Branch: `abstraction`. Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/abstraction`. Baseline: `d1ee51a7`. Implementation commit:

```text
5a910e2f Extract shared collection and MeTTa syntax operations
```

This report follows in a documentation-only commit on the same branch. `git log --oneline master..abstraction` gives the final two-commit hand-back.

No reserved E3/merge-1b file, public API document, expected-failure declaration, master branch, other worktree, remote Git ref or GitHub object was changed. All runtime, test and benchmark invocations used the repository-pinned runtime through `/nexus/Dev/OpenCog/bench/capped`, with `ulimit -v 16000000`, `DISPLAY` unset and stdin from `/dev/null`. The existing worktree venv was used.

## Diagnosis and design as built

The full audit and ranked candidates are in [docs/metta/abstraction_review.md](docs/metta/abstraction_review.md). There are 43 syntactically recognized recursive list walkers, 44 expanded existence probes and 155 alpha-filtered alternatives. Their enclosing expression sizes are not all removable code. The largest attractive extraction, generic alpha lookup, failed callers despite passing a small direct test. The accepted extraction therefore targets collection mechanics and inert syntax, while retaining the specialized matching boundary.

- `metta/lib/collections.metta`: six pre-existing generic operations moved out of compiler/runtime modules, plus generic `reverse-onto` and short-circuit `any-flat?`. Three typed reverse walkers and five specialized existential list walkers are deleted. Eleven expanded exact-existence probes use the shared operation, quoting open row data explicitly.
- `metta_syntax.py`: one inert tokenizer/parser and one renderer used by validation, diagnostics and proof expansion. The obsolete diagnostic parser/renderer and runtime renderer are deleted; callers and tests use the new library directly.
- Both modules are generic under the brief's counting update: no chainer symbols, independent tests, and useful in a different MeTTa/Python integration. `chainer-first-or` stays in core rather than being labelled generic.

The collection library's contracts cover proper lists, semidet failure propagation, evaluation order, identity membership and short-circuit behavior. The Python library preserves quoted tokens and scientific float syntax. Neither library changes inference policies, budgets, evidence identity, proof shapes, cache ownership or store indexing.

Alternatives rejected or deferred:

- A generic runtime `space-alpha-present?` wrapper changed behavior. Its unquoted version first failed strict loading; explicitly quoting rows fixed loading but failed `test_answers_by_index`, `test_dormant_rules`, `test_forgetting`, and `test_forward_chainer`. The experiment, migrated calls and temporary tests were removed; the next complete MeTTa suite passed. No old/new dual implementation remains. This proves that the tested extraction is unsafe; the precise compiler cause is not established.
- The four remaining typed reverse/append walkers have active callers in the reserved compiler files. They remain as working implementations, with coordinated deletion targets recorded in the audit.
- A general cache-or-compute helper would need a lazy miss path. A strict fallback argument could compute or publish the miss on every hit. No such helper was added.
- Native hash sets, ordered evidence identities, dependency DAGs and scoped mutation have different contracts; cosmetic wrappers would add functions while retaining their real implementations.

## Token accounting

Counts are o200k_base, including comments. Tests, reports and audit documents are outside this production count. Existing third-party code is counted. Moving an operation into a library is not a total saving.

| Group | Before | After | Delta |
| --- | ---: | ---: | ---: |
| Core, excluding separately eligible generic libraries | 326,924 | 325,401 | -1,523 |
| New generic MeTTa library | 0 | 580 | +580 |
| New generic Python syntax library | 0 | 407 | +407 |
| Existing third-party formulas/lowering | 17,685 | 17,685 | 0 |
| **Total** | **344,609** | **344,073** | **-536** |

Net total reduction: **536 tokens (0.156%)**. Core reduction excluding the generic libraries: **1,523 tokens (0.466%)**. This is a small accepted reduction; it does not support a claim that the whole core is now close to its simplest design.

Every changed production file:

| File | Before | After | Delta |
| --- | ---: | ---: | ---: |
| `pettachainer/metta/bootstrap.metta` | 1,522 | 1,531 | +9 |
| `pettachainer/metta/compiler/source_lowering.metta` | 14,538 | 14,033 | -505 |
| `pettachainer/metta/lib/collections.metta` | 0 | 580 | +580 |
| `pettachainer/metta/runtime/backward/skeleton.metta` | 32,542 | 32,419 | -123 |
| `pettachainer/metta/runtime/base_rates.metta` | 1,804 | 1,734 | -70 |
| `pettachainer/metta/runtime/evidence.metta` | 7,074 | 6,821 | -253 |
| `pettachainer/metta/runtime/skeleton_journal.metta` | 8,514 | 8,486 | -28 |
| `pettachainer/metta/runtime/values.metta` | 2,857 | 2,796 | -61 |
| `pettachainer/metta_syntax.py` | 0 | 407 | +407 |
| `pettachainer/pettachainer.py` | 8,149 | 8,051 | -98 |
| `pettachainer/pln_validator.py` | 758 | 561 | -197 |
| `pettachainer/query_diagnostics.py` | 1,483 | 1,286 | -197 |

All other production files are unchanged. The reproducible counting scripts and JSON inventories are retained under this worktree's ignored `scratch/` directory; `scratch/core_count.py .` independently reports the inclusive core as 326,388, third party as 17,685, total 344,073.

## Gates

`capped --slots 16 env PETTA_JOBS=16 scripts/verify.sh`: **PASS**, exit 0, 352 s.

| Gate | Result |
| --- | --- |
| MeTTa lint | PASS |
| MeTTa suite | 162 files passed, 0 failed |
| Python | 969 tests in 60 files; 125 existing expected failures, 1 existing skip; PASS |
| Strict defect stream | 4,430 Python query records and 3 judgment records, 0 aborts |
| Import scaling | PASS; late/early median 1.006, limit 1.500 |
| Judgment scaling | PASS; large/empty inference growth 1.06653, routing/control growth 1.03579 |
| ConceptNet | PASS; expected 2 result rows |

Additional validation: the collection tests passed in a fresh strict pinned PeTTa process importing only standard libraries and `collections`; all three standalone Python syntax tests passed. Successive MeTTa suites were run immediately after accepted simplifications.

Log: `scratch/verify-abstraction.log`. Production source and tests stayed unchanged during this verification. The audit/report documents were written while it ran, so the official runner correctly declined to record a reusable tree cache entry. It did not append to the main checkout's shared verification cache.

## Comparisons

Quick: **PASS**, accuracy changed in **0 cases**, 76 s wall. Report: `/nexus/Dev/OpenCog/bench/results/compare/d1ee51a7_vs_d1ee51a7-d3f8628ad_quick/report.md`.

Full, using the documented local-timing fallback: **PASS**, accuracy changed in **0 cases** (all 22 scored cases identical; 23 entries including the separate reference). The final comparison ran 28 paired confirmation jobs, reused all 45 accuracy results, and finished in 230 s. All 14 initial timing flags were dismissed by paired reruns; no confirmed timing, memory or accuracy regression remains. Every present base, candidate and reference side in the final JSON has exit 0.

Report: `/nexus/Dev/OpenCog/bench/results/compare/d1ee51a7_vs_d1ee51a7-d3f8628ad_full/report.md`.

Selected **paired-rerun metric seconds** (the initial stored-run times remain in the report's main case table):

| Workload | Master | Candidate | Change |
| --- | ---: | ---: | ---: |
| SupplyNet stage 1 b100 s3 | 5.294 | 5.342 | +0.9% |
| SupplyNet stage 3 timed b50 s3 | 15.52 | 16.21 | +4.4% |
| SupplyNet stage 3 untimed soft0.9 b100 s4 | 45.08 | 47.16 | +4.6% |
| Learned stage 3 timed b50 r200 s1 | 23.15 | 24.84 | +7.3% |
| Conflict reliable l spq4 s1 | 72.76 | 64.68 | -11.1% |
| Replay b25 s1 | 5.749 | 5.409 | -5.9% |

These are mixed small timing movements, not a demonstrated overall speedup. None crossed the harness's repeated timing thresholds. Memory stayed essentially flat in the sampled hot cases: stage 3 timed b50, 231.6 to 231.4 MB; timed soft0.9, 253.0 to 252.2 MB. Accuracy, Brier, coverage and regret are unchanged against master. The fuzzer retains the baseline's 6 flagged KBs, error 0.005060085160683605 and 363 answers; both sides report 0 unsupported and 0 crashes.

Canary, local fallback: **PASS**, accuracy changed in **4 of 6 cases versus the older anchor**. These differences are also on master; there is no new anchor-blocking regression. Example inherited live-workload differences are error 0.09813 to 0.105 and regret 59.78 to 72.78. The canary's supporting master comparison dismissed one initial timing flag after a pair. Every final canary side record has exit 0. Wall time was 126 s.

Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_d1ee51a7-d3f8628ad_canary/report.md`.

The original timing-host attempts could not execute this worktree's absolute `.venv/bin/python` path (exit 127); their PASS verdicts were not evidence of remote timing success. The final runs set `BENCH_TIMING_HOST=` and use the same official harness, builds, workloads, seeds and admission pool locally. Logs preserve both attempts. No runner or frozen build was improvised.

Frozen candidate: `d1ee51a7-d3f8628ad`, runtime tree `db4f56bf0016`; pinned PeTTa digest `eec735bf4d1d3e31`. Logs: `scratch/compare-quick.log`, `scratch/compare-full-local.log`, `scratch/compare-canary-local.log`; earlier host failures remain in `scratch/compare-full.log` and `scratch/compare-canary.log`. One trailing blank line in `metta_syntax.py` was removed during final Git whitespace checks after these runs. Its Python AST is identical to the frozen tested module; every other production source file is byte-identical. Token counts are unchanged by this formatting correction.

## Moved test values

**None.** No numerical expected value, proof shape, scheduler score, expected-failure table or skip policy changed. The prefilter tests now invoke `any-flat?` with the existing premise predicate; expected answers are unchanged. Six Python test modules import shared parsing/rendering directly; the diagnostic test module drops those internal imports. The former diagnostic parser test moved into the independent syntax tests with additional malformed-source and native-number checks.

## Limits

The alpha-lookup abstraction is rejected in its tested form, and the precise specialization failure remains a follow-up. Most candidate tokens are in reserved files or semantically distinct computation, not accepted deletions. The extraction changes no scheduler/budget policy, so curves were not required. No universal runtime speedup is claimed; the final comparison's repeated timing verdict is the available performance evidence. Dedicated timing-host execution remains unavailable for this worktree path. No push or merge was attempted.
