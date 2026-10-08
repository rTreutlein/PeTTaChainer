!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd invKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd invKb (: pb (P bob) (STV 0.7 0.8)))

; The rule states both branches, so inversion is Bayes' rule with the base
; rate of P as the prior, found as a FoldAll aggregate over all proofs of P
; (pb, one confidence-weighted piece of evidence with K=800): P(P | Q) =
; 0.8 * 0.7 / (0.8 * 0.7 + 0.1 * 0.3) = 0.949 and P(P | not Q) = 0.2 * 0.7 /
; (0.2 * 0.7 + 0.9 * 0.3) = 0.341. The inverted CTV is then applied to the
; witness qa via modus ponens: 0.9 * 0.949 + 0.1 * 0.341 = 0.888.
!(test
   (query 200 invKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.6999999999999998 0.0009990009990009992))) qa) (P alice) (STV 0.8883802148701847 0.017951122492168896)))

; The consequent's own base rate is not read: here P(Late) = 0.1 contradicts
; P(Blocked) = 1/6 and the stated likelihoods, which give P(Late) = 0.1917.
; Recovering P(Late | not Blocked) from the two rates would give
; (0.1 - 0.9 / 6) / (5 / 6) < 0, so one late shipment would prove the route
; blocked; Bayes' rule with the stated likelihoods gives 0.9 / 6 /
; (0.9 / 6 + 0.05 * 5 / 6) = 0.7826.
!(compileadd lateKb (: late (Implication (Blocked $r) (Late $r)) (CTV (STV 0.9 1.0) (STV 0.05 1.0))))
!(set-base-rate lateKb (Blocked $r) (STV 0.16666666666666666 0.9))
!(set-base-rate lateKb (Late $r) (STV 0.1 0.9))
!(compileadd lateKb (: l1 (Late r1) (STV 1.0 1.0)))
!(test
   (query 100 lateKb (: $prf (Blocked r1) $tv))
   (: ((inverted late with cpu (prior (STV 0.16666666666666666 0.9))) l1) (Blocked r1) (STV 0.782608695652174 0.8799444564487994)))
