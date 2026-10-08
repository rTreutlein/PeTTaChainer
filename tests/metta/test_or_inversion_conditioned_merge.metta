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

;; The current alarm supplies independent evidence for Problem. Historical
;; cases provide the base rate of Problem, the prior this ordinary implication
;; is inverted over.
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
   (: h2Problem (Problem h2) (STV 0.0 1.0)))

;; The OR follows from the Problem estimate. The alarm is independent of the
;; two priors given Problem, so its inversion's likelihood ratio moves the
;; definition's odds instead of the base rate's (prior_factored_merge.md): odds
;; 0.52 / 0.48 times the stated ratio 0.9 / 0.1 give 0.907. The base rate is
;; read from two historical cases, so the confidence falls with its variance.
!(test
   (query 2000 orInversionConditionedMergeKb
      (: $proof
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         $tv))
   (: (by (bi-backward problemDefinition) (factored-revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) (prior (STV 0.52 0.9140621947055227)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5062734570069661 0.003629357526433342))) currentAlarm)))) (Or (LocalProblem current) (ProblemDependency current)) (STV 0.9069767441860467 0.013071960017362709)))

;; The general Problem estimate can use both the definition and the alarm.
;; The base rates count the whole population, including the derived alarm.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (factored-revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) (prior (STV 0.52 0.9140621947055227)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5062734570069661 0.003629357526433342))) currentAlarm))) (Problem current) (STV 0.9069767441860467 0.013071960017567873)))

;; LocalProblem cannot reuse evidence that depends on itself. Its constrained
;; view retains the direct prior even though the general Problem estimate changes.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: localPrior (LocalProblem current) (STV 0.4 0.9)))
