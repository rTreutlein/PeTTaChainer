!(import! &self ../petta_chainer)

;; A dog establishes a strong claim that some cat is chased. The existential
;; conclusion is retained as a proposition; it does not create a new cat.
!(compileadd existentialExampleKb
   (: fidoDog (Dog fido) (STV 1.0 1.0)))

!(compileadd existentialExampleKb
   (: dogChasesCat
      (Implication
         (Dog $dog)
         (Exists ($cat)
            (And
               (Cat $cat)
               (Chases $dog $cat))))
      (CTV (STV 0.95 0.9) (STV 0.0 1.0))))

;; The two cats currently known to the KB are confidently poor explanations.
!(compileadd existentialExampleKb
   (: miloCat (Cat milo) (STV 1.0 0.99)))
!(compileadd existentialExampleKb
   (: fidoRarelyChasesMilo
      (Chases fido milo) (STV 0.02 0.9)))
!(compileadd existentialExampleKb
   (: lunaCat (Cat luna) (STV 1.0 0.99)))
!(compileadd existentialExampleKb
   (: fidoRarelyChasesLuna
      (Chases fido luna) (STV 0.03 0.9)))

;; KnownExistential exposes only the disjunction of enumerated witnesses.
!(compileadd existentialExampleKb
   (: exposeKnownWitnesses
      (Implication
         (KnownExistential ($cat)
            (And
               (Cat $cat)
               (Chases fido $cat)))
         (KnownWitnessDisjunction fido))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; ExistentialResidual compares that disjunction with the direct existential
;; and exposes the remaining support as an "other witness" proposition.
!(compileadd existentialExampleKb
   (: exposeOtherWitness
      (Implication
         (ExistentialResidual ($cat)
            (And
               (Cat $cat)
               (Chases fido $cat)))
         (OtherWitnessEstimate fido))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Direct existential claim E.
!(query 200 existentialExampleKb
   (: $proof
      (ExistentialClaim
         (And
            (Cat (exists-slot 0))
            (Chases fido (exists-slot 0))))
      $tv))

;; Enumerated disjunction D and residual U, with E = D or U.
!(query 300 existentialExampleKb
   (: $proof (KnownWitnessDisjunction fido) $tv))
!(query 300 existentialExampleKb
   (: $proof (OtherWitnessEstimate fido) $tv))

;; Knowledge addition refines the witness partition without retracting E or
;; either earlier residual proposition. Felix explains part of the previously
;; unenumerated mass, so D rises and the narrower residual falls.
!(compileadd existentialExampleKb
   (: felixCat (Cat felix) (STV 1.0 0.99)))
!(compileadd existentialExampleKb
   (: fidoOftenChasesFelix
      (Chases fido felix) (STV 0.6 0.9)))

!(query 300 existentialExampleKb
   (: $proof (KnownWitnessDisjunction fido) $tv))
!(query 300 existentialExampleKb
   (: $proof (OtherWitnessEstimate fido) $tv))
