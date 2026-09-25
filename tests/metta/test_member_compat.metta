!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd memberCompatKb (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd memberCompatKb (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(test
   (collapse (query 20 memberCompatKb (: $prf (Member Tom Human) $tv)))
   ((: tomHuman
       (Member Tom Human)
       (STV 0.99 0.9))))

!(test
   (collapse (query 40 memberCompatKb (: $prf (Member Tom Mortal) $tv)))
   ((: (by (no_inverse (member-inheritance-implication humanMortal)) tomHuman)
       (Member Tom Mortal)
       (STV 0.792 0.9008662163590345))))

!(compileadd memberDirectKb (: tomHumanDirect (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberDirectKb (: tomMortalDirect (Member Tom Mortal) (STV 0.8 1.0)))

;; The concrete Inheritance query installs a Member-based producer on the same
;; public relation, so its proof names the producer without an adapter.
!(test
   (query 40 memberDirectKb (: $prf (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.8 0.0012484394506866417)))

;; The member producer queries both sides through the normal backward chainer.
;; Neither membership below is materialized: Human is derived from Seed, and
;; Mortal is then derived from Human. The fold must count the derived sample
;; rather than reading only facts already present in &kb.
!(compileadd memberDerivedKb (: tomSeed (Member Tom Seed) (STV 1.0 1.0)))
!(compileadd memberDerivedKb
   (: seedHuman
      (Implication
         (Member $x Seed)
         (Member $x Human))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd memberDerivedKb
   (: humanMortal
      (Implication
         (Member $x Human)
         (Member $x Mortal))
      (CTV (STV 0.8 1.0) (STV 0.0 1.0))))

!(test
   (query 100 memberDerivedKb (: $prf (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance Human Mortal)
      (STV 0.8 0.0012480654725264188)))

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
