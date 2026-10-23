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

`compileadd` checks the complete evaluated source annotation before compiling
or publishing it. An ordinary fact must have **no free statement variables**.
`(: f ($predicate a b) (STV 1 1))`, `(Pair $x $x)` and `(P $y)` as facts
raise `domain_error(fact_without_free_variables, ...)`, with the message
`fact contains free variables`. Python `add_atom` and `add_atoms_no_check`
surface this as `janus_swi.PrologError`. Rejection publishes no compiled
facts, rules or ingestion observations for that input. Bulk Python ingestion
keeps its successfully added prefix, including its timed-worker replay journal.

A proof name, with its statement and context, is one observation's identity.
Restating it with the same value is accepted, values compared by number:
`(STV 1 1)` restates `(STV 1.0 1.0)`, and `(Not (P a))` at 0.8 restates
`(P a)` at 0.2. A different value raises `permission_error(restate, proof,
Name)` (#113). A new
observation of the same statement takes a new name and revises with the old.

Scope is lexical to each occurrence, with actual constant heads and the stated
arities (a variable head never becomes a binder by unification):

- `Implication antecedent consequent` binds all variables in its two sides.
  Configured bidirectional implication forms (default `BiImplication`) do too.
- `ForAll params body` and `Exists params body` bind exactly the variables
  occurring in `params`, only inside `body`. Other body variables remain free.
- The supported rule wrappers `WithPrior prior (Implication ...)`,
  `ForAll params (Implication ...)`, and
  `ForAll params (WithPrior prior (Implication ...))` carry the complete
  rule schema, including prior variables. Variables remain allowed in rules.
- A nested rule or binder in a predicate argument is scoped quoted content.
  Thus `(ClaimContent Finding (Implication (P $x) (Q $x)))` is a valid fact,
  as are quoted `ForAll` and `Exists` bodies with no free variables. Storing
  quoted content does not execute that content or assert its conclusion.
  An occurrence of `$x` outside that nested scope is still free, even when
  the same name occurs inside it. `RuleTruth` itself introduces no binder;
  its nested implication does. `WithPrior` without an implication is not a
  binder. Strings containing `$` are literal data.

Queries keep their variables, including variable predicate heads. Groundness
validation does not apply to query compilation or internal rule products.
Existing restrictions on executable existential syntax still apply.

| Function | Meaning |
|---|---|
| `(set-max-term-bytes $kb $limit)` | Set the KB's maximum source annotation size, a positive integer, default **65536 bytes (64 KiB)**. Python: `PeTTaChainer.set_max_term_bytes(limit)`. Existing add/query signatures are unchanged. |

The limit counts UTF-8 bytes in the canonical MeTTa serialization of the
complete evaluated `(: proof statement tv)` annotation, including parentheses,
spaces, string escaping, proof and TV. Whitespace/comments in the input do not
count; variable names are canonicalized by PeTTa's serializer. It applies to
both facts and rules, including closed quoted content. Oversized input raises
`resource_error(stored_term_bytes(actual, limit))`, with the message
`stored term exceeds max-term-bytes`, before compilation publishes anything.
Invalid native limits raise a Prolog type/domain error; Python rejects invalid
limits with `ValueError`. Settings are KB-local, affect subsequent additions,
and are replayed before loading knowledge in timed query workers. The cap is
an ingestion bound; compiler-generated views and derived proofs are not
revalidated as authored source annotations.

The live `&kb` keeps every added fact as stored; several facts of one
statement are merged where they are read, as leaves of the backward search.
Only stored binary-certain facts, STV strength 0 or 1 at confidence >= 1,
are absorbing for search retirement. Fractional strength at confidence 1
and derived certain values retain their backward derivations.
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
| `(query $steps $kb $stmt)` | Backward-chain up to `$steps` expansions to answer `$stmt` against `$kb`; yields the proven results. A larger budget extends the same search order. `$steps` also scales the query's allowances for walking already-built search state and for recomputing values; the values within two steps of its roots draw first on a reserve proportional to how many there are, so they are brought current at any budget; work beyond both is left for later queries. Stored facts cost no expansion, so a zero-step query answers from stored facts and from what earlier queries derived through permanent rules. When the search has no value for a statement, a result an earlier query materialized is returned instead. The premise prefilter skips a candidate before search state is created only when a ground deterministic CPU premise fails; missing fact premises retain ordinary join subscriptions for later additions. |
| `(query $steps $kb (: $prf (Implication $a $b) $tv))` | Always returns an STV for the positive judgment P(b given a). Reads a stated implication first (also at zero budget), including an explicitly negated antecedent or the corresponding negative branch of a stated CTV; every reader of an assumed ground antecedent uses its assumed truth, excluding its main-world value. An STV application contributes zero confidence and no evidence when hypothetical assumptions alone make its ground antecedent false. Variable antecedents retain the population-inferred complement. Merges stated and calculated evidence without counting the same rule twice, with the stored/derived statement provenance, a proof `(conditional-implication ...)`, or their revision with empirical instance evidence. `$tv` may be open or an STV pattern; a CTV answer pattern has no answer. CTVs are internal rule storage, used by modus ponens, and never query answers. Ask `(Implication (Not $a) $b)` explicitly for the negative statement; its empirical instance evidence is `$a`'s instance fold read on the instances where `$a` is false (one fold and one set of samples for both queries), with no instance answer before such an instance is seen. A nested implication `A -> (X -> Y)` is judged in exported form `(And A X) -> Y`, assuming all antecedents and proving the innermost consequent. Its answer retains the stated nested shape: `(: <proof> (Implication A (Implication X Y)) (STV <P(Y given A,X)> <confidence>))`. Each antecedent remains a query-local assumption; a source gate is never accepted in the main KB by querying its implication. Rules and computed-premise adapters remain available in the hypothetical context. World observations of other statements serve as co-premises there, never a world value of the consequent (#63), and a calculated answer must depend on the assumed antecedent: world support for the consequent alone gives no calculated answer (#65). See `derived_implications.md`. |
| `(query $steps $kb (: $prf (And <conjunct> ...) $tv))` | Ordinary STV And over the queried statements, with shared-evidence conditioning. An implication conjunct contributes only its positive STV, so `(And M (Implication G Y))` answers `(: <proof> (And M (Implication G Y)) (STV <strength> <confidence>))`; the answer preserves the conjunction shape and contains no added negative conjunct. To request both statements, write `(And M (Implication G Y) (Implication (Not G) Y))`. Conjuncts are statements; a nested `(: proof statement tv)` selector raises `domain_error(weighted_assumption, ...)`. |
| `(query $steps $kb (: $prf (Assuming $facts $goal) $tv))` | Prove `$goal` as if `$facts` (a statement or an `And` of them, implications included) were stored, together with everything the KB holds; nothing assumed is stored. A bare fact is certain. A fact written `(: name statement tv)` keeps its value, as `compileadd` would store it: an ordinary closed fact or `Not` fact with an STV, or an implication with an STV or CTV, whose variables are its own as a stored rule's are (#127), with both sides given and a plain consequent. Any other annotation, or one in any other statement position of a query, raises `domain_error(weighted_assumption, ...)`; a bare implication with a variable side or a nested-implication or existential consequent raises `domain_error(assumed_rule, ...)`. `Assuming` is only the outermost query statement; one anywhere else raises `domain_error(nested_assuming, ...)` (#125), and one without exactly its facts and a goal `domain_error(assuming_arguments, ...)`. Known limits: an assumed CTV rule that MAIN also states does not combine as two stored rules do (#123), base-rate reads use MAIN's population (#124), and a judgment of an assumed implication itself has no answer (see [weighted assumptions](assumption_queries.md#weighted-assumptions-tracker-120)). Answers have proof `(assuming ...)`, one per binding of `$goal`'s variables. MAIN keys and rows are shared; unchanged values are read in MAIN. Only changed values live in the context overlay. Independent cold MAIN work persists after cleanup. Each context evaluates with its own allowance scaled by `$steps`, so a batch of N contexts may spend N times one query's evaluation (#55). |
| `(query-materialize $steps $kb $stmt)` | As `query`, but also writes back the first result and, for every statement its proof uses, that statement's current value. Positive implication judgments use a private query context and are never materialized as world facts. An unpaid clash's waiting estimate may be returned but is not materialized. |
| `(query-many $steps $kb $statements)` | Compile every statement, inject their temporary additions once (alpha-equivalent additions of different roots as one), and answer all roots in one shared backward search. `$steps` is one total expansion budget. All roots share one priority order: a goal's priority is the best score any join waiting on it gives it. Emits `(query-result $index $answer)` for each answer. A ground root the search leaves without a value answers its population prior, `(population-prior <pattern>)`, when one of its rules reads a base rate over its population, as the prior of one more member (the rate under the Bayes prior, `set-bayes-prior-count`) and its predicate is not positive-only (`set-positive-only-predicate`); other unanswered roots emit no row. Python: `PeTTaChainer.query_many(statements, steps)` returns an input-aligned `list[list[str]]`, including empty lists for unanswered roots. |
| `(query-many-refs $steps $kb $statements)` | As `query-many`, but each answer's proof is left as the value holds it: a reference `(proof-ref N)` into the proof store, a fact's name, or a merge of references. No proof is expanded or printed, so an answer's size does not grow with its derivation. Python: `PeTTaChainer.query_many_refs(statements, steps)` returns an input-aligned `list[list[Answer]]`, each `Answer(proof, statement, tv)` passed as terms through janus (an expression is a list, a symbol or string a `str`, a number an `int` or `float`, a variable a `str` starting with `$`). It runs in the caller's live process, which holds the proofs the references point to. The latest public query batch retains its reference proofs through collection, including after hypothetical context cleanup. The next public query replaces that batch; expand a borrowed proof first if its text must outlive the batch. |
| `(expand-proof $proof)` | The full proof of a proof that refers to stored proofs, as `query` prints it: a stored subproof referenced more than once appears in full at its first occurrence as `(shared N proof)` and as `(shared N)` after that. Python: `PeTTaChainer.expand_proof(answer.proof)` returns its text. |
| `(query-many-materialize $steps $kb $statements)` | As `query-many`, but materializes each root's first result and the current values of the statements its proof uses. Unpaid clash waiting estimates are returned without being materialized. Python: `PeTTaChainer.query_many_materialization(statements, steps)` runs in the caller's live process so the KB writes persist. |
| `(forward-chain $steps $kb $facts)` | Forward-chain from a caller-selected list of compiled facts. The run grows the backward skeleton upward from them: rules triggered by a taken key join it with the facts and keys that already exist, and the rows are evaluated as a query evaluates them. Keys are taken by how far their value moved (Beta divergence); every row the run computes costs one of `$steps`. The run works the facts callers chose first (its own and those earlier runs on the KB queued), for a share of `$steps` (`set-forward-seed-share`), then everything the agenda holds, and carries what it leaves to the next run. With no facts it continues that agenda only; with no steps it only queues its facts. Stores the values of the derived keys it built on in `&kb`, where later queries read them as facts, and returns them. A returned fact's proof is a reference, `(proof-ref N)`, into the proof store, as its stored copy's is, so a run's cost does not grow with the length of the derivations behind it; a query for the statement prints the full proof. |
| `(chainer $steps $goal)` / `(chainer-materialize $steps $goal)` | Lower-level backward chainer over an already-compiled goal. A result's proof refers to stored proofs, as a `query-many-refs` answer's does. |
| `(chainer-many $steps $goals)` / `(chainer-many-materialize $steps $goals)` | Lower-level multi-root variants over compiled goals; return one result list per input goal. Duplicate and common subgoals share their skeleton nodes. |
| `(compileQuery $kb (: $prf $Type $tv))` / `(mm2compileQuery $kb $stmt)` | Compile a query without running it. `compileQuery` returns `(compilation-plan goal additions)`; `mm2compileQuery` returns the runtime-encoded equivalent. Advanced. |

`(set-context-reuse-threshold threshold)` / Python
`PeTTaChainer.set_context_reuse_threshold(threshold)` sets Assuming's propagation
threshold (nonnegative Beta KL divergence, default `1e-6`; zero propagates exact
value and compatibility changes). The setting is process-wide and replayed by
timed workers. Assuming inherits MAIN's user priors; see
[the prior-inheritance correction](assumption_queries.md#accepted-prior-inheritance-correction).

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

A bare `(Exists ($x ...) $body)` query and an existential rule antecedent use
one judgment: the maximum **strength** of the direct `ExistentialClaim` and the
OR of known witness tuples, with the winning judgment's confidence and proof.
The channels never revise together. Strength decides first; on an exact strength
tie, higher confidence (more evidence) wins without revision. Equal TVs use the
alpha-normalized statement-key order, so discovery order does not choose a proof.
Free outer variables produce one answer per binding. Empty or unfinished search
has no value; `set-complete-predicate` does not close the existential population.
Any shared uncertain fact dependency collapses the **whole witness population**
to its single strongest member. Two correlated witnesses at 0.5 plus an
independent witness at 0.4 still give 0.5, not 0.7. The result carries only the
chosen witness's proof and evidence; all member dependencies remain for
recomputation. A shared uncertain rule alone does not count as overlap.

Exact queries of stored rules with `Exists` on a complete antecedent or
consequent return their stated STV, including at budget zero and with renamed
binders. Matching uses canonical scoped slots, syntactically up to renaming:
conjunct order and co-reference must agree. Public expressions reconstruct local
binders, retaining outer sharing and source proof IDs. A non-constructive claim
never fabricates a witness.

A non-stored quantified implication is judged by assuming its antecedent in a
private context and proving its consequent through the KB's rules. An existential
antecedent installs one canonical `ExistentialClaim` at (1,1), never its body or a
witness. The answer is the positive-branch STV; its `conditional-implication`
proof retains every source rule. Complete-side existential consequents use the
same direct-claim/witness judgment as bare queries. An axiom and its own
application share rule evidence and cannot revise one another as independent.

`Assuming` accepts a complete existential fact, or such facts among an `And` of
assumptions, and a bare existential goal. It uses the same contextual claim and
retains its ordinary world-reading behavior. Local binders are fresh in public
answers; free outer variables remain shared. No hypothetical claim, witness,
body fact, or categorical consequence is published to MAIN.

Nested binders, quantified nested implication export, quantified implications
as Assuming goals, assumed implications with an existential consequent, and `Not (Exists ...)` remain unsupported. Existentials must
occupy a complete implication side; moving them across connectives is not
inferred. Existential completion and overlap-aware witness OR are deferred.
See [Existential queries and premises](explicit_exists.md) for semantics,
costs, scope, and changed expectations.

Two complete-side premise forms expose the relationship between a direct claim
and the witnesses currently enumerable from the KB:

| Form | Meaning |
|---|---|
| `(KnownExistential ($x ...) $body)` | Fold the truth values of matching body instances with `OrFormula`. This is the currently enumerated witness disjunction D, not a proof that the population is complete. |
| `(ExistentialResidual ($x ...) $body)` | Match the corresponding direct `ExistentialClaim`, build D, and calculate U from E = D or U using `ExistentialResidualFormula`. Its confidence is propagated from both E and D. |

Both are lazy, budgeted FoldAll producers. An empty `KnownExistential` has no
value. For `ExistentialResidual` only, empty D is `(STV 0 1)`: no known witness
contributes zero witness mass, so U retains E's strength. This is an accounting
identity for the residual, not a false existential judgment or a population
completion claim. As new witness facts become available, their aggregate proofs refine without retracting the direct
existential proof. See `examples/metta/existential_residual.metta` for a runnable
example in which two weak known cats leave a strong residual and a later Felix
witness moves support from that residual into the enumerated disjunction.

## Base rates

| Function | Meaning |
|---|---|
| `(set-base-rate-smoothing $kbid $enabled)` | Opt `$kbid` into reading each computed base rate as a Beta estimate: over n observations its strength is (Σs + k/2)/(n + k), its evidence plus k pseudo-observations at 0.5, and its confidence n/(n+k) is unchanged, so a rate over few observations is not taken as certain. Set it before adding knowledge; user base rates are kept as set. Python: `PeTTaChainer.set_base_rate_smoothing(enabled)`, which timed subprocess queries replay. |
| `(set-base-rate $kbid $pattern $tv)` | Pin a user-provided base rate for `$pattern` (overrides computed values and positive-only sampling). A conjunction with disconnected variable components has a Cartesian-product rate and rejects a separate joint override with `domain_error(disconnected_base_rate, pattern)` before changing the cache; set the component rates instead. Conjunctions sharing variables accept joint rates. The folds over `$pattern` and their readers recompute at the next query. |
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
| `(set-functional-predicate $kb $head $arity $key-positions)` | Declare an immutable input relation before adding its facts or rules. Positions are sorted, unique, counted from 1, nonempty, and leave at least one value argument. All remaining arguments together form the value. This also declares the predicate positive-only. Only ground certain-true STV inputs are allowed; the first value fixes a key. Repeating that same tuple is allowed; a different tuple for the same key is rejected before publishing that fact, including via bulk/no-check ingestion. Negative, uncertain, open or wrong-arity facts, and rules (including temporary query rules) deriving this relation, are rejected. Earlier additions in a bulk operation remain. The declaration is idempotent and cannot be changed; use a new KB for a corrected value. Unassigned keys remain open; no absent values or negative samples are invented. Main-world facts alone assign keys; private assumptions do not close world subscriptions. Waiters for incompatible values retire through the existing bounded retirement queue; a matching subscription closes only after consuming its unique answer. Stored facts, rows and sample tallies remain. Python: `PeTTaChainer.set_functional_predicate(head, arity, key_positions)`; timed subprocess queries replay it. Examples: `("NextPeriod", 2, (1,))`; `("At", 3, (1, 3))` for `(At object value time)`. This API does not declare probabilistic or rule-derived functional relations. |
| `(set-complete-predicate $kb $head)` | Declare that the rules and facts of predicate `$head` in `$kb` are the only ways one of its statements becomes true (Clark completion, well-founded on loops); declare before adding knowledge. A ground statement of it in the main context or an `Assuming` query's context whose search is settled reads its derivations through a reading rule's own complete conclusion as unfounded, `(STV 0.0 1.0)`, and is itself unfounded when no rule application derives it; a budget that has not examined every rule application concludes nothing (see `complete_predicates.md`). Undeclared predicates stay open-world. Python: `PeTTaChainer.set_complete_predicate(head)`, which timed subprocess queries replay. |
| `(set-positive-only-predicate $kb $head)` | Declare that `$kb` stores only the true instances of predicate `$head` (logic KBs of Provable, Path or Ancestor facts); declare before adding the rules that would be inverted onto it. Its stored instances are then no sample of its population: without an explicit `set-base-rate` for the pattern, inversions and antecedent completions onto it give no value, a root of it gets no population prior, and an STV rule whose antecedent has a conjunct of it derives its negative branch without the antecedent's rate, so P(B | A) applies as stated instead of being reconciled with a rate of 1. An explicit `set-base-rate` overrides this sampling restriction, including when supplied after rule compilation; clearing it restores the restriction. Undeclared predicates read their base rate as the prior of one more member, its mean under the Bayes prior (`set-bayes-prior-count`), whatever the rate (see `prior_factored_merge.md`). Python: `PeTTaChainer.set_positive_only_predicate(head)`, which timed subprocess queries replay. |
| `(set-rule-refinement $kb $enabled)` | Opt `$kb` into rule refinement; set it before adding the rules. A refined rule applies with the revision of its stored truth and the fold of its instances, and is searched in proportion to what that truth can add (see LANGUAGE_SPEC, "Refining rules from their instances"; hypotheses: docs/metta/hypothesis_rules.md). Python: `PeTTaChainer.set_rule_refinement(enabled)`, which timed subprocess queries replay. |
| `(set-rule-change-hazard $kb $hazard)` | Set the prior probability that a sample of one of `$kb`'s refined rules starts a new regime of the rule's rate; set it before adding the rules. The default, 0.0001 (one change in 10^4 samples of a branch), is on; 0 keeps one regime, every sample counting alike. Each branch of a rule's instance tally (P(B\|A), P(B\|not A)) keeps its samples as an old regime, the current one and a candidate run since a possible change, and its truth is the posterior mixture over where the rate changed: the posterior mean strength on the posterior mean evidence. On samples of one rate the no-change hypothesis takes the posterior and the truth is the one in one regime; after a change the new samples take over as their evidence grows; an old regime that returns is merged with its earlier samples, so they count at once. Nothing is cut: a regime is dropped only when a third distinct one needs its place. Constant cost per sample; the order is the order samples' values arrive (docs/metta/hypothesis_rules.md, "Regimes"). Python: `PeTTaChainer.set_rule_change_hazard(hazard)`, which timed subprocess queries replay. |
| `(set-hypothesis-mining $kb $max-new $max-live)` | Opt `$kb` into proposing its own hypotheses (`$max-new` 0, the default, turns it off; off, an added fact costs one lookup). Only predicates with a declared place in time (`set-predicate-time`) are mined. Each true fact of one added afterwards (strength above 0.5) is related to the recent true facts sharing a constant with it at its time point and at the adjacent ones (`set-time-link`), whichever arrived first: the fact at the earlier time point, or at one time point of the lower layer, is the antecedent, and equal layers are not related. It may propose refined rules with a weak prior (STV, or CTV when no conjunct is a positive-only predicate, at strength 0.5 with the evidence of 0.01 observations): from a pair of a time point's facts at once (a pair whose two facts share another constant also in its relational form), from one fact, across a link with the link as a conjunct, once it recurs at another instance with other companions. A false fact is concluded the same way where no live hypothesis concluded the candidate's consequent before it (singles recurring among failures), so a statement that never holds learns its failure, and where a live hypothesis predicted it, by the pairs of its context containing a fact the prediction read. Nothing concludes a positive-only predicate. At most `$max-new` per fact; a consequent pattern keeps at most `$max-live` live hypotheses, and screened candidates become eligible for ordinary proposal again when their current instance fold distinguishes them from their recorded screening rule by more than two current standard errors (or that screening rule is withdrawn), reconsidered only on that key’s change at a subsequent review. Other drops remain final. Turns rule refinement on (docs/metta/hypothesis_rules.md, "Mining hypotheses"). Python: `PeTTaChainer.set_hypothesis_mining(max_new, max_live)`, which timed subprocess queries replay (not the reviews). |
| `(set-predicate-time $kb $head $position $layer)` | Declare where predicate `$head` sits in time for hypothesis mining: its facts refer to the time point at argument `$position` (counted from 1), and within one time point a fact of a lower `$layer` may be an antecedent of one of a higher layer, never the reverse. Mined facts are grouped and ordered by these, never by arrival. Python: `PeTTaChainer.set_predicate_time(head, position, layer)`, which timed subprocess queries replay. |
| `(set-time-link $kb $link)` | Declare that `($link $earlier $later)` facts make time point `$earlier` the one before `$later`. Hypothesis mining then relates facts of adjacent time points that share a constant, the earlier as the antecedent with the link as a conjunct and only the time points as variables: `(And (NextPeriod $q $p) (Storm north $q)) → (Storm north $p)`. Such a candidate is not proposed once a live hypothesis concludes its consequent from its own time point. Link facts are not mined themselves. Python: `PeTTaChainer.set_time_link(head)`, which timed subprocess queries replay. |
| `(set-observed-predicate $kb $head)` | Declare that the statements of predicate `$head` in `$kb` are observed: once a true `($link earlier later)` fact (`set-time-link`) reaches a time point, each ground statement of `$head` at it that a rule of `$kb` concludes (the rule's conclusion with the time argument of `set-predicate-time` a variable and the rest ground) and that has no stored fact is stored false, `(: unobserved-<hash> S (STV 0.0 1.0))`. So a rule whose predicted event did not come gets a negative sample (ONA's anticipation). The client states a time point's observations before the link into it; a fact stated after it is not reconciled. Declare before adding knowledge (docs/metta/observed_predicates.md). Python: `PeTTaChainer.set_observed_predicate(head)`, which timed subprocess queries replay. |
| `(review-hypotheses $steps $kb $goal)` | Review the live mined hypotheses that apply to `$goal` (for a ground goal, those whose consequent unifies with it and whose antecedent then holds of stored facts; a variable reviews all): one query reads their truths, with `$steps` for each hypothesis no review has read yet (its first read folds its instances) and no budget otherwise, since the chainer keeps the truths current. A hypothesis whose truth rests on enough samples is dropped when its strength does not differ, by two standard errors, from the consequent's probability without its antecedent (a CTV's learned negative branch; without one this test is skipped) or from a more general live hypothesis's strength (the SE variance floor never shifts the reference strength); one whose consequent was observed 32 times without enough samples of its own is dropped too. A dropped hypothesis's rules leave the rule indexes, so no later search applies them. Yields `(hypothesis name implication truth kept\|dropped)` per hypothesis. Python: `PeTTaChainer.review_hypotheses(goal, steps)`. |
| `(set-evidence-confidence-k $k)` | Set PLN's evidence parameter k (default 800): n observations have confidence n/(n+k). Process-wide and read when a formula runs, so set it before adding knowledge; values already derived keep their k. Python: `PeTTaChainer.set_evidence_confidence_k(k)`, which timed subprocess queries replay. |
| `(set-bayes-prior-count $a)` | Configure heterogeneity κ (default 0.2), process-wide; the signature is unchanged. #69's weight uses an independently justified centre's confidence. All reads follow [the prior definition](prior_definition.md): same-class revision, incomparable-general mixtures, provenance-checked leave-one-out branch centres, neutral population/finite-instance priors, and one read of inferred negative branches. Certain facts remain exact; κ=0 disables statistical smoothing. Prior reads add no likelihood evidence. Python `set_bayes_prior_count(a)` and timed replay retain their signatures. No κ fitting is performed. |
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
concluding it for which no join is present, including dormant rules. A
candidate binds the rule's premises in order by the stored facts that answer
them, as its join would, one route per binding: the child is the first
statement premise without a stored fact, `remaining_premises` the statements
from it on, and `supported_evidence` the facts bound before it (a rule whose
every premise has a fact gives none). So `(LocatedIn FactoryA Coastvale)` with
`(LocatedIn $f $r) ∧ (Flooded $r) → (Disrupted $f)` and no `Flooded`
knowledge gives the gap `(Flooded Coastvale)` with the location as evidence.
Candidates are leads, not executable paths: a gap premise may still be
derivable by rules. Each record
keeps the variables its terms share. Temporary query scaffolds leave with the
query and are not represented (an `Assuming` query's context leaves with all
its nodes, so its snapshot has no goals), nor are fold goals (`CPU`), which
the walk passes through.

`termination.reason` is `budget_exhausted` when the budget left work this
query needed: a root whose search has work left, answer deliveries still
queued for want of rows, rows its evaluation could not pay to compute
(`rows_unpaid` metric), or conditioning it could not pay for
(`conditions_unpaid`). This includes a queried root whose deep conditioning
claim exhausted its structural slice (one eighth of evaluation, capped at 256
units / 512 conditioned rows). Such a claim sleeps on identical inputs to avoid
repeating the attempt; it remains unpaid and reports `budget_exhausted`.
A new KB input generation (facts, permanent rules or user base rates) or a larger
slice can re-enable it; further refinement of the same inputs does not. This does not enlarge the
query's ordinary budget. `agenda_entries` counts those items and is positive
exactly then; otherwise the reason is `agenda_exhausted`, which means no
computational cutoff, not logical completeness or falsity. `pruned_entries`
is 0: backward search prunes nothing a budget could reach. Limits apply to the
walk and to the serialized JSON; goal counts are lower bounds when the walk
stops early, and a truncated snapshot is not complete research feedback.
Support counts are observations, not counts of independent evidence, and do
not establish admissibility to every consumer.
