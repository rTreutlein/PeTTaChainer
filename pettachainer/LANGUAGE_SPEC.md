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

`Member` can also appear in explicit rule premises and conclusions:

```metta
!(compileadd kb
    (: seedHuman
       (Implication
          (Premises (Member $x Seed))
          (Conclusions (Member $x Human)))
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

Set a known closed-world population size when one is available:

```metta
!(set-universe-size kb 100.0)
```

The universe size affects the confidence assigned to observed population
coverage. Without it, the member estimator uses its count-based confidence.
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
(FoldAllValue pattern init fold-fn -> out)
```

Typical distribution fold:

```metta
(FoldAllValue (In $room $kid)
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
    (CountryHeightDist countryA (ParticleFromPairs ((170 0.5) (180 0.5))))
    (STV 1.0 1.0)))

!(compileadd kb (: countryHeightB
    (CountryHeightDist countryB (ParticleFromPairs ((175 1.0))))
    (STV 1.0 1.0)))

!(compileadd kb (: compareHeightsRule
    (Implication
        (Premises
            (CountryHeightDist countryA $distA)
            (CountryHeightDist countryB $distB)
            (GreaterThan $distA $distB))
        (Conclusions
            (Taller countryA countryB)))
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
        (Premises
            (Group g1)
            (AverageDist (HeightDist g1 $person $heightDist) $heightDist -> $avgDist))
        (Conclusions
            (AvgHeightDist g1 $avgDist)))
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
    (STV 1.0 1.0)))

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))

!(query 120 kb (: $prf (AreaDist rectA $areaDist) $tv))
```

## Notes

- `NatDist`/`FloatDist` remain available for exact small cases.
- `ParticleDist` is preferred for scalability.
- Rule/application truth functions still use STV semantics for implication chaining.
