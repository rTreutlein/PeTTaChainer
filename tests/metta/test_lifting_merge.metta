!(import! &self ../../pettachainer/metta/petta_chainer)

;; Several proofs of one grounded conclusion that share a premise but are
;; otherwise independent revise, recovering the confidence that dominance would
;; discard. A shared certain fact read as a condition is given, so such proofs
;; are independent and revise directly; a shared uncertain statement is
;; conditioned on. Confidences differ from the residual revision below 1e-9.

;; --- Two independent implications A->B applied to the same a ---
!(compileadd twoImplKb (: a (A i) (STV 1.0 1.0)))
!(compileadd twoImplKb (: ab1 (Implication (A $x) (B $x)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd twoImplKb (: ab2 (Implication (A $x) (B $x)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

;; dominance would give (STV 0.6 0.9); pooling the two implications raises it.
!(test
   (query 40 twoImplKb (: $prf (B i) $tv))
   (: (merge/revision (by ab1 a) (by ab2 a)) (B i) (STV 0.6 0.9473684209852937)))

;; --- Same shape but the two implications differ in strength (0.7 vs 0.6).
;; Their idealized confidences then differ slightly, so plain overlap-dominance
;; would drop the lower-scoring proof at storage before pooling could run --
;; only keeping fact-overlapping proofs (they share a, residuals {ab1}/{ab2} are
;; disjoint) lets them pool. Confirms the direct query agrees with the bare
;; A->B implication query rather than collapsing to a single dominated proof. ---
!(compileadd diffImplKb (: a (A i) (STV 1.0 1.0)))
!(compileadd diffImplKb (: ab1 (Implication (A $x) (B $x)) (CTV (STV 0.7 0.9) (STV 0.0 1.0))))
!(compileadd diffImplKb (: ab2 (Implication (A $x) (B $x)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(test
   (query 40 diffImplKb (: $prf (B i) $tv))
   (: (merge/revision (by ab2 a) (by ab1 a)) (B i) (STV 0.6499999999812448 0.9473684209665905)))

;; --- A,X->B / A,Y->B sharing only A. The bare implication query cannot express
;; this shape. These distinct sibling conditions combine by odds over the
;; neutral prior: odds(.6)^2 gives .6923077; same-condition revision above stays. ---
!(compileadd conjKb (: a (A i) (STV 1.0 1.0)))
!(compileadd conjKb (: xx (X i) (STV 1.0 1.0)))
!(compileadd conjKb (: yy (Y i) (STV 1.0 1.0)))
!(compileadd conjKb (: r1 (Implication (And (A $z) (X $z)) (B $z)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd conjKb (: r2 (Implication (And (A $z) (Y $z)) (B $z)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

;; #49/#77: no live shared-class estimate resolves this overlap. Keep the
;; population strength and halve confidence for the minimum R=1 allowance.
!(test
   (query 80 conjKb (: $prf (B i) $tv))
   (: (combination odds (prior (STV 0.5 0.0)) ((by r1 (conjunction a xx)) (by r2 (conjunction a yy)))) (B i) (STV 0.6923076923076922 0.00010848340203948785)))

;; --- Not independent: both paths to D share the uncertain bImpliesD rule, so
;; their residuals overlap and the group must NOT pool (dominance instead). ---
!(compileadd sharedRuleKb (: bm (B m) (STV 1.0 0.9)))
!(compileadd sharedRuleKb (: cm (C m) (STV 1.0 0.9)))
!(compileadd sharedRuleKb (: cImpliesB (Implication (C $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))
!(compileadd sharedRuleKb (: bImpliesD (Implication (B $x) (D $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

;; the two (B m) proofs merge at the subgoal, so bImpliesD is applied once to the
;; revised premise -- not pooled across two conclusions sharing bImpliesD.
!(test
   (query 60 sharedRuleKb (: $prf (D m) $tv))
   (: (by bImpliesD (factored-revision (by cImpliesB cm) (prior (STV 0.8 0.8999996399380039)) (((reported with cpu (prior (STV 0.5 0.0))) bm)))) (D m) (STV 0.5 0.899999909975099)))

;; --- Multi-leaf: two rules A,B->C share BOTH a and b. Their conjunction is
;; factored out as a unit and the residual implications pooled. ---
!(compileadd mlKb (: a (A i) (STV 1.0 1.0)))
!(compileadd mlKb (: b (Bp i) (STV 1.0 1.0)))
!(compileadd mlKb (: r1 (Implication (And (A $z) (Bp $z)) (C $z)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd mlKb (: r2 (Implication (And (A $z) (Bp $z)) (C $z)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (query 80 mlKb (: $prf (C i) $tv))
   (: (merge/revision (by r2 (conjunction a b)) (by r1 (conjunction a b))) (C i) (STV 0.5499999999774938 0.9473684209403997)))

;; --- Shared b enters through different paths (directly in path 1, via M in
;; path 2), but the conclusion is still linear in the shared {a,b} conjunction,
;; so a 2-point probe would be linear. These distinct conditions do not use
;; residual revision. Their shared uncertain facts condition the combination,
;; including the path deriving M from b, instead of selecting one view. ---
!(compileadd rtKb (: a (A i) (STV 0.5 1.0)))
!(compileadd rtKb (: b (Bp i) (STV 0.5 1.0)))
!(compileadd rtKb (: bToM (Implication (Bp $z) (M $z)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(compileadd rtKb (: r1 (Implication (And (A $z) (Bp $z)) (D $z)) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd rtKb (: r2 (Implication (And (A $z) (M $z)) (D $z)) (CTV (STV 0.7 0.9) (STV 0.0 1.0))))

;; Shared a and b are mixed once. In the true branch, odds(.6)*odds(.63)
;; over the neutral prior give .718631; P(a AND b)=.25 gives .179658.
;; #49/#77: the branch lacks a live shared-class estimate. Its unresolved
;; confidence discount propagates through the unchanged conditioning mixture.
!(test
   (let (: $prf $_type $tv) (query 100 rtKb (: $prf (D i) $tv))
      ($tv (car-atom $prf)))
   ((STV 0.17965779467755605 0.014827336747515504) conditioned))
