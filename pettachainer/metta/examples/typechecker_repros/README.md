# PeTTa typechecker follow-up repros

These standalone programs were extracted while validating PeTTaChainer against
PeTTa `28e87bd`. Run one with:

```sh
sh /path/to/PeTTa/run.sh REPRO.metta --strict --warn-runtime-checks
```

Every file in **Remaining failures** fails in both `--strict` and
`--strict-det` at `28e87bd`.

## Remaining failures

- `semidet_nested_arguments.metta`: two semideterministic calls nested as
  arguments of a deterministic call make the enclosing destructuring `let`
  determinism `unknown`. PeTTaChainer reaches this shape in
  `merge-proof-atoms`.
- `brand_after_control_flow.metta`: an erased `brand` around an `if` does not
  establish the declared nominal output.
- `case_structural_union.metta`: `if` and separate clauses synthesize
  `(| Number (List Atom))`, but the equivalent `case` leaves a residual output
  guard.
- `det_add_atom_expression.metta`: `add-atom` remains semideterministic when
  its value is a syntactically manifest expression. Changing the wrapper to
  `-[semidet]->` passes.
- `det_remove_atom_typed_expression.metta`: `remove-atom` remains
  semideterministic when its value has a closed nominal constructor type.
  Changing the wrapper to `-[semidet]->` passes. This blocks three Chainer
  cache-removal helpers and forward fact removal.
- `det_nominal_pattern_if.metta`: a total `if` whose condition structurally
  matches a nominal expression with `=` is classified as `unknown`.
- `det_is_member_concrete_list.metta`: `is-member` is not accepted as
  deterministic even when its second argument is a concrete finite list.
- `det_and_bool.metta`, `det_or_bool.metta`, and `det_not_bool.metta`: the
  Boolean builtins are not accepted inside explicitly deterministic wrappers
  with fully typed Boolean arguments.
- `named_union_alias.metta`: inline unions work, but `(: Either (| Left Right))`
  declares the value `Either`; it does not define a reusable type name.

## Fixed by `28e87bd`

- `car_atom_after_collapse.metta`: `collapse` followed by `car-atom` now
  retains the selected constructor field type.
- `det_nonempty_min_atom.metta`: a syntactically nonempty `min-atom` argument
  is now recognized as deterministic.

The fixed files remain here as regression checks and pass under both strict
modes.
