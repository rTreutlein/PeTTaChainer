!(import! &self ../petta_chainer)

!(test (rule-marginal-score no-current 0.42) 0.42)

!(compileadd kb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd kb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd kb
   (: ruleHighThenDrop (Implication (And (WeakPremise) (BasePremise)) (SwitchGoal)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd kb
   (: ruleStable (Implication (BasePremise) (SwitchGoal)) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test
   (query 10 kb (: $prf (SwitchGoal) $tv))
   (: (merge/revision (by ruleStable baseFact) (by ruleHighThenDrop (conjunction weakFact baseFact))) (SwitchGoal) (STV 1.0 0.7094641445679878)))

!(test
   (query 30 kb
      (: (by ruleHighThenDrop (conjunction weakFact baseFact))
         (SwitchGoal)
         (STV 1.0 0.1)))
   ())

!(test (query 0 kb (: $prf (SwitchGoal) $tv)) ())

!(test (query 4 kb (: $prf (SwitchGoal) $tv))
   (: (by ruleStable baseFact) (SwitchGoal) (STV 1.0 0.699950950923023)))

!(test (query 7 kb (: $prf (SwitchGoal) $tv))
   (: (merge/revision (by ruleStable baseFact) (by ruleHighThenDrop (conjunction weakFact baseFact))) (SwitchGoal) (STV 1.0 0.7094641445679878)))

!(test (query 100 kb (: $prf (SwitchGoal) $tv))
   (: (merge/revision (by ruleStable baseFact) (by ruleHighThenDrop (conjunction weakFact baseFact))) (SwitchGoal) (STV 1.0 0.7094641445679878)))

!(compileadd priorityStrengthKb (: weakInput (WeakInput) (STV 0.2 1.0)))

!(compileadd priorityStrengthKb (: strongInput (StrongInput) (STV 0.8 1.0)))

!(compileadd priorityStrengthKb
   (: weakRule (Implication (WeakInput) (StrengthPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityStrengthKb
   (: strongRule (Implication (StrongInput) (StrengthPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 2 priorityStrengthKb (: $prf (StrengthPriorityGoal) $tv))
   (: (by strongRule strongInput) (StrengthPriorityGoal) (STV 0.8 0.9999000095740854)))

!(test (query 3 priorityStrengthKb (: $prf (StrengthPriorityGoal) $tv))
   (: (by strongRule strongInput) (StrengthPriorityGoal) (STV 0.8 0.9999000095740854)))

!(compileadd chainedPriorityKb (: weakEvidence (WeakEvidence) (STV 0.2 1.0)))

!(compileadd chainedPriorityKb (: strongEvidence (StrongEvidence) (STV 0.8 1.0)))

!(compileadd chainedPriorityKb
   (: weakToA (Implication (WeakEvidence) (AForPriority)) (CTV (STV 0.1 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: strongToA (Implication (StrongEvidence) (AForPriority)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: aToGoal (Implication (AForPriority) (ChainedPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 4 chainedPriorityKb (: $prf (ChainedPriorityGoal) $tv))
   (: (by aToGoal (by strongToA strongEvidence)) (ChainedPriorityGoal) (STV 0.8 0.9998999995760428)))

!(test (query 5 chainedPriorityKb (: $prf (ChainedPriorityGoal) $tv))
   (: (by aToGoal (by strongToA strongEvidence)) (ChainedPriorityGoal) (STV 0.8 0.9998999995760428)))

!(compileadd priorityNegKb (: highInput (HighInput) (STV 0.9 1.0)))

!(compileadd priorityNegKb (: lowInput (LowInput) (STV 0.1 1.0)))

!(compileadd priorityNegKb
   (: highNegRule (Implication (Not (HighInput)) (NegPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityNegKb
   (: lowNegRule (Implication (Not (LowInput)) (NegPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 3 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (by lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 0.999900009088072)))

!(test (query 4 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (by lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 0.999900009088072)))

!(test (query 5 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (by lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 0.999900009088072)))

!(compileadd incumbentPriorityKb (: directB (IncumbentB) (STV 1.0 0.9)))

!(compileadd incumbentPriorityKb (: directA (IncumbentA) (STV 1.0 1.0)))

!(compileadd incumbentPriorityKb (: directC (IncumbentC) (STV 1.0 1.0)))

!(compileadd incumbentPriorityKb
   (: bToGoal
      (Implication (IncumbentB) (IncumbentGoal))
      (CTV (STV 1.0 0.99) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: dToGoal
      (Implication (IncumbentD) (IncumbentGoal))
      (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: aToB
      (Implication (IncumbentA) (IncumbentB))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: cToD
      (Implication (IncumbentC) (IncumbentD))
      (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test (query 2 incumbentPriorityKb (: $prf (IncumbentGoal) $tv))
   (: (by bToGoal directB) (IncumbentGoal) (STV 1.0 0.8918896597655677)))

!(test (query 7 incumbentPriorityKb (: $prf (IncumbentGoal) $tv))
   (: (merge/revision (by bToGoal directB) (by dToGoal (by cToD directC))) (IncumbentGoal) (STV 1.0 0.9039912235037112)))

!(test
   (query 7 incumbentPriorityKb
      (: (merge/revision (by bToGoal (by aToB directA)) $_other)
         (IncumbentGoal)
         $tv))
   ())
