!(import! &self ../../pettachainer/metta/petta_chainer)

;; A claim stated as a certain ground rule holds its information in the rule.
;; The claim's view (R -> U at .9 / .2) and the system's (R and O -> U at
;; .95 / .1) both read R; with O certain the exact value is
;; .7 * .95 + .3 * .2 = .725. Unnamed, the claim looked contained in the
;; system view and the two only revised (.692). Named, they condition on R.
!(compileadd groundKb (: r1 (Reliable s1) (STV 0.7 0.9)))
!(compileadd groundKb (: o1 (Other) (STV 1 1)))
!(compileadd groundKb (: claim (Implication (Reliable s1) (Up s1)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd groundKb (: sys (Implication (And (Reliable $s) (Other)) (Up $s)) (CTV (STV 0.95 1.0) (STV 0.1 1.0))))
!(test (let (: $_p $_t (STV $s $_c)) (query 200 groundKb (: $proof (Up s1) $tv)) $s) 0.725)

;; Known limit: the same claim written with a variable is a general rule and
;; is not named (a cost line, runtime_design_assumptions.md), so it keeps the
;; revision.
!(compileadd generalKb (: r1 (Reliable s1) (STV 0.7 0.9)))
!(compileadd generalKb (: o1 (Other) (STV 1 1)))
!(compileadd generalKb (: claim (Implication (Reliable $s) (Up $s)) (CTV (STV 0.9 1.0) (STV 0.2 1.0))))
!(compileadd generalKb (: sys (Implication (And (Reliable $s) (Other)) (Up $s)) (CTV (STV 0.95 1.0) (STV 0.1 1.0))))
!(test (let (: $_p $_t (STV $s $_c)) (query 200 generalKb (: $proof (Up s1) $tv)) $s) 0.6920097040409717)

;; Known limit (#112): A, B and C one variable through certain rules, reports
;; a0 .8 and c0 .6; exact .8571. The query conditions on c0 and loses a0
;; (no Pearl reweighting of the weight by the branches' evidence).
!(compileadd cycleKb (: a0 (CycA) (STV 0.8 0.5)))
!(compileadd cycleKb (: c0 (CycC) (STV 0.6 0.5)))
!(compileadd cycleKb (: aToB (Implication (CycA) (CycB)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd cycleKb (: cToB (Implication (CycC) (CycB)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd cycleKb (: bToA (Implication (CycB) (CycA)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (let (: $_p $_t (STV $s $_c)) (query 200 cycleKb (: $proof (CycA) $tv)) $s) 0.6)
;; C reads a0 through the inverted chain and c0 directly: exact.
!(test (let (: $_p $_t (STV $s $_c)) (query 200 cycleKb (: $proof (CycC) $tv)) $s) 0.8571301048873019)
