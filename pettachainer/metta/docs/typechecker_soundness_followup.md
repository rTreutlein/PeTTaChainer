# Typechecker soundness follow-up

This audit compares PeTTaChainer `a8d8edf` with the committed PeTTa checker
revision `e906499`. The local checker used for the full import was patched only
with argument-sensitive determinism for syntactically nonempty `min-atom` and
`max-atom`; that pending issue otherwise stops the import at
`confidence-to-count`.

## Result

With the nonempty-min diagnostic patch, the unchanged Chainer emits 64 runtime
check warnings before stopping at the Proof walker:

- 26 are existing explicit `(the ...)` ascriptions.
- 38 are implicit residual guards.
- The first hard error is honest: `cdr-atom` produces
  `(List %Undefined%)`, but `proof-term-children-mode` declared
  `(List Proof)`.

The independent fixes in this commit remove 13 of those 38 implicit guards,
leaving 25 before the same Proof boundary. They do not add runtime checks.

## Chainer issues fixed

### `no-evidence` had two unrelated nominal types

`dist_formulas.metta` declares `no-evidence` as `TV`, then
`tv_formulas.metta` redeclared it as `WeightedTV`. The second declaration made
every TV-producing fallback involving `no-evidence` require a residual guard.

`WeightedBaseRateAcc` and `WeightedBaseRateWithPriorAcc` now accept the honest
inline sum `(| TV WeightedTV)`. This removes guards from:

- `BaseRateTv`
- `WeightedBaseRateTv`
- `WeightedCountBaseRateTv`
- `WeightedUniverseBaseRateTv`
- `UniformPriorTv`
- `UniformPriorKnownTv`
- `normalize-expected-tv`

### Constructor matching was expressed as untyped equality

`particle-ids-in-term` used an `if` whose condition unified its input with
`(ParticleDist $pid $scale)`. Expressing that dispatch as `case` lets the
declared `ParticleDist` constructor type establish that `$pid` is a `Number`.
The output is now proven `(List Number)` without a guard.

### Erased role boundaries were missing

- `compile-inheritance-lift-instance` extracted a KB name from `KBContext` and
  shadowed its already typed `$kb` parameter with the unbranded result. The
  extracted field is now explicitly branded `KB`, removing two guards.
- `rule-evidence-base-name` now brands names extracted from proof wrappers as
  `Proof`.
- `query-temp-rule-premise` returns the already typed input in its fallback and
  explicitly brands the rewritten `Compute` statement.
- The direct branch of `compiled-add-mm2stmt` now brands its generated runtime
  addition.

### `cached-base-rate` declared the wrong output shape

The function always returns either `()` or a singleton list containing a TV,
but its signature claimed `(| TV (List $no-result))`. It now returns
`(List TV)` and constructs the singleton with `cons`, preserving the same
runtime representation.

## Checker issues or missing type-language features

Standalone repros live in `examples/typechecker_repros`.

### `car-atom` loses a collapsed list's element type

The `match` in `car_atom_after_collapse.metta` correctly establishes `Choice`.
The loss occurs after `collapse`, at `car-atom`. The temporary boundary
workaround would be `(the Choice (car-atom $matches))`, but PeTTaChainer does
not add it because it creates a runtime check for information the checker
already had.

This affects `current-logic`, `configured-compound-premise-mode`, and
`configured-compound-output-mode`. `particle-fetch-pairs` is the corresponding
whole-list form: `collapse` does not retain the typed match result as its
element type.

### Known-nonempty `min-atom` / `max-atom`

The builtins are semideterministic for an arbitrary list because the empty
list fails. `det_nonempty_min_atom.metta` passes a syntactically nonempty pair,
so that call is deterministic.

### Nested semideterministic calls become `unknown`

In `semidet_nested_arguments.metta`, two semideterministic calls are arguments
of one deterministic call. The enclosing function is semideterministic, but
the checker reports the enclosing `let` as `unknown`. The same shape occurs in
`merge-proof-atoms`.

### `brand` knowledge is lost across control flow

`brand_after_control_flow.metta` explicitly brands an `if` result inside
`let*`, yet strict mode still emits an output check for the nominal type. This
is relevant to the remaining `mm2stmt` guard and likely several compiler
functions that return erased `CompiledAddition` values.

### Named union aliases are needed for Evidence

Evidence tokens are not one closed nominal constructor family. A plain proof
walk deliberately retains an arbitrary whole `Proof` term as one evidence
token, while other paths produce structured `fact-ev`, `not-fact-ev`,
`rule-ev`, and `not-ev` values. The honest domain is:

```metta
(| Proof StructuredEvidence)
```

Inline unions work, but `named_union_alias.metta` demonstrates that
`(: Evidence (| Proof StructuredEvidence))` declares a value named `Evidence`;
it does not define a reusable type alias. Repeating the union through every
proof-store, forward-chainer, and backward-chainer signature would obscure the
domain model. The Evidence refactor is therefore deferred until a named union
can be expressed.

The Proof walker itself should then:

- return `(List %Undefined%)` from `proof-term-children-mode`;
- brand each `cdr-atom` child as `Proof` at the recursive boundary;
- use `(List (| Proof StructuredEvidence))` through evidence APIs (preferably
  via the named alias).

## Residual warnings still needing triage

The remaining implicit warnings before the Proof boundary group as follows:

- collapsed/dynamic list knowledge: `list-count`, `remove-index`,
  `partition-existential-premises-walk`, `implication-proof-token`,
  `ground-specialization-with-fact`, and two `map-flat` specializations;
- erased compiler output roles: `compile-output-children`,
  `compile-adapter-chain`, `compile-implication-forward-rules`, `compile_`,
  `union-compiled-additions`, `mm2stmt`, and
  `query-context-premise-assumption-adds`;
- dynamic CPU result unions: `cpu-expected-tv`, `first-cpu-expected-tv`, and
  their generated `CTVModusPonensFormula` specializations;
- deliberate dynamic safety boundaries: `aggregate-args-tv-mode` and
  `internalize-proof-structure-any`.

The last group is cheap or compiler-only and may be worth retaining for
stability. The others should be rechecked after the standalone checker issues
above land before adding any explicit runtime ascriptions.
