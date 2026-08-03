!(import! &self ../petta_chainer)

; Hypothetical context premises carry no evidence, and unmarked implication
; facts do. Together: branches of a conditional that share only the hypothesis
; revision-merge, while derivations sharing an uncertain implication are
; treated as dependent.

!(test
   (proof-term-evidence-list-mode
      proof-walk-plain (ctx hypothesis))
   ())

; --- Two derivation branches under one hypothesis merge ---

!(compileadd evKb (: aImpliesB (Implication (A $x) (B $x)) (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: aImpliesC (Implication (A $x) (C $x)) (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: bImpliesD (Implication (B $x) (D $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(compileadd evKb (: cImpliesD (Implication (C $x) (D $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

; The assumed (A $x) is shared by both branches but is the conditioning
; hypothesis, not evidence; the implication sets are disjoint, so the
; branches revise to 0.947 (matching the fact-level representation of the
; same inference in examples/deductionrevision_pettachainer.metta).
!(test
   (let
      (: $prf
         (Implication (A $x) (D $x))
         $tv)
      (query 100 evKb
         (: $prf
            (Implication (A $x) (D $x))
            $tv))
      $tv)
   (CTV (STV 0.125 0.9692294378874315) (STV 0.0 0.9999367205825538)))

; --- Derivations sharing an uncertain implication do not merge ---

!(compileadd sharedKb (: bm (B m) (STV 1.0 0.9)))

!(compileadd sharedKb (: cm (C m) (STV 1.0 0.9)))

!(compileadd sharedKb (: cImpliesB (Implication (C $x) (B $x)) (CTV (STV 0.8 0.9) (STV 0.0 1.0))))

!(compileadd sharedKb (: bImpliesD (Implication (B $x) (D $x)) (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

; (D m) is reachable from bm directly and from cm via cImpliesB. The two
; (B m) proofs have disjoint evidence and merge at the subgoal, so the shared
; uncertain bImpliesD is applied exactly once to the revised premise instead
; of double-counting its uncertainty across two conclusions.
!(test
   (query 60 sharedKb (: $prf (D m) $tv))
   (: (by bImpliesD (merge/revision bm (by cImpliesB cm))) (D m) (STV 0.4500001000170611 0.9124430019925824)))
