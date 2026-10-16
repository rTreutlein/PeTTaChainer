!(import! &self ../../pettachainer/metta/petta_chainer)

;; Axiom K is a schema rule. The identity computation keeps both parameters
;; in its antecedent; it can derive open or concrete instances on demand.
!(compileadd mathkb
   (: (no_inverse ax-k) (Implication (Compute id (($x $y)) -> ($x $y))
         (Provable (→ $x (→ $y $x)))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 10 mathkb (: (by (no_inverse ax-k) cpu) (Provable (→ $x (→ $y $x))) $tv))
   (: (by (no_inverse ax-k) cpu) (Provable (→ $x (→ $y $x))) (STV 1.0 0.9998000399670116)))
