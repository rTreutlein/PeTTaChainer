!(import! &self petta_chainer)

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
   (: (merge/revision (ab1 a) (ab2 a))
      (B i)
      (STV 0.6 0.9473684210526316)))

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
   (: (merge/revision (r2 (conjunction a yy)) (r1 (conjunction a xx)))
      (B i)
      (STV 0.6 0.9473684210526316)))

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
   (: (bImpliesD (merge/revision bm (cImpliesB cm)))
      (D m)
      (STV 0.45 0.9047368421052632)))
