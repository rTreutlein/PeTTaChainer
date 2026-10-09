!(import! &self ../../pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 5.0)

;; Many roots, small budgets. A storm persists into period t1 and blocks three
;; routes; a blocked route delays its shipment. Periods h1..h4 are resolved:
;; the storm and blocks are stored, so their base rates count four periods.
;; At t1, s1 is late and s3 is not.
(: any-kb! (-[det]-> KB KB))
(= (any-kb! $kb)
   (let $_added
      (collapse (compileadd $kb (superpose (
         (: persist (Implication (And (NextPeriod $p $t) (Storm north $p)) (Storm north $t)) (CTV (STV 0.7 1) (STV 0.3 1)))
         (: block-r1 (Implication (Storm north $p) (Blocked r1 $p)) (CTV (STV 0.8 1) (STV 0.05 1)))
         (: block-r2 (Implication (Storm north $p) (Blocked r2 $p)) (CTV (STV 0.8 1) (STV 0.05 1)))
         (: block-r3 (Implication (Storm north $p) (Blocked r3 $p)) (CTV (STV 0.8 1) (STV 0.05 1)))
         (: late-s1 (Implication (Blocked r1 $p) (Late s1 $p)) (CTV (STV 0.9 1) (STV 0.05 1)))
         (: late-s2 (Implication (Blocked r2 $p) (Late s2 $p)) (CTV (STV 0.9 1) (STV 0.05 1)))
         (: late-s3 (Implication (Blocked r3 $p) (Late s3 $p)) (CTV (STV 0.9 1) (STV 0.05 1)))
         (: next-h2 (NextPeriod h1 h2) (STV 1 1))
         (: next-h3 (NextPeriod h2 h3) (STV 1 1))
         (: next-h4 (NextPeriod h3 h4) (STV 1 1))
         (: next-t1 (NextPeriod h4 t1) (STV 1 1))
         (: storm-h1 (Storm north h1) (STV 1 1))
         (: storm-h2 (Storm north h2) (STV 0 1))
         (: storm-h3 (Storm north h3) (STV 0 1))
         (: storm-h4 (Storm north h4) (STV 1 1))
         (: blocked-r1-h1 (Blocked r1 h1) (STV 1 1))
         (: blocked-r1-h2 (Blocked r1 h2) (STV 0 1))
         (: blocked-r1-h3 (Blocked r1 h3) (STV 0 1))
         (: blocked-r1-h4 (Blocked r1 h4) (STV 1 1))
         (: blocked-r2-h1 (Blocked r2 h1) (STV 1 1))
         (: blocked-r2-h2 (Blocked r2 h2) (STV 0 1))
         (: blocked-r2-h3 (Blocked r2 h3) (STV 1 1))
         (: blocked-r2-h4 (Blocked r2 h4) (STV 1 1))
         (: blocked-r3-h1 (Blocked r3 h1) (STV 0 1))
         (: blocked-r3-h2 (Blocked r3 h2) (STV 0 1))
         (: blocked-r3-h3 (Blocked r3 h3) (STV 0 1))
         (: blocked-r3-h4 (Blocked r3 h4) (STV 1 1))
         (: late-s1-t1 (Late s1 t1) (STV 1 1))
         (: late-s3-t1 (Late s3 t1) (STV 0 1))))))
      $kb))

(: any-query (-[det]-> Number KB (List QueryBatchResult)))
(= (any-query $steps $kb)
   (collapse (query-many $steps $kb
      ((: $prf (Blocked r1 t1) $tv)
       (: $prf (Blocked r2 t1) $tv)
       (: $prf (Blocked r3 t1) $tv)
       (: $prf (Storm north t1) $tv)))))

;; The strengths of the roots' answers in root order, and their total distance
;; from the exact posterior: storm 0.8456, routes 0.9091, 0.6842 and 0.2514
;; (Bayes' rule over the persisted storm and both shipments).
(: any-strengths (-[det]-> (List QueryBatchResult) (List Number)))
(= (any-strengths ()) ())
(= (any-strengths (cons (query-result $_i (: $_proof $_statement (STV $s $_c))) $rest))
   (cons (the Number $s) (any-strengths $rest)))

(: any-error (-[det]-> (List Number) (List Number) Number))
(= (any-error () ()) 0.0)
(= (any-error (cons $s $rest) (cons $e $exact-rest)) (+ (abs-math (- $s $e)) (any-error $rest $exact-rest)))

(: any-error-at (-[det]-> Number KB Number))
(= (any-error-at $steps $kb)
   (any-error (any-strengths (any-query $steps (any-kb! $kb))) (0.9091 0.6842 0.2514 0.8456)))

;; With no budget every root answers its population prior: the base rate of
;; its pattern over the resolved periods, which its inversions update.
!(test
   (any-query 0 (any-kb! b0))
   ((query-result 0 (: (population-prior (Blocked r1 $p1)) (Blocked r1 t1) (STV 0.5 0.4444444444444444)))
    (query-result 1 (: (population-prior (Blocked r2 $p2)) (Blocked r2 t1) (STV 0.75 0.4444444444444444)))
    (query-result 2 (: (population-prior (Blocked r3 $p3)) (Blocked r3 t1) (STV 0.25 0.4444444444444444)))
    (query-result 3 (: (population-prior (Storm north $p4)) (Storm north t1) (STV 0.5 0.4444444444444444)))))

;; Every budget answers every root, and the answers approach the posterior as
;; the budget grows. The first steps complete the answers of the roots they
;; start: the root's own premise, the storm, goes before the next root, and a
;; premise no rule concludes (NextPeriod) is expanded without a step once the
;; budget is spent. Four steps reach the posterior.
!(test (length (any-strengths (any-query 1 (any-kb! c1)))) 4)
!(test (< (any-error-at 1 e1) (any-error-at 0 e0)) true)
!(test (< (any-error-at 2 e2) (any-error-at 1 e1b)) true)
!(test (< (any-error-at 4 e4) (any-error-at 2 e2b)) true)
!(test (< (any-error-at 4 e4b) 0.001) true)
!(test (< (any-error-at 50 e50) 0.001) true)

;; The prior is the population's value, not the statement's: a materializing
;; query writes back no prior.
!(test
   (let $_rows (collapse (query-many-materialize 0 (any-kb! m0) ((: $prf (Storm north t1) $tv))))
      (collapse (match &materialized_facts (materialized-row $_h (Storm north t1) $_ctx $fact $_ev) $fact)))
   ())
