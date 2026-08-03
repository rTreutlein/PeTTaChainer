!(import! &self petta_chainer)

(: NoEvidenceSide Type)
(: none NoEvidenceSide)
(: EvidencePolarity Type)
(: pos EvidencePolarity)
(: neg EvidencePolarity)
(: EvidenceCase Type)
(: EvidenceCase
   (-[det]-> EvidencePolarity STVType EvidenceCase))
(: TotalEvidenceTvs Type)
(: TotalEvidenceTvs
   (-[det]-> (| STVType NoEvidenceSide)
       (| STVType NoEvidenceSide) TotalEvidenceTvs))

(: TotalEvidenceOr
   (-[det]-> (| STVType NoEvidenceSide) STVType STVType))
(= (TotalEvidenceOr none $right) $right)
(= (TotalEvidenceOr (STV $ls $lc) (STV $rs $rc))
   (or-stv-fields $ls $lc $rs $rc))

(: TotalEvidenceTv
   (-[det]-> (| STVType NoEvidenceSide) STVType))
(= (TotalEvidenceTv none) (STV 0.0 0.0))
(= (TotalEvidenceTv (STV $s $c)) (STV $s $c))

(: TotalEvidenceAcc
   (-[det]-> TotalEvidenceTvs EvidenceCase  TotalEvidenceTvs))
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase pos $tv))
   (TotalEvidenceTvs (TotalEvidenceOr $pos-tv $tv) $neg-tv))
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase neg $tv))
   (TotalEvidenceTvs $pos-tv (TotalEvidenceOr $neg-tv $tv)))

(: TotalEvidenceCTVModusPonensFormula
   (-[nondet]-> TV TotalEvidenceTvs STVType))
(= (TotalEvidenceCTVModusPonensFormula $atv $evidence-tvs)
   (if (= $evidence-tvs (TotalEvidenceTvs none none))
	      (empty)
	      (let (TotalEvidenceTvs $pos-tv $neg-tv) $evidence-tvs
	         (CTVModusPonensFormula $atv (CTV (TotalEvidenceTv $pos-tv) (TotalEvidenceTv $neg-tv))))))

!(compileadd kb (: ta (Tall alice) (STV 0.9 0.5)))
!(compileadd kb (: fa (Female alice) (STV 0.9 0.5)))

!(compileadd kb (: tm (Tall mary) (STV 0.9 0.5)))
!(compileadd kb (: fm (Female mary) (STV 0.9 0.5)))

!(compileadd kb (: tl (Tall luci) (STV 0.1 0.5)))
!(compileadd kb (: fl (Female luci) (STV 0.9 0.5)))

!(compileadd kb (: tb (Female bob) (STV 0.5 1.0)))

!(add-to-kb
   (rules
      (((($p1 $x) (kb $ctx $vars) $p1prf $p1tv)
        (($p2 $x) (kb $ctx $vars) $p2prf $p2tv)
        (CPU AndFormula ($p1tv $p2tv) $case-tv))
       |-
       ((TotalEvidence pos $p1 $p2 $x $case-tv)
          (kb $ctx $vars)
          (total-pos (conjunction $p1prf $p2prf))
          $case-tv))))

!(add-to-kb
   (rules
      (((($p1 $x) (kb $ctx $vars) $p1prf $p1tv)
        (CPU NotFormula ($p1tv) $not-p1tv)
        (($p2 $x) (kb $ctx $vars) $p2prf $p2tv)
        (CPU AndFormula ($not-p1tv $p2tv) $case-tv))
       |-
       ((TotalEvidence neg $p1 $p2 $x $case-tv)
          (kb $ctx $vars)
          (total-neg (conjunction (negated $p1prf) $p2prf))
          $case-tv))))

; Generic total implication introduction/application rule. It keeps ii-style
; predicate variables, but folds both P(B|A) and P(B|Not A) evidence through
; one aggregate premise so the conjunction proofs remain visible.
!(add-to-kb
   (rules
      (((($p1 $y) (kb $ctx $vars) $apr $atv)
        (CPU NotEqual ($p1 $p2) true)
        (CPU FoldAllCompiled
           (kb
              (TotalEvidence $case $p1 $p2 $x $case-tv)
              (extract-value
                 (TotalEvidence $case $p1 $p2 $x $case-tv)
                 (EvidenceCase $case $case-tv))
              (TotalEvidenceTvs none none)
              TotalEvidenceAcc
              identity
              result-tv)
           $evidence-tvs)
        (CPU TotalEvidenceCTVModusPonensFormula ($atv $evidence-tvs) $btv))
       |-
       (($p2 $y)
          (kb $ctx $vars)
          (ii_total $apr cpu)
          $btv))))

!(=================================================)
!(query 50 kb
   (: $prf
      (Implication (Tall $x) (Female $x))
      $stv))

!(=================================================)
!(query 50 kb (: $prf (Tall bob) $stv))
