!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule's truth is a live statistic, not a historical belief. Freezing it
;; disconnected the instance fold: a rule learned from one success stayed at
;; 0.995 after a retained counterexample rather than revising to 0.5.
!(set-evidence-confidence-k 1)
!(set-rule-refinement fgRuleKb true)
!(set-rule-change-hazard fgRuleKb 0)
!(set-positive-only-predicate fgRuleKb A)
!(set-forgetting 1 1.0)
!(compileadd fgRuleKb (: r (Implication (A $x) (B $x)) (STV 0.5 0.01)))
!(compileadd fgRuleKb (: a1 (A i1) (STV 1 1)))
!(compileadd fgRuleKb (: b1 (B i1) (STV 1 1)))
!(test (let (: $_p $_s (STV $strength $_c)) (query 100 fgRuleKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $strength) 0.9949999999999999)
!(advance-epoch)
!(advance-epoch)
!(test (match-count &sk_row ($_h (sk-key (RuleTruth (Implication (A $x) (B $x))) (fgRuleKb MAIN Nil)) $_rh $_row)) 1)
!(compileadd fgRuleKb (: a2 (A i2) (STV 1 1)))
!(compileadd fgRuleKb (: b2 (B i2) (STV 0 1)))
!(test (let (: $_p $_s (STV $strength $_c)) (query 100 fgRuleKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $strength) 0.5)
!(test (query 0 fgRuleKb (: $p (B i1) $tv)) (: b1 (B i1) (STV 1 1)))
!(test (query 0 fgRuleKb (: $p (B i2) $tv)) (: b2 (B i2) (STV 0 1)))
!(set-forgetting 0 1.0)
!(set-evidence-confidence-k 800)
