# PeTTa typechecker follow-up repros

These files are standalone PeTTa programs extracted while validating
PeTTaChainer against PeTTa `e906499`.

- `car_atom_after_collapse.metta`: `match` correctly types the selected
  constructor field, but `collapse` followed by `car-atom` loses the list
  element type.
- `det_nonempty_min_atom.metta`: a syntactically nonempty argument makes
  `min-atom` deterministic even though the builtin is semideterministic for an
  arbitrary (possibly empty) list.
- `semidet_nested_arguments.metta`: two semideterministic calls nested as
  arguments of a deterministic call make the enclosing `let` determinism
  `unknown`.
- `brand_after_control_flow.metta`: an explicit erased `brand` around an
  `if` inside `let*` does not discharge the declared nominal output.
- `named_union_alias.metta`: inline unions work, but there is no way to give
  one a reusable type name. `(: Either (| Left Right))` declares the value
  `Either`; it does not define a type alias.

The repros intentionally fail under the affected strict checker revision.
