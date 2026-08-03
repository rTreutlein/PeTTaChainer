!(import! &self ../petta_chainer)

!(compileadd memberCompatKb (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd memberCompatKb (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(test
   (collapse (query 20 memberCompatKb (: $prf (Member Tom Human) $tv)))
   ((: tomHuman
       (Member Tom Human)
       (STV 0.99 0.9))))

!(test
   (collapse (query 40 memberCompatKb (: $prf (Member Tom Mortal) $tv)))
   ((: ((no_inverse (member-inheritance-implication humanMortal)) tomHuman)
       (Member Tom Mortal)
       (STV 0.792 0.9008662163590345))))

!(set-universe-size memberClosedKb 1.0)

!(compileadd memberClosedKb (: tomHumanClosed (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberClosedKb (: tomMortalClosed (Member Tom Mortal) (STV 0.8 1.0)))

;; The concrete Inheritance query installs a Member-based producer on the same
;; public relation, so its proof identifies the producer without an adapter.
!(test
   (query 40 memberClosedKb (: $prf (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold
          (foldall-proof
             (member-inheritance-sample tomHumanClosed tomMortalClosed)))
      (Inheritance Human Mortal)
      (STV 0.8 1.0)))

;; The member producer queries both sides through the normal backward chainer.
;; Neither membership below is materialized: Human is derived from Seed, and
;; Mortal is then derived from Human. The fold must retain both derivations in
;; its proof rather than reading only facts already present in &kb.
!(set-universe-size memberDerivedKb 1.0)
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
   (: (member-inheritance-fold
          (foldall-proof
             (member-inheritance-sample
                (seedHuman tomSeed)
                (humanMortal (seedHuman tomSeed)))))
      (Inheritance Human Mortal)
      (STV 0.8 0.9997000691603363)))

;; A consequent that requires the very Inheritance being estimated is
;; self-supporting. The normal proof dependency checks must reject it before it
;; reaches the fold.
!(set-universe-size memberCycleKb 1.0)
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
