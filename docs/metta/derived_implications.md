# Derived implications

Status: built, October 2026.

Quantified rule judgments (tracker #51, existential stage 2) use the same
positive private-context semantics. For example, with just

```metta
(: flood-inspection
   (Implication
      (Exists ($event) (And (Member $site Facility)
                           (RecordedFlood $site $event) (During $event S1)))
      (RequiresInspectionDuring $site S1)) (STV 1 1))
(: inspection-pause
   (Implication (RequiresInspectionDuring $site S1)
      (MustPauseProductionDuring $site S1)) (STV 1 1))
```

querying the composed implication from the existential antecedent to
`MustPauseProductionDuring` returns strength 1 with propagated confidence,
and a proof of the form

```metta
(conditional-implication
   (by inspection-pause (by flood-inspection (ctx proof context-id))))
```

The context assumes **the existential statement**, represented by a direct
`ExistentialClaim` with canonical local slots and TV (1,1). It does not assume
`Member`, `RecordedFlood`, or `During` individually and creates no flood event.
The existing premise judgment reads that claim through the existential floor.
Free `$site` remains shared between both sides; renamed binders are equivalent,
but different co-reference and conjunct order are not. Contextual results never
become unconditional MAIN facts.

A complete existential consequent is proved through the same judgment. Each
side owns its slots, even when both source binders have the same spelling.
`Assuming` uses the same claim lowering, with its existing world-reading scope.
Source rule identities remain in the proof DAG and retirement dependencies;
uncertain rule evidence is unioned, and shared derivations are not independent.
In particular a stated quantified rule and its own conditional application use
the same rule evidence. Partial search yields a supported positive answer or
no answer, never a fabricated negative from an empty witness population.

Stage 2 supports complete-side quantifiers through ordinary multi-rule chains.
It does not implement quantified nested implication export, nested binders,
quantifier distribution across connectives, quantified implications as Assuming facts or goals,
`Not Exists`, completion, or overlap-aware witness OR. See
[explicit_exists.md](explicit_exists.md) for the shared judgment and cost.

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

    (: ctx (derived-implication $proof) (Implication X Y) (CTV $pos $neg))
    X ...                                  ; X lowered as a rule antecedent
    |- (: ctx (by $proof <X proof>) Y <modus ponens>)

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

### Merged statement values (tracker #92)

The statement premise uses the internal proof selector
`(derived-implication $proof)`. Search interprets it as a rule-application
producer, `(by $rule $premises)`, and installs no hypothetical scaffold.
Evaluation selects those producers before merging, then binds `$proof` to
their resulting proof, which may be a revision rather than a single `by`.
The selector is never part of the output proof. Ordinary user proof patterns
retain their literal matching semantics.

Previously the same `(by $rule $premises)` pattern did both jobs. Two
independent sources produced a valid merged CTV, but the statement consumer
could not bind the revision proof to that pattern and lost the answer.
Corroborating accepted sources now revise their rule evidence before applying
the shared inner antecedent once. Shared uncertain gates retain the existing
conservative overlap behavior, without adding independent evidence counts.
A pooled positive source proof retains all its source conditions for
specificity; a general rule supplies its prior rather than another likelihood.
Mixed source branches remain mixtures for containment comparisons.
This changes neither sibling separator odds (#49) nor the unresolved family
approximation (#77).

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
  instance fold) are not read by statement rules: their internal premise
  selector admits rule-application producers, and installs no hypothetical
  scaffold. Assuming B and proving
  C to apply `B → C` to B would re-prove C by the same rules that prove it
  directly and count their evidence twice, at the cost of two hypothetical
  contexts per application.

## Truth values

An STV's missing negative branch is unknown, `(STV 0.5 0)`, when the
reconciled base rates cannot determine it (tracker #83). An uncertain
antecedent then mixes its positive estimate with that neutral branch, with
the unknown variance included in confidence. For example, the three-level
STV .9 case below now gives .6344 with confidence .0053284 nested and
.0013782 flat; the historical table's .3024 implicitly used a zero complement.

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
  implication premise to the rules concluding it. Missing fact premises
  retain their join subscriptions; only failing ground CPU premises trigger
  the prefilter. Its applications are rule applications (`by`), so they count
  as ways a complete statement becomes true.
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
never enters this judgment. Leading pairs of `Not` are eliminated before
lowering either assumption polarity: `Not Not G` assumes G true, and
`Not Not Not G` assumes G false. The answer retains the original statement.
Independent fixed premises can read MAIN observations and the projections of
compound observations. Private leaf reads use the fact prefix index, exclude
assumed keys, the judgment's own consequent (including its instances and
negation), and forwarded/materialized values, and retain the source fact's
MAIN evidence and dependency identities. Conditioning a MAIN observation
also conditions its borrowed private leaf, while assumed keys keep their own
truth. Fixed MAIN projection rules are evaluated with private premises; their derived MAIN views are never imported. This lets a rule join a
world classification with an assumed implementation without asserting either
implementation or its consequence in MAIN (tracker #63). A derived implication
statement dominates its application to the judgment's certain assumption: the
application restates the same source, including when a certain rule has no
empirical evidence id.

World observations of the consequent are not conditional evidence. Each private
context carries temporary target metadata in a separate namespace, removed with
its scaffold. Both leaf borrowing and fixed MAIN projection matching reject
that target, including after an open reader is specialized. Negation adapters
that explicitly read MAIN are routed privately for this key too. This keeps
an actual-world B value out of P(B given A), and prevents revising it with an
instance fold that already read B.

The assumption must be necessary to the calculated derivation (tracker #65).
Before merging alternatives for a private key, keep only the alternatives
whose dependency sets contain an assumption key whenever such alternatives
exist. A weak assumed `A -> C` path therefore cannot be revised with a strong
world observation of C to drive `A -> B`. This selection also precedes proof
dominance and selection of certain leaves. Borrowed world facts, even at
confidence 1, do not retire private search before it can discover a dependent
alternative; MAIN facts and private assumptions retain their usual absorption.
Assumption dependencies retain the stored key identity when a computed
consequent specializes context variables.

A key with only world support may still supply a co-premise: world
`StockSplit Split1` and assumed `Implemented Split1` together prove
`PreservesOwnership Split1`, retaining `src_split` and `src_bridge` and
`(STV 1.0 0.8180941097204595)`. At the judgment's consequent, however, a value
without any assumption dependency is rejected. World C and `C -> B` alone
provide no calculated `A -> B` proof. A stated conditional or an empirical
instance fold can still answer through its separate producer.

For a ground private conclusion, cycle exclusion also covers the corresponding
MAIN key. In particular, constructing `(And C A)` from world C and assumed A,
then projecting C, cannot supply C to a rule deriving B: that projection reads
C itself. This extends the existing exclusion check and adds no store or
exclusion-cache representation. Open hypothetical individuals retain their
existing separation from world individuals.

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

### Disjunctive antecedents (tracker #15)

For a disjunction D, the calculated judgment is P(B and D) / P(D).
Its private world reads each disjunct's leaves at their base rates rather
than assuming every leaf true. The numerator uses the ordinary conjunction
and shared-premise conditioning machinery. The denominator reads D's own
base rate; it is not the probability of one selected disjunct. Zero-probability
conditioning returns no calculated answer. Stated judgments keep their
existing independent read path.

For example, independent priors P(A)=0.2 and P(C)=0.4 give P(A or C)=0.52.
With P(B|A)=0.3 and P(B|not A)=0.1, the answer is
0.1 + (0.3 - 0.1) * 0.2/0.52 = 0.17692307692307693, not 0.3.
A rule requiring both A and C instead uses 0.08/0.52; multiplying the two
conditional marginals would be incorrect. N-ary disjunctions, negated
disjuncts, and disjunctions inside conjunctions use the same calculation.
Ordinary conjuncts outside the disjunction remain certain assumptions: a
source gate needs no population prior of its own.

Temporary `JudgmentPrior` facts identify the private prior inputs; their
logical keys remain assumption dependencies when conditioning pins a leaf.
This preserves necessity selection through merges and prevents MAIN values
from overriding those inputs. Consequent metadata continues to exclude world
observations of B. All prior rows and markers leave with the query.
The two internal CTV sides retain separate goal shapes; refuting an Or
assumes every disjunct false.

As elsewhere in PLN, leaf priors and connective formulas describe the joint
distribution used by the calculation. Supplying mutually inconsistent
marginal and compound base rates does not define a coherent joint model;
this path does not fit a new joint distribution to reconcile them. Ground
events and open populations have distinct base-rate keys, as in ordinary
rule compilation.

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
private context. Without a stored gate, wrong-source and gate-free queries
remain unsupported; neither `(AcceptSource S)` nor `(C a)` becomes a
main-context fact. If `(AcceptSource S)` is stored as a fact, the gate-free
judgment `(Implication (A $x) (C $x))` can borrow it as a world co-premise
(tracker #45, supported by the #63 world-premise path). This holds for both
the wrapped rule above and an unwrapped nested rule with an `And` consequent.
The assumed A must still be necessary: a world-only derivation of C cannot
establish this calculated judgment (#65). Querying it does not assert A or C
in MAIN. Withdrawing the source also retires its projected support.

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

The compiler prepares implication leaf scaffolds for each query before
search starts. A missing fact premise keeps its subscription rather than
pruning the compound; only failing ground CPU premises trigger the prefilter.
Scaffold reuse requires the same statement up to variable renaming: an open
scaffold cannot replace a bound instance's contexts. The copied lookup type
narrows the clause index; the original clause shape is then checked for
alpha identity.
Permanent joins, including existential witness joins, install permanent
implication leaf scaffolds before reading their existing answer keys. Reuse
also requires a permanent producer: a query-local scaffold leaves at cleanup
and cannot support the durable consumer. This check runs even when an earlier
ground query already expanded the leaf (tracker #73). Its assumptions and
consequent metadata retain the same private scope as the consuming judgment.

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

- A premise sharing the query's hypothetical individual does not import world
  individuals. Fixed premises and open auxiliary variables may read world
  observations; an assumed ground key overrides only that binding.

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

`tests/metta/test_source_gate_judgment.metta` and
`tests/test_source_gate_judgment.py` cover #45: wrapped and unwrapped
consequents, observed/absent/assumed gates, open and bound judgments, cold and
warm reads, late gate addition, assumption necessity, MAIN isolation, and
borrowed evidence identity.
