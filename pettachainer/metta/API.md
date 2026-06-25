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

## Querying and chaining

| Function | Meaning |
|---|---|
| `(query $steps $kb $stmt)` | Backward-chain up to `$steps` to answer `$stmt` against `$kb`; yields the proven results. |
| `(query-materialize $steps $kb $stmt)` | As `query`, but also writes the derived proofs back into the KB. |
| `(forward-chain $steps $kb)` | Forward-chain the KB's facts up to `$steps`. |
| `(forward-chain-from $steps $kb $target)` | Forward-chain starting from the fact matching `$target`. |
| `(forward-chain-from-fact $steps $kb $fact)` / `(forward-chain-from-facts $steps $kb $facts)` | Forward-chain from explicit fact(s). |
| `(forward-has-derived? $kb $type)` | True if a fact of `$type` exists in `$kb`. |
| `(chainer $steps $goal)` / `(chainer-materialize $steps $goal)` | Lower-level backward chainer over an already-compiled goal. |
| `(compileQuery $kb (: $prf $Type $tv))` / `(mm2compileQuery $kb $stmt)` | Compile a query into a goal + rule adds without running it. Advanced. |

## Base rates and universe size

| Function | Meaning |
|---|---|
| `(set-base-rate $kbid $pattern $tv)` | Pin a user-provided base rate for `$pattern` (overrides computed values). |
| `(clear-base-rate $kbid $pattern)` | Remove any base-rate cache entry for `$pattern`. |
| `(cached-base-rate $kbid $pattern)` | Read the cached base-rate TV for `$pattern` (or `()`). |
| `(set-universe-size $kbid $n)` / `(clear-universe-size $kbid)` / `(kb-universe-size $kbid)` | Set / clear / read the universe size used by extension-based estimates. |

## Logic configuration (`logic_config.metta`)

| Function | Meaning |
|---|---|
| `(set-logic-name $logic)` / `(current-logic)` / `(clear-logic-config)` | Set / read / reset the active logic. |
| `(set-compound-connective $head $premise-mode $output-mode)` | Configure a compound connective's premise and output modes. |
| `(set-compound-mode $head $mode)` | Convenience: set a connective with `ProjectAll` output. |
| `(set-bidirectional-implication-form $head)` | Mark `$head` as a bidirectional-implication rule form. |
| `(mark-logic-rule $name)` | Mark `$name` as a logic (structural) rule, excluded from rule-application evidence. |
| `(register-inheritance-induction! $kb)` | Enable the inheritance-induction rule set for `$kb`. |

## Runtime tuning

| Function | Meaning |
|---|---|
| `(set-context-polymorphic-facts $kb $enabled)` | Toggle context-polymorphic fact storage for `$kb`. |
| `(set-bounded-agenda-pruning $enabled)` | Toggle agenda pruning in the backward chainer. |
| `(ParticleSetBudget $n)` / `(ParticleGetBudget)` | Set / read the particle-resampling budget. |
| `(ParticleStoreClear)` / `(ParticleStorePruneKB)` | Clear the particle store / garbage-collect particles no longer referenced by the KB. |
