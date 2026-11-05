!(import! &self ../../pettachainer/metta/petta_chainer)

;; A proof KB stores only what is provable: Provable is positive-only, so its
;; stored theorems are no sample of how often a formula is provable, and no
;; rule is inverted or completed onto it.
!(set-positive-only-predicate mathkb Provable)

;; Axiom K is a schema rule. The identity computation keeps both parameters
;; in its antecedent; it can derive open or concrete instances on demand.
!(compileadd mathkb
   (: (no_inverse ax-k) (Implication (Compute id (($𝜑 $𝜓)) -> ($𝜑 $𝜓))
         (Provable (→ $𝜑 (→ $𝜓 $𝜑)))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd mathkb
   (: ax-id (Provable (→ a a)) (STV 1.0 1.0)))

!(compileadd mathkb
   (: mp
      (Implication
         (And (Provable (→ $p $q)) (Provable $p))
         (Provable $q))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd mathkb (: given-imp (Provable (→ (PropP) (PropQ))) (STV 1.0 1.0)))

!(compileadd mathkb (: given-p (Provable (PropP)) (STV 1.0 1.0)))

!(test
   (query 10 mathkb (: (by (no_inverse ax-k) cpu) (Provable (→ $𝜑 (→ $𝜓 $𝜑))) $tv))
   (: (by (no_inverse ax-k) cpu) (Provable (→ $𝜑 (→ $𝜓 $𝜑))) (STV 1.0 0.9999)))

!(test
   (query 10 mathkb (: (by (no_inverse ax-k) cpu) (Provable (→ a (→ b a))) $tv))
   (: (by (no_inverse ax-k) cpu) (Provable (→ a (→ b a))) (STV 1.0 0.9999)))

!(test
   (query 1 mathkb (: ax-id (Provable (→ a a)) $tv))
   (: ax-id (Provable (→ a a)) (STV 1.0 1.0)))

!(test
   (query 20 mathkb (: $prf (Provable (PropQ)) $tv))
   (: (by mp (conjunction given-imp given-p)) (Provable (PropQ)) (STV 1.0 0.9999)))
