!(import! &self ../../pettachainer/metta/petta_chainer)

;; #74: the first query discovers an overlapping prior and inverse update.
;; Its remaining evaluation allowance cannot prepay the dependency-count
;; estimate. Its exact or partial conditioned result must use the dependent
;; update; a partial result must expose the remaining uncertainty.
(= (finite-tv (: $_proof $_type $tv)) $tv)
;; The dropped-update result was 0.0136612 at confidence 0.9999675.
;; This finite prefix must move toward the analytic conditioned strength,
;; while lowering confidence to account for its unread frontier.
(= (finite-contributes (: $proof $_type (STV $s $c)))
   (if (== (car-atom $proof) partial-conditioned)
      (if (< $c 0.999967519870426)
         (< (abs-math (- $s 0.05887282355682909))
            (abs-math (- 0.01366120218579236 0.05887282355682909))) false)
      false))

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

!(test (map-flat finite-contributes (collapse (query 15 finiteKb (: $p (Degraded plant t1) $tv)))) (true))
!(test (map-flat finite-tv (collapse (query 2000 finiteKb (: $p (Degraded plant t1) $tv))))
   ((STV 0.05887282355682909 0.9998816871581414)))
!(test (search-id-value sk_claim_state) -1)
!(test (search-id-value sk_claim_approx) 0)

;; Metering itself: one unit buys two conditioned rows, including nested
;; reads. An exhausted charge cannot borrow from the near-root reserve or
;; make the allowance negative; unused credit expires with the claim.
!(change-state! sk_eval_budget 1)
!(sk-open-claim! false)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) false)
!(test (sk-close-claim!) true)
!(change-state! sk_eval_budget 1)
!(sk-open-claim! false)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) true)
!(test (sk-close-claim!) false)
!(sk-open-claim! false)
!(test (sk-claim-charge! ((sk-given 1 (sk-key (Cut x) (finiteKb MAIN Nil)) true))) false)
!(test (search-id-value sk_eval_budget) 0)
!(test (sk-close-claim!) true)

;; An unread conditional branch contributes ignorance, never observations.
!(test (proof-term-evidence proof-walk-in-kb (uncomputed)) (ev-set 0))
