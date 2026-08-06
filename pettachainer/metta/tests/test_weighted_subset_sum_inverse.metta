!(import! &self ../petta_chainer)

(: station-candidates (-[det]-> (List WeightedSubsetCandidate)))
(= (station-candidates)
   ((WeightedCandidate pump 5 0.02)
    (WeightedCandidate valve 3 0.10)
    (WeightedCandidate motor 2 0.05)))

(: repeated-unit-candidates (-[det]-> (List WeightedSubsetCandidate)))
(= (repeated-unit-candidates)
   ((WeightedCandidate c01 1 0.5)
    (WeightedCandidate c02 1 0.5)
    (WeightedCandidate c03 1 0.5)
    (WeightedCandidate c04 1 0.5)
    (WeightedCandidate c05 1 0.5)
    (WeightedCandidate c06 1 0.5)
    (WeightedCandidate c07 1 0.5)
    (WeightedCandidate c08 1 0.5)
    (WeightedCandidate c09 1 0.5)
    (WeightedCandidate c10 1 0.5)
    (WeightedCandidate c11 1 0.5)
    (WeightedCandidate c12 1 0.5)))

(: posterior-test-selected-facts
   (-[det]-> KB Statement
       (List (Statement KBContext Proof TV))))
(= (posterior-test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $proof $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $proof $tv)))))

;; The descriptive exhaustive name and original compatibility name agree.
!(test
   (EnumerateWeightedSubsetExplanations (station-candidates) 5)
   (WeightedSubsetSumInverse (station-candidates) 5))

!(test
   (let (((Selection (pump)) $pump-weight)
         ((Selection (valve motor)) $pair-weight))
      (WeightedSubsetPairs
         (WeightedSubsetSumInverse (station-candidates) 5))
      (and
         (and (> $pump-weight 0.7772) (< $pump-weight 0.7773))
         (and (> $pair-weight 0.2227) (< $pair-weight 0.2228))))
   true)

!(test
   (WeightedSubsetMarginal
      (WeightedSubsetSumInverse (station-candidates) 5)
      pump)
   0.7772727272727272)

!(test
   (let $probability
      (WeightedSubsetMarginal
         (WeightedSubsetSumInverse (station-candidates) 5)
         valve)
      (and (> $probability 0.2227) (< $probability 0.2228)))
   true)

!(test
   (let $probability
      (WeightedSubsetMarginal
         (WeightedSubsetSumInverse (station-candidates) 5)
         motor)
      (and (> $probability 0.2227) (< $probability 0.2228)))
   true)

!(test
   (WeightedSubsetMarginal
      (WeightedSubsetSumInverse (station-candidates) 5)
      sensor)
   0.0)

!(test
   (WeightedSubsetPairs
      (WeightedSubsetSumInverse (station-candidates) 4))
   ())

;; The compact DP keeps one prefix and postfix distribution at every candidate
;; boundary. No row retains either underlying fault configuration.
!(test
   (WeightedSubsetPosteriorDP (station-candidates) 5)
   (WeightedSubsetDP
      5
      ((WeightedCandidate pump 5 0.02)
       (WeightedCandidate valve 3 0.10)
       (WeightedCandidate motor 2 0.05))
      ((WeightedDPRow ((WeightedDPCell 0 1.0)))
       (WeightedDPRow
          ((WeightedDPCell 0 0.98)
           (WeightedDPCell 5 0.02)))
       (WeightedDPRow
          ((WeightedDPCell 0 0.882)
           (WeightedDPCell 3 0.098)
           (WeightedDPCell 5 0.018000000000000002)))
       (WeightedDPRow
          ((WeightedDPCell 0 0.8379)
           (WeightedDPCell 2 0.0441)
           (WeightedDPCell 3 0.0931)
           (WeightedDPCell 5 0.022000000000000002))))
      ((WeightedDPRow
          ((WeightedDPCell 0 0.8379)
           (WeightedDPCell 2 0.04410000000000001)
           (WeightedDPCell 3 0.0931)
           (WeightedDPCell 5 0.022000000000000002)))
       (WeightedDPRow
          ((WeightedDPCell 0 0.855)
           (WeightedDPCell 2 0.045000000000000005)
           (WeightedDPCell 3 0.095)
           (WeightedDPCell 5 0.005000000000000001)))
       (WeightedDPRow
          ((WeightedDPCell 0 0.95)
           (WeightedDPCell 2 0.05)))
       (WeightedDPRow ((WeightedDPCell 0 1.0))))))

!(test
   (WeightedSubsetPosteriorMass
      (WeightedSubsetPosteriorDP (station-candidates) 5))
   0.022000000000000002)

!(test
   (WeightedSubsetPosteriorMarginal
      (WeightedSubsetPosteriorDP (station-candidates) 5)
      motor)
   0.22272727272727275)

!(test
   (WeightedSubsetPosteriorMass
      (WeightedSubsetPosteriorDP (station-candidates) 4))
   0.0)

!(test
   (WeightedSubsetPosteriorMarginal
      (WeightedSubsetPosteriorDP (station-candidates) 4)
      pump)
   0.0)

;; Twelve binary choices collapse to the seven reachable loss cells 0..6,
;; rather than retaining the 2^12 underlying configurations.
!(test
   (let (WeightedSubsetDP $_target $_candidates $_prefix-rows
           (cons (WeightedDPRow $all-cells) $_postfix-rest))
      (WeightedSubsetPosteriorDP (repeated-unit-candidates) 6)
      (length $all-cells))
   7)

!(compileadd stationKb
   (: stationCandidates
      (CandidateModules (station-candidates))
      (STV 1.0 1.0)))

!(compileadd stationKb
   (: observedLoss
      (ObservedTotalLoss 5)
      (STV 1.0 1.0)))

!(compileadd stationKb
   (: diagnoseFaultSets
      (Implication
         (And
            (CandidateModules $candidates)
            (ObservedTotalLoss $total)
            (Compute WeightedSubsetPosteriorDP
               ($candidates $total)
               ->
               $posterior))
         (FaultPosterior $posterior))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd stationKb (: pumpModule (Module pump) (STV 1.0 1.0)))
!(compileadd stationKb (: valveModule (Module valve) (STV 1.0 1.0)))
!(compileadd stationKb (: motorModule (Module motor) (STV 1.0 1.0)))

!(compileadd stationKb
   (: projectFaultProbability
      (Implication
         (And
            (FaultPosterior $posterior)
            (Module $module)
            (Compute WeightedSubsetPosteriorMarginal
               ($posterior $module)
               ->
               $probability))
         (FaultProbability $module $probability))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let (: $_proof (FaultProbability pump $probability) $_tv)
      (query 40 stationKb
         (: $_proof (FaultProbability pump $probability) $_tv))
      (let $number (the Number $probability)
         (and (> $number 0.7772) (< $number 0.7773))))
   true)

!(test
   (let (: $_proof (FaultProbability valve $probability) $_tv)
      (query 40 stationKb
         (: $_proof (FaultProbability valve $probability) $_tv))
      (let $number (the Number $probability)
         (and (> $number 0.2227) (< $number 0.2228))))
   true)

;; The forward chainer consumes the same compact CPU result. Seeding the
;; candidate catalog is sufficient because the observed loss and modules are
;; already canonical KB facts used by the rule's remaining premises.
!(test
   (let*
      (($_changed
          (forward-chain 20 stationKb
             (posterior-test-selected-facts
                stationKb
                (CandidateModules (station-candidates)))))
       ($probabilities
          (collapse
             (match &kb
                ((FaultProbability pump $probability)
                   (stationKb MAIN Nil) $_proof $_tv)
                $probability))))
      $probabilities)
   (0.7772727272727272))
