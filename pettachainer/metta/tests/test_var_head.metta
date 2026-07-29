!(import! &self ../petta_chainer)

!(compileadd kb (: sum_rel (Implication (Premises (Symmetric $r) ($r $x $y)) (Conclusions ($r $y $x))) (STV 0.9 0.9)))
!(compileadd kb (: tag (Symmetric Friend) (STV 0.9 0.9)))
!(compileadd kb (: f1 (Friend bob alice) (STV 0.9 0.9)))

!(test
   (query 100 kb (: $prf (Friend alice bob) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.7290000000000001 0.9092749078344904)))

!(test
   (query 100 kb (: $prf (Friend alice $x) $tv))
   (: (sum_rel (conjunction tag f1)) (Friend alice bob) (STV 0.7290000000000001 0.9092749078344904)))
