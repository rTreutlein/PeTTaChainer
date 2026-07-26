# PeTTa typechecker follow-up repros

These standalone programs were extracted while validating PeTTaChainer against
PeTTa `typecheck-v2`. Run one with:

```sh
sh /path/to/PeTTa/run.sh REPRO.metta --strict --warn-runtime-checks
```

## Status at `11710ca`

### Remaining failures

- `mixed_list_atom_widening.metta`: bottom-up `cons` inference does not widen
  a heterogeneous list to the declared wildcard element type `(List Atom)`.
  Both elements fit `Atom`, but `(cons () (cons (item 1) ()))` leaves a
  residual output guard under both strict modes.
- `named_union_alias.metta`: inline unions work, but
  `(: Either (| Left Right))` declares the value `Either`; it does not define a
  reusable type name. This is a missing language feature rather than a
  regression in the latest fixes.

### Fixed by `11710ca`

- `semidet_nested_arguments.metta`
- `brand_after_control_flow.metta`
- `case_structural_union.metta`
- `det_add_atom_expression.metta`
- `det_remove_atom_typed_expression.metta`
- `det_nominal_pattern_if.metta`
- `det_is_member_concrete_list.metta`
- `det_and_bool.metta`
- `det_or_bool.metta`
- `det_not_bool.metta`

All ten pass with both `--strict` and `--strict-det`.

Explicit `-[det]->` and `-[semidet]->` declarations now emit runtime
`nonvar/1` checks for direct variable parameters. These determinism-boundness
checks are intentional, but `--warn-runtime-checks` currently reports only
type checks and explicit `(the ...)` ascriptions, not the new boundness guards.

### Fixed by `28e87bd`

- `car_atom_after_collapse.metta`: `collapse` followed by `car-atom` retains
  the selected constructor field type.
- `det_nonempty_min_atom.metta`: a syntactically nonempty `min-atom` argument
  is recognized as deterministic.

The fixed files remain here as regression checks.
