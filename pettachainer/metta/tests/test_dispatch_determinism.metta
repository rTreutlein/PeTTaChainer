!(import! &self petta_chainer)

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
!(test (collapse (materializable-proof-output? ((A) (kb MAIN Nil) proof tv))) (true))
!(test (collapse (materializable-proof-output? other-output)) (false))
!(test (collapse (base-rate-finish? weighted-base-rate)) (true))
!(test (collapse (base-rate-finish? other-finish)) (false))

!(test (collapse (specialization-statement-name (: named (A) (STV 1.0 1.0)))) (named))
!(test (collapse (specialization-statement-name other)) (no-specialization-name))
!(test
   (collapse (specialization-job-name (compile-specialization (: named (A) (STV 1.0 1.0)))))
   (named))
!(test (collapse (specialization-job-name other)) (no-specialization-name))

!(test (collapse (proof-term-children-mode proof-walk-in-kb (conjunction a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (derived a b))) ((a b)))
!(test (collapse (proof-term-children-mode proof-walk-in-kb (STV 1.0 1.0))) (()))
!(test (collapse (proof-term-children-mode shallow (derived a b))) (()))

!(test (collapse (record-compiled-inheritance-subject! unrelated)) (()))
!(test (collapse (record-compiled-inheritance-concepts! unrelated)) (()))
!(test
   (let*
      (($_ (collapse
              (record-compiled-inheritance-subject!
                 (: (dispatchKb MAIN Nil) proof (Inheritance subject concept) tv))))
       ($rows (collapse (match &inheritance_subject (dispatchKb subject) true))))
      (length $rows))
   1)
!(test
   (let*
      (($_ (collapse
              (record-compiled-inheritance-concepts!
                 (: (dispatchKb MAIN Nil) proof (Inheritance subject concept) tv))))
       ($rows (collapse (match &concept_node (dispatchKb concept) true))))
      (length $rows))
   1)

!(test (collapse (frontier-waiter-step (frontier-waiter g b s e p r) (old)))
   (((frontier-waiter g b s e p r) old)))
!(test (collapse (frontier-waiter-step unrelated (old))) ((old)))
!(test (collapse (aggregate-waiter-step (aggregate-waiter g) (old))) ((g old)))
!(test (collapse (aggregate-waiter-step unrelated (old))) ((old)))
!(test (collapse (query-temp-rule-premise (Compute f args result))) ((Compute f args -> result)))
!(test (collapse (query-temp-rule-premise premise)) (premise))
