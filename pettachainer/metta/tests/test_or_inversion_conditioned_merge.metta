!(import! &self ../petta_chainer)

;; Problem is definitionally equivalent to an OR of its two causes.  The
;; generated BiImplication directions are already explicit and must not create
;; another pair of Bayesian inversions.
!(compileadd orInversionConditionedMergeKb
   (: localPrior
      (LocalProblem current)
      (STV 0.4 0.9)))
!(compileadd orInversionConditionedMergeKb
   (: dependencyPrior
      (ProblemDependency current)
      (STV 0.2 0.9)))
!(compileadd orInversionConditionedMergeKb
   (: problemDefinition
      (BiImplication
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         (Problem current))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; The current alarm supplies independent evidence for Problem.  Historical
;; cases provide the base rates needed to invert this ordinary implication.
!(compileadd orInversionConditionedMergeKb
   (: problemRaisesAlarm
      (Implication
         (Problem $unit)
         (Alarm $unit))
      (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd orInversionConditionedMergeKb
   (: currentAlarm
      (Alarm current)
      (STV 1.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h1Alarm (Alarm h1) (STV 1.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h2Alarm (Alarm h2) (STV 0.0 1.0)))

;; Ordinary OR introduction must remain available.  Conditioning compound
;; leaves globally would incorrectly reject this direct proof.
!(test
   (query 2000 orInversionConditionedMergeKb
      (: $proof
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         $tv))
   (: (conjunction localPrior dependencyPrior)
      (Or
         (LocalProblem current)
         (ProblemDependency current))
      (STV 0.52 0.9140621948732192)))

;; Problem legitimately combines the definitional prior and sensor evidence.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (merge/revision
         (by (bi-forward problemDefinition)
            (conjunction localPrior dependencyPrior))
         ((inverted problemRaisesAlarm
              with cpu (foldall-proof currentAlarm h1Alarm h2Alarm))
          currentAlarm))
      (Problem current)
      (STV 0.5200045678777936 0.9140643897315559)))

;; When the merged Problem output is consumed while proving LocalProblem, its
;; forward branch is cyclic: it was constructed from LocalProblem itself.  The
;; frontier must discard that branch before merging and retain the independent
;; sensor branch, so the alarm-conditioned proof remains reachable.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: (merge/revision
         localPrior
         ((proj 0
              (by (bi-backward problemDefinition)
                 ((inverted problemRaisesAlarm with cpu cpu)
                  currentAlarm)))
          dependencyPrior))
      (LocalProblem current)
      (STV 0.4000000227040712 0.9000000100000091)))
