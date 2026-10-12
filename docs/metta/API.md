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
| `(query $steps $kb $stmt)` | Backward-chain up to `$steps` expansions to answer `$stmt` against `$kb`; yields the proven results. A larger budget extends the same search order. `$steps` also scales the query's allowances for walking already-built search state and for recomputing values; the values within two steps of its roots draw first on a reserve proportional to how many there are, so they are brought current at any budget; work beyond both is left for later queries. Stored facts cost no expansion, so a zero-step query answers from stored facts and from what earlier queries derived through permanent rules. When the search has no value for a statement, a result an earlier query materialized is returned instead. A candidate rule is skipped before search state is created when a ground premise has no matching fact and no rule can conclude its head; ground deterministic CPU premises are evaluated during that check so later premises become checkable. |
| `(query $steps $kb (: $prf (Implication $a $b) $tv))` | An implication query: `$a` is assumed in hypothetical contexts and `$b` proved there. With `$tv` open or a `CTV`, it judges the implication's truth from a positive and a refuting context, `(CTV P(b|a) P(b|not a))`, revised with the instance fold of the implication and with the statement as rules derive it (a rule concluding an implication, `docs/metta/derived_implications.md`). With an `STV`, it evaluates the positive side only: the answer's truth value is how `$b` stands when `$a` holds, with proof `(conditional-implication ...)`, one answer per binding of `$b`'s variables. A premise is read in the hypothetical context when it mentions the query's variables, and in the main context otherwise. Rules apply there with their adapters, so a rule concluding `(And A B C)` from `$a` answers `$b` = `(And A B)`, `A` or `(And B A)`. A nested implication, `$b` = `(Implication $x $y)` at any depth, is judged as its exported form `(Implication (And <conjuncts of $a> <conjuncts of $x>) $y)`: its contexts assume all the antecedents, each as its own statement, and prove the innermost consequent, so its truth value has the same shape and value as the exported query's, `(CTV (STV ...) (STV ...))` with P(y \| a, x) and, as the refuting context assumes the first conjunct (`$a`'s) false and the others true, P(y \| not a, x), or an `STV` for an `STV` query; never a CTV with CTV branches. The answer keeps the stated nested statement, and a nested rule's proof applies it step by step, `(by (by rule <proof of $a>) <proof of $x>)`. No antecedent is stored: an outer condition such as a source gate stays a condition (`docs/metta/derived_implications.md`, "Implication queries"). The judgment does not answer `(Not (Implication ...))`: how the consequent fails is one minus each branch's strength. |
| `(query $steps $kb (: $prf (Assuming $facts $goal) $tv))` | Prove `$goal` as if `$facts` (a statement or an `And` of them, implications included) were stored, together with everything the KB holds; nothing assumed is stored. Answers have proof `(assuming ...)`, one per binding of `$goal`'s variables. Premises the assumptions cannot change are read in the main context and shared with other queries. |
| `(query-materialize $steps $kb $stmt)` | As `query`, but also writes back the first result and, for every statement its proof uses, that statement's current value. |
| `(query-many $steps $kb $statements)` | Compile every statement, inject their temporary additions once, and answer all roots in one shared backward search. `$steps` is one total expansion budget. All roots share one priority order: a goal's priority is the best score any join waiting on it gives it. Emits `(query-result $index $answer)` for each answer. A ground root the search leaves without a value answers its population prior, `(population-prior <pattern>)`, when one of its rules reads a base rate over its population, as the prior of one more member (the rate under the Bayes prior, `set-bayes-prior-count`) and its predicate is not positive-only (`set-positive-only-predicate`); other unanswered roots emit no row. Python: `PeTTaChainer.query_many(statements, steps)` returns an input-aligned `list[list[str]]`, including empty lists for unanswered roots. |
| `(query-many-refs $steps $kb $statements)` | As `query-many`, but each answer's proof is left as the value holds it: a reference `(proof-ref N)` into the proof store, a fact's name, or a merge of references. No proof is expanded or printed, so an answer's size does not grow with its derivation. Python: `PeTTaChainer.query_many_refs(statements, steps)` returns an input-aligned `list[list[Answer]]`, each `Answer(proof, statement, tv)` passed as terms through janus (an expression is a list, a symbol or string a `str`, a number an `int` or `float`, a variable a `str` starting with `$`). It runs in the caller's live process, which holds the proofs the references point to. |
| `(expand-proof $proof)` | The full proof of a proof that refers to stored proofs, as `query` prints it: a stored subproof referenced more than once appears in full at its first occurrence as `(shared N proof)` and as `(shared N)` after that. Python: `PeTTaChainer.expand_proof(answer.proof)` returns its text. |
| `(query-many-materialize $steps $kb $statements)` | As `query-many`, but materializes each root's first result and the current values of the statements its proof uses. Python: `PeTTaChainer.query_many_materialization(statements, steps)` runs in the caller's live process so the KB writes persist. |
| `(forward-chain $steps $kb $facts)` | Forward-chain from a caller-selected list of compiled facts. The run grows the backward skeleton upward from them: rules triggered by a taken key join it with the facts and keys that already exist, and the rows are evaluated as a query evaluates them. Keys are taken by how far their value moved (Beta divergence); every row the run computes costs one of `$steps`. The run works the facts callers chose first (its own and those earlier runs on the KB queued), for a share of `$steps` (`set-forward-seed-share`), then everything the agenda holds, and carries what it leaves to the next run. With no facts it continues that agenda only; with no steps it only queues its facts. Stores the values of the derived keys it built on in `&kb`, where later queries read them as facts, and returns them. A returned fact's proof is a reference, `(proof-ref N)`, into the proof store, as its stored copy's is, so a run's cost does not grow with the length of the derivations behind it; a query for the statement prints the full proof. |
| `(chainer $steps $goal)` / `(chainer-materialize $steps $goal)` | Lower-level backward chainer over an already-compiled goal. A result's proof refers to stored proofs, as a `query-many-refs` answer's does. |
| `(chainer-many $steps $goals)` / `(chainer-many-materialize $steps $goals)` | Lower-level multi-root variants over compiled goals; return one result list per input goal. Duplicate and common subgoals share their skeleton nodes. |
| `(compileQuery $kb (: $prf $Type $tv))` / `(mm2compileQuery $kb $stmt)` | Compile a query without running it. `compileQuery` returns `(compilation-plan goal additions)`; `mm2compileQuery` returns the runtime-encoded equivalent. Advanced. |

## Timing

| Function | Meaning |
|---|---|
| `PeTTaChainer.timing()` (Python) | Process-wide seconds of the chainer calls made so far (adding, querying, forward chaining, expanding proofs): `wall` as the caller sees them, the `inference` within them (activating what was added, search and evaluation of queries, forward runs) and `overhead`, the rest (the Python layer, reading the call, compiling queries, their temporary additions, reading and printing results, storing statements), with the number of `calls`. Differences of two readings time a span. It costs two clock reads per query and nothing per call to Python; a query run in a timed subprocess counts as overhead. With query metrics on, each record also carries `inference_seconds` and `overhead_seconds`. |

Python's add, query and expand calls pass their arguments to the chainer function directly when they are data; an argument holding a call (`(STV (/ 1 2) 0.9)`) or a lambda is evaluated first, as a MeTTa runnable evaluates it.

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
| `(set-positive-only-predicate $kb $head)` | Declare that `$kb` stores only the true instances of predicate `$head` (logic KBs of Provable, Path or Ancestor facts); declare before adding the rules that would be inverted onto it. Its stored instances are then no sample of its population: no inversion or antecedent completion is compiled onto a pattern with a conjunct of it, a root of it gets no population prior, and an STV rule whose antecedent has a conjunct of it derives its negative branch without the antecedent's rate, so P(B | A) applies as stated instead of being reconciled with a rate of 1. Undeclared predicates read their base rate as the prior of one more member, its mean under the Bayes prior (`set-bayes-prior-count`), whatever the rate (see `prior_factored_merge.md`). Python: `PeTTaChainer.set_positive_only_predicate(head)`, which timed subprocess queries replay. |
| `(set-rule-refinement $kb $enabled)` | Opt `$kb` into rule refinement; set it before adding the rules. A refined rule applies with the revision of its stored truth and the fold of its instances, and is searched in proportion to what that truth can add (see LANGUAGE_SPEC, "Refining rules from their instances"; hypotheses: docs/metta/hypothesis_rules.md). Python: `PeTTaChainer.set_rule_refinement(enabled)`, which timed subprocess queries replay. |
| `(set-rule-change-hazard $kb $hazard)` | Set the prior probability that a sample of one of `$kb`'s refined rules starts a new regime of the rule's rate; set it before adding the rules. The default, 0.0001 (one change in 10^4 samples of a branch), is on; 0 keeps one regime, every sample counting alike. Each branch of a rule's instance tally (P(B\|A), P(B\|not A)) keeps its samples as an old regime, the current one and a candidate run since a possible change, and its truth is the posterior mixture over where the rate changed: the posterior mean strength on the posterior mean evidence. On samples of one rate the no-change hypothesis takes the posterior and the truth is the one in one regime; after a change the new samples take over as their evidence grows; an old regime that returns is merged with its earlier samples, so they count at once. Nothing is cut: a regime is dropped only when a third distinct one needs its place. Constant cost per sample; the order is the order samples' values arrive (docs/metta/hypothesis_rules.md, "Regimes"). Python: `PeTTaChainer.set_rule_change_hazard(hazard)`, which timed subprocess queries replay. |
| `(set-hypothesis-mining $kb $max-new $max-live)` | Opt `$kb` into proposing its own hypotheses (`$max-new` 0, the default, turns it off; off, an added fact costs one lookup). Only predicates with a declared place in time (`set-predicate-time`) are mined. Each true fact of one added afterwards (strength above 0.5) is related to the recent true facts sharing a constant with it at its time point and at the adjacent ones (`set-time-link`), whichever arrived first: the fact at the earlier time point, or at one time point of the lower layer, is the antecedent, and equal layers are not related. It may propose refined rules with a weak prior (STV, or CTV when no conjunct is a positive-only predicate, at strength 0.5 with the evidence of 0.01 observations): from a pair of a time point's facts at once (a pair whose two facts share another constant also in its relational form), from one fact, across a link with the link as a conjunct, once it recurs at another instance with other companions. Nothing concludes a positive-only predicate. At most `$max-new` per fact; a consequent pattern keeps at most `$max-live` live hypotheses, and a dropped one is never proposed again. Turns rule refinement on (docs/metta/hypothesis_rules.md, "Mining hypotheses"). Python: `PeTTaChainer.set_hypothesis_mining(max_new, max_live)`, which timed subprocess queries replay (not the reviews). |
| `(set-predicate-time $kb $head $position $layer)` | Declare where predicate `$head` sits in time for hypothesis mining: its facts refer to the time point at argument `$position` (counted from 1), and within one time point a fact of a lower `$layer` may be an antecedent of one of a higher layer, never the reverse. Mined facts are grouped and ordered by these, never by arrival. Python: `PeTTaChainer.set_predicate_time(head, position, layer)`, which timed subprocess queries replay. |
| `(set-time-link $kb $link)` | Declare that `($link $earlier $later)` facts make time point `$earlier` the one before `$later`. Hypothesis mining then relates facts of adjacent time points that share a constant, the earlier as the antecedent with the link as a conjunct and only the time points as variables: `(And (NextPeriod $q $p) (Storm north $q)) → (Storm north $p)`. Such a candidate is not proposed once a live hypothesis concludes its consequent from its own time point. Link facts are not mined themselves. Python: `PeTTaChainer.set_time_link(head)`, which timed subprocess queries replay. |
| `(review-hypotheses $steps $kb $goal)` | Review the live mined hypotheses that apply to `$goal` (for a ground goal, those whose consequent unifies with it and whose antecedent then holds of stored facts; a variable reviews all): one query reads their truths, with `$steps` for each hypothesis no review has read yet (its first read folds its instances) and no budget otherwise, since the chainer keeps the truths current. A hypothesis whose truth rests on enough samples is dropped when its strength does not differ, by two standard errors, from the consequent's probability without its antecedent (a CTV's learned negative branch; without one this test is skipped) or from a more general live hypothesis's strength; one whose consequent was observed 32 times without enough samples of its own is dropped too. A dropped hypothesis's rules leave the rule indexes, so no later search applies them. Yields `(hypothesis name implication truth kept\|dropped)` per hypothesis. Python: `PeTTaChainer.review_hypotheses(goal, steps)`. |
| `(set-evidence-confidence-k $k)` | Set PLN's evidence parameter k (default 800): n observations have confidence n/(n+k). Process-wide and read when a formula runs, so set it before adding knowledge; values already derived keep their k. Python: `PeTTaChainer.set_evidence_confidence_k(k)`, which timed subprocess queries replay. |
| `(set-bayes-prior-count $a)` | Set the pseudo-observations of the prior with which Bayes' rule and inversion read a likelihood estimated from finite evidence (default 0.2). The prior is centred on independence (the pooled P(B) of both branches, or P(B) for P(B\|A)), so a likelihood from few observations moves a belief little instead of making it certain; certain likelihoods are read as they are. Process-wide. Python: `PeTTaChainer.set_bayes_prior_count(a)`, which timed subprocess queries replay. |
| `(set-forgetting $horizon $decay)` | Freeze a key that got no row and was not needed for `$horizon` epochs (0, the default: never): at the next `advance-epoch` its rows, views and caches are dropped and what they derived becomes one summary fact, proof `(forgotten <key-hash> <epoch>)`, whose observation count is multiplied by `$decay`. The summary keeps the value's evidence and depends on the keys within two derivation steps. Process-wide. Python: `PeTTaChainer.set_forgetting(horizon, decay)`. |
| `(advance-epoch)` | End an epoch and freeze the keys idle for the forgetting horizon; returns the new epoch. Python: `PeTTaChainer.advance_epoch()`. |
| `(set-forward-min-evidence $n)` | Set the least evidence, in observations (n = c·k/(1−c)), a derived key's value needs for a forward run to build on it (default 1). Process-wide. Python: `PeTTaChainer.set_forward_min_evidence(n)`. |
| `(set-forward-seed-share $share)` | Set the share of a forward run's steps the facts callers chose and no run has taken yet get before carried derived keys compete for the rest (default 1, the chosen facts first; 0 ranks everything together). Process-wide. Python: `PeTTaChainer.set_forward_seed_share(share)`. |
| `(set-bounded-agenda-pruning $enabled)` | Toggle forward-agenda pruning. Skeleton backward search is bounded by its expansion and row budgets. |
| `(ParticleSetBudget $n)` / `(ParticleGetBudget)` | Set / read the maximum particle support. Over-budget structured numeric samples are condensed as complete vectors; bare numeric or symbolic samples use deterministic systematic resampling. |
| `(ParticleStoreClear)` / `(ParticleStorePruneKB)` | Clear the particle store / garbage-collect particles no longer referenced by the KB. |

### Python compact query diagnostics

`PeTTaChainer.query_with_diagnostics(atom, steps=100, *, max_goals=32,
max_routes=32, max_bytes=32768)` runs one query in the owning live process
and returns its ordinary `proofs` with a bounded `diagnostics` object (schema
version 1). It turns query metrics on for the query and restores the caller's
setting. There is no subprocess timeout: bound the owning process when a
deadline is required. `pettachainer.query_diagnostics.snapshot(chainer,
metrics, max_goals, max_routes, max_bytes)` reads the same snapshot again,
with other limits, from the skeleton the last query left and that query's
`last_query_metrics()`, without inferring anything.

The snapshot walks the last query's roots and their children breadth first,
reading child links, waiting joins, stored facts, cached merged values and the
pending-work index; it never evaluates, expands or starts anything. A goal's
`proof_count` counts its answers that have a cached value or a stored fact; a
supported goal ends the walk below it. `expanded` says whether its node was
expanded, and `work_requested` whether the search still has work at or below
it (it is unexpanded, or the pending-work index holds work below it). A
route with `origin` `continuation` is a join waiting on the child premise:
`remaining_premises` are the statements it still needs, and
`supported_evidence` the stored facts of the premises it has bound. An
expanded goal with no support also lists, as `candidate` routes, the rules
concluding it that have no join there (dormant rules, rules pruned because a
ground premise had no fact and no rule, inverted rules), one per statement
premise: they are leads, not executable paths or missing facts. Each record
keeps the variables its terms share. Temporary query scaffolds leave with the
query and are not represented (an `Assuming` query's context leaves with all
its nodes, so its snapshot has no goals), nor are fold goals (`CPU`), which
the walk passes through.

`termination.reason` is `budget_exhausted` when the budget left work this
query needed: a root whose search has work left, answer deliveries still
queued for want of rows, rows its evaluation could not pay to compute
(`rows_unpaid` metric), or conditioning it could not pay for
(`conditions_unpaid`). `agenda_entries` counts those items and is positive
exactly then; otherwise the reason is `agenda_exhausted`, which means no
computational cutoff, not logical completeness or falsity. `pruned_entries`
is 0: backward search prunes nothing a budget could reach. Limits apply to the
walk and to the serialized JSON; goal counts are lower bounds when the walk
stops early, and a truncated snapshot is not complete research feedback.
Support counts are observations, not counts of independent evidence, and do
not establish admissibility to every consumer.
