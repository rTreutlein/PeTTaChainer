!(import! &self petta_chainer)

!(compileadd kb (: prf (Pred A 1) (STV 1.0 1.0)))

!(compileadd kb (: prf (Pred A 2) (STV 0.0 1.0)))

!(compileadd kb (: prf (Pred B 1) (STV 1.0 1.0)))

!(compileadd kb (: prf (Pred B 2) (STV 0.9 1.0)))

;!(match &kb $a $a)
!(query 1 kb (: $prf (Pred $v #) $tv))
