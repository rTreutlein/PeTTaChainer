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
        (Premises (Member $x Human))
        (Conclusions (Member $x Mortal)))
    (CTV (STV 0.8 0.9) (STV 0.0 1.0)))
```

Population-based incremental estimation requires ground classes. Open
`Inheritance` queries may retrieve ordinary matching derivations, but they do
not register a concrete forward member estimate.

## Rule Template

```metta
(: ruleName
    (Implication
        (Premises
            premise1
            premise2)
        (Conclusions
            conclusion1))
    (STV 1.0 1.0))
```

## Premise Helpers You Can Use

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
        (Premises
            (Group $g)
            (AverageDist (HeightDist $g $person $heightDist) $heightDist -> $avgDist))
        (Conclusions
            (AvgHeightDist $g $avgDist)))
    (STV 1.0 1.0))

(: $prf (AvgHeightDist g1 $avgDist) $tv)
```

## Example: Rectangle Area Rule

```metta
(: areaDistRule
    (Implication
        (Premises
            (Rectangle $rect)
            (Map2Dist *
                (LengthDist $rect $lengthDist)
                $lengthDist
                (WidthDist $rect $widthDist)
                $widthDist
                ->
                $areaDist))
        (Conclusions
            (AreaDist $rect $areaDist)))
    (STV 1.0 1.0))

(: $prf (AreaDist rectA $areaDist) $tv)
```
