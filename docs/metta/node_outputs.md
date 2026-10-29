# Compound outputs from the event node

Baseline `2ad70bdf`, worktree/branch `merge2-outputs`, 2026-10-29.
Measured with `scratch/core_count.py`, `o200k_base`: core **327,208**,
third party **17,685**, total **344,893** tokens.

## Existing ownership and callers

| Producer or consumer | Callers and obligations | Intended replacement/deletion |
| --- | --- | --- |
| `compile-outputs`, source_lowering | `compile-ordinary-fact`, `compile-implication-forward-rules`, and the non-pure-connective inversion branch of `compile-implication`; no direct test calls | Install output rows from the same node lowering as compound producers; remove source-proof-shaped output dispatch. Preserve ProjectAll configuration and negation canonicalization. |
| `compile-node-rows` | Output dispatch only; emits one observed-message and one predicted-update row per distinct atom | Preserve EventNodeMessage/Pearl and EventNodeJeffrey/merge-time Jeffrey. These already call the event node; deleting their installer alone deletes supported behavior. |
| `compile-node-joints` | Output dispatch only; node-joint-goals supplies nested and subset/permutation goals | Preserve EventNodeJoint, distinct-atom formula, sibling cavities, canonical conclusions and source proof; canonical/permutation changes are out of scope. |
| `lower-node-siblings`, `lower-node-sibling` | Both node row generators | Preserve optional CompoundEvidence cavity reads, late wakeups, CPU lowering and unknown implication siblings of predictions. |
| `compile-consequent-implications`, `consequent-projection-tv` | Named source branch of compile-implication; recursive And descent/export to compile-implication-forward-rules; evidence.rule-evidence-head unwraps consequent-projection | Test removal against node-only support. This is the remaining strong conditional export, including both CTV branches, source ownership and universal variables. |
| Conditional quotient in disjunction-judgment-query-side | Joint key P(B and D), written-event base-rate denominator P(D), conditioned-disjunction proof | A node conditional must preserve that denominator, zero-denominator failure, confidence and evidence. Replacing it with an independent atom marginal is not equivalent. |
| `AndProjection`, third-party truth_values | Only live call is the above quotient; tests have no direct calls | Delete only after the shared conditional operation preserves its joint/denominator semantics. |
| Open-proof 0.99 scheduling factor | term-confidence, called by premises-expected-confidence and rule scoring/storage | Delete the factor and its obsolete comment; preserve deterministic search and finite-budget answers. Full curves are required because this changes priority. |

No listed internal helper is in API.md. Public compound configuration and
query signatures remain unchanged. Grep of tests finds direct term-confidence
coverage in test_dispatch_determinism; consequent-projection proof expectations
in test_source_gate_judgment and test_nested_consequent_projection; node-joint
proof expectations in test_implication_projection. No direct tests call either
node compiler generator or the old output dispatcher.

Runtime consumers are shared: evidence.proof-term-evidence preserves source and
sibling evidence for node-message/node-jeffrey/node-joint; the evaluator's
sk-merge-key separates messages and updates, sk-messages-on combines observed
messages, and sk-node-apply applies predictions after other views merge.
sk-message-counted? screens completion evidence. Skeleton CPU handling registers
optional cavity reads and their need/wakeup edges. The node lowering must retain
these contracts rather than adding another merge path.

## Implementation sequence and stopping rule

1. Delete the priority factor alone; immediately run the strict MeTTa suite,
   then verify/full/canary and curves if green.
2. Test deletion of parallel conditional-export rows while keeping node output
   rows. In particular, inspect the cold/warm/source-evidence/withdrawal tests
   above. The event-node design section 6 explicitly reserves this open-variable
   FTV export: it is not currently a ground event marginal.
3. Unify output installation only if it can preserve those rows and the joint
   conditional with less code. Renaming the existing output dispatcher or
   moving its body into a new helper is not a mechanism deletion.

After each simplification run the relevant tests immediately. Restore a failed
experiment and stop at the largest fully green state if any required mechanism
has no answer-preserving node replacement. Record the exact failing query and
old/new values; do not grow EXPECTED_FAILURES or alter expected answers without
a D0 oracle derivation. Existing node numerics and the Assuming limitation are
outside this cleanup.

## Baseline footprint

| File | o200k tokens |
| --- | ---: |
| compiler/source_lowering.metta | 14,538 |
| compiler/rules.metta | 19,542 |
| compiler/query_lowering.metta | 7,746 |
| runtime/scheduling.metta | 1,118 |
| runtime/values.metta | 2,857 |
| runtime/evidence.metta | 7,074 |
| prolog/runtime_helpers.pl | 55,976 |
| prolog/event_node.pl | 6,991 |
| third_party/pln_formulas/metta/truth_values.metta | 11,477 |

Per-file baseline counts are captured in scratch/tokens-before.json. The report
will include final counts, deleted-symbol audits, every moved value, required
comparison verdicts and uncompleted scope.

## Measured outcome

Both deletion experiments were rejected and restored. Removing the priority
factor failed the scheduler-score assertion in test_hypothesis_rules, and a
standard quick comparison changed one timed SupplyNet case's accuracy.
Removing conditional export failed three MeTTa files; unconstrained cold and
warm query probes confirmed actual answer loss, rather than a proof-pattern
mismatch. The retained runtime is byte-identical to the baseline, with zero
token savings and no accepted answer changes. See
[the hand-back report](../../MERGE2_REPORT.md) for exact queries, values,
symbol audit and verification/comparison evidence. The complete mechanism
deletion remains unimplemented under the brief's stopping rule.
