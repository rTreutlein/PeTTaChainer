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
checked before aggregation. A configured universe size controls how observed
coverage contributes to confidence.

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
`Implication`. The variables listed in `($child ...)` are folded as witnesses;
other body variables remain correlated with the rule. Put conjuncts inside the
binder's body. Do not nest `Exists` inside an outer `And`, and do not reuse a
bound variable on the consequent side.

`Exists` may also wrap a stored implication conclusion:

```metta
(Exists ($y) (GeneratedBy $x $y))
```

The compiler replaces `$y` with a stable witness depending on the rule and the
free antecedent variables. Variables bound by an existential antecedent are
eliminated by aggregation and are not witness dependencies. A variable
occurring only in an unwrapped conclusion is given the same implicit witness
treatment. Do not generate nested `Exists`, direct `Exists` queries, or
`Exists` inside `BiImplication`.

### Compute

```metta
(Compute f (arg1 arg2 ...) -> $out)
```

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

### Finite weighted subset-sum inverse

Use the restricted exact inverse when a known total must generate possible
subsets from a finite candidate list:

```metta
(Compute WeightedSubsetSumInverse
   ($candidates $observedTotal)
   ->
   $weightedSelections)

(Compute WeightedSubsetMarginal
   ($weightedSelections $candidate)
   ->
   $conditionalProbability)
```

Candidates have shape `(WeightedCandidate identity contribution prior)`.
Contributions are exact and nonnegative, identities are unique, and priors are
independent. Preserve `WeightedSelections` as one joint result; do not assert
members from competing selections as independent facts.

## TV Modeling Rules

- `STV` is truth uncertainty only.
- Distribution TVs (`ParticleDist`, `NatDist`, `FloatDist`) are value uncertainty.
- For uncertain numeric values, use distribution TVs.

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
