# Structure round 9 hand-back

Branch: `struct9`. Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/struct9`.
Baseline: `13622cf34dfff45f2575d6b05b700e6f28657e1b`.
Runtime implementation: `1ae9060a`; final test wiring: `4275599d`.
Scope: this round only; no posterior work, push, merge or GitHub write.

## Commits

- `8cfa4c17` Separate native term and proof readers from inference services.
- `075c95f3` Layer raw stores below readers and installation policy.
- `1ae9060a` Keep pending graph counters below search retirement policy.
- `4275599d` Point the pending-index differential test at its raw backend.

All commits use the brief's `Co-Authored-By` and `Claude-Session` trailers.
The final documentation/evidence commit contains this report.

## Diagnosis and design

At baseline, the largest call SCC was the 17-file store component listed below.
File ownership mixed primitive hashing with search retirement, immutable proof
reads with evidence construction, structural types with ingestion notification,
and indexed settings with compiler rate plans. Those mixtures created back-edges
from lower storage to reader, catalog, proof and statistics policy.

The implementation moves complete definitions; it does not inline or rewrite
reasoning operations, add callbacks, introduce forwarding aliases, change table
keys, or retain superseded implementations.

- `core/search_terms.metta` owns search/value schemas and node hashing;
  `core/proof_terms.metta` owns assumption and binary-certainty term classifiers.
- `prolog/term_index.pl`, `functional_store.pl`, `proof_terms.pl` and
  `space_store.pl` own key encoding, assigned-key lookup, immutable proof reads,
  raw row mutations and exact waiter lookup. `pending_store.pl` owns raw pending
  components and their work counters. Evidence/dependency/provenance lifetime
  stays in `runtime_state.pl`. None calls reader or inference policy.
- `runtime/store/` contains indexed facts/settings, rule identity, raw input
  epochs/dirty keys, search/value indexes, row removal and allowance frames.
  The only store-to-store call paths are `rows` → `search_index` / `value_store`
  → `journal`. Other store files depend directly on core/collections/natives.
- Fact selection and declaration/completeness policy live in
  `runtime/fact_reads/`; application discovery lives in
  `runtime/application_discovery/`. Native search retirement and listeners live
  above those readers in `prolog/application_support/search_state.pl`.
- `runtime/skeleton_journal.metta` coordinates catalog/dormancy notifications.
  `kb_publication.metta` and `installation_retirement.metta` own supplied-fact
  publication and withdrawal orchestration. Proof evidence policy lives in
  `runtime/proofs.metta`, and view admission in `runtime/evaluator/versions.metta`.
- `user-base-rate?` now belongs to the raw indexed-settings reader. The unchanged
  `source_catalog.pl` therefore reads downward without reaching statistics plans.
  Its template removal likewise reaches the immutable proof-record owner.

The third step checks transitive dependencies: raw search counters originally
still shared a native service with known-fact retirement. Separating their
physical graph prevents a raw store from reaching fact-selection policy through
that native service. The final static reachability audit checks this explicitly.

Alternatives rejected: passing evaluator callbacks into stores would add a new
binding/specialization boundary; merging files would hide rather than remove
layer violations; numerical or scheduling changes would violate this round's
behavior-preservation requirement. Existing named reduction boundaries remain.
`bootstrap.metta` retains the prior relative order of existing implementation
imports; extracted terms/index readers load before their users. Counter
initialization order and every function signature/body are preserved.

## Structural measurements

Both revisions were measured with the unchanged `scratch/reference_graph.py`
and the unchanged current map in `scripts/coupling.py`.

| Metric | Baseline | Final |
| --- | ---: | ---: |
| Largest file SCC | 17 | 11 |
| Largest SCC containing a store | 17 | 1 |
| Nontrivial SCCs containing a store | 1 | 0 |
| File reciprocal pairs | 8 | 1 |
| Files | 81 | 91 |
| Resolved names | 1760 | 1760 |
| File edges | 549 | 626 |
| External name references | 1604 | 1639 |
| Subsystem edges, fixed map | 124 | 117 |
| Cross-boundary functions, fixed map | 638 | 642 |
| Subsystem two-way pairs, fixed map | 5 | 5 |
| Widest interface, fixed map | 41 | 41 |

Largest SCC shrinks 35.3%; the store SCC is completely eliminated. Every store
is a singleton SCC, including through transitive native dependencies. The only
remaining nontrivial SCC is the same 11-file evaluator/posterior component.
File edges and cross-file references grow because definitions now cross explicit
layer boundaries. The fixed subsystem map still groups readers/publishers with
raw fact storage; its five lexical reciprocal pairs and width-41 Fact store
interface remain. No files are unclassified, and no mapping rule was changed.

### Fixed-map reciprocal pairs, before and after

| Pair | Before A → B / B → A | After A → B / B → A |
| --- | ---: | ---: |
| API / Native stores | 1 / 2 | 1 / 2 |
| Evaluator / Posterior | 1 / 4 | 1 / 4 |
| Evaluator / Value store | 22 / 1 | 21 / 1 |
| Installation / Search state | 1 / 1 | 1 / 1 |
| Native stores / Posterior | 2 / 2 | 2 / 4 |

The native/API error-context labels and instruction-name checks still count as
lexical references; protected posterior boundaries remain outside this round.
`docs/metta/module_dependencies.md` lists the final interfaces and storage order.

### SCC lists

Paths below are relative to `pettachainer/metta/`. Every component is listed;
braces identify the non-singleton components. Full edge/name data is retained
in `scratch/struct9-before-graph.json` and `scratch/struct9-after-graph.json`.

#### Before: 55 SCCs

```
{
  core/logic_config.metta
  core/runtime_terms.metta
  prolog/application_support.pl
  prolog/context_overlay.pl
  prolog/ingestion.pl
  prolog/proof_semantics.pl
  prolog/runtime_state.pl
  prolog/source_catalog.pl
  runtime/statistics/plans.metta
  runtime/store/fact_index.metta
  runtime/store/fact_policy.metta
  runtime/store/fact_reads.metta
  runtime/store/journal.metta
  runtime/store/predicate_policy.metta
  runtime/store/proofs.metta
  runtime/store/rule_identity.metta
  runtime/store/schema.metta
}
{
  prolog/event_graph.pl
  prolog/runtime_helpers.pl
  runtime/evaluator/context.metta
  runtime/evaluator/core.metta
  runtime/evaluator/evaluation.metta
  runtime/evaluator/folds.metta
  runtime/evaluator/sampling.metta
  runtime/evaluator/stored_facts.metta
  runtime/evaluator/versions.metta
  runtime/evaluator/work.metta
  runtime/hypothesis_mining.metta
}
bootstrap.metta
compiler/compiler.metta
compiler/query_lowering.metta
compiler/rules.metta
compiler/runtime_encoding.metta
compiler/source_ingress.pl
compiler/source_lowering.metta
core/fold_values.metta
core/logic_configs/pln.metta
core/logic_configs/predicate_logic.metta
core/natives.metta
core/stored_terms.metta
core/truth_values.metta
core/types.metta
core/vocabulary.metta
lib/collections.metta
petta_chainer.metta
prolog/event_node.pl
prolog/event_values.pl
prolog/execution.pl
prolog/sorts.pl
prolog/statistical_ledger.pl
prolog/store_schema.pl
runtime/backward/diagnostics.metta
runtime/backward/execution.metta
runtime/backward/forgetting.metta
runtime/backward/skeleton.metta
runtime/backward/upward.metta
runtime/configuration.metta
runtime/evaluator/formulas.metta
runtime/evaluator/merge.metta
runtime/evaluator/types.metta
runtime/evaluator/values.metta
runtime/hypothesis_review.metta
runtime/ingest.metta
runtime/installation.metta
runtime/observed_predicates.metta
runtime/presentation.metta
runtime/query.metta
runtime/scheduling.metta
runtime/statistics/aggregates.metta
runtime/statistics/base_rates.metta
runtime/statistics/ledger.metta
runtime/store/allowances.metta
runtime/store/application_policy.metta
runtime/store/applications.metta
runtime/store/contracts.metta
runtime/store/publication.metta
runtime/store/retirement.metta
runtime/store/rows.metta
runtime/store/search_index.metta
runtime/store/value_store.metta
runtime/values.metta
```

#### After: 81 SCCs

```
{
  prolog/event_graph.pl
  prolog/runtime_helpers.pl
  runtime/evaluator/context.metta
  runtime/evaluator/core.metta
  runtime/evaluator/evaluation.metta
  runtime/evaluator/folds.metta
  runtime/evaluator/sampling.metta
  runtime/evaluator/stored_facts.metta
  runtime/evaluator/versions.metta
  runtime/evaluator/work.metta
  runtime/hypothesis_mining.metta
}
bootstrap.metta
compiler/compiler.metta
compiler/query_lowering.metta
compiler/rules.metta
compiler/runtime_encoding.metta
compiler/source_ingress.pl
compiler/source_lowering.metta
core/fold_values.metta
core/logic_config.metta
core/logic_configs/pln.metta
core/logic_configs/predicate_logic.metta
core/natives.metta
core/proof_terms.metta
core/runtime_terms.metta
core/search_terms.metta
core/stored_terms.metta
core/truth_values.metta
core/types.metta
core/vocabulary.metta
lib/collections.metta
petta_chainer.metta
prolog/application_support.pl
prolog/application_support/search_state.pl
prolog/context_overlay.pl
prolog/event_node.pl
prolog/event_values.pl
prolog/execution.pl
prolog/functional_store.pl
prolog/ingestion.pl
prolog/pending_store.pl
prolog/proof_semantics.pl
prolog/proof_terms.pl
prolog/runtime_state.pl
prolog/sorts.pl
prolog/source_catalog.pl
prolog/space_store.pl
prolog/statistical_ledger.pl
prolog/store_schema.pl
prolog/term_index.pl
runtime/application_discovery/plans.metta
runtime/application_discovery/policy.metta
runtime/backward/diagnostics.metta
runtime/backward/execution.metta
runtime/backward/forgetting.metta
runtime/backward/skeleton.metta
runtime/backward/upward.metta
runtime/configuration.metta
runtime/evaluator/formulas.metta
runtime/evaluator/merge.metta
runtime/evaluator/types.metta
runtime/evaluator/values.metta
runtime/fact_reads/declarations.metta
runtime/fact_reads/policy.metta
runtime/fact_reads/selection.metta
runtime/hypothesis_review.metta
runtime/ingest.metta
runtime/installation.metta
runtime/installation_retirement.metta
runtime/kb_publication.metta
runtime/observed_predicates.metta
runtime/presentation.metta
runtime/proofs.metta
runtime/query.metta
runtime/scheduling.metta
runtime/skeleton_journal.metta
runtime/statistics/aggregates.metta
runtime/statistics/base_rates.metta
runtime/statistics/ledger.metta
runtime/statistics/plans.metta
runtime/store/allowances.metta
runtime/store/contracts.metta
runtime/store/fact_index.metta
runtime/store/fact_settings.metta
runtime/store/journal.metta
runtime/store/rows.metta
runtime/store/rule_identity.metta
runtime/store/schema.metta
runtime/store/search_index.metta
runtime/store/value_store.metta
runtime/values.metta
```

## Behavior and tokens

`scratch/struct9_equivalence.py` compares baseline and final native clauses per
predicate/arity, including clause order, and all MeTTa equations, signatures and
datatype forms as parsed terms. Result: 608 native predicates and 950 native
clauses in both revisions, zero changed predicates; zero added/removed MeTTa
forms. It also asserts all stores are singleton SCCs and that their transitive
callees contain only lower stores, core terms, collections and native storage.
The audit excludes Prolog directives; their movement and bootstrap composition
are covered by inspection and runtime gates.

`prolog/event_*.pl`, `prolog/source_catalog.pl`, public API signatures and
`scripts/coupling.py` are unchanged. No symbol was deleted, and no expected test
value or expected-failure set changed. The pending-index differential test now
consults `pending_store.pl` and its `term_index.pl` dependency instead of the
old combined `runtime_state.pl`; its four random seeds, graph sizes, step counts
and BFS-oracle assertions are unchanged. Existing reduction boundaries remain.

Core o200k tokens (`scratch/core_count.py`): **325654 → 325803, +149 (+0.046%)**.
Third-party tokens stay 17685; total **343339 → 343488**. The additional tokens
are ownership comments, module imports and raw-state declarations; no new
runtime function or algorithm was added.

## Gates and benchmarks

All required gates pass. Runtime tree: `407bccc16908` at `1ae9060a`;
`4275599d` only repairs direct native imports in the differential test.
Docs/report-only diffs explain the benchmark build-label suffixes and do not
alter the runtime tree.

- `scripts/verify.sh`: **PASS**, exit 0, all six gates, 229 s wall; 162 MeTTa
  cases and 1043 Python tests in 74 files (24 expected failures, one nightly
  skip). The Python metric stream contains 4554 queries with zero aborts;
  judgment scaling has three more with zero aborts. Import scaling ratio 0.986
  (limit 1.5); judgment scaling and ConceptNet pass. Verify-cache PASS key
  `f4cae21bde9c`. Log: `scratch/struct9-verify-final2.log`.
- `compare.sh master <worktree> --full`: **PASS**, exit 0; `accuracy changed in
  0 cases`, identical in all 22 build-to-build cases. The profile has 23 records
  including its standalone CombiNet reference; 43 runs executed and 2/45 results
  reused, 769 s wall (including the machine-wide comparison queue), 1642 CPU-s.
  Every selected base/candidate/reference run exits 0. No regression or false
  timing flag. Both replay streams retain all 200 beliefs exactly (zero changed,
  zero maximum shift). Fuzz `all n100 s22` retains the same five flagged KBs,
  with no newly flagged KB, unsupported KB or crash.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/13622cf3_vs_1ae9060a-dfebf4056_full/report.md`.
  Log: `scratch/struct9-full-final.log`.
- `compare.sh anchor <worktree> --canary`: **PASS**, 6 cases, 12 attempts,
  6/12 results reused, 271 s wall. `accuracy changed in 4 cases` versus the
  older anchor, with no blocking regressions. The report records seven existing
  deficits also present on master and one timing improvement toward the anchor;
  changes versus this round's baseline are judged by the full master comparison.
  All six selected candidate runs exit 0. The standard harness fell back to
  local runs after its timing-host attempts exited 127.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_1ae9060a-d984b53f1_canary/report.md`.
  Log: `scratch/struct9-canary-final.log`.

The first final-code verify run (`scratch/struct9-verify-final.log`) passed five
gates but failed the Python gate because the differential test consulted the old
combined native source. After rewiring its imports, the focused check passed
(1 test, four graph seeds; 0.414 s). The complete verify rerun uses the final test
wiring; no expected values, seeds or assertions were changed.

All runtime/test jobs use the pinned worktree environment, admission-capped
execution (16 slots/PETTA_JOBS for verify), `ulimit -v 16000000`, DISPLAY unset
and stdin from `/dev/null`. `compare.sh` supplies its own admission-capped runs.
Intermediate MeTTa checks each passed 162/162. Superseded validation on
`075c95f3` was stopped/reaped before the final pending-store split; its partial
Python and benchmark results are not claimed as final gates. No superseded job
was left running. Only standard comparison profiles were used; scheduling and
budgets did not change, so no curves were requested or run.

### Strict RSS gate and measured changes

The brief's +5% RSS limit was checked independently of the standard harness's
looser 35%/300 MB threshold. Every one of the 22 paired cases passes; the maximum
increase is **+0.3425%**, `learned stage 3 timed learned b50 r200 s1`,
292.0 → 293.0 MB. The overall largest peak is 1499.2 → 1498.8 MB.
Selected-run data and the computed ratios are retained in
`scratch/struct9-benchmark-acceptance.json`.

| Case | Base RSS MB | Candidate RSS MB | Change |
| --- | ---: | ---: | ---: |
| learned stage 3 timed learned b50 r200 s1 | 292.0 | 293.0 | +0.342% |
| learned stage 3 timed learned b50 r200 s2 | 295.3 | 296.2 | +0.305% |
| supplynet stage 4 extend b50 s2 | 229.7 | 230.2 | +0.218% |
| scale l spq4 s1 | 989.7 | 991.5 | +0.182% |
| supplynet stage 3 untimed b100 s4 | 211.9 | 212.2 | +0.142% |
| supplynet stage 3 timed b50 s3 | 216.2 | 216.5 | +0.139% |
| fuzz all n100 s22 | 156.9 | 157.1 | +0.127% |
| replay b25 s1 | 225.9 | 226.1 | +0.089% |
| replay b25 s4 | 226.6 | 226.8 | +0.088% |
| conflict pln-sources m spq4 s2 | 256.1 | 256.3 | +0.078% |
| supplynet stage 3 untimed soft0.9 b100 s4 | 227.7 | 227.8 | +0.044% |
| supplynet stage 1 b100 s3 | 177.5 | 177.5 | +0.000% |
| supplynet stage 3 timed b100 s3 | 224.7 | 224.7 | +0.000% |
| scale l spq16 s1 | 1499.2 | 1498.8 | -0.027% |
| conflict pln-sources m spq4 s3 | 262.5 | 262.3 | -0.076% |
| supplynet stage 3 untimed b25 s4 | 189.6 | 189.4 | -0.105% |
| supplynet stage 3 timed b25 s3 | 197.8 | 197.5 | -0.152% |
| scale s spq1 s1 | 168.2 | 167.7 | -0.297% |
| supplynet stage 3 timed soft0.9 b100 s3 | 254.8 | 254.0 | -0.314% |
| learned stage 3 untimed learned mined b50 r50 h10 s3 | 629.4 | 627.4 | -0.318% |
| combinet n2 s1 | 147.0 | 146.4 | -0.408% |
| conflict pln-reliable l spq4 s1 | 325.2 | 290.2 | -10.763% |

The full report's suite totals (inference seconds and maximum RSS per suite)
are below. These paired observations support no regression; no algorithmic
speedup is claimed from timing fluctuations in a definition-move refactor.

| Suite | Base s | Candidate s | Base peak MB | Candidate peak MB |
| --- | ---: | ---: | ---: | ---: |
| supplynet | 162.7 | 166.8 | 255 | 254 |
| scale | 191.8 | 191.6 | 1499 | 1499 |
| conflict | 100.2 | 89.1 | 325 | 290 |
| learned | 127.0 | 123.7 | 629 | 627 |
| replay | 10.0 | 9.8 | 227 | 227 |
| combinet | 0.8 | 0.8 | 147 | 146 |
| fuzz | 59.0 | 54.0 | 157 | 157 |

## Reproduction

From this worktree:

```bash
python3 scratch/reference_graph.py --revision 13622cf3
python3 scratch/reference_graph.py --revision 1ae9060a
python3 scripts/coupling.py 13622cf3 --json
python3 scripts/coupling.py 1ae9060a --json
python3 scratch/struct9_equivalence.py
.venv/bin/python scratch/core_count.py .
```

Native graph/equivalence parsing loads no project runtime. The runtime gates and
comparisons use the exact wrappers described above and in `docs/agent_workflow.md`.

## Limits

This is a file/name-resolved structural result, not a claim that the entire
inference engine is acyclic. The existing evaluator/posterior SCC remains.
The graph omits imports, physical store references, generated predicates and
dynamic calls. The fixed coupling map measures lexical names and aggregates
several layers; its width/pair counts do not establish a cycle within raw stores.
No posterior semantics, evidence identities, finite-budget behavior or source
catalog implementation was intentionally changed. All 22 build-to-build accuracy
comparisons and all strict per-case RSS checks pass. This is evidence for the
covered workloads, not a new numerical correctness claim. The older anchor's
four pre-existing accuracy differences remain documented above. All jobs started
for this round have completed or were stopped and reaped; no next round began.
