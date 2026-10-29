!(import! &self ../../pettachainer/metta/petta_chainer)

;; The public compiler plans keep their distinct wire formats and variable
;; sharing, even though statement compilation now encodes each addition once.
!(test
   (compileQuery compilerWireKb (: wire (Pair $x $x) (STV 1.0 1.0)))
   (compilation-plan
      (: (compilerWireKb MAIN Nil) wire (Pair $x $x) (STV 1.0 1.0)) ()))
!(test
   (mm2compileQuery compilerWireKb (: wire (Pair $x $y) (STV 1.0 1.0)))
   (compiled-query
      ((Pair $x $y) (compilerWireKb MAIN Nil) wire (STV 1.0 1.0)) ()))
!(test
   (compileadd compilerWireKb
      (: opaque (Payload (: a b c d) (data (x y z) p value)) (STV 1.0 1.0)))
   (: (compilerWireKb MAIN Nil) opaque
      (Payload (: a b c d) (data (x y z) p value)) (STV 1.0 1.0)))

;; Fixed-input dispatch helpers must each reduce to exactly one result.
!(test (collapse (term-confidence (Goal (kb MAIN Nil) proof (STV 1.0 0.5)))) (0.5))
!(test (collapse (base-rate-finish? base-rate)) (true))
!(test (collapse (base-rate-finish? other-finish)) (false))

!(test (collapse (proof-term-children-mode proof-walk-in-kb (conjunction a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (derived a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (STV 1.0 1.0))) (()))
!(test (collapse (proof-term-children-mode shallow (derived a b))) (()))


