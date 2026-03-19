!(import! &self petta_chainer)
!(import! &self math)

!(test
   (not (== (collapse (query 10 mathkb (: $prf (Provable (→ $𝜑 (→ $𝜓 $𝜑))) $tv))) ()))
   true)

!(test (not (== (collapse (query 1 mathkb (: $prf (Provable (→ a a)) $tv))) ())) true)

!(compileadd mathkb (: given-imp (Provable (→ (PropP) (PropQ))) (STV 1.0 1.0)))

!(compileadd mathkb (: given-p (Provable (PropP)) (STV 1.0 1.0)))

!(test (not (== (collapse (query 20 mathkb (: $prf (Provable (PropQ)) $tv))) ())) true)
