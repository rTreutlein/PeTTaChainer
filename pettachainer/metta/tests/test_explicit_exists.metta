!(import! &self ../petta_chainer)

;; Explicit existential scope retains the existing evidence-disjunction
;; semantics without relying on the variable being absent from Conclusions.
!(compileadd explicitExistsKb (: pa (P a) (STV 0.8 0.5)))
!(compileadd explicitExistsKb (: pb (P b) (STV 0.6 0.7)))

!(compileadd explicitExistsKb
   (: pExistsToT
      (Implication
         (Premises
            (Exists ($x) (P $x)))
         (Conclusions (T)))
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
         (Premises
            (Exists ($child)
               (And
                  (Parent $person $child)
                  (Doctor $child))))
         (Conclusions (HasDoctorChild $person)))
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

;; Existential conclusions require constructive witness semantics and are
;; deliberately rejected instead of being stored as an ordinary predicate.
!(test
   (collapse
      (compileadd explicitExistsConclusionKb
         (: unsupported
            (Implication
               (Premises (Seed $x))
               (Conclusions
                  (Exists ($y) (GeneratedBy $x $y))))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

!(test
   (query 10 explicitExistsKb
      (: $prf (Exists ($x) (P $x)) $tv))
   ())

!(test
   (collapse
      (compileadd nestedExplicitExistsKb
         (: unsupportedNested
            (Implication
               (Premises
                  (And
                     (Seed $x)
                     (Exists ($y) (GeneratedBy $x $y))))
               (Conclusions (Generated $x)))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

!(test
   (collapse
      (compileadd bidirectionalExplicitExistsKb
         (: unsupportedBidirectional
            (BiImplication
               (Premises
                  (Exists ($x) (P $x)))
               (Conclusions (T)))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())

!(test
   (collapse
      (compileadd escapingExplicitExistsKb
         (: unsupportedEscape
            (Implication
               (Premises
                  (Exists ($x) (P $x))
                  (R $x))
               (Conclusions (T)))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ())
