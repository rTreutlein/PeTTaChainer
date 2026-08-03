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
   (: (pExistsToT (disjunction pa pb))
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
   (: (doctorChild
          (disjunction
             (conjunction aliceBob bobDoctor)))
      (HasDoctorChild alice)
      (STV 1.0 0.999700089898053)))

!(test
   (query 100 explicitExistsJoinKb
      (: $prf (HasDoctorChild eve) $tv))
   ())

;; A conclusion-local variable becomes a stable witness depending on the
;; variables retained from the premise.
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
      (: $prf (GeneratedBy alice $witness) $tv))
   (: (generateExplicit aliceSeed)
      (GeneratedBy alice
         (exists generateExplicit 0 (alice)))
      (STV 1.0 0.9998000399670116)))

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
      (: $proof (Generated (exists aggregatedGenerate 0 ())) $tv))
   (: (aggregatedGenerate (disjunction observedP))
      (Generated (exists aggregatedGenerate 0 ()))
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
   (: (generateImplicit bobSeed)
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
