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
- **Implication queries.** `(query n kb (: $p (Implication (B x) (C x)) $tv))`
  with an open or CTV truth value also reads the rules concluding the
  statement, so r's derived statement is one more answer, merged with the
  hypothetical judgment and the instance fold. An STV implication query asks
  for the positive side only, and a derived statement (a CTV) does not
  answer it. A query of a nested implication is judged as its exported
  form (below).

## Nested implication queries

A query whose consequent is an implication,

    (query n kb (: $p (Implication A (Implication X Y)) $tv))

is judged as its exported form `(A ∧ X) → Y`, as the rule is: its positive
context assumes A and X's conjuncts, each as its own statement, and proves
Y; its refuting context, as for any conjunctive antecedent, assumes the
first conjunct false and the others true, here not A with X, which is the
nested reading of the negative branch, P(X → Y | not A) = P(Y | X, not A).
So the answer has the shape of any implication query's, and the exported
query's value:

| `$tv` | answer |
|---|---|
| open or `(CTV $pos $neg)` | `(: (total-implication <pos proof> <neg proof>) (Implication A (Implication X Y)) (CTV (STV P(Y\|A,X) c) (STV P(Y\|not A,X) c)))`, revised with the instance fold of `(A ∧ X) → Y` |
| `(STV $s $c)` | `(: (conditional-implication <pos proof>) (Implication A (Implication X Y)) (STV P(Y\|A,X) c))` |

The answer's statement is the stated nested one, and only the
hypothetical judgment and the instance fold read the exported form:
derived statements answer the nested query when a rule concludes the
nested statement itself, and a `RuleTruth` is read for the stated rule.
Before this, the positive context proved `X → Y`, so its branch was the
derived statement's CTV: an open query failed on the STV-typed branch, and
a `(CTV $a $b)` query returned `(CTV (CTV ..) (CTV ..))`, the inner
statement's CTV under A and under not A. That is not a value of the
implication: its branches must be probabilities of the consequent.

The judgment does not answer `(Not (Implication ...))`, flat or nested;
how Y fails under the antecedents is one minus each branch's strength.

**Value equivalence and the gate.** The nested and the exported query give
the same value on the same knowledge base, at any depth (tested). That does
not merge an outer condition into the inner antecedent anywhere it is
visible: the stored rule stays nested, applied through its statement rule;
the answer names the nested statement; and the proof applies the outer
condition first, as its own step, `(by (by r <A>) <X>)`. A is assumed only
in the query's contexts and never stored, so a source gate such as
`(AcceptSource Report1)` is not accepted by asking about the rule it gates:
in the main context neither `Y` nor the inner rule `X → Y` holds without it.

Example, the knowledge-extraction report (`gateKb` in the test):

    (: src_rule (Implication (AcceptSource Report1)
                   (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk))
                                (LowerPrices $x)))
       (STV 1 0.9))

| query | answer |
|---|---|
| the stated rule, `$tv` open | `(: (total-implication (by (by src_rule (ctx proof 11)) (conjunction (ctx proof 11 1) (ctx proof 11 2))) (by (by src_rule (ctx proof 12)) (conjunction ...))) <the stated rule> (CTV (STV 1.0 0.89976) (STV 0.0 1.0e-06)))` |
| the same with `Supplier1` for `$x` | the same shape and value, ground |
| `(Not <the stated rule>)` | none |
| `(LowerPrices Supplier1)`, `(Implication (And (Supplier $x) (ExposedTo $x ClimateRisk)) (LowerPrices $x))` | none (the gate is not accepted) |

The negative branch (0.0, c 1e-06) is the STV rule's base-rate negative
branch with no base rates known.

## Limits

- No inversion or antecedent completion through a nested rule or a derived
  statement.
- A derived statement whose antecedent has a variable that neither the
  rule's outer antecedent nor the statement's consequent binds, as `$f` in
  `(Implication (AcceptSource R) (Implication (Rel a $f) (P a)))`, answers
  as a statement (an open key) but is not applied: the statement rule's
  join takes no answer from that open key, so neither `(P a)` nor the
  nested query has an answer. Once the statement is asked for at its ground
  instance, `(Implication (Rel a g) (P a))`, it applies. A stored rule of
  that shape (the flat form) applies.
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
implication query answers the exported query's CTV (and STV), under the
nested statement; the source-gated rule of the report answers its nested
query, ground and with variables, and neither its negation, its consequent
nor its inner rule is answered; a forward run
from `(A x)` stores the statement and `(C x)`, which a zero-budget query then
reads; a knowledge base with no rule concluding an implication gets no
statement rule.
