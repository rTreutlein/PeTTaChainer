!(import! &self ../petta_chainer)

!(compileadd kb (: sum_rel (Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x)) (STV 0.9 0.9)))
!(compileadd kb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd kb (: f1 (Friend bob alice) (STV 0.9 0.9)))

!(test
   (query 100 kb (: $prf (Friend alice bob) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.7290000000000001 0.9092749078344904)))

!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (by sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.7290000000000001 0.9092749078344904)))

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
