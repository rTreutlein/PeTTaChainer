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

;; The OR follows from the Problem estimate, which revises the definition with
;; the independent alarm inversion.
!(test
   (query 2000 orInversionConditionedMergeKb
      (: $proof
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         $tv))
   (: (by (bi-backward problemDefinition) (merge/revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) ((inverted problemRaisesAlarm with cpu cpu) currentAlarm))) (Or (LocalProblem current) (ProblemDependency current)) (STV 0.5200045678777936 0.9140643895638585)))

;; The general Problem estimate can use both the definition and the alarm.
;; The base rates count the whole population, including the derived alarm.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (merge/revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) ((inverted problemRaisesAlarm with cpu cpu) currentAlarm)) (Problem current) (STV 0.5200045678183972 0.9140643896768536)))

;; LocalProblem cannot reuse evidence that depends on itself. Its constrained
;; view retains the direct prior even though the general Problem estimate changes.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: localPrior (LocalProblem current) (STV 0.4 0.9)))
