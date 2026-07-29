!(import! &self ../petta_chainer)

!(compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))

!(compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

;; Concrete Inheritance queries have one non-Member producer: the compiler's
;; total-implication view. Both deduction chains revise inside that view.
!(test
   (collapse (query 60 deductionRevisionKb (: $prf (Inheritance A D) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               ((inheritance-implication bInheritsD)
                  ((inheritance-implication aInheritsB) (ctx proof 0)))
               ((inheritance-implication cInheritsD)
                  ((inheritance-implication aInheritsC) (ctx proof 0))))
            (merge/revision
               ((inheritance-implication bInheritsD)
                  ((inheritance-implication aInheritsB) (ctx proof 1)))
               ((inheritance-implication cInheritsD)
                  ((inheritance-implication aInheritsC) (ctx proof 1))))))
      (Inheritance A D)
      (STV 0.49999983333327785 0.22475956376843811))))



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
   (query 100 deductionRevisionImplicationKb
      (: $prf
         (Implication (Premises (A $x)) (Conclusions (D $x)))
         $tv))
   (:
      (total-implication
         (merge/revision
            (cImpliesD (aImpliesC (ctx proof 2)))
            (bImpliesD (aImpliesB (ctx proof 2))))
         (merge/revision
            (bImpliesD (aImpliesB (ctx proof 3)))
            (cImpliesD (aImpliesC (ctx proof 3)))))
      (Implication (Premises (A $x)) (Conclusions (D $x)))
      (CTV
         (STV 0.125 0.9692294378874315)
         (STV 0.0 0.9999367205825538))))
