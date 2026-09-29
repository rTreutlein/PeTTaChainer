!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule inside (ForAll (vars) ...) holds for each value of those variables
;; with the same truth; its other variables are the individuals its
;; probability ranges over. Base rates are then taken per parameter value, so
;; inverting the sensor rule uses each cohort's own leak and alarm rates. The
;; plain rule averages over cohorts and units alike and pools the rates.
;; old: leaks 2/4, alarms 3/5 (with q); new: leaks 1/4, alarms 3/5 (with r).

!(compileadd forallKb (: sensor (ForAll ($c) (Implication (Leak $c $u) (Alarm $c $u))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd forallKb (: leak-o1 (Leak old o1) (STV 1 1)))
!(compileadd forallKb (: alarm-o1 (Alarm old o1) (STV 1 1)))
!(compileadd forallKb (: leak-o2 (Leak old o2) (STV 1 1)))
!(compileadd forallKb (: alarm-o2 (Alarm old o2) (STV 1 1)))
!(compileadd forallKb (: leak-o3 (Leak old o3) (STV 0 1)))
!(compileadd forallKb (: alarm-o3 (Alarm old o3) (STV 0 1)))
!(compileadd forallKb (: leak-o4 (Leak old o4) (STV 0 1)))
!(compileadd forallKb (: alarm-o4 (Alarm old o4) (STV 0 1)))
!(compileadd forallKb (: leak-n1 (Leak new n1) (STV 1 1)))
!(compileadd forallKb (: alarm-n1 (Alarm new n1) (STV 1 1)))
!(compileadd forallKb (: leak-n2 (Leak new n2) (STV 0 1)))
!(compileadd forallKb (: alarm-n2 (Alarm new n2) (STV 1 1)))
!(compileadd forallKb (: leak-n3 (Leak new n3) (STV 0 1)))
!(compileadd forallKb (: alarm-n3 (Alarm new n3) (STV 0 1)))
!(compileadd forallKb (: leak-n4 (Leak new n4) (STV 0 1)))
!(compileadd forallKb (: alarm-n4 (Alarm new n4) (STV 0 1)))
!(compileadd forallKb (: alarm-q (Alarm old q) (STV 1 1)))
!(compileadd forallKb (: alarm-r (Alarm new r) (STV 1 1)))

;; 0.9 * 0.5 / 0.6 and 0.9 * 0.25 / 0.6.
!(test
   (query 400 forallKb (: $p (Leak old q) $tv))
   (: ((inverted sensor with cpu cpu) alarm-q) (Leak old q) (STV 0.7499450545791458 8.965949626547365e-05)))
!(test
   (query 400 forallKb (: $p (Leak new r) $tv))
   (: ((inverted sensor with cpu cpu) alarm-r) (Leak new r) (STV 0.37505120988541074 0.0016759835542741416)))

!(compileadd plainKb (: sensor (Implication (Leak $c $u) (Alarm $c $u)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd plainKb (: leak-o1 (Leak old o1) (STV 1 1)))
!(compileadd plainKb (: alarm-o1 (Alarm old o1) (STV 1 1)))
!(compileadd plainKb (: leak-o2 (Leak old o2) (STV 1 1)))
!(compileadd plainKb (: alarm-o2 (Alarm old o2) (STV 1 1)))
!(compileadd plainKb (: leak-o3 (Leak old o3) (STV 0 1)))
!(compileadd plainKb (: alarm-o3 (Alarm old o3) (STV 0 1)))
!(compileadd plainKb (: leak-o4 (Leak old o4) (STV 0 1)))
!(compileadd plainKb (: alarm-o4 (Alarm old o4) (STV 0 1)))
!(compileadd plainKb (: leak-n1 (Leak new n1) (STV 1 1)))
!(compileadd plainKb (: alarm-n1 (Alarm new n1) (STV 1 1)))
!(compileadd plainKb (: leak-n2 (Leak new n2) (STV 0 1)))
!(compileadd plainKb (: alarm-n2 (Alarm new n2) (STV 1 1)))
!(compileadd plainKb (: leak-n3 (Leak new n3) (STV 0 1)))
!(compileadd plainKb (: alarm-n3 (Alarm new n3) (STV 0 1)))
!(compileadd plainKb (: leak-n4 (Leak new n4) (STV 0 1)))
!(compileadd plainKb (: alarm-n4 (Alarm new n4) (STV 0 1)))
!(compileadd plainKb (: alarm-q (Alarm old q) (STV 1 1)))
!(compileadd plainKb (: alarm-r (Alarm new r) (STV 1 1)))

;; Pooled: 0.9 * 3/8 / 0.6 for both cohorts.
!(test
   (query 400 plainKb (: $p (Leak old q) $tv))
   (: ((inverted sensor with cpu cpu) alarm-q) (Leak old q) (STV 0.5625177966904826 0.002697500960340694)))
!(test
   (query 400 plainKb (: $p (Leak new r) $tv))
   (: ((inverted sensor with cpu cpu) alarm-r) (Leak new r) (STV 0.5625177966904826 0.002697500960340694)))

;; Refined, the ForAll rule's instances pool across cohorts: every
;; (cohort, unit) with a leak is a sample of the one shared truth.
!(set-rule-refinement forallRefineKb true)
!(compileadd forallRefineKb (: sensor (ForAll ($c) (Implication (Leak $c $u) (Alarm $c $u))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd forallRefineKb (: leak-o1 (Leak old o1) (STV 1 1)))
!(compileadd forallRefineKb (: alarm-o1 (Alarm old o1) (STV 1 1)))
!(compileadd forallRefineKb (: leak-o2 (Leak old o2) (STV 1 1)))
!(compileadd forallRefineKb (: alarm-o2 (Alarm old o2) (STV 1 1)))
!(compileadd forallRefineKb (: leak-n1 (Leak new n1) (STV 1 1)))
!(compileadd forallRefineKb (: alarm-n1 (Alarm new n1) (STV 0 1)))
!(compileadd forallRefineKb (: leak-n2 (Leak new n2) (STV 0 1)))
!(compileadd forallRefineKb (: alarm-n2 (Alarm new n2) (STV 1 1)))

!(test
   (query 400 forallRefineKb (: $p (RuleTruth (Implication (Leak $c $u) (Alarm $c $u))) $tv))
   (: (merge/revision
         (rule-axiom sensor)
         (implication-instance-fold
            (foldall-proof
               (implication-instance-sample leak-o1 alarm-o1)
               (implication-instance-sample leak-o2 alarm-o2)
               (implication-instance-sample leak-n1 alarm-n1)
               (implication-instance-sample leak-n2 alarm-n2))))
      (RuleTruth (Implication (Leak $_c $_u) (Alarm $_c $_u)))
      (CTV (STV 0.8999028182701653 0.9000374859427714) (STV 0.2 0.9))))
