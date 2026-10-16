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
   (if (== $statement $type) (cons ((sk-full-proof $proof) $tv) ()) (result-for $type $rest)))

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
   (: ((inverted pToQ with cpu (prior (STV 0.6599999999999998 0.0009990009990009992)))
       qa)
      (P alice)
      (STV 0.8756842458979404 0.016392040302468155)))

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

;; frontierP2 is gone; P a revises frontierP1 with the inversion from Q a,
;; which S a supports through sToQ: Q holds only with P (P(Q | not P) = 0), so
;; Q a at 0.7 gives P a 0.7, at the confidence of Q a.
!(test
   (query 200 forwardFrontierKb (: $prf (P a) $tv))
   (: (merge/revision ((inverted pToQ with cpu (prior (STV 0.28571428571428575 0.0006246096189881324))) (by sToQ frontierS1)) frontierP1)
      (P a) (STV 0.5000037925526352 0.7142875453279081)))

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

;; The rule states both branches, so its inversion reads no base rate of Q.
!(test
   (cached-base-rate forwardBaseRateKb (Q $x))
   ())

;; A query's fold updates the same estimate. The forward run's inverted
;; P(alice) was derived through the P base rate, which does not count it.
!(test
   (query 200 forwardBaseRateKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) qa)
      (P alice)
      (STV 0.8756842458979404 0.016392040302468155)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries forwardBaseRateKb (P $x)))
      $source)
   computed)

;; A stored fact counts in the base rates observing it when it is added,
;; whether or not a forward run takes it: counting is bookkeeping, not
;; inference. A forward run over the facts changes nothing.
!(compileadd forwardBudgetBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBudgetBaseRateKb (: high (P high) (STV 0.9 0.9)))

!(test
   (cached-base-rate forwardBudgetBaseRateKb (P $x))
   ((STV 0.9 0.0011237357972281184)))

!(compileadd forwardBudgetBaseRateKb (: low (P low) (STV 0.1 0.2)))

!(test
   (cached-base-rate forwardBudgetBaseRateKb (P $x))
   ((STV 0.7545454545454545 0.0013731119710398204)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            ($_obs-hash
               ($_id
                  (forward-output-key
                     (forwardBudgetBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   2)

!(forward-chain 1 forwardBudgetBaseRateKb
   (test-selected-facts forwardBudgetBaseRateKb (P low)))

!(test
   (cached-base-rate forwardBudgetBaseRateKb (P $x))
   ((STV 0.7545454545454545 0.0013731119710398204)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            ($_obs-hash
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
             ((inverted (inheritance-implication penguinBird) with cpu (prior (STV 0.3333749895859368 0.5)))
                (by (inheritance-implication ravenBird) (ctx proof 0)))
             ((inverted (inheritance-implication penguinBird) with cpu (prior (STV 0.3333749895859368 0.5)))
                (by (inheritance-implication ravenBird) (ctx proof 1)))))
      (Inheritance Raven Penguin)
      (STV 0.9978639641851278 1.0e-06)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries
            forwardInheritanceBaseRateKb (Inheritance $x Bird)))
      $source)
   computed)

;; A computed ordinary snapshot keeps that source across later additions.
;; compileadd counts the new fact in the harvested statistics and republishes;
;; a seeded forward step over it changes nothing.
!(compileadd computedForwardBaseRateKb
   (: pToQ
      (Implication (P $x) (Q $x))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd computedForwardBaseRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd computedForwardBaseRateKb (: pb (P bob) (STV 0.7 0.8)))

!(test
   (query 200 computedForwardBaseRateKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu (prior (STV 0.6599999999999998 0.0009990009990009992)))
       qa)
      (P alice)
      (STV 0.8756842458979404 0.016392040302468155)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            ($_obs-hash
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
   ((STV 0.49999999999999994 0.0019960079840319364)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            ($_obs-hash
               ($_id
                  (forward-output-key
                     (computedForwardBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   2)

!(forward-chain 1 computedForwardBaseRateKb
   (test-selected-facts computedForwardBaseRateKb (P carol)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries computedForwardBaseRateKb (P $x)))
      $source)
   computed)

;; The earlier query's inverted P(alice) was derived through this fold, so
;; the one tally holds bob and carol only.
!(test
   (cached-base-rate computedForwardBaseRateKb (P $x))
   ((STV 0.49999999999999994 0.0019960079840319364)))

!(test
   (list-count
      (collapse
         (match &forward_aggregate_observation
            ($_obs-hash
               ($_id
                  (forward-output-key
                     (computedForwardBaseRateKb MAIN Nil)
                     (P $_which)))
               (forward-base-rate-observation-value $_fact)
               $_weight $_count)
            true)))
   2)

;; A fact counted in several base rates is read without its values derived
;; through any of them: the rates read here are (Leak $u $z), (Leak $u z1) and
;; (Leak u1 $z), and the exclusion holds each of them.
(: excludes-one? (-[det]-> (List Number) Number Bool))
(= (excludes-one? $folds $hash) (stored-list-member? $hash $folds))
!(compileadd ordKb (: sensor (Implication (Leak $u $z) (Alarm $u $z)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd ordKb (: narrow1 (Implication (Leak $u z1) (Seen1 $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd ordKb (: narrow2 (Implication (Leak u1 $z) (Seen2 $z)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd ordKb (: l1 (Leak u1 z1) (STV 1.0 1.0)))
!(compileadd ordKb (: l2 (Leak u2 z2) (STV 0.0 1.0)))
!(compileadd ordKb (: aq (Alarm q z1) (STV 1.0 1.0)))
!(compileadd ordKb (: s1 (Seen1 q) (STV 1.0 1.0)))
!(compileadd ordKb (: s2 (Seen2 w) (STV 1.0 1.0)))
!(collapse (query 200 ordKb (: $p (Leak q $z) $tv)))
!(collapse (query 200 ordKb (: $p (Leak q z1) $tv)))
!(collapse (query 200 ordKb (: $p (Leak u1 w) $tv)))
!(test
   (let $folds (forward-rate-folds (assemble-runtime-fact (Leak u1 z1) (ordKb MAIN Nil) l1 (STV 1.0 1.0)))
      (map-flat (excludes-one? $folds) $folds))
   (true true true))

;; A fact is excluded only from the rates it counts in: (Leak u1 z1) belongs to
;; the rate over (Leak $u z1), not to the one over (Leak $u z2), though both
;; are triggered by Leak.
!(compileadd colorKb (: red (Implication (Leak $u z1) (Seen1 $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd colorKb (: blue (Implication (Leak $u z2) (Seen2 $u)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd colorKb (: l1 (Leak u1 z1) (STV 1.0 1.0)))
!(compileadd colorKb (: l2 (Leak u2 z2) (STV 0.0 1.0)))
!(compileadd colorKb (: s1 (Seen1 q) (STV 1.0 1.0)))
!(compileadd colorKb (: s2 (Seen2 q) (STV 1.0 1.0)))
!(collapse (query 200 colorKb (: $p (Leak q z1) $tv)))
!(collapse (query 200 colorKb (: $p (Leak q z2) $tv)))
!(test
   (forward-rate-folds (assemble-runtime-fact (Leak u1 z1) (colorKb MAIN Nil) l1 (STV 1.0 1.0)))
   ((index-hash (sk-fold (colorKb (Leak $_u z1) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)))))
