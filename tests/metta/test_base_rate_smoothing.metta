!(import! &self ../../pettachainer/metta/petta_chainer)

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
   (query 400 smoothKb (: $p (Leak q) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.11904761904761901 0.8))) aq) (Leak q) (STV 0.37815126050420156 0.5514604290276861)))
!(test
   (query 400 plainKb (: $p (Leak q) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.023809523809523805 0.8))) aq) (Leak q) (STV 0.09890109890109888 0.23309946016373)))
