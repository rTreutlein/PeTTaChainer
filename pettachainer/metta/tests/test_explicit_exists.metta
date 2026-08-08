!(import! &self ../petta_chainer)

;; Explicit existential scope retains the existing evidence-disjunction
;; semantics without relying on the variable being absent from a consequent.
!(compileadd explicitExistsKb (: pa (P a) (STV 0.8 0.5)))
!(compileadd explicitExistsKb (: pb (P b) (STV 0.6 0.7)))

!(compileadd explicitExistsKb
   (: pExistsToT
      (Implication
         (Exists ($x) (P $x))
         (T))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 explicitExistsKb (: $prf (T) $tv))
   (: (by pExistsToT (disjunction pa pb))
      (T)
      (STV 0.9199999999999999 0.7123799943249737)))

;; The binder scopes over the complete And body.  A Parent and Doctor proof
;; must therefore agree on one child; evidence about different children does
;; not satisfy the existential.
!(compileadd explicitExistsJoinKb
   (: aliceBob (Parent alice bob) (STV 1.0 1.0)))
!(compileadd explicitExistsJoinKb
   (: bobDoctor (Doctor bob) (STV 1.0 1.0)))
!(compileadd explicitExistsJoinKb
   (: eveCarol (Parent eve carol) (STV 1.0 1.0)))
!(compileadd explicitExistsJoinKb
   (: danDoctor (Doctor dan) (STV 1.0 1.0)))

!(compileadd explicitExistsJoinKb
   (: doctorChild
      (Implication
         (Exists ($child)
               (And
                  (Parent $person $child)
                  (Doctor $child)))
         (HasDoctorChild $person))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 explicitExistsJoinKb
      (: $prf (HasDoctorChild alice) $tv))
   (: (by doctorChild
          (disjunction
             (conjunction aliceBob bobDoctor)))
      (HasDoctorChild alice)
      (STV 1.0 0.999700089898053)))

!(test
   (query 100 explicitExistsJoinKb
      (: $prf (HasDoctorChild eve) $tv))
   ())

;; An explicit existential conclusion becomes a proposition-level claim. Its
;; bound position is canonical, not a concrete Skolem object.
!(compileadd explicitExistsConclusionKb
   (: aliceSeed (Seed alice) (STV 1.0 1.0)))

!(compileadd explicitExistsConclusionKb
   (: generateExplicit
      (Implication
         (Seed $x)
         (Exists ($y) (GeneratedBy $x $y)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 20 explicitExistsConclusionKb
      (: $prf
         (ExistentialClaim
            (GeneratedBy alice (exists-slot 0)))
         $tv))
   (: (by generateExplicit aliceSeed)
      (ExistentialClaim
         (GeneratedBy alice (exists-slot 0)))
      (STV 1.0 0.9998000399670116)))

;; The claim does not assert that one syntactically new object is the witness.
!(test
   (query 20 explicitExistsConclusionKb
      (: $prf (GeneratedBy alice $witness) $tv))
   ())

;; A downstream Exists premise consumes the proposition-level claim even when
;; no concrete GeneratedBy witness is known. The separately compiled witness
;; fold remains available as an alternative proof path when components exist.
!(compileadd explicitExistsConclusionKb
   (: consumeGenerated
      (Implication
         (Exists ($y) (GeneratedBy alice $y))
         (HasGenerated alice))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (not
      (==
         (collapse
            (query 40 explicitExistsConclusionKb
               (: $proof (HasGenerated alice) $tv)))
         ()))
   true)

;; A variable consumed by existential antecedent aggregation cannot leak into
;; the dependency list of a generated consequent witness.
!(compileadd aggregatedWitnessKb
   (: observedP (P alpha) (STV 1.0 1.0)))

!(compileadd aggregatedWitnessKb
   (: aggregatedGenerate
      (Implication
         (Exists ($x) (P $x))
         (Exists ($y) (Generated $y)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 20 aggregatedWitnessKb
      (: $proof
         (ExistentialClaim (Generated (exists-slot 0)))
         $tv))
   (: (by aggregatedGenerate (disjunction observedP))
      (ExistentialClaim (Generated (exists-slot 0)))
      (STV 1.0 0.999800029971008)))

;; The same conclusion-only treatment applies to the implicit implication
;; syntax, independently of whether an Exists wrapper was written.
!(compileadd implicitExistsConclusionKb
   (: bobSeed (Seed bob) (STV 1.0 1.0)))

!(compileadd implicitExistsConclusionKb
   (: generateImplicit
      (Implication
         (Seed $x)
         (GeneratedBy $x $y))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 20 implicitExistsConclusionKb
      (: $prf (GeneratedBy bob $witness) $tv))
   (: (by generateImplicit bobSeed)
      (GeneratedBy bob
         (exists generateImplicit 0 (bob)))
      (STV 1.0 0.9998000399670116)))

;; Ordinary premise variables remain universally quantified. With disjoint
;; variables, inversion therefore consumes B($b) and introduces a stable
;; conclusion witness for $a instead of treating A($a) as an aggregate.
!(compileadd disjointInverseKb
   (: a_b
      (Implication
         (A $a)
         (B $b))
      (STV 1.0 1.0)))

!(compileadd disjointInverseKb
   (: observedB (B beta) (STV 1.0 1.0)))

;; STV inversion needs priors for both sides. Explicit estimates keep this
;; regression focused on quantifier lowering rather than recursive estimation.
!(set-base-rate disjointInverseKb (A $x) (STV 0.5 0.5))
!(set-base-rate disjointInverseKb (B $x) (STV 0.5 0.5))

!(test
   (query 20 disjointInverseKb
      (: $proof (A (exists a_b 0 (beta))) $tv))
   (: ((inverted a_b with cpu cpu) observedB)
      (A (exists a_b 0 (beta)))
      (STV 1.0 1.0e-06)))

!(test
   (query 10 explicitExistsKb
      (: $prf (Exists ($x) (P $x)) $tv))
   ())

!(test
   (collapse
      (compileadd nestedExplicitExistsKb
         (: unsupportedNested
            (Implication
               (And
                     (Seed $x)
                     (Exists ($y) (GeneratedBy $x $y)))
               (Generated $x))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

!(test
   (collapse
      (compileadd bidirectionalExplicitExistsKb
         (: unsupportedBidirectional
            (BiImplication
               (Exists ($x) (P $x))
               (T))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

!(test
   (collapse
      (compileadd escapingExplicitExistsKb
         (: unsupportedEscape
            (Implication
               (Exists ($x) (P $x))
               (R $x))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

;; Implication has exactly two expression arguments.
!(test
   (collapse
      (compileadd malformedImplicationKb
         (: malformedArity
            (Implication (A) (B) (C))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

;; A direct existential claim and the disjunction of known witnesses retain
;; separate estimates. Their difference is exposed as an explicit residual.
!(compileadd existentialResidualKb
   (: fidoDog (Dog fido) (STV 1.0 1.0)))
!(compileadd existentialResidualKb
   (: dogChasesCat
      (Implication
         (Dog $dog)
         (Exists ($cat)
            (And (Cat $cat) (Chases $dog $cat))))
      (CTV (STV 0.95 0.9) (STV 0.0 1.0))))

!(compileadd existentialResidualKb
   (: miloCat (Cat milo) (STV 1.0 0.99)))
!(compileadd existentialResidualKb
   (: fidoRarelyChasesMilo
      (Chases fido milo) (STV 0.02 0.9)))
!(compileadd existentialResidualKb
   (: lunaCat (Cat luna) (STV 1.0 0.99)))
!(compileadd existentialResidualKb
   (: fidoRarelyChasesLuna
      (Chases fido luna) (STV 0.03 0.9)))

!(compileadd existentialResidualKb
   (: exposeKnownWitnesses
      (Implication
         (KnownExistential ($cat)
            (And (Cat $cat) (Chases fido $cat)))
         (KnownWitnessDisjunction fido))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd existentialResidualKb
   (: exposeOtherWitness
      (Implication
         (ExistentialResidual ($cat)
            (And (Cat $cat) (Chases fido $cat)))
         (OtherWitnessEstimate fido))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 200 existentialResidualKb
      (: $proof
         (ExistentialClaim
            (And
               (Cat (exists-slot 0))
               (Chases fido (exists-slot 0))))
         $tv))
   (: (by dogChasesCat fidoDog)
      (ExistentialClaim
         (And
            (Cat (exists-slot 0))
            (Chases fido (exists-slot 0))))
      (STV 0.95 0.899999998460563)))

!(test
   (query 300 existentialResidualKb
      (: $proof (KnownWitnessDisjunction fido) $tv))
   (: (by exposeKnownWitnesses
          (disjunction
             (conjunction miloCat fidoRarelyChasesMilo)
             (conjunction lunaCat fidoRarelyChasesLuna)))
      (KnownWitnessDisjunction fido)
      (STV 0.0494 0.9010944415002473)))

!(test
   (query 300 existentialResidualKb
      (: $proof (OtherWitnessEstimate fido) $tv))
   (: (by exposeOtherWitness
          (conjunction
             (by dogChasesCat fidoDog)
             (disjunction
                (conjunction miloCat fidoRarelyChasesMilo)
                (conjunction lunaCat fidoRarelyChasesLuna))))
      (OtherWitnessEstimate fido)
      (STV 0.9474016410687987 0.8948358186906257)))

;; Adding a stronger known witness leaves the direct existential proof intact,
;; increases D, and refines the residual estimate downward.
!(compileadd existentialResidualKb
   (: felixCat (Cat felix) (STV 1.0 0.99)))
!(compileadd existentialResidualKb
   (: fidoOftenChasesFelix
      (Chases fido felix) (STV 0.6 0.9)))

!(test
   (query 300 existentialResidualKb
      (: $proof (KnownWitnessDisjunction fido) $tv))
   (: (by exposeKnownWitnesses
          (disjunction
             (conjunction miloCat fidoRarelyChasesMilo)
             (conjunction lunaCat fidoRarelyChasesLuna)
             (conjunction felixCat fidoOftenChasesFelix)))
      (KnownWitnessDisjunction fido)
      (STV 0.61976 0.9043600864574071)))

!(test
   (query 300 existentialResidualKb
      (: $proof (OtherWitnessEstimate fido) $tv))
   (: (by exposeOtherWitness
          (conjunction
             (by dogChasesCat fidoDog)
             (disjunction
                (conjunction miloCat fidoRarelyChasesMilo)
                (conjunction lunaCat fidoRarelyChasesLuna)
                (conjunction felixCat fidoOftenChasesFelix))))
      (OtherWitnessEstimate fido)
      (STV 0.8685041026719965 0.7430346472921185)))
