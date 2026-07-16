!(import! &self petta_chainer)

!(compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))

!(compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

(= (inheritance-result-tv (: $_proof $_type $tv)) $tv)

;; Both A -> B -> D and A -> C -> D are merged behind the single public
;; inheritance adapter instead of escaping as competing query results.
!(test
   (let $results
      (collapse (query 30 deductionRevisionKb (: $prf (Inheritance A D) $tv)))
      ((length $results) (map-flat inheritance-result-tv $results)))
   (1 ((STV 0.4999998333332778 0.002909100855559274))))



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
   (CTV (STV 0.125 0.9692294378874315) (STV 0.0 0.9998734491731702)))
