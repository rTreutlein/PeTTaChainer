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

;; The compiler also indexes the fused (And A C) -> B completion directly.
;; Constraining the proof isolates it from the overlapping marginal projection
;; of the whole-conjunction inverse.
!(collapse
   (query 2000 completionKb (: $proof B $tv)))
!(test
   (query 2000 completionKb
      (: ((antecedent-completion ab_c 1 with cpu cpu cpu cpu)
          (conjunction a c))
         B $tv))
   (: ((antecedent-completion ab_c 1 with cpu cpu cpu cpu)
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
      (STV 0.5 0.6205423660898484)))

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
      (: ((antecedent-completion unsafe 0 with cpu cpu cpu)
          $witness)
         (A2 current arbitrary)
         $tv))
   ())
