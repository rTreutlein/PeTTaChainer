!(import! &self ../../pettachainer/metta/petta_chainer)

;; #81 one-step filtering summarizes deep shared history instead of opening
;; cross-period key claims. Root refinement is capped separately; a producing
;; observation certifies zero degradation without any conditioning work.

(= (nested-tv (: $_proof $_type $tv)) $tv)
(: nested-count (-[det]-> Number BackwardQueryMetric Number))
(= (nested-count $found (query-metric $key $n)) (if (== $key conditioned-evaluations) $n $found))

;; Five periods of alternating soft reports. The last report implies no
;; degradation; older periods enter as consumer-admitted marginal summaries.
!(compileadd nestedKb (: storm-t1 (Storm t1) (STV 0.6 1)))
!(compileadd nestedKb (: persist-storm (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.7 1) (STV 0.3 1))))
!(compileadd nestedKb (: fuel (Implication (Storm $t) (Fuelled plant $t)) (CTV (STV 0.2 1) (STV 0.9 1))))
!(compileadd nestedKb (: runs-plant (Implication (And (Fuelled plant $t) (Not (Degraded plant $t))) (Producing plant $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd nestedKb (: persist-degraded (Implication (And (NextPeriod $p $t) (Degraded plant $p)) (Degraded plant $t)) (CTV (STV 0.75 1) (STV 0.05 1))))
!(set-base-rate nestedKb (Degraded plant $t) (STV 0.25 0.9))
!(set-base-rate nestedKb (Storm $t) (STV 0.4 0.9))
!(compileadd nestedKb (: sound-t0 (Degraded plant t0) (STV 0 1)))
!(compileadd nestedKb (: next-t1 (NextPeriod t0 t1) (STV 1 1)))
!(compileadd nestedKb (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd nestedKb (: next-t3 (NextPeriod t2 t3) (STV 1 1)))
!(compileadd nestedKb (: next-t4 (NextPeriod t3 t4) (STV 1 1)))
!(compileadd nestedKb (: next-t5 (NextPeriod t4 t5) (STV 1 1)))
!(compileadd nestedKb (: rep-t1 (Producing plant t1) (STV 1 0.9)))
!(compileadd nestedKb (: rep-t2 (Producing plant t2) (STV 0 0.9)))
!(compileadd nestedKb (: rep-t3 (Producing plant t3) (STV 1 0.9)))
!(compileadd nestedKb (: rep-t4 (Producing plant t4) (STV 0 0.9)))
!(compileadd nestedKb (: rep-t5 (Producing plant t5) (STV 1 0.9)))
!(set-backward-query-metrics true)
;; #81: a producing report certifies zero degradation. Nested history is
;; summarized by factored updates, whose #49 discount changes the confidence
;; propagated through modus ponens but cannot weaken that zero likelihood.
!(test (map-flat nested-tv (collapse (query 300 nestedKb (: $p (Degraded plant t5) $tv))))
   ((STV 0.0 0.9830070597502556)))
!(test (fold-flat nested-count 0 (backward-query-metrics)) 0)
!(set-backward-query-metrics false)
