# PeTTaChainer public API

This is the user-facing surface of the compiler and chainer: the functions
callers (NL2PLN, examples, downstream code) are expected to invoke. **Treat
everything listed here as public** — do not remove or change its signature as
part of an internal cleanup, even if only a test currently exercises it.

Everything *not* listed here is internal. Internal helpers may be inlined,
renamed, or removed whenever they have no remaining caller — and a reference
from a unit test alone does not make a helper public (rewire or drop the test
with it). When in doubt about whether a function is public, it is internal.

The TV/distribution formula vocabulary (`tv_formulas.metta`, `dist_formulas.metta`)
is a separate, independent surface usable inside rules; it is not enumerated here.

## Knowledge base construction

| Function | Meaning |
|---|---|
| `(compileadd $kb $stmt)` | Compile a statement (fact or rule) and add it to KB `$kb`. The primary entry point. |
| `(add-to-kb $expr)` | Add an already-compiled, internal-form atom to the live KB. Lower-level. |
| `(remove-compiled-statement $name)` | Inverse of `compileadd` for one named statement `(: $name ...)`: retracts its kb facts and rules together with their index rows and cached scores. Use before re-adding a statement under the same name (e.g. a truth-value update); rules whose compiled proof carries no extractable name (negated outputs, open query adapters) are not covered. Python: `PeTTaChainer.remove_statement(name)`. |

## Querying and chaining

| Function | Meaning |
|---|---|
| `(query $steps $kb $stmt)` | Backward-chain up to `$steps` to answer `$stmt` against `$kb`; yields the proven results. |
| `(query-materialize $steps $kb $stmt)` | As `query`, but also writes the derived proofs back into the KB. |
| `(forward-chain $steps $kb)` | Forward-chain the KB's canonical merged facts up to `$steps`; processed outputs also update provisional base-rate estimates. |
| `(forward-chain-from $steps $kb $target)` | Forward-chain starting from the canonical fact matching `$target`. |
| `(forward-chain-from-fact $steps $kb $fact)` / `(forward-chain-from-facts $steps $kb $facts)` | Forward-chain from explicit fact(s), using their canonical merged values when present. This is the cheap incremental path to call after `compileadd`. |
| `(forward-has-derived? $kb $type)` | True if a fact of `$type` exists in `$kb`. |
| `(chainer $steps $goal)` / `(chainer-materialize $steps $goal)` | Lower-level backward chainer over an already-compiled goal. |
| `(compileQuery $kb (: $prf $Type $tv))` / `(mm2compileQuery $kb $stmt)` | Compile a query into a goal + rule adds without running it. Advanced. |

## Base rates and universe size

| Function | Meaning |
|---|---|
| `(set-base-rate $kbid $pattern $tv)` | Pin a user-provided base rate for `$pattern` (overrides computed values). |
| `(clear-base-rate $kbid $pattern)` | Remove any base-rate cache entry for `$pattern`. |
| `(cached-base-rate $kbid $pattern)` | Read the cached base-rate TV for `$pattern` (or `()`). A value may be a provisional forward estimate until a full backward fold refines it. |
| `(set-universe-size $kbid $n)` / `(clear-universe-size $kbid)` / `(kb-universe-size $kbid)` | Set / clear / read the universe size used by extension-based estimates. |

## Logic configuration (`logic_config.metta`)

| Function | Meaning |
|---|---|
| `(set-logic-name $logic)` / `(current-logic)` / `(clear-logic-config)` | Set / read / reset the active logic. |
| `(set-compound-connective $head $premise-mode $output-mode)` | Configure a compound connective's premise and output modes. |
| `(set-compound-mode $head $mode)` | Convenience: set a connective with `ProjectAll` output. |
| `(set-bidirectional-implication-form $head)` | Mark `$head` as a bidirectional-implication rule form. |
| `(mark-logic-rule $name)` | Mark `$name` as a logic (structural) rule, excluded from rule-application evidence. |
| `(set-specializing-predicate $head)` | Resolve premises headed by `$head` at add-time: a rule premise like `(Symmetric $r)` is ground against stored facts, emitting one concrete-headed rule per matching fact instead of a single variable-headed rule. See below. |
| `(register-inheritance-induction! $kb)` | No-op retained for callers; inheritance induction is now compiled into every concrete `Inheritance` query. |

### Specializing predicates

Marking a predicate as specializing turns "structural" rules — those whose
conclusion head is a variable bound by such a premise — into concrete, precisely
indexed rules. Given

```
!(set-specializing-predicate Symmetric)
!(compileadd kb (: sym (Implication (Premises (Symmetric $r) ($r $x $y)) (Conclusions ($r $y $x))) (STV 0.9 0.9)))
```

adding `(Symmetric Friend)` does not leave the generic variable-headed rule in
place. Instead it emits `(Symmetric Friend) (Friend $x $y) -> (Friend $y $x)` —
the same rule with `$r` ground to `Friend`, keeping `(Symmetric Friend)` as a
grounded premise so its truth value threads through exactly. The fact itself is
still stored. Both add orders (rule-first and fact-first) work, and each ground
instance is emitted once.

The benefit is a lower branching factor: a goal only matches rules instantiated
for its own relation, rather than every variable-headed structural rule (which
would match every same-arity goal via the `any` index bucket). This matters most
for deep queries, where the per-node rule count compounds with search depth.

## Runtime tuning

| Function | Meaning |
|---|---|
| `(set-context-polymorphic-facts $kb $enabled)` | Toggle context-polymorphic fact storage for `$kb`. |
| `(set-bounded-agenda-pruning $enabled)` | Toggle agenda pruning in the backward chainer. |
| `(set-backward-premise-prefilter $enabled)` | Toggle the backward chainer's premise pre-filter (default off). When on, a candidate rule is skipped before any search state is created if one of its ground premises has no matching fact *and* no rule can conclude its head; ground deterministic CPU premises (e.g. `Compute`) are evaluated eagerly during the check so later premises become checkable. Semantics-preserving with an unlimited step budget — it never prunes a rule that could complete — but under a finite `$steps` budget it typically *increases* the number of proofs found, because the budget stops being spent on unprovable rules. Big win for KBs where many rules share a conclusion head and most premises bottom out in facts (fact-heavy/agentic KBs); near no-op for densely connected KBs where every premise head is derivable. Python: `PeTTaChainer.set_backward_premise_prefilter(enabled)`. |
| `(ParticleSetBudget $n)` / `(ParticleGetBudget)` | Set / read the particle-resampling budget. |
| `(ParticleStoreClear)` / `(ParticleStorePruneKB)` | Clear the particle store / garbage-collect particles no longer referenced by the KB. |
