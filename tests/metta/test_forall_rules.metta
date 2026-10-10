!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule inside (ForAll (vars) ...) holds for each value of those variables
;; with the same truth; its other variables are the individuals its
;; probability ranges over. Base rates are then taken per parameter value, so
;; inverting the sensor rule uses each cohort's own leak rate as the prior. The
;; plain rule averages over cohorts and units alike and pools the rates.
;; old: leaks 2/4; new: leaks 1/4.

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

;; Bayes: 0.9 * 0.5 / (0.9 * 0.5 + 0.2 * 0.5) and 0.9 * 0.25 / (0.9 * 0.25 + 0.2 * 0.75).
!(test
   (query 400 forallKb (: $p (Leak old q) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.5 0.004975124378109453))) alarm-q) (Leak old q) (STV 0.8181729800434836 0.009160887759402827)))
!(test
   (query 400 forallKb (: $p (Leak new r) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.2619047619047619 0.004975124378109453))) alarm-r) (Leak new r) (STV 0.6148927639357369 0.0038345935534032857)))

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

;; Pooled: 0.9 * 3/8 / (0.9 * 3/8 + 0.2 * 5/8) for both cohorts.
!(test
   (query 400 plainKb (: $p (Leak old q) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.37804878048780494 0.009900990099009901))) alarm-q) (Leak old q) (STV 0.7322718172506869 0.012078479877071847)))
!(test
   (query 400 plainKb (: $p (Leak new r) $tv))
   (: ((inverted sensor with cpu (prior (STV 0.37804878048780494 0.009900990099009901))) alarm-r) (Leak new r) (STV 0.7322718172506869 0.012078479877071847)))

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
         (implication-instance-fold cpu))
      (RuleTruth (Implication (Leak $_c $_u) (Alarm $_c $_u)))
      (CTV (STV 0.8999028182701653 0.9000374859427714) (STV 0.2001110956811554 0.9000124984376953))))
