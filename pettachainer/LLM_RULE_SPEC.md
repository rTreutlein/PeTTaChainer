# PeTTaChainer LLM Rule Spec

This spec focuses only on constructing valid Statements and Queries.
It does not describe how to invoke chainer interface functions.

## Core Forms

- Statement form (fact or rule assertion):

```metta
(: proof-id type tv)
```

- Query pattern form:

```metta
(: $proofVar typePattern $tvVar)
```

For a negative ground observation, prefer the canonical zero-strength form:

```metta
(: noLeak (SealLeak old unit-1) (STV 0.0 1.0))
```

The equivalent user-facing negation is also accepted:

```metta
(: noLeak (Not (SealLeak old unit-1)) (STV 1.0 1.0))
```

The compiler stores the latter as `SealLeak` with complemented strength and
unchanged confidence. This lets population/base-rate folds count both positive
and negative observations. `Not` remains available normally in rule premises,
rule conclusions, and queries.

## Assuming Queries

`Assuming` asks a query as if some premises held, without storing them. The
`(: $proof ... $tv)` annotation encloses the whole `Assuming` form, which
takes exactly two arguments: the premises and the goal.

```metta
(: $proof (Assuming (: premise (Accepted Report1) (STV 1.0 1.0)) (Claim Topic1)) $tv)
```

- **Premises:** one premise, or several combined with `And`. Never a bare
  list of premises.
- **A bare premise** such as `(Accepted Report1)` is certain.
- **A weighted premise** is written as a stored statement,
  `(: name statement tv)`. It can be a closed fact or `(Not fact)` with an
  `STV`, or an implication (next section).
- **The goal** is an ordinary statement pattern, and its variables are
  answered.
- **Answers** have proof `(assuming ...)` and statement
  `(Assuming premises goal)` with the goal's bindings. Nothing is stored.

The examples below read a KB that holds `(About Report1 Topic1)` and the
rules `(Implication (And (Accepted $r) (About $r $t)) (Claim $t))` and
`(Implication (Claim $t) (Covered $t))`:

```metta
(: $proof (Assuming (Accepted Report1) (Claim Topic1)) $tv)
(: $proof (Assuming (: premise (Accepted Report1) (STV 0.8 0.9)) (Claim Topic1)) $tv)
(: $proof (Assuming (: premise (Not (Accepted Report1)) (STV 0.9 0.9)) (Claim Topic1)) $tv)
(: $proof (Assuming (And (: premise (Accepted Report2) (STV 0.8 0.9)) (About Report2 Topic2)) (Claim Topic2)) $tv)
(: $proof (Assuming (Accepted Report1) (Claim $topic)) $tv)
```

### Implication premises

An implication premise is a rule of the query's world. A bare one is
certain; a weighted one takes an `STV` or a `CTV`. Its variables are its own,
as a stored rule's are. They are standardized apart from the goal's and from
other premises' variables, even when spelled the same, and each application
binds them anew (#120, #127). Both sides must be given, and the consequent
must be a plain statement: a nested implication or an `Exists` consequent is
rejected.

```metta
(: $proof (Assuming (And (Accepted Report1) (: bridge (Implication (Claim $t) (Newsworthy $t)) (STV 0.6 0.8))) (Newsworthy $t)) $tv)
(: $proof (Assuming (And (Accepted Report1) (: bridge (Implication (Claim $t) (Newsworthy $t)) (CTV (STV 0.6 0.8) (STV 0.1 0.8)))) (Newsworthy Topic1)) $tv)
(: $proof (Assuming (And (Accepted Report1) (Implication (Claim $t) (Newsworthy $t))) (Newsworthy Topic1)) $tv)
```

In the first example the goal's `$t` and the rule's `$t` are different
variables; the answer binds the goal's `$t` to `Topic1`.

### Stored rules and assumed rules

A rule stored in the KB applies to the premises, and judging it reads its
stated value:

```metta
(: $proof (Assuming (Accepted Report1) (Covered Topic1)) $tv)
(: $proof (Assuming (Accepted Report1) (Implication (Claim $t) (Covered $t))) $tv)
```

A rule introduced as a premise applies the same way, but judging that rule
itself has no answer
([#129](https://github.com/rTreutlein/PeTTaChainer/issues/129)). Ask for its
consequences instead:

```metta
(: $proof (Assuming (: bridge (Implication (Claim $t) (Newsworthy $t)) (STV 0.6 0.8)) (Implication (Claim $t) (Newsworthy $t))) $tv)
```

### Not supported

These forms are rejected or have no answer. Do not write them:

```metta
(: $proof (Assuming ((Accepted Report1) (About Report1 Topic1)) (Claim Topic1)) $tv)
(: $proof (Assuming (Accepted Report1) (Assuming (Accepted Report2) (Claim Topic1))) $tv)
(: $proof (Assuming (Accepted Report1)) $tv)
(: $proof (Assuming (: premise (Accepted Report1) (CTV (STV 1 1) (STV 0 1))) (Claim Topic1)) $tv)
(: $proof (Assuming (Implication (Claim $t) (Implication (Hot $t) (Newsworthy $t))) (Newsworthy Topic1)) $tv)
(: $proof (Assuming (Implication (Claim $t) (Exists ($x) (Covers $x $t))) (Claim Topic1)) $tv)
```

- **A bare list of premises** is read as one statement and answers nothing.
  Combine premises with `And`.
- **`Assuming` must be the outermost statement of the query.** It cannot be
  nested, nor sit under `And`, `Or` or `Not`
  ([#125](https://github.com/rTreutlein/PeTTaChainer/issues/125)), and it
  takes exactly its premises and a goal.
- **A weighted fact takes an `STV`**, not a `CTV`.
- **An implication premise** cannot have a nested-implication or an `Exists`
  consequent.
- **Without the enclosing `(: $proof ... $tv)`**, `(Assuming ...)` is not a
  query.

Two limits answer, but not as storing the premises would:

- An assumed `CTV` rule whose implication the KB already states is not
  combined with the stored rule
  ([#123](https://github.com/rTreutlein/PeTTaChainer/issues/123)).
- A rule that reads a population base rate counts only the KB's facts, not
  the weighted premises
  ([#124](https://github.com/rTreutlein/PeTTaChainer/issues/124)).

## Member and Inheritance

Use `Member` for an object belonging to a class:

```metta
(: tomHuman (Member Tom Human) (STV 0.99 0.9))
(: $prf (Member Tom Human) $tv)
```

Use `Inheritance` for a subclass or concept relationship:

```metta
(: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9))
(: $prf (Inheritance Human Mortal) $tv)
```

A concrete `Inheritance A B` assertion automatically supports both:

```metta
(Member $x A)      -> (Member $x B)
(Inheritance $x A) -> (Inheritance $x B)
```

Do not emit either helper rule yourself. PeTTaChainer generates both from the
original assertion's proof and truth value.

A concrete `Inheritance A B` query can also estimate the relationship from
objects that have both `(Member $x A)` and `(Member $x B)`. Memberships derived
by rules count as evidence; self-supporting and overlapping proof paths are
checked before aggregation; confidence follows the observed count.

Prefer `Member object class` for new instance data. Legacy object-style
`Inheritance object class` data remains supported, but mixing the two forms for
the same observation creates two distinct facts rather than aliases.

Member rules use the ordinary implication form. Use a `CTV` when the rule is a
conditional relationship:

```metta
(: humansAreMortal
    (Implication
        (Member $x Human)
        (Member $x Mortal))
    (CTV (STV 0.8 0.9) (STV 0.0 1.0)))
```

Population-based incremental estimation requires ground classes. Open
`Inheritance` queries may retrieve ordinary matching derivations, but they do
not register a concrete forward member estimate.

## Rule Template

```metta
(: ruleName
    (Implication
        (And
            premise1
            premise2)
        conclusion1)
    (STV 1.0 1.0))
```

`Implication` takes exactly two expressions: antecedent and consequent. Use a
direct expression for a singleton side and explicit `And` for a conjunction.
Multiple conclusions must be one joint expression, for example
`(And conclusion1 conclusion2)`.

## Premise Helpers You Can Use

### Exists

Use an explicit existential when one witness must satisfy a complete premise
body:

```metta
(Exists ($child)
    (And
        (Parent $person $child)
        (Doctor $child)))
```

On an antecedent, `Exists` must wrap that complete side of a stored
`Implication`. It accepts either a matching direct `ExistentialClaim` or the OR
fold over currently enumerable witnesses. Other body variables remain
correlated with the rule. Put conjuncts inside the binder's body. Do not nest
`Exists` inside an outer `And`, and do not reuse a bound variable on the
consequent side.

`Exists` may also wrap a stored implication conclusion:

```metta
(Exists ($y) (GeneratedBy $x $y))
```

The compiler stores a proposition-level claim such as
`(ExistentialClaim (GeneratedBy $x (exists-slot 0)))`. `exists-slot` marks a
bound position; it is not a concrete object. A variable occurring only in an
unwrapped conclusion instead keeps the constructive behavior and becomes a
stable `(exists rule index args)` Skolem term. Variables bound by an
existential antecedent are eliminated by aggregation and are not witness
dependencies. Do not generate nested `Exists`, direct `Exists` queries, or
`Exists` inside `BiImplication`.

When a rule needs the disjunction of only the currently known witnesses, use:

```metta
(KnownExistential ($y) (GeneratedBy $x $y))
```

When it needs the unexplained portion of a matching direct existential claim,
use:

```metta
(ExistentialResidual ($y) (GeneratedBy $x $y))
```

The latter computes U from `E = D or U`, where D is the lazy OR fold over known
witnesses. Neither form proves that the witness population is complete, and
their bound variables must not be reused in the conclusion.

### Compute

```metta
(Compute f (arg1 arg2 ...) -> $out)
```

For automatically invertible implications, use only a top-level binary `+` or
`-` computation with a result bound by the consequent and exactly one unknown
direct argument variable. The compiler solves that argument with the matching
arithmetic inverse and validates it by rerunning the original computation.
Eligible computation chains are solved in reverse order.

Do not expect automatic inversion for multiple unknown arguments, nested
unknowns, unsupported functions, or rules containing any other CPU premise
(including `FoldAll`). Those rules remain forward-only unless modeled with a
separate restricted inverse operator. `no_inverse` always forces forward-only
compilation.

A pure top-level `Or` antecedent remains invertible. Its TV-formula CPU is
introduced by lowering and is not a source computation. Inversion derives the
whole disjunction; ordinary OR projection may then recover one child from the
disjunction and the other known children. Ordinary multi-premise `And`
reconstructs no bindings unless it contains a supported reversible `Compute`;
its children are proved by antecedent completion instead.

### Antecedent completion

A pure top-level `And` antecedent is completed automatically: from
`(Implication (And O M) C)` the compiler also proves each child `M` from the
other children `O` and the consequent `C`, with proofs of the form
`((antecedent-completion rule idx with cpu (prior <P(M)>)) witnesses)` (`idx`
is the zero-based position of `M`). The truth value is Bayes' rule over the
base rate of `M` with the rule's two likelihoods (for an `STV`-valued rule the
negative one is recovered from the base rates of `(And O M)` and `C`); pin
base rates with `(set-base-rate kb pattern tv)` when the knowledge base cannot
estimate them, otherwise the completion yields nothing.

No completion is compiled for `Exists` antecedents, antecedents containing a
source `Compute`, bare-variable children, or children whose variables do not
all occur in the rest of the rule, nor for a rule named `no_inverse`.
Derived consequents support completion as they support inversion (PLN
induction); dependency sets exclude circular self-support, and closed-read
unfounded pins are refused. A stage (a statement about an event or time
point, by the sorts of `set-argument-sorts`, or of a predicate with a time
declaration, `set-predicate-time`) is updated only by evidence
from below (observations of the consequent and what follows from them), never
by a forward prediction from another cause. Do not declare time on a predicate
whose values come from claim rules pointing from a source to the claimed
state; encode claims as events caused by their content first. Do not write the
reverse rule by hand for a pure `And` antecedent; write the forward
implication and its base rates.

### Not

```metta
(Not expr)
```

### GreaterThan / >

```metta
(GreaterThan $distA 5)
(GreaterThan $distA $distB)
```

### MapDist

```metta
(MapDist f (DistFactA ... $inDist) $inDist -> $outDist)
```

### Map2Dist

```metta
(Map2Dist f (DistFactA ... $distA) $distA (DistFactB ... $distB) $distB -> $outDist)
```

### AverageDist

```metta
(AverageDist (DistFactPattern ... $inDist) $inDist -> $outDist)
```

### FoldAll / FoldAllValue

```metta
(FoldAll pattern value init fold-fn -> out)
(FoldAllValue pattern init fold-fn -> out)
```

## TV Modeling Rules

- `STV` is truth uncertainty only.
- Distribution TVs (`ParticleDist`, `NatDist`, `FloatDist`) are value uncertainty.
- For uncertain numeric values, use distribution TVs.
- A statement with no proof is unknown, not false. Do not add rules or facts
  only to make an underivable statement false: when a predicate's rules are
  all the ways it becomes true, the application declares the predicate
  complete, and its statements without a non-circular proof are then false.

Good:

```metta
(: h1 (HeightDist g1 alice (PointMass 160.0)) (STV 1.0 1.0))
(: h2 (HeightDist g1 bob (ParticleFromNormal 170.0 2.0)) (STV 1.0 1.0))
```

Avoid encoding numeric values in `STV` strength for measurement semantics.

## Distribution Constructors

```metta
(PointMass x)
(ParticleFromNormal mu sigma)
(ParticleFromPairs ((x1 w1) (x2 w2) ...))
```

When support exceeds `ParticleSetBudget`, a structured numeric sample such as
`(Coefficients 0.8 -0.2)` is treated as one joint vector and condensed with
nearby same-shaped samples. Use a separate `ParticleDist` for each model. Bare
numbers and symbols retain deterministic systematic resampling; wrap continuous
parameters in a domain constructor to opt into geometric merging.

## Example: Average Height Rule

```metta
(: avgHeightDistRule
    (Implication
        (And
            (Group $g)
            (AverageDist (HeightDist $g $person $heightDist) $heightDist -> $avgDist))
        (AvgHeightDist $g $avgDist))
    (STV 1.0 1.0))

(: $prf (AvgHeightDist g1 $avgDist) $tv)
```

## Example: Rectangle Area Rule

```metta
(: areaDistRule
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
    (STV 1.0 1.0))

(: $prf (AreaDist rectA $areaDist) $tv)
```

Exact `(PointMass x)` values retain their value-bearing representation in facts
and queries; they allocate no particle-store rows. General `ParticleDist` handles
remain opaque identities. Equal distribution contents do not imply independent
random variables or independent evidence.
