!(import! &self ../../pettachainer/metta/petta_chainer)

;; Direct completion conditions on the known antecedent/consequence joint:
;; P(B|A,C) = P(C|A,B) P(A,B) / P(A,C) = 1.0 * 0.2 / 0.25.
!(test
   (CTVAntecedentCompletionFormula
      (STV 0.3 0.9)
      (STV 0.2 0.9)
      (STV 0.25 0.9)
      (ImplicationCTVFormula
         (STV 0.2 0.9)
         (STV 0.4 0.9)
         (STV 1.0 0.9)))
   (CTV
      (STV 0.8 0.2425523017889163)
      (STV 0.1333333333333333 0.6102780211026617)))

!(compileadd completionKb (: a A (STV 1.0 0.9)))
!(compileadd completionKb (: c C (STV 1.0 0.9)))
!(compileadd completionKb
   (: ab_c
      (Implication (And A B) C)
      (STV 1.0 0.9)))

!(set-base-rate completionKb (And A B) (STV 0.2 0.9))
!(set-base-rate completionKb C (STV 0.4 0.9))
!(set-base-rate completionKb (And A C) (STV 0.25 0.9))
!(set-base-rate completionKb B (STV 0.3 0.9))

;; The compiler indexes the fused (And A C) -> B completion as the only
;; child-recovery operator. Whole-compound inversion still proves (And A B)
;; itself and does not also project to B.
!(test
   (query 2000 completionKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu cpu)
       (conjunction a c))
      B
      (STV 0.8 0.24255226513533926)))

;; Disabling whole-antecedent inversion does not disable direct completion.
;; Its conjunction classification must remain outside inversion planning.
!(compileadd noInverseCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd noInverseCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd noInverseCompletionKb
   (: (no_inverse ab_c)
      (Implication (And A B) C)
      (STV 1.0 0.9)))
!(set-base-rate noInverseCompletionKb (And A B) (STV 0.2 0.9))
!(set-base-rate noInverseCompletionKb C (STV 0.4 0.9))
!(set-base-rate noInverseCompletionKb (And A C) (STV 0.25 0.9))
!(set-base-rate noInverseCompletionKb B (STV 0.3 0.9))

!(test
   (query 2000 noInverseCompletionKb (: $proof B $tv))
   (: ((antecedent-completion (no_inverse ab_c) 1 with cpu cpu)
       (conjunction a c))
      B
      (STV 0.8 0.24255226513533926)))

;; Pure conjunction antecedents retain whole-compound Bayesian inversion.
!(compileadd conjunctionInversionKb (: c C (STV 1.0 0.9)))
!(compileadd conjunctionInversionKb
   (: ab_c
      (Implication (And A B) C)
      (STV 1.0 0.9)))
!(set-base-rate conjunctionInversionKb
   (And A B) (STV 0.2 0.9))
!(set-base-rate conjunctionInversionKb C (STV 0.4 0.9))

!(test
   (query 2000 conjunctionInversionKb
      (: $proof (And A B) $tv))
   (: ((inverted ab_c with cpu cpu) c)
      (And A B)
      (STV 0.49999166689814173 0.6205495495952107)))

;; A completion is not generated when the missing premise contains a variable
;; which neither the remaining antecedents nor the consequence can bind.
!(compileadd unboundCompletionKb
   (: unsafe
      (Implication
         (And (A2 $x $y) (B2 $x))
         (C2 $x))
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(compileadd unboundCompletionKb (: b2 (B2 current) (STV 1.0 0.9)))
!(compileadd unboundCompletionKb (: c2 (C2 current) (STV 1.0 0.9)))
!(set-base-rate unboundCompletionKb
   (And (A2 $x $y) (B2 $x)) (STV 0.2 0.9))
!(set-base-rate unboundCompletionKb
   (And (B2 $x) (C2 $x)) (STV 0.25 0.9))
!(set-base-rate unboundCompletionKb
   (A2 $x $y) (STV 0.3 0.9))

!(test
   (query 2000 unboundCompletionKb
      (: ((antecedent-completion unsafe 0 with cpu cpu)
          $witness)
         (A2 current arbitrary)
         $tv))
   ())

;; An explicit CTV compiles the same fused completion.
!(compileadd ctvCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd ctvCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd ctvCompletionKb
   (: ab_c
      (Implication (And A B) C)
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(set-base-rate ctvCompletionKb (And A B) (STV 0.2 0.9))
!(set-base-rate ctvCompletionKb C (STV 0.4 0.9))
!(set-base-rate ctvCompletionKb (And A C) (STV 0.25 0.9))
!(set-base-rate ctvCompletionKb B (STV 0.3 0.9))

!(test
   (query 2000 ctvCompletionKb (: $proof B $tv))
   (: ((antecedent-completion ab_c 1 with cpu cpu)
       (conjunction a c))
      B
      (STV 0.8 0.24255226513533926)))

;; A three-child conjunction completes the middle child from the other
;; children plus the original consequence: (And A D C) -> Mid.
!(compileadd ternaryCompletionKb (: a A (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb (: d D (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb (: c C (STV 1.0 0.9)))
!(compileadd ternaryCompletionKb
   (: abd_c
      (Implication (And A Mid D) C)
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(set-base-rate ternaryCompletionKb (And A Mid D) (STV 0.2 0.9))
!(set-base-rate ternaryCompletionKb C (STV 0.4 0.9))
!(set-base-rate ternaryCompletionKb (And A D C) (STV 0.25 0.9))
!(set-base-rate ternaryCompletionKb Mid (STV 0.3 0.9))

!(test
   (query 2000 ternaryCompletionKb (: $proof Mid $tv))
   (: ((antecedent-completion abd_c 1 with cpu cpu)
       (conjunction a d c))
      Mid
      (STV 0.8 0.24255224680855486)))

;; Source computations in the antecedent block every child completion.
!(compileadd computeSkipKb
   (: addOne
      (Implication
         (And
            (A $x)
            (Compute + ($x 1) -> $y))
         (B $y))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd computeSkipKb (: a-one (A 1) (STV 0.7 0.8)))
!(compileadd computeSkipKb (: b-two (B 2) (STV 0.9 0.8)))
!(set-base-rate computeSkipKb
   (And (A $x) (Compute + ($x 1) -> $y)) (STV 0.2 0.9))
!(set-base-rate computeSkipKb (B $y) (STV 0.4 0.9))
!(set-base-rate computeSkipKb
   (And (Compute + ($x 1) -> $y) (B $y)) (STV 0.25 0.9))
!(set-base-rate computeSkipKb (A $x) (STV 0.3 0.9))

!(test
   (query 300 computeSkipKb
      (: ((antecedent-completion addOne 0 with cpu cpu) $w)
         (A 1) $tv))
   ())

;; An existential And is compiled as an ExistentialClaim, not as a
;; conjunction that can complete a missing child.
!(compileadd existsSkipKb (: p (P a) (STV 1.0 1.0)))
!(compileadd existsSkipKb (: q Q (STV 1.0 0.9)))
!(compileadd existsSkipKb
   (: existsRule
      (Implication
         (Exists ($x) (And (P $x) Q))
         R)
      (CTV (STV 1.0 0.9) (STV 0.0 0.9))))
!(compileadd existsSkipKb (: r R (STV 1.0 0.9)))
!(set-base-rate existsSkipKb (And (P $x) Q) (STV 0.2 0.9))
!(set-base-rate existsSkipKb R (STV 0.4 0.9))
!(set-base-rate existsSkipKb (And Q R) (STV 0.25 0.9))
!(set-base-rate existsSkipKb (P $x) (STV 0.3 0.9))

!(test
   (query 300 existsSkipKb
      (: ((antecedent-completion existsRule 1 with cpu cpu) $w)
         Q $tv))
   ())
