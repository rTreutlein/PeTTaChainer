!(import! &self ../petta_chainer)

;; A finite inverse-fold diagnosis. Each candidate records
;;   (identity, production loss, independent failure prior).
;; An observed loss of 5 has two explanations: pump, or valve + motor.
(: station-candidates (-[det]-> (List WeightedSubsetCandidate)))
(= (station-candidates)
   ((WeightedCandidate pump 5 0.02)
    (WeightedCandidate valve 3 0.10)
    (WeightedCandidate motor 2 0.05)))

!(compileadd stationOpsKb
   (: candidates
      (CandidateModules (station-candidates))
      (STV 1.0 1.0)))

!(compileadd stationOpsKb
   (: observed
      (ObservedTotalLoss 5)
      (STV 1.0 1.0)))

!(compileadd stationOpsKb
   (: diagnose
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

!(compileadd stationOpsKb (: pumpModule (Module pump) (STV 1.0 1.0)))
!(compileadd stationOpsKb (: valveModule (Module valve) (STV 1.0 1.0)))
!(compileadd stationOpsKb (: motorModule (Module motor) (STV 1.0 1.0)))

!(compileadd stationOpsKb
   (: projectModuleProbability
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
   (let (: $_proof (FaultSetPosterior $solutions) $_tv)
      (query 30 stationOpsKb
         (: $_proof (FaultSetPosterior $solutions) $_tv))
      (let (((Selection (pump)) $pump-weight)
            ((Selection (valve motor)) $pair-weight))
         (WeightedSubsetPairs
            (the WeightedSubsetSolutions $solutions))
         (and
            (and (> $pump-weight 0.7772) (< $pump-weight 0.7773))
            (and (> $pair-weight 0.2227) (< $pair-weight 0.2228)))))
   true)

!(test
   (let (: $_proof (FaultProbability pump $probability) $_tv)
      (query 40 stationOpsKb
         (: $_proof (FaultProbability pump $probability) $_tv))
      (let $number (the Number $probability)
         (and (> $number 0.7772) (< $number 0.7773))))
   true)

!(test
   (let (: $_proof (FaultProbability motor $probability) $_tv)
      (query 40 stationOpsKb
         (: $_proof (FaultProbability motor $probability) $_tv))
      (let $number (the Number $probability)
         (and (> $number 0.2227) (< $number 0.2228))))
   true)
