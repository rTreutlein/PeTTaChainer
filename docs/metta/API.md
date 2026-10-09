# PeTTaChainer public API

This is the user-facing surface of the compiler and chainer: the functions
callers (NL2PLN, examples, downstream code) are expected to invoke. **Treat
everything listed here as public** — do not remove or change its signature as
part of an internal cleanup, even if only a test currently exercises it.

Everything *not* listed here is internal. Internal helpers may be inlined,
renamed, or removed whenever they have no remaining caller — and a reference
from a unit test alone does not make a helper public (rewire or drop the test
with it). When in doubt about whether a function is public, it is internal.

The formula vocabulary under `third_party/pln_formulas/metta/` is a separate,
independent surface usable inside rules; it is not enumerated here.

Python callers can load application-owned formula modules with
`PeTTaChainer.load_metta_file(path)`. This extends that handler's MeTTa runtime;
it does not add statements to the handler's knowledge base.

## Knowledge base construction

| Function | Meaning |
|---|---|
| `(compileadd $kb $stmt)` | Compile a statement (fact or rule) and add it to KB `$kb`. The primary entry point. |
| `(add-to-kb $expr)` | Add an already-compiled, internal-form atom to the live KB. Lower-level. |
| `(remove-compiled-statement $name)` | **Deprecated compatibility operation.** Retracts the current kb facts, rules, index rows, and cached scores for one named statement, but does not forget stored backward proofs or skeleton rows. It is outside the monotonic query contract; rules whose compiled proof carries no extractable name are not covered. Python: deprecated `PeTTaChainer.remove_statement(name)`, which emits `DeprecationWarning`. |

The live `&kb` keeps every added fact as stored; several facts of one
statement are merged where they are read, as leaves of the backward search.
Materialized results are marked facts in `&kb`: a statement's latest
materialization replaces its earlier one, and marked facts are never read as
leaves.

The backward chainer keeps a durable skeleton across calls: expanded goals,
their answers, complete rule instances, and the truth-value views evaluation
computed for them. A later query continues from what earlier queries built and
recomputes only the values its roots read that changed; rows compiled for one
query leave with it. Proof IDs
are monotonic. Aggregates are recomputed from their members when a member
changes. See `runtime_design_assumptions.md` for the contracts.

## Querying and chaining

| Function | Meaning |
|---|---|
| `(query $steps $kb $stmt)` | Backward-chain up to `$steps` expansions to answer `$stmt` against `$kb`; yields the proven results. A larger budget extends the same search order. `$steps` also scales the query's allowances for walking already-built search state and for recomputing values far from its roots; work beyond them is left for later queries. Stored facts cost no expansion, so a zero-step query answers from stored facts and from what earlier queries derived through permanent rules. When the search has no value for a statement, a result an earlier query materialized is returned instead. A candidate rule is skipped before search state is created when a ground premise has no matching fact and no rule can conclude its head; ground deterministic CPU premises are evaluated during that check so later premises become checkable. |
| `(query $steps $kb (: $prf (Implication $a $b) $tv))` | An implication query: `$a` is assumed in hypothetical contexts and `$b` proved there. With `$tv` open or a `CTV`, it judges the implication's truth from a positive and a refuting context, `(CTV P(b|a) P(b|not a))`, revised with the instance fold of the implication. With an `STV`, it evaluates the positive side only: the answer's truth value is how `$b` stands when `$a` holds, with proof `(conditional-implication ...)`, one answer per binding of `$b`'s variables. A premise is read in the hypothetical context when it mentions the query's variables, and in the main context otherwise. |
| `(query $steps $kb (: $prf (Assuming $facts $goal) $tv))` | Prove `$goal` as if `$facts` (a statement or an `And` of them, implications included) were stored, together with everything the KB holds; nothing assumed is stored. Answers have proof `(assuming ...)`, one per binding of `$goal`'s variables. Premises the assumptions cannot change are read in the main context and shared with other queries. |
| `(query-materialize $steps $kb $stmt)` | As `query`, but also writes back the first result and, for every statement its proof uses, that statement's current value. |
| `(query-many $steps $kb $statements)` | Compile every statement, inject their temporary additions once, and answer all roots in one shared backward search. `$steps` is one total expansion budget. All roots share one priority order: a goal's priority is the best score any join waiting on it gives it. Emits `(query-result $index $answer)` for each answer. A ground root the search leaves without a value answers its population prior, `(population-prior <pattern>)`, when one of its rules reads a base rate strictly between 0 and 1 over its population; other unanswered roots emit no row. Python: `PeTTaChainer.query_many(statements, steps)` returns an input-aligned `list[list[str]]`, including empty lists for unanswered roots. |
| `(query-many-materialize $steps $kb $statements)` | As `query-many`, but materializes each root's first result and the current values of the statements its proof uses. Python: `PeTTaChainer.query_many_materialization(statements, steps)` runs in the caller's live process so the KB writes persist. |
| `(forward-chain $steps $kb $facts)` | Forward-chain from a caller-selected list of compiled facts. The run grows the backward skeleton upward from them: rules triggered by a taken key join it with the facts and keys that already exist, and the rows are evaluated as a query evaluates them. Keys are taken by how far their value moved (Beta divergence); every row the run computes costs one of `$steps`. The run works the facts callers chose first (its own and those earlier runs on the KB queued), for a share of `$steps` (`set-forward-seed-share`), then everything the agenda holds, and carries what it leaves to the next run. With no facts it continues that agenda only; with no steps it only queues its facts. Stores the values of the derived keys it built on in `&kb`, where later queries read them as facts, and returns them. A returned fact's proof is a reference, `(proof-ref N)`, into the proof store, as its stored copy's is, so a run's cost does not grow with the length of the derivations behind it; a query for the statement prints the full proof. |
| `(chainer $steps $goal)` / `(chainer-materialize $steps $goal)` | Lower-level backward chainer over an already-compiled goal. |
| `(chainer-many $steps $goals)` / `(chainer-many-materialize $steps $goals)` | Lower-level multi-root variants over compiled goals; return one result list per input goal. Duplicate and common subgoals share their skeleton nodes. |
| `(compileQuery $kb (: $prf $Type $tv))` / `(mm2compileQuery $kb $stmt)` | Compile a query without running it. `compileQuery` returns `(compilation-plan goal additions)`; `mm2compileQuery` returns the runtime-encoded equivalent. Advanced. |

## Existential rules and witness views

An explicit conclusion such as

```metta
(Implication
   (Dog $dog)
   (Exists ($cat) (And (Cat $cat) (Chases $dog $cat))))
```

derives a proposition-level claim with canonical bound positions:

```metta
(ExistentialClaim
   (And
      (Cat (exists-slot 0))
      (Chases $dog (exists-slot 0))))
```

`exists-slot` is not an object and does not assert that a new cat distinct from
all known cats exists. Multiple rules for the same quantified body therefore
contribute evidence to the same claim. Implicit conclusion-only variables keep
the older constructive behavior and produce stable `(exists rule index args)`
Skolem terms.

An ordinary `(Exists ($x ...) $body)` antecedent compiles two alternative proof
paths: a matching direct `ExistentialClaim`, and the OR fold over currently
enumerable body instances. A non-constructive existential conclusion can thus
feed a downstream existential rule even when no concrete witness is known.

Two complete-side premise forms expose the relationship between a direct claim
and the witnesses currently enumerable from the KB:

| Form | Meaning |
|---|---|
| `(KnownExistential ($x ...) $body)` | Fold the truth values of matching body instances with `OrFormula`. This is the currently enumerated witness disjunction D, not a proof that the population is complete. |
| `(ExistentialResidual ($x ...) $body)` | Match the corresponding direct `ExistentialClaim`, build D, and calculate U from E = D or U using `ExistentialResidualFormula`. Its confidence is propagated from both E and D. |

Both are lazy, budgeted FoldAll producers. As new witness facts become
available, their aggregate proofs refine without retracting the direct
existential proof. See `examples/metta/existential_residual.metta` for a runnable
example in which two weak known cats leave a strong residual and a later Felix
witness moves support from that residual into the enumerated disjunction.

## Base rates

| Function | Meaning |
|---|---|
| `(set-base-rate-smoothing $kbid $enabled)` | Opt `$kbid` into reading each computed base rate as a Beta estimate: over n observations its strength is (Σs + k/2)/(n + k), its evidence plus k pseudo-observations at 0.5, and its confidence n/(n+k) is unchanged, so a rate over few observations is not taken as certain. Set it before adding knowledge; user base rates are kept as set. Python: `PeTTaChainer.set_base_rate_smoothing(enabled)`, which timed subprocess queries replay. |
| `(set-base-rate $kbid $pattern $tv)` | Pin a user-provided base rate for `$pattern` (overrides computed values). The folds over `$pattern` and their readers recompute at the next query. |
| `(clear-base-rate $kbid $pattern)` | Remove any base-rate cache entry for `$pattern`; its folds recompute at the next query. |
| `(cached-base-rate $kbid $pattern)` | Read the cached base-rate TV for `$pattern` (or `()`). A value may be a provisional forward estimate until a full backward fold refines it. |

## Logic configuration (`core/logic_config.metta`)

| Function | Meaning |
|---|---|
| `(set-logic-name $logic)` / `(current-logic)` / `(clear-logic-config)` | Set / read / reset the active logic. |
| `(set-compound-connective $head $premise-mode $output-mode)` | Configure a compound connective's premise and output modes. |
| `(set-compound-mode $head $mode)` | Convenience: set a connective with `ProjectAll` output. |
| `(set-compound-settling $head $value)` | A part of an `All`-mode `$head` compound known with certainty at `$value` settles the compound to `$value` without its other parts (PLN: `And` at `(STV 0.0 1.0)`, `Or` at `(STV 1.0 1.0)`; see `connective_settling.md`). |
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
!(compileadd kb (: sym (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))
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
| `(set-complete-predicate $kb $head)` | Declare that the rules and facts of predicate `$head` in `$kb` are the only ways one of its statements becomes true (Clark completion, well-founded on loops); declare before adding knowledge. A ground statement of it in the main context whose search is settled reads its derivations through a reading rule's own complete conclusion as unfounded, `(STV 0.0 1.0)`, and is itself unfounded when no rule application derives it; a budget that has not examined every rule application concludes nothing (see `complete_predicates.md`). Undeclared predicates stay open-world. Python: `PeTTaChainer.set_complete_predicate(head)`, which timed subprocess queries replay. |
| `(set-rule-refinement $kb $enabled)` | Opt `$kb` into rule refinement; set it before adding the rules. A refined rule applies with the revision of its stored truth and the fold of its instances, and is searched in proportion to what that truth can add (see LANGUAGE_SPEC, "Refining rules from their instances"; hypotheses: docs/metta/hypothesis_rules.md). Python: `PeTTaChainer.set_rule_refinement(enabled)`, which timed subprocess queries replay. |
| `(set-evidence-confidence-k $k)` | Set PLN's evidence parameter k (default 800): n observations have confidence n/(n+k). Process-wide and read when a formula runs, so set it before adding knowledge; values already derived keep their k. Python: `PeTTaChainer.set_evidence_confidence_k(k)`, which timed subprocess queries replay. |
| `(set-bayes-prior-count $a)` | Set the pseudo-observations of the prior with which Bayes' rule and inversion read a likelihood estimated from finite evidence (default 0.2). The prior is centred on independence (the pooled P(B) of both branches, or P(B) for P(B\|A)), so a likelihood from few observations moves a belief little instead of making it certain; certain likelihoods are read as they are. Process-wide. Python: `PeTTaChainer.set_bayes_prior_count(a)`, which timed subprocess queries replay. |
| `(set-forgetting $horizon $decay)` | Freeze a key that got no row and was not needed for `$horizon` epochs (0, the default: never): at the next `advance-epoch` its rows, views and caches are dropped and what they derived becomes one summary fact, proof `(forgotten <key-hash> <epoch>)`, whose observation count is multiplied by `$decay`. The summary keeps the value's evidence and depends on the keys within two derivation steps. Process-wide. Python: `PeTTaChainer.set_forgetting(horizon, decay)`. |
| `(advance-epoch)` | End an epoch and freeze the keys idle for the forgetting horizon; returns the new epoch. Python: `PeTTaChainer.advance_epoch()`. |
| `(set-forward-min-evidence $n)` | Set the least evidence, in observations (n = c·k/(1−c)), a derived key's value needs for a forward run to build on it (default 1). Process-wide. Python: `PeTTaChainer.set_forward_min_evidence(n)`. |
| `(set-forward-seed-share $share)` | Set the share of a forward run's steps the facts callers chose and no run has taken yet get before carried derived keys compete for the rest (default 1, the chosen facts first; 0 ranks everything together). Process-wide. Python: `PeTTaChainer.set_forward_seed_share(share)`. |
| `(set-bounded-agenda-pruning $enabled)` | Toggle forward-agenda pruning. Skeleton backward search is bounded by its expansion and row budgets. |
| `(ParticleSetBudget $n)` / `(ParticleGetBudget)` | Set / read the maximum particle support. Over-budget structured numeric samples are condensed as complete vectors; bare numeric or symbolic samples use deterministic systematic resampling. |
| `(ParticleStoreClear)` / `(ParticleStorePruneKB)` | Clear the particle store / garbage-collect particles no longer referenced by the KB. |
