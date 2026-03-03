!(import! &self petta_chainer)

!(compileadd fwdkb (: edgeAB (Edge A B) (STV 1.0 1.0)))

!(compileadd fwdkb (: edgeBC (Edge B C) (STV 1.0 1.0)))

!(compileadd fwdkb
   (: edgeToPath (Implication (Premises (Edge $x $y)) (Conclusions (Path $x $y))) (STV 1.0 1.0)))

!(compileadd fwdkb
   (: pathStep (Implication (Premises (Path $x $y) (Edge $y $z)) (Conclusions (Path $x $z))) (STV 1.0 1.0)))

!(compileadd fwdkb
   (: pathIdempotent (Implication (Premises (Path $x $y)) (Conclusions (Path $x $y))) (STV 1.0 1.0)))

!(test (let $_ (forward-chain 50 fwdkb) (forward-has-derived? fwdkb (Path A C))) true)

!(test
   (let*
      (($_ (forward-chain 50 fwdkb))
        ($proofs (collapse (match &kb (: (fwdkb MAIN Nil) $prf (Path A C) $tv) $prf))))
      (list-count $proofs))
   1)

!(compileadd loopkb (: seedLoop (Loop Start) (STV 1.0 1.0)))

!(compileadd loopkb
   (: keepLoop (Implication (Premises (Loop $x)) (Conclusions (Loop $x))) (STV 1.0 1.0)))

!(test
   (let*
      (($_ (forward-chain 200 loopkb))
        ($proofs (collapse (match &kb (: (loopkb MAIN Nil) $prf (Loop Start) $tv) $prf))))
      (list-count $proofs))
   1)

!(compileadd mergekb (: weakFact (WeakPremise) (STV 1.0 0.1)))

!(compileadd mergekb (: baseFact (BasePremise) (STV 1.0 1.0)))

!(compileadd mergekb
   (: ruleHighThenDrop (Implication (Premises (WeakPremise) (BasePremise)) (Conclusions (SwitchGoal))) (STV 1.0 0.9)))

!(compileadd mergekb
   (: ruleStable (Implication (Premises (BasePremise)) (Conclusions (SwitchGoal))) (STV 1.0 0.7)))

!(test
   (let*
      (($_ (forward-chain 50 mergekb))
        ($merged
           (collapse
              (match &kb (: (mergekb MAIN Nil) (merge/revision $p1 $p2) (SwitchGoal) $tv)
                 true))))
      (== $merged ()))
   true)

!(test
   (let*
      (($_ (forward-chain 50 mergekb))
        ($proofs (collapse (match &kb (: (mergekb MAIN Nil) $prf (SwitchGoal) $tv) $prf))))
      (list-count $proofs))
   1)
