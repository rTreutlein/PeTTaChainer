!(import! &self ../../pettachainer/metta/petta_chainer)

;; #45: the source acceptance is observed, while A is assumed privately.
;; These cold/warm proofs retain both inputs. The derived And(B, C) is a
;; prediction, so it moves C from its uniform prior by probability kinematics,
;; B unknown (P(K | C) = .5, P(K | not C) = 0): with n = 3.5 for the parts and
;; 800 c/(1 - c) for the prediction, P(K) = .798 and C = .798 + .202 (.25/.75).
!(compileadd wrappedGate45 (: accepted (AcceptSource S) (STV 1 1)))
!(compileadd wrappedGate45 (: rule
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 0.8 0.6)))
!(test (collapse (let
   (: (conditional-implication ((node-jeffrey 1
      (by (consequent-projection $source $child rule)
         (conjunction accepted (ctx proof $ctx))) $prediction $conditionals) cpu)) $type $tv)
   (query 300 wrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8655786350145539 0.03980772466060817)))
!(test (collapse (let
   (: (conditional-implication ((node-jeffrey 1
      (by (consequent-projection $source $child rule)
         (conjunction accepted (ctx proof $ctx))) $prediction $conditionals) cpu)) $type $tv)
   (query 300 wrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8655786350145539 0.03980772466060817)))

!(compileadd unwrappedGate45 (: accepted (AcceptSource S) (STV 1 1)))
!(compileadd unwrappedGate45 (: rule
   (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x))))
   (STV 0.8 0.6)))
!(test (collapse (let
   (: (conditional-implication ((node-jeffrey 1
      (by (by rule accepted) (ctx proof $ctx)) $prediction $conditionals) cpu)) $type $tv)
   (query 300 unwrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8657957244652751 0.04001674008863015)))
!(test (collapse (let
   (: (conditional-implication ((node-jeffrey 1
      (by (by rule accepted) (ctx proof $ctx)) $prediction $conditionals) cpu)) $type $tv)
   (query 300 unwrappedGate45 (: $p (Implication (A $x) (C $x)) $value)) $tv))
   ((STV 0.8657957244652751 0.04001674008863015)))

;; Inspect the live private value: MAIN evidence/dependency identity survives
;; borrowing, the certain gate is read as a condition (given-ev), and the
;; assumed A is a dependency but no empirical evidence.
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
               (given-ev (wrappedGate45 MAIN Nil) accepted (AcceptSource S)))))
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
