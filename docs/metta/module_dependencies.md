# Chainer module dependencies

`petta_chainer.metta` is the public facade. It loads the implementation into a
single MeTTa environment in foundational-to-specialized order:

1. `chainer_types` defines the shared nominal types and runtime row shapes.
2. `logic_config` defines the selectable logic configuration.
3. `dist_formulas`, `fold_inverse`, `compute_inverse`, and `tv_formulas`
   provide the formula vocabulary used by compiled rules.
4. `compile` lowers public facts, rules, and queries into the internal runtime
   representation.
5. `chainer_utils` owns shared evidence/proof operations, canonical KB helpers,
   safe space insertion, and flat iteration.
6. `forward_chainer` owns forward agendas and incremental derived-state
   maintenance.
7. `compiled_query_runtime` owns canonical KB, index, and cache storage.
8. `backward_proof_store` owns durable backward proof, dependency, and result
   rows.
9. `backward_chainer` owns backward scheduling, proof search, and aggregate
   finalization.
10. `query_runtime` provides public single-root and shared multi-root query
    orchestration.

The import order is observable because PeTTa specializes equations as modules
are loaded. Do not reorder modules merely to make the dependency list look more
conventional; validate any ordering change against the strict suite and the
relevant performance benchmarks.

## Order-sensitive boundaries

Some runtime transactions intentionally cross file boundaries:

- Canonical insertion in `compiled_query_runtime` updates indexes and activates
  forward state owned by `forward_chainer`.
- Forward aggregation reads and updates canonical base-rate and universe state
  through helpers loaded with `chainer_utils` and `compiled_query_runtime`.
- `backward_proof_store` commits durable proof rows, while `backward_chainer`
  owns the active agenda that consumes those rows.
- `backward_chainer` owns backward aggregate finalization. Forward aggregation
  uses its separate `forward-finish-aggregate` dispatch.
- Public query wrappers remain in the last-loaded `query_runtime`; storage and
  compilation modules must not depend on query orchestration.

These are semantic ownership boundaries, not a reason to expose additional
public API. The supported public surface remains the one documented in
`docs/metta/API.md` and re-exported by `pettachainer/metta/petta_chainer.metta`.
