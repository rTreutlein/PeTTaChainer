!(import! &self ../../pettachainer/metta/petta_chainer)

;; A premise no rule can conclude is answered by stored facts only, so
;; expanding it costs no step: one step expands the goal, and the premises
;; Value and Cost, open in their numbers, are read on the way.
!(compileadd netKb (: c1 (Cost x 5) (STV 1 1)))
!(compileadd netKb (: v1 (Value x 12) (STV 1 1)))
!(compileadd netKb
   (: (no_inverse net)
      (Implication (And (Value $u $v) (Cost $u $c) (Compute - ($v $c) -> $n)) (Net $u $n))
      (CTV (STV 1 1) (STV 0 1))))

!(test
   (query 1 netKb (: $prf (Net x $n) $tv))
   (: (by (no_inverse net) (conjunction v1 c1 cpu)) (Net x 7) (STV 1.0 0.9999)))
