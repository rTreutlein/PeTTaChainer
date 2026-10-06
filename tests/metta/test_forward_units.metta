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

;; --- A new seed gets its share of the units --------------------------------

;; A run without units carries a confident seed, which ranks above a weak
;; new seed of the next run.

;; With no share, the carried seed's rows take both units.
!(set-forward-seed-share 0)
!(compileadd noShareKb (: hi (Hi a) (STV 1.0 0.99)))
!(compileadd noShareKb (: h1 (Implication (Hi $x) (H1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd noShareKb (: h2 (Implication (Hi $x) (H2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd noShareKb (: h3 (Implication (Hi $x) (H3 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 0 noShareKb (test-selected-facts noShareKb (Hi a)))
!(compileadd noShareKb (: lo (Lo a) (STV 1.0 0.3)))
!(compileadd noShareKb (: l1 (Implication (Lo $x) (LoGoal $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 2 noShareKb (test-selected-facts noShareKb (Lo a)))
!(test (computed? noShareKb (LoGoal a)) false)

;; With half, the new seed's conclusion is computed first.
!(set-forward-seed-share 0.5)
!(compileadd halfShareKb (: hi (Hi a) (STV 1.0 0.99)))
!(compileadd halfShareKb (: h1 (Implication (Hi $x) (H1 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd halfShareKb (: h2 (Implication (Hi $x) (H2 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd halfShareKb (: h3 (Implication (Hi $x) (H3 $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 0 halfShareKb (test-selected-facts halfShareKb (Hi a)))
!(compileadd halfShareKb (: lo (Lo a) (STV 1.0 0.3)))
!(compileadd halfShareKb (: l1 (Implication (Lo $x) (LoGoal $x)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(forward-chain 2 halfShareKb (test-selected-facts halfShareKb (Lo a)))
!(test (computed? halfShareKb (LoGoal a)) true)

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
