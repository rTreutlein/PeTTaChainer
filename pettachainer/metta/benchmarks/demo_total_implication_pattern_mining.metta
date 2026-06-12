!(import! &self petta_chainer)

(= (PMBenchListCount ()) 0)
(= (PMBenchListCount (cons $_x $tail)) (+ 1 (PMBenchListCount $tail)))

(= (PMBenchPred $idx) (atom_concat PMPred $idx))
(= (PMBenchTargetPred $kb) (atom_concat PMTarget $kb))
(= (PMBenchObj $kb $idx) (pm-obj $kb $idx))
(= (PMBenchQueryObj $kb) (pm-query $kb))

(= (TotalEvidenceOr none $tv) $tv)
(= (TotalEvidenceOr $left $right) (OrFormula $left $right))
(= (TotalEvidenceTv none) (STV 0.0 0.0))
(= (TotalEvidenceTv $tv) $tv)
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase pos $tv))
   (TotalEvidenceTvs (TotalEvidenceOr $pos-tv $tv) $neg-tv))
(= (TotalEvidenceAcc (TotalEvidenceTvs $pos-tv $neg-tv) (EvidenceCase neg $tv))
   (TotalEvidenceTvs $pos-tv (TotalEvidenceOr $neg-tv $tv)))
(= (TotalEvidenceMpFormula $atv $evidence-tvs)
   (if (= $evidence-tvs (TotalEvidenceTvs none none))
      (empty)
      (let (TotalEvidenceTvs $pos-tv $neg-tv) $evidence-tvs
         (TotalMpFormula $atv (TotalEvidenceTv $pos-tv) (TotalEvidenceTv $neg-tv)))))

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
              result-tv)
           $evidence-tvs)
        (CPU TotalEvidenceMpFormula ($atv $evidence-tvs) $btv))
       |-
       (($p2 $y)
          (kb $ctx $vars)
          (ii_total $apr cpu)
          $btv))))

(= (PMBenchAddTarget $kb $idx)
   (let*
      (($obj (PMBenchObj $kb $idx))
       ($target-pred (PMBenchTargetPred $kb)))
      (compileadd kb
         (: (pm-target $idx)
            ($target-pred $obj)
            (STV 0.9 0.9)))))

(= (PMBenchAddTargets $kb $idx)
   (if (<= $idx 0) done
      (let $_ (PMBenchAddTarget $kb $idx)
         (PMBenchAddTargets $kb (- $idx 1)))))

(= (PMBenchAddPredObj $kb $pred-idx $obj)
   (let $pred (PMBenchPred $pred-idx)
      (compileadd kb
         (: (pm-pred $pred-idx $obj)
            ($pred $obj)
            (STV 0.9 0.9)))))

(= (PMBenchAddPredObjects $kb $pred-idx $obj-idx)
   (if (<= $obj-idx 0) done
      (let*
         (($obj (PMBenchObj $kb $obj-idx))
          ($_ (PMBenchAddPredObj $kb $pred-idx $obj)))
         (PMBenchAddPredObjects $kb $pred-idx (- $obj-idx 1)))))

(= (PMBenchAddPred $kb $pred-idx $obj-count)
   (let $_history (PMBenchAddPredObjects $kb $pred-idx $obj-count)
      (let $query-obj (PMBenchQueryObj $kb)
         (PMBenchAddPredObj $kb $pred-idx $query-obj))))

(= (PMBenchAddPreds $kb $pred-idx $obj-count)
   (if (<= $pred-idx 0) done
      (let $_ (PMBenchAddPred $kb $pred-idx $obj-count)
         (PMBenchAddPreds $kb (- $pred-idx 1) $obj-count))))

(= (PMBenchGenerate $kb $pred-count $obj-count)
   (let*
      (($t1 (current-time))
        ($_targets (PMBenchAddTargets $kb $obj-count))
        ($_preds (PMBenchAddPreds $kb $pred-count $obj-count))
        ($t2 (current-time)))
      (pmbench-generated
         (kb $kb)
         (predicates $pred-count)
         (objects $obj-count)
         (facts (+ $obj-count (* $pred-count (+ $obj-count 1))))
         (seconds (- $t2 $t1)))))

(= (PMBenchQuery $kb $pred-count $steps)
   (let*
      (($t1 (current-time))
        ($query-obj (PMBenchQueryObj $kb))
        ($target-pred (PMBenchTargetPred $kb))
        ($results
           (collapse
              (query $steps kb
                 (: $prf ($target-pred $query-obj) $tv))))
        ($t2 (current-time)))
      (pmbench-query
         (kb $kb)
         (candidate-predicates $pred-count)
         (steps $steps)
         (seconds (- $t2 $t1))
         (answers (PMBenchListCount $results)))))

(= (PMBenchCase $kb $pred-count $obj-count $steps)
   ((PMBenchGenerate $kb $pred-count $obj-count)
    (PMBenchQuery $kb $pred-count $steps)))

!(PMBenchCase pmBench05x10 5 10 80)
!(PMBenchCase pmBench10x10 10 10 120)
!(PMBenchCase pmBench20x10 20 10 180)
