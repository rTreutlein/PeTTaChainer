# Chainer module dependencies

`petta_chainer.metta` imports modules in foundational-to-specialized order:

1. formulas and compilation
2. `chainer_runtime_core` (safe space insertion and flat iteration)
3. `chainer_utils` (shared scoring, evidence, and proof merging)
4. `forward_chainer`
5. `compiled_query_runtime` (KB/index/cache storage)
6. `proof_semantics` (fold finalization shared by both chainers)
7. `backward_proof_store`
8. `backward_chainer`
9. `query_runtime` (public query orchestration)

This keeps the public import path and API unchanged while preventing low-level
modules from depending on query orchestration or a specialized chainer.

## Cyclic interface inventory

The order-sensitive compatibility baseline `f978360` contains **15** exact
`__chainer-interface__` declarations (the earlier reported count of fourteen
was off by one). The complete before/after inventory is:

| Baseline interface | Baseline dependency | Resolution |
|---|---|---|
| `record-inheritance-nodes!` | `forward_chainer` -> later `compiled_query_runtime` | **Retained.** Canonical insertion calls the forward frontier, while forward insertion records canonical runtime indexes. Splitting that shared transaction would change add behavior. |
| `base-rate-cache-remove-derived!` | `forward_chainer` -> later `compiled_query_runtime` | **Retained.** Forward sufficient-statistic maintenance and the canonical cache store update each other as one insertion transaction. |
| `kb-universe-size` | forward aggregation -> later storage runtime | **Retained.** Forward aggregation reads canonical runtime configuration while canonical insertion activates forward state. |
| `store-forward-base-rate!` | `forward_chainer` -> later `compiled_query_runtime` | **Retained.** The forward accumulator commits into the canonical cache owned by the runtime. |
| `resolve-base-rate-prior` | formulas/forward aggregation -> storage runtime | **Retained.** Formula vocabulary loads before the runtime-owned configurable prior store. |
| `inheritance-subjects` | `forward_chainer` -> later `compiled_query_runtime` | **Retained.** Forward estimates read the canonical subject index that forward insertion also populates. |
| `proof-output-atom` | `chainer_utils` -> later proof store | Move its only generic-module consumer, `frontier-proof-score`, to `backward_chainer`. |
| `assumption-proof?` | `chainer_utils` -> later proof store | Move the representation-only predicate to shared `chainer_utils`. |
| `goal-by-id` | proof store -> later backward chainer | Move the store accessor to `backward_proof_store`. |
| `aggregate-by-id` | proof store -> later backward chainer | Move the store accessor to `backward_proof_store`. |
| `aggregate-finish` | `forward_chainer` -> later backward chainer | **Retained at the import boundary, but extracted** into shared `proof_semantics`, because both chainers consume it. Loading it after runtime configuration preserves PeTTa specialization behavior. |
| `chainer` | compiled query orchestration -> later backward chainer | Move public orchestration to late-loaded `query_runtime`. |
| `chainer-materialize` | compiled query orchestration -> later backward chainer | Move public orchestration to late-loaded `query_runtime`. |
| `schedule-aggregate-heap` | proof-store commit -> backward scheduler | **Retained.** A committed child proof must wake aggregate waiters in the active agenda; the store and scheduler form one event callback boundary. |
| `advance-frontier-waiter-heap` | proof-store commit -> backward scheduler | **Retained.** A committed proof must advance live frontier waiters in the active agenda; moving agenda policy into storage would invert ownership. |

After the refactor there are **9** exact declarations: six at the canonical
runtime/forward-insertion transaction boundary, one shared fold-finalization
interface, and two at the irreducible proof-commit-to-active-scheduler callback
boundary. This reduces the interface set by 40% while avoiding a semantic split
of either transaction or a change in PeTTa specialization behavior. Every
remaining declaration keeps an exact sentinel shape; no catch-all equation is
used.
