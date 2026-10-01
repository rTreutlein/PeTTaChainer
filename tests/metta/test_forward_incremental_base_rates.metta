!(import! &self ../../pettachainer/metta/petta_chainer)

;; These tests intentionally request the full-KB special case by selecting all
;; current canonical facts. The forward chainer itself has no global-KB mode.
(: test-main-facts
   (-[det]-> KB
      (List (Statement KBContext Proof TV))))
(= (test-main-facts $kb)
   (collapse
      (match &kb
         ($type ($kb MAIN Nil) $prf $tv)
         (assemble-stored-runtime-fact
            $type ($kb MAIN Nil) $prf $tv))))

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

;; A forward run returns the values of the keys it built on.
(: result-for (-[det]-> Atom (List (Statement KBContext Proof TV)) (List Atom)))
(= (result-for $_type ()) ())
(= (result-for $type (cons ($statement $_kbctx $proof $tv) $rest))
   (if (== $statement $type) (cons ($proof $tv) ()) (result-for $type $rest)))

;; A fact produced by the forward chainer is only a cached derivation.  When
;; backward chaining rediscovers the same rule path, both views must carry the
;; same evidence so the result is not revised with itself.
!(compileadd forwardBackwardDedupKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBackwardDedupKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd forwardBackwardDedupKb (: pb (P bob) (STV 0.7 0.8)))

!(forward-chain 20 forwardBackwardDedupKb
   (test-main-facts forwardBackwardDedupKb))
;; Remove the cheap forward estimates so the query reads the complete folds.
;; Forward and backward share the skeleton, so the query reads the one
;; inversion. The forward run already derived P(alice) through the P base
;; rate; the rate does not count that version, so the answer matches a query
;; without the run.
!(clear-base-rate forwardBackwardDedupKb (P $x))
!(clear-base-rate forwardBackwardDedupKb (Q $x))

!(test
   (query 200 forwardBackwardDedupKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu cpu)
       qa)
      (P alice)
      (STV 0.7361612357845151 0.0003604274173100072)))

;; Revising an input changes its key's value, so a later run that takes it
;; carries the change to the rules downstream.
!(compileadd forwardRevisionKb (: p1 (P a) (STV 0.2 0.5)))
!(compileadd forwardRevisionKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd forwardRevisionKb
   (: qToR
      (Implication (Q $x) (R $x))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(forward-chain 20 forwardRevisionKb
   (test-main-facts forwardRevisionKb))
!(compileadd forwardRevisionKb (: p2 (P a) (STV 0.8 0.5)))

!(test
   (result-for (R a) (forward-chain 20 forwardRevisionKb (test-main-facts forwardRevisionKb)))
   (((by qToR (by pToQ (merge/revision p2 p1))) (STV 0.5 0.6666665676407715))))

;; Two independent derivations of Q revise; revising one of their inputs
;; reaches Q's value, which is the value a query reads.
!(compileadd forwardFrontierKb (: frontierP1 (P a) (STV 0.2 0.5)))
!(compileadd forwardFrontierKb (: frontierS1 (S a) (STV 0.7 0.6)))
!(compileadd forwardFrontierKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd forwardFrontierKb
   (: sToQ
      (Implication (S $x) (Q $x))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(forward-chain 20 forwardFrontierKb
   (test-main-facts forwardFrontierKb))
!(compileadd forwardFrontierKb (: frontierP2 (P a) (STV 0.8 0.5)))

!(test
   (let $forward (result-for (Q a) (forward-chain 20 forwardFrontierKb (test-main-facts forwardFrontierKb)))
      (== $forward
         (case (collapse (query 200 forwardFrontierKb (: $p (Q a) $tv))) (
            ((cons (: $qp $_t $qv) $_more) (cons ($qp $qv) ()))
            (() ())))))
   true)

!(remove-compiled-statement frontierP2)

;; frontierP2 is gone; P a keeps frontierP1 and the weak inversion from Q a,
;; which S a supports through sToQ.
!(test
   (query 200 forwardFrontierKb (: $prf (P a) $tv))
   (: (merge/revision frontierP1 ((inverted pToQ with cpu cpu) (by sToQ frontierS1)))
      (P a) (STV 0.2000713979305293 0.5002232242766069)))

;; Adding evidence can raise an antecedent's confidence while moving its
;; strength toward an implication branch with much greater uncertainty.  The
;; derived confidence then decreases.  The change must still be taken, and the
;; lower-confidence Q value must propagate through qToR.
!(compileadd forwardLowerConfidenceKb (: p1 (P a) (STV 0.9 0.8)))
!(compileadd forwardLowerConfidenceKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.5 0.1))))
!(compileadd forwardLowerConfidenceKb
   (: qToR
      (Implication (Q $x) (R $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (result-for (R a) (forward-chain 20 forwardLowerConfidenceKb (test-main-facts forwardLowerConfidenceKb)))
   (((by qToR (by pToQ p1)) (STV 0.77 0.8204934934752165))))

!(compileadd forwardLowerConfidenceKb (: p2 (P a) (STV 0.1 0.8)))

!(test
   (result-for (R a) (forward-chain 20 forwardLowerConfidenceKb (test-main-facts forwardLowerConfidenceKb)))
   (((by qToR (by pToQ (merge/revision p2 p1))) (STV 0.65 0.2869444474025344))))

;; Compiler-generated base-rate folds register additive sufficient statistics.
;; Forward chaining updates those statistics only for canonical outputs it
;; actually processes and exposes the result as a provisional cache entry.
!(compileadd forwardBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBaseRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd forwardBaseRateKb (: pb (P bob) (STV 0.7 0.8)))
!(forward-chain 20 forwardBaseRateKb
   (test-main-facts forwardBaseRateKb))

!(test
   (cached-base-rate forwardBaseRateKb (P $x))
   ((STV 0.6999999999999998 0.0009990009990009992)))

;; What forward chaining keeps is the base rate's one estimate, which backward
;; folds update too.
!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries forwardBaseRateKb (P $x)))
      $source)
   computed)

!(test
   (cached-base-rate forwardBaseRateKb (Q $x))
   ((STV 0.7382770346341803 0.0020863193128742123)))

;; A query's fold updates the same estimate. The forward run's inverted
;; P(alice) was derived through the P base rate, which does not count it.
!(test
   (query 200 forwardBaseRateKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu cpu) qa)
      (P alice)
      (STV 0.7361612357845151 0.0003604274173100072)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries forwardBaseRateKb (P $x)))
      $source)
   computed)

;; compileadd registers accumulator interests but performs no forward work.
;; With an explicit one-step seed, exactly that canonical fact contributes;
;; a second one-step seed adds the second fact and nothing else.
!(compileadd forwardBudgetBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBudgetBaseRateKb (: high (P high) (STV 0.9 0.9)))
!(compileadd forwardBudgetBaseRateKb (: low (P low) (STV 0.1 0.2)))

!(test (cached-base-rate forwardBudgetBaseRateKb (P $x)) ())

!(forward-chain 1 forwardBudgetBaseRateKb
   (test-selected-facts forwardBudgetBaseRateKb (P high)))

!(test
   (cached-base-rate forwardBudgetBaseRateKb (P $x))
   ((STV 0.9 0.0011237357972281184)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id
                  (forward-output-key
                     (forwardBudgetBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   1)

!(forward-chain 1 forwardBudgetBaseRateKb
   (test-selected-facts forwardBudgetBaseRateKb (P low)))

!(test
   (cached-base-rate forwardBudgetBaseRateKb (P $x))
   ((STV 0.7545454545454545 0.0013731119710398204)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id
                  (forward-output-key
                     (forwardBudgetBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   2)

;; A user base rate is authoritative.  Fact processing may maintain internal
;; sufficient statistics, but it must not replace or duplicate the user row.
!(compileadd forwardUserBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(set-base-rate forwardUserBaseRateKb (P $x) (STV 0.42 0.75))
!(compileadd forwardUserBaseRateKb (: pa (P a) (STV 0.9 0.9)))
!(forward-chain 20 forwardUserBaseRateKb
   (test-main-facts forwardUserBaseRateKb))

!(test
   (base-rate-cache-entries forwardUserBaseRateKb (P $x))
   ((base-rate forwardUserBaseRateKb (P $x)
      (STV 0.42 0.75) user any)))

;; Inheritance base rates use the same incremental path, with subject/universe
;; mass and the configured concept prior applied when the accumulator finishes.
!(set-concept-prior-confidence forwardInheritanceBaseRateKb 0.5)
!(compileadd forwardInheritanceBaseRateKb
   (: ravenBird (Inheritance Raven Bird) (STV 1.0 0.9)))
!(compileadd forwardInheritanceBaseRateKb
   (: penguinBird (Inheritance Penguin Bird) (STV 1.0 0.9)))
!(forward-chain 50 forwardInheritanceBaseRateKb
   (test-main-facts forwardInheritanceBaseRateKb))

!(test
   (cached-base-rate
      forwardInheritanceBaseRateKb (Inheritance $x Bird))
   ((STV 0.33408249053148537 0.5002810918858142)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries
            forwardInheritanceBaseRateKb (Inheritance $x Bird)))
      $source)
   computed)

!(test
   (query 100 forwardInheritanceBaseRateKb
      (: $proof (Inheritance Raven Penguin) $tv))
   (: (inheritance-implication-fold
          (total-implication
             ((inverted (inheritance-implication penguinBird) with cpu cpu)
                (by (inheritance-implication ravenBird) (ctx proof 0)))
             ((inverted (inheritance-implication penguinBird) with cpu cpu)
                (by (inheritance-implication ravenBird) (ctx proof 1)))))
      (Inheritance Raven Penguin)
      (STV 0.9977391124912127 1.0e-06)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries
            forwardInheritanceBaseRateKb (Inheritance $x Bird)))
      $source)
   computed)

;; A computed ordinary snapshot keeps that source across a later selected
;; forward delta. compileadd records the fact but does not rewrite the cache;
;; one seeded forward step patches the harvested statistics and republishes.
!(compileadd computedForwardBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd computedForwardBaseRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd computedForwardBaseRateKb (: pb (P bob) (STV 0.7 0.8)))

!(test
   (query 200 computedForwardBaseRateKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu cpu)
       qa)
      (P alice)
      (STV 0.7361612357845151 0.0003604274173100072)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id
                  (forward-output-key
                     (computedForwardBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   1)

!(compileadd computedForwardBaseRateKb (: pc (P carol) (STV 0.3 0.8)))

!(test
   (cached-base-rate computedForwardBaseRateKb (P $x))
   ((STV 0.6999999999999998 0.0009990009990009992)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id
                  (forward-output-key
                     (computedForwardBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   1)

!(forward-chain 1 computedForwardBaseRateKb
   (test-selected-facts computedForwardBaseRateKb (P carol)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

;; The run's evaluation recomputes the P fold that the new fact made stale. The
;; earlier query's inverted P(alice) was derived through this fold, so the one
;; tally holds bob and carol only.
!(test
   (cached-base-rate computedForwardBaseRateKb (P $x))
   ((STV 0.49999999999999994 0.0019960079840319364)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            (forward-aggregate-observation
               ($_id
                  (forward-output-key
                     (computedForwardBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   2)
