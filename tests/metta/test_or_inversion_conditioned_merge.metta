!(import! &self ../../pettachainer/metta/petta_chainer)

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

;; OR introduction stays available alongside independent alarm inversion.
;; Consumer-specific selection preserves both branches for the global OR.
!(test
   (query 2000 orInversionConditionedMergeKb
      (: $proof
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         $tv))
   (: (merge/revision (conjunction localPrior dependencyPrior) (by (bi-backward problemDefinition) ((inverted problemRaisesAlarm with (foldall-proof h1Problem h2Problem (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior))) (foldall-proof (merge/revision currentAlarm (by problemRaisesAlarm (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)))) h1Alarm h2Alarm)) currentAlarm))) (Or (LocalProblem current) (ProblemDependency current)) (STV 0.520004534224267 0.9140643699222947)))

;; The general Problem estimate can use both the definition and the alarm.
;; The complete proof assertions retain the population evidence explicitly.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (merge/revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) ((inverted problemRaisesAlarm with (foldall-proof h1Problem h2Problem (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior))) (foldall-proof (merge/revision currentAlarm (by problemRaisesAlarm (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)))) h1Alarm h2Alarm)) currentAlarm)) (Problem current) (STV 0.5200045342242767 0.9140643697546067)))

;; LocalProblem cannot reuse evidence that depends on itself. Its constrained
;; view retains the direct prior even though the general Problem estimate changes.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: localPrior (LocalProblem current) (STV 0.4 0.9)))
