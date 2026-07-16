!(import! &self petta_chainer)

; Hypothetical context premises carry no evidence, and unmarked implication
; facts do. Together: branches of a conditional that share only the hypothesis
; revision-merge, while derivations sharing an uncertain implication are
; treated as dependent.

; --- Two derivation branches under one hypothesis merge ---

!(compileadd evKb (: aImpliesB (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: aImpliesC (Implication (Premises (A $x)) (Conclusions (C $x))) (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: bImpliesD (Implication (Premises (B $x)) (Conclusions (D $x))) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: cImpliesD (Implication (Premises (C $x)) (Conclusions (D $x))) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

; The assumed (A $x) is shared by both branches but is the conditioning
; hypothesis, not evidence; the implication sets are disjoint, so the
; branches revise to 0.947 (matching the fact-level representation of the
; same inference in examples/deductionrevision_pettachainer.metta).
!(test
   (let
      (: $prf
         (Implication (Premises (A $x)) (Conclusions (D $x)))
         $tv)
      (query 100 evKb
         (: $prf
            (Implication (Premises (A $x)) (Conclusions (D $x)))
            $tv))
      $tv)
   (CTV (STV 0.125 0.9692294378874315) (STV 0.0 0.9999367205825538)))

; --- Derivations sharing an uncertain implication do not merge ---

!(compileadd sharedKb (: bm (B m) (STV 1.0 0.9)))

!(compileadd sharedKb (: cm (C m) (STV 1.0 0.9)))

!(compileadd sharedKb (: cImpliesB (Implication (Premises (C $x)) (Conclusions (B $x))) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(compileadd sharedKb (: bImpliesD (Implication (Premises (B $x)) (Conclusions (D $x))) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

; (D m) is reachable from bm directly and from cm via cImpliesB. The two
; (B m) proofs have disjoint evidence and merge at the subgoal, so the shared
; uncertain bImpliesD is applied exactly once to the revised premise instead
; of double-counting its uncertainty across two conclusions.
!(test
   (query 60 sharedKb (: $prf (D m) $tv))
   (: (bImpliesD (merge/revision bm (cImpliesB cm))) (D m) (STV 0.4500001000170611 0.9124430019925824)))
