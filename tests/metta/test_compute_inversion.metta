!(import! &self ../../pettachainer/metta/petta_chainer)

;; Built-in binary addition and subtraction are reversible at either argument.
!(test
   (compute-inverse-goal-or-none + 0 ($x 1) $y)
   (inverse-compute-goal (CPU - ($y 1) $x)))

!(test
   (compute-inverse-goal-or-none + 1 (1 $x) $y)
   (inverse-compute-goal (CPU - ($y 1) $x)))

!(test
   (compute-inverse-goal-or-none - 0 ($x 1) $y)
   (inverse-compute-goal (CPU + ($y 1) $x)))

!(test
   (compute-inverse-goal-or-none - 1 (10 $x) $y)
   (inverse-compute-goal (CPU - (10 $y) $x)))

;; A chain is inverted from the conclusion backwards. Each inverse computation
;; is followed by the original forward computation as an exact validation.
!(test
   (let (inverse-compute-plan $goals $_known)
      (compile-reversible-compute-plan
         (And
            (A $x)
            (Compute + ($x 1) -> $y)
            (Compute + ($y 1) -> $z))
         (C $z))
      $goals)
   ((CPU - ($z 1) $y)
    (CPU + ($y 1) $z)
    (CPU - ($y 1) $x)
    (CPU + ($x 1) $y)))

;; A step that cannot be inverted in the middle of a longer chain rejects the
;; whole chain: no partially bound plan escapes.
!(test
   (collapse (compile-reversible-compute-plan
      (And
         (A $x)
         (Compute + ($x 1) -> $y)
         (Compute * ($y 2) -> $z)
         (Compute + ($z 1) -> $w))
      (C $w)))
   ())

!(test
   (collapse (compile-reversible-compute-plan
      (And
         (Pair $x $q)
         (Compute + ($x $q) -> $y)
         (Compute + ($y 1) -> $z)
         (Compute + ($z 1) -> $w))
      (C $w)))
   ())

;; Ambiguous and unsupported computations retain the normal CPU inversion veto.
!(test
   (collapse (compile-reversible-compute-plan
      (And
         (Pair $x $z)
         (Compute + ($x $z) -> $total))
      (Total $total)))
   ())

!(test
   (collapse (compile-reversible-compute-plan
      (And
         (A $x)
         (Compute * ($x 2) -> $product))
      (Product $product)))
   ())

!(test
   (collapse (compile-reversible-compute-plan
      (And
         (A $x)
         (Compute + ($x 1) -> $y)
         (FoldAll (Score $_name $n) $n 0 + -> $total))
      (Result $y $total)))
   ())

!(compileadd computeInverseKb
   (: addOne
      (Implication
         (And
            (A $x)
            (Compute + ($x 1) -> $y))
         (B $y))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd computeInverseKb
   (: a-one (A 1) (STV 0.7 0.8)))

!(compileadd computeInverseKb
   (: observed-b-three (B 3) (STV 0.9 0.8)))

;; Observing B(3) runs 3 - 1 = 2, validates 2 + 1 = 3, applies ordinary CTV
;; inversion, and projects A(2) from the reconstructed antecedent; the
;; projection reads its computed sibling as the computation.
!(test
   (query 300 computeInverseKb (: $proof (A 2) $tv))
   (: ((proj 0 ((inverted addOne with cpu (prior (STV 0.6599999999940221 0.000999000998814564))) observed-b-three)) cpu) (A 2) (STV 0.8756835083726222 0.016391821879727795)))

;; The same reversible computation remains executable when inversion is
;; disabled. The observations above demonstrate that its reverse would
;; otherwise have enough evidence to derive A(2).
!(compileadd noInverseComputeKb
   (: (no_inverse addOne)
      (Implication
         (And
            (A $x)
            (Compute + ($x 1) -> $y))
         (B $y))
      (CTV (STV 0.8 0.9) (STV 0.1 0.9))))
!(compileadd noInverseComputeKb
   (: a-one (A 1) (STV 0.7 0.8)))
!(compileadd noInverseComputeKb
   (: observed-b-three (B 3) (STV 0.9 0.8)))

!(test
   (query 300 noInverseComputeKb (: $proof (B 2) $tv))
   (: (by (no_inverse addOne) (conjunction a-one cpu))
      (B 2)
      (STV 0.59 0.8725449129775122)))
!(test
   (query 300 noInverseComputeKb (: $proof (A 2) $tv))
   ())
