!(import! &self petta_chainer)

!(compileadd bwdOnlyKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test (not (== (collapse (query 2 bwdOnlyKb (: $p (Goal) $tv))) ())) false)

!(test (not (== (collapse (query 4 bwdOnlyKb (: $p (Goal) $tv))) ())) true)

!(compileadd composeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd composeKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test (let $_ (forward-chain 1 composeKb) (not (== (collapse (query 2 composeKb (: $p (Goal) $tv))) ())))
   true)

!(compileadd composeKbShort (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test
   (let $_ (forward-chain 1 composeKbShort)
      (not (== (collapse (query 1 composeKbShort (: $p (Goal) $tv))) ())))
   false)
