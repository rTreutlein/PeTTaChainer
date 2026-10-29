# One implication lowering

Baseline: `2ad70bdf`, branch `merge1-implication`. This round preserves the
public API, answers, evidence and finite-budget behavior. No B3/Assuming,
Boolean-event, compound-output or canonical-key changes are included.

## Existing entry points and stores

| Entry / store | Callers and role |
| --- | --- |
| `compileQuery` implication branch | Public single/batch roots through `mm2compileQuery`; builds a positive judgment, stated/derived copies and empirical support |
| `compile-implication-subgoal-query` | `inject-special-subgoal-query-adds`; internal CTV reads build positive and refuting judgments |
| `compile-existential-query` | `compileQuery`; canonical quantified-rule positive judgments and ordinary existential folds |
| `judgment-query-side`, basic and disjunction variants | Both implication plans, bidirectional queries, quantified queries; private assumptions, necessary-assumption target metadata and consequent reads |
| Former two-side packaging wrapper | Only the internal CTV plan; now directly calls the shared judgment-side builder |
| `implication-statement-query-adds`, `query-source-premise` | Only the positive public plan; copies indexed rule-application producers and stored statements |
| `positive-implication-producer`, `query-positive-tv` | Stated/derived copies, empirical and class-link producers; projects CTV conclusions to STV |
| `rule-truth-query-adds`, `rule-truth-installed?` | Positive/CTV plans and permanent class-link installation; reuse a refined rule's existing parameter |
| `class-link-query-adds`, `install-class-link-rules!` | Root preparation and node expansion; permanent instance-fold producers |
| `compile-rule` source block | Ingestion; raw source, executable CTV storage, stated positive copies and nested-source projections |
| `lower`, `lower-part`, `producers`, `root-adapters` | Rule premises, connective children, folds, public and private roots; common statement/key lowering |
| `inject-special-subgoal-query-adds` | Durable/temporary join waiting and non-root expansion; exact shape, proof/TV and lifetime reuse |
| `contextualize-rule-premise` | Rule discovery; redirects STV implication premises to the positive namespace and scopes private reads |
| private positive KB namespace | `compile-rule` writes stated positives; public plans write hypothetical/derived/empirical rows; skeleton redirects reads and installs permanent link folds |
| private stated-source KB namespace | `compile-rule` writes raw STVs and reads them to build executable CTVs / nested projections; native rule-evidence confidence reads it first |
| `judgment-consequent` metadata | Query-local facts identify a hypothetical world's target; world borrowing and evaluator necessary-assumption checks consume it |
| `&installed_producers`, `rules`, `ccls_index`, `&rule_truth_shapes` | Shared lifetime, discovery and refinement registries; not separate truth engines |
| `&sk_world_*`, private contextual facts and normal skeleton tables | Indexed borrowing, late-input delivery, assumptions, rows and values; retained for hypothetical judgments |

Direct internal tests occur in `test_conjunction_conditioning`,
`test_goal_constraint_identity`, `test_ground_negated_implications` and
`test_conditional_world_facts`. Namespace assertions also occur in
`test_query_materialize`. Public behavior is covered by implication-premise,
derived-implication, quantified-judgment, class-link, refinement, world and
conjunction tests. Full caller evidence is in
`scratch/merge1/caller-audit-before.txt` (including a search of `tests/`).
None of these internal helpers is a public signature in `API.md`.

## Producer contract and migration

An implication has three independent supports: its stated source, a judgment
of its consequent under its antecedent, and instance evidence (or the existing
refined `RuleTruth` parameter). They use the existing merge and evidence rules;
the same stated rule and its hypothetical application remain one source.

First consolidate the positive and CTV producer assembly. Both use the same
judgment-side builder and the same parameter/instance producer. Consequents
must pass through `lower` while preserving the whole-statement negation view:
its evidence polarity changes at that row, not at an arbitrary consumer.
A positive read selects the positive branch; an executable premise can need
both branches. That is value policy, not a second copy of source producers.

Then remove private namespace publication and redirection in favor of ordinary
key reads. Stated sources must remain readable at budget zero. Derived
statement producers must keep their original premises and proof identities;
judgments must never become eligible statement-rule producers or materialized
world facts. Internal CTV reads must retain their negative branch and exact
proof/TV constraints. The shared producer registry owns permanent versus
query-local lifetime; it must not reuse a temporary private context for a
durable premise.

Delete superseded query assembly, projected producer copies, namespace
unwrapping and namespace-only source/evidence/materialization adapters once
the ordinary-key route satisfies these obligations. Do not replace a private
KB name with an equivalent private statement tag and claim a consolidation.

Exists retains canonical claims, witness folds, binder sharing and private
fold routing. Instance and exact data folds retain their different evidence
and settlement policies. These operations are not redundant with a plain
statement read. Or-event conditional planning is explicitly out of scope.

## Footprint and acceptance

The supplied `scratch/core_count.py` uses `o200k_base`: baseline core 327,208,
third-party 17,685, total 344,893 tokens. Relevant baseline files: query
lowering 7,746; rule compiler 19,542; shared source lowering 14,538; skeleton
32,542; evaluator 100,831; native helpers 55,976. These are file footprints,
not additive deletion estimates. Final report gives per-file deltas.

After each coherent deletion run the strict MeTTa suite; then capped full
`verify.sh`, master full comparison and anchor canary. Never change an expected
answer or add calibration expected failures to make an internal cleanup pass.
If removing a remaining component changes a tested result, restore that
component, retain the largest validated deletion, and report the exact result
and the replacement obligation. This is a measured stopping point, not proof
that no future replacement is possible.

## First deletion

The initial deletion removed the query-time stored-statement collector and
the single-use two-side packaging wrapper. Strict MeTTa (161/0), full verify
and quick comparison passed, but a focused public `add-to-kb` probe found that
the collector serves an independent entry point: already-compiled CTV and
STV statements bypass ingestion's positive publication. An STV must answer
at budget zero; a CTV needs one expansion for positive-branch projection
(the initial zero-budget CTV probe was too strict). The collector was restored
and regressions added for both direct value representations. Only the two-side wrapper deletion is retained: its
caller now invokes the shared side builder directly.

## Source storage and stopping point

Raw STV source truth now uses its ordinary statement key. The permanent CTV
producer uses the immutable source value compiled into its formula, retaining
its `ForAll` rate parameters, instead of reading a second stored source key.
Nested-source projections read the ordinary source. Native rule-evidence
confidence lookup no longer searches a second namespace. Strict MeTTa after
this deletion: 161 passed, zero failed.

A subsequent ordinary-key positive-judgment candidate failed three files
(158 passed): `test_forward_start_contextualized` gained a previously absent
Assuming conjunction at STV (0.01896, 0.42039754412058533);
`test_member_inheritance_premise` doubled sample confidence from
0.0012484394506833685 to 0.0024937655860280327; and
`test_implication_premise` lost the calculated total-implication proof while
retaining its TV. That candidate was reverted in full, including the internal
test-key rewrites. No expected value changed. Positive judgments retain their
existing separate namespace and lifetime machinery. A future shared read must
separate executable-rule seeds from judgment support, admit each sample fold
once across value policies, and preserve CTV-premise proof discovery. Adding a
new private statement tag would not solve those obligations. The complete
one-lowering goal is therefore not achieved in this round.
