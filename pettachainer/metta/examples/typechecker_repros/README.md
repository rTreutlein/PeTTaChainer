# PeTTa typechecker follow-up repros

These standalone programs were extracted while validating PeTTaChainer against
PeTTa `typecheck-v2`. Run one with:

```sh
sh /path/to/PeTTa/run.sh REPRO.metta --strict --warn-runtime-checks
```

Determinism repros additionally need `--strict-det`.

## Fixed by `e1bd9e3`: contextual narrowing and outer-brand edges

All four files below pass with `--strict --strict-det --silent`:

- `nested_constructed_tuple_case_newtype_field.metta`: a `case` over a
  positional pair constructed from two typed parameters loses nested
  `KBContext` field types. Passing an already typed pair instead works.
- `if_union_subtraction_variable_head.metta`: a literal `CPU` equality pattern
  is subtracted from a two-member union, but the singleton remainder does not
  type a following variable-headed fact pattern.
- `outer_brand_case_open_fallthrough.metta`: an outer `Proof` brand accepts
  closed branch construction, but rejects a fallthrough variable still
  carrying a union type even though `Proof` has representation `Expression`.
- `outer_brand_let_binding.metta`: `(brand Proof (if ... (data ...) (data ...)))`
  checks its branches, but a `let` binding of that expression does not retain
  `Proof` for a typed consumer.

Before `e1bd9e3`, the first two left a residual check for `KB`. The third
reported a conflict between `WorkItem` and `Proof`; the fourth left a residual
`Proof` check at the consumer.

## Remaining at `45b1b81`: strict import library has no declaration

Run:

```sh
sh /path/to/PeTTa/run.sh \
  examples/typechecker_repros/strict_lib_import_missing_types.metta \
  --strict --strict-det --silent
```

Expected: PeTTa's own `lib_import.metta` loads successfully.

Actual:

```text
Strict mode requires a declared or inferable type for
import_prolog_functions_from_file/2
```

This blocks a strict ConceptNet benchmark before `static-import!` can load the
export. The import error propagation fix itself is working; the remaining
problem is that the standard-library helper is not strict-typed.

## Remaining at `45b1b81`: nested nominal call is not reduced

Run:

```sh
sh /path/to/PeTTa/run.sh \
  examples/typechecker_repros/nested_nominal_call_argument_not_reduced.metta \
  --strict --strict-det --silent
```

Expected: the test evaluates to `true`.

Actual:

```text
is false, should true. ❌
```

The generated clause passes the literal expression `(holder-role $holder)` to
`expected-role?` instead of first evaluating `holder-role`. The same lowering
made PeTTaChainer's forward proof-dominance check recurse over a
`(proof-atom-proof ...)` accessor expression and turned a one-second test into
a timeout. Binding the accessor result with `let*` is a valid local workaround.

## Fixed by `45b1b81`: malformed imported file

Run:

```sh
sh /path/to/PeTTa/run.sh \
  examples/typechecker_repros/malformed_import_missing_paren_main.metta \
  --strict --strict-det --silent
```

`malformed_import_missing_paren_defs.metta` deliberately omits the closing
parenthesis of its definition. PeTTa now exits with status 2 and reports:

```text
Syntax error: missing ')', starting at line 2:
= (imported-value) 7
```

The malformed module is no longer silently discarded.

## Status at `418a0c5`

`det_forward_mutual_bool_operand.metta` is fixed.

The next FFI boundary remains:

- `det_callpredicate_assertz.metta`: `callPredicate` is nondet in general, but
  a concrete whitelisted `assertz/2` goal succeeds exactly once and binds its
  clause-reference output. The argument-aware determinism analysis does not
  currently recognize that mode.
- `det_callpredicate_erase.metta`: the corresponding `erase/1` cleanup call is
  also deterministic for the valid clause reference produced by `assertz/2`.

## Status at `3a2ad2c`

`det_mutual_bool_output.metta` is fixed when the mutually recursive bodies
consume their certificates only after all bodies have been registered.

One source-order timing case remains:

- `det_forward_mutual_bool_operand.metta`: the first mutually recursive body
  itself consumes the later function's bound-Bool certificate before that
  function has any stored clause metadata. The SCC assumption cannot begin
  because the later node is not yet present.

## Status at `9ba8764`

`det_nested_bool_operand.metta` is fixed.

One certificate-derivation follow-up remains:

- `det_mutual_bool_output.metta`: mutually recursive det Bool functions cannot
  acquire the bound-Bool output certificate because derivation is a one-pass,
  source-ordered process rather than an SCC/fixpoint analysis.

## Status at `e513a09`

`det_bool_call_operand.metta` is fixed for direct bound-Bool call operands.

One recursive-composition follow-up remains:

- `det_nested_bool_operand.metta`: a bound Bool produced by a contextual
  builtin such as `not` is not recognized as a bound operand of an enclosing
  `and`.

## Status at `19c4671`

`det_nonempty_collapse_let_star.metta` is fixed.

One follow-up remains:

- `det_bool_call_operand.metta`: `and`/`or`/`not` recognize bound Boolean
  parameters and det builtin Boolean results, but not a bound Boolean produced
  by a det user function. This blocks Chainer's composition of its deterministic
  evidence predicates.

## Status at `d429c10`

`det_nonempty_collapse_binding.metta` is fixed for a plain `let`.

The production Chainer expression exposed the corresponding `let*` gap:

- `det_nonempty_collapse_let_star.metta`: a collapse-derived proper-list
  guarantee is lost when the binding follows another binding in `let*`, so the
  nonempty branch does not upgrade the semidet head accessor to det.

## Status at `72175b7`

The three repros introduced at `6222d50` are fixed:

- `det_nonempty_semidet_branch.metta`
- `det_collapse_union_bound_list.metta`
- `det_min_computed_nonempty.metta`

All three now pass with `--strict --strict-det`.

One narrower follow-up remains:

- `det_nonempty_collapse_binding.metta`: nonemptiness refinement works for a
  declared list parameter, but not for a `let` variable inferred from
  `collapse`, despite `collapse` certifying a bound proper-list result.

## Remaining at `6222d50`

These three programs pass under plain `--strict`, but fail under
`--strict --strict-det`:

- `det_nonempty_semidet_branch.metta`: the nonempty branch of an explicit
  empty-list test does not refine a semidet head accessor into a det call.
- `det_collapse_union_bound_list.metta`: the fact that `collapse` returns a
  bound proper list is lost across a typed helper, so `union-atom` remains
  conservatively nondeterministic.
- `det_min_computed_nonempty.metta`: `min-atom` recognizes a literal nonempty
  list, but not the same manifest list shape when its elements are deterministic
  typed calls.

Generic `append`/`union-atom` calls on a `(List T)` parameter are deliberately
not included: that type alone does not prove that the runtime value is bound or
has a proper list spine.

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
