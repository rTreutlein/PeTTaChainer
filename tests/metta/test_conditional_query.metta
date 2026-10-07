!(import! &self ../../pettachainer/metta/petta_chainer)

;; An implication query that asks for an STV evaluates only the positive side:
;; how the consequent stands when the antecedent holds, one answer per
;; binding of the consequent's variables, and no refuting context.
!(compileadd netKb
   (: (no_inverse net)
      (Implication (And (Value $u $v) (Cost $u $c) (Compute - ($v $c) -> $n)) (Net $u $n))
      (CTV (STV 1 1) (STV 0 1))))

!(test
   (query 60 netKb
      (: $prf (Implication (And (Value x 12) (Cost x 5) (Value y 9) (Cost y 2)) (Net x $n)) (STV $s $c)))
   (: (conditional-implication (by (no_inverse net) (conjunction (ctx proof 0) (ctx proof 0 1) cpu)))
      (Implication (And (Value x 12) (Cost x 5) (Value y 9) (Cost y 2)) (Net x 7))
      (STV 1.0 0.9996001597861454)))

!(test
   (let $answers
      (collapse (query 60 netKb
         (: $prf (Implication (And (Value x 12) (Cost x 5) (Value y 9) (Cost y 2)) (Net $u $n)) (STV $s $c))))
      (size-atom $answers))
   2)
