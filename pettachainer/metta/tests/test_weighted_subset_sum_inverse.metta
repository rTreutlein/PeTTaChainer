!(import! &self ../petta_chainer)

(: station-candidates (-[det]-> (List WeightedSubsetCandidate)))
(= (station-candidates)
   ((WeightedCandidate pump 5 0.02)
    (WeightedCandidate valve 3 0.10)
    (WeightedCandidate motor 2 0.05)))

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
            (Compute WeightedSubsetSumInverse
               ($candidates $total)
               ->
               $solutions))
         (FaultSetPosterior $solutions))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd stationKb (: pumpModule (Module pump) (STV 1.0 1.0)))
!(compileadd stationKb (: valveModule (Module valve) (STV 1.0 1.0)))
!(compileadd stationKb (: motorModule (Module motor) (STV 1.0 1.0)))

!(compileadd stationKb
   (: projectFaultProbability
      (Implication
         (And
            (FaultSetPosterior $solutions)
            (Module $module)
            (Compute WeightedSubsetMarginal
               ($solutions $module)
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
