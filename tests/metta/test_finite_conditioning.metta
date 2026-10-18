!(import! &self ../../pettachainer/metta/petta_chainer)

;; #74: an unaffordable pass retains the waiting value; a later large query
;; completes the retained conditioned calculation.
;; The waiting strength is the factored update: odds(.05) times
;; (.25/.95)/(1-.48), giving .02594438; it retains the report evidence. The small affordable-cut
;; regression is in test_premise_conditioning.metta (budget 3). The cheaper
;; certain-likelihood reads now reach this waiting stage at budget 10.
(= (finite-tv (: $_proof $_type $tv)) $tv)

!(compileadd finiteKb (: storm-t1 (Storm t1) (STV 0.6 1)))
!(compileadd finiteKb (: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1))))
!(compileadd finiteKb (: fuel (Implication (Storm $t) (Fuelled plant $t)) (CTV (STV 0.2 1) (STV 0.9 1))))
!(compileadd finiteKb (: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd finiteKb (: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1))))
!(set-base-rate finiteKb (Degraded plant $t) (STV 0.25 0.9))
!(set-base-rate finiteKb (Storm $t) (STV 0.4 0.9))
!(compileadd finiteKb (: sound-t0 (Degraded plant t0) (STV 0 1)))
!(compileadd finiteKb (: next-t1 (NextPeriod t0 t1) (STV 1 1)))
!(compileadd finiteKb (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd finiteKb (: next-t3 (NextPeriod t2 t3) (STV 1 1)))
!(compileadd finiteKb (: off-t1 (Producing plant t1) (STV 0 1)))
!(compileadd finiteKb (: on-t2 (Producing plant t2) (STV 1 1)))

!(test (map-flat finite-tv (collapse (query 10 finiteKb (: $p (Degraded plant t1) $tv))))
   ((STV 0.025944381244804894 0.8018751981786723)))
!(test (map-flat finite-tv (collapse (query 2000 finiteKb (: $p (Degraded plant t1) $tv))))
   ((STV 0.0588728408972088 0.9998816871399366)))
!(test (search-id-value sk_claim_state) -1)

;; Metering itself: one unit buys two conditioned rows, including nested
;; reads. An exhausted charge cannot borrow from the near-root reserve or
;; make the allowance negative; unused credit expires with the claim.
!(change-state! sk_eval_budget 1)
!(sk-open-claim!)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) false)
!(test (sk-close-claim!) true)
!(change-state! sk_eval_budget 1)
!(sk-open-claim!)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (sk-close-claim!) false)
!(sk-open-claim!)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) false)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-close-claim!) true)
