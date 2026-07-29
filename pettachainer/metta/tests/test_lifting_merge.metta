!(import! &self ../petta_chainer)

;; Lifting-merge: when several proofs of one grounded conclusion share a premise
;; but are otherwise independent, they are pooled by factoring the shared premise
;; out, revising the residual implications, and re-applying the premise once --
;; recovering the confidence that dominance would discard.

;; --- Two independent implications A->B applied to the same a ---
!(compileadd twoImplKb (: a (A i) (STV 1.0 1.0)))
!(compileadd twoImplKb (: ab1 (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd twoImplKb (: ab2 (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

;; dominance would give (STV 0.6 0.9); pooling the two implications raises it.
!(test
   (query 40 twoImplKb (: $prf (B i) $tv))
   (: (merge/revision (ab1 a) (ab2 a)) (B i) (STV 0.6 0.9473684208506429)))

;; --- Same shape but the two implications differ in strength (0.7 vs 0.6).
;; Their idealized confidences then differ slightly, so plain overlap-dominance
;; would drop the lower-scoring proof at storage before pooling could run --
;; only keeping fact-overlapping proofs (they share a, residuals {ab1}/{ab2} are
;; disjoint) lets them pool. Confirms the direct query agrees with the bare
;; A->B implication query rather than collapsing to a single dominated proof. ---
!(compileadd diffImplKb (: a (A i) (STV 1.0 1.0)))
!(compileadd diffImplKb (: ab1 (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.7 0.9) (STV 0.0 1.0))))
!(compileadd diffImplKb (: ab2 (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(test
   (query 40 diffImplKb (: $prf (B i) $tv))
   (: (merge/revision (ab2 a) (ab1 a)) (B i) (STV 0.6499999999812448 0.9473684207998814)))

;; --- A,X->B / A,Y->B sharing only A. The bare implication query cannot express
;; this shape, so factoring at the conclusion is the only route to the pooled
;; value. Residuals {x, r1} and {y, r2} are disjoint, so the group pools. ---
!(compileadd conjKb (: a (A i) (STV 1.0 1.0)))
!(compileadd conjKb (: xx (X i) (STV 1.0 1.0)))
!(compileadd conjKb (: yy (Y i) (STV 1.0 1.0)))
!(compileadd conjKb (: r1 (Implication (Premises (And (A $z) (X $z))) (Conclusions (B $z))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd conjKb (: r2 (Implication (Premises (And (A $z) (Y $z))) (Conclusions (B $z))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

!(test
   (query 80 conjKb (: $prf (B i) $tv))
   (: (merge/revision (r2 (conjunction a yy)) (r1 (conjunction a xx))) (B i) (STV 0.6 0.947368420783305)))

;; --- Not independent: both paths to D share the uncertain bImpliesD rule, so
;; their residuals overlap and the group must NOT pool (dominance instead). ---
!(compileadd sharedRuleKb (: bm (B m) (STV 1.0 0.9)))
!(compileadd sharedRuleKb (: cm (C m) (STV 1.0 0.9)))
!(compileadd sharedRuleKb (: cImpliesB (Implication (Premises (C $x)) (Conclusions (B $x))) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))
!(compileadd sharedRuleKb (: bImpliesD (Implication (Premises (B $x)) (Conclusions (D $x))) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

;; the two (B m) proofs merge at the subgoal, so bImpliesD is applied once to the
;; revised premise -- not pooled across two conclusions sharing bImpliesD.
!(test
   (query 60 sharedRuleKb (: $prf (D m) $tv))
   (: (bImpliesD (merge/revision bm (cImpliesB cm))) (D m) (STV 0.4500001000170611 0.9124430019925824)))

;; --- Multi-leaf: two rules A,B->C share BOTH a and b. Their conjunction is
;; factored out as a unit and the residual implications pooled. ---
!(compileadd mlKb (: a (A i) (STV 1.0 1.0)))
!(compileadd mlKb (: b (Bp i) (STV 1.0 1.0)))
!(compileadd mlKb (: r1 (Implication (Premises (And (A $z) (Bp $z))) (Conclusions (C $z))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd mlKb (: r2 (Implication (Premises (And (A $z) (Bp $z))) (Conclusions (C $z))) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (query 80 mlKb (: $prf (C i) $tv))
   (: (merge/revision (r2 (conjunction a b)) (r1 (conjunction a b))) (C i) (STV 0.5499999999774938 0.9473684207209665)))

;; --- Shared b enters through different paths (directly in path 1, via M in
;; path 2), but the conclusion is still linear in the shared {a,b} conjunction,
;; so the 2-point probe is exact (the strength round-trip holds). The residuals
;; {r1} and {r2, bToM} are disjoint, so the group pools -- bToM lives in r2's
;; residual and is counted once. The round-trip guard only disables factoring
;; for genuinely non-linear shapes (a shared leaf used twice within one proof). ---
!(compileadd rtKb (: a (A i) (STV 0.5 1.0)))
!(compileadd rtKb (: b (Bp i) (STV 0.5 1.0)))
!(compileadd rtKb (: bToM (Implication (Premises (Bp $z)) (Conclusions (M $z))) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(compileadd rtKb (: r1 (Implication (Premises (And (A $z) (Bp $z))) (Conclusions (D $z))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(compileadd rtKb (: r2 (Implication (Premises (And (A $z) (M $z))) (Conclusions (D $z))) (CTV (STV 0.7 0.9) (STV 0.0 1.0))))

!(test
   (query 100 rtKb (: $prf (D i) $tv))
   (: (merge/revision (r1 (conjunction a b)) (r2 (conjunction a (bToM b)))) (D i) (STV 0.1539084488434874 0.9939398172053266)))
