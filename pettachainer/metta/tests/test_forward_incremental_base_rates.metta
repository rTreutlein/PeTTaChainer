!(import! &self ../petta_chainer)

;; These tests intentionally request the full-KB special case by selecting all
;; current canonical facts. The forward chainer itself has no global-KB mode.
(= (test-main-facts $kb)
   (collapse
      (match &kb
         ($type ($kb MAIN Nil) $prf $tv)
         ($type ($kb MAIN Nil) $prf $tv))))

(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            ($type ($kb MAIN Nil) $prf $tv)))))

;; A fact produced by the forward chainer is only a cached derivation.  When
;; backward chaining rediscovers the same rule path, both views must carry the
;; same evidence so the result is not revised with itself.
!(compileadd forwardBackwardDedupKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBackwardDedupKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd forwardBackwardDedupKb (: pb (P bob) (STV 0.7 0.8)))

!(forward-chain 20 forwardBackwardDedupKb
   (test-main-facts forwardBackwardDedupKb))
;; Remove the cheap forward estimates so the query exposes the complete fold
;; proof, including the forward-materialized Q(bob) path.
!(clear-base-rate forwardBackwardDedupKb (P $x))
!(clear-base-rate forwardBackwardDedupKb (Q $x))

!(test
   (query 200 forwardBackwardDedupKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with
          (foldall-proof pb)
          (foldall-proof qa (pToQ pb)))
       qa)
      (P alice)
      (STV 0.736162240263287 0.0003604307138536469)))

;; A rule derivation has a stable key based on the rule and its grounded input
;; slots.  Revising an input therefore replaces that derivation and requeues
;; its canonical output, allowing the change to reach downstream rules.
!(compileadd forwardRevisionKb (: p1 (P a) (STV 0.2 0.5)))
!(compileadd forwardRevisionKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd forwardRevisionKb
   (: qToR
      (Implication (Premises (Q $x)) (Conclusions (R $x)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(forward-chain 20 forwardRevisionKb
   (test-main-facts forwardRevisionKb))
!(compileadd forwardRevisionKb (: p2 (P a) (STV 0.8 0.5)))
!(forward-chain 20 forwardRevisionKb
   (test-main-facts forwardRevisionKb))

!(test
   (collapse
      (match &kb
         ((R a) (forwardRevisionKb MAIN Nil) $prf $tv)
         ((R a) (forwardRevisionKb MAIN Nil) $prf $tv)))
   (((R a) (forwardRevisionKb MAIN Nil)
      (qToR (pToQ (merge/revision p1 p2)))
      (STV 0.5 0.6666665676407715))))

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (Q a) (forwardRevisionKb MAIN Nil) $_fact $_ev)
            true)))
   1)

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (R a) (forwardRevisionKb MAIN Nil) $_fact $_ev)
            true)))
   1)

;; Keep only the active proof frontier.  The new pToQ result contains all of
;; the evidence of its earlier result, so it replaces that branch even though
;; the independent sToQ branch must remain available for the canonical merge.
!(compileadd forwardFrontierKb (: frontierP1 (P a) (STV 0.2 0.5)))
!(compileadd forwardFrontierKb (: frontierS1 (S a) (STV 0.7 0.6)))
!(compileadd forwardFrontierKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd forwardFrontierKb
   (: sToQ
      (Implication (Premises (S $x)) (Conclusions (Q $x)))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(forward-chain 20 forwardFrontierKb
   (test-main-facts forwardFrontierKb))
!(compileadd forwardFrontierKb (: frontierP2 (P a) (STV 0.8 0.5)))
!(forward-chain 20 forwardFrontierKb
   (test-main-facts forwardFrontierKb))

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (Q a) (forwardFrontierKb MAIN Nil) $_fact $_ev)
            true)))
   2)

!(test
   (collapse
      (match &forward_frontier
            ($_hash (Q a) (forwardFrontierKb MAIN Nil)
            ((Q a) (forwardFrontierKb MAIN Nil)
               (pToQ (merge/revision frontierP1 frontierP2)) $_tv)
            $_ev)
         true))
   (true))

!(test
   (collapse
      (match &forward_frontier
         ($_hash (Q a) (forwardFrontierKb MAIN Nil)
            ((Q a) (forwardFrontierKb MAIN Nil) (sToQ frontierS1) $_tv)
            $_ev)
         true))
   (true))

!(test
   (collapse
      (match &forward_frontier
         ($_hash (Q a) (forwardFrontierKb MAIN Nil)
            ((Q a) (forwardFrontierKb MAIN Nil) (pToQ frontierP1) $_tv)
            $_ev)
         true))
   ())

!(test
   (not (==
      (collapse
         (match &kb
            ((Q a) (forwardFrontierKb MAIN Nil)
               (merge/revision $left $right) $_tv)
            (if (or
                   (and (== $left (pToQ (merge/revision frontierP1 frontierP2)))
                        (== $right (sToQ frontierS1)))
                   (and (== $right (pToQ (merge/revision frontierP1 frontierP2)))
                        (== $left (sToQ frontierS1))))
               true
               (empty))))
      ()))
   true)

!(test
   (list-count
      (collapse
         (match &kb
            ((P a) (forwardFrontierKb MAIN Nil) $_prf $_tv)
            true)))
   1)

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (P a) (forwardFrontierKb MAIN Nil) $_fact $_ev)
            true)))
   2)

!(remove-compiled-statement frontierP2)

!(test
   (collapse
      (match &kb
         ((P a) (forwardFrontierKb MAIN Nil) $prf $tv)
         (: $prf (P a) $tv)))
   ((: frontierP1 (P a) (STV 0.2 0.5))))

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (P a) (forwardFrontierKb MAIN Nil) $_fact $_ev)
            true)))
   1)

;; Adding evidence can raise an antecedent's confidence while moving its
;; strength toward an implication branch with much greater uncertainty.  The
;; derived confidence then decreases.  The replacement must still be queued,
;; and the lower-confidence Q value must propagate through qToR.
!(compileadd forwardLowerConfidenceKb (: p1 (P a) (STV 0.9 0.8)))
!(compileadd forwardLowerConfidenceKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.5 0.1))))
!(compileadd forwardLowerConfidenceKb
   (: qToR
      (Implication (Premises (Q $x)) (Conclusions (R $x)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(forward-chain 20 forwardLowerConfidenceKb
   (test-main-facts forwardLowerConfidenceKb))

!(test
   (collapse
      (match &kb
         ((R a) (forwardLowerConfidenceKb MAIN Nil) $prf $tv)
         ((R a) (forwardLowerConfidenceKb MAIN Nil) $prf $tv)))
   (((R a) (forwardLowerConfidenceKb MAIN Nil)
      (qToR (pToQ p1))
      (STV 0.77 0.8204934934752165))))

!(compileadd forwardLowerConfidenceKb (: p2 (P a) (STV 0.1 0.8)))
!(forward-chain 20 forwardLowerConfidenceKb
   (test-main-facts forwardLowerConfidenceKb))

!(test
   (collapse
      (match &kb
         ((R a) (forwardLowerConfidenceKb MAIN Nil) $prf $tv)
         ((R a) (forwardLowerConfidenceKb MAIN Nil) $prf $tv)))
   (((R a) (forwardLowerConfidenceKb MAIN Nil)
      (qToR (pToQ (merge/revision p1 p2)))
      (STV 0.65 0.2869444474025344))))

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (Q a) (forwardLowerConfidenceKb MAIN Nil) $_fact $_ev)
            true)))
   1)

!(test
   (list-count
      (collapse
         (match &forward_frontier
            ($_hash (R a) (forwardLowerConfidenceKb MAIN Nil) $_fact $_ev)
            true)))
   1)

;; Compiler-generated base-rate folds register additive sufficient statistics.
;; Forward chaining updates those statistics only for canonical outputs it
;; actually processes and exposes the result as a provisional cache entry.
!(compileadd forwardBaseRateKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardBaseRateKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd forwardBaseRateKb (: pb (P bob) (STV 0.7 0.8)))
!(forward-chain 20 forwardBaseRateKb
   (test-main-facts forwardBaseRateKb))

!(test
   (cached-base-rate forwardBaseRateKb (P $x))
   ((STV 0.6999999999999998 0.0009990009990009992)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom (base-rate-cache-entries forwardBaseRateKb (P $x)))
      $source)
   forward-approx)

!(test
   (cached-base-rate forwardBaseRateKb (Q $x))
   ((STV 0.7382770346341803 0.0020863193128742123)))

;; A full backward fold remains authoritative.  It refines the provisional
;; estimate and upgrades the cache source even when the TV itself is unchanged.
!(test
   (query 200 forwardBaseRateKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with cpu cpu) qa)
      (P alice)
      (STV 0.736162240263287 0.0003604307138536469)))

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
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
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
         (match &forward_base_rate_observation
            (($_id ((forwardBudgetBaseRateKb MAIN Nil) (P $_which)))
               $_fact $_weight $_count)
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
         (match &forward_base_rate_observation
            (($_id ((forwardBudgetBaseRateKb MAIN Nil) (P $_which)))
               $_fact $_weight $_count)
            true)))
   2)

;; A user base rate is authoritative.  Fact processing may maintain internal
;; sufficient statistics, but it must not replace or duplicate the user row.
!(compileadd forwardUserBaseRateKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(set-base-rate forwardUserBaseRateKb (P $x) (STV 0.42 0.75))
!(compileadd forwardUserBaseRateKb (: pa (P a) (STV 0.9 0.9)))
!(forward-chain 20 forwardUserBaseRateKb
   (test-main-facts forwardUserBaseRateKb))

!(test
   (base-rate-cache-entries forwardUserBaseRateKb (P $x))
   ((base-rate forwardUserBaseRateKb (P $x)
      (STV 0.42 0.75) user any)))

;; Unlike a complete computed snapshot, a forward approximation is never
;; protected by the monotone-confidence guard: partial work may be confidently
;; wrong, so the complete fold below must replace this artificial estimate.
!(compileadd forwardApproxRefineKb
   (: pToQ
      (Implication (Premises (P $x)) (Conclusions (Q $x)))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd forwardApproxRefineKb (: qa (Q alice) (STV 0.9 0.8)))
!(compileadd forwardApproxRefineKb (: pb (P bob) (STV 0.7 0.8)))
!(store-forward-base-rate!
   forwardApproxRefineKb (P $x) (STV 0.5 0.9) base-rate)

!(test
   (query 200 forwardApproxRefineKb (: $proof (P alice) $tv))
   (: ((inverted pToQ with
          (foldall-proof pb)
          (foldall-proof qa (pToQ pb)))
       qa)
      (P alice)
      (STV 0.736162240263287 0.0003604307138536469)))

!(test
   (cached-base-rate forwardApproxRefineKb (P $x))
   ((STV 0.6999999999999998 0.0009990009990009992)))

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
   ((STV 0.9333333333333333 0.9090909090909091)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries
            forwardInheritanceBaseRateKb (Inheritance $x Bird)))
      $source)
   forward-approx)

!(test
   (query 100 forwardInheritanceBaseRateKb
      (: $proof (Inheritance Raven Penguin) $tv))
   (: (inheritance-implication-fold
          (total-implication
             ((inverted (inheritance-implication penguinBird) with cpu cpu)
                ((inheritance-implication ravenBird) (ctx proof 0)))
             ((inverted (inheritance-implication penguinBird) with cpu cpu)
                ((inheritance-implication ravenBird) (ctx proof 1)))))
      (Inheritance Raven Penguin)
      (STV 0.3571428571428571 0.4727586120223953)))

!(test
   (let (base-rate $_kb $_pattern $_tv $source $_mode)
      (car-atom
         (base-rate-cache-entries
            forwardInheritanceBaseRateKb (Inheritance $x Bird)))
      $source)
   computed)
