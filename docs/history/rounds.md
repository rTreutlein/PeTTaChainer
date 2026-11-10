# Round reports

Each delegated round handed back a root `<ROUND>_REPORT.md`. The reports stay
in history; read one with `git show <commit>:<ROUND>_REPORT.md` (the commit is
the report's final version). Live design lives in `docs/metta/`.

| Round | Commit | Date | Outcome |
| --- | --- | --- | --- |
| [ISSUE183_LOOKUP](ISSUE183_LOOKUP_REPORT.md) | 0a115264 | 2026-11-10 | Stored compound canonical keys use the ordinary source merge; all gates pass, benchmark TVs unchanged. Child-order normalization remains outside this change. |
| ABSTRACTION | 9102bd1c | 2026-10-29 | Extracted generic collection operations and one shared MeTTa syntax module; -536 tokens. |
| BOUNDED | dbf0bbbb | 2026-10-29 | Compiler list walkers replaced by shared collection operations, declarations moved to `datatype`, specialization keeps the full normalized rule. |
| CLEANUP | 2ad70bdf | 2026-10-29 | Evaluator contract and deletion inventory (`docs/metta/cleanup_inventory.md`, see below); three helpers removed. |
| E3 | a6783416 | 2026-10-29 | Event-node dependence modelled through shared conditional parents in `event_graph.pl`. |
| MERGE1 | 39c1af64 | 2026-10-29 | Partial: separate raw-STV source namespace removed; the one-lowering goal was not reached. |
| MERGE1B | f1ca759f | 2026-10-29 | Implication judgment reads unified and the positive namespace deleted; master's 0.99 open-proof discount kept. |
| MERGE2 | d1ee51a7 | 2026-10-29 | Stopped, documentation only: compound-output audit in `docs/metta/node_outputs.md` (see below). |
| SCC | 80ea5628 | 2026-10-29 | Evaluator split into merge, fold and sampling units with typed reader capabilities to shrink the call cycle. |
| SIMPLIFY_FORWARD | c2f342a7 | 2026-10-29 | Forward base-rate tally made direct; the generic forward sampling framework removed. |
| BOILERPLATE2 | 2b6c42a8 | 2026-10-30 | 86 type groups converted to `datatype`; native entry points declared in one table (`core/natives.metta`). |
| COMPLETION_RECIPE | 3c87d737 | 2026-10-30 | Antecedent-completion recipe stored once per rule instead of on executable inputs; peak RSS back to baseline. |
| POSTERIOR1 | 575420f4 | 2026-10-30 | Checkpoint only: fixture/oracle audit and prior/variance fixes ahead of posterior route deletion. |
| ROUND_METRICS | 4443fe99 | 2026-10-30 | `scripts/round_metrics.py` logs per-landing metrics from `land.sh`. |
| STORE_DECL | c39d127c | 2026-10-30 | One store schema generates all store declarations, bindings and overlay policies. |
| STRUCT1 | 48bdacf5 | 2026-10-30 | Vocabulary, logic configuration, rule policy and rate plans moved out of the compiler. |
| STRUCT2 | a9cd7e1b | 2026-10-30 | Source catalog separated from executable inference applications. |
| STRUCT3 | 3d72b4c6 | 2026-10-30 | Proof semantics recorded as immutable records at construction. |
| STRUCT4A | 84496c3e | 2026-10-30 | One owner for value publication and eviction. |
| STRUCT4B | fbdfe26c | 2026-10-30 | One owner for exposed KB copies. |
| CONFVAR | c3ee6d01 | 2026-10-31 | Round 1 stopped (first-order variance not conservative); round 2 landed the closed-form confidence bound. Measurements in `experiments/confvar/` at that commit. |
| STRUCT5 | ca236838 | 2026-10-31 | Statistical ledger owns the contribution lifecycle. |
| STRUCT6 | 40d329fd | 2026-10-31 | One execution owner for query scopes and allowances. |
| STRUCT7 | 23d62195 | 2026-10-31 | Application discovery separated; owner-to-evaluator cycles broken. |
| STRUCT8 | 13622cf3 | 2026-10-31 | Store ownership completed; reciprocal subsystem pairs 22 -> 5. |
| STRUCT9 | c1a4bb99 | 2026-10-31 | Raw stores layered below readers and installation policy; largest store SCC split. |
| STRUCT10 | 4f639adf | 2026-10-31 | Generic terms and configuration moved out of stores; two-way subsystem pairs 5 -> 2. |
| FIX154 | 6fd4fc88 | 2026-11-01 | Compound settling preserves reader bindings (#154, #151). |
| SUPPORTLIB | 309d2f27 | 2026-11-02 | `terms-unifiable?` and `inference-clock` replaced by `=?` and `current-time`; generic natives moved to `lib/` (core -1,964 tokens). |

## Removed documents

Dated measurement reports, round write-ups and superseded one-off notes that
used to live under `docs/`. Each is at commit `39e41c5e`; read one with
`git show 39e41c5e:<path>`.

The piPLN research material (`piPLN_riposte_draft_v6.pdf`, `research/piPLN/`)
is kept at tag `pipln-archive`.

| Path | Subject |
| --- | --- |
| `docs/metta/core_reduction_2026-09-05.md` | Core MeTTa reduction |
| `docs/metta/performance_review_2026-09-05.md` | Runtime and benchmark review |
| `docs/metta/stationops_regression_2026-09-08.md` | StationOps second-shift regression investigation |
| `docs/metta/stationops_fold_startup_2026-09-08.md` | Cached fold startup experiment |
| `docs/metta/stationops_no_success_prior_2026-09-08.md` | Rule priority without a base-rate success prior |
| `docs/metta/stationops_cost_models_2026-09-08.md` | Cost-model screening after the success prior's removal |
| `docs/metta/stationops_refinement_trace_2026-09-08.md` | Refinement tracing, elapsed-time comparison, depth ablation |
| `docs/metta/stationops_reuse_refinement_2026-09-08.md` | Reuse-first search with a 0-1 refinement budget |
| `docs/metta/stationops_reuse_derivation_2026-09-08.md` | Which derivation gives reuse-only its lower error |
| `docs/metta/stationops_shorter_paths_2026-09-09.md` | Late shorter paths: scheduler experiment |
| `docs/metta/stationops_consumer_views_2026-09-09.md` | Consumer-specific proof selection and continuation validity |
| `docs/metta/stationops_consumer_delivery_2026-09-09.md` | Consumer-specific live proof delivery experiment |
| `docs/metta/stationops_quality_gate_2026-09-09.md` | Original-reference diagnosis quality check |
| `docs/metta/compact_demand_2026-09-09.md` | Compact demand projection experiment |
| `docs/metta/indexed_proof_checks_2026-09-09.md` | Indexed proof checks: combined validation |
| `docs/metta/proof_dependency_cache_2026-09-09.md` | Recursive proof dependency memoization |
| `docs/metta/proof_descriptor_index_2026-09-09.md` | Exact derivation descriptors: behavior and cost |
| `docs/metta/proof_eligibility_cache_2026-09-09.md` | Query-local proof eligibility cache review |
| `docs/metta/waiter_demand_index_2026-09-09.md` | Waiter demand index: behavior and cost |
| `docs/metta/verified_optimizations_2026-09-10.md` | Verified search optimizations |
| `docs/metta/skeleton_answer_index_2026-09-25.{md,json}` | Proof-indexed root answers and session measurements |
| `docs/metta/skeleton_bookkeeping_2026-09-25.{md,json}` | Skeleton evaluation bookkeeping (per-cause forcing cleanup) |
| `docs/metta/skeleton_core_optimization_2026-09-25.{md,json}` | Skeleton-core size, complexity and performance review |
| `docs/metta/memory_census_2026-10-09.md` | Where SupplyNet scale memory goes |
| `docs/metta/typechecker_soundness_followup.md` | PeTTa typechecker repro follow-up (August) |
| `docs/metta/mm2_followup_candidates.md` | mm2-chainer optimization ideas as of 2026-08-06 |
| `docs/metta/scale_l_evidence_paths.md` | Late evidence on SupplyNet scale l, analysis only |
| `docs/metta/equation_dispatch_audit.md` | Repeated equation-head audit |
| `docs/metta/cleanup_inventory.md` | CLEANUP round: core cleanup inventory |
| `docs/metta/implication_lowering.md` | MERGE1B round: one implication lowering |
| `docs/metta/node_outputs.md` | MERGE2 round: compound-output audit |
| `docs/metta/abstraction_review.md` | ABSTRACTION round: abstraction review at d1ee51a7 |
| `docs/metta/forward_learning_design.md` | Forward chaining and learning: smallest retained mechanisms |
| `docs/reviews/history-bug/{report,cache-followup,round3,round4,round5}.md` | Issue 54 exclusion-filtered branch rebuilding, rounds 1-5 |
| `docs/reviews/numeric_retirement_performance_2026-10-15.md` | Numeric retirement performance regression (#23) |
| `docs/demos/lazy_proof_scheduler.html` | August multi-root lazy proof scheduler demo |

Removed Nov 2 2026 (unreferenced, user-approved): docs/metta/search_gain.md, docs/metta/shared_joins.md, docs/metta/hash_foldall_design_note.md, docs/metta/materialized_composed_rules.md, docs/metta/libpln_pettachainer_examples.txt — read with `git show d940bbfa:<path>`.

- simplify-stats (Claude build, Nov 2 2026; A/B vs Codex): Statistics −873 tokens, no behaviour change — `git show fec48dbf:SIMPLIFY_REPORT.md`
- simplify-store (Claude build, Nov 2 2026; A/B vs Codex): Proofs/Fact store/Runtime terms −189 tokens; known edge: empty internal proof values now return false instead of raising — `git show 2e83cfa3:SIMPLIFY_STORE_REPORT.md`
- dupfold164 (Codex build r2, Claude review, Nov 3 2026; issue #164): identical rule replay reuses the installed rule instead of adding another instance-fold producer, −9 production tokens — `git show 2405fc92:DUPFOLD164_REPORT.md`
- rulelookup (Claude build, Nov 3 2026; shared-profile proposal 3): the duplicate `rules` store is deleted and `ccls_index` is the only rule store; ConceptNet query −15.6%, core −192 tokens — `git show e960fb4f:RULELOOKUP_REPORT.md`
- ingestcheck (Codex build, Nov 3 2026; wmtm findings): legacy (Implication (Premises ..) (Conclusions ..)) wrappers and out-of-range STV/CTV values are rejected at ingestion; wmtm canary and disjoint-chain contracts ported, +289 core tokens — `git show fc87826d:INGESTCHECK_REPORT.md`
- fuzzmeta (Codex build, Nov 4 2026): tests/fuzz extended with an exact event reference and metamorphic builder checks; reduced counterexamples for master and routedel2 3a990295 — `git show cd21f586:FUZZMETA_REPORT.md`, evidence `git show cd21f586:experiments/fuzzmeta` (copy in bench/results/fresh-design/fuzzmeta-evidence)
- master-ke-r1 (Codex build, Nov 4 2026; #167 + master fuzzer): certain producer families become one Or template with the consequent's base as fallback, and duplicate children are removed; fuzzer blockers 56 → 6, +199 core tokens — `git show 76f728b3:MASTER_KE_R1_REPORT.md`
- master-ke-r2 (Claude build, Codex parallel reviewer pilot, Nov 4 2026; KE .818 + known-false identity): world parts of an And with a judgment are read as one compound key, evidence-free regions are pruned (constant .5 sources carry no evidence), and every modelled compound reads the graph's answer; KE identity matches exact references, +924 core tokens — `git show e5576e2c:MASTER_KE_R2_REPORT.md`; reviewer tests in bench/results/fresh-design/master-ke-r2-review
- master-ke-r3 (Codex build, Claude parallel reviewer, Nov 4 2026; #148 refinement + width): refined CTV truths are read under the count law inside the graph, and roots that always co-occur fold into exact block parameters (KE 19-part answers), +1,139 core tokens — `git show 0ffc6456:MASTER_KE_R3_REPORT.md`; the shared-population-parameter independence error (also on old master) is a follow-up, see bench/results/fresh-design/r3-sharedparam.md
- master-tooling (Claude build, Nov 5 2026): fuzzer quick gate in verify, tests that checked nothing now check (one real fixture-oracle confidence mismatch marked expected-fail), balanced Python test splitting; verify 346 s → 147 s, no runtime change — `git show 446c03fc:MASTER_TOOLING_REPORT.md`
- master-certain (Claude build, Codex parallel reviewer, Nov 5 2026): c = 1 is an exact point internally (.9999 at the public boundary, stored sources keep 1); all count readers handle c = 1; about 300 pins moved to derived values; +1,564 core and +379 third_party tokens — `git show 4a581ee2:MASTER_CERTAIN_REPORT.md`. Open: the query_many temporal batch is wrong (inherited), and factored-update rounding residue.
- master-batch (Claude build, Codex parallel reviewer, Nov 5 2026): query_many temporal batches now equal sequential queries and the exact oracle; updates over a population base rate combine across fold snapshots (values.metta sk-factored-merge), +8/-3 lines — `git show 6412b2c0:MASTER_BATCH_REPORT.md`. The neutral soft-report channel is deferred to #106.
- master-width (Claude build, Codex parallel reviewer, Nov 5 2026; KE two overlapping reports): the 12-parameter bound is checked after folding (discovery keeps a 256-statement memory guard); graph keys are admitted only by paid reads, and warm budget-0 reads reuse their answers; +418 core tokens — `git show 105a2287:MASTER_WIDTH_REPORT.md`. Deferred: the neutral wide report, cold direct-report batches (#106), shared rates (#168).
- master-dominance (Claude build, Codex parallel reviewer, Nov 5–6 2026; #106 batch loss): a settled step dominates the complete step it settles, so two-root batches keep the descendant answer (mine .9499997, plant-a .864999) and batch = sequential; core net 0 — `git show 77630017:MASTER_DOMINANCE_REPORT.md`. Accepted flag (user, Nov 6): supplynet stage 3 timed b100 s3 degraded error .0039 → .0086, a key master refreshed only by luck (late-fact refresh limit, to be fixed in routedel2); dominance beats master in aggregate over seeds (fresh-design/dominance-seeds-report.md).
- master-168 (Claude build, Codex parallel reviewer, Nov 5–6 2026; #168 shared parameters): one owner-keyed polynomial kernel shares population and refined-rule rates across uses (exact E[N]/E[Z], variance from exact second moments); bits billed and enumerated by one predicate; independent components integrated apart; graph numeric work paid from a budget tier before it is done (no fixed 2^18/2^22 limits); budget 0 refreshes no graph posterior; all 112 shared-rate probe goals exact at KE's steps=200; about +2,200 core tokens (inside the shared #106/#168 estimate) — `git show fe47e919:MASTER_168_REPORT.md`. Inherited and open: installation-order population owner, training-member cavity, budget-0 plan construction; the 12-variable admission and 256-statement discovery limits are to be replaced by cost in routedel2.
- master-169 (Claude build, Codex parallel reviewer, Nov 6 2026; KE #169): a producer joins a key's event model only if its antecedent can match (a positive-only conjunct, ground or open, that no stored fact or assumption unifies with and no rule concludes makes it inapplicable; indexed lookups, no scan); graph work billed at a measured 1/1700 unit per operation (median over nine graph workload families, scripts/calibrate_graph_tariff.py), replacing the guessed 1/256; +226 core tokens — `git show e59bd1dc:MASTER_169_REPORT.md`. KE 50-prefix sweep: all 4/4 at 1000 steps; prefixes 37–50 answer only the joint at 200 steps (graph cost exceeds the budget; cheaper second moments and a leaf fallback deferred to routedel2).
- master-106b (Claude build, Codex parallel reviewer, Nov 6 2026; #106 lost Producing answers): only a fully paid computation settles conditioning debt; an unanswered root reads a waiting answer from rows left without a view, at c=0 when no independent read exists; representative reads are billed to the budget (fixed 256/128 removed); nested conditioned reads wait as debt instead of opening inline claims (depth-64 cap removed). KE replay at 200 steps: timed 396→403/403, error .0145→.0065; untimed 362→375/376, error .0241→.0057; +521 core tokens — `git show ce05fb68:MASTER_106B_REPORT.md`. Accepted by the user (Nov 6): budget-25 answers lost for plant-a t10 and plant-b t20. Follow-ups: batch vs sequential at b4000 (Storm north t15 c .633 vs .9999; up to 6e-4 strength on a few keys), power-plant t19 and plant-b t20 beyond 2 sd (inherited), b76000 stack overflow (inherited).
- master-budgetstatus (Claude build, Codex parallel reviewer, Nov 7 2026; #155 option D): query_many_with_status and MeTTa query-many-with-status report ran-out or did-not-run-out per call, from one always-on cell plus end-of-run reads; no claim of correctness (API.md says so); answers unchanged; +1,028 core tokens — `git show 6306fb6b:MASTER_BUDGETSTATUS_REPORT.md`. Replaced the certifying design (dp-truncation.md, branch master-truncation abandoned at +1,623: KE's ProductDebut never certified). Documented limits: silent need decline and old debt under-report; open branch requests can over-report after a hard call.
- budget-own-A (Claude build, five review rounds, Nov 7–9 2026; #175, #176, #177): the budget owns every replay, generated row and turn: pinned replays run in a paid claim or are owed, only the query's scaffold rows are free (roots' KB-rule rows pay), rows cost by stored size, unpaid work keeps only how to rebuild it, and a deeper payment cannot take a waiting target's root-claim share — `docs/history/budget-own-a.md`. Curves: conflict m s1 best error .0893 → .0896, stage 3 timed s2 .001653 → .001693; #175 case 1 keeps its low-confidence value (recorded, not asserted).
- fc-integrate (Claude build integrating i181-fc-cycle and i180-chain-conf, three Codex review rounds, Nov 10 2026; #180, #181): one inverse-witness exclusion by provenance (an inverse of r excludes the premise keys that set r's own rows at the key it observes apart from other rules' derivations there; relaying rows and refined truths set nothing apart), forward joins register stored premise keys, and forward mode stays on through publication — `docs/history/fc-integrate.md`. #180 cases 3, 4, 6 answer uncle at about (1, .89) with stable re-queries; #181 forward values about (.8, .9) with no invented witness. Open: #180 case 5 still returns [] (expected failure; root fallbacks are master's after every bound on them lost other answers), and a second rule with the same antecedent defeats the exclusion.

- i183-lookup (Nov 10 review fix): stored compound source merge plus a partial part producer using connective bounds; decisive independent parts revise normally, report-derived parts are excluded; deterministic KE pins restored. Two commits on 8538013b; formula, full probe tables, gates, moved values and unposted reply in [ISSUE183_LOOKUP_REVIEW_REPORT.md](ISSUE183_LOOKUP_REVIEW_REPORT.md).

- i183-lookup (Nov 10 midpoint review fix): partial compound evidence reads ((L+U)/2, (1-width)*min(cL,cU)); decisive rows and all 58 prior review outputs unchanged. Five graded before/after rows, derivation, gates and unposted reply in [ISSUE183_LOOKUP_MIDPOINT_REPORT.md](ISSUE183_LOOKUP_MIDPOINT_REPORT.md). Two commits on 8538013b.
