!(import! &self ../../pettachainer/metta/petta_chainer)

;; PLN induction (book section 5.4): A predicts B at 0.8; C explains B
;; with likelihoods (0.9, 0.1) and prior 0.5. Both reverse branches are
;; (0.9, 0.1), so C = 0.8 * 0.9 + 0.2 * 0.1 = 0.74.
!(set-bayes-prior-count 0)

!(set-base-rate c1 (C $x) (STV 0.5 1))
!(compileadd c1 (: a (A q) (STV 1 1)))
!(compileadd c1 (: o (O q) (STV 1 1)))
!(compileadd c1 (: ab (Implication (A $x) (B $x))
                    (CTV (STV 0.8 1) (STV 0.2 1))))
!(compileadd c1 (: cb (Implication (And (O $x) (C $x)) (B $x))
                    (CTV (STV 0.9 1) (STV 0.1 1))))
!(test (query 2000 c1 (: $p (C q) $tv))
   (: ((antecedent-completion cb 1 with cpu (prior (STV 0.5 1))) (conjunction o (by ab a))) (C q) (STV 0.7400000000000001 0.9999092513583969)))

!(set-base-rate c1b (C $x) (STV 0.5 1))
!(compileadd c1b (: a (A q) (STV 1 1)))
!(compileadd c1b (: o (O q) (STV 1 1)))
!(compileadd c1b (: historical (B old) (STV 1 1)))
!(compileadd c1b (: ab (Implication (A $x) (B $x))
                    (CTV (STV 0.8 1) (STV 0.2 1))))
!(compileadd c1b (: cb (Implication (And (O $x) (C $x)) (B $x))
                    (CTV (STV 0.9 1) (STV 0.1 1))))
!(test (query 2000 c1b (: $p (C q) $tv))
   (: ((antecedent-completion cb 1 with cpu (prior (STV 0.5 1))) (conjunction o (by ab a))) (C q) (STV 0.7400000000000001 0.9999092513583969)))

!(set-base-rate c1c (C $x) (STV 0.5 1))
!(compileadd c1c (: a (A q) (STV 1 1)))
!(compileadd c1c (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(compileadd c1c (: cb (Implication (C $x) (B $x)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(test (query 2000 c1c (: $p (C q) $tv))
   (: ((inverted cb with cpu (prior (STV 0.5 1))) (by ab a)) (C q) (STV 0.7400000000000001 0.9999092513583969)))

!(set-bayes-prior-count 0.2)

;; A prediction through the very rule being completed is self-support.
;; Its transitive dependencies include Degraded now and make it inadmissible
;; to that completion. There is no Produced observation.
!(compileadd selfKb (: rule (Implication (And (InService $t) (Not (Degraded $t))) (Produced $t)) (CTV (STV 1 1) (STV 0 1))))
!(set-base-rate selfKb (Degraded $t) (STV 0.25 0.9))
!(compileadd selfKb (: degraded-prior (Degraded now) (STV 0.25 0.9)))
!(compileadd selfKb (: service (InService now) (STV 1 1)))
!(test (query 2000 selfKb (: $p (Produced now) $tv))
   (: (by rule (conjunction service (negated degraded-prior))) (Produced now) (STV 0.75 0.8999999994868244)))
!(test (query 2000 selfKb (: $p (Degraded now) $tv)) (: degraded-prior (Degraded now) (STV 0.25 0.9)))
!(test (sk-observation-prior (brand Proof unfounded) (STV 0 1)) ())

;; Also exercise a materialized forward prediction: its evidence and dependency
;; identities survive storage, so it still cannot feed back into Degraded.
!(let $seeds (collapse (match &kb ($type (selfKb MAIN Nil) $proof $tv)
       (assemble-stored-runtime-fact $type (selfKb MAIN Nil) $proof $tv)))
   (forward-chain 100 selfKb (the (List SkFact) $seeds)))
!(test
   (let* (($target (index-hash (sk-key (Degraded now) (selfKb MAIN Nil))))
          ($produced (index-hash (sk-key (Produced now) (selfKb MAIN Nil)))))
      (collapse (match &sk_forward_stored ($produced $_key $fact $ev $deps)
         (data (deps-has? $deps $target)
            (sk-admits? sk-any-filter (cons $target ()) (sk-val $fact $ev $deps))))))
   ((true false)))
!(test (query 2000 selfKb (: $p (Degraded now) $tv))
   (: degraded-prior (Degraded now) (STV 0.25 0.9)))

;; Cause/Action from ctx-fix, with a matched completion whose sibling is true.
;; An Assuming context contains only Action now as new evidence. Both paths
;; consume the consequent predicted there and return the same strength and
;; confidence, using MAIN's explicit prior. With P(Cause)=.3 the diagnostic
;; predicts Effect at .41; the action predicts .40. Jeffrey's update is
;; .4*.6585 + .6*.0508 = .2939, a slight decrease. The stored belief is
;; the instance prior for this update (#42), so its strength is .2939 and
;; confidence stays near .8. Revising the posterior with the stored belief
;; instead gave .2944343613 at inflated confidence near .98.
!(set-context-reuse-threshold 0)
!(compileadd premiseKb (: diagnostic (Implication (Cause $t) (Effect $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd premiseKb (: (no_inverse prediction) (Implication (Action $t) (Effect $t)) (CTV (STV 0.4 1) (STV 0.4 1))))
!(compileadd premiseKb (: observed-old (Effect old) (STV 1 1)))
!(compileadd premiseKb (: cause-prior (Cause now) (STV 0.3 0.8)))
!(set-base-rate premiseKb (Cause $t) (STV 0.3 0.9))

!(compileadd premiseKb (: complete-diagnostic (Implication (And (Enabled $t) (Hidden $t)) (Consequence $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd premiseKb (: (no_inverse complete-prediction) (Implication (Action $t) (Consequence $t)) (CTV (STV 0.4 1) (STV 0.4 1))))
!(compileadd premiseKb (: observed-old-consequence (Consequence old) (STV 1 1)))
!(compileadd premiseKb (: enabled (Enabled now) (STV 1 1)))
!(compileadd premiseKb (: hidden-prior (Hidden now) (STV 0.3 0.8)))
!(set-base-rate premiseKb (Hidden $t) (STV 0.3 0.9))


!(test (let* (((: $_cp $_cq $completion-tv)
                 (query 2000 premiseKb (: $p (Assuming (Action now) (Hidden now)) $tv)))
              ((: $_ip $_iq $inversion-tv)
                 (query 2000 premiseKb (: $p (Assuming (Action now) (Cause now)) $tv))))
          (== $completion-tv $inversion-tv)) true)
!(test (let (: $_prf $_stmt (STV $s $_c))
          (query 2000 premiseKb (: $p (Assuming (Action now) (Cause now)) $tv))
          (< (max (- $s 0.29393311641031633) (- 0.29393311641031633 $s)) 0.000001)) true)
!(set-context-reuse-threshold 0.000001)

;; Induction reads a sibling with no stored instance at its population prior.
;; A predicate stored only when true samples as true, so undeclared, an absent
;; Via r1 reads as almost certain and ra's predicted arrival completes Blocked
;; r1 to 0.19 (SupplyNet stage 4, #119). Declared positive-only, Via has no
;; prior and Blocked r1 keeps its own.
!(set-positive-only-predicate viaKb Via)
!(compileadd viaKb (: arrives (Implication (And (Via $r $t) (Not (Blocked $r $t))) (Arrived $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd viaKb (: via-old (Via ra old) (STV 1 1)))
!(compileadd viaKb (: via (Via ra now) (STV 1 1)))
!(compileadd viaKb (: r1-old (Blocked r1 old) (STV 0 1)))
!(compileadd viaKb (: ra-old (Blocked ra old) (STV 1 1)))
!(compileadd viaKb (: ra-prior (Blocked ra now) (STV 0.2 0.9)))
!(test (query 2000 viaKb (: $p (Blocked r1 now) $tv))
   (: (population-prior (Blocked $_0 $_1)) (Blocked r1 now) (STV 0.4129032258064516 0.003611906837713289)))
