!(import! &self petta_chainer)

!(compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))

!(compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))

!(compileadd fwdkb
   (: edgeToPath (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd fwdkb
   (: pathStep (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd fwdkb
   (: pathIdempotent (Implication (Premises (Path $x $y)) (Conclusions (Path $x $y))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 50 fwdkb) (forward-has-derived? fwdkb (Path A C))) true)

!(test
   (let*
      (($_ (forward-chain 50 fwdkb))
        ($proofs (collapse (match &kb ((Path A C) (fwdkb MAIN Nil) $prf $tv) $prf))))
      (list-count $proofs))
   1)

!(compileadd loopkb (: seedLoop (Loop Start) (STV 1.0 1.0)))

!(compileadd loopkb
   (: keepLoop (Implication (Premises (Loop $x)) (Conclusions (Loop $x))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let*
      (($_ (forward-chain 200 loopkb))
        ($proofs (collapse (match &kb ((Loop Start) (loopkb MAIN Nil) $prf $tv) $prf))))
      (list-count $proofs))
   1)

!(compileadd mergekb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd mergekb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd mergekb
   (: ruleHighThenDrop (Implication (Premises (WeakPremise) (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd mergekb
   (: ruleStable (Implication (Premises (BasePremise)) (Conclusions (SwitchGoal))) (CTV (STV 1.0 0.7) (STV 0.0 1.0))))

!(test
   (let*
      (($_ (forward-chain 50 mergekb))
        ($merged (collapse (match &kb ((SwitchGoal) (mergekb MAIN Nil) (merge/revision $p1 $p2) $tv) true))))
      (== $merged ()))
   true)

!(test
   (let*
      (($_ (forward-chain 50 mergekb))
        ($ev-ok
           (collapse
              (match &kb ((SwitchGoal) (mergekb MAIN Nil) $prf $tv)
                 (== (proof-atom-evidence-set ((SwitchGoal) (mergekb MAIN Nil) $prf $tv)) (baseFact))))))
      (not (== $ev-ok ())))
   true)

!(test
   (let*
      (($_ (forward-chain 50 mergekb))
        ($proofs (collapse (match &kb ((SwitchGoal) (mergekb MAIN Nil) $prf $tv) $prf))))
      (list-count $proofs))
   1)

!(compileadd deltakb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd deltakb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd deltakb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (DeltaGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 1 deltakb) (forward-has-derived? deltakb (DeltaGoal))) false)

!(test (let $_ (forward-chain 1 deltakb) (forward-has-derived? deltakb (DeltaGoal))) true)

!(compileadd selectedkb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd selectedkb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd selectedkb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (SelectedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain-from 1 selectedkb (LowPriority)) (forward-has-derived? selectedkb (SelectedGoal))) true)

!(compileadd factseedkb (: highFact (HighPriority) (STV 1.0 1.0)))

!(compileadd factseedkb (: lowFact (LowPriority) (STV 1.0 0.8)))

!(compileadd factseedkb
   (: lowToGoal (Implication (Premises (LowPriority)) (Conclusions (FactSeedGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let*
      (($facts (collapse (match &kb ((LowPriority) (factseedkb MAIN Nil) $prf $tv) ((LowPriority) (factseedkb MAIN Nil) $prf $tv))))
        ($_ (forward-chain-from-facts 1 factseedkb $facts)))
      (forward-has-derived? factseedkb (FactSeedGoal)))
   true)

!(compileadd ruleaddkb (: oldSeed (RuleSeed) (STV 1.0 1.0)))

!(test (let $_ (forward-chain 1 ruleaddkb) (forward-has-derived? ruleaddkb (RuleAddGoal))) false)

!(compileadd ruleaddkb
   (: seedToGoal (Implication (Premises (RuleSeed)) (Conclusions (RuleAddGoal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 2 ruleaddkb) (forward-has-derived? ruleaddkb (RuleAddGoal))) true)

!(compileadd dedupekb (: dedupeSeed (DedupeSeed) (STV 1.0 0.4)))

!(compileadd dedupekb
   (: dedupeRule (Implication (Premises (DedupeSeed)) (Conclusions (DedupeGoal))) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))

!(test (forward-agenda-dirty? dedupekb) true)

!(test
   (let*
      (($_ (forward-chain 10 dedupekb))
        ($cpu-call-tvs
           (collapse (match &kb ((DedupeGoal) (dedupekb MAIN Nil) $prf (cpu-call $steps $fun $args)) true))))
      (== $cpu-call-tvs ()))
   true)
