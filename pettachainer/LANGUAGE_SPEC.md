# PeTTaChainer Language Spec

This document describes how to write facts, rules, and queries in the PeTTaChainer MeTTa language used in this repository.

If you need an LLM-oriented helper-first spec, use `pettachainer/LLM_RULE_SPEC.md`.

## Core Model

- Knowledge is stored as proof atoms of the form:

```metta
(: proof-id type tv)
```

- A statement is stored, assumed and concluded at its canonical key. A negated
  STV fact is stored as the statement under its negations, its strength
  complemented once per negation and its confidence unchanged. For example,
  `(: noLeak (Not (SealLeak old unit-1)) (STV 1.0 1.0))` is stored as
  `(: noLeak (SealLeak old unit-1) (STV 0.0 1.0))`. Rule conclusions,
  projections and assumptions follow the same rule, so ordinary population
  folds see negative observations. A query of `(Not s)` reads `s` and answers
  complemented, so it answers wherever `s` does, at budget zero included. A
  stored `Exists` fact is its `ExistentialClaim`. A negated implication is the
  conditional complement: `(Not (Implication G A))` at s means
  `(Implication G (Not A))`, P(not A given G) = 1 - s, not the material reading
  G and not A. `Not` in rules and queries keeps its logical meaning.

- In user code, facts/rules are usually inserted with:

```metta
!(compileadd kb (: proof-id type tv))
```

- Queries use:

```metta
!(query steps kb (: $prf type $tv))
```

`steps` is the search budget.

- An implication-derived proof uses the explicit application form:

```metta
(by rule-name premise-proof)
```

The rule name is metadata, while `premise-proof` is the proof dependency that
evidence and cycle walkers traverse. This avoids confusing a rule name that
happens to look like a proof constructor with an actual dependency.

## Types and Truth Values

### STV

Simple truth value:

```metta
(STV strength confidence)
```

- `strength` is belief/probability-like mass in `[0,1]`
- `confidence` is evidence/reliability in `[0,1]`

`STV` is for truth of a proposition, not for numeric value uncertainty.
For example, `(STV 1.0 0.5)` means low confidence that a fact is true,
not "value is around X".

### PTV and FTV

The two kinds an STV can state, written explicitly:

```metta
(PTV strength confidence)   ; a ground statement: the probability its event holds
(FTV strength confidence)   ; a rule: the degree or frequency it states
```

An STV takes its statement's kind: a ground statement is an event (PTV), a
rule (`Implication`, `ForAll` or `WithPrior` over one) a frequency (FTV). An
explicit kind reads as that STV; a kind the statement does not take is
rejected with `domain_error(tv_kind, [Kind, Statement])` (degrees of ground
statements come later, with FTV compound evidence). The same holds for the
weighted facts of an `Assuming` query.

### Distribution TVs

- Exact discrete:
  - `(NatDist ((value probability) ...))`
  - `(FloatDist ((value probability) ...))`
- Scalable particle-based:
  - `ParticleDist` is an opaque reference backed by `&particle_store`
  - Create from explicit weighted samples with:

```metta
(ParticleFromPairs ((x1 w1) (x2 w2) ...))
```

Useful constructors:

```metta
(PointMass 160.0)
(ParticleFromNormal 160.0 2.0)
```

- `PointMass` encodes an exact value as a degenerate distribution. It remains
  `(PointMass x)` at runtime, so separately constructed exact values match in
  facts and queries without allocating particle-store rows. Distribution
  operations accept it, and normalized unit-scale singleton results reduce to
  this representation. Clearing/pruning the particle store does not affect it.
- Nondegenerate `ParticleDist` handles still have identity semantics; separately
  allocated equal marginals are not interchangeable query constants. Equal
  values do not establish shared evidence or statistical independence.
- `ParticleFromNormal` creates a deterministic normal-like particle approximation.

## Truth vs Value Uncertainty

- Truth uncertainty: use `STV`.
- Value uncertainty: use `Dist` (`ParticleDist`, `FloatDist`, `NatDist`).

Recommended modeling pattern:

- `(HeightDist g1 alice)` with TV `(PointMass 160.0)` for crisp numeric values
- `(HeightDist g1 alice)` with TV `(ParticleFromNormal 160.0 2.0)` for uncertain values
- keep instance membership/existence truth in separate `(Member object class)`
  STV facts if needed

## Fact Syntax

Example:

```metta
!(compileadd kb (: in11 (In room1 kid1) (STV 0.5 1.0)))
```

## Member and Inheritance

`Member` and `Inheritance` have distinct modeling roles:

- `(Member object class)` says that one object belongs to a class.
- `(Inheritance subclass superclass)` says that one class or concept inherits
  from another.

### Member is a unary predicate (#96)

`(Member x P)` and `(P x)` are one statement: the chainer reads every
`(Member x P)` it is given (a fact, a rule premise or conclusion, a query, an
`Assuming` fact, a base-rate pattern) as `(P x)`, wherever it occurs: a
compound's parts, an existential's body, a `RuleTruth` goal, and a statement
quoted as a predicate argument, as in `(Claims bob (Member rex Dog))`, which a
rule `(Implication (Claims $p $s) $s)` may conclude.

- The two forms share one key and one evidence identity: one proof name
  stated in either form is one fact, a different value under that name is
  rejected, and two names are two observations that revise.
- An answer comes back in its query's form: `(Member rex $c)` answers
  `(Member rex Dog)`, `(Dog rex)` answers `(Dog rex)`. Statements inside
  proofs, forward-chained facts and the stored KB use the predicate form.
- A class is a symbol or a variable. `(Member x <expression>)` raises
  `domain_error(member_class, ...)`, and so does a class naming a connective,
  binder, computation or internal key (`Not`, `And`, `Implication`, `Exists`,
  `Compute`, `FoldAll`, `RuleTruth`, ...), which would otherwise make the
  statement that connective. A class variable makes a variable-headed
  statement: `(Member rex $c)` reads `($c rex)`, and its answers never bind
  `$c` to an internal key.
- Per-predicate declarations (`set-positive-only-predicate`,
  `set-complete-predicate`, `set-functional-predicate`,
  `set-observed-predicate`, `set-predicate-time`,
  `set-specializing-predicate`) name the class itself, as for any predicate;
  one naming `Member` raises `domain_error(predicate_head, Member)`.
- One head has one arity in a KB, so a class cannot also be a predicate of
  more arguments (`domain_error(predicate_arity, (head arity other))`).

### Inheritance is the implication between two classes

`(Inheritance A B)` and `(Implication (A $x) (B $x))` are one statement, read
like `Member` wherever it occurs. A stated link is an ordinary rule, with its
stated truth: it applies forward and backward, is inverted and completed, and
its negative branch comes from the two classes' base rates, as for any rule
stated with an STV. Observing that an object is Mortal is evidence that it is
Human, through Bayes' rule over the base rates.

```metta
!(compileadd kb
    (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd kb
    (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(query 40 kb (: $prf (Member Tom Mortal) $tv))
```

- Both classes are symbols or variables; `(Inheritance <expression> B)` raises
  `domain_error(inheritance_class, ...)`. A link is between classes, so
  instance membership is written `(Member object class)`: `(Inheritance rex
  Dog)` is the link from a class named `rex`.
- A ground query `(Inheritance A B)` is the implication query of the link and
  answers in the `Inheritance` shape: the stated and rule-derived links,
  revised with the judgment over the rules and with the link's instance fold.
- An open query, such as `(Inheritance $subclass $superclass)`, is the
  implication query over variable predicates: it answers the links stated or
  derived, and also the identity `(Inheritance $x $x)` and an instance fold
  over every class, as `(Implication ($p $x) ($q $x))` does.
- A rule concluding a link, `(Implication X (Inheritance A B))`, is the derived
  implication `(X and (A $x)) -> (B $x)`.
- An existential over a link, `(Exists ($y) (Inheritance $y Animal))`, gives
  no answer, as an existential over any implication does: its witnesses are
  not judged, though the identity link `(Inheritance Animal Animal)` answers
  (1, 1) as a query of its own.
- A base rate is a population's: `set-base-rate` on a pattern stating a link,
  in any spelling (`(Inheritance A B)`, `(Implication (Member $x A) (Member $x
  B))`, `(Implication (A $x) (B $x))`), raises
  `domain_error(base_rate_class_link, ...)`; rate `(Member $x A)`.
- A link read as a compound's part, `(And (Inheritance A B) ...)` or negated,
  `(And (Not (Inheritance A B)) ...)`, answers as the link itself does, on a
  cold KB too. So does any implication part: it is read as the implication's
  judgment, and a negated one as that judgment's complement.
- Through a stated link, a member's conclusion is less confident than a
  certain negative branch would make it: `(Member Sam Raven)` at (.99, .9) and
  links at (.99, .9) give `(Member Sam flies)` (.983, .479). The 1% of Sam that
  may be no raven has an unknown value, which bounds the confidence; this is
  intended.

### Estimating a link from members

A ground query such as:

```metta
!(query 100 kb (: $prf (Inheritance Human Mortal) $tv))
```

estimates the link from the objects for which both `(Member object Human)`
and `(Member object Mortal)` are provable: the link's instance fold, as for any
implication. The sample collector uses the normal backward chainer, so
rule-derived memberships count along with directly stored facts. It retains
proof identities, rejects self-supporting cycles, and leaves out samples that
restate the link.

The estimate uses count-based confidence: every observed member adds
evidence, and there is no closed-world population size to declare. A class
link whose members are no stages is stationary, so its estimate is the plain
frequency of its samples, whatever order they arrive in (see the regimes of
refined rules below).
A link query at budget 0 on a link no query has searched yet answers nothing;
budget 1 suffices. Once a ground link query has registered the link, each class fact stored or
taken by a forward run marks its subject's sample, and the next query reading
the link takes the marked samples, whatever its budget: a registration at
budget 0 followed by facts and a forward run answers the exact frequency at
budget 1, and once a query has searched the link, at budget 0 too.

Legacy programs that encode instance membership as `(Inheritance object
class)` must be rewritten with `Member`.

## Sorts: stages and aggregates

Argument positions may be declared with sorts, and constants take the sort of
the declared positions they are stated at:

```metta
!(set-argument-sorts kb Agent (Stage Object))
!(set-argument-sorts kb Time (Stage Time))
!(set-argument-sorts kb About (Stage Value))
!(set-constant-sort kb d2026_10_25 Time)
```

The sorts are `Stage` (an event, claim or observation), `Time` (a time point
or period), `Object` (an entity), `Concept` (a class), `Value` (data, such as
a number or a quoted statement, which sorts nothing) and `Any` (undeclared).
A statement with a `Stage` or `Time` argument is a *stage*: after
`(Agent e1 Bob)`, `(Late e1)` is one. So is an `And`, `Or`, `Not` or
existential claim with a stage part. `set-predicate-time` declares its
position `Time`, so the symbols stated there make stages too. An inversion or
completion of a stage reads only evidence from below, never a forward
prediction; every other statement is an aggregate and keeps PLN induction and
abduction. A constant that would be both a stage or time and an object or
concept, such as from swapped role arguments `(Agent Bob e1)`, is rejected
with `domain_error(sort_conflict, ...)`. Only stored facts and rules sort constants, never a query or an
assumed fact. Declare sorts and state an event's role facts before querying
its properties: a value computed earlier keeps its kind for good
(docs/metta/API.md, "Sorts").

## Rule Syntax

An implication has exactly two expression arguments: its antecedent and its
consequent. Write `And` explicitly when either side is a conjunction:

```metta
!(compileadd kb (: ruleName
    (Implication
        (And
            premise1
            premise2
            ...)
        conclusion)
    (STV s c)))
```

A singleton side is written directly, without a unary `And`. There is only one
source form for an implication. Multiple conclusions form one explicit joint
consequent such as `(And conclusion1 conclusion2)`, whose value moves its
parts as below.

### What a compound's value says about its parts

A compound K, an `And` or `Or` stored or concluded, is an event node over its
distinct atoms: K is a formula over them (nested `And`, `Or` and `Not`
included), an atom it repeats is one parameter, and each atom is an
independent parameter at its value read apart from K, its cavity (its views
without K's own and without the atom being computed; an atom with no such view
is the uniform prior). A stored atom enters as the Beta of its count (n s + 1,
n (1 - s) + 1), a derived one with its own variance; only confidence 1 makes
an atom a point. K's value reaches its atoms in one of two ways:

- Observed: a stored fact, a revision of stored facts, or a certain value
  (confidence 1, a K given under a condition included). This is Pearl
  evidence at K's predictive strength m = (n s + 1)/(n + 2), n = k c/(1 - c):
  each world of the atoms where K holds has likelihood m, the others 1 - m.
  Only at confidence 1 is the evidence exact: a report of strength 0 or 1
  then determines an atom where K does. An observed K at strength .5 below
  confidence 1 says nothing about its atoms.
- Predicted: anything else derived. This is probability kinematics
  (Jeffrey). The prediction s at confidence c is first revised with the atoms'
  own estimate of K, P* = (n_parts P_parts + n_rule s)/(n_parts + n_rule), with
  n_rule = k c/(1 - c) and n_parts the moment count of P_parts at its exact
  variance (two uniform atoms of an And: P_parts = 1/4 at variance 7/144,
  n_parts = 20/7). An atom's value p, its other views (observations included)
  merged first, then moves to
  P* p f1/P_parts + (1 - P*) p (1 - f1)/(1 - P_parts), where f1 = P(K | atom),
  f0 = P(K | not atom) and P_parts = p f1 + (1 - p) f0. A prediction at
  confidence 0 leaves the atom as it was; one near certain adopts s. With B
  and C at .9 and .6 (confidence .9), K = (And B C) predicted at .8 moves C to
  .603 at confidence .1 and to .806 at .99. Several predictions of one atom
  apply one after the other in an order fixed by what they carry, their
  evidence included, whatever order they arrived in. An update's evidence is
  its compound's, as raw sources (facts and rules): what the atom's value
  already holds counts once, so the prediction's count is at most the count
  of its uncertain sources that are new, and one with none new is dropped.

All of an atom's messages are read together, as one node, on the atom's
prior. Messages whose compounds share no other atom are independent given it:
their likelihoods multiply (in log space), the mean is exact, and the variance
integrates the prior and each message's other atoms (their product taken by
its two moments). Messages that share an atom are one node over the union of
their atoms, enumerated exactly: Or(A, B) and Or(A, Not B) at (.9, .9) make A
m = .8999 whatever B is, and Or(A, B) and Or(A, C) with B and C false make it
.9878. The prior is A's population rate read apart from the node (without the
members whose values rest on the messages' own observations), or a rate set on
the population with `set-base-rate`, as a stored count; with neither it is the
uniform prior, whose variance the answer keeps, so a message about an atom
nothing else informs claims little confidence. An update or message that an
antecedent completion of the atom already counts (the completion's prior was
formed under K's evidence, alone or within a revision) is not applied again.

An `And` or `Or` over two or more of K's children or of its atoms, in any
order, and each compound inside K, is a joint row of K's node over at most four
atoms, the node's own posterior; it takes the place of the conjunction or
disjunction of the parts' values, so (And A B) and (And B A) agree, and in
S -> (And A (And B C)) both (And A B) and (And B C) are P* + (1 - P*)/7. K's
own connective over all its children is K, at K's value. Any other connective
over parts of one K is conditioned on K, given true and false; within each
branch K's children are read jointly, each given K and the children before
it.

A part's other parts are read at their values without searching them first;
their searches run as low-priority children of the part's search, on the
budget the direct work leaves, so a part read cold improves with budget.

Limits: the node's variance is exact only where its quadrature settles: each
rule twice as fine until two agree within 1 % (a factor constant to 1e-9 is a
point; one broad dimension is integrated on intervals graded toward its
endpoints, so a boundary layer as thin as 1e-12 is resolved), within 257
nodes a dimension and 70000 points, the prior and up to four uncertain
dimensions for independent messages; elsewhere, and past twelve atoms, the
answer claims the bound s(1 - s), confidence 0, tested before any rounding;
joint rows exist for at most four atoms; parts derived from each other by
rules inside the node (rule-derived atoms with their own observations) are
read as independent, and are then underconfident.

An `And` or `Or` premise, an antecedent or a queried compound, combines the
truth values of all its parts with `AndFormula` (`s1 s2`) or `OrFormula`
(`s1 + s2 - s1 s2`), so it needs a proof of every part. One part known with
certainty settles the compound without the others: a disjunct of `(STV 1 1)`
makes an `Or` `(STV 1 1)`, and a conjunct of `(STV 0 1)` makes an `And`
`(STV 0 1)`, whatever the other parts are, including parts with no proof. So
with `(A t)` stored as `(STV 1 1)`, `(Implication (Or (A $t) (B $t)) (C $t))`
concludes `(C t)` by its positive branch although `(B t)` is unknown; its
proof reads `(settled a)` in place of the conjunction of both parts. A part
settles only when it binds every variable of the compound and its value is a
certain stored fact (a derived value never reaches confidence 1), and only
certainty settles: an uncertain part still waits for the others, since
P(A or B) >= P(A) is only a bound. The settling value of a connective is configured with
`(set-compound-settling $head $value)` (`docs/metta/connective_settling.md`).

Variables in an ordinary antecedent are implicitly universally quantified. An
antecedent may instead request existential aggregation explicitly with:

```metta
!(compileadd kb
    (: doctorChild
       (Implication
          (Exists ($child)
                (And
                   (Parent $person $child)
                   (Doctor $child)))
          (HasDoctorChild $person))
       (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
```

`Exists` has the form `(Exists ($var ...) body)` and must wrap one complete
side of a stored implication. An antecedent accepts either a matching direct
`ExistentialClaim` or the disjunction obtained by querying its body for every
currently known witness. Free body variables such as `$person` form independent
result groups. The binder scopes over its complete body, so the same `$child`
must satisfy both predicates in the example. Put `And` inside the binder when
its body is conjunctive; an `Exists` nested inside an outer `And` is invalid. A
bound variable name may not be reused on the implication's other side.

An explicit existential conclusion introduces a proposition-level claim:

```metta
!(compileadd kb
    (: generate
       (Implication
          (Seed $x)
          (Exists ($y) (GeneratedBy $x $y)))
       (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
```

For a proof of `(Seed alice)`, the stored result is:

```metta
(ExistentialClaim (GeneratedBy alice (exists-slot 0)))
```

`exists-slot` is a canonical bound position, not an object and not a claim that
a new object distinct from all known objects was generated. Independent rules
for the same quantified body therefore contribute to the same existential
proposition. Variables which occur only in an ordinary, unwrapped conclusion
retain the constructive behavior and become stable `(exists rule index args)`
Skolem terms.

Variables in an ordinary antecedent retain the implication's universal scope
even when they do not occur in the consequent. Use explicit `Exists` when the
antecedent should instead aggregate existential evidence. Variables bound by
an existential antecedent are eliminated by that aggregation and do not become
dependencies of generated consequent witnesses.
Nested existential binders, direct existential queries, and existential terms
in bidirectional implications are currently rejected rather than interpreted
as ordinary predicates.

Two additional complete-premise forms expose an existential's open witness
population without treating it as complete:

```metta
(KnownExistential ($y) (GeneratedBy alice $y))
(ExistentialResidual ($y) (GeneratedBy alice $y))
```

`KnownExistential` folds the matching witness TVs with `OrFormula` to produce
the currently enumerated disjunction D. `ExistentialResidual` also consumes the
corresponding direct `ExistentialClaim` E and reads the remaining U off the
event node of `E = D or U`: E's message to U when E is observed (stored), its
Jeffrey update of U's uniform prior when E is derived (see "What a compound's
value says about its parts"). Both forms are lazy FoldAll-backed
premises and their bound variables do not escape into the conclusion.

### Premises that reuse evidence

A rule may read a premise derived from a fact that it also reads, directly or
through another derived premise:

```metta
!(compileadd kb (: a (A x) (STV 1.0 0.9)))
!(compileadd kb (: b (B x) (STV 1.0 0.9)))
!(compileadd kb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (STV 0.9 0.9)))
!(compileadd kb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (STV 0.9 0.9)))
```

Multiplying the premises would count `a` twice, so `(D x)` is instead
conditioned on `(A x)`. The rule is evaluated once with `(A x)` known true and
once known false, and the two results are mixed by the value of `(A x)`, which
is the chain rule P(A and C) = P(A) P(C | A). The proof records both branches:

```metta
(conditioned a
   (by r2 (conjunction (given true) (by r1 (conjunction (given true) b))))
   (by r2 (conjunction (given false) (by r1 (conjunction (given false) b)))))
```

`(given true)` and `(given false)` mark the statement taken as known. They are
assumptions, not evidence: the evidence of the proof counts `a` once, through
the weight `a` at the head.

A premise that reads the conditioned statement itself reads it as known, so
`(And K K)` is K. Premises sharing a compound's node views condition on the
compound, given true and false. Conditioning is not used for rules whose
conclusion is not a simple truth value; their premise is refused, as before. Folds read under a
condition take their ordinary values. A query or forward run pays for
conditioning from its evaluation allowance (see
`docs/metta/runtime_design_assumptions.md`), so a small one may leave such a
conclusion for a later one.

Two proofs of one statement that both read an uncertain statement, a stored
fact or a derived one, are conditioned on it the same way: the answer is
`(conditioned <weight> <merge given true> <merge given false>)`, each branch
the statement's proofs merged with the shared one known
(`docs/metta/overlap_conditioning.md`). Before conditioning completes, its
conservative component fallback is the answer. Conditioning spends the remaining
query allowance on actual row evaluations and retains the deepest completed
pass; an incomplete pass cannot replace that fallback.

A rule that builds terms from its own conclusions, such as
`(AtTime $x $t) ∧ (AtTime $y $t) → (AtTime (And $x $y) $t)`, derives ever
larger terms, `(And X (And X Y))` among them: `And` inside a term is data, and
each such conclusion is valid. Only the budget bounds them, as it bounds any
recursive rule.

### Querying an implication

A query for an implication is answered by two producers whose proofs revise
into one answer:

```metta
!(query 100 kb (: $prf (Implication (A $x) (B $x)) $tv))
```

The hypothetical producer assumes the antecedent in a fresh context and derives
the consequent through the stored rules, once positively and once for the
refuting branch. The context borrows world observations of other statements
as co-premises, never of the consequent (#63), and a derivation counts only
when it depends on the assumed antecedent (#65). It answers only when some
rule connects the two sides.

The empirical producer samples the instances. For every binding of the
antecedent variables whose antecedent and consequent are both provable, it
folds one sample whose value is the consequent strength weighted by both
sides' confidence. With the facts `(A a)`, `(A b)`, `(A c)`, `(B a)`, `(B b)`
the query above answers strength 1.0 with count-based confidence from two
samples. `c` contributes nothing: an antecedent instance without a provable
consequent is not a counterexample, so no universe size is needed. A stored
`(Not (B c))` is a sample with consequent strength 0 and lowers the strength.
A binding whose antecedent is false (a stored `(A d)` with strength 0) is a
sample of the negative branch: each sample counts towards P(B|A) with the
antecedent's strength as its weight and towards P(B|not A) with the
complement, so both branches are frequencies with count-based confidence.
While no sample has a false antecedent, the negative branch is derived from
the base rates of both sides by the heuristic that reinterprets a stored STV
rule as a CTV. Either way the empirical proof is a CTV, so it and a stored
rule revise on equal terms and the answer can serve as a rule premise.

Consequent proofs are resolved through the backward chainer, so instances
derived by other rules count as samples with their proof identities intact,
unless the derivation uses the sample's own antecedent facts. A consequent
proof through a rule that restates the queried implication is never a sample,
so a rule's own derivations never confirm it: the sample takes the
consequent's other proofs, and is dropped when there are none. When both
producers answer, the rule's proof and the independent samples revise. The
empirical producer applies when every consequent variable occurs in the
antecedent and both sides are plain predicate conjuncts; conditional,
computed, negated, or existential sides are answered hypothetically only.

### Rules that conclude an implication

A rule may conclude an implication:

```metta
!(compileadd kb (: r (Implication (A $x) (Implication (B $x) (C $x))) (STV 0.9 1.0)))
```

It holds as its exported form `(Implication (And (A $x) (B $x)) (C $x))`: its
truth is that rule's (an STV's negative branch comes from the base rates of
`(And (A $x) (B $x))` and `(C $x)`). From `(A x)` it derives the statement
`(Implication (B x) (C x))`, a CTV whose negative branch is the exported
rule's, and the statement is applied to `(B x)` by modus ponens like a rule,
proof `(by (by r a) b)`. The answer has the flat rule's strength for any
truth of `(A x)` and `(B x)`, at any depth of nesting; its confidence is close
to the flat rule's but not equal. The derived statement is also an answer of
an implication query for it. Such a rule is not inverted
(docs/metta/derived_implications.md).

### Rules that hold for each value of a parameter

An implication's variables are averaged over: `(Implication (Leak $c $u)
(Alarm $c $u))` states the probability of an alarm given a leak for a random
cohort and unit. When the rule instead holds for each cohort with the same
truth, wrap it in `ForAll`:

```metta
!(compileadd kb (: sensor (ForAll ($c) (Implication (Leak $c $u) (Alarm $c $u)))
                   (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
```

The variables `ForAll` binds are parameters; the others are the individuals
the rule's probability ranges over. The rule applies as an ordinary rule, but
every base rate it needs, to reinterpret an STV truth or to invert the rule,
is taken per parameter value: inverting the sensor rule for an alarm in cohort
`old` uses the leak and alarm rates of `old` units only. A refined `ForAll`
rule pools its instances across the parameter values, since they share one
truth.

### Updating an instance's own belief

Inverting a rule normally uses population base rates: an alarm on unit `m`
yields P(leak | alarm) for a random unit. When `m` has its own prior belief,
name it with `WithPrior`:

```metta
!(compileadd kb (: sensor (WithPrior (LeakPredicted $u)
                            (Implication (SealLeak $u) (Alarm $u)))
                   (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
```

The rule is then also inverted per instance: the observation `(Alarm m)`
updates `(LeakPredicted m)` by Bayes' rule, with P(alarm) derived from that
prior and the rule by total probability, and the result proves `(SealLeak m)`.
For an instance without a provable prior, the base rate of the rule's
antecedent stands in as the prior, still with P(alarm) derived from it, so the
update never contradicts the rule; the instance's own update carries more
evidence and replaces that answer wherever its prior is provable. Together with a transition rule that predicts the
next state from the current one, this is a filter over time: each state's
posterior predicts the next, and each observation updates that prediction.
`WithPrior` may appear inside `ForAll`.

An inversion's proof names its prior,
`((inverted rule with P (prior TV)) observation)`, with `P` the prior's proof,
or `cpu` for a base rate, and `TV` its truth. Inversions of different
observations over one prior, a base rate or an instance's own, through
different rules or through one rule stated with confidence 1, combine by
Bayes' rule: each multiplies the prior odds by its
observation's likelihood ratio, so the prior counts once and an uninformative
observation changes nothing (`docs/metta/prior_factored_merge.md`). An
inversion over a base rate and a derived view of the statement that shares
none of its evidence, such as a forward conclusion from other observations,
combine the same way, with that view in the base rate's place: its odds times
the inversions' likelihood ratios. Their proof is
`(factored-revision P (prior TV) (inversion ...))` with `P` the other view's
proof. A stored fact of the instance, already counted in the base rate, and
a certain view are not combined this way.

A rule whose truth is an estimate, stated with confidence below 1 or refined
from its instances, is evidence of every proof through it, so a proof of the
rule itself and a proof through it are not independent; a rule stated with
confidence 1 (in both branches of a CTV) is given and carries no evidence.
Proofs that apply one rule to different premises are independent either way:
given the rule's truth they share nothing, and its uncertainty is in each
proof's confidence. A ground
statement stored with confidence 1 is its own value: no rule is applied to it,
and proofs found for it before it was stored no longer count.

### Refining rules from their instances

Rule refinement is opt-in per KB and must be set before the rules are added:

```metta
!(set-rule-refinement kb true)
!(compileadd kb (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))
```

A refined rule no longer applies with its stored truth. Its truth is the goal
`(RuleTruth (Implication (A $x) (B $x)))`, shared by every application of the
rule: the stored truth is that goal's axiom fact `(rule-axiom ab)`, the rule's
instance fold is a second proof, and revision merges them. The rule applies
with the merged truth forward, backward, and inverted, so an observation of
the consequent is explained through the refined rule too. A rule's own
derivations never count as its samples, nor do values that depend on any
refined rule's truth: what other hypotheses predict is not an observation.
Applied to an instance whose own sample is in the fold, the rule reads its
truth without that sample. The fold keeps each sample's contribution: facts
added later are taken at the next query or forward run, whatever it asks,
at the cost of the samples they change. The axiom carries the rule's own evidence,
so a proof through the axiom and a proof through the rule are dependent and
never revise twice.

An STV rule's truth merges as an STV and is converted through base rates
where it is applied. Its instances are members those rates count, and they
have already moved the truth by their evidence, so the truth applies as it is
and the rates derive only its negative branch: reconciling it with them (see
the Fréchet bounds below) would count its instances again and drain its prior.
A rule stated with frequency .8 at count 8 and twelve instances that all hold
answers .92 at count 20, as its truth goal, as an implication query and
applied to a new instance. A CTV rule's fold learns both branches as an implication
query does: P(B|A) from the instances where A holds and P(B|not A) from those
where it fails, or from the base rates of A and B while there are none. An
implication query of a refined rule's shape answers through the goal (proof
`(rule-truth ...)`) instead of folding the instances again. Rules whose shape
the instance producer does not sample keep their stored truth, and so do rules
stated with confidence 1 (for a CTV, in its positive branch): revision leaves
a certain truth unchanged, so their instances are not folded. Forward
chaining fires refined rules with the truth goal's current value.

A refined rule is searched in proportion to what applying it can add: its
expected confidence is scaled by its truth's confidence times, for a CTV,
|P(B|A) − P(B|not A)| (at least 0.01, so it is still reached with budget to
spare). A weakly held rule, a hypothesis, is therefore searched little until
the data confirms it, and a rule whose consequent does not move with its
antecedent falls back to the floor. The first query that reads the goal, for
instance `(query 50 kb (: $p (RuleTruth (Implication ...)) $tv))`, folds the
instances; from then on the truth and the score follow new instances without
one (docs/metta/hypothesis_rules.md).

A refined rule's rate may change while the KB runs. Each branch of its
instance tally keeps the samples as regimes (an old one, the current one and a
candidate since a possible change), and the rule's truth is the posterior
mixture over where the rate changed. The prior probability that a sample
starts a new regime is the KB's hazard, 0.0001 by default:
`!(set-rule-change-hazard kb 0.001)` expects changes more often, and
`!(set-rule-change-hazard kb 0)` keeps one regime. On samples of one rate the
truth is the one in one regime; after a change the new samples take over as
their evidence grows, and an earlier regime that returns counts its old samples
at once. Only a rule that can apply to stages has regimes: one of its
variables is at a position declared `Stage` or `Time`, or at one where a
constant of sort `Stage` or `Time` was stated (with `set-constant-sort` or
through a declared position). Every other rule, whatever its arity, is
stationary and keeps one regime whatever the hazard: its estimate is the
plain frequency of its samples. A KB that declares no sorts has no stages,
so all its rules are stationary; declare the stages of a rule whose rate may
change.

A KB can also propose its own hypotheses (off by default):

```metta
!(set-hypothesis-mining kb 8 16)
!(set-time-link kb NextPeriod)
!(set-predicate-time kb Storm 2 0)
!(set-predicate-time kb Blocked 2 1)
```

Mining reads only predicates with a declared place in time: the argument
holding the time point a fact refers to, and its layer within a time point.
Each added true fact then proposes up to 8 refined rules with a weak prior
between it and recent true facts sharing a constant with it at its time
point or an adjacent one (linked by `NextPeriod`): the earlier fact, or at
one time point the lower layer, is the antecedent, whichever arrived first.
A pair is proposed at once, a single fact once it recurs in another context;
across a link the link is a conjunct, as in
`(And (NextPeriod $q $p) (Storm north $q)) → (Storm north $p)`. A consequent
pattern keeps at most 16 live ones. `!(review-hypotheses 200 kb (Reward left t9))`
reads the truths of the live hypotheses that apply to a goal (a variable
reviews all) and drops those whose truth does not differ from the
consequent's probability without them, or from a more general hypothesis's (docs/metta/hypothesis_rules.md, "Mining hypotheses").

### Complete predicates

The chainer is open-world: a statement with no proof is unknown. A KB may
declare that a predicate's rules and facts are the only ways one of its
statements becomes true, before adding knowledge:

```metta
!(set-complete-predicate kb Producing)
!(set-complete-predicate kb Fuelled)
!(set-complete-predicate kb FuelArrived)
```

A ground statement of a complete predicate is then false when nothing outside
a loop supports it. In

```metta
(: fuelled (Implication (Or (StockedFuel $t) (FuelArrived $t)) (Fuelled power $t)) (CTV (STV 1 1) (STV 0 1)))
(: arrives (Implication (And (Producing mine $t) (Not (Blocked fuel $t))) (FuelArrived $t)) (CTV (STV 1 1) (STV 0 1)))
```

with the mine powered by the plant the fuel feeds, `FuelArrived t` is read
by the `fuelled` rule with `Fuelled power t` itself taken false (proof
`unfounded`): the loop cannot fuel itself, so the plant is fuelled with the
stock's strength, 0 without stock and 0.9 with a stock of 0.9. A complete
statement that no rule concludes and no fact states is false,
`(: unfounded (Q a) (STV 0.0 1.0))`.

Only complete statements are taken false this way, and only once their search
has examined every rule application concluding them: a premise not yet
expanded, or an open statement with no proof, leaves the statement unknown,
so a small budget never concludes false. Statements in a hypothetical context
(`Assuming`, implication queries) stay open (docs/metta/complete_predicates.md).

## Built-in Premise Forms

### 1) Plain predicates

```metta
(Room $room)
```

### 2) Compute

Runs a function and binds output:

```metta
(Compute + ($a $b) -> $sum)
```

Implication inversion supports one restricted arithmetic subset. A top-level
binary `Compute` using `+` or `-` may be reversed when its result is known and
exactly one direct argument variable is unknown. The other argument must
already be known. For example:

```metta
(Implication
   (And (A $x) (Compute + ($x 1) -> $y))
   (B $y))
```

Given `(B 3)`, the inverse rule computes `$x` with `3 - 1`, then reruns the
original `2 + 1` computation as a validation before producing the antecedent.
Several eligible computations may form a chain; they are reversed from the
consequent back toward the antecedent.

The compiler emits no inverse rule when a computation has zero or multiple
unknown inputs, the unknown is nested inside an argument, the function is not
one of the supported `+`/`-` modes, or another CPU premise such as `FoldAll` is
present. `no_inverse` still disables inversion explicitly. Truth-value
inversion and modus ponens are unchanged; the arithmetic inverse only
reconstructs variable bindings.

The compiler-generated TV computation for a pure top-level `Or` does not
trigger that veto. A rule such as `(Or A B) -> C` may be inverted from `C` to
the whole `Or`, whose predicted value then moves `A` given `B`, or vice versa
(see "What a compound's value says about its parts"). Ordinary
multi-premise `And` rules reconstruct no variable bindings unless they contain
a supported reversible `Compute`; their children are instead proved directly
by antecedent completion.

A rule is inverted by Bayes' rule with the base rate of its antecedent `A` as
the prior. A rule stated with a `CTV` gives both likelihoods, `P(B|A)` and
`P(B|not A)`, so `P(A|B) = P(B|A) P(A) / (P(B|A) P(A) + P(B|not A) (1 - P(A)))`
and the base rate of `B` is not read: an observed `P(B)` that disagrees with
`P(A)` and the stated likelihoods, as small histories often do, cannot decide
the inversion. A refined `CTV` rule is inverted with its learned branches. A
rule stated with an `STV` gives only `P(B|A)`; its negative branch is read from
the base rates of both sides, and its inversion is the ratio
`P(B|A) P(A) / P(B)` over them.

The missing negative branch is estimated by
`P(B|not A) = (P(B) - P(A) P(B|A)) / (1 - P(A))` only while all three
reconciled estimates retain evidence and `P(A) < 1`. Otherwise that branch is
unknown, `(STV 0.5 0)`, or `(STV 0 0)` when the conclusion's predicate is
complete: only rule applications make it true, so a rule whose condition fails
adds nothing, and a single sufficient cause `A` gives `P(B) = P(A) P(B|A)`.
Selecting an unknown branch gives that branch at zero confidence;
it contributes nothing when an informative view of the conclusion exists.
Thus a positive STV rule with a known-false condition cannot override an
applicable rule. An explicit CTV branch or a separately stated rule with a
negative antecedent retains its ordinary meaning.

Inverting an `STV` rule, and reading its negative branch from base rates,
need `P(B|A)` within the Fréchet bounds `P(A)` and `P(B)` allow:
`max(0, P(A)+P(B)-1)/P(A) <= P(B|A) <= P(B)/P(A)`. When the three estimates
violate them, the least evidence that restores them is dropped first, either
drained from all three or by giving up the one with the least evidence
entirely, and the rule applies with what remains, at lower confidence. So a
rate estimated from one observation gives way to a well-supported rule rather
than overriding it. A truth learned from instances (a refined rule's, or an
implication query's instance fold) keeps its positive branch: the rates count
those instances, which it already holds, and only its negative branch is
reconciled.

### Antecedent completion

A stored implication whose antecedent is a pure top-level `And` also proves
each antecedent child from the other children plus the consequent. For

```metta
(Implication (And O M) C)
```

the compiler adds, per child `M`, the completion rule `(And O C) -> M`. Its
proofs have the form

```metta
((antecedent-completion rule idx with cpu (prior <P(M)>)) witnesses)
```

where `idx` is the zero-based position of `M` in the `And`, `witnesses` is
the conjunction of the proofs of `O` and `C`, and `<P(M)>` is the base rate of
`M` the completion updates. The completion is Bayes' rule over that base
rate, with `u = P(C | O and M)` and `v = P(C | not (O and M))` the rule's two
branches (for an `STV`-valued rule, `v` is recovered from the base rates of
`(And O M)` and `C`):

- given `O` and `C`: `P(M | O, C) = u P(M) / (u P(M) + v (1 - P(M)))`
- given `O` and not `C`: the same with `1 - u` and `1 - v`
- `C`'s value weighs the two by modus ponens, and `O`'s value weighs the
  result against `P(M)`, since without `O` the rule says nothing about `M`.

So the completion reads no base rate of `C` or of `(And O C)`: a value as
likely as the rule makes it leaves `P(M)`, and the view merges with other
updates of `P(M)`, such as an inversion of another rule on `M`, by Bayes'
rule (`docs/metta/prior_factored_merge.md`). The completion has no result
when `P(M)` is unavailable; pin it with `(set-base-rate kb pattern tv)` when
the knowledge base cannot estimate it.

Completion is compiled only for a plain `And` antecedent (no `Exists`), only
when the antecedent contains no source `Compute` premise, and only for
children that are not bare variables and whose variables are exactly the
variables of the other children plus the consequent. A child that carries a
variable absent from the rest of the rule is skipped, and so is a child that
alone links the others' variables: for `(Implication (And (Next $p $u) (Leak
$p)) (Pred $u))`, recovering `(Next $p $u)` from `(Leak $p)` and `(Pred $u)`
would infer a link for every pair of unrelated instances. A rule named
`no_inverse` gets no completion either. The completion reads `C` as an
observation, so it applies only when `C`'s predicate can be observed: a
statement of it is stored, or an inversion or another completion concludes
it. A consequence that only forward rules predict carries no evidence about
`M`, and the rule start prunes the completion.

```metta
!(compileadd kb (: a A (STV 1.0 0.9)))
!(compileadd kb (: c C (STV 1.0 0.9)))
!(compileadd kb (: ab_c (Implication (And A B) C) (CTV (STV 0.9 1) (STV 0.3 1))))
!(set-base-rate kb B (STV 0.3 0.9))
!(query 2000 kb (: $proof B $tv))
```

proves `B` through
`(: ((antecedent-completion ab_c 1 with cpu (prior (STV 0.3 0.9))) (conjunction a c)) B (STV 0.5625000000000001 0.8847429725023245))`:
`0.9 * 0.3 / (0.9 * 0.3 + 0.3 * 0.7) = 0.5625`. A completion for a child of an
`STV`-valued implication or of a three-way `And` works the same way.

### 3) FoldAll / FoldAllValue

Aggregate over matching facts:

```metta
(FoldAll pattern value init fold-fn -> out)
(FoldAllValue pattern init fold-fn -> out)
```

Typical distribution fold:

```metta
(FoldAllValue (In $room $kid)
              (ParticleFromPairs ((0 1.0)))
              ParticleAddBernoulliFromSTV
              -> $dist)
```

`FoldAllTruth` also matches each member's truth value against a pattern, so
the value can read it:

```metta
(FoldAllTruth pattern truth value init fold-fn -> out)
```

The fold reads its members' truth values as data, so it is not revised
against their evidence: a rule may fold every candidate's belief and then read
one of the same candidates again. Normalizing beliefs over a group:

```metta
(: share
   (Implication
      (And (FoldAllTruth (Leak $v) (STV $s $_c) $s 0.0
              (|-> ($acc $elem) (+ $acc $elem)) -> $total)
           (Leak $u)
           (FoldAllTruth (Leak $u) (STV $su $_cu) $su 0.0
              (|-> ($acc $elem) $elem) -> $mine)
           (Compute / ($mine $total) -> $p))
      (Share $u))
   (CTV (STV $p 1.0) (STV $p 1.0)))
```

### 4) Not

```metta
(Not expr)
```

### 5) GreaterThan / >

Two forms are supported:

- Distribution vs numeric threshold:

```metta
(CntKidIn $room $cnt)
(GreaterThan $cnt 1)
```

Compiled to `DistGreaterThanFormula` over the bound distribution value.

- Distribution vs distribution (compile sugar):

```metta
(CountryHeightDist countryA $distA)
(CountryHeightDist countryB $distB)
(GreaterThan $distA $distB)
```

Compiled to `DistGreaterThanDistFormula`.

### 6) MapDist / Map2Dist / AverageDist

Distribution helper premises with explicit value binders:

```metta
(MapDist f (DistFactA ... $inDist) $inDist -> $outDist)
(Map2Dist f (DistFactA ... $distA) $distA (DistFactB ... $distB) $distB -> $outDist)
(AverageDist (DistFactPattern ... $inDist) $inDist -> $outDist)
```

- `MapDist` compiles to `DistMapFormula`.
- `Map2Dist` compiles to `DistMap2Formula`.
- `AverageDist` compiles to `DistAverageFormula`.

## Distribution Operations

### Threshold probability

```metta
(DistGreaterThanFormula dist threshold)
```

Returns `STV(P(dist > threshold), confidence)`.

### Distribution comparison

```metta
(DistGreaterThanDistFormula distA distB)
```

Returns `STV(P(distA > distB), confidence)`.

### Particle transforms

Unary map:

```metta
(ParticleMap f particleDist)
```

Binary composition:

```metta
(ParticleMap2 f particleDistA particleDistB)
```

### Particle update from STV Bernoulli

```metta
(ParticleAddBernoulliFromSTV particleDist stv)
```

## Particle Computation Confidence

Particle-based threshold and comparison formulas currently return confidence
`1.0`. Particle weights describe the probability distribution itself; their
concentration is not evidence about the reliability of that distribution. The
source fact and rule TVs continue to carry epistemic confidence through normal
proof composition.

The particle budget compresses a distribution and thereby introduces numeric
approximation error. Structured samples with the same constructor and symbolic
leaves, such as `(Coefficients 0.8 -0.2)`, opt into geometric condensation.
The strongest samples become anchors; each weaker overflow sample is merged
into the compatible anchor with the least weighted Ward loss. Every numeric
leaf moves to the shared weighted centroid, so the coefficient vector remains
one joint sample rather than being split into independent marginals. Samples
with incompatible structure are never merged. If the support cannot be
condensed geometrically, deterministic systematic resampling is used instead.

Bare numbers retain systematic resampling because the representation does not
say whether they are continuous values or discrete states such as Bernoulli
counts. Wrap continuous parameters in a domain constructor to declare their
geometry. Each model should own its own `ParticleDist`; the model name is not a
coordinate inside a shared coefficient distribution.

Approximation quality is not represented yet. A future representation should
carry evidence or approximation-quality metadata separately from both particle
weights and the existing `ParticleDist` scale (which contributes to result
strength). This separation is also required if particle distributions
eventually replace STVs: distribution shape, epistemic support, and
representation quality must not be conflated.

## Particle Store Utilities

- `(ParticleStoreCount)` -> number of stored `(particle id x w)` atoms
- `(ParticleStoreClear)` -> clears store and resets particle id counter
- `(ParticleStorePruneKB)` -> keeps only particle ids reachable from current `&kb` facts

## End-to-End Example

```metta
!(compileadd kb (: countryHeightA
    (CountryHeightDist countryA (ParticleFromPairs ((170 0.5) (180 0.5))))
    (STV 1.0 1.0)))

!(compileadd kb (: countryHeightB
    (CountryHeightDist countryB (ParticleFromPairs ((175 1.0))))
    (STV 1.0 1.0)))

!(compileadd kb (: compareHeightsRule
    (Implication
        (And
            (CountryHeightDist countryA $distA)
            (CountryHeightDist countryB $distB)
            (GreaterThan $distA $distB))
        (Taller countryA countryB))
    (STV 1.0 1.0)))

!(query 40 kb (: $prf (Taller countryA countryB) $tv))
```

## Example: Average Height Distribution in a Group

This example computes average height distributions via a rule and queries the derived fact.
Each person height stores the distribution in the term, while the `tv` slot remains `STV`.

```metta
!(compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))
!(compileadd kb (: hd11 (HeightDist g1 alice (PointMass 160.0)) (STV 1.0 1.0)))
!(compileadd kb (: hd12 (HeightDist g1 bob (PointMass 170.0)) (STV 1.0 1.0)))
!(compileadd kb (: hd13 (HeightDist g1 carol (PointMass 180.0)) (STV 1.0 1.0)))

!(compileadd kb (: avgHeightDistG1Rule
    (Implication
        (And
            (Group g1)
            (AverageDist (HeightDist g1 $person $heightDist) $heightDist -> $avgDist))
        (AvgHeightDist g1 $avgDist))
    (STV 1.0 1.0)))

!(query 10 kb
    (: (avgHeightDistG1Rule (conjunction group1 cpu))
       (AvgHeightDist g1 $avgDist)
       $tv))
```

## Example: Rectangle Area Distribution

Area is the product of length and width distributions, derived through a rule.

```metta
!(compileadd kb (: lenA (LengthDist rectA (ParticleFromNormal 10.0 1.0)) (STV 1.0 1.0)))
!(compileadd kb (: widA (WidthDist rectA (ParticleFromNormal 5.0 0.5)) (STV 1.0 1.0)))

!(compileadd kb (: areaDistRule
    (Implication
        (And
            (Rectangle $rect)
            (Map2Dist *
               (LengthDist $rect $lengthDist)
               $lengthDist
               (WidthDist $rect $widthDist)
               $widthDist
               ->
               $areaDist))
        (AreaDist $rect $areaDist))
    (STV 1.0 1.0)))

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))

!(query 120 kb (: $prf (AreaDist rectA $areaDist) $tv))
```

## Notes

- `NatDist`/`FloatDist` remain available for exact small cases.
- `ParticleDist` is preferred for scalability.
- Rule/application truth functions still use STV semantics for implication chaining.
