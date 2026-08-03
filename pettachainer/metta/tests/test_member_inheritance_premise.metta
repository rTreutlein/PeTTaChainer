!(import! &self ../petta_chainer)

!(set-universe-size memberInheritanceRootKb 1.0)
!(compileadd memberInheritanceRootKb
   (: tomHuman (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberInheritanceRootKb
   (: tomMortal (Member Tom Mortal) (STV 0.8 1.0)))

;; The empirical member fold can answer the public root query.
!(test
   (> (length
      (query 60 memberInheritanceRootKb
         (: $prf (Inheritance Human Mortal) $tv))) 0)
   true)

!(set-universe-size memberInheritancePremiseKb 1.0)
!(compileadd memberInheritancePremiseKb
   (: premiseTomHuman (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberInheritancePremiseKb
   (: premiseTomMortal (Member Tom Mortal) (STV 0.8 1.0)))
!(compileadd memberInheritancePremiseKb
   (: inheritanceToGoal
      (Implication
         (Inheritance Human Mortal)
         (Member Goal Supported))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; The identical Inheritance goal must also be available as a stored rule
;; premise, not only when compileQuery sees it at the root.
!(test
   (query 100 memberInheritancePremiseKb
      (: $prf (Member Goal Supported) $tv))
   (: (by inheritanceToGoal
         (member-inheritance-fold
            (foldall-proof
               (member-inheritance-sample
                  premiseTomHuman premiseTomMortal))))
      (Member Goal Supported)
      (STV 0.8 0.9999000095740854)))

;; Making the same fold available below a stored rule must not admit a
;; self-supporting member sample.
!(set-universe-size memberInheritancePremiseCycleKb 1.0)
!(compileadd memberInheritancePremiseCycleKb
   (: cycleTomHuman (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberInheritancePremiseCycleKb
   (: cyclicHumanMortal
      (Implication
         (And
            (Member $x Human)
            (Inheritance Human Mortal))
         (Member $x Mortal))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd memberInheritancePremiseCycleKb
   (: cyclicInheritanceToGoal
      (Implication
         (Inheritance Human Mortal)
         (Member CyclicGoal Supported))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 150 memberInheritancePremiseCycleKb
      (: $prf (Member CyclicGoal Supported) $tv))
   ())
