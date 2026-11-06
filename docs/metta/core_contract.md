# Backward evaluator contract

This is the normative contract for the evaluator in `runtime/evaluator/`,
`runtime/backward/skeleton.metta` and `prolog/runtime_helpers.pl`. Preserve the public
signatures in [API.md](API.md), answers, proof/evidence identity and budgeted
behavior. A replacement must replace its old mechanism completely.

Sources: [runtime_design_assumptions.md](runtime_design_assumptions.md), the
repository's [LANGUAGE_SPEC.md](../../pettachainer/LANGUAGE_SPEC.md), and the
regression families named below. The brief's `docs/metta/LANGUAGE_SPEC.md` does
not exist at baseline `6b66c506`; the package file is the actual specification.
Where that file's older limitations disagree with current tests (for example
bare Exists queries), preserve the tested behavior and record the discrepancy.
This contract does not authorize numerical corrections or broader language support.

## Identity and storage

- Normalize Member/Inheritance recursively on entry. Negations use their
  underlying canonical statement and signed STV; Exists uses a canonical
  `ExistentialClaim` with binder slots. Restore the written answer shape at
  output. Syntax dispatch must inspect heads without binding variable heads.
- A fact key is `sk-key(statement, (KB, context, parameters))`; folds, groups,
  compound priors and compound-evidence reads have distinct key constructors.
  Preserve variable sharing and distinguish unification from alpha identity.
- Keep logical knowledge append-only. Multiple proof names are evidence;
  the same name/statement cannot acquire a different TV. Configuration is
  replaceable. Rule withdrawal, temporary worlds and forgetting have their
  explicitly defined lifetimes; cache eviction is not logical retraction.
- Nodes hold goal patterns, answers link nodes to keys, partial joins hold
  premise bindings, and rows hold complete rule instances without TVs.
  A row belongs to its conclusion key, independent of a reader's proof/TV
  filter. Preserve an open premise key when later premises bind its variables.
- Exact tables use selective first columns and collision-checked full keys.
  Never hash a pattern index as though it were an exact map. Erase a selected
  open row by exact clause reference or unique ID, not by unifying retraction.

| State | Lookup key and lifetime | Required readers/writers |
| --- | --- | --- |
| `&kb`, `&kb_prefix`, `&kb_open` | canonical statement/context/proof; prefixes of ground arguments; authored lifetime | ingestion, leaf reads, forward copies, materialization |
| `ccls_index`, `prem_index`, `&prem_prefix` | structural conclusion (the rule store; rule ID second), premise prefix | compilation/storage; downward and upward joins |
| `&sk_expanded`, `&sk_node_terms`, `&sk_answer` | node hash plus exact pattern; answer key | search and late activation; durable except retired/context-local nodes |
| `&sk_keys`, `&sk_key_*`, `&sk_reader_*`, `&sk_unifiers` | key hash/exact key and statement prefixes | key registration, matching readers and self-support cuts |
| `&sk_wait`, native payloads/templates, `&sk_child`, pending components | awaited node and exact continuation; owner/conclusion leases | search delivery and bounded retirement; structure shared by Assuming |
| `&sk_row`, `&sk_use`, `&sk_reader`, `&sk_stale_reader` | conclusion key/row hash; input key -> consumer | construction, evaluation, change propagation and retirement |
| `&sk_view`, `&sk_latest`, `&sk_support`, `&sk_merged` | key/row; retained versions; merged dependency union and root policy | all value reads; values scoped through overlay facades |
| `&sk_fold`, `&sk_member_of`, `&sk_group_of`, `&sk_rate_dirty` | fold/member identity; changed-member index | fold discovery, replacement takes and exact-fold coverage |
| `&forward_aggregate_*`, base-rate cache | aggregate/pattern and member key | ingestion/forward seeding and backward folds; scoped publication |
| `&sk_instance_*`, `&sk_sample_*`, `&sk_truth_fold` | fold, member, regime and source identities | rule-truth tallies and indexed leave-one-out reads |
| `&sk_branch*`, pending/granted conditions, holds | row slot, exact exclusion context and cuts | paid rebuilding; ordinary views remain independently valid |
| `&sk_needed`, `&sk_new`, queues, forced causes, roots | query/evaluation, per world | scheduling only; no invented evidence |
| `&sk_world_*` | private borrowing key and MAIN lookup prefix | late observation/projection delivery and unpaid refresh paths |
| `&proof`, interned evidence/dependencies, rule provenance | durable IDs, immutable DAG/set nodes | all views and output; metered collection traces surviving holders |
| `&sk_forward_stored`, `&sk_summary`, `&sk_aggregate_row` | exact key and provenance | copied incumbents, historical summaries, replayable aggregate eviction |
| `&query_proofs`, summary/representative memos | latest reference batch or current query, including actual pins/filter/cuts | output retention and bounded fallback; replace on next query |

## Value and merge rules

1. A row view carries fact/CPU result, proof reference, interned evidence ID
   and transitive dependency ID. Proof IDs form a DAG and are never reused.
   Materialized and forward copies retain their computed source identities.
2. A consumer excludes its own key and unifying keys transitively. Choose
   each row's latest admissible version, retaining older admissible versions.
   Filters apply to the whole merged value first, then admissible alternatives.
   A derived-implication producer filter applies before merging producers.
3. Stored confidence-one facts take precedence as Jeffrey beliefs at their
   strength. Only ground binary-certain stored facts retire search. Derived
   confidence-one predictions do not get that retirement privilege. Ignore
   zero-confidence placeholders when informative alternatives exist.
4. Merge in stable order: certain/complete and dominating steps first;
   same-proof evidence once; specificity before aggregation; independent
   reports by revision; reports update independent predictions by likelihood
   odds. Prior-factored updates apply their shared prior once. Preserve
   evidence/dependencies even where a component discards a candidate.
5. Syntactic containing conditions determine specificity, not confidence.
   Same-class estimates revise; nearest incomparable classes form a mixture.
   Shared uncertain observations/dependencies require conditioning or the
   documented conservative approximation. Shared rule parameters and binary
   certain givens alone do not establish observational dependence.
6. Observed compounds send Pearl likelihood messages; predicted compounds
   apply ordered Jeffrey updates after other views merge. Read sibling cavities
   without the compound/target feedback. Preserve joint, repeated-atom,
   completion-screening and evidence-deduplication semantics. A completion is
   a Bayesian observation update, not an unconditional projection.
7. Stage inversions/completions consume observations from below, not forward
   predictions; aggregate statements retain PLN induction/abduction. Sorts
   come from declarations/ingestion, never questions or assumptions.
8. Use the documented prior centre, heterogeneity weight and support exclusions.
   Do not substitute raw tally snapshots for leave-one-out reads. STV rules'
   unknown negative branches remain unknown; explicit CTV branches remain
   explicit. Learned positive truths are not reconciled with their own samples
   again. Preserve certified zero likelihoods and provisional-fold discounts.

## Readers, folds and worlds

- Ordinary, filtered, conditioned, closed, representative and root reads all
  obey the same source identity, liveness and self-support exclusions. Their
  differences are evaluation policy, pins and payment, not separate knowledge.
- Complete predicates become unfounded only after search settles. A budget
  cut is not false. Closed reads retain actual pins; pins are not observations.
- Exact folds report partial coverage until members/search settle. Provisional
  results yield to complete alternatives. Population/instance folds carry no
  member evidence or transitive member dependencies; exact data folds and
  existential witness judgments retain their specified provenance.
- Base rates replace one member contribution, never double count it. Addition
  preserves computed estimates; only interpretive configuration changes dirty
  their indexed readers. Population need visits changed members only. A fold
  excludes its own feedback and consumes only its own cache notification.
- Instance folds exclude self-confirming rules/refined truths. Leave-one-out
  subtracts indexed affected samples. Stationary rules pool frequencies;
  stage rules retain bounded regime hypotheses and arrival order on rebuild.
- Exists direct claims and witness folds meet at one claim key. Empty witness
  judgments remain subscribed and unanswered, except the residual's explicit
  empty identity. Correlated witnesses retain a conservative chosen proof and
  all member dependencies. Binder freshening preserves free variables.
- Implication judgments require the antecedent dependency. Borrow other MAIN
  observations, never the consequent or its instances/negation. Assumed keys
  override world values. Hypothetical individuals cannot bind world individuals.
  Keep independent empirical and hypothetical support channels distinct.
- Assuming shares MAIN rows/search but owns dependent values, assumptions,
  cache maintenance and aggregate writes. Independent cold reads execute in
  MAIN. Overlay facade writes/reads enforce scope; cleanup removes dependent
  state without discarding independent MAIN work. Each world gets its own
  evaluation allowance/reserve after shared batch search.

## Scheduling and lifetime invariants

- Ingestion journals bounded indexed work; it does no inference or history
  scan. Activate matching late facts/rules before search. Missing fact joins
  retain subscriptions. Expanded nodes do not restart all rules on fact arrival.
- Search is deterministic best-first over pending components. A warm walk
  visits paths to work only; cycles use component accounting. Preserve root
  order, tie order, free fact/compound expansions and term-growth subsumption.
- Charge expansions/large terms explicitly; row creation has its own allowance
  (ten per step, roots exempt) and late facts their activation allowance.
  Unfinished work resumes under its owner, not an unrelated query's budget.
- Need is breadth-first at minimum root depth. Compound producer rows remain
  at the consumer's depth; population members follow ordinary need. Evaluate
  near rows first, then deeper rows by depth and creation order. Near-root
  reserve is bounded (eight per reached item); ordinary allowance is two per
  step. Determined binary rows retain their separately specified free update.
- Stale rows keep views and unlink current readers. During evaluation, needed
  readers remain linked; held staleness propagates after answers. Admit new
  support, forced changes and the specified new uncertainty-source correction.
  Force each row once per cause per evaluation/world; folds do not renew causes.
- Conditioning uses remaining ordinary allowance, never near reserve. Charge
  actual conditioned rows, including nested/weight reads, two per unit. An
  incomplete pass cannot replace a completed result. Deferred rebuilding uses
  at most one eighth of that same allowance; cuts and exclusions remain intact.
- Root-only deep claims use one eighth, capped at 256 units. Exhausted full
  slices sleep until a new KB input generation or larger slice, without
  declaring settlement. Nested deep history keeps its marginal approximation.
  Representative output fallback is paid from the evaluation allowance:
  before conditioning, each root without a value buys its waiting answer from
  an equal share of what is left, roots without a population prior first; it
  cannot expand, materialize, or buy conditioning.
- On unchanged inputs sufficient repeated budgets must reach quiescence:
  zero row computations and branch builds after pending work finishes.
- Query producers/scaffolds retire with all their rows, deferred work, waiters,
  views and private state. Permanent fold-shape/class-link producers and
  implication-premise scaffolds keep their necessary lifetime. Never reuse a
  temporary rule ID while a deferred join can still refer to it.
- Withdrawal follows indexed provenance to exposed copies and excludes retired
  derivations on every read. Forgetting replays aggregate readers; it cannot
  freeze live RuleTruth parameters or turn aggregate caches into historical
  truth. Collection retains returned reference proofs before context teardown.
- Root reads preserve answer order/subsumption, stored incumbents and the
  population-prior fallback. Waiting answers and priors are never materialized.
  Forward runs build the same rows and use the same evaluator, but pay row
  computations at every depth and retain caller-selected seeds/agenda work.

## Acceptance evidence

The tests are executable examples of this contract, not permission to retain
helpers with no production caller. Preserve `tests/test_tv_calibration.py`'s
expected-failure set unchanged during internal cleanup. Relevant families:

| Obligation | Regression sources under `tests/` |
| --- | --- |
| canonical identities/dispatch | `metta/test_canonical_keys`, `test_member_canon`, `test_dispatch_determinism`, `test_double_negation_evidence` |
| compound reads/settling/evidence | `metta/test_compound_key_reads`, `test_connective_settling`, `test_jeffrey_updates`; `test_event_node.py`, `test_compound_completion.py` |
| merge/conditioning/exclusions | `metta/test_lifting_merge`, `test_prior_factored_merge`, `test_exclusion_rebuild`; `test_deep_conditioning.py`, `test_specificity.py`, `test_soft_reports.py` |
| folds/learning/late input | `metta/test_partial_folds`, `test_instance_tally`, `test_stationary_rules`, `test_fact_absorption`, `test_late_world_fact`; `test_fold_refresh.py` |
| worlds/Exists/judgments | `metta/test_assuming_query`, `test_exists_queries`, `test_quantified_judgments`; `test_assuming_exists_join.py`, `test_or_judgments.py`, `test_context_overlay_cache.py` |
| budgets/lifetime/output | `metta/test_anytime_roots`, `test_multi_root_query`, `test_skeleton_evaluation_lifecycle`, `test_query_many_refs`; `test_pending_work.py`, `test_rule_retirement.py`, `test_forgetting_aggregates.py` |

After each mechanism deletion run relevant tests immediately; before hand-back
run capped `scripts/verify.sh`, full comparison with master and the anchor
canary. No moved value without a separately stated oracle derivation. Timing
and accuracy are separate acceptance conditions.
