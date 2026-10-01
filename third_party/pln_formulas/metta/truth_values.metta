;; Idealized confidence via second-order uncertainty propagation. Treat each TV
;; as a Beta (strength = mean, confidence = count/(count+k)); propagate the
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
(= (confidence-to-count $conf) (/ (* $conf (evidence-confidence-k)) (- 1 (min-atom ($conf 0.9999)))))

;; PLN's evidence parameter k: n pieces of evidence have confidence n/(n+k).
;; It is process-wide and read when a formula runs, so set it before building
;; knowledge bases; values already derived keep the k they were derived with.
!(change-state! evidence_confidence_k 800.0)

(: evidence-confidence-k (-[det]-> Number))
(= (evidence-confidence-k) (the Number (car-atom (collapse (get-state evidence_confidence_k)))))

(: set-evidence-confidence-k (-[det]-> Number Bool))
(= (set-evidence-confidence-k $k) (change-state! evidence_confidence_k $k))

;; The pseudo-observations of the prior with which Bayes' rule reads a
;; likelihood (see bayes-shrink). Process-wide, like k.
!(change-state! bayes_prior_count 0.2)

(: bayes-prior-count (-[det]-> Number))
(= (bayes-prior-count) (the Number (car-atom (collapse (get-state bayes_prior_count)))))

(: set-bayes-prior-count (-[det]-> Number Bool))
(= (set-bayes-prior-count $a) (change-state! bayes_prior_count $a))

;; A likelihood as Bayes' rule reads it: the mean of its Beta under a prior of
;; a observations centred on m, (s n + a m) / (n + a) for n = c k / (1 - c)
;; observations. The centre is independence: the value the likelihood would
;; have if the evidence told nothing about the hypothesis. So a likelihood
;; estimated from few observations moves a belief little, instead of making it
;; certain; a certain likelihood, or one with neither evidence nor prior, is
;; unchanged.
(: bayes-shrink (-[det]-> Number Number Number Number))
(= (bayes-shrink $s $c $m)
   (if (>= $c 1.0) $s
      (let* (($n (confidence-to-count $c))
             ($a (bayes-prior-count)))
         (if (<= (+ $n $a) 0.0) $s
            (/ (+ (* $s $n) (* $a $m)) (+ $n $a))))))

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
         (max 0.000001 (count-confidence $nB)))))

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

(: CTVModusPonensFormula
   (-[semidet]-> TV TV STVType))
(= (CTVModusPonensFormula (CTV $pos $_neg) $ctv) (CTVModusPonensFormula $pos $ctv))

(= (CTVModusPonensFormula (STV $as $ac) (CTV (STV $bs_a $bc_a) (STV $bs_na $bc_na)))
   (STV
      (+ (* $bs_a $as) (* $bs_na (- 1 $as)))
      (ideal-mp-confidence $as $ac $bs_a $bc_a $bs_na $bc_na)))

(: CTVFormula
   (-[semidet]-> TV TV STVType))
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
(: AndFormula (-[semidet]-> TV TV STVType))
(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (STV (* $si $sa)
      (if (or (<= $ci 0.0) (<= $ca 0.0))
         0.0
         (ideal-prod-confidence $si (ideal-var $si $ci) $sa (ideal-var $sa $ca) (* $si $sa)))))

(: OrFormula (-[det]-> STVType STVType STVType))
(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (or-stv-fields $si $ci $sa $ca))

(: or-stv-fields
   (-[det]-> Number Number Number Number STVType))
(= (or-stv-fields $si $ci $sa $ca)
   (STV (- (+ $si $sa) (* $si $sa))
      (if (or (<= $ci 0.0) (<= $ca 0.0))
         0.0
         (ideal-prod-confidence (- 1.0 $si) (ideal-var $si $ci) (- 1.0 $sa) (ideal-var $sa $ca)
            (- (+ $si $sa) (* $si $sa))))))

;; "A is likelier than B" as P(A and not B) under independence: s_a * (1 - s_b).
;; Multilinear (linear in each argument), consistent with And (s1*s2) and
;; Or (s1+s2-s1*s2), and free of the max(0, s_a - s_b) clamp's kink.
(: LikelierThanFormula (-[det]-> STVType STVType STVType))
(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb)) (STV (* $sa (- 1.0 $sb)) (min $ca $cb)))

(: AndProjection (-[det]-> STVType STVType STVType))
(= (AndProjection (STV $sab $cab) (STV $sa $ca))
   (if (== $sa 0.0)
      (STV 0.0 0.0)
      (STV (min 1.0 (/ $sab $sa)) (min $cab $ca))))

(: AndMarginalProjection (-[det]-> STVType STVType))
(= (AndMarginalProjection (STV $sab $cab))
   (STV $sab
      (count-confidence (* $sab (confidence-to-count $cab)))))

;; Solve E = D or U for the unknown child U. Strength is the exact noisy-OR
;; inverse. Confidence uses first-order variance propagation through
;; u = (e-d)/(1-d), so projection cannot inherit the total's confidence while
;; ignoring uncertainty in the known alternative.
(: OrProjection (-[det]-> STVType STVType STVType))
(= (OrProjection (STV $se $ce) (STV $sd $cd))
   (if (>= $sd 1.0)
      (STV 0.0 0.0)
      (let*
         (($den (- 1.0 $sd))
          ($su (min 1.0 (max 0.0 (/ (- $se $sd) $den))))
          ($Ve (ideal-var $se $ce))
          ($Vd (ideal-var $sd $cd))
          ($den2 (* $den $den))
          ($slope-d (/ (- 1.0 $se) $den2))
          ($Vu (+ (/ $Ve $den2) (* (* $slope-d $slope-d) $Vd))))
         (STV $su
            (if (or (<= $ce 0.0) (<= $cd 0.0))
               0.0
               (ideal-conf-from-var $su $Vu))))))

;; The unknown-witness residual is the same probabilistic projection as an
;; ordinary OR child: E = D or U. Keep the semantic name at the existential
;; compiler boundary while sharing the variance-aware implementation.
(: ExistentialResidualFormula (-[det]-> STVType STVType STVType))
(= (ExistentialResidualFormula $existential-tv $known-tv)
   (OrProjection $existential-tv $known-tv))

(: NotFormula (-[det]-> STVType STVType))
(= (NotFormula (STV $s $c)) (STV (- 1 $s) $c))

(: BaseRateAcc (-[semidet]-> BaseRateEvidenceState TV BaseRateEvidenceState))
(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (STV $s $c))
   (BaseRateEvidence (+ $wsum (* $s $c)) (+ $csum $c)))
(= (BaseRateAcc (BaseRateEvidence $wsum $csum) (CTV $pos $_neg))
   (BaseRateAcc (BaseRateEvidence $wsum $csum) $pos))

(: BaseRateTv
   (-[det]-> BaseRateEvidenceState OptionalSTV))
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
(: WeightedCountBaseRateTv
   (-[det]-> BaseRateEvidenceState OptionalSTV))
(= (WeightedCountBaseRateTv (BaseRateEvidence $wsum $msum))
   (if (<= $msum 0.0) no-evidence
      (STV (/ $wsum $msum) (count-confidence $msum))))
(: WeightedUniverseBaseRateTv
   (-[det]-> Number BaseRateEvidenceState OptionalSTV))
(= (WeightedUniverseBaseRateTv $universe-size (BaseRateEvidence $wsum $msum))
   (if (or (<= $msum 0.0) (<= $universe-size 0.0)) no-evidence
      (STV (/ $wsum $msum) (min 1.0 (/ $msum $universe-size)))))

(: WeightedBaseRateWithPriorAcc
   (-[semidet]-> BaseRateEvidenceWithPriorState (| TV WeightedTV)
       BaseRateEvidenceWithPriorState))
(= (WeightedBaseRateWithPriorAcc (BaseRateEvidenceWithPrior $prior $ev) $tv)
   (BaseRateEvidenceWithPrior $prior (WeightedBaseRateAcc $ev $tv)))

(: BaseRateWithPriorFormula
   (-[det]-> OptionalSTV OptionalSTV OptionalSTV))
(= (BaseRateWithPriorFormula no-evidence $evidence) $evidence)
(= (BaseRateWithPriorFormula (STV $s $c) no-evidence)
   (STV $s $c))
(= (BaseRateWithPriorFormula
      (STV $ps $pc) (STV $es $ec))
   (mergetvs (STV $ps $pc) (STV $es $ec)))

;; PLN admits P(B|A) only within the Frechet bounds its marginals set:
;; max(0, P(A)+P(B)-1)/P(A) <= P(B|A) <= P(B)/P(A). Estimates of the three that
;; violate them are reconciled by dropping the least evidence that satisfies
;; them, so a formula still applies, at lower confidence. Either the counts are
;; drained together, each in proportion to how far a unit of its evidence
;; moves the violated bound (over P(B)/P(A): lowering P(A) or P(B|A) or raising
;; P(B); under the lower bound: lowering P(A) or P(B) or raising P(B|A)), or one
;; estimate loses all its evidence and so constrains nothing; whichever drops
;; fewer counts is taken. Draining a positive count moves its mean by
;; (1 - p)/n and a negative one by p/n, so evidence of one kind alone cannot
;; move and only emptying removes it. Draining all movable counts restores the
;; bound, so the least drain that does is found by bisection. Adapted from
;; argset-chainer's tvconsistency.
(: STVTriple Type)
(: stv-triple (-[det]-> STVType STVType STVType STVTriple))

(: EvidenceCounts Type)
(: counts (-[det]-> Number Number Number Number Number Number EvidenceCounts))

(: DrainPlan Type)
(: drain-plan (-[det]-> Number STVTriple DrainPlan))

(: frechet-excess (-[det]-> Bool EvidenceCounts Number))
(= (frechet-excess $upper (counts $a1 $b1 $a2 $b2 $a3 $b3))
   (let* (($pa (/ $a1 (+ $a1 $b1)))
          ($pb (/ $a2 (+ $a2 $b2)))
          ($pab (/ $a3 (+ $a3 $b3))))
      (if $upper (- (* $pa $pab) $pb)
         (- (max 0.0 (- (+ $pa $pb) 1.0)) (* $pa $pab)))))

(: drain-counts (-[det]-> EvidenceCounts EvidenceCounts Number EvidenceCounts))
(= (drain-counts (counts $a1 $b1 $a2 $b2 $a3 $b3) (counts $r1 $s1 $r2 $s2 $r3 $s3) $n)
   (counts (- $a1 (* $n $r1)) (- $b1 (* $n $s1)) (- $a2 (* $n $r2))
      (- $b2 (* $n $s2)) (- $a3 (* $n $r3)) (- $b3 (* $n $s3))))

(: least-drain (-[det]-> Bool EvidenceCounts EvidenceCounts Number Number Number Number))
(= (least-drain $upper $counts $rates $lo $hi $steps)
   (if (<= $steps 0) $hi
      (let $mid (/ (+ $lo $hi) 2.0)
         (if (> (frechet-excess $upper (drain-counts $counts $rates $mid)) 0.0)
            (least-drain $upper $counts $rates $mid $hi (- $steps 1))
            (least-drain $upper $counts $rates $lo $mid (- $steps 1))))))

;; The least drain that empties a count, among those drained at all.
(: drain-limit (-[det]-> Number Number Number Number))
(= (drain-limit $count $rate $limit)
   (if (> $rate 0.0) (min (/ $count $rate) $limit) $limit))

(: counts-stv (-[det]-> Number Number STVType))
(= (counts-stv $a $b) (STV (/ $a (+ $a $b)) (count-confidence (+ $a $b))))

;; The drain of the movable counts, weighted wa, wb, wab (summing to w > 0), that
;; restores the bound, and the estimates it leaves.
(: drain-evidence
   (-[det]-> Bool EvidenceCounts Number Number Number Number Number Number Number Number Number
       DrainPlan))
(= (drain-evidence $upper $counts $wa $wb $wab $w $sb $sab $na $nb $nab)
   (let* (($ra (/ $wa $w))
          ($rb (/ $wb $w))
          ($rab (/ $wab $w))
          ($rates (if $upper (counts $ra 0.0 0.0 $rb $rab 0.0)
                     (counts $ra 0.0 $rb 0.0 0.0 $rab)))
          ($max (drain-limit (case $counts (((counts $alpha-a $_b1 $_a2 $_b2 $_a3 $_b3) $alpha-a))) $ra
                   (drain-limit (* (if $upper (- 1.0 $sb) $sb) $nb) $rb
                      (drain-limit (* (if $upper $sab (- 1.0 $sab)) $nab) $rab
                         (+ $na (+ $nb $nab))))))
          ($n (least-drain $upper $counts $rates 0.0 $max 60)))
      (case (drain-counts $counts $rates $n) (
         ((counts $a1 $b1 $a2 $b2 $a3 $b3)
            (drain-plan $n
               (stv-triple (counts-stv $a1 $b1) (counts-stv $a2 $b2) (counts-stv $a3 $b3))))))))

;; The estimate with the least evidence loses all of it.
(: empty-least-supported
   (-[det]-> STVType STVType STVType Number Number Number STVTriple))
(= (empty-least-supported (STV $sa $ca) (STV $sb $cb) (STV $sab $cab) $na $nb $nab)
   (if (<= $na (min $nb $nab)) (stv-triple (STV $sa 0.0) (STV $sb $cb) (STV $sab $cab))
      (if (<= $nb $nab) (stv-triple (STV $sa $ca) (STV $sb 0.0) (STV $sab $cab))
         (stv-triple (STV $sa $ca) (STV $sb $cb) (STV $sab 0.0)))))

(: ConsistentTriple (-[det]-> STVType STVType STVType STVTriple))
(= (ConsistentTriple (STV $sa $ca) (STV $sb $cb) (STV $sab $cab))
   (let* (($upper (> (* $sa $sab) $sb))
          ($lower (> (- (+ $sa $sb) 1.0) (* $sa $sab))))
      (if (if (if $upper true $lower) (> (min $ca (min $cb $cab)) 0.0) false)
         (let* (($na (confidence-to-count $ca))
                ($nb (confidence-to-count $cb))
                ($nab (confidence-to-count $cab))
                ($counts (counts (* $sa $na) (* (- 1.0 $sa) $na) (* $sb $nb)
                            (* (- 1.0 $sb) $nb) (* $sab $nab) (* (- 1.0 $sab) $nab)))
                ($wa (/ (* (if $upper $sab (- 1.0 $sab)) (- 1.0 $sa)) $na))
                ($wb (/ (if $upper $sb (- 1.0 $sb)) $nb))
                ($wab (/ (* $sa (if $upper (- 1.0 $sab) $sab)) $nab))
                ($w (+ $wa (+ $wb $wab)))
                ($emptied (empty-least-supported (STV $sa $ca) (STV $sb $cb) (STV $sab $cab) $na $nb $nab)))
            (if (<= $w 0.0) $emptied
               (case (drain-evidence $upper $counts $wa $wb $wab $w $sb $sab $na $nb $nab) (
                  ((drain-plan $n $drained)
                     (if (<= $n (min $na (min $nb $nab))) $drained $emptied))))))
         (stv-triple (STV $sa $ca) (STV $sb $cb) (STV $sab $cab)))))

(: normalize-stv
   (-[det]-> (| STVType NoEvidenceType) STVType))
(= (normalize-stv no-evidence) (STV 0.0 0.0))
(= (normalize-stv (STV $s $c)) (STV $s $c))

; TV is the nominal domain shared by STV, CTV, and no-evidence. The result is a
; CTV for either concrete input variant.
(: ImplicationCTVFormula
   (-[det]-> OptionalSTV OptionalSTV
       (| STVType CTVType) CTVType))
(= (ImplicationCTVFormula $atv $btv $itv)
   (case $itv
      (((CTV $pos $neg) (CTV $pos $neg))
       ;; P(B|not A) = (P(B) - P(A) P(B|A)) / (1 - P(A)) over the reconciled
       ;; estimates, which keeps it in [0, 1] up to rounding; its confidence is
       ;; a heuristic quarter of the weakest input's.
       ((STV $s $c)
          (case (ConsistentTriple (normalize-stv $atv) (normalize-stv $btv) (STV $s $c)) (
             ((stv-triple (STV $sa $ca) (STV $sb $cb) (STV $sab $cab))
                (CTV
                   (STV $sab $cab)
                   (STV
                      (if (>= $sa 1.0) $sb
                         (max 0.0 (min 1.0 (/ (- $sb (* $sa $sab)) (- 1.0 $sa)))))
                      (* 0.25 (min $ca (min $cb $cab))))))))))))

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

(: UniformPriorTv
   (-[det]-> (List $subject) OptionalSTV))
(= (UniformPriorTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) (count-confidence $n)))))

(: UniformPriorKnownTv
   (-[det]-> (List $subject) OptionalSTV))
(= (UniformPriorKnownTv $subjects)
   (let $n (list-len (list_to_set $subjects))
      (if (<= $n 0) no-evidence
         (STV (/ 1.0 $n) 1.0))))

(: CTVInversionFormula (-[semidet]-> TV TV TV TV))
(= (CTVInversionFormula no-evidence $_btv $_itv) (empty))
(= (CTVInversionFormula (STV $_sa $_ca) no-evidence $_itv) (empty))
;; P(B|A) is read under the Bayes prior centred on P(B) (bayes-shrink).
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

(= (CTVInversionFormula (STV $sa0 $ca0) (STV $sb0 $cb0) (CTV (STV $sb_a0 $cb_a0) (STV $_sb_na $_cb_na)))
   (if (or (<= $sb0 0.0) (>= $sb0 1.0))
      (CTV (STV 0.0 0.0) (STV 0.0 0.0))
      ;; The base rates and P(B|A) are reconciled first, so the ratios stay
      ;; within [0, 1] up to rounding and contradictory inputs invert at the
      ;; confidence their consistent part supports.
      (case (ConsistentTriple (STV $sa0 $ca0) (STV $sb0 $cb0) (STV (bayes-shrink $sb_a0 $cb_a0 $sb0) $cb_a0)) (
         ((stv-triple (STV $sa $ca) (STV $sb $cb) (STV $sb_a $cb_a))
            (let*
               (($Va (ideal-var $sb_a $cb_a))
                ($Vsa (ideal-var $sa $ca))
                ($Vsb (ideal-var $sb $cb))
                ($s_pos (min 1.0 (/ (* $sb_a $sa) $sb)))
                ($s_neg (min 1.0 (/ (* (- 1.0 $sb_a) $sa) (- 1.0 $sb)))))
               (CTV
                  (STV $s_pos (ideal-conf-from-var $s_pos (ideal-ratio-var $sb_a $Va $sa $Vsa $sb $Vsb)))
                  (STV $s_neg (ideal-conf-from-var $s_neg (ideal-ratio-var (- 1.0 $sb_a) $Va $sa $Vsa (- 1.0 $sb) $Vsb))))))))))

;; Bayes' rule for an instance whose prior P(A) and likelihoods P(B|A),
;; P(B|not A) are independent inputs: P(A|B) = u sa / (u sa + v (1 - sa)) with
;; u = P(B|A), v = P(B|not A), and P(A|not B) the same with 1 - u, 1 - v. P(B)
;; is not an input, so the delta-method variance needs no independence between
;; P(B) and the likelihoods it is computed from, and a certain prior keeps a
;; certain posterior. The likelihoods are read under the Bayes prior centred on
;; their pooled value, P(B) over both branches (bayes-shrink), so a likelihood
;; estimated from few observations moves the posterior little.
(: ideal-bayes-stv (-[det]-> Number Number Number Number Number Number STVType))
(= (ideal-bayes-stv $u $Vu $v $Vv $sa $Va)
   (let $d (+ (* $u $sa) (* $v (- 1.0 $sa)))
      (if (<= $d 0.0)
         (STV $sa 0.0)
         (let* (($s (/ (* $u $sa) $d))
                ($d2 (* $d $d))
                ($du (/ (* $v (* $sa (- 1.0 $sa))) $d2))
                ($dv (/ (* $u (* $sa (- 1.0 $sa))) $d2))
                ($ds (/ (* $u $v) $d2)))
            (STV $s
               (ideal-conf-from-var $s
                  (+ (* (* $du $du) $Vu)
                     (+ (* (* $dv $dv) $Vv) (* (* $ds $ds) $Va)))))))))

(: CTVBayesFormula (-[semidet]-> TV TV TV))
(= (CTVBayesFormula no-evidence $_ctv) (empty))
(= (CTVBayesFormula (STV $sa $ca) (CTV (STV $u0 $cu) (STV $v0 $cv)))
   (let* (($nu (confidence-to-count $cu))
          ($nv (confidence-to-count $cv))
          ($m (if (<= (+ $nu $nv) 0.0) 0.5 (/ (+ (* $u0 $nu) (* $v0 $nv)) (+ $nu $nv))))
          ($u (bayes-shrink $u0 $cu $m))
          ($v (bayes-shrink $v0 $cv $m))
          ($Va (ideal-var $sa $ca))
          ($Vu (ideal-var $u $cu))
          ($Vv (ideal-var $v $cv)))
      (CTV
         (ideal-bayes-stv $u $Vu $v $Vv $sa $Va)
         (ideal-bayes-stv (- 1.0 $u) $Vu (- 1.0 $v) $Vv $sa $Va))))

;; Complete one missing implication antecedent directly. For
;;
;;   (Implication (And O M) C)
;;
;; the completed rule is (Implication (And O C) M). Its positive branch is
;; P(M|O,C) = P(C|O,M) P(O,M) / P(O,C). The negative branch follows from the
;; same joint P(M,O,C): P(M|not(O,C)) = (P(M)-P(M,O,C))/(1-P(O,C)). This is
;; ordinary inversion when O is empty, but retaining O in both base-rate
;; patterns avoids the independence approximation introduced by inverting the
;; complete conjunction and projecting it afterwards.
(: ideal-antecedent-completion-neg-var
   (-[det]-> Number Number Number Number Number Number Number Number Number))
(= (ideal-antecedent-completion-neg-var
      $sm $Vm $sc_h $Vc_h $sh $Vh $sk $Vk)
   (let*
      (($den (- 1.0 $sk))
       ($joint (* $sc_h $sh))
       ($d-m (/ 1.0 $den))
       ($d-c_h (/ (- 0.0 $sh) $den))
       ($d-h (/ (- 0.0 $sc_h) $den))
       ($d-k (/ (- $sm $joint) (* $den $den))))
      (+ (* (* $d-m $d-m) $Vm)
         (+ (* (* $d-c_h $d-c_h) $Vc_h)
            (+ (* (* $d-h $d-h) $Vh)
               (* (* $d-k $d-k) $Vk))))))

(: CTVAntecedentCompletionFormula
   (-[semidet]-> TV TV TV TV TV))
(= (CTVAntecedentCompletionFormula
      no-evidence $_full-tv $_known-tv $_rule-ctv)
   (empty))
(= (CTVAntecedentCompletionFormula
      (STV $_sm $_cm) no-evidence $_known-tv $_rule-ctv)
   (empty))
(= (CTVAntecedentCompletionFormula
      (STV $_sm $_cm) (STV $_sh $_ch) no-evidence $_rule-ctv)
   (empty))
(= (CTVAntecedentCompletionFormula
      (STV $sm $cm)
      (STV $sh $ch)
      (STV $sk $ck)
      (CTV (STV $sc_h $cc_h) (STV $_sc_nh $_cc_nh)))
   (if (or (<= $sk 0.0) (>= $sk 1.0))
      (CTV (STV 0.0 0.0) (STV 0.0 0.0))
      (let $joint (* $sc_h $sh)
         (if
            (and
               (<= (max 0.0 (- (+ $sm $sk) 1.0)) $joint)
               (<= $joint (min $sm $sk)))
            (let*
               (($Vm (ideal-var $sm $cm))
                ($Vc_h (ideal-var $sc_h $cc_h))
                ($Vh (ideal-var $sh $ch))
                ($Vk (ideal-var $sk $ck))
                ($s-pos (min 1.0 (/ $joint $sk)))
                ($s-neg
                   (min 1.0 (/ (- $sm $joint) (- 1.0 $sk)))))
               (CTV
                  (STV $s-pos
                     (ideal-conf-from-var $s-pos
                        (ideal-ratio-var
                           $sc_h $Vc_h $sh $Vh $sk $Vk)))
                  (STV $s-neg
                     (ideal-conf-from-var $s-neg
                        (ideal-antecedent-completion-neg-var
                           $sm $Vm $sc_h $Vc_h $sh $Vh
                           $sk $Vk)))))
            (empty)))))

(: Equal (-[det]-> $a $b Bool))
(= (Equal $a $b) (== $a $b))

(: NotEqual (-[det]-> $a $b Bool))
(= (NotEqual $a $b) (not (== $a $b)))
;; Merging two zero-confidence TVs has no evidence to weight the strengths by;
;; average them at confidence 0 instead of dividing by the zero total count.
(: merge-stv-fields
   (-[det]-> Number Number Number Number STVType))
;; A certain truth value (confidence 1) stands for unlimited evidence, so
;; revising it with finite evidence leaves it unchanged; two certain values
;; average.
(= (merge-stv-fields $m1 $conf1 $m2 $conf2)
   (if (>= $conf1 1.0)
      (if (>= $conf2 1.0) (STV (/ (+ $m1 $m2) 2) 1.0) (STV $m1 $conf1))
      (if (>= $conf2 1.0) (STV $m2 $conf2)
         (let*
            (($count1 (confidence-to-count $conf1))
              ($count2 (confidence-to-count $conf2))
              ($c (+ $count1 $count2)))
            (if (<= $c 0.0)
               (STV (/ (+ $m1 $m2) 2) 0.0)
               (STV (/ (+ (* $m1 $count1) (* $m2 $count2)) $c) (count-confidence $c)))))))

(: merge-stvs
   (-[det]-> STVType STVType STVType))
(= (merge-stvs (STV $m1 $conf1) (STV $m2 $conf2))
   (merge-stv-fields $m1 $conf1 $m2 $conf2))

(: mergetvs (-[det]-> STVType STVType STVType))
(= (mergetvs (STV $m1 $conf1) (STV $m2 $conf2))
   (merge-stv-fields $m1 $conf1 $m2 $conf2))
