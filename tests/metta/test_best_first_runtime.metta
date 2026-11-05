!(import! &self ../../pettachainer/metta/petta_chainer)

;; The forward agenda keeps a fixed beam, independent of the remaining
;; budget; skeleton backward search uses its own expansion and row allowances.
!(test (bounded-agenda-target-size) 1000)

;; Exercise the actual pruning threshold: the older one- and two-entry heap
;; checks never entered pruning after the beam became independent of budget.
;; Native numlist supplies the fixture without a recursive MeTTa list builder.
(: pruning-test-add-number (-[det]-> (Heap Number) Number (Heap Number)))
(= (pruning-test-add-number $heap $index)
   (add_to_heap $heap $index $index))

!(test
   (let*
      (($_numbers
          (callPredicate (Predicate (numlist 1 64000 $numbers))))
       ($at-limit
          (fold-flat pruning-test-add-number
             (empty_heap)
             (the (List Number) $numbers)))
       ($over-limit (add_to_heap $at-limit 64001 64001))
       ($needed-at-limit (bounded-agenda-prune-needed? $at-limit))
       ($needed-over-limit (bounded-agenda-prune-needed? $over-limit))
       ($pruned (bounded-agenda-prune $over-limit))
       ($_disable (set-bounded-agenda-pruning false))
       ($unpruned (bounded-agenda-prune $over-limit))
       ($_enable (set-bounded-agenda-pruning true))
       (($best-priority $best-item $_rest) (heap_pop $pruned)))
      ($needed-at-limit $needed-over-limit
       (heap_size $pruned) (heap_size $unpruned)
       $best-priority $best-item))
   (false true 1000 64001 1 1))

!(compileadd kb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd kb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd kb
   (: ruleHighThenDrop (Implication (And (WeakPremise) (BasePremise)) (SwitchGoal)) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd kb
   (: ruleStable (Implication (BasePremise) (SwitchGoal)) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

;; The conjunction is a narrower class. Its strength stays 1, while its
;; confidence comes from that class; the general rule is only its prior.
!(test
   (query 10 kb (: $prf (SwitchGoal) $tv))
   (: (specializes (by ruleHighThenDrop (conjunction weakFact baseFact)) (by ruleStable baseFact) (STV 1.0 0.09887651214618275) (STV 1.0 0.7000000000000001)) (SwitchGoal) (STV 1.0 0.09887651214618275)))

!(test
   (query 30 kb
      (: (by ruleHighThenDrop (conjunction weakFact baseFact))
         (SwitchGoal)
         (STV 1.0 0.1)))
   ())

;; Completed answers survive the per-query search reset. A zero-budget query
;; can therefore read the durable proof without expanding a new frontier.
!(test (query 0 kb (: $prf (SwitchGoal) $tv))
   (: (specializes (by ruleHighThenDrop (conjunction weakFact baseFact)) (by ruleStable baseFact) (STV 1.0 0.09887651214618275) (STV 1.0 0.7000000000000001)) (SwitchGoal) (STV 1.0 0.09887651214618275)))

!(test (query 4 kb (: $prf (SwitchGoal) $tv))
   (: (specializes (by ruleHighThenDrop (conjunction weakFact baseFact)) (by ruleStable baseFact) (STV 1.0 0.09887651214618275) (STV 1.0 0.7000000000000001)) (SwitchGoal) (STV 1.0 0.09887651214618275)))

!(test (query 7 kb (: $prf (SwitchGoal) $tv))
   (: (specializes (by ruleHighThenDrop (conjunction weakFact baseFact)) (by ruleStable baseFact) (STV 1.0 0.09887651214618275) (STV 1.0 0.7000000000000001)) (SwitchGoal) (STV 1.0 0.09887651214618275)))

!(test (query 100 kb (: $prf (SwitchGoal) $tv))
   (: (specializes (by ruleHighThenDrop (conjunction weakFact baseFact)) (by ruleStable baseFact) (STV 1.0 0.09887651214618275) (STV 1.0 0.7000000000000001)) (SwitchGoal) (STV 1.0 0.09887651214618275)))

;; A completed non-root proof is a frontier input for a later bounded search.
;; Two steps suffice for the new root plus its new CPU formula because the
;; middle premise is read directly from durable history.
!(compileadd durableFrontierKb
   (: durable-frontier-seed (DurableFrontierSeed) (STV 1.0 1.0)))
!(compileadd durableFrontierKb
   (: durable-frontier-first
      (Implication (DurableFrontierSeed) (DurableFrontierMiddle))
      (CTV (STV 1.0 1.0) (STV 0.11 1.0))))
!(test
   (not
      (==
         (collapse
            (query 20 durableFrontierKb
               (: $proof (DurableFrontierMiddle) $tv)))
         ()))
   true)

!(compileadd durableFrontierKb
   (: durable-frontier-second
      (Implication (DurableFrontierMiddle) (DurableFrontierGoal))
      (CTV (STV 1.0 1.0) (STV 0.17 1.0))))
!(test
   (not
      (==
         (collapse
            (query 2 durableFrontierKb
               (: $proof (DurableFrontierGoal) $tv)))
         ()))
   true)

;; Proof and TV constraints still filter the durable index rather than leaking
;; incompatible historical results into the new query.
!(test
   (query 0 durableFrontierKb
      (: incompatible-proof (DurableFrontierMiddle) $tv))
   ())
!(test
   (query 0 durableFrontierKb
      (: $proof (DurableFrontierMiddle) (STV 0.5 0.5)))
   ())

!(compileadd priorityStrengthKb (: weakInput (WeakInput) (STV 0.2 1.0)))

!(compileadd priorityStrengthKb (: strongInput (StrongInput) (STV 0.8 1.0)))

!(compileadd priorityStrengthKb
   (: weakRule (Implication (WeakInput) (StrengthPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityStrengthKb
   (: strongRule (Implication (StrongInput) (StrengthPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Premises that are stored facts are read when a rule starts and cost no
;; expansion, so the first expansion of a goal answers with every rule whose
;; premises are facts, and small budgets already revise disjoint evidence in.
!(test (query 1 priorityStrengthKb (: $prf (StrengthPriorityGoal) $tv))
   (: (merge/revision
         (by weakRule weakInput)
         (by strongRule strongInput))
      (StrengthPriorityGoal)
      (STV 0.5 0.9999)))

!(compileadd chainedPriorityKb (: weakEvidence (WeakEvidence) (STV 0.2 1.0)))

!(compileadd chainedPriorityKb (: strongEvidence (StrongEvidence) (STV 0.8 1.0)))

!(compileadd chainedPriorityKb
   (: weakToA (Implication (WeakEvidence) (AForPriority)) (CTV (STV 0.1 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: strongToA (Implication (StrongEvidence) (AForPriority)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd chainedPriorityKb
   (: aToGoal (Implication (AForPriority) (ChainedPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 4 chainedPriorityKb (: $prf (ChainedPriorityGoal) $tv))
   (: (by aToGoal
         (merge/revision
            (by weakToA weakEvidence)
            (by strongToA strongEvidence)))
      (ChainedPriorityGoal)
      (STV 0.41000000000000003 0.9999)))

!(compileadd priorityNegKb (: highInput (HighInput) (STV 0.9 1.0)))

!(compileadd priorityNegKb (: lowInput (LowInput) (STV 0.1 1.0)))

!(compileadd priorityNegKb
   (: highNegRule (Implication (Not (HighInput)) (NegPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd priorityNegKb
   (: lowNegRule (Implication (Not (LowInput)) (NegPriorityGoal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 3 priorityNegKb (: $prf (NegPriorityGoal) $tv))
   (: (merge/revision
         (by highNegRule (negated highInput))
         (by lowNegRule (negated lowInput)))
      (NegPriorityGoal)
      (STV 0.5 0.9999)))

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
   (: (by bToGoal (factored-revision (by aToB directA) (prior (STV 1.0 1.0)) (((reported with cpu (prior (STV 0.5 0.0))) directB)))) (IncumbentGoal) (STV 1.0 0.99)))

!(test (query 7 incumbentPriorityKb (: $prf (IncumbentGoal) $tv))
   (:
      (merge/revision
         (by
            bToGoal
            (factored-revision
               (by aToB directA)
               (prior (STV 1.0 1.0))
               (((reported with cpu (prior (STV 0.5 0.0))) directB))))
         (by dToGoal (by cToD directC)))
      (IncumbentGoal)
      (STV 1.0 0.9901152601848553)))

!(test
   (query 7 incumbentPriorityKb
      (: (merge/revision (by bToGoal (by aToB directA)) $_other)
         (IncumbentGoal)
         $tv))
   ())

;; A stored answer for the goal is revised with both refinements: the
;; three-premise alternative costs no more expansions than the one-premise one,
;; because all its premises are facts.
!(compileadd refinementValueKb
   (: incumbentValueRoot (RefinementValueGoal) (STV 1.0 0.9)))
!(compileadd refinementValueKb
   (: cheapRefinementSeed (CheapRefinementSeed) (STV 1.0 1.0)))
!(compileadd refinementValueKb
   (: expensiveRefinementSeed1 (ExpensiveRefinementSeed1) (STV 1.0 1.0)))
!(compileadd refinementValueKb
   (: expensiveRefinementSeed2 (ExpensiveRefinementSeed2) (STV 1.0 1.0)))
!(compileadd refinementValueKb
   (: expensiveRefinementSeed3 (ExpensiveRefinementSeed3) (STV 1.0 1.0)))

!(compileadd refinementValueKb
   (: cheapRootRefinement
      (Implication (CheapRefinementSeed) (RefinementValueGoal))
      (CTV (STV 1.0 0.95) (STV 0.0 1.0))))
!(compileadd refinementValueKb
   (: expensiveRootRefinement
      (Implication
         (And
            (ExpensiveRefinementSeed1)
            (ExpensiveRefinementSeed2)
            (ExpensiveRefinementSeed3))
         (RefinementValueGoal))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 3 refinementValueKb (: $prf (RefinementValueGoal) $tv))
   (: (factored-revision (by expensiveRootRefinement (conjunction expensiveRefinementSeed1 expensiveRefinementSeed2 expensiveRefinementSeed3)) (prior (STV 1.0 1.0)) (((reported with cpu (prior (STV 0.5 0.0))) incumbentValueRoot))) (RefinementValueGoal) (STV 1.0 0.9999)))
