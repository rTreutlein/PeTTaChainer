!(import! &self petta_chainer)

;; Facts used by competing rules.
!(compileadd kb (: weakFact (WeakPremise) (STV 1.0 0.1)))
!(compileadd kb (: baseFact (BasePremise) (STV 1.0 1.0)))

;; Rule with higher initial confidence, but two premises.
;; After proving WeakPremise first, this candidate drops to 0.1.
!(compileadd kb (: ruleHighThenDrop
    (Implication
        (Premises
            (WeakPremise)
            (BasePremise))
        (Conclusions
            (SwitchGoal)))
    (STV 1.0 0.9)))

;; Competing rule with lower initial confidence, but stable one-premise path.
!(compileadd kb (: ruleStable
    (Implication
        (Premises
            (BasePremise))
        (Conclusions
            (SwitchGoal)))
    (STV 1.0 0.7)))

!(test
    (let (: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7))
         (superpose (collapse (query 30 kb (: $prf (SwitchGoal) $tv))))
         true)
    true)

!(test
    (let (: (ruleHighThenDrop (conjunction weakFact baseFact)) (SwitchGoal) (STV 1.0 0.1))
         (superpose (collapse (query 30 kb (: $prf (SwitchGoal) $tv))))
         true)
    true)

!(test
    (collapse (query 0 kb (: $prf (SwitchGoal) $tv)))
    ())

!(test
    (collapse (query 4 kb (: $prf (SwitchGoal) $tv)))
    ((: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7))))

!(test
    (collapse (query 7 kb (: $prf (SwitchGoal) $tv)))
    ((: (ruleStable baseFact) (SwitchGoal) (STV 1.0 0.7)) (: (ruleHighThenDrop (conjunction weakFact baseFact)) (SwitchGoal) (STV 1.0 0.1))))

