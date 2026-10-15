# Derived implications

Status: built, October 2026.

## Problem

A rule whose conclusion is an implication,

    (: r (Implication (A $x) (Implication (B $x) (C $x))) (STV 0.9 1.0))

concludes the statement `(Implication (B x) (C x))` from `(A x)`, but nothing
applied that statement to `(B x)`: the query `(C x)` had no answer, while the
flat rule `(Implication (And (A $x) (B $x)) (C $x))` gave 0.9. The derived
statement also had an STV whose negative branch came from the base rate of
`(Implication (B $x) (C $x))` as a population, which is meaningless.

The compiler never rewrote nested rules into their exported form
`(A ∧ B) → C`: the history (all branches, from the first commit on) and the
sibling chainers have no such rewrite. Nested implications were data in a
conclusion, or premises answered by the hypothetical scaffold.

## Rule

An implication statement the chainer derives is applied by modus ponens
like a rule. For each implication shape a rule concludes, the compiler adds
one **statement rule**:

    (: ctx (by $r $t) (Implication X Y) (CTV $pos $neg))
    X ...                                  ; X lowered as a rule antecedent
    |- (: ctx (by (by $r $t) <X proof>) Y <modus ponens>)

Its first premise reads the statement's key, its proof is the implication's
proof applied to the antecedent's, `(by <implication proof> <antecedent
proof>)`, the shape an assumed implication's application already has
(`Assuming`). The antecedent is lowered as any rule antecedent, so
conjunctions, `Not`, settling parts and conclusions under `Not` behave as in
an ordinary rule. When `Y` is itself an implication, the statement rule for
`Y` is added as well, so `A → (B → (C → D))` works at any depth.

The rule is found through the ordinary rule index, by its conclusion `Y`.
So it costs nothing when no rule concludes an implication, and one rule
match per goal otherwise. One statement rule is added per shape (alpha
equivalence) and knowledge base, in `&implication_statement_rules`, keyed by
the hash of the shape.

### Open statements

A statement's antecedent may have a variable that neither the rule's outer
antecedent nor the statement's consequent binds, as `$f` in
`(Implication (AcceptSource R) (Implication (And (A $a) (Rel $a $f)) (P $a)))`.
The derived statement is then an open key, `(Implication (And (A a) (Rel a
$f)) (P a))` for a goal `(P a)`: the implication's own variable, so a
statement for every `$f`. The statement rule's join reads it first and binds
`$f` later, through `(Rel a g)`; its row reads the open key it was extended
with, not the instance `(Implication (And (A a) (Rel a g)) (P a))`, which is
no key of its own and has no rows (`sk-read-step`, `skeleton.metta`). Before,
the row read that instance, found no value, and neither `(P a)` nor the
nested query had an answer unless the instance had been asked for first.

### Where statements come from

- **A rule concluding an implication** (the nested case): the source this
  note is about.
- **A statement rule whose conclusion is an implication**: the middle levels
  of a deeper nesting.
- **A stored implication** is compiled into a rule, as before; that rule is
  modus ponens over the stored truth, so it needs no statement rule. A
  stored implication and a derived one of the same statement are two
  proofs of the consequent; sharing only the antecedent's fact, they revise
  through the lifting merge (below).
- **Inversions** conclude antecedents, not implications. **Learned truths**
  are `RuleTruth` goals, read by their own rule only, so a refined rule is
  not applied twice. Implication queries (the hypothetical judgment and the
  instance fold) are not read by statement rules: their premise asks for a
  rule application's proof, `(by $r $t)`, and an implication premise asking
  for one does not install the hypothetical scaffold. Assuming B and proving
  C to apply `B → C` to B would re-prove C by the same rules that prove it
  directly and count their evidence twice, at the cost of two hypothetical
  contexts per application.

## Truth values

A rule `A → (X → Y)` holds as its exported form `(A ∧ X) → Y`: under that
reading P(X → Y | A) is P(Y | A, X), and P(X → Y | not A) is P(Y | X, not A),
a case of P(Y | not (A ∧ X)). So the rule's CTV is the exported rule's CTV:

- stated as an STV s, the negative branch comes from the base rates of the
  exported sides, `ImplicationCTVFormula(P(A ∧ X), P(Y), s)`, exactly as for
  the flat rule (the conjunctions of all nested antecedents, flattened, and
  the innermost consequent);
- stated as a CTV, it is that CTV.

The derived statement is a CTV, `ImplicationModusPonensFormula`:

    (X → Y) = CTV(MP(A, ctv), neg(ctv))

its positive branch the modus ponens over A and its negative branch the
exported rule's P(Y | not all antecedents), carried unchanged. A statement
rule applies it the same way: to a plain `Y` by `CTVModusPonensFormula`, to an
implication `Y` by `ImplicationModusPonensFormula` again. For `A → (B → C)`
with rule CTV (p, n):

    C = b (a p + (1 − a) n) + (1 − b) n = a b p + (1 − a b) n

which is the flat rule over `AndFormula(a, b)`. The strengths are equal for
any a and b, and at any depth. The confidences are equal when A and B are
certain, and otherwise not: the idealized variance of modus ponens treats
its two branches as independent, and in the nested form n enters both the
statement's positive branch and the second step's negative branch, so its
variance is counted as b²(1 − a)² + (1 − b)² instead of (1 − ab)². The nested
form is therefore more confident when n is weak, as an STV rule's negative
branch is (a quarter of its inputs' confidence): in the test, 0.0130
against 0.0080 for a = 0.8, b = 0.6. With an informative n (a CTV rule) the
two are close (0.9364 against 0.9304). Exact agreement needs the covariance
of the statement's branches, which a CTV does not carry.

## Interactions

- **Evidence and overlap.** The statement rule's premises are the
  statement key and the antecedent, so the view's evidence and dependencies
  are both premises', which include the nested rule's evidence and A's. A
  proof through the derived statement and a direct proof that both read A
  overlap and do not revise. The nested rule's evidence is registered as any
  rule's; the statement rule's own name is a proof, so it adds none.
- **Inversions and antecedent completions.** A rule concluding an
  implication is neither inverted nor completed: both read the conclusion's
  value as an observation of a statement, and a derived implication is not
  observed. The statement rules are not inverted either. So the flat rule's
  inversions (A ∧ B from C) and completions (A from B and C) have no nested
  counterpart (limit).
- **Rule refinement.** Instance sampling does not take an implication
  consequent, so a rule concluding an implication is never refined; it
  applies with its stated truth.
- **Dormancy, the prefilter, complete predicates.** The statement rule is an
  ordinary rule with an ordinary premise: the dormancy analysis follows its
  implication premise to the rules concluding it, the prefilter keeps it
  when a rule concludes the statement, and its applications are rule
  applications (`by`), so they count as ways a complete statement becomes
  true.
- **Combination modes and lifting.** A statement rule's views are rule
  applications and combine as others do. The lifting merge evaluates a
  proof with its shared facts replaced by a probe; for a statement rule's
  proof the CTV applied is the statement's, evaluated the same way from the
  nested rule's literal CTV (`sk-lift-ctv`). So a stored `B → C` and a
  derived one, both applied to a certain `b`, factor `b` out and revise
  exactly as the stored rule and the flat rule do. As for flat rules, an
  STV rule's CTV is computed at run time and is not lifted.
- **Forward chaining.** Upward joins use the same rules: taking A derives
  the statement, and taking the statement (or B) joins the statement rule.
  A forward run reads the evidence behind an implication's value by its
  positive branch, as its agenda's Beta already does; by the minimum of
  both branches, a statement whose negative branch rests on no base rate
  was never built on. The run stores the statement's value like any derived
  key's.
- **Implication queries.** Public queries always return the positive branch as
  an STV. CTVs remain internal rule storage; modus ponens still uses both
  branches. Internal implication premises retain their full CTV scaffolds.
  Empirical instance evidence and learned rule truths still contribute to
  the positive judgment. Stated truths are read first and merged with the
  calculated judgment without counting the same rule's evidence twice.

## Implication queries

An open or STV-pattern query has this answer shape:

```metta
(query n kb (: $p (Implication G Y) $tv))
;; => (: (conditional-implication <proof of Y under G>)
;;       (Implication G Y) (STV <P(Y given G)> <confidence>))
```

A stated implication is read before calculating its judgment, even at zero
budget, with its original proof and positive STV. Stated STVs and the two
branches of a stated CTV are retained in the private `implication-query`
namespace: the negative branch is a stated truth of `(Implication (Not G) Y)`.
They cannot become new world observations through a query.

A stated CTV also remains a full statement in main rule storage, in both
antecedent polarities. An STV
source is retained in `implication-stated`; a permanent producer reads that
source and converts it to a full CTV with the ordinary base-rate formula,
retaining the original `ForAll` parameters. Internal implication premises
read these stated truths before their calculated scaffolds. Later additions
reach cached readers through the ordinary fact and rule journals. Source
statements preserve the compiler's consequent-only witnesses.

A stored or derived implication retains its own statement provenance. The
positive hypothetical proof may be revised with an empirical instance fold. A CTV answer
pattern returns no answer. CTVs never appear in public query answers; a rule
may still be stated and stored with `(CTV <positive STV> <negative STV>)`.
To ask for the negative statement, query it explicitly:

```metta
(query n kb (: $p (Implication (Not G) Y) $tv))
;; => (: <proof> (Implication (Not G) Y) (STV <strength> <confidence>))
```

The judgment assumes the stated antecedent in its private context. Under
`(Not G)`, every reader of G reads `(STV 0 1)`; under G, every reader of G
reads `(STV 1 1)`. This includes negated premises lowered to a read of G
followed by `NotFormula`, even when G is ground. The main world's value of G
never enters this judgment. Independent fixed premises retain their existing
main-context reads.

Stated and calculated proofs of one rule share its evidence identity and
are not revised as independent observations. Independent conditional evidence
still revises normally.
For an STV rule, a false antecedent supported only by hypothetical assumptions
contributes zero confidence and no evidence. Internal two-branch readers
can still read its value as an unknown branch. Its population-inferred complementary branch
remains available for world observations; it cannot add evidence to an
opposite judgment merely because the assumption made its antecedent false.
An explicit CTV still supplies both stated branches.

The stored statement is the original stated truth, including for a refined
rule. Learned rule truth supplies the executable applications; empirical
instance evidence revises the stated query judgment through its normal fold.

## Nested implication queries

`A -> (X -> Y)` is judged as its exported form `(And A X) -> Y` at any
depth. The positive context assumes every antecedent conjunct and proves the
innermost consequent. Nested and exported queries have the same conditional strength; an exact
stated read retains its confidence, while a calculated exported form propagates
formula variance.
The answer retains the queried statement and the proof applies the rule
step by step:

```metta
(query n kb (: $p (Implication A (Implication X Y)) $tv))
;; => (: (conditional-implication (by (by r <A assumption>) <X assumption>))
;;       (Implication A (Implication X Y)) (STV <P(Y given A,X)> <confidence>))
```

For the source-gated knowledge-extraction rule,

```metta
(: src_rule
   (Implication (AcceptSource Report1)
      (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk))
         (LowerPrices $x)))
   (STV 1 0.9))
```

the query of that nested statement returns an STV with strength 1 and
confidence 0.9, read from the stated source, under the same nested statement. The query
assumes the source gate only in its private context. Asking about the rule
does not accept the source: `(AcceptSource Report1)`, `(LowerPrices Supplier1)`
and the inner rule remain unsupported in the main KB. The implication
judgment does not answer `(Not (Implication ...))`.

### Projection through consequent conjunctions

A conjunction between the gate and the nested implication also supports
projection ([issue #43](https://github.com/rTreutlein/PeTTaChainer/issues/43)):

```metta
(: rule (Implication (AcceptSource S)
   (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 1 1))
(query 300 kb (: $p
   (Implication (AcceptSource S) (Implication (A $x) (C $x))) $tv))
;; => (: (conditional-implication ...) <queried statement>
;;       (STV 1.0 0.999700089698173))
```

The compiler projects the nested implication from the rule's consequent
before exporting it. Each intervening `And` applies `AndMarginalProjection`
to the rule's truth (both branches of a CTV). The projected conditional is
compiled directly in exported form,
`(And G A) -> Y`, using the ordinary implication forward compiler. Repeated
conjunction layers and conjunctions after further nested implications use the
same path. An inner antecedent's variables remain variables of that
conditional;
they are not replaced by consequent-only witnesses on this path.

Previously, `nested-implication-parts` stopped at the outer `And`, ordinary
output adapters projected an STV implication conjunct, and statement-rule
compilation never reached that conjunct. An STV projection cannot be applied
by a statement rule, which reads a CTV. Increasing the budget cannot bridge
these compilation boundaries.

Projected conditionals retain a `consequent-projection` proof naming the
source conjunction, selected child and source proof. They read the original
stated implication as a premise, so every projection carries its source
evidence. The proof's rule head resolves to the original named rule, so the
compiled projected row also retains its withdrawal identity. Exporting the
projected conditional directly keeps that owner on the application, including
when its answer is materialized. Two paths from one uncertain source share
its rule evidence and cannot revise as independent observations. No extra projected axiom is stored.

The outer gate still has to hold in the context applying the conditional.
Querying it assumes that gate and the inner antecedent only in the judgment's
private context. Wrong-source and gate-free queries remain unsupported;
neither `(AcceptSource S)` nor `(C a)` becomes a main-context fact. Withdrawing
the source also retires its projected support.

## Conjunction queries

Every implication conjunct contributes its positive STV. There is no CTV
unfolding and no annotated positive-only selector inside `And`:

```metta
(query n kb (: $p (And M (Implication G Y)) $tv))
;; => (: (conjunction <M proof> <positive implication proof>)
;;       (And M (Implication G Y)) (STV <strength> <confidence>))

;; Explicitly request both implication statements:
(query n kb (: $p (And M (Implication G Y) (Implication (Not G) Y)) $tv))
```

The conjunction retains its shape, combines STVs with the normal And
formula and conditions shared evidence once. An unsupported negative branch
in internal rule storage does not reduce the confidence of a query that
only asks the positive statement.

The compiler prepares implication leaf scaffolds for each query before a
compound can be rejected by the ground-premise prefilter. Scaffold reuse
requires the same statement up to variable renaming: an open scaffold cannot
replace a bound instance's contexts. The copied lookup type narrows the
clause index; the original clause shape is then checked for alpha identity.

Positive query values use a private KB namespace with the original
statement shape. They cannot become observations in main-context populations
or untyped user-rule premises. An explicitly STV-typed main-context
implication premise reads the private positive judgment; untyped/CTV
premises and stored rule keys retain their full CTVs. Private judgments
are excluded from `query-materialize` storage.

Root answers are deduplicated by proof identity. An identical fact term
retains its existing dependency path; distinct references to the same proof
DAG retain the union of their dependency paths for cycle exclusions.

The regression tests cover the original source-gated conjunction, reversed
order, constants, removal of either assertion, scope, shared uncertain facts,
computed children, and scaffold reuse. The certain report metadata and rule
give `(STV 1 0.9998000399670116)` in the original two-conjunct query:
strength 1 from the stated positive truth, with confidence propagated through
the normal And formula.

## Limits

- Calculations under nested `Not` antecedents currently return no answer:
  a judgment of
  `(Not (Not (A Item)))` does not route a reader of `(A Item)` to its
  assumption. This is queued separately.
- `Or` antecedents currently assume each lowered part certain. For example,
  `(Or A C) -> B` returns 0.3 when `A -> B` has positive strength 0.3.
  This behavior is unchanged from master and is queued separately.
- An open premise such as `(A $z)` is routed whole into the private context
  and can hide world individuals it would otherwise join with. The planned
  context overlay will address this.

- The positive statement-producer collector projects rule applications
  shaped `(by rule token)` and stored facts. Other clause proof shapes are
  not collected there; hypothetical and empirical query scaffolds have
  their own compilation paths.
- Conditional projection through a consequent conjunction uses the marginal
  `And` projection; it does not infer a stronger conditional by dividing by
  independently known sibling truths. This composition does not project
  through `Or`, `Not`, or arbitrary source wrappers.

- No inversion or antecedent completion through a nested rule or a derived
  statement.
- Statement rules are deduplicated by shape, not by subsumption: rules
  concluding `(Implication (B $x) (C $x))` and `(Implication (B x) (C x))`
  add two statement rules, whose views of `(C x)` have the same proof.
- A derived statement whose value is an STV is not applied; the sources
  above all give CTVs.
- Confidence equals the flat rule's only when the antecedents are certain
  (see above).
- Implications assumed by an `Assuming` query are compiled as rules of its
  context; a nested assumed implication gets no statement rule.

## Tests

`tests/metta/test_derived_implications.metta`, each case against the flat
rule in its own knowledge base:

| case | nested | flat |
|---|---|---|
| A, B certain, STV 0.9 | 0.9, c 0.99990 | 0.9, c 0.99990 |
| a 0.8, b 0.6, base rates from (A y) (B y) (C y), STV (0.9, 0.9) | 0.52894, c 0.0130 | 0.52894, c 0.0080 |
| three levels, a 0.8, b 0.6, c 0.7, STV 0.9 | 0.3024, c 0.93856 | 0.3024, c 0.93767 |
| CTV (0.9, 0.2), a 0.8, b 0.6 | 0.536, c 0.93636 | 0.536, c 0.93038 |
| with a stored `(B x) → (C x)` CTV (0.7, 0.1) at c 0.5 | 0.88, c 0.90909 | 0.88, c 0.90909 |

Also: the derived statement answers the implication query; a nested
implication query answers the exported query's positive STV, under the
nested statement; the source-gated rule of the report answers its nested
query, ground and with variables, and neither its negation, its consequent
nor its inner rule is answered; a nested rule whose inner antecedent has a
variable bound by neither side gives the flat rule's value, and its nested
query is answered; a forward run
from `(A x)` stores the statement and `(C x)`, which a zero-budget query then
reads; a knowledge base with no rule concluding an implication gets no
statement rule.

`tests/metta/test_ground_negated_implications.metta` covers stated ground and
open negated antecedents, bound instances of open rules, both branches of CTV
sources, conflicting main-world values, derived consequents, positive
counterparts, zero-budget reads, and STV/CTV implication premises before any
public judgment query. `test_conjunction_conditioning.metta` includes the
explicit `Not G -> Y` judgment at 0.9, an unknown positive `G -> Y` value
with zero confidence from an opposite-only STV rule at either world g value, and a derived
implication whose source g is conditioned jointly with its sibling M.

`tests/metta/test_nested_consequent_projection.metta` covers issue #43 cold
and warm at 300 steps, a bound instance, both passing controls, wrong-source
and gate-free queries, absence of categorical facts and answers, repeated
conjunction/nested-implication layers, shared uncertain source evidence, both
CTV branches, and withdrawal after warm queries.
