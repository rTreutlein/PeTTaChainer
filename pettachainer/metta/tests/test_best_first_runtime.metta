!(import! &self petta_chainer)

!(compileadd kb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd kb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd kb
   (: ruleHighThenDrop (Implication (Premises (WeakPremise) (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd kb
   (: ruleStable (Implication (Premises (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test
   (query 10 kb (: $prf (SwitchGoal) $tv))
   (: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7)))

!(test
   (query 30 kb
      (: (ruleHighThenDrop (conjunction weakFact baseFact))
         (SwitchGoal)
         (STV 1.0 0.1)))
   ())

!(test (query 0 kb (: $prf (SwitchGoal) $tv)) ())

!(test (query 4 kb (: $prf (SwitchGoal) $tv))
   (: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7)))

!(test (query 7 kb (: $prf (SwitchGoal) $tv))
   (: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7)))

!(test (query 100 kb (: $prf (SwitchGoal) $tv))
   (: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7)))

!(compileadd priorityStrengthKb (: weakInput (WeakInput) (STV 0.2 1.0)))

!(compileadd priorityStrengthKb (: strongInput (StrongInput) (STV 0.8 1.0)))

!(compileadd priorityStrengthKb
   (: weakRule (Implication (Premises (WeakInput)) (Conclusions (StrengthPriorityGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityStrengthKb
   (: strongRule (Implication (Premises (StrongInput)) (Conclusions (StrengthPriorityGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 2 priorityStrengthKb (: $prf (StrengthPriorityGoal) $tv))
   (: (strongRule strongInput) (StrengthPriorityGoal) (STV 0.8 1.0)))

!(test (query 3 priorityStrengthKb (: $prf (StrengthPriorityGoal) $tv))
   (: (strongRule strongInput) (StrengthPriorityGoal) (STV 0.8 1.0)))

!(compileadd chainedPriorityKb (: weakEvidence (WeakEvidence) (STV 0.2 1.0)))

!(compileadd chainedPriorityKb (: strongEvidence (StrongEvidence) (STV 0.8 1.0)))

!(compileadd chainedPriorityKb
   (: weakToA (Implication (Premises (WeakEvidence)) (Conclusions (AForPriority))) (CTV (STV 0.1 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: strongToA (Implication (Premises (StrongEvidence)) (Conclusions (AForPriority))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: aToGoal (Implication (Premises (AForPriority)) (Conclusions (ChainedPriorityGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 4 chainedPriorityKb (: $prf (ChainedPriorityGoal) $tv))
   (: (aToGoal (strongToA strongEvidence))
      (ChainedPriorityGoal)
      (STV 0.8 1.0)))

!(test (query 5 chainedPriorityKb (: $prf (ChainedPriorityGoal) $tv))
   (: (aToGoal (strongToA strongEvidence))
      (ChainedPriorityGoal)
      (STV 0.8 1.0)))

!(compileadd priorityNegKb (: highInput (HighInput) (STV 0.9 1.0)))

!(compileadd priorityNegKb (: lowInput (LowInput) (STV 0.1 1.0)))

!(compileadd priorityNegKb
   (: highNegRule (Implication (Premises (Not (HighInput))) (Conclusions (NegPriorityGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityNegKb
   (: lowNegRule (Implication (Premises (Not (LowInput))) (Conclusions (NegPriorityGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 3 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 1.0)))

!(test (query 4 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 1.0)))

!(test (query 5 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (lowNegRule (negated lowInput)) (NegPriorityGoal) (STV 0.9 1.0)))

!(compileadd incumbentPriorityKb (: directB (IncumbentB) (STV 1.0 0.9)))

!(compileadd incumbentPriorityKb (: directA (IncumbentA) (STV 1.0 1.0)))

!(compileadd incumbentPriorityKb (: directC (IncumbentC) (STV 1.0 1.0)))

!(compileadd incumbentPriorityKb
   (: bToGoal
      (Implication (Premises (IncumbentB)) (Conclusions (IncumbentGoal)))
      (CTV (STV 1.0 0.99) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: dToGoal
      (Implication (Premises (IncumbentD)) (Conclusions (IncumbentGoal)))
      (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: aToB
      (Implication (Premises (IncumbentA)) (Conclusions (IncumbentB)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd incumbentPriorityKb
   (: cToD
      (Implication (Premises (IncumbentC)) (Conclusions (IncumbentD)))
      (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test (query 2 incumbentPriorityKb (: $prf (IncumbentGoal) $tv))
   (: (bToGoal directB) (IncumbentGoal) (STV 1.0 0.9)))

!(test (query 6 incumbentPriorityKb (: $prf (IncumbentGoal) $tv))
   (: (merge/revision
        (bToGoal directB)
        (dToGoal (cToD directC)))
      (IncumbentGoal)
      (STV 1.0 0.918918918918919)))

!(test
   (query 6 incumbentPriorityKb
      (: (merge/revision (bToGoal (aToB directA)) $_other)
         (IncumbentGoal)
         $tv))
   ())
