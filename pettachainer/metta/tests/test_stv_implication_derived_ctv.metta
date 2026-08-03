!(import! &self ../petta_chainer)

!(compileadd stvRuleKb (: a (A x) (STV 1.0 0.9)))

!(compileadd stvRuleKb
   (: aToB
      (Implication
         (A $x)
         (B $x))
      (STV 0.6 0.9)))

!(test
   (query 20 stvRuleKb (: $prf (B x) $tv))
   (: (by aToB a) (B x) (STV 0.6 0.8999998649685302)))
