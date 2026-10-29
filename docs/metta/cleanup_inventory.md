# Core cleanup inventory — round 1

Baseline: `6b66c506`, branch `cleanup-1`, 2026-10-29. Count with
`scratch/core_count.py` using `tiktoken` / `o200k_base`: **327,439 core tokens**,
**17,685 third-party tokens**, **345,124 combined**. Core comprises every
`pettachainer/metta/**/*.{metta,pl}` and `pettachainer/*.py`; docs, tests and
nested Python benchmarks/simulations are outside that definition.

The 220K checkpoint and 160K target are later campaign milestones. This round
establishes [core_contract.md](core_contract.md) and removes only proven redundant
code. Token counts below include comments and declarations, not generated
runtime rows. A proposed deletion's footprint is not a promised net saving:
replacement semantics still need code.

## File mechanisms and callers

Paths in the table are relative to `pettachainer/`. Callers are direct semantic
consumers, not the bootstrap import of every file. Shared types and stores have
many readers; their important consumers are named explicitly. “Shared” means
there is already one mechanism to preserve, not a claim that it can be removed.

| File | Tokens before | Mechanisms | Callers | Duplication / disposition |
| --- | ---: | --- | --- | --- |
| `__init__.py` | 131 | Package exports | Python clients/tests | Public export surface |
| `metta/bootstrap.metta` | 1,522 | Native imports, formula imports and ordered compiler/runtime assembly | petta_chainer.metta | Load order is a specialization boundary |
| `metta/compiler/compiler.metta` | 295 | Compiler assembly, mm2compile and mm2compileQuery | ingest.compileadd; query preparation | Public entry points adapt one compiler pipeline |
| `metta/compiler/query_lowering.metta` | 7,746 | Judgment contexts, disjunctive conditional quotient, source/empirical implication readers, Exists query adapters and Assuming plans | compiler.mm2compileQuery; source/rule implication reads | Private implication query/stated namespaces remain alongside ordinary statement keys |
| `metta/compiler/rules.metta` | 19,542 | Forward rule compilation, consequent projections, STV/CTV truth plans, compound priors, instance folds, inversion/completion, refinement, specialization and derived implications | compile_ via mm2compile; query_lowering and skeleton install helpers | Several adapters per source construct; shared evaluator after compilation |
| `metta/compiler/runtime_encoding.metta` | 1,111 | Compiler annotation -> runtime tuple conversion and public proof/result conversion | compiler entries, ingest, query and diagnostics | Internal encoding maps; trivial forwarding helpers are candidates |
| `metta/compiler/source_lowering.metta` | 14,570 | Canonical keys, premise/compound lowering, event-node outputs, producers, settling, existential claims/folds, assumption lowering and context encoding | rules, query_lowering, skeleton, base_rates | Main construct lowering; compile-outputs still owns unique downward event rows |
| `metta/core/logic_config.metta` | 1,203 | Connective modes, settling values, rule forms, specialization declarations | source_lowering, rules, evidence | Public readers/setters remain even with no production callers |
| `metta/core/logic_configs/pln.metta` | 102 | PLN connective/rule-form configuration | Explicit logic selection in tests/examples | Configuration, no evaluator |
| `metta/core/logic_configs/predicate_logic.metta` | 75 | Predicate logic configuration | Explicit logic selection in tests/examples | Configuration, no evaluator |
| `metta/core/types.metta` | 4,220 | Shared wire/domain types and native signatures | Compiler and every runtime module | Shared representation |
| `metta/petta_chainer.metta` | 243 | Public package load entry | Python bridge, tests and examples | Assembly only |
| `metta/prolog/context_overlay.pl` | 4,488 | Scoped store facades, local dependency checks, search seeding, MAIN cold reads, per-world evaluation, cleanup and propagation | Assuming ContextQuery via runtime_helpers imports and evaluator | One value overlay over shared MAIN skeleton; not the private judgment context mechanism |
| `metta/prolog/event_node.pl` | 6,991 | Exact event worlds, Beta/moment integration and conservative numerical fallback | runtime_helpers event_node_* calls; test_event_node.py | Numerical boundary, distinct from compiler lowering |
| `metta/prolog/ingestion.pl` | 4,559 | Source validation, head/arity checking, Member/Inheritance canonicalization and TV kinds | compileadd and query canonicalization; pln_validator | Shared source boundary |
| `metta/prolog/runtime_helpers.pl` | 55,976 | Event-node adapters/independent message integration, indexing, binder identity, proof/evidence/dependency DAGs and collectors, withdrawal provenance, dormancy, instance regimes, hypothesis candidates, compact waiters and pending SCC graph | bootstrap native imports; MeTTa compiler/evidence/skeleton/evaluation/upward/forgetting; sibling native modules | 55,976 tokens; native services share global proof/state identities; split by semantic ownership later |
| `metta/prolog/sorts.pl` | 2,518 | Sort declarations, ingestion sort propagation, stage/stationary classification and hazard-change notifications | ingest, rules, evaluation and hypothesis mining | Indexed classification; no query-driven inference |
| `metta/runtime/backward/diagnostics.metta` | 1,494 | Search/condition/gap diagnostics | Python query diagnostics and public diagnostic entry | Reads current shared skeleton; no alternative inference path |
| `metta/runtime/backward/evaluation.metta` | 100,831 | Leaf/row/merge readers; priors, reports, specificity, overlap, nodes; folds/tallies; exclusions and closed/representative reads; conditioning; propagation/need; materialization/metrics and backward entries | query; upward evaluation; aggregates/forgetting and diagnostics | 100,831 tokens; policy-specific read kernels overlap but cannot yet substitute for one another |
| `metta/runtime/backward/forgetting.metta` | 3,732 | Age/need freezing, aggregate replay eviction, summary provenance, proof/dependency roots | Evaluation lifecycle and public forgetting setters | Historical summaries differ from replayable aggregate eviction |
| `metta/runtime/backward/skeleton.metta` | 32,688 | Node/answer/key registration, private world borrowing, joins, CPU/fold handling, contextualized rules, producer installation, activation, budgeted walk, branch/row retirement | execute-backward; upward joins; query temp cleanup; forgetting | Shared structural engine; only test-only prefilter-head-concludable? proved dead |
| `metta/runtime/backward/upward.metta` | 5,701 | Premise-triggered upward joins, shared evaluation waves, KL agenda and forward copies | Public forward-chain entries; context_overlay seeds | Already shares rows/evaluator; no old independent forward inference engine |
| `metta/runtime/base_rates.metta` | 1,804 | Prior settings, cached user/computed estimates, member folding and cache notifications | Compiler prior goals; aggregates; evaluator; public setters | One estimate per pattern; incremental contribution maintenance |
| `metta/runtime/evidence.metta` | 7,074 | Evidence construction, proof traversal, dominance/containment, signed fact/rule identity | evaluation merge; schema stored facts; forward and materialization | Shared proof semantics; native DAG services underneath |
| `metta/runtime/forward/aggregates.metta` | 6,012 | Base-rate/class-link interest registration, member replacement, cache publication and dirty marks | Ingestion and forward takes; backward fold takes/readers | Physical stored observations and searched member reads feed one tally |
| `metta/runtime/forward/schema.metta` | 1,926 | Trigger/output/aggregate schemas, scoped observations, merged stored-fact readers | aggregates, knowledge_store, skeleton/evaluation and upward | Uses shared sk-merge-facts; no separate merge semantics |
| `metta/runtime/hypothesis_mining.metta` | 4,792 | Observed history, candidate ordering, refined-rule proposals | compileadd / hm-observe!; hypothesis_review | Control-plane model proposals, not a second truth engine |
| `metta/runtime/hypothesis_review.metta` | 2,875 | Truth screening, hypothesis withdrawal and reconsideration | Public review-hypotheses and reconsideration APIs | Uses normal queries, instance truth and native retirement |
| `metta/runtime/ingest.metta` | 530 | Source transaction, lambda evaluation, validation, compilation and journal writes | Public compileadd and Python bridge | Public register-inheritance-induction! no-op is API-protected |
| `metta/runtime/kb_index.metta` | 608 | Fact prefix/open lookup and presence | knowledge_store writers; skeleton/evaluation/aggregates readers | One physical KB with selective lookup indexes |
| `metta/runtime/knowledge_store.metta` | 5,238 | Fact/rule writes, prefix/trigger indexes, expected scores, truth/rate registrations, permanent/temp rule lifetimes and removal | ingest, query-add installation, forward/materialization/forgetting | Shared write boundary; temp retirement cannot be replaced by dropping just rules |
| `metta/runtime/observed_predicates.metta` | 486 | Observed relation declarations and generated gap observations | compileadd | Input modeling |
| `metta/runtime/query.metta` | 3,477 | Single/batch execution plans, canonical/written output shapes, refs retention and scoped cleanup | Public query family / Python bridge | Single and batch have different plan assembly, same run-query-execution-plan |
| `metta/runtime/scheduling.metta` | 1,118 | Expected premise confidence, 0.99 open-proof priority discount, bounded forward agenda and fact assembly | knowledge_store.rule scoring; skeleton priority; upward agenda | 0.99 is scheduling, not TV discount; removal can move finite-budget answers |
| `metta/runtime/skeleton_journal.metta` | 8,514 | Skeleton types/stores, ID state, ingestion journal, input generations and dormancy wake | knowledge_store ingestion; skeleton/evaluation/upward/forgetting | Store schemas shared by downward/upward construction and overlay facades |
| `metta/runtime/values.metta` | 2,857 | Exact match utilities, CPU calling/expected values, stored value/proof predicates | Compiler, scheduling, both chainers and evidence | Shared runtime primitives |
| `pettachainer.py` | 8,149 | Pinned PeTTa bridge, query/add APIs, timing, serialization and proof presentation | Python clients, simulations, benchmarks and tests | Bridge to shared MeTTa APIs; no second inference engine |
| `pln_validator.py` | 758 | Syntax validation adapter | Python callers and tests/test_pln_validator.py | Shares native ingestion validation |
| `query_diagnostics.py` | 1,483 | Diagnostic result decoding | pettachainer.py / Python diagnostics API | Presentation only |

## Evaluator ownership boundaries

The existing section headings are imperfect: the “Coverage of exact folds”
section also owns ordinary merged-value readers. Token footprints are contiguous
source sections, not estimates of what can all be deleted.

| Baseline section (starting line) | Tokens | Main consumers / next ownership boundary |
| --- | ---: | --- |
| Leaves (16), Values (124) | 1,802 | every value reader; shared signed/scoped leaf semantics |
| Prior-factored merge (133) | 8,239 | pair merging, likelihood reads, compound prior/evidence keys |
| Learned combination modes (637) | 2,154 | independent forward-view merging and observed outcome scoring |
| Overlapping views (756) | 25,911 | key merge, specificity, shared-history fallbacks, branch compatibility and leave-one-out support |
| Folds (2361) | 7,761 | scalar/group folds, instance regimes, base-rate changed-member takes |
| Exact coverage and key readers (2841) | 10,203 | partial coverage, ordinary merge, node messages/updates, filtered reads and diagnostic calibration |
| Row views (3497) | 626 | row references and proof normalization |
| Conditioning (3547) | 5,320 | given/pinned/compatible and representative readers |
| Closed reads and row kernel (3889) | 14,163 | completion, unfounded search checks, target claims, premise evaluation and row formulas |
| Evaluation (4770) | 8,728 | change/force propagation and ordered work queues |
| Demand (5318) | 9,896 | need depth/reserve, stale holds, branch/payment tiers and root reads |
| Base-rate API (5923) | 414 | public setters and indexed invalidation |
| Materialization (5950) | 1,202 | materializing query APIs; stored incumbent/proof preservation |
| Metrics (6034) | 478 | diagnostics/bridge |
| Entry points (6074) | 3,753 | root fallbacks and shared execute-backward lifecycle |

A future evaluator should have one row/value kernel with explicit policy inputs;
it must not conflate these existing reader obligations:

| Reader | Entry points | Caller / distinguishing policy |
| --- | --- | --- |
| Ordinary/filtered | `sk-value`, `sk-open-value`, `sk-merge-key` | row and key reads; whole merge then filtered alternatives; cached root eligibility |
| Exclusion rebuild | `sk-rebuild-view`, `sk-branch-values` | rejected ordinary views; paid deferred slice, immutable exclusion cuts, settled/unfinished state |
| Conditioned | `sk-calibrated-value`, `sk-given-merge`, `sk-pinned-value` | row/key claims; shared-statement pins, no evidence for givens, actual-row payment |
| Closed | `sk-closed-read` | complete premises; settlement certificate and unfounded conclusion pins |
| Representative | `sk-representative-value`, `sk-representative-row` | unanswered public roots/closed fallback; bounded replay, no expansion/conditioning/materialization |
| Reference diagnostic | `sk-summary-version`, `sk-cached-summary-version` | filtered premise confidence; endpoint certificate only, not ordinary re-evaluation |
| Population / instance | `sk-rate-read`, `sk-rate-without`, instance fold evaluators | support-aware leave-one-out and tally maintenance; no observation evidence |
| Root | `sk-root-key-value`, `sk-root-values` | answer filters/subsumption, waiting/materialized/population fallback, root-only claims |

## Construct × path map

S = source/compiler `source_lowering.metta`; R = `rules.metta`;
Q = `query_lowering.metta`; E = evaluator; K = skeleton; O = overlay.
“Parallel adapters” identifies a candidate consolidation, not dead code.
All paths eventually use the shared skeleton/evaluator; the differing lowering
and lifetime are the duplication to address.

| Construct | Stored fact / rule conclusion | Rule premise / inversion | Public query / batch | Assuming | Assessment |
| --- | --- | --- | --- | --- | --- |
| Atom, Member, Inheritance | native `member-canon`, R ordinary facts/rules | S `lower`; R MP, inversion and completion | Q `compileQuery`, `query-root`, written-shape restoration | Q ContextQuery -> O shared MAIN structure | One canonical identity already; public spelling adapter must stay |
| Not, double Not | S `canon` complements STV, R canonical additions | S lowers Not with NotFormula; R swaps branches / De Morgan completion | query root strips Not, canonical-results complements output; internal root adapters supply views | canonical assumed key, signed local evidence | Parallel outer/output and internal-view adapters; no independent Not store to delete |
| And | source `compile-outputs` -> event messages/updates/joints plus R strong consequent projections | conjunct-by-conjunct outer antecedent; compound child through S producers; R completion | root key and temporary producers; nested reads share keys | query-context premise adds and MAIN producer discovery; O local values | Output/inverse projection, strong projection and key producer are distinct live paths |
| Or | source event outputs and joints | S producer combines parts/settles; R inversion and completion | root key producer; disjunctive judgment has separate joint/denominator plan | same MAIN key producers with local values | Shared event/part semantics, multiple compiler adapters remain |
| Implication, ForAll | R stores source truth, query STV copies and MP adapters; nested implication export | Q implication read scaffold; permanent K lifetime for premise use; R inversion/refinement | source/derived views + positive/negative hypothetical judgments + empirical instance folds | assumed rule compilation; ContextQuery overlay, private judgments still private | Positive-query namespace still parallels ordinary keys; the separate raw-source namespace was removed in targeted merge 1; producer channels carry different evidence |
| Exists / claim | canonical claim on conclusion, not invented object | S existential direct/witness alternative fold, grouped free variables; residual event node | Q compile-existential-query -> same claim/witness lowering | freshened binder, MAIN member keys with O local values | Multiple entry adapters share claim semantics; keep witness/claim channels and empty subscriptions |
| Compute / distribution comparisons | R/S generated CPU goals and conclusion bindings | S lower; R restricted reversible +/- plan | computation adapters | same CPU goals, scoped input values | Specialization/argument boundaries matter; not an independent inference path |
| FoldAll / Value / Truth / grouped | compiled fold premise and key, never ordinary fact row | S scalar/grouped spec, E member reader/coverage; K search memberships | Q goal adapters to same fold | MAIN member identity, O scoped reads and takes | Exact-fold completeness differs from base-rate / instance estimates and existential disjunction |
| RuleTruth / WithPrior | R truth axiom + instance fold, explicit prior plan | normal fact/CPU key reads with leave-one-out | ordinary query and implication empirical path reuse truth | local truth/tally/cache state where dependent | One parameter engine, but duplicate prior/likelihood planning adapters remain |

The external construct-matrix generator was inspected for its cold/warm/batch,
forward-copy, premise/conclusion and judgment templates. It was not run: the
round deletes an unreachable helper and trivial forwarding functions, not
construct lowering. No fresh matrix correctness claim is made.

## Deletion ledger, ordered by saving per semantic risk

Risk here is about answer and budget movement. Exact net savings are recorded
in `CLEANUP_REPORT.md`; “footprint” is the current source to investigate.

| Order | Mechanism / footprint | Evidence and action | Required proof before larger deletion |
| --- | --- | --- | --- |
| 1 | Test-only `prefilter-head-concludable?` (146 tokens) | Production call count zero; only two direct assertions in `test_structural_conclusion_prefilter.metta`; not in API. Deleted implementation and obsolete tests; live checks moved to `test_missing_input_prefilter.metta`. | Immediate MeTTa suite, final verify/full/canary |
| 2 | `existing-kb-context` (one forwarding function) | Its only production call just brands an already shaped context. Inlined the identical `brand KBContext` in `kbctx`; removed declaration/definition (32 tokens net). No tests directly call it. | Immediate strict MeTTa suite; revert any specialization/answer change |
| 3 | `externalize-proof-structure-list-core` (two forwarding calls) | Only maps `externalize-proof-structure` over its argument. Inlined that same map at its two call sites (53 tokens net); no test/API references. | Immediate strict MeTTa suite and bridge/public-result tests; revert any change |
| 4 | Canonical internal And/Or keys replacing permutations | `node-joint-goals` + `connective_combos` emit permutations; `compile-node-joints` emits a row per goal. Footprint small (~650 native + ~220 compiler tokens), generated-row saving potentially large. **Defer**: reversed keys currently differ; removing permutation before canonicalizing every key loses answers. | Canonical identity in ingestion, rules, all queries/folds, proof/output metadata and scoped caches; unchanged cold/warm/batch results and order/budget behavior |
| 5 | Separate implication source/judgment namespaces | Q 7,746 tokens + R stored-source/scaffold adapters + K context routing; whole files are an upper bound, not additive savings. **Completed in merge 1/1b**: ordinary keys with distinct value policies; shared sample tally and executable-seed filtering. | One implication lowering with producer/lifetime policy; necessary-assumption, world exclusion, ground/non-ground, refinement, Exists and derived-rule tests |
| 6 | `compile-outputs` and parallel strong-projection path | S event-output/joint block ~1.9K tokens plus R projection block; outputs still carry unique Pearl/Jeffrey/joint semantics. **Defer** until unified construct lowering supplies those rows. | All observed/predicted compound, cavity, completion-screening and source evidence cases; no larger EXPECTED_FAILURES |
| 7 | `AndProjection` quotient | One Q live call for disjunctive judgment; formula defined in third_party. **Defer**: deleting it removes P(B and D)/P(D), not merely old downward projection. | Shared event conditional operation with identical denominator key, TV propagation, evidence and zero-probability behavior |
| 8 | 0.99 scheduling discount | One `term-confidence` branch. **Removed in merge 1b** under the relaxed gate; updated scheduler-score pins. | Full benchmark and budget curves with deterministic tie policy; no value changes |
| 9 | Repeated row/value reader kernels | Overlap + closed + conditioned + ordinary-reader sections: large portion of E's 100,831 tokens. **Regenerate from contract**, do not inline through writable row-variable boundaries speculatively. | One policy-parameterized kernel, metered condition/rebuild behavior, quiescence, overlay scope, self-support and reference diagnostics |
| 10 | Native proof/state ownership | runtime_helpers 55,976 tokens. **Split/regenerate** only at actual identities/lifecycle boundaries; event_node is already separate. | Preserve collection roots, native facade idempotence/cache replay and no history scans |

No proven replacement covers the larger mechanisms in this baseline. Removing
them now would delete supported behavior; fewer symbol references alone are not
a redundancy proof. Several zero-production-caller functions are expressly
public (`register-inheritance-induction!`, `current-logic`, `set-compound-mode`,
`chainer-materialize`, and configuration setters): preserve their signatures.
`stored-refs-gc!` is a deliberate complete-collection boundary used by lifecycle
tests; the budgeted production collector is not an equivalent test operation.

## Known behavior / discrepancies to carry forward

These are existing documented limits or static observations, **not bugs fixed
or newly reproduced in this round**:

- The language spec's blanket rejection of direct existential queries is stale
  relative to `compile-existential-query` and `test_exists_queries.metta`.
- `runtime_design_assumptions.md` records variable-headed forward-copy evidence
  overcount, compound implication-part producer overlap, duplicate equivalence
  loss, and connected joint-rate precedence limitations. Preserve values here;
  any correction needs its own oracle-backed change.
- The calibration expected-failure set has 122 entries, including MAIN/Assuming
  differences and zero-confidence omission problems. Do not convert these into
  extra expected failures or suppress their probes during regeneration.
- Source comments place map-semidet/fold-semidet in the old skeleton location;
  their current definitions are in source_lowering. These semidet reduction
  boundaries are live and must not be removed as duplicate library folds.
- A library load emits the pre-existing `sk-merge-facts` defined-after-use warning
  and SWI's yall `/` import warning. Baseline verify passes. These warnings alone
  do not establish an answer bug and are not silently repaired in cleanup.

## Next regeneration sequence

1. Canonicalize internal commutative keys as an explicit compiler/storage
   contract while preserving written output and deterministic proof order;
   then delete permutation row generation completely.
2. Lower each construct once with explicit scope, producer kind and lifetime;
   migrate implication namespaces/output adapters/conditional quotient only
   when the replacement serves every matrix column.
3. Regenerate the value reader and row kernel around explicit filter,
   exclusions, pins, policy and payment; keep mutable row specialization at
   its proven boundary. Separate merge, folds, evaluation and query lifecycle
   into modules below 40K tokens in the actual bootstrap load order.
4. Separate native event adapters, identity/index services, proof storage /
   collection, instance regimes and pending graph by their ownership contract.
   Do not replace indexed delta maintenance with history scans.
5. Count each replacement, delete its old path, and run focused tests plus
   capped required gates before advancing. Target measured net savings,
   unchanged benchmark accuracy and equal/better paired timings.

Round-1 measured result: **327,208 core tokens**, **231 saved (0.071%)**;
third-party stays **17,685**. The three deletions above each have an immediate
strict MeTTa-suite gate; final gate/benchmark evidence and full before/after
per-file counts are in the root `CLEANUP_REPORT.md`. This is contract groundwork,
not attainment of either size milestone.

Final validation: strict MeTTa 161/0 after each deletion; full verify PASS
(967 Python tests, 125 existing expected failures, one skip); full comparison
PASS with no accuracy changes; local-timing anchor canary PASS. A focused
standard paired retime resolved the full report's incomparable conflict
sample: 45.12 -> 44.93 chainer seconds at equal load, identical accuracy.
See [CLEANUP_REPORT.md](../../CLEANUP_REPORT.md) for exact commands, reports,
remote timing failure diagnosis, limitations and every per-file token count.
