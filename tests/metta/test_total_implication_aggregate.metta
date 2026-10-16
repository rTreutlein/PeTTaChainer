!(import! &self ../../pettachainer/metta/petta_chainer)

;; Round 1: H2 removal: current cross-predicate aggregate members include admissible derived evidence, rather than historical leaf-only views.

(: TotalEvidenceSentinel Type)
(: none TotalEvidenceSentinel)
(: TotalEvidenceTvs Type)
(: TotalEvidenceTvs
   (-[det]-> (| STVType TotalEvidenceSentinel)
       (| STVType TotalEvidenceSentinel)
       TotalEvidenceTvs))
(: EvidenceCase Type)
(: EvidenceCase (-[det]-> $evidence STVType EvidenceCase))
(: TotalEvidenceOr
   (-[det]-> (| STVType TotalEvidenceSentinel)
       STVType STVType))
(: TotalEvidenceTv
   (-[det]-> (| STVType TotalEvidenceSentinel) STVType))
(: TotalEvidenceKnownTv (-[det]-> STVType STVType))
(: TotalEvidenceAcc
   (-[semidet]-> TotalEvidenceTvs EvidenceCase TotalEvidenceTvs))
(: TotalEvidenceCTVModusPonensFormula
   (-[nondet]-> TV TotalEvidenceTvs STVType))

(= (TotalEvidenceOr none (STV $rs $rc))
   (STV $rs $rc))
(= (TotalEvidenceOr (STV $ls $lc) (STV $rs $rc))
   (or-stv-fields $ls $lc $rs $rc))
(= (TotalEvidenceKnownTv (STV $s $c)) (STV $s $c))
(= (TotalEvidenceTv none) (STV 0.0 0.0))
(= (TotalEvidenceTv (STV $s $c)) (STV $s $c))
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase pos $tv))
   (TotalEvidenceTvs (TotalEvidenceOr $pos-tv $tv) $neg-tv))
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase neg $tv))
   (TotalEvidenceTvs $pos-tv (TotalEvidenceOr $neg-tv $tv)))
(= (TotalEvidenceCTVModusPonensFormula $atv $evidence-tvs)
   (if (= $evidence-tvs (TotalEvidenceTvs none none))
	      (empty)
	      (let (TotalEvidenceTvs $pos-tv $neg-tv) $evidence-tvs
	         (CTVModusPonensFormula $atv (CTV (TotalEvidenceTv $pos-tv) (TotalEvidenceTv $neg-tv))))))

!(test (collapse (TotalEvidenceOr none (STV 0.7 0.5))) ((STV 0.7 0.5)))
!(test (collapse (TotalEvidenceTv none)) ((STV 0.0 0.0)))

!(compileadd kb (: ta (Tall alice) (STV 0.9 0.5)))
!(compileadd kb (: fa (Female alice) (STV 0.9 0.5)))
!(compileadd kb (: tm (Tall mary) (STV 0.9 0.5)))
!(compileadd kb (: fm (Female mary) (STV 0.9 0.5)))
!(compileadd kb (: tl (Tall luci) (STV 0.1 0.5)))
!(compileadd kb (: fl (Female luci) (STV 0.9 0.5)))
!(compileadd kb (: tb (Tall bob) (STV 0.5 1.0)))

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
              unit-stv)
           $evidence-tvs)
	        (CPU TotalEvidenceCTVModusPonensFormula ($atv $evidence-tvs) $btv))
       |-
       (($p2 $y)
          (kb $ctx $vars)
          (ii_total $apr cpu)
          $btv))))

!(test
   (query 50 kb (: $prf (Female bob) $stv))
   (: (ii_total tb (foldall-proof (total-pos (conjunction (merge/revision (ii_total fa (foldall-proof (total-pos (conjunction fm tm)) (total-neg (conjunction (negated fm) tm)) (total-pos (conjunction fl tl)) (total-neg (conjunction (negated fl) tl)))) ta) fa)) (total-neg (conjunction (negated (merge/revision (ii_total fa (foldall-proof (total-pos (conjunction fm tm)) (total-neg (conjunction (negated fm) tm)) (total-pos (conjunction fl tl)) (total-neg (conjunction (negated fl) tl)))) ta)) fa)) (total-pos (conjunction (merge/revision (ii_total fm (foldall-proof (total-pos (conjunction fa ta)) (total-neg (conjunction (negated fa) ta)) (total-pos (conjunction fl tl)) (total-neg (conjunction (negated fl) tl)))) tm) fm)) (total-neg (conjunction (negated tm) fm)) (total-pos (conjunction tl fl)) (total-neg (conjunction (negated tl) fl)))) (Female bob) (STV 0.8961967072948066 0.7857044342286138)))
