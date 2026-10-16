!(import! &self ../../pettachainer/metta/petta_chainer)

;; Round 1: H2 removal changes conditioned current inputs; H1/H3 still make this finite-budget history approximate.

;; Conditioning nests: a branch whose views still overlap conditions again on
;; the next shared statement, so a claim's work can double with every level.
;; A claim may make at most twice its cost bound in conditioned row
;; evaluations; one that would make more falls back as an unpaid one does
;; (docs/metta/overlap_conditioning.md, "Cost").

(= (nested-tv (: $_proof $_type $tv)) $tv)
(: nested-count (-[det]-> Number BackwardQueryMetric Number))
(= (nested-count $found (query-metric $key $n)) (if (== $key conditioned-evaluations) $n $found))

;; test_overlap_conditioning's plant over five periods, every report soft:
;; each Degraded key's persistence view and report view share the storms, and
;; conditioning Degraded plant t5 conditions t4 inside its branches, t4 t3,
;; and so on. Before claims were bounded this query took 238 s for the same
;; answer; it now makes 5642 conditioned row evaluations, in a few seconds.
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
!(test (map-flat nested-tv (collapse (query 300 nestedKb (: $p (Degraded plant t5) $tv))))
   ((STV 0.23349245547949588 0.9994951194533498)))
!(test (< (fold-flat nested-count 0 (backward-query-metrics)) 10000) true)
!(set-backward-query-metrics false)
