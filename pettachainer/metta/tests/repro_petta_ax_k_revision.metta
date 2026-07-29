!(import! &self ../petta_chainer)

!(compileadd mathkb
   (: ax-k (Provable (→ $x (→ $y $x))) (STV 1.0 1.0)))

!(test
   (query 10 mathkb (: ax-k (Provable (→ $x (→ $y $x))) $tv))
   (: ax-k (Provable (→ $x (→ $y $x))) (STV 1.0 1.0)))
