# PeTTaChainer Language Spec

This document describes how to write facts, rules, and queries in the PeTTaChainer MeTTa language used in this repository.

If you need an LLM-oriented helper-first spec, use `pettachainer/LLM_RULE_SPEC.md`.

## Core Model

- Knowledge is stored as proof atoms of the form:

```metta
(: proof-id type tv)
```

- A negated STV fact is canonicalized to its inner expression with complemented
  strength and unchanged confidence. For example,
  `(: noLeak (Not (SealLeak old unit-1)) (STV 1.0 1.0))` is stored as
  `(: noLeak (SealLeak old unit-1) (STV 0.0 1.0))`. This ensures ordinary
  population folds see negative observations. `Not` in rules and queries keeps
  its logical meaning.

- In user code, facts/rules are usually inserted with:

```metta
!(compileadd kb (: proof-id type tv))
```

- Incremental pattern mining on insert is off by default. To enable it for a KB:

```metta
!(enable-pattern-mining-on-add kb)
```

This updates mining statistics during `compileadd` without recompiling mined rules on every insert.
When you want to emit the current mined implication rules, run:

```metta
!(materialize-mined-implications kb)
```

- For a one-shot insert that also mines patterns without changing the KB default:

```metta
!(compileadd-mine kb (: proof-id type tv))
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

- `PointMass` encodes an exact value as a degenerate distribution.
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

For new knowledge, prefer `Member` for instance-to-class observations:

```metta
!(compileadd kb
    (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd kb
    (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(query 40 kb (: $prf (Member Tom Mortal) $tv))
```

The concrete `Inheritance Human Mortal` assertion is compiled into ordinary
inference views equivalent to:

```metta
(Member $x Human)       -> (Member $x Mortal)
(Inheritance $x Human)  -> (Inheritance $x Mortal)
```

These views are generated automatically. User code should not duplicate them.
The generated member view is marked non-invertible: observing that an object is
Mortal does not by itself prove that it is Human.

`Member` can also appear on either side of an explicit rule:

```metta
!(compileadd kb
    (: seedHuman
       (Implication
          (Member $x Seed)
          (Member $x Human))
       (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
```

### Estimating inheritance from members

A ground query such as:

```metta
!(query 100 kb (: $prf (Inheritance Human Mortal) $tv))
```

can infer class-level inheritance from objects for which both
`(Member object Human)` and `(Member object Mortal)` are provable. The sample
collector uses the normal backward chainer, so rule-derived memberships count
along with directly stored facts. It retains proof identities, rejects
self-supporting cycles, and avoids treating overlapping evidence as independent.

The member estimator uses count-based confidence: every observed member adds
evidence, and there is no closed-world population size to declare.
Forward chaining can maintain a provisional estimate incrementally after a
ground inheritance query has registered interest; a later backward query folds
the complete currently derivable sample set and refines that estimate.

PeTTaChainer also estimates ground `Inheritance A B` through its
total-implication path using `Inheritance x A` and `Inheritance x B`
observations. Concept priors used by inheritance base-rate folds can be
configured with:

```metta
!(set-concept-prior-confidence kb 0.5)
!(clear-concept-prior-confidence kb)
```

Only class terms are registered as concept nodes by `Member`; the member object
is not. Open queries such as `(Inheritance $subclass $superclass)` remain useful
for retrieving matching ordinary derivations, but variable classes cannot
register a selective incremental member estimate.

Legacy programs in this repository sometimes encode instance membership as
`(Inheritance object class)`. That representation remains supported for
compatibility and participates in inheritance-only reasoning. It is not an
alias for `Member`: adding both forms records two distinct propositions.

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
consequent such as `(And conclusion1 conclusion2)` and retain the normal
compound-output projection semantics.

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
corresponding direct `ExistentialClaim` E and calculates the remaining U from
`E = D or U`. The latter uses variance-based confidence propagation rather than
copying the existential confidence onto U. Both forms are lazy FoldAll-backed
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

Conditioning is not used in these cases:
- when a premise reads the same statement again, since P(K and K) is P(K);
- for projections of one conjunction, which pool;
- for rules whose conclusion is not a simple truth value.

In all three cases the premise is refused, as before. Folds read under a
condition take their ordinary values. A query or forward run pays for
conditioning from its evaluation allowance (see
`docs/metta/runtime_design_assumptions.md`), so a small one may leave such a
conclusion for a later one.

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
refuting branch. It answers only when some rule connects the two sides.

The empirical producer samples the instances. For every binding of the
antecedent variables whose antecedent and consequent are both provable, it
folds one sample whose value is the consequent strength weighted by both
sides' confidence. With the facts `(A a)`, `(A b)`, `(A c)`, `(B a)`, `(B b)`
the query above answers strength 1.0 with count-based confidence from two
samples. `c` contributes nothing: an antecedent instance without a provable
consequent is not a counterexample, so no universe size is needed. A stored
`(Not (B c))` is a sample with consequent strength 0 and lowers the strength.
The fold measures the positive branch. The negative branch is derived from the
base rates of both sides by the same heuristic that reinterprets a stored STV
rule as a CTV, so the empirical proof and a stored rule revise on equal terms
and the answer can serve as a rule premise.

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
derivations never count as its samples. Facts added later join the fold at
the next query that reads the goal. The axiom carries the rule's own evidence,
so a proof through the axiom and a proof through the rule are dependent and
never revise twice.

An STV rule's truth merges as an STV and is converted through base rates
where it is applied; a CTV rule's negative branch comes from its axiom. An
implication query of a refined rule's shape answers through the goal (proof
`(rule-truth ...)`) instead of folding the instances again. Rules whose shape
the instance producer does not sample keep their stored truth, and so do rules
stated with confidence 1 (for a CTV, in its positive branch): revision leaves
a certain truth unchanged, so their instances are not folded. Forward
chaining fires refined rules from the axiom fact, so facts it materializes
carry the stored truth.

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
the whole `Or`; the normal compound-output adapters can then project `A` given
`B`, or vice versa. OR projection uses the noisy-OR inverse and propagates
variance from both the reconstructed total and the known alternative. Ordinary
multi-premise `And` rules reconstruct no variable bindings unless they contain
a supported reversible `Compute`; their children are instead proved directly
by antecedent completion.

Inverting a rule, and reading an `STV` rule's negative branch from base rates,
need `P(B|A)` within the Fréchet bounds `P(A)` and `P(B)` allow:
`max(0, P(A)+P(B)-1)/P(A) <= P(B|A) <= P(B)/P(A)`. When the three estimates
violate them, the least evidence that restores them is dropped first, either
drained from all three or by giving up the one with the least evidence
entirely, and the rule applies with what remains, at lower confidence. So a
rate estimated from one observation gives way to a well-supported rule rather
than overriding it.

### Antecedent completion

A stored implication whose antecedent is a pure top-level `And` also proves
each antecedent child from the other children plus the consequent. For

```metta
(Implication (And O M) C)
```

the compiler adds, per child `M`, the completion rule `(And O C) -> M`. Its
proofs have the form

```metta
((antecedent-completion rule idx with cpu cpu) witnesses)
```

where `idx` is the zero-based position of `M` in the `And` and `witnesses`
is the conjunction of the proofs of `O` and `C`. The truth value is computed
directly from joint base rates rather than by inverting the whole conjunction
and projecting `M` out of it, which would introduce an independence
approximation. With `H = (And O M)` and `K = (And O C)`:

- positive branch: `P(M | K) = P(C | H) * P(H) / P(K)`
- negative branch: `P(M | not K) = (P(M) - P(C | H) * P(H)) / (1 - P(K))`

When `O` is empty this is ordinary inversion. The rule consumes the base
rates of `M`, `H` and `K`; an `STV`-valued implication additionally consumes
the base rate of `C` to form the implication's CTV first. Pin base rates with
`(set-base-rate kb pattern tv)` when the knowledge base cannot estimate them.
The completion has no result when a base rate is unavailable, when `P(K)` is
`0` or `1`, or when `P(C | H) * P(H)` is inconsistent with the marginals of
`M` and `K` (Fréchet bounds).

Completion is compiled only for a plain `And` antecedent (no `Exists`), only
when the antecedent contains no source `Compute` premise, and only for
children that are not bare variables and whose variables are exactly the
variables of the other children plus the consequent. A child that carries a
variable absent from the rest of the rule is skipped, and so is a child that
alone links the others' variables: for `(Implication (And (Next $p $u) (Leak
$p)) (Pred $u))`, recovering `(Next $p $u)` from `(Leak $p)` and `(Pred $u)`
would infer a link for every pair of unrelated instances. `no_inverse`
disables whole-antecedent inversion but not completion.

```metta
!(compileadd kb (: a A (STV 1.0 0.9)))
!(compileadd kb (: c C (STV 1.0 0.9)))
!(compileadd kb (: ab_c (Implication (And A B) C) (STV 1.0 0.9)))
!(set-base-rate kb (And A B) (STV 0.2 0.9))
!(set-base-rate kb C (STV 0.4 0.9))
!(set-base-rate kb (And A C) (STV 0.25 0.9))
!(set-base-rate kb B (STV 0.3 0.9))
!(query 2000 kb (: $proof B $tv))
```

proves `B` through
`(: ((antecedent-completion ab_c 1 with cpu cpu) (conjunction a c)) B (STV 0.8 0.24255226513533926))`.
A query constrained to that proof pattern returns the same proof, and a
completion for a child of a `CTV`-valued implication or of a three-way `And`
works the same way.

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
