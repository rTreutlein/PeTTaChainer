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

;; The evidence count of a confidence, the inverse of count-confidence, so
;; revision adds counts at any confidence below 1: views near certainty keep
;; their weight however many are merged, in any order. A certain value (1) has
;; no finite count; the formulas read it as 10^4 k pieces of evidence, the
;; count of the most confident value they derive (ideal-conf-from-var).
(: confidence-to-count (-[det]-> Number Number))
(= (confidence-to-count $conf) (/ (* $conf (evidence-confidence-k)) (- 1 (if (< $conf 1.0) $conf 0.9999))))

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

;; Modus ponens whose consequent is itself an implication, A → (X → Y), read
;; as its exported form (A ∧ X) → Y: the derived X → Y keeps the rule's
;; negative branch, P(Y | not all antecedents), so applying it in turn gives
;; the exported rule's strength.
(: ImplicationModusPonensFormula
   (-[semidet]-> TV TV CTVType))
(= (ImplicationModusPonensFormula $atv (CTV $pos $neg))
   (CTV (CTVModusPonensFormula $atv (CTV $pos $neg)) $neg))

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

;; One input known with certainty at the connective's absorbing value decides
;; the connective exactly, whatever the other input: a certain-false conjunct
;; makes an And certainly false, a certain-true disjunct an Or certainly true.
;; Otherwise no evidence about an input means no evidence about the combination:
;; at zero confidence the propagated variance of a clipped extreme strength is
;; tiny, so ideal-prod-confidence would otherwise turn a zero count into
;; near-certainty.
(: certain-at? (-[det]-> Number Number Number Bool))
(= (certain-at? $value $s $c) (if (>= $c 1.0) (== (* 1.0 $s) $value) false))

(: AndFormula (-[semidet]-> TV TV STVType))
(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (if (or (certain-at? 0.0 $si $ci) (certain-at? 0.0 $sa $ca))
      (STV 0.0 1.0)
      (STV (* $si $sa)
         (if (or (<= $ci 0.0) (<= $ca 0.0))
            0.0
            (ideal-prod-confidence $si (ideal-var $si $ci) $sa (ideal-var $sa $ca) (* $si $sa))))))

(: OrFormula (-[det]-> STVType STVType STVType))
(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (or-stv-fields $si $ci $sa $ca))

(: or-stv-fields
   (-[det]-> Number Number Number Number STVType))
(= (or-stv-fields $si $ci $sa $ca)
   (if (or (certain-at? 1.0 $si $ci) (certain-at? 1.0 $sa $ca))
      (STV 1.0 1.0)
      (STV (- (+ $si $sa) (* $si $sa))
         (if (or (<= $ci 0.0) (<= $ca 0.0))
            0.0
            (ideal-prod-confidence (- 1.0 $si) (ideal-var $si $ci) (- 1.0 $sa) (ideal-var $sa $ca)
               (- (+ $si $sa) (* $si $sa)))))))

;; A part of a compound known with certainty at the connective's absorbing
;; value `$settling` settles the compound to that value, without its other
;; parts (compound settling, `set-compound-settling`); any other part value
;; settles nothing.
(: SettlesFormula (-[semidet]-> TV STVType STVType))
(= (SettlesFormula $tv (STV $value $certain))
   (case $tv (
      ((STV $s $c) (if (certain-at? $value $s $c) (STV $value $certain) (empty)))
      ($_other (empty)))))

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
;; An implication's instances, the consequent strengths weighted by the
;; antecedent's mass where it holds and where it fails: the evidence of
;; P(B | A) and of P(B | not A). An antecedent known false is a sample of the
;; negative branch only.
(: InstanceEvidenceState Type)
(: InstanceEvidence (-[det]-> BaseRateEvidenceState BaseRateEvidenceState InstanceEvidenceState))

(: ImplicationInstanceAcc
   (-[semidet]-> InstanceEvidenceState (| WeightedTV NoEvidenceType) InstanceEvidenceState))
(= (ImplicationInstanceAcc (InstanceEvidence (BaseRateEvidence $pw $pm) (BaseRateEvidence $nw $nm)) (WeightedTv (STV $m $mc) (STV $s $c)))
   (let* (($mass (* $mc $c))
          ($pos (* $m $mass))
          ($neg (* (- 1.0 $m) $mass)))
      (InstanceEvidence (BaseRateEvidence (+ $pw (* $s $pos)) (+ $pm $pos))
         (BaseRateEvidence (+ $nw (* $s $neg)) (+ $nm $neg)))))
(= (ImplicationInstanceAcc $acc (WeightedTv $mass-tv (CTV $pos $_neg)))
   (ImplicationInstanceAcc $acc (WeightedTv $mass-tv $pos)))
(= (ImplicationInstanceAcc $acc no-evidence) $acc)

;; The instances' estimate of P(B | A), and of P(B | not A) beside it as a
;; CTV once antecedent-false instances were seen. Without positive instances
;; the positive branch has no evidence (confidence 0, where its strength is
;; irrelevant) while the negative one still learns; without any there is no
;; estimate.
(: ImplicationInstanceTv (-[det]-> InstanceEvidenceState TV))
(= (ImplicationInstanceTv (InstanceEvidence $pos $neg))
   (case (data (WeightedCountBaseRateTv $pos) (WeightedCountBaseRateTv $neg)) (
      (((STV $ps $pc) (STV $ns $nc)) (CTV (STV $ps $pc) (STV $ns $nc)))
      (((STV $ps $pc) $_none) (STV $ps $pc))
      ((no-evidence (STV $ns $nc)) (CTV (STV 0.5 0.0) (STV $ns $nc)))
      ($_nothing no-evidence))))
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
;; Inversion of a rule stated with an STV, whose negative branch is derived
;; from the base rates (ImplicationCTVFormula); a rule stating both branches is
;; inverted by CTVBayesFormula, which needs no P(B).
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

;; The likelihoods of a rule's consequence C for one conjunct M of its
;; antecedent (And O M), with u = P(C|O,M) and v = P(C|not(O,M)) the rule's
;; branches and O read at its value s_O: P(C|M) = s_O u + (1 - s_O) v (modus
;; ponens) and P(C|not M) = v. Bayes' rule over P(M) with these is the joint
;; posterior of O and M given C, marginalized over O: C's value also updates
;; O, and given O it decides M as the rule does. O certainly true leaves the
;; rule's branch as it is. A negated conjunct (Not I) gives I's likelihoods,
;; the two swapped.
(: ConjunctLikelihoodFormula (-[semidet]-> Bool TV TV CTVType))
(= (ConjunctLikelihoodFormula $negated (STV $so $co) (CTV $pos $neg))
   (let $given (if (certain-at? 1.0 $so $co) $pos (CTVModusPonensFormula (STV $so $co) (CTV $pos $neg)))
      (if $negated (CTV $neg $given) (CTV $given $neg))))

;; An inversion reads an observation of b as a likelihood ratio. A soft
;; observation's strength s is a posterior under the prior p it was formed
;; under (a base rate of b), so its ratio is lambda = odds(s) / odds(p). The
;; inversion (P(a|b), P(a|not b)) of a prior P(a) weighs its branches by b's
;; value under the prior it implies for b, the pi with pi P(a|b) + (1 - pi)
;; P(a|not b) = P(a), so the observation is restated under pi, odds(s') =
;; lambda odds(pi), and modus ponens over the inversion gives the posterior
;; odds odds(P(a)) (u lambda + 1 - u) / (v lambda + 1 - v) for the likelihoods
;; u and v. The ratio's log-odds variance is the observation's less its
;; prior's, which the observation's contains (delta method); a value stated
;; with confidence 1 keeps it. A certain observation, an inversion b does not
;; move, and a prior of 0 or 1 or none (`no-evidence`: a value formed under no
;; known prior) leave the observation as it is.
(: ObservationRatioFormula (-[semidet]-> TV TV TV TV STVType))
(= (ObservationRatioFormula (STV $s $c) $base (STV $sa $_ca) (CTV (STV $pos $_cpos) (STV $neg $_cneg)))
   (case $base (
      ((STV $p $cp)
         (if (or (== $pos $neg) (or (<= (* $s (- 1.0 $s)) 0.0) (<= (* $p (- 1.0 $p)) 0.0)))
            (STV $s $c)
            (let* (($pi (ideal-clip (/ (- $sa $neg) (- $pos $neg))))
                   ($x (* $s (* $pi (- 1.0 $p))))
                   ($r (/ $x (+ $x (* (- 1.0 $s) (* $p (- 1.0 $pi))))))
                   ($ls (* $s (- 1.0 $s)))
                   ($lp (* $p (- 1.0 $p)))
                   ($lr (* $r (- 1.0 $r))))
               (STV $r (if (>= $c 1.0) $c
                          (ideal-conf-from-var $r
                             (* (* $lr $lr)
                                (max 0.0 (- (/ (ideal-var $s $c) (* $ls $ls)) (/ (ideal-var $p $cp) (* $lp $lp)))))))))))
      ($_none (STV $s $c)))))

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
