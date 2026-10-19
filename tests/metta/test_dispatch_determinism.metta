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
!(test (collapse (BaseRateWithPriorFormula no-evidence no-evidence)) (no-evidence))
!(test (collapse (BaseRateWithPriorFormula no-evidence (STV 0.8 0.6))) ((STV 0.8 0.6)))
!(test (collapse (BaseRateWithPriorFormula (STV 0.2 0.4) no-evidence)) ((STV 0.2 0.4)))
!(test
   (collapse (BaseRateWithPriorFormula (STV 0.2 0.4) (STV 0.8 0.6)))
   ((mergetvs (STV 0.2 0.4) (STV 0.8 0.6))))

!(test (collapse (term-confidence (Goal (kb MAIN Nil) (marginal-proj 0 proof) (STV 1.0 0.5)))) (0.495))
!(test (collapse (term-confidence (Goal (kb MAIN Nil) proof (STV 1.0 0.5)))) (0.5))
!(test (collapse (base-rate-finish? weighted-base-rate)) (true))
!(test (collapse (base-rate-finish? other-finish)) (false))

!(test (collapse (proof-term-children-mode proof-walk-in-kb (conjunction a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (derived a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (STV 1.0 1.0))) (()))
!(test (collapse (proof-term-children-mode shallow (derived a b))) (()))

!(test (collapse (record-compiled-inheritance! unrelated)) (()))
!(test
   (let*
      (($_ (collapse
              (record-compiled-inheritance!
                 (: (dispatchKb MAIN Nil) proof (Inheritance subject concept) tv))))
       ($subjects (collapse (match &inheritance_subject (dispatchKb subject) true)))
       ($concepts (collapse (match &concept_node (dispatchKb concept) true))))
      ((length $subjects) (length $concepts)))
   (1 1))

!(test (collapse (query-temp-rule-premise (Compute f args result))) ((Compute f args -> result)))
!(test (collapse (query-temp-rule-premise premise)) (premise))
