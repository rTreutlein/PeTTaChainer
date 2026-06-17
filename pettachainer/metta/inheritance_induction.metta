; Inheritance induction (extensional) with base rates derived from the facts.
;
; From two observed links sharing a subject -- (Inheritance C A) and
; (Inheritance C B) -- derive (Inheritance A B) with the PLN induction formula.
; All three node base rates are folded from the store rather than stipulated:
;   P(A), P(B) -- extensional means over the instances of each concept,
;   P(C)       -- the shared-subject (individual) prior, 1/N over the distinct
;                 observed subjects of the premise concept (uniform-prior fold).
;
; register-inheritance-induction! installs the rule for a given KB; the rule id
; and ccls indices are assigned automatically by add-to-kb.

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

(= (register-inheritance-induction! $kb)
   (progn
      (mark-logic-rule inheritanceInduction)
      (add-to-kb
         (rules
            ((((Inheritance $c $a) ($kb $ctx $vars) $prf1 $t1)
              ((Inheritance $c $b) ($kb $ctx $vars) $prf2 $t2)
              (CPU FoldAllCompiled
                 ($kb (Inheritance $xa $a) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)
                 $brA)
              (CPU FoldAllCompiled
                 ($kb (Inheritance $xb $b) extract-tv (BaseRateEvidence 0.0 0.0) BaseRateAcc base-rate result-tv)
                 $brB)
              (CPU FoldAllCompiled
                 ($kb (Inheritance $sc $a) (extract-value (Inheritance $sc $a) $sc) () CollectSubject uniform-prior result-tv)
                 $brC)
              (CPU InductionFormula ($brA $brB $brC $t1 $t2) $outtv))
             |-
             ((Inheritance $a $b) ($kb $ctx $vars) (inheritanceInduction $prf1 $prf2) $outtv))))))
