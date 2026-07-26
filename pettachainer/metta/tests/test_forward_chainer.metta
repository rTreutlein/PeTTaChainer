!(import! &self ../petta_chainer)

;; Forward chaining consumes canonical compiled facts. Tests that want to
;; select by surface type do that explicitly outside the chainer.
(: test-selected-facts
   (-[det]-> KB Statement
      (List (Statement KBContext Proof TV))))
(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $prf $tv)))))

!(compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))

!(compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))

!(compileadd fwdkb
   (: edgeToPath (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd fwdkb
   (: pathStep (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd fwdkb
   (: pathIdempotent (Implication (Premises (Path $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let $changed (forward-chain 50 fwdkb (test-selected-facts fwdkb (Edge A B)))
      (and (== (list-count $changed) 3)
         (forward-has-derived? fwdkb (Path A C))))
   true)

;; A run returns each changed output once, using its final canonical proof.
;; Reprocessing the same seed without new evidence changes nothing.
!(test (forward-chain 50 fwdkb (test-selected-facts fwdkb (Edge A B))) ())

!(test
   (let*
      (($proofs
           (collapse
              (match &kb
                 ((Path A C) (fwdkb MAIN Nil) $prf $_tv)
                 (brand Proof $prf)))))
      (list-count $proofs))
   1)

!(compileadd loopkb (: seedLoop (Loop Start) (STV 1.0 1.0)))

!(compileadd loopkb
   (: keepLoop (Implication (Premises (Loop $x)) (Conclusions (Loop $x))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let*
      (($_ (forward-chain 200 loopkb (test-selected-facts loopkb (Loop Start))))
       ($proofs
           (collapse
              (match &kb
                 ((Loop Start) (loopkb MAIN Nil) $prf $_tv)
                 (brand Proof $prf)))))
      (list-count $proofs))
   1)

;; A longer idempotent derivation overlaps the direct seed, but it is not a
;; refinement of the same rule application and must not evict that seed.
!(test
   (collapse
      (match &kb
         ((Loop Start) (loopkb MAIN Nil) $prf $_tv)
         $prf))
   (seedLoop))

!(compileadd mergekb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd mergekb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd mergekb
   (: ruleHighThenDrop (Implication (Premises (WeakPremise) (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd mergekb
   (: ruleStable (Implication (Premises (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test
   (let*
      (($_ (forward-chain 50 mergekb (test-selected-facts mergekb (BasePremise))))
        ($merged
           (collapse
              (match &kb
                 ((SwitchGoal) (mergekb MAIN Nil)
                    (merge/revision $_p1 $_p2) $_tv)
                 true))))
      (== $merged ()))
   true)

!(test
   (let*
      (($_ (forward-chain 50 mergekb (test-selected-facts mergekb (BasePremise))))
        ($ev-ok
           (collapse
              (match &kb
                 ((SwitchGoal) (mergekb MAIN Nil) $prf $tv)
                 (==
                    (proof-atom-evidence-set
                       (assemble-runtime-fact
                          (brand Statement (SwitchGoal))
                          (brand KBContext (mergekb MAIN Nil))
                          (brand Proof $prf)
                          (the TV $tv)))
                    (baseFact))))))
      (not (== $ev-ok ())))
   true)

!(test
   (let*
      (($_ (forward-chain 50 mergekb (test-selected-facts mergekb (BasePremise))))
        ($proofs
           (collapse
              (match &kb
                 ((SwitchGoal) (mergekb MAIN Nil) $prf $_tv)
                 (brand Proof $prf)))))
      (list-count $proofs))
   1)

!(compileadd deltakb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd deltakb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd deltakb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (DeltaGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 1 deltakb (test-selected-facts deltakb (HighPriority))) (forward-has-derived? deltakb (DeltaGoal))) false)

;; Exhausted work is not retained. Selecting the same irrelevant seed again
;; cannot resume a discarded global agenda.
!(test (let $_ (forward-chain 1 deltakb (test-selected-facts deltakb (HighPriority))) (forward-has-derived? deltakb (DeltaGoal))) false)

!(test (let $_ (forward-chain 1 deltakb (test-selected-facts deltakb (LowPriority))) (forward-has-derived? deltakb (DeltaGoal))) true)

!(compileadd selectedkb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd selectedkb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd selectedkb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (SelectedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 1 selectedkb (test-selected-facts selectedkb (LowPriority))) (forward-has-derived? selectedkb (SelectedGoal))) true)

!(compileadd factseedkb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd factseedkb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd factseedkb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (FactSeedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let*
      (($facts
          (collapse
             (match &kb
                ((LowPriority) (factseedkb MAIN Nil) $prf $tv)
                (assemble-stored-runtime-fact
                   (LowPriority)
                   (factseedkb MAIN Nil)
                   $prf $tv))))
        ($_ (forward-chain 1 factseedkb $facts)))
      (forward-has-derived? factseedkb (FactSeedGoal)))
   true)

!(compileadd ruleaddkb (: oldSeed (RuleSeed) (STV 1.0 1.0)))

!(test (let $_ (forward-chain 1 ruleaddkb (test-selected-facts ruleaddkb (RuleSeed))) (forward-has-derived? ruleaddkb (RuleAddGoal))) false)

!(compileadd ruleaddkb
   (: seedToGoal (Implication (Premises (RuleSeed)) (Conclusions (RuleAddGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Adding a rule does not schedule old facts globally. The caller explicitly
;; selects the existing fact that should activate the new rule.
!(test (let $_ (forward-chain 2 ruleaddkb (test-selected-facts ruleaddkb (RuleSeed))) (forward-has-derived? ruleaddkb (RuleAddGoal))) true)

!(compileadd dedupekb (: dedupeSeed (DedupeSeed) (STV 1.0 0.4)))

!(compileadd dedupekb
   (: dedupeRule (Implication (Premises (DedupeSeed)) (Conclusions (DedupeGoal))) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))

!(test
   (let*
      (($_ (forward-chain 10 dedupekb (test-selected-facts dedupekb (DedupeSeed))))
        ($cpu-call-tvs
           (collapse (match &kb ((DedupeGoal) (dedupekb MAIN Nil) $prf (cpu-call $steps $fun $args)) true))))
      (== $cpu-call-tvs ()))
   true)
