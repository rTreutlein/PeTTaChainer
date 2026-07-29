;; Idealized confidence via second-order uncertainty propagation. Treat each TV
;; as a Beta (strength = mean, confidence = count/(count+800)); propagate the
;; exact variance of sB = bs_a*as + bs_na*(1-as) through modus ponens, then
;; convert back to a confidence. Strengths are clipped off 0/1 so the Beta
;; variance and the back-conversion stay finite.
(: BaseRateEvidenceState Type)
(: BaseRateEvidence (-[det]-> Number Number BaseRateEvidenceState))

(: WeightedTV Type)
(: WeightedTv (-[det]-> TV TV WeightedTV))

(: BaseRateEvidenceWithPriorState Type)
(: BaseRateEvidenceWithPrior
   (-[det]-> BaseRatePrior BaseRateEvidenceState
       BaseRateEvidenceWithPriorState))

(: ideal-clip (-[det]-> Number Number))
(= (ideal-clip $s) (max 0.000001 (min 0.999999 $s)))

(: confidence-to-count (-[det]-> Number Number))
(= (confidence-to-count $conf) (/ (* $conf 800) (- 1 (min-atom ($conf 0.9999)))))

(: evidence-confidence-k (-[det]-> Number))
(= (evidence-confidence-k) 800.0)

(: count-confidence (-[det]-> Number Number))
(= (count-confidence $n) (/ $n (+ $n (evidence-confidence-k))))

(: ideal-var (-[det]-> Number Number Number))
(= (ideal-var $s $c)
   (let $cs (ideal-clip $s) (/ (* $cs (- 1.0 $cs)) (+ (confidence-to-count $c) 1.0))))

;; Convert a strength and its propagated variance back to confidence. Clamp the
;; variance to the maximum possible Bernoulli variance so the implied count is
;; non-negative and the resulting confidence remains in [0, 1).
(: ideal-conf-from-var (-[det]-> Number Number Number))
(= (ideal-conf-from-var $s $Var)
   (if (<= $Var 0.0)
      0.9999
      (let*
         (($cs (ideal-clip $s))
          ($maxvar (* $cs (- 1.0 $cs)))
          ($v (min $Var $maxvar))
          ($nB (- (/ $maxvar $v) 1.0)))
         (max 0.000001 (/ $nB (+ $nB 800.0))))))

(: ideal-mp-confidence (-[det]-> Number Number Number Number Number Number Number))
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

(: CTVModusPonensFormula (-[semidet]-> TV TV TV))
(= (CTVModusPonensFormula (CTV $pos $_neg) $ctv) (CTVModusPonensFormula $pos $ctv))

(= (CTVModusPonensFormula (STV $as $ac) (CTV (STV $bs_a $bc_a) (STV $bs_na $bc_na)))
   (STV
      (+ (* $bs_a $as) (* $bs_na (- 1 $as)))
      (ideal-mp-confidence $as $ac $bs_a $bc_a $bs_na $bc_na)))

(: CTVFormula (-[semidet]-> TV TV TV))
(= (CTVFormula $tv $ctv) (CTVModusPonensFormula $tv $ctv))

;; Idealized confidence for product-form combinations. For And, sB = s1*s2 with
;; exact Var = V1*V2 + V1*s2^2 + s1^2*V2; for Or, sB = 1-(1-s1)(1-s2), the same
;; product variance on the complements. Then convert variance back to a count.
(: ideal-prod-confidence (-[det]-> Number Number Number Number Number Number))
(= (ideal-prod-confidence $s1 $V1 $s2 $V2 $sB)
   (let*
      (($VarsB (+ (* $V1 $V2) (+ (* $V1 (* $s2 $s2)) (* (* $s1 $s1) $V2))))
       )
      (ideal-conf-from-var $sB $VarsB)))

;; No evidence about an input means no evidence about the combination: at zero
;; confidence the propagated variance of a clipped extreme strength is tiny, so
;; ideal-prod-confidence would otherwise turn a zero count into near-certainty.
(: AndFormula (-[semidet]-> TV TV TV))
(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (STV (* $si $sa)
      (if (or (<= $ci 0.0) (<= $ca 0.0))
         0.0
         (ideal-prod-confidence $si (ideal-var $si $ci) $sa (ideal-var $sa $ca) (* $si $sa)))))

(: OrFormula (-[semidet]-> TV TV TV))
(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (or-stv-fields $si $ci $sa $ca))

(: or-stv-fields
   (-[det]-> Number Number Number Number TV))
(= (or-stv-fields $si $ci $sa $ca)
   (STV (- (+ $si $sa) (* $si $sa))
      (if (or (<= $ci 0.0) (<= $ca 0.0))
         0.0
         (ideal-prod-confidence (- 1.0 $si) (ideal-var $si $ci) (- 1.0 $sa) (ideal-var $sa $ca)
            (- (+ $si $sa) (* $si $sa))))))

;; "A is likelier than B" as P(A and not B) under independence: s_a * (1 - s_b).
;; Multilinear (linear in each argument), consistent with And (s1*s2) and
;; Or (s1+s2-s1*s2), and free of the max(0, s_a - s_b) clamp's kink.
(: LikelierThanFormula (-[semidet]-> TV TV TV))
(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb)) (STV (* $sa (- 1.0 $sb)) (min $ca $cb)))

(: AndProjection (-[semidet]-> TV TV TV))
(= (AndProjection (STV $sab $cab) (STV $sa $ca))
   (if (== $sa 0.0)
      (STV 0.0 0.0)
      (STV (min 1.0 (/ $sab $sa)) (min $cab $ca))))

(: AndMarginalProjection (-[semidet]-> TV TV))
(= (AndMarginalProjection (STV $sab $cab))
   (STV $sab
      (count-confidence (* $sab (confidence-to-count $cab)))))

(: OrProjection (-[semidet]-> TV TV TV))
(= (OrProjection (STV $sab $cab) (STV $sa $ca))
   (if (== $sa 1.0)
      (STV 0.0 0.0)
      (STV (min 1.0 (max 0.0 (/ (- $sab $sa) (- 1.0 $sa)))) (min $cab $ca))))

(: NotFormula (-[semidet]-> TV TV))
(= (NotFormula (STV $s $c)) (STV (- 1 $s) $c))

(: InversionSmallestIntersectionProbability (-[det]-> Number Number Number))
(= (InversionSmallestIntersectionProbability $sa $sb)
   (max 0.0 (/ (- (+ $sa $sb) 1.0) $sa)))

(: InversionLargestIntersectionProbability (-[det]-> Number Number Number))
(= (InversionLargestIntersectionProbability $sa $sb)
   (min 1.0 (/ $sb $sa)))

(: InversionConsistency (-[semidet]-> TV TV TV Bool))
(= (InversionConsistency (STV $sa $_ca) (STV $sb $_cb) (STV $sab $_cab))
   (if (<= $sa 0.0) false
      (if (<= $sb 0.0) false
         (and (<= (InversionSmallestIntersectionProbability $sa $sb) $sab)
            (<= $sab (InversionLargestIntersectionProbability $sa $sb))))))

(: BaseRateAcc (-[semidet]-> BaseRateEvidenceState TV BaseRateEvidenceState))
(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (STV $s $c))
   (BaseRateEvidence (+ $wsum (* $s $c)) (+ $csum $c)))
(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (CTV $pos $_neg))
   (BaseRateAcc (BaseRateEvidence $wsum $csum) $pos))

(: BaseRateTv (-[det]-> BaseRateEvidenceState TV))
(= (BaseRateTv (BaseRateEvidence $wsum $csum))
   (if (<= $csum 0.0) no-evidence
      (STV (/ $wsum $csum) (count-confidence $csum))))

(: WeightedBaseRateAcc
   (-[semidet]-> BaseRateEvidenceState (| TV WeightedTV)
       BaseRateEvidenceState))
(= (WeightedBaseRateAcc (BaseRateEvidence $wsum $msum) (WeightedTv (STV $m $mc) (STV $s $c)))
   (let $mass (* (* $m $mc) $c)
      (BaseRateEvidence (+ $wsum (* $s $mass)) (+ $msum $mass))))
(= (WeightedBaseRateAcc $acc (WeightedTv $mass-tv (CTV $pos $_neg)))
   (WeightedBaseRateAcc $acc (WeightedTv $mass-tv $pos)))
(= (WeightedBaseRateAcc $acc no-evidence) $acc)
(: WeightedBaseRateTv (-[det]-> BaseRateEvidenceState TV))
(= (WeightedBaseRateTv (BaseRateEvidence $wsum $msum))
   (if (<= $msum 0.0) no-evidence
      (STV (/ $wsum $msum) (min 1.0 $msum))))
(: WeightedCountBaseRateTv (-[det]-> BaseRateEvidenceState TV))
(= (WeightedCountBaseRateTv (BaseRateEvidence $wsum $msum))
   (if (<= $msum 0.0) no-evidence
      (STV (/ $wsum $msum) (count-confidence $msum))))
(: WeightedUniverseBaseRateTv (-[det]-> Number BaseRateEvidenceState TV))
(= (WeightedUniverseBaseRateTv $universe-size (BaseRateEvidence $wsum $msum))
   (if (or (<= $msum 0.0) (<= $universe-size 0.0)) no-evidence
      (STV (/ $wsum $msum) (min 1.0 (/ $msum $universe-size)))))

(: WeightedBaseRateWithPriorAcc
   (-[semidet]-> BaseRateEvidenceWithPriorState (| TV WeightedTV)
       BaseRateEvidenceWithPriorState))
(= (WeightedBaseRateWithPriorAcc (BaseRateEvidenceWithPrior $prior $ev) $tv)
   (BaseRateEvidenceWithPrior $prior (WeightedBaseRateAcc $ev $tv)))

(: BaseRateWithPriorFormula (-[semidet]-> TV TV TV))
(= (BaseRateWithPriorFormula $prior $evidence)
   (if (== $prior no-evidence) $evidence
      (if (== $evidence no-evidence) $prior (mergetvs $prior $evidence))))

(: NegativeBranchStrength (-[det]-> Number Number Number Number))
(= (NegativeBranchStrength $sa $sb $sb_a)
   (if (>= $sa 1.0) $sb
      (max 0.0 (min 1.0 (/ (- $sb (* $sa $sb_a)) (- 1.0 $sa))))))

(: HeuristicNegativeBranchFormula (-[semidet]-> TV TV TV TV))
(= (HeuristicNegativeBranchFormula (STV $sa $ca) (STV $sb $cb) (STV $sb_a $cb_a))
   (STV
      (NegativeBranchStrength $sa $sb $sb_a)
      (* 0.25 (min $ca (min $cb $cb_a)))))

; TV is the nominal domain shared by STV, CTV, and no-evidence. The result is a
; CTV for either concrete input variant.
(: ImplicationCTVFormula (-[semidet]-> TV TV TV TV))
(= (ImplicationCTVFormula $atv $btv $itv)
   (case $itv
      (((CTV $pos $neg) (CTV $pos $neg))
       ((STV $s $c)
          (let*
             (($normalized-atv
                 (if (== $atv no-evidence) (STV 0.0 0.0) $atv))
              ($normalized-btv
                 (if (== $btv no-evidence) (STV 0.0 0.0) $btv)))
             (CTV
                (STV $s $c)
                (HeuristicNegativeBranchFormula
                   $normalized-atv $normalized-btv (STV $s $c))))))))

; Uniform 1/N node prior for individuals, where N is the number of distinct
; subjects observed. The fold collects each matched subject; UniformPriorTv
; dedups them and returns 1/N at a confidence reflecting how many objects we
; have observed. Used for the base rate of an individual (a singleton concept),
; which cannot be folded extensionally because nothing inherits an individual.
(: list-len (-[det]-> (List $a) Number))
(= (list-len ()) 0)
(= (list-len (cons $_ $rest)) (+ 1 (list-len $rest)))

(: CollectSubject (-[det]-> (List $subject) $subject (List $subject)))
(= (CollectSubject $acc $subj) (cons $subj $acc))

(: UniformPriorTv (-[det]-> (List $subject) TV))
(= (UniformPriorTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) (count-confidence $n)))))

(: UniformPriorKnownTv (-[det]-> (List $subject) TV))
(= (UniformPriorKnownTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) 1.0))))

(: CTVInversionFormula (-[semidet]-> TV TV TV TV))
(= (CTVInversionFormula no-evidence $_btv $_itv) (empty))
(= (CTVInversionFormula (STV $_sa $_ca) no-evidence $_itv) (empty))
;; Idealized inversion confidence. The inverted strength is a Bayes ratio
;; P(A|B) = sb_a*sa/sb (and P(A|not B) = (1-sb_a)*sa/(1-sb)); both depend on the
;; implication's positive branch sb_a, the base rates sa, sb. Propagate variance
;; through the ratio by the delta method (validated against Monte-Carlo) and
;; convert back to a count. (cb_na is unused: sb_na is redundant given sb_a, sa,
;; sb.)
(: ideal-ratio-var (-[det]-> Number Number Number Number Number Number Number))
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
      ;; Reject contradictory inversions: when P(A) > 0, the implication's
      ;; P(B|A) must lie within the Frechet bounds set by the base rates P(A),
      ;; P(B). Outside them the marginals and conditional cannot coexist, so the
      ;; inverse does not hold (clamping the ratio would assert it anyway).
      (if
         (if (> $sa 0.0)
            (InversionConsistency
               (STV $sa $ca)
               (STV $sb $cb)
               (STV $sb_a $cb_a))
            True)
         (let*
         (($Va (ideal-var $sb_a $cb_a))
          ($Vsa (ideal-var $sa $ca))
          ($Vsb (ideal-var $sb $cb))
          ($s_pos (min 1.0 (/ (* $sb_a $sa) $sb)))
          ($s_neg (min 1.0 (/ (* (- 1.0 $sb_a) $sa) (- 1.0 $sb)))))
         (CTV
            (STV $s_pos (ideal-conf-from-var $s_pos (ideal-ratio-var $sb_a $Va $sa $Vsa $sb $Vsb)))
            (STV $s_neg (ideal-conf-from-var $s_neg (ideal-ratio-var (- 1.0 $sb_a) $Va $sa $Vsa (- 1.0 $sb) $Vsb)))))
         (empty))))

(: Equal (-[det]-> $a $b Bool))
(= (Equal $a $b) (== $a $b))

(: NotEqual (-[det]-> $a $b Bool))
(= (NotEqual $a $b) (not (== $a $b)))
;; Merging two zero-confidence TVs has no evidence to weight the strengths by;
;; average them at confidence 0 instead of dividing by the zero total count.
(: merge-stv-fields
   (-[det]-> Number Number Number Number TV))
(= (merge-stv-fields $m1 $conf1 $m2 $conf2)
   (let*
      (($count1 (confidence-to-count $conf1))
        ($count2 (confidence-to-count $conf2))
        ($c (+ $count1 $count2)))
      (if (<= $c 0.0)
         (STV (/ (+ $m1 $m2) 2) 0.0)
         (STV (/ (+ (* $m1 $count1) (* $m2 $count2)) $c) (/ $c (+ $c 800))))))

(: merge-stvs
   (-[det]-> (STV Number Number) (STV Number Number) TV))
(= (merge-stvs (STV $m1 $conf1) (STV $m2 $conf2))
   (merge-stv-fields $m1 $conf1 $m2 $conf2))

(: mergetvs (-[semidet]-> TV TV TV))
(= (mergetvs (STV $m1 $conf1) (STV $m2 $conf2))
   (merge-stv-fields $m1 $conf1 $m2 $conf2))
