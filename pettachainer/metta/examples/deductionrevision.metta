!(import! &self petta_chainer)

!(compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))

!(compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

(= (inheritance-result-tv (: $_proof $_type $tv)) $tv)

;; Concrete Inheritance queries have one non-Member producer: the compiler's
;; total-implication view. Both deduction chains revise inside that view.
!(test
   (let $results
      (collapse (query 30 deductionRevisionKb (: $prf (Inheritance A D) $tv)))
      ((length $results) (map-flat inheritance-result-tv $results)))
   (1 ((STV 0.49999983333327785 0.0009715845768689697))))



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
   (CTV (STV 0.125 0.9692294378874315) (STV 0.0 0.9999367205825538)))
