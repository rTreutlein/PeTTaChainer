!(import! &self ../../pettachainer/metta/petta_chainer)

;; A forward run spends its units on row computations and carries the agenda
;; it leaves to the next run (docs/metta/forward_units.md).

(: test-selected-facts
   (-[det]-> KB Statement
      (List (Statement KBContext Proof TV))))
(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $prf $tv)))))

(: computed? (-[semidet]-> KB Statement Bool))
(= (computed? $kb $type)
   (case (sk-key-value (sk-key $type ($kb MAIN Nil))) (
      ((sk-val $_fact $_ev $_deps) true)
      ($_none false))))

!(set-backward-query-metrics true)

;; --- Every row computed costs a unit; a cut run is continued later ---------

!(compileadd fanKb (: pa (P a) (STV 1.0 0.9)))
!(compileadd fanKb (: r1 (Implication (P $x) (Q1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd fanKb (: r2 (Implication (P $x) (Q2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd fanKb (: r3 (Implication (P $x) (Q3 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd fanKb (: r4 (Implication (P $x) (Q4 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

;; Three units compute three of the four rows the seed's joins create.
!(begin-backward-query-metrics!)
!(forward-chain 3 fanKb (test-selected-facts fanKb (P a)))
!(test (query_metric_value row-computes) 3)
!(test
   (+ (+ (if (computed? fanKb (Q1 a)) 1 0) (if (computed? fanKb (Q2 a)) 1 0))
      (+ (if (computed? fanKb (Q3 a)) 1 0) (if (computed? fanKb (Q4 a)) 1 0)))
   3)

;; A call without facts continues from the carried agenda.
!(forward-chain 10 fanKb ())
!(test
   (and (and (computed? fanKb (Q1 a)) (computed? fanKb (Q2 a)))
        (and (computed? fanKb (Q3 a)) (computed? fanKb (Q4 a))))
   true)

;; --- Seeds queued without units keep their share ------------------------

;; A run without units queues its facts; a later run without facts gives the
;; queued seeds the share, however high a carried derived key ranks: here
;; (Mid a), which one unit computed and left to build on.
!(set-forward-seed-share 0)
!(compileadd queuedNoShareKb (: hi (Hi a) (STV 1.0 0.99)))
!(compileadd queuedNoShareKb (: hm (Implication (Hi $x) (Mid $x)) (CTV (STV 1.0 0.99) (STV 0.0 1.0))))
!(compileadd queuedNoShareKb (: m1 (Implication (Mid $x) (M1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd queuedNoShareKb (: m2 (Implication (Mid $x) (M2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd queuedNoShareKb (: m3 (Implication (Mid $x) (M3 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 1 queuedNoShareKb (test-selected-facts queuedNoShareKb (Hi a)))
!(compileadd queuedNoShareKb (: lo (Lo a) (STV 1.0 0.3)))
!(compileadd queuedNoShareKb (: l1 (Implication (Lo $x) (LoGoal $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 0 queuedNoShareKb (test-selected-facts queuedNoShareKb (Lo a)))
!(forward-chain 2 queuedNoShareKb ())
!(test (computed? queuedNoShareKb (LoGoal a)) false)

!(set-forward-seed-share 0.5)
!(compileadd queuedHalfShareKb (: hi (Hi a) (STV 1.0 0.99)))
!(compileadd queuedHalfShareKb (: hm (Implication (Hi $x) (Mid $x)) (CTV (STV 1.0 0.99) (STV 0.0 1.0))))
!(compileadd queuedHalfShareKb (: m1 (Implication (Mid $x) (M1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd queuedHalfShareKb (: m2 (Implication (Mid $x) (M2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd queuedHalfShareKb (: m3 (Implication (Mid $x) (M3 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 1 queuedHalfShareKb (test-selected-facts queuedHalfShareKb (Hi a)))
!(compileadd queuedHalfShareKb (: lo (Lo a) (STV 1.0 0.3)))
!(compileadd queuedHalfShareKb (: l1 (Implication (Lo $x) (LoGoal $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 0 queuedHalfShareKb (test-selected-facts queuedHalfShareKb (Lo a)))
!(forward-chain 2 queuedHalfShareKb ())
!(test (computed? queuedHalfShareKb (LoGoal a)) true)

;; --- A row a run created but could not pay for is computed when needed ----

;; One unit computes one of the two rows the seed's joins create. A query
;; reaching the other below the depth it computes in full still computes it,
;; since it has no value yet.
!(set-forward-seed-share 0.5)
!(compileadd deepKb (: pd (P d) (STV 1.0 0.9)))
!(compileadd deepKb (: d1 (Implication (P $x) (Q1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd deepKb (: d2 (Implication (P $x) (Q2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd deepKb (: d3 (Implication (Q2 $x) (R $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd deepKb (: d4 (Implication (R $x) (S $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd deepKb (: d5 (Implication (S $x) (T $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd deepKb (: d6 (Implication (T $x) (U $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 1 deepKb (test-selected-facts deepKb (P d)))
!(test (+ (if (computed? deepKb (Q1 d)) 1 0) (if (computed? deepKb (Q2 d)) 1 0)) 1)
!(test (== (collapse (query 100 deepKb (: $prf (U d) $tv))) ()) false)
