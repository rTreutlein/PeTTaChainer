!(import! &self petta_chainer)

!(compileadd plnLogicKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 plnLogicKb (: $prf (Or (A) (B)) $tv))
   ())

!(compileadd plnProjectionNeedsEvidenceKb (: ab (And (A) (B)) (STV 1.0 0.9)))

!(test
   (query 20 plnProjectionNeedsEvidenceKb (: $prf (B) $tv))
   ())

!(compileadd plnProjectionKb (: ab (And (A) (B)) (STV 1.0 0.9)))
!(compileadd plnProjectionKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 plnProjectionKb (: $prf (B) $tv))
   (: ((proj 1 ab) a) (B) (STV 1.0 0.9)))

!(compileadd plnOrProjectionKb (: ab (Or (A) (B)) (STV 1.0 0.9)))
!(compileadd plnOrProjectionKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 plnOrProjectionKb (: $prf (B) $tv))
   (: ((proj 1 ab) a) (B) (STV 0.0 0.0)))

!(import! &self logic_configs/predicate_logic)

!(compileadd predicateLogicKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 predicateLogicKb (: $prf (Or (A) (B)) $tv))
   (: (Orintroduction a) (Or (A) (B)) (STV 1.0 1.0)))

!(import! &self logic_configs/pln)

!(compileadd plnAfterSwitchKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 plnAfterSwitchKb (: $prf (Or (A) (B)) $tv))
   ())

!(clear-logic-config)
!(set-logic-name CustomLogic)
!(set-compound-connective Either Any NoProjection)

!(compileadd customEitherKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 customEitherKb (: $prf (Either (A) (B)) $tv))
   (: (Eitherintroduction a) (Either (A) (B)) (STV 1.0 1.0)))

!(clear-logic-config)
!(set-logic-name NoOrLogic)
!(set-compound-connective And All ProjectAll)

!(compileadd noOrKb (: a (A) (STV 1.0 1.0)))

!(test
   (query 20 noOrKb (: $prf (Or (A) (B)) $tv))
   ())

!(import! &self logic_configs/pln)
