# PeTTaChainer Language Spec

This document describes how to write facts, rules, and queries in the PeTTaChainer MeTTa language used in this repository.

If you need an LLM-oriented helper-first spec, use `pettachainer/LLM_RULE_SPEC.md`.

## Core Model

- Knowledge is stored as proof atoms of the form:

```metta
(: proof-id type tv)
```

- In user code, facts/rules are usually inserted with:

```metta
!(compileadd kb (: proof-id type tv))
```

- Queries use:

```metta
!(query steps kb (: $prf type $tv))
```

`steps` is the search budget.

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
- keep membership/existence truth in separate STV facts if needed

## Fact Syntax

Example:

```metta
!(compileadd kb (: in11 (In room1 kid1) (STV 0.5 1.0)))
```

## Rule Syntax

Rules are implications with explicit premises and conclusions:

```metta
!(compileadd kb (: ruleName
    (Implication
        (Premises
            premise1
            premise2
            ...)
        (Conclusions
            conclusion1
            ...))
    (STV s c)))
```

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

### 3) FoldAll / FoldAllValue

Aggregate over matching facts:

```metta
(FoldAll pattern value init fold-fn -> out)
(FoldAllValue pattern value init fold-fn -> out)
```

Typical distribution fold:

```metta
(FoldAllValue (In $room $kid)
              $tvin
              (ParticleFromPairs ((0 1.0)))
              ParticleAddBernoulliFromSTV
              -> $dist)
```

### 4) Not

```metta
(Not expr)
```

### 5) GreaterThan / >

Two forms are supported:

- Distribution vs numeric threshold:

```metta
(GreaterThan (CntKidIn $room) 1)
```

Compiled to `DistGreaterThanFormula` over the distribution TV.

- Distribution vs distribution (compile sugar):

```metta
(GreaterThan (CountryHeightDist countryA)
             (CountryHeightDist countryB))
```

Compiled to `DistGreaterThanDistFormula`.

### 6) MapDist / Map2Dist / AverageDist

Distribution helper premises (TV-based, LLM-friendly):

```metta
(MapDist f (DistFactA ...) -> $outDist)
(Map2Dist f (DistFactA ...) (DistFactB ...) -> $outDist)
(AverageDist (DistFactPattern ...) -> $outDist)
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

## Particle Confidence Semantics

For particle-based threshold/comparison formulas, confidence is derived from effective sample size:

- `N_eff = 1 / sum(w_i^2)` after weight normalization
- `confidence = N_eff / (N_eff + 20)`

For dist-vs-dist comparisons, confidence is the minimum of both sides.

## Particle Store Utilities

- `(ParticleStoreCount)` -> number of stored `(particle id x w)` atoms
- `(ParticleStoreClear)` -> clears store and resets particle id counter
- `(ParticleStorePruneKB)` -> keeps only particle ids reachable from current `&kb` facts

## End-to-End Example

```metta
!(compileadd kb (: countryHeightA
    (CountryHeightDist countryA)
    (ParticleFromPairs ((170 0.5) (180 0.5)))))

!(compileadd kb (: countryHeightB
    (CountryHeightDist countryB)
    (ParticleFromPairs ((175 1.0)))))

!(compileadd kb (: compareHeightsRule
    (Implication
        (Premises
            (GreaterThan (CountryHeightDist countryA)
                         (CountryHeightDist countryB)))
        (Conclusions
            (Taller countryA countryB)))
    (STV 1.0 1.0)))

!(query 40 kb (: $prf (Taller countryA countryB) $tv))
```

## Example: Average Height Distribution in a Group

This example computes average height distributions via a rule and queries the derived fact.
Each person height is stored as a distribution TV.

```metta
!(compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))
!(compileadd kb (: hd11 (HeightDist g1 alice) (PointMass 160.0)))
!(compileadd kb (: hd12 (HeightDist g1 bob) (PointMass 170.0)))
!(compileadd kb (: hd13 (HeightDist g1 carol) (PointMass 180.0)))

!(compileadd kb (: avgHeightDistG1Rule
    (Implication
        (Premises
            (Group g1)
            (AverageDist (HeightDist g1 $person) -> $avgDist))
        (Conclusions
            (AvgHeightDist g1)))
    (STV 1.0 1.0)))

!(query 10 kb
    (: (avgHeightDistG1Rule (conjunction group1 cpu))
       (AvgHeightDist g1)
       $avgDist))
```

## Example: Rectangle Area Distribution

Area is the product of length and width distributions, derived through a rule.

```metta
!(compileadd kb (: lenA (LengthDist rectA) (ParticleFromNormal 10.0 1.0)))
!(compileadd kb (: widA (WidthDist rectA) (ParticleFromNormal 5.0 0.5)))

!(compileadd kb (: areaDistRule
    (Implication
        (Premises
            (Rectangle $rect)
            (Map2Dist * (LengthDist $rect) (WidthDist $rect) -> $areaDist))
        (Conclusions
            (AreaDist $rect)))
    (STV 1.0 1.0)))

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))

!(query 120 kb (: $prf (AreaDist rectA) $areaDist))
```

## Notes

- `NatDist`/`FloatDist` remain available for exact small cases.
- `ParticleDist` is preferred for scalability.
- Rule/application truth functions still use STV semantics for implication chaining.
