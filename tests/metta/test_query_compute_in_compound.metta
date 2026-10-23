!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd queryComputeKb (: p1 (P 1) (STV 1.0 1.0)))

!(compileadd queryComputeKb (: p2 (P 2) (STV 1.0 1.0)))

!(compileadd queryComputeKb (: p3 (P 3) (STV 1.0 1.0)))

;; A compound root is its conjunction, read through the key's producer (#142).
!(test
   (query 50 queryComputeKb (: $prf (And (P $x) (Compute + ($x 1) $y) (P $y)) $tv))
   ((: (conjunction p1 cpu p2) (And (P 1) (Compute + (1 1) 2) (P 2)) (STV 1.0 0.999700089898053)) (: (conjunction p2 cpu p3) (And (P 2) (Compute + (2 1) 3) (P 3)) (STV 1.0 0.999700089898053))))

!(compileadd queryNotCompoundKb (: tallAlice (Tall alice) (STV 0.9 0.5)))

!(compileadd queryNotCompoundKb (: femaleAlice (Female alice) (STV 0.9 0.5)))

!(test
   (query 20 queryNotCompoundKb (: $prf (And (Not (Tall alice)) (Female alice)) $tv))
   (: (conjunction (negated tallAlice) femaleAlice) (And (Not (Tall alice)) (Female alice)) (STV 0.08999999999999998 0.5260081823495032)))

;; Implication children retain arithmetic bindings from ordinary conjuncts.
;; Certain P1/P2 contribute strength 1, and the positive implication contributes
;; 0.8. The negative rule-storage branch is not a conjunct.
!(compileadd implicationComputeKb (: p1 (P 1) (STV 1 1)))
!(compileadd implicationComputeKb (: p2 (P 2) (STV 1 1)))
!(compileadd implicationComputeKb (: r (Implication (G) (Y))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(test (collapse (let
   (: (conjunction p1 cpu p2 r)
      (And (P 1) (Compute + (1 1) 2) (P 2) (Implication (G) (Y))) $tv)
   (query 300 implicationComputeKb
      (: $p (And (P $x) (Compute + ($x 1) $y) (P $y)
         (Implication (G) (Y))) $value)) $tv))
   ((STV 0.8 0.8999999990276973)))
