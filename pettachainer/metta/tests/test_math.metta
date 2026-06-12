!(import! &self petta_chainer)

!(compileadd mathkb
   (: ax-k (Provable (→ $𝜑 (→ $𝜓 $𝜑))) (STV 1.0 1.0)))

!(compileadd mathkb
   (: ax-id (Provable (→ a a)) (STV 1.0 1.0)))

!(compileadd mathkb
   (: mp
      (Implication
         (Premises (Provable (→ $p $q)) (Provable $p))
         (Conclusions (Provable $q)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd mathkb (: given-imp (Provable (→ (PropP) (PropQ))) (STV 1.0 1.0)))

!(compileadd mathkb (: given-p (Provable (PropP)) (STV 1.0 1.0)))

!(test
   (query 10 mathkb (: ax-k (Provable (→ $𝜑 (→ $𝜓 $𝜑))) $tv))
   (: ax-k (Provable (→ $𝜑 (→ $𝜓 $𝜑))) (STV 1.0 1.0)))

!(test
   (query 1 mathkb (: ax-id (Provable (→ a a)) $tv))
   (: ax-id (Provable (→ a a)) (STV 1.0 1.0)))

!(test
   (query 20 mathkb (: $prf (Provable (PropQ)) $tv))
   (: (mp (conjunction given-imp given-p))
      (Provable (PropQ))
      (STV 1.0 1.0)))
