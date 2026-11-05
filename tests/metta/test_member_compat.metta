!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd memberCompatKb (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd memberCompatKb (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(test
   (collapse (query 20 memberCompatKb (: $prf (Member Tom Human) $tv)))
   ((: tomHuman
       (Member Tom Human)
       (STV 0.99 0.9))))

;; The link is the rule (Human $x) -> (Mortal $x): its negative branch comes
;; from the base rates, not from a certain "not Human, so not Mortal".
!(test
   (collapse (query 40 memberCompatKb (: $prf (Member Tom Mortal) $tv)))
   ((: (by humanMortal tomHuman)
       (Member Tom Mortal)
       (STV 0.797 0.8694959758070814))))

!(compileadd memberDirectKb (: tomHumanDirect (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberDirectKb (: tomMortalDirect (Member Tom Mortal) (STV 0.8 1.0)))

;; A concrete Inheritance query is the implication query of its link, which the
;; link's instance fold over the members answers.
!(test
   (query 40 memberDirectKb (: $prf (Inheritance Human Mortal) $tv))
   (: (implication-instance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.8 0.0012484394506866417)))

;; The instance fold reads both sides through the normal backward chainer.
;; Neither membership below is materialized: Human and Mortal are derived from
;; Seed. The fold must count the derived sample rather than reading only facts
;; already present in &kb; the rules also give the link by deduction: a human
;; is a seed, so mortal at .8.
!(compileadd memberDerivedKb (: tomSeed (Member Tom Seed) (STV 1.0 1.0)))
!(compileadd memberDerivedKb
   (: seedHuman
      (Implication
         (Member $x Seed)
         (Member $x Human))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd memberDerivedKb
   (: seedMortal
      (Implication
         (Member $x Seed)
         (Member $x Mortal))
      (CTV (STV 0.8 1.0) (STV 0.0 1.0))))

!(test
   (query 100 memberDerivedKb (: $prf (Inheritance Human Mortal) $tv))
   (: (conditional-implication (by seedMortal ((inverted seedHuman with cpu (prior (STV 0.9166666666666667 0.0012484394506866417))) (ctx proof 1)))) (Inheritance Human Mortal) (STV 0.8 0.9999)))

;; A written rule between the two classes is the link itself, revised with
;; the instances.
!(compileadd memberRuleKb
   (: humanMortalRule (Implication (Member $x Human) (Member $x Mortal)) (STV 0.8 0.9)))
!(test
   (query 100 memberRuleKb (: $prf (Inheritance Human Mortal) $tv))
   (: humanMortalRule (Inheritance Human Mortal) (STV 0.8 0.9)))

;; A consequent that requires the very Inheritance being estimated is
;; self-supporting. The normal proof dependency checks must reject it before it
;; reaches the fold.
!(compileadd memberCycleKb (: tomHumanCycle (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberCycleKb
   (: cyclicHumanMortal
      (Implication
         (And
            (Member $x Human)
            (Inheritance Human Mortal))
         (Member $x Mortal))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 memberCycleKb (: $prf (Inheritance Human Mortal) $tv))
   ())
