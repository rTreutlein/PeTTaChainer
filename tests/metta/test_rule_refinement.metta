!(import! &self ../../pettachainer/metta/petta_chainer)

(: test-selected-facts
   (-[det]-> KB Statement
      (List (Statement KBContext Proof TV))))
(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $prf $tv)))))

;; Rule refinement is opt-in per KB. A refined rule resolves its truth value
;; as the goal (RuleTruth (Implication a b)): the stored row is that goal's
;; axiom proof, the implication instance fold a second proof, and modus
;; ponens consumes their revision. Instances the rule itself derives never
;; count as samples, so here only a with its stored fact b1 is a sample.

!(set-rule-refinement refineKb true)
!(compileadd refineKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd refineKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd refineKb (: a3 (A c) (STV 1.0 0.9)))
!(compileadd refineKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd refineKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

;; A derived instance carries the refined rule truth within one search.
!(test
   (query 400 refineKb (: $p (B b) $tv))
   (: (by ab a2) (B b) (STV 0.8000224974690348 0.9000097638542305)))

;; The rule-truth goal itself: axiom and fold revised, evidence is the rule's.
!(test
   (query 400 refineKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv))
   (: (merge/revision
         (rule-axiom ab)
         (implication-instance-fold
            (foldall-proof (implication-instance-sample a1 b1))))
      (RuleTruth (Implication (A $_x) (B $_x)))
      (CTV (STV 0.8000224974690348 0.9000101239749476) (STV 0.0 1.0))))

;; The implication query answers through the shared rule-truth goal. The
;; hypothetical proof through ab shares the rule's evidence and is dominated.
!(test
   (query 400 refineKb (: $p (Implication (A $v) (B $v)) $tv))
   (: (rule-truth
         (merge/revision
            (rule-axiom ab)
            (implication-instance-fold
               (foldall-proof (implication-instance-sample a1 b1)))))
      (Implication (A $_v) (B $_v))
      (CTV (STV 0.8000224974690348 0.9000101239749476) (STV 0.0 1.0))))

;; --- Facts added later join the fold --------------------------------------
;; The next query that reads the truth goal refolds it with the new samples.

!(set-rule-refinement refreshKb true)
!(compileadd refreshKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd refreshKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd refreshKb (: a3 (A c) (STV 1.0 0.9)))
!(compileadd refreshKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd refreshKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(test
   (query 400 refreshKb (: $p (B b) $tv))
   (: (by ab a2) (B b) (STV 0.8000224974690348 0.9000097638542305)))

!(compileadd refreshKb (: b3 (B c) (STV 1.0 0.9)))
!(compileadd refreshKb (: a4 (A d) (STV 1.0 0.9)))

!(test
   (query 400 refreshKb (: $p (B d) $tv))
   (: (by ab a4) (B d) (STV 0.8000449898772777 0.9000198857207663)))

!(test
   (query 400 refreshKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv))
   (: (merge/revision
         (rule-axiom ab)
         (implication-instance-fold
            (foldall-proof
               (implication-instance-sample a1 b1)
               (implication-instance-sample a3 b3))))
      (RuleTruth (Implication (A $_x) (B $_x)))
      (CTV (STV 0.8000449898772777 0.9000202459002052) (STV 0.0 1.0))))

!(compileadd refreshKb (: a5 (A e) (STV 1.0 0.9)))

!(test
   (query 400 refreshKb (: $p (B e) $tv))
   (: (by ab a5) (B e) (STV 0.8000449898772777 0.9000198857207663)))

;; --- Without the flag the stored truth is used as before ------------------

!(compileadd plainKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd plainKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd plainKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd plainKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(test
   (query 400 plainKb (: $p (B b) $tv))
   (: (by ab a2) (B b) (STV 0.8 0.8999996399380039)))

;; --- An STV rule: truth merges as an STV, modus ponens converts ------------

!(set-rule-refinement refineStvKb true)
!(compileadd refineStvKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd refineStvKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd refineStvKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd refineStvKb (: ab (Implication (A $x) (B $x)) (STV 0.8 0.9)))

!(test
   (query 400 refineStvKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv))
   (: (merge/revision
         (rule-axiom ab)
         (implication-instance-fold
            (foldall-proof (implication-instance-sample a1 b1))))
      (RuleTruth (Implication (A $_x) (B $_x)))
      (STV 0.8000224974690348 0.9000101239749476)))

!(test
   (query 400 refineStvKb (: $p (B b) $tv))
   (: (by ab a2) (B b) (STV 0.8000224974690348 0.9000101014614428)))

;; --- Facts only: no refined rule carries the fold, so the query folds ------

!(set-rule-refinement refineFactsKb true)
!(compileadd refineFactsKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd refineFactsKb (: a2 (A b) (STV 1.0 0.9)))
!(compileadd refineFactsKb (: b1 (B a) (STV 1.0 0.9)))
!(compileadd refineFactsKb (: b2 (B b) (STV 1.0 0.9)))

!(test
   (query 400 refineFactsKb (: $p (Implication (A $v) (B $v)) $tv))
   (: (implication-instance-fold
         (foldall-proof
            (implication-instance-sample a1 b1)
            (implication-instance-sample a2 b2)))
      (Implication (A $_v) (B $_v))
      (CTV (STV 1.0 0.0020209076619844817) (STV 1.0 0.0005052269154961204))))

;; --- Forward chaining fires a refined rule with its truth goal's value -----

!(set-rule-refinement refineFwdKb true)
!(compileadd refineFwdKb
   (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))
!(compileadd refineFwdKb (: a1 (A a) (STV 1.0 0.9)))

!(test
   (case (forward-chain 3 refineFwdKb (test-selected-facts refineFwdKb (A a))) (
      ((cons ((B a) $_kbctx $prf $tv) $_rest) (let $full (sk-full-proof $prf) (quote ($full $tv))))
      ($_other $_other)))
   ((by ab a1) (STV 0.8 0.8999996399380039)))

;; --- A shape the instance producer does not sample keeps its stored truth --

!(set-rule-refinement refineNotKb true)
!(compileadd refineNotKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd refineNotKb
   (: notRule (Implication (A $x) (Not (D $x))) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(test
   (query 400 refineNotKb (: $p (Not (D a)) $tv))
   (: (negated (negated (by notRule a1))) (Not (D a)) (STV 0.8 0.8999996399380039)))

;; --- Inversion reads the refined truth ---------------------------------------
;; (P alice) follows from (Q alice) by inverting r. The samples bob and carl
;; refine r's truth, and the inverted rule applies with it; the stored truth
;; alone gives (STV 0.9440830137009913 0.0036792980798056596).

!(set-rule-refinement refineInvKb true)
!(compileadd refineInvKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd refineInvKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd refineInvKb (: pb (P bob) (STV 0.7 0.8)))
!(compileadd refineInvKb (: qb (Q bob) (STV 1.0 0.9)))
!(compileadd refineInvKb (: pc (P carl) (STV 1.0 0.9)))
!(compileadd refineInvKb (: qc (Q carl) (STV 0.0 0.9)))

!(test
   (query 400 refineInvKb (: $p (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.8588235294117645 0.0021204939503554946))) qa) (P alice) (STV 0.9440628144837059 0.003672066646012404)))

;; --- A certain rule is not refined --------------------------------------------
;; Revision leaves a truth stated with confidence 1 unchanged, so the rule
;; applies with its stored truth and has no rule-truth goal.

!(set-rule-refinement certainRuleKb true)
!(compileadd certainRuleKb (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 1.0) (STV 0.0 1.0))))
!(compileadd certainRuleKb (: a1 (A a) (STV 1.0 0.9)))
!(compileadd certainRuleKb (: b1 (B a) (STV 0.0 0.9)))
!(compileadd certainRuleKb (: a2 (A b) (STV 1.0 0.9)))

!(test
   (query 400 certainRuleKb (: $p (B b) $tv))
   (: (by ab a2) (B b) (STV 0.8 0.9998995657056552)))
!(test
   (collapse (query 400 certainRuleKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)))
   ())
