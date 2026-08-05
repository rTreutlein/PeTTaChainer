!(import! &self ../petta_chainer)

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
   (inverse-compute-plan-goals
      (compile-reversible-compute-plan
         (And
            (A $x)
            (Compute + ($x 1) -> $y)
            (Compute + ($y 1) -> $z))
         (C $z)))
   ((CPU - ($z 1) $y)
    (CPU + ($y 1) $z)
    (CPU - ($y 1) $x)
    (CPU + ($x 1) $y)))

;; Ambiguous and unsupported computations retain the normal CPU inversion veto.
!(test
   (compile-reversible-compute-plan
      (And
         (Pair $x $z)
         (Compute + ($x $z) -> $total))
      (Total $total))
   no-compute-inverse)

!(test
   (compile-reversible-compute-plan
      (And
         (A $x)
         (Compute * ($x 2) -> $product))
      (Product $product))
   no-compute-inverse)

!(test
   (compile-reversible-compute-plan
      (And
         (A $x)
         (Compute + ($x 1) -> $y)
         (FoldAll (Score $_name $n) $n 0 + -> $total))
      (Result $y $total))
   no-compute-inverse)

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
;; inversion, and projects A(2) from the reconstructed antecedent.
!(test
   (query 300 computeInverseKb (: $proof (A 2) $tv))
   (: (marginal-proj 0
         ((inverted addOne with
             (foldall-proof
                (by query-compound (conjunction a-one cpu)))
             (foldall-proof
                observed-b-three
                (by addOne (conjunction a-one cpu))))
          observed-b-three))
      (A 2)
      (STV 0.7361622402584586 0.00026536071629869475)))
