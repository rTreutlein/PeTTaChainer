!(import! &self ../../pettachainer/metta/petta_chainer)

;; #45: the source acceptance is observed, while A is assumed privately.
;; These cold/warm proofs retain both inputs through And projection.
!(compileadd wrappedGate45 (: accepted (AcceptSource S) (STV 1 1)))
!(compileadd wrappedGate45 (: rule
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 0.8 0.6)))
!(test (collapse (let
   (: (conditional-implication (marginal-proj 1
      (by (consequent-projection $source $child rule)
         (conjunction accepted (ctx proof $ctx))))) $type $tv)
   (query 300 wrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8 0.4897959182395719)))
!(test (collapse (let
   (: (conditional-implication (marginal-proj 1
      (by (consequent-projection $source $child rule)
         (conjunction accepted (ctx proof $ctx))))) $type $tv)
   (query 300 wrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8 0.4897959182395719)))

!(compileadd unwrappedGate45 (: accepted (AcceptSource S) (STV 1 1)))
!(compileadd unwrappedGate45 (: rule
   (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x))))
   (STV 0.8 0.6)))
!(test (collapse (let
   (: (conditional-implication (marginal-proj 1
      (by (by rule accepted) (ctx proof $ctx)))) $type $tv)
   (query 300 unwrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8 0.5454545452961622)))
!(test (collapse (let
   (: (conditional-implication (marginal-proj 1
      (by (by rule accepted) (ctx proof $ctx)))) $type $tv)
   (query 300 unwrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8 0.5454545452961622)))

;; Inspect the live private value: MAIN evidence/dependency identity survives
;; borrowing, and the assumed A is a dependency but no empirical evidence.
!(let* (((compiled-query $goal $adds)
           (mm2compileQuery wrappedGate45 (: $p (Implication (A $x) (C $x)) $tv)))
        ($_injected (collapse (once (inject-compiled-adds $adds))))
        ($_answers (chainer 300 (typed-runtime-premise $goal)))
        (($type $scope $_proof $_tv) $goal)
        ((sk-val $_fact $ev $deps)
           (sk-value (sk-key (brand Statement $type) (brand KBContext $scope)) sk-any-filter ()))
        ($valid (and
           (== $ev (evidence-set
              ((rule-ev wrappedGate45 rule)
               (fact-ev (wrappedGate45 MAIN Nil) accepted (AcceptSource S)))))
           (deps-has? $deps (index-hash (sk-key (AcceptSource S) (wrappedGate45 MAIN Nil))))))
        ($_cleared (clear-temp-query-adds))
        ($_contexts (sk-clear-contexts!)))
   (test $valid true))

;; Query materialization must not publish a positive private judgment in MAIN.
!(query-materialize 300 wrappedGate45 (: $p (Implication (A a) (C a)) $tv))
!(test (kb-facts (brand Statement (Implication (A a) (C a))) (kbctx wrappedGate45)) ())
!(test (kb-facts (brand Statement (A a)) (kbctx wrappedGate45)) ())
!(test (kb-facts (brand Statement (C a)) (kbctx wrappedGate45)) ())
!(test (collapse (query 300 wrappedGate45 (: $p (A a) $tv))) ())
!(test (collapse (query 300 wrappedGate45 (: $p (C a) $tv))) ())
!(test (kb-facts (brand Statement (A a)) (kbctx unwrappedGate45)) ())
!(test (kb-facts (brand Statement (C a)) (kbctx unwrappedGate45)) ())
!(test (collapse (query 300 unwrappedGate45 (: $p (A a) $tv))) ())
!(test (collapse (query 300 unwrappedGate45 (: $p (C a) $tv))) ())
