!(import! &self ../../pettachainer/metta/petta_chainer)

;; Observations of one instance through several sensors, each inverted over
;; the instance's prior, combine by Bayes' rule: an uninformative sensor
;; (as likely with a leak as without) leaves the belief the informative one
;; gives (docs/metta/prior_factored_merge.md).

!(compileadd alarmKb (: alarm (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.85 0.9) (STV 0.15 0.9))))
!(compileadd alarmKb (: p1 (LeakPredicted m) (STV 0.088 0.8)))
!(compileadd alarmKb (: a1 (Alarm m) (STV 1.0 1.0)))

!(compileadd noisyKb (: alarm (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.85 0.9) (STV 0.15 0.9))))
!(compileadd noisyKb (: noise0 (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Noise0 $u))) (CTV (STV 0.5675 1.0) (STV 0.5675 1.0))))
!(compileadd noisyKb (: noise1 (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Noise1 $u))) (CTV (STV 0.5675 1.0) (STV 0.5675 1.0))))
!(compileadd noisyKb (: p1 (LeakPredicted m) (STV 0.088 0.8)))
!(compileadd noisyKb (: a1 (Alarm m) (STV 1.0 1.0)))
!(compileadd noisyKb (: n0 (Noise0 m) (STV 1.0 1.0)))
!(compileadd noisyKb (: n1 (Noise1 m) (STV 0.0 1.0)))

!(test (case (query 100 alarmKb (: $p (SealLeak m) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.3535530522561636 0.5373975857284105))
!(test (case (query 100 noisyKb (: $p (SealLeak m) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.3535530522561636 0.5373701458221191))

;; Two informative sensors that both fire compound as Bayes' rule does.
!(compileadd twoKb (: alarm (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm $u))) (CTV (STV 0.85 0.9) (STV 0.15 0.9))))
!(compileadd twoKb (: alarm2 (WithPrior (LeakPredicted $u) (Implication (SealLeak $u) (Alarm2 $u))) (CTV (STV 0.85 0.9) (STV 0.15 0.9))))
!(compileadd twoKb (: p1 (LeakPredicted m) (STV 0.088 0.8)))
!(compileadd twoKb (: a1 (Alarm m) (STV 1.0 1.0)))
!(compileadd twoKb (: b1 (Alarm2 m) (STV 1.0 1.0)))
!(test (case (query 100 twoKb (: $p (SealLeak m) $tv)) (((: $_p $_s $tv) $tv))) (STV 0.7560357977009485 0.5511163316231898))
