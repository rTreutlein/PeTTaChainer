!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd deductionRevisionKb (: aInheritsB (Inheritance A B) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: aInheritsC (Inheritance A C) (STV 0.25 0.9)))

!(compileadd deductionRevisionKb (: bInheritsD (Inheritance B D) (STV 0.5 0.9)))

!(compileadd deductionRevisionKb (: cInheritsD (Inheritance C D) (STV 0.5 0.9)))

;; A class link is the implication between its two classes, so the concept
;; chains A -> B -> D and A -> C -> D revise as the implications below do.
;; Stated as STVs, the links' negative branches are unknown: no member gives
;; a base rate.
!(test
   (collapse (query 60 deductionRevisionKb (: $prf (Inheritance A D) $tv)))
   ((: (conditional-implication
          (merge/revision
             (by cInheritsD (by aInheritsC (ctx proof 0)))
             (by bInheritsD (by aInheritsB (ctx proof 0)))))
       (Inheritance A D)
       (STV 0.5 0.010716021787382275))))



!(compileadd deductionRevisionImplicationKb
   (: aImpliesB
      (Implication (A $x) (B $x))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: aImpliesC
      (Implication (A $x) (C $x))
      (CTV (STV 0.25 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: bImpliesD
      (Implication (B $x) (D $x))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(compileadd deductionRevisionImplicationKb
   (: cImpliesD
      (Implication (C $x) (D $x))
      (CTV (STV 0.5 0.9) (STV 0.0 1.0))))

!(test
   (query 100 deductionRevisionImplicationKb (: $prf (Implication (A $x) (D $x)) $tv))
   (:
      (conditional-implication
         (merge/revision
            (by cImpliesD (by aImpliesC (ctx proof 1)))
            (by bImpliesD (by aImpliesB (ctx proof 1)))))
      (Implication (A $_1139496) (D $_1139496))
      (STV 0.125 0.9692294378874315)))
