!(import! &self petta_chainer)

!(compileadd materializeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd materializeKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd materializeKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 4 materializeKb (: $p (Goal) $tv))
   (: (r2 (r1 a0)) (Goal) (STV 1.0 1.0)))

!(test
   (collapse (match &kb ((B) (materializeKb MAIN Nil) $_prf $_tv) true))
   ())

!(test
   (collapse (match &kb ((Goal) (materializeKb MAIN Nil) $_prf $_tv) true))
   ())

!(test
   (query-materialize 4 materializeKb (: $p (Goal) $tv))
   (: (r2 (r1 a0)) (Goal) (STV 1.0 1.0)))

!(test
   (not (== (collapse (match &kb ((B) (materializeKb MAIN Nil) $_prf $_tv) true)) ()))
   true)

!(test
   (not (== (collapse (match &kb ((Goal) (materializeKb MAIN Nil) $_prf $_tv) true)) ()))
   true)

!(test
   (query 1 materializeKb (: $p (B) $tv))
   (: (r1 a0) (B) (STV 1.0 1.0)))

!(test
   (query 1 materializeKb (: $p (Goal) $tv))
   (: (r2 (r1 a0)) (Goal) (STV 1.0 1.0)))
