!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd kb (: sum_rel (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))
!(compileadd kb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd kb (: f1 (Friend bob alice) (STV 0.9 0.9)))

;; The STV rule states P(Friend(y,x) | Symmetric(Friend) and Friend(x,y)).
;; Its open predicate population stays generic instead of being bound to
;; a reserved head while computing base rates; its positive conditional is 0.9.
;; Its negative branch reads the antecedent's prior: the joint fold over the
;; conjunction has no evidence on a cold query, so the prior composes from the
;; parts' rates (#142), and the cold query already gives the value the
;; population estimate converges to. Ground and open queries agree, cold and
;; warm.
!(test
   (query 100 kb (: $prf (Friend alice bob) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

!(compileadd openFirstKb (: sum_rel (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))
!(compileadd openFirstKb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd openFirstKb (: f1 (Friend bob alice) (STV 0.9 0.9)))

!(test
   (query 100 openFirstKb (: $prf (Friend alice $x) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

!(test
   (query 100 openFirstKb (: $prf (Friend alice bob) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.8642193246799066 0.02243916988834716)))

;; A variable-headed singleton antecedent is not mistaken for an `And` merely
;; because its head can unify with that symbol.
!(compileadd directVariableHeadKb
   (: genericUnary
      (Implication ($relation $x) (Observed $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd directVariableHeadKb
   (: dogAlice (Dog alice) (STV 1.0 1.0)))

!(test
   (query 20 directVariableHeadKb (: $proof (Observed alice) $tv))
   (: (by genericUnary dogAlice)
      (Observed alice)
      (STV 1.0 0.9998000399670116)))
