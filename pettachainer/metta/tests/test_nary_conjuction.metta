!(import! &self petta_chainer)

!(compileadd kb (: a A (STV 1.0 1.0)))
!(compileadd kb (: b B (STV 1.0 1.0)))
!(compileadd kb (: c C (STV 1.0 1.0)))

!(test (query 10 kb (: $prf (And A B C) $tv))
       (: (conjunction a b c) (And A B C) (STV 1.0 0.999700089898053)))
