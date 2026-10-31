!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

;; With base-rate smoothing a KB reads each computed base rate as its n
;; observations plus k pseudo-observations at 0.5; the confidence n/(n+k) is
;; unchanged. With k = 1, no leak among four units gives 0.1, not 0.
!(set-evidence-confidence-k 1.0)
!(set-base-rate-smoothing smoothKb true)

!(test (finish-aggregate smoothKb base-rate (BaseRateEvidence 0.0 4.0)) (STV 0.09999999999999998 0.8))
!(test (finish-aggregate plainKb base-rate (BaseRateEvidence 0.0 4.0)) (STV 0.0 0.8))

;; An alarm on a new unit. The inversion reads the leak rate as the prior of
;; one more unit, its mean under the Bayes prior (0.2 pseudo-observations at
;; 0.5): no leak among four units gives 0.1 / 4.2 = 0.0238 without smoothing,
;; and the alarm (likelihood ratio 4.5) makes the leak 0.0989. The smoothed
;; rate, 0.1 over the same units, is read the same way, (0.4 + 0.1) / 4.2 =
;; 0.119, and gives 0.378.
!(compileadd smoothKb (: sensor (Implication (Leak $u) (Alarm $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd smoothKb (: l1 (Leak u1) (STV 0 1)))
!(compileadd smoothKb (: l2 (Leak u2) (STV 0 1)))
!(compileadd smoothKb (: l3 (Leak u3) (STV 0 1)))
!(compileadd smoothKb (: l4 (Leak u4) (STV 0 1)))
!(compileadd smoothKb (: a1 (Alarm u1) (STV 0 1)))
!(compileadd smoothKb (: a2 (Alarm u2) (STV 0 1)))
!(compileadd smoothKb (: a3 (Alarm u3) (STV 1 1)))
!(compileadd smoothKb (: a4 (Alarm u4) (STV 0 1)))
!(compileadd smoothKb (: aq (Alarm q) (STV 1 1)))

!(compileadd plainKb (: sensor (Implication (Leak $u) (Alarm $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd plainKb (: l1 (Leak u1) (STV 0 1)))
!(compileadd plainKb (: l2 (Leak u2) (STV 0 1)))
!(compileadd plainKb (: l3 (Leak u3) (STV 0 1)))
!(compileadd plainKb (: l4 (Leak u4) (STV 0 1)))
!(compileadd plainKb (: a1 (Alarm u1) (STV 0 1)))
!(compileadd plainKb (: a2 (Alarm u2) (STV 0 1)))
!(compileadd plainKb (: a3 (Alarm u3) (STV 1 1)))
!(compileadd plainKb (: a4 (Alarm u4) (STV 0 1)))
!(compileadd plainKb (: aq (Alarm q) (STV 1 1)))

!(test
   (let (: (node (conjunction aq (by sensor cpu) (population-prior (Leak $_0)))) (Leak q) (STV $posterior-s $posterior-c)) (query 400 smoothKb (: $p (Leak q) $tv)) (posterior-tv-near? 0.5779816513761467 0.6461336828309306 (STV $posterior-s $posterior-c)))
   true)
!(test
   (let (: (node (conjunction aq (by sensor cpu) (population-prior (Leak $_0)))) (Leak q) (STV $posterior-s $posterior-c)) (query 400 plainKb (: $p (Leak q) $tv)) (posterior-tv-near? 0.47368421052631565 0.5773644637910565 (STV $posterior-s $posterior-c)))
   true)
