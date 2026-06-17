!(import! &self petta_chainer)

(= (TruthW2C $w) (/ $w (+ $w 1.0)))
(= (/safe $a $b) (if (> $b 0.0) (/ $a $b) 0.0))

(= (InductionFormula (STV $sA $_cA)
      (STV $sB $_cB)
      (STV $sC $_cC)
      (STV $sCA $cCA)
      (STV $sCB $cCB))
   (STV
      (+
         (/safe (* (* $sCA $sCB) $sB) $sA)
         (*
            (- 1 (/safe (* $sCA $sB) $sA))
            (/safe (- $sC (* $sB $sCB)) (- 1 $sB))))
      (TruthW2C (* (* $sCB $cCB) $cCA))))

!(set-base-rate ravenInductionKb (Inheritance raven) (STV 0.25 0.9))
!(set-base-rate ravenInductionKb (Inheritance (IntSet black)) (STV 0.25 0.9))
!(set-base-rate ravenInductionKb (Inheritance $x) (STV 0.25 0.9))

!(compileadd ravenInductionKb (: rv1Raven (Inheritance rv1 raven) (STV 0.9 0.9)))

!(compileadd ravenInductionKb (: rv2Raven (Inheritance rv2 raven) (STV 0.9 0.9)))

!(compileadd ravenInductionKb (: rv1Black (Inheritance rv1 (IntSet black)) (STV 0.8 0.9)))

!(compileadd ravenInductionKb (: rv2NotBlack (Inheritance rv2 (IntSet black)) (STV 0.0 0.9)))

!(mark-logic-rule inheritanceInduction)

!(add-atom rules
   (990001
      ((Inheritance $a $b) (ravenInductionKb $ctx $vars) (inheritanceInduction $prf1 $prf2) $outtv)
      (((Inheritance $c $a) (ravenInductionKb $ctx $vars) $prf1 $t1)
       ((Inheritance $c $b) (ravenInductionKb $ctx $vars) $prf2 $t2)
       (CPU InductionFormula ((STV 0.25 0.9) (STV 0.25 0.9) (STV 0.25 0.9) $t1 $t2) $outtv))))

!(add-atom ccls_index
   (((Inheritance $a $b) (ravenInductionKb $ctx $vars) (inheritanceInduction $prf1 $prf2) $outtv) 990001))

!(add-atom ccls_head_index ((fwd_trigger ravenInductionKb Inheritance) 990001))

!(test
   (query 100 ravenInductionKb (: $prf (Inheritance raven (IntSet black)) $tv))
   (: (merge/revision
         (inheritanceInduction rv1Raven rv1Black)
         (inheritanceInduction rv2Raven rv2NotBlack))
      (Inheritance raven (IntSet black))
      (STV 0.7266666666666668 0.3932038834951457)))
