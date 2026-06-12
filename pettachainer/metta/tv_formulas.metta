(= (CTVFormula (CTV $pos $_neg) $ctv) (CTVFormula $pos $ctv))

(= (CTVFormula (STV $as $ac) (CTV (STV $bs_a $bc_a) (STV $bs_na $bc_na)))
   (STV
      (+ (* $bs_a $as) (* $bs_na (- 1 $as)))
      (+ (* $as (min $bc_a $ac)) (* (- 1 $as) (min $bc_na $ac)))))

(= (AndFormula (STV $si $ci) (STV $sa $ca)) (let* (($sb (* $si $sa)) ($cb (min $ci $ca))) (STV $sb $cb)))

(= (OrFormula (STV $si $ci) (STV $sa $ca)) (let* (($sb (- (+ $si $sa) (* $si $sa))) ($cb (min $ci $ca))) (STV $sb $cb)))

(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb)) (STV (max 0.0 (- $sa $sb)) (min $ca $cb)))

(= (AndProjection (STV $sab $cab) (STV $sa $ca))
   (if (== $sa 0.0)
      (STV 0.0 0.0)
      (STV (min 1.0 (/ $sab $sa)) (min $cab $ca))))

(= (OrProjection (STV $sab $cab) (STV $sa $ca))
   (if (== $sa 1.0)
      (STV 0.0 0.0)
      (STV (min 1.0 (max 0.0 (/ (- $sab $sa) (- 1.0 $sa)))) (min $cab $ca))))

(= (DistGreaterThanFormula (ParticleDist $pid $scale) $threshold)
   (let $pairs (particle-fetch-pairs $pid)
      (STV (* $scale (dist-prob-gt $pairs $threshold)) (particle-confidence-from-pairs $pairs))))

(= (DistGreaterThanDistFormula $pda $pdb)
   (let*
      (($pida (particle-dist-id $pda))
        ($pidb (particle-dist-id $pdb))
        ($scalea (particle-dist-scale $pda))
        ($scaleb (particle-dist-scale $pdb))
        ($pairsa (particle-fetch-pairs $pida))
        ($pairsb (particle-fetch-pairs $pidb))
        ($ca (particle-confidence-from-pairs $pairsa))
        ($cb (particle-confidence-from-pairs $pairsb)))
      (STV (* (* $scalea $scaleb) (dist-prob-gt2 $pairsa $pairsb)) (min $ca $cb))))

(= (NotFormula (STV $s $c)) (STV (- 1 $s) $c))

(= (InversionSmallestIntersectionProbability $sa $sb)
   (max 0.0 (/ (- (+ $sa $sb) 1.0) $sa)))

(= (InversionLargestIntersectionProbability $sa $sb)
   (min 1.0 (/ $sb $sa)))

(= (InversionConsistency (STV $sa $_ca) (STV $sb $_cb) (STV $sab $_cab))
   (if (<= $sa 0.0) false
      (if (<= $sb 0.0) false
         (and (<= (InversionSmallestIntersectionProbability $sa $sb) $sab)
            (<= $sab (InversionLargestIntersectionProbability $sa $sb))))))

(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (STV $s $c))
   (BaseRateEvidence (+ $wsum (* $s $c)) (+ $csum $c)))
(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (CTV $pos $_neg))
   (BaseRateAcc (BaseRateEvidence $wsum $csum) $pos))

(= (evidence-confidence-k) 800.0)

(= (count-confidence $n) (/ $n (+ $n (evidence-confidence-k))))

(= (BaseRateTv (BaseRateEvidence $wsum $csum))
   (if (<= $csum 0.0) no-evidence
      (STV (/ $wsum $csum) (count-confidence $csum))))

(= (CTVInversionFormula no-evidence $_btv $_itv) (empty))
(= (CTVInversionFormula (STV $_sa $_ca) no-evidence $_itv) (empty))
(= (CTVInversionFormula (STV $sa $ca) (STV $sb $cb) (CTV (STV $sb_a $cb_a) (STV $sb_na $cb_na)))
   (if (or (<= $sb 0.0) (>= $sb 1.0))
      (CTV (STV 0.0 0.0) (STV 0.0 0.0))
      (CTV
         (STV (min 1.0 (/ (* $sb_a $sa) $sb)) (* (min-atom ($ca $cb $cb_a)) 0.9))
         (STV (min 1.0 (/ (* (- 1.0 $sb_a) $sa) (- 1.0 $sb))) (* (min-atom ($ca $cb $cb_na)) 0.9)))))

(= (Equal $a $b) (== $a $b))

(= (NotEqual $a $b) (not (== $a $b)))
