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
   (: (by (bi-backward problemDefinition) (factored-revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) (prior (STV 0.5199995299237518 0.9140621947055227)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm)))) (Or (LocalProblem current) (ProblemDependency current)) (STV 0.906976585290498 0.9691290850214814)))

;; The general Problem estimate can use both the definition and the alarm.
;; The base rates count the whole population, including the derived alarm.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (factored-revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) (prior (STV 0.5199995299237518 0.9140621947055227)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm))) (Problem current) (STV 0.906976585290498 0.9691290859469237)))

;; LocalProblem cannot reuse evidence that depends on itself: the general
;; Problem estimate does. The completion of the definition onto it reads the
;; alarm's inversion over Problem's base rate, which does not, with the other
;; disjunct at its value. The completion updates the stored localPrior in
;; its population prior's place (#42): odds(.4)*odds(completion)/
;; odds(.4185934569) gives .6976600101. Revision formerly drowned out
;; this diagnostic update in the stored belief's evidence count.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: (factored-revision localPrior (prior (STV 0.4000027777006194 0.9)) (((antecedent-completion (bi-forward problemDefinition) 0 with cpu (prior (STV 0.5 0.0))) (conjunction dependencyPrior ((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm))))) (LocalProblem current) (STV 0.6976768597879697 0.9110388213710066)))
