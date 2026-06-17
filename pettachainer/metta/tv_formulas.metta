;; Idealized confidence via second-order uncertainty propagation. Treat each TV
;; as a Beta (strength = mean, confidence = count/(count+800)); propagate the
;; exact variance of sB = bs_a*as + bs_na*(1-as) through modus ponens, then
;; convert back to a confidence. Strengths are clipped off 0/1 so the Beta
;; variance and the back-conversion stay finite.
(= (ideal-clip $s) (max 0.000001 (min 0.999999 $s)))
(= (ideal-var $s $c)
   (let $cs (ideal-clip $s) (/ (* $cs (- 1.0 $cs)) (+ (confidence-to-count $c) 1.0))))
(= (ideal-mp-confidence $as $ac $bs_a $bc_a $bs_na $bc_na)
   (let*
      (($Va (ideal-var $bs_a $bc_a))
       ($Vna (ideal-var $bs_na $bc_na))
       ($Vz (ideal-var $as $ac))
       ($sB (+ (* $bs_a $as) (* $bs_na (- 1.0 $as))))
       ($VarsB
          (+ (* (* $as $as) $Va)
             (+ (* (* (- 1.0 $as) (- 1.0 $as)) $Vna)
                (+ (* (* (- $bs_a $bs_na) (- $bs_a $bs_na)) $Vz)
                   (* $Vz (+ $Va $Vna))))))
       )
      (ideal-conf-from-var $sB $VarsB)))

(= (CTVModusPonensFormula (CTV $pos $_neg) $ctv) (CTVModusPonensFormula $pos $ctv))

(= (CTVModusPonensFormula (STV $as $ac) (CTV (STV $bs_a $bc_a) (STV $bs_na $bc_na)))
   (STV
      (+ (* $bs_a $as) (* $bs_na (- 1 $as)))
      (ideal-mp-confidence $as $ac $bs_a $bc_a $bs_na $bc_na)))

;; Idealized confidence for product-form combinations. For And, sB = s1*s2 with
;; exact Var = V1*V2 + V1*s2^2 + s1^2*V2; for Or, sB = 1-(1-s1)(1-s2), the same
;; product variance on the complements. Then convert variance back to a count.
(= (ideal-prod-confidence $s1 $V1 $s2 $V2 $sB)
   (let*
      (($VarsB (+ (* $V1 $V2) (+ (* $V1 (* $s2 $s2)) (* (* $s1 $s1) $V2))))
       )
      (ideal-conf-from-var $sB $VarsB)))

(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (STV (* $si $sa)
      (ideal-prod-confidence $si (ideal-var $si $ci) $sa (ideal-var $sa $ca) (* $si $sa))))

(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (STV (- (+ $si $sa) (* $si $sa))
      (ideal-prod-confidence (- 1.0 $si) (ideal-var $si $ci) (- 1.0 $sa) (ideal-var $sa $ca)
         (- (+ $si $sa) (* $si $sa)))))

;; "A is likelier than B" as P(A and not B) under independence: s_a * (1 - s_b).
;; Multilinear (linear in each argument), consistent with And (s1*s2) and
;; Or (s1+s2-s1*s2), and free of the max(0, s_a - s_b) clamp's kink.
(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb)) (STV (* $sa (- 1.0 $sb)) (min $ca $cb)))

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

(= (WeightedBaseRateAcc (BaseRateEvidence $wsum $msum) (WeightedTv (STV $m $mc) (STV $s $c)))
   (let $mass (* (* $m $mc) $c)
      (BaseRateEvidence (+ $wsum (* $s $mass)) (+ $msum $mass))))
(= (WeightedBaseRateAcc (BaseRateEvidence $wsum $msum) (WeightedTv $mass-tv (CTV $pos $_neg)))
   (WeightedBaseRateAcc (BaseRateEvidence $wsum $msum) (WeightedTv $mass-tv $pos)))
(= (WeightedBaseRateTv (BaseRateEvidence $wsum $msum))
   (if (<= $msum 0.0) no-evidence
      (STV (/ $wsum $msum) (min 1.0 $msum))))

(= (WeightedBaseRateWithPriorAcc (BaseRateEvidenceWithPrior $prior $ev) $tv)
   (BaseRateEvidenceWithPrior $prior (WeightedBaseRateAcc $ev $tv)))

(= (BaseRateWithPriorFormula no-evidence no-evidence) no-evidence)
(= (BaseRateWithPriorFormula no-evidence $evidence) $evidence)
(= (BaseRateWithPriorFormula $prior no-evidence) $prior)
(= (BaseRateWithPriorFormula $prior $evidence) (mergetvs $prior $evidence))

(= (WeightedBaseRateWithPriorTv (BaseRateEvidenceWithPrior $prior $ev))
   (BaseRateWithPriorFormula (reduce $prior) (WeightedBaseRateTv $ev)))

(= (NegativeBranchStrength $sa $sb $sb_a)
   (if (>= $sa 1.0) $sb
      (max 0.0 (min 1.0 (/ (- $sb (* $sa $sb_a)) (- 1.0 $sa))))))

(= (HeuristicNegativeBranchFormula (STV $sa $ca) (STV $sb $cb) (STV $sb_a $cb_a))
   (STV
      (NegativeBranchStrength $sa $sb $sb_a)
      (* 0.25 (min-atom ($ca $cb $cb_a)))))

(= (ImplicationCTVFormula $_atv $_btv (CTV $pos $neg)) (CTV $pos $neg))
(= (ImplicationCTVFormula $atv $btv (STV $s $c))
   (CTV
      (STV $s $c)
      (HeuristicNegativeBranchFormula $atv $btv (STV $s $c))))

; Uniform 1/N node prior for individuals, where N is the number of distinct
; subjects observed. The fold collects each matched subject; UniformPriorTv
; dedups them and returns 1/N at a confidence reflecting how many objects we
; have observed. Used for the base rate of an individual (a singleton concept),
; which cannot be folded extensionally because nothing inherits an individual.
(= (list-len ()) 0)
(= (list-len (cons $_ $rest)) (+ 1 (list-len $rest)))

(= (CollectSubject $acc $subj) (cons $subj $acc))

(= (UniformPriorTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) (count-confidence $n)))))

(= (UniformPriorKnownTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) 1.0))))

(= (CTVInversionFormula no-evidence $_btv $_itv) (empty))
(= (CTVInversionFormula (STV $_sa $_ca) no-evidence $_itv) (empty))
;; Idealized inversion confidence. The inverted strength is a Bayes ratio
;; P(A|B) = sb_a*sa/sb (and P(A|not B) = (1-sb_a)*sa/(1-sb)); both depend on the
;; implication's positive branch sb_a, the base rates sa, sb. Propagate variance
;; through the ratio by the delta method (validated against Monte-Carlo) and
;; convert back to a count. (cb_na is unused: sb_na is redundant given sb_a, sa,
;; sb.)
;; convert a strength + its variance to a confidence. The propagated variance is
;; clamped to the max-entropy variance s(1-s) (a Beta cannot be more spread than
;; that), so the count stays >= 0 and the confidence stays in [0,1).
(= (ideal-conf-from-var $s $Var)
   (if (<= $Var 0.0)
      0.9999
      (let*
         (($cs (ideal-clip $s))
          ($maxvar (* $cs (- 1.0 $cs)))
          ($v (min $Var $maxvar))
          ($nB (- (/ $maxvar $v) 1.0)))
         (max 0.000001 (/ $nB (+ $nB 800.0))))))

(= (ideal-ratio-var $p $Vp $sa $Vsa $q $Vq)
   (let*
      (($d1 (/ $sa $q))
       ($d2 (/ $p $q))
       ($d3 (/ (* $p $sa) (* $q $q))))
      (+ (* (* $d1 $d1) $Vp)
         (+ (* (* $d2 $d2) $Vsa)
            (* (* $d3 $d3) $Vq)))))

(= (CTVInversionFormula (STV $sa $ca) (STV $sb $cb) (CTV (STV $sb_a $cb_a) (STV $sb_na $cb_na)))
   (if (or (<= $sb 0.0) (>= $sb 1.0))
      (CTV (STV 0.0 0.0) (STV 0.0 0.0))
      (let*
         (($Va (ideal-var $sb_a $cb_a))
          ($Vsa (ideal-var $sa $ca))
          ($Vsb (ideal-var $sb $cb))
          ($s_pos (min 1.0 (/ (* $sb_a $sa) $sb)))
          ($s_neg (min 1.0 (/ (* (- 1.0 $sb_a) $sa) (- 1.0 $sb)))))
         (CTV
            (STV $s_pos (ideal-conf-from-var $s_pos (ideal-ratio-var $sb_a $Va $sa $Vsa $sb $Vsb)))
            (STV $s_neg (ideal-conf-from-var $s_neg (ideal-ratio-var (- 1.0 $sb_a) $Va $sa $Vsa (- 1.0 $sb) $Vsb)))))))

(= (Equal $a $b) (== $a $b))

(= (NotEqual $a $b) (not (== $a $b)))
