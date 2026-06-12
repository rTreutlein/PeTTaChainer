!(import! &self petta_chainer)

!(compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))

!(compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

!(mark-logic-rule inheritanceDeduction)

!(compileadd deductionRevisionKb
   (: inheritanceDeduction
      (Implication
         (Premises (Inheritance $a $b) (Inheritance $b $c))
         (Conclusions (Inheritance $a $c)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 30 deductionRevisionKb (: $prf (Inheritance A D) $tv))
   (: (merge/revision
         (inheritanceDeduction (conjunction aInheritsC cInheritsD))
         (inheritanceDeduction (conjunction aInheritsB bInheritsD)))
      (Inheritance A D)
      (STV 0.125 0.9473684210526316)))

!(compileadd deductionRevisionImplicationKb
   (: aImpliesB
      (Implication (Premises (A $x)) (Conclusions (B $x)))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: aImpliesC
      (Implication (Premises (A $x)) (Conclusions (C $x)))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: bImpliesD
      (Implication (Premises (B $x)) (Conclusions (D $x)))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: cImpliesD
      (Implication (Premises (C $x)) (Conclusions (D $x)))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (let
      (: $prf
         (Implication (Premises (A $x)) (Conclusions (D $x)))
         $tv)
      (query 100 deductionRevisionImplicationKb
         (: $prf
            (Implication (Premises (A $x)) (Conclusions (D $x)))
            $tv))
      $tv)
   (CTV (STV 0.125 0.9473684210526316) (STV 0.0 1.0)))
