# Typechecker soundness follow-up

## Verification target

- PeTTaChainer: `98b66d0` (`typecheck-v2-strict`)
- PeTTa: `28e87bd` (`typecheck-v2`)
- PeTTa checkout used for the audit: `/tmp/petta-28e87-impact`

The PeTTa worktree was clean and pinned to the commit above.

## Latest-fix verification

Two previously reported failures are fixed:

- constructor field knowledge survives `match` -> `collapse` -> `car-atom`;
- `min-atom` over a syntactically nonempty list is accepted as deterministic.

Both retained regression programs pass with `--strict` and `--strict-det`:

```text
car_atom_after_collapse.metta  PASS
det_nonempty_min_atom.metta   PASS
```

The original strict Chainer import now gets beyond those checker failures. Its
first plain-strict blocker is an honest Chainer contract in
`particle-fetch-pairs`: particle values are dynamically typed, so the result
cannot be `(List ($value Number))`. The first strict-determinism blocker is
`add-atom` in `set-logic-name`.

## Audit method

I corrected Chainer-owned contracts in a scratch worktree and repeatedly
compiled the whole import with:

```sh
sh /tmp/petta-28e87-impact/run.sh tests/test.metta \
  --strict --warn-runtime-checks
```

This advanced the import through distribution formulas, TV formulas, the
compiler, proof/evidence helpers, and into forward chaining. Before the next
checker blocker, all 28 emitted runtime-check warnings were explicit
`(the ...)` boundaries; there were no implicit residual guards.

The Chainer-side findings included:

- particle-pair values need the actual dynamic `Atom` role, while particle IDs
  remain `Number`;
- relational `append` should not be called from deterministic helpers; small
  typed recursive append functions preserve determinism;
- raw compiler additions must be branded at the branch or construction point,
  not after control flow;
- values returned by `match` need typed constructors or explicit erased-role
  boundaries before `collapse`;
- `Evidence` is an open erased role because evidence lists intentionally
  contain opaque leaf proof tokens as well as known evidence constructors;
- projection keys deserve a real nominal `ProjectionKey` constructor rather
  than an anonymous structural type expression.

These scratch changes were diagnostic and are not part of this repro-only
commit.

## Remaining checker issues

Standalone programs are in `examples/typechecker_repros`. Every item below
fails with both `--strict` and `--strict-det` at PeTTa `28e87bd`.

### Semideterministic composition through destructuring `let`

`semidet_nested_arguments.metta` reports the enclosing expression as
`unknown`. This is the exact shape reached by `merge-proof-atoms`: two
semideterministic evidence lookups feed a deterministic merge whose pair output
is destructured.

### Nominal branding after control flow

`brand_after_control_flow.metta` leaves a residual nominal output guard even
though the complete `if` result is explicitly branded.

### Structural-list unions through `case`

`case_structural_union.metta` cannot prove
`(| Number (List Atom))`. Equivalent `if` code and equivalent separate
function clauses both pass, isolating the loss to `case` output synthesis.
PeTTaChainer reaches this with `cpu-expected-tv`.

### Space mutations with manifest or typed expressions

- `det_add_atom_expression.metta` rejects a literal `(fact 1)` argument.
- `det_remove_atom_typed_expression.metta` rejects a variable known to have a
  closed constructor type.

The same wrappers pass when declared `-[semidet]->`, confirming that the only
disagreement is builtin determinism. The `remove-atom` case blocks cache-entry
removal and forward canonical-fact removal.

### Deterministic structural match on a nominal expression

`det_nominal_pattern_if.metta` classifies a total
`(if (= $value ($a $b $c)) true false)` as `unknown` when `$value` has an
expression-backed newtype.

### Deterministic finite membership and Boolean builtins

- `det_is_member_concrete_list.metta` rejects `is-member` over a concrete
  finite list.
- `det_and_bool.metta`, `det_or_bool.metta`, and `det_not_bool.metta` reject
  fully typed Boolean wrappers.

PeTTaChainer can spell these as recursive or nested-`if` helpers, but the
builtins themselves are total in these modes and should be reusable in
deterministic functions.

### Named union aliases

`named_union_alias.metta` confirms that inline unions work but cannot be given
a reusable type name. This is no longer required for the immediate Evidence
model—an open nominal role is honest there—but remains a type-language gap.

## Reproduction summary

```text
PASS  car_atom_after_collapse.metta
PASS  det_nonempty_min_atom.metta

FAIL  semidet_nested_arguments.metta
FAIL  brand_after_control_flow.metta
FAIL  case_structural_union.metta
FAIL  det_add_atom_expression.metta
FAIL  det_remove_atom_typed_expression.metta
FAIL  det_nominal_pattern_if.metta
FAIL  det_is_member_concrete_list.metta
FAIL  det_and_bool.metta
FAIL  det_or_bool.metta
FAIL  det_not_bool.metta
FAIL  named_union_alias.metta
```
