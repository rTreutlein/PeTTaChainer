!(import! &self ../../pettachainer/metta/petta_chainer)

;; Fixed-input dispatch helpers must each reduce to exactly one result.
!(test (collapse (BaseRateWithPriorFormula no-evidence no-evidence)) (no-evidence))
!(test (collapse (BaseRateWithPriorFormula no-evidence (STV 0.8 0.6))) ((STV 0.8 0.6)))
!(test (collapse (BaseRateWithPriorFormula (STV 0.2 0.4) no-evidence)) ((STV 0.2 0.4)))
!(test
   (collapse (BaseRateWithPriorFormula (STV 0.2 0.4) (STV 0.8 0.6)))
   ((mergetvs (STV 0.2 0.4) (STV 0.8 0.6))))

!(test (collapse (proof-score (marginal-proj 0 proof) (STV 1.0 0.5))) (0.495))
!(test (collapse (proof-score proof (STV 1.0 0.5))) (0.5))
!(test (collapse (materializable-proof-kind? (rule sample))) (true))
!(test (collapse (materializable-proof-kind? fact)) (false))
!(test
   (collapse
      (materializable-proof-output?
         ((A) (kb MAIN Nil) proof (STV 0.8 0.6))))
   (true))
!(test
   (collapse (materializable-proof-output? ((A) (kb MAIN Nil) proof no-tv)))
   (false))
!(test
   (collapse
      (materializable-proof-output?
         ((A) (kb MAIN Nil) proof (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   (false))
!(test (collapse (materializable-proof-output? other-output)) (false))
;; Goal classification must preserve open CPU outputs and nested fact variables.
!(test (collapse (goal-has-type-vars? (CPU + (1 2) 3))) (false))
!(test (collapse (goal-has-type-vars? (CPU + (1 2) $result))) (true))
!(test (collapse (goal-has-type-vars? (CPU + (1 $value) 3))) (true))
!(test
   (collapse
      (goal-has-type-vars?
         ((Nested $x $x) (kb MAIN Nil) proof (STV 1.0 1.0))))
   (true))
!(test
   (collapse
      (goal-has-type-vars?
         ((Nested a a) (kb MAIN Nil) proof (STV 1.0 1.0))))
   (false))
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
