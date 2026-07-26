(: TV Type)
(: STV (-> Number Number TV))
(: CTV (-> TV TV TV))
(: no-evidence TV)

(: Distribution Type)
(: ParticleDist (-> Number Number Distribution))

(: DistributionStats Type)
(: Stats (-> Number Number Number DistributionStats))

(: DistributionSumCount Type)
(: SumCount (-> Distribution Number DistributionSumCount))

(: DistributionPairCounts Type)
(: PairCounts (-> (List ($value Number)) DistributionPairCounts))

(: InputOutputPair Type)
(: Pair (-> $input $output InputOutputPair))

(: ParticleSample Type)
(: particle (-> Number $value Number ParticleSample))

(: clamp01 (-> Number Number))
(= (clamp01 $x) (max 0.0 (min 1.0 $x)))

(: tv-probability (-> TV Number))
(= (tv-probability $tv)
   (case $tv
      (((STV $s $c) (clamp01 (* $s $c)))
       ($_other 1.0))))

(: next-particle-id (-> Number))
(= (next-particle-id)
   (let $mn (catch (get-state particleid))
      (let $n (if-error-number $mn 0)
         (progn (change-state! particleid (+ $n 1)) $n))))

(: particle-dist-id (-> Distribution Number))
(= (particle-dist-id $pd) (case $pd (((ParticleDist $pid $_scale) $pid))))

(: particle-dist-scale (-> Distribution Number))
(= (particle-dist-scale $pd) (case $pd (((ParticleDist $_pid $scale) $scale))))

(: particle-fetch-pairs (-> Number (List ($value Number))))
(= (particle-fetch-pairs $pid) (collapse (match &particle_store (particle $pid $x $w) ($x $w))))

(: particle-store-pairs (-> Number (List ($value Number)) (List $done)))
(= (particle-store-pairs $pid ()) ())
(= (particle-store-pairs $pid (cons ($x $w) $tail))
   (progn (add-atom &particle_store (particle $pid $x $w)) (particle-store-pairs $pid $tail)))

(: list-count (-> (List $value) Number))
(= (list-count ()) 0)
(= (list-count (cons $_x $tail)) (+ 1 (list-count $tail)))

(: pairs-stats (-> (List ($value Number)) DistributionStats))
(= (pairs-stats ()) (Stats 0.0 0.0 0))
(= (pairs-stats (cons ($_x $w) $tail))
   (let (Stats $sum $sumsq $count) (pairs-stats $tail)
      (Stats (+ $w $sum) (+ (* $w $w) $sumsq) (+ 1 $count))))

(: ParticleStoreCount (-> Number))
(= (ParticleStoreCount) (list-count (collapse (match &particle_store (particle $pid $x $w) ($pid $x $w)))))

(: ParticleStoreClear (-> Bool))
(= (ParticleStoreClear) (progn (remove-all-atoms &particle_store) (change-state! particleid 0)))

;; Particle distributions can be embedded anywhere in a compiled fact or TV,
;; so this is intentionally a generic structural walk rather than a
;; Distribution-only accessor. The ParticleDist branch checks only its numeric
;; id; the resulting cons is then known statically as (List Number).
(: particle-ids-in-term (-[det]-> Atom (List Number)))
(= (particle-ids-in-term $term)
   (case $term (
      ((ParticleDist $pid $_scale)
         (cons $pid ()))
      ($_other
         (if (or (is-var $term) (== $term ())) ()
            (if (is-expr $term)
               (append
                  (particle-ids-in-term (car-atom $term))
                  (particle-ids-in-term (cdr-atom $term)))
               ()))))))

(: ParticleStorePruneKB (-> Number))
(= (ParticleStorePruneKB)
   (let*
      (($keep
           (list_to_set
              (collapse
                 (match &kb (: $_kb $_prf $_type $tv)
                    (let $particle-ids
                       (append
                          (particle-ids-in-term $_type)
                          (particle-ids-in-term $tv))
                       (superpose $particle-ids))))))
        ($atoms
           (collapse
              (match &particle_store
                 (particle $pid $x $w)
                 (particle $pid $x $w))))
        ($_pruned
           (fold-flat
              (|-> ($acc (particle $pid $x $w))
                 (progn (if (is-member $pid $keep) () (remove-atom &particle_store (particle $pid $x $w)))
                    $acc))
              ()
              $atoms))
        ($maxid (fold-flat (|-> ($acc $pid) (max $acc $pid)) -1 $keep))
        ($_reset (change-state! particleid (+ $maxid 1))))
      (ParticleStoreCount)))

(: particle-neff-from-pairs (-> (List ($value Number)) Number))
(= (particle-neff-from-pairs $pairs)
   (let*
      (($norm (normalize-pairs $pairs))
        ((Stats $_sum $sumsq $_count) (pairs-stats $norm)))
      (if (<= $sumsq 0.0) 0.0 (/ 1.0 $sumsq))))

(: particle-confidence-k (-> Number))
(= (particle-confidence-k) 20.0)

(: particle-confidence-from-neff (-> Number Number))
(= (particle-confidence-from-neff $neff) (if (<= $neff 0.0) 0.0 (/ $neff (+ $neff (particle-confidence-k)))))

(: particle-confidence-from-pairs (-> (List ($value Number)) Number))
(= (particle-confidence-from-pairs $pairs) (particle-confidence-from-neff (particle-neff-from-pairs $pairs)))

(: normalize-pairs (-> (List ($value Number)) (List ($value Number))))
(= (normalize-pairs $pairs)
   (let (Stats $total $_sumsq $_count) (pairs-stats $pairs)
      (if (<= $total 0.0) () (scale-dist-pairs $pairs (/ 1.0 $total)))))

(: pairs-to-cdf-acc (-> (List ($value Number)) Number (List ($value Number))))
(= (pairs-to-cdf-acc () $acc) ())
(= (pairs-to-cdf-acc (cons ($x $w) $tail) $acc)
   (let $nacc (+ $acc $w) (cons (quote ($x $nacc)) (pairs-to-cdf-acc $tail $nacc))))

(: pairs-to-cdf (-> (List ($value Number)) (List ($value Number))))
(= (pairs-to-cdf $pairs) (pairs-to-cdf-acc $pairs 0.0))

(: cdf-select (-> Number (List ($value Number)) $value))
(= (cdf-select $u (cons ($x $cum) $tail)) (if (or (<= $u $cum) (== $tail ())) $x (cdf-select $u $tail)))

(: resample-counts (-> (List ($value Number)) Number Number (List ($value Number)) (List ($value Number))))
(= (resample-counts $cdf $n $i $acc)
   (if (>= $i $n) $acc
      (let*
         (($u (/ (+ $i 0.5) $n))
           ($x (cdf-select $u $cdf))
           ($nacc (dist-add-mass $acc $x 1.0)))
         (resample-counts $cdf $n (+ $i 1) $nacc))))

(: pairs-resample-systematic (-> (List ($value Number)) Number (List ($value Number))))
(= (pairs-resample-systematic $pairs $n)
   (if (or (== $pairs ()) (<= $n 0)) ()
      (let*
         (($cdf (pairs-to-cdf (normalize-pairs $pairs)))
           ($counts (resample-counts $cdf $n 0 ())))
         (scale-dist-pairs $counts (/ 1.0 $n)))))

(: particle-budget-default (-> Number))
(= (particle-budget-default) 512)

(: ParticleSetBudget (-> Number Bool))
(= (ParticleSetBudget $n) (change-state! particle_budget $n))

(: ParticleGetBudget (-> Number))
(= (ParticleGetBudget)
   (let $mb (catch (get-state particle_budget))
      (if-error-number $mb (particle-budget-default))))

(: particle-budget (-> Number))
(= (particle-budget) (ParticleGetBudget))

(: compress-pairs (-> (List ($value Number)) (List ($value Number))))
(= (compress-pairs $pairs)
   (let*
      (($norm (normalize-pairs $pairs))
        ((Stats $_sum $_sumsq $count) (pairs-stats $norm)))
      (if (<= $count (particle-budget)) $norm (pairs-resample-systematic $norm (particle-budget)))))

(: particle-build-dist (-> Number (List ($value Number)) Distribution))
(= (particle-build-dist $scale $pairs)
   (let*
      (($pid (next-particle-id))
        ($compressed (compress-pairs $pairs))
        ($_store (particle-store-pairs $pid $compressed)))
      (ParticleDist $pid $scale)))

(: ParticleFromPairs (-> (List ($value Number)) Distribution))
(= (ParticleFromPairs $pairs) (particle-build-dist 1.0 $pairs))

(: PointMass (-> $value Distribution))
(= (PointMass $x) (ParticleFromPairs (quote (($x 1.0)))))

(: normal-kernel-9 (-> (List (Number Number))))
(= (normal-kernel-9)
   ((-2.0 0.027630550638898826) (-1.5 0.0662822452863612)
      (-1.0 0.1238315368057753)
      (-0.5 0.18017382291138087)
      (0.0 0.20416368871516764)
      (0.5 0.18017382291138087)
      (1.0 0.1238315368057753)
      (1.5 0.0662822452863612)
      (2.0 0.027630550638898826)))

(: affine-pairs (-> (List (Number Number)) Number Number (List (Number Number))))
(= (affine-pairs () $mu $sigma) ())
(= (affine-pairs (cons ($x $w) $tail) $mu $sigma)
   (cons ((+ $mu (* $sigma $x)) $w) (affine-pairs $tail $mu $sigma)))

(: ParticleFromNormal (-> Number Number Distribution))
(= (ParticleFromNormal $mu $sigma) (ParticleFromPairs (affine-pairs (normal-kernel-9) $mu $sigma)))

(: ParticlePairs (-> Distribution (List ($value Number))))
(= (ParticlePairs $pd)
   (scale-dist-pairs (particle-fetch-pairs (particle-dist-id $pd)) (particle-dist-scale $pd)))

(: scale-dist-pairs (-> (List ($value Number)) Number (List ($value Number))))
(= (scale-dist-pairs () $w) ())
(= (scale-dist-pairs (cons ($x $p) $tail) $w)
   (let $scaled (* $p $w)
      (cons (quote ($x $scaled)) (scale-dist-pairs $tail $w))))

(: dist-add-mass
   (-> (List ($value Number)) $value Number (List ($value Number))))
(= (dist-add-mass () $x $m) (cons (quote ($x $m)) ()))
(= (dist-add-mass (cons ($k $p) $tail) $x $m)
   (if (== $k $x)
      (let $merged (+ $p $m) (cons (quote ($k $merged)) $tail))
      (cons (quote ($k $p)) (dist-add-mass $tail $x $m))))

(: dist-add-bernoulli-step (-> (List (Number Number)) Number (Number Number) (List (Number Number))))
(= (dist-add-bernoulli-step $acc $p ($n $mass))
   (let $acc0 (dist-add-mass $acc $n (* $mass (- 1.0 $p))) (dist-add-mass $acc0 (+ $n 1) (* $mass $p))))

(: dist-add-bernoulli-pairs (-> (List (Number Number)) Number (List (Number Number))))
(= (dist-add-bernoulli-pairs $pairs $p)
   (fold-flat (|-> ($acc $item) (dist-add-bernoulli-step $acc $p $item)) () $pairs))

(: dist-prob-gt (-> (List (Number Number)) Number Number))
(= (dist-prob-gt () $threshold) 0.0)
(= (dist-prob-gt (cons ($x $p) $tail) $threshold)
   (+ (if (> $x $threshold) $p 0.0) (dist-prob-gt $tail $threshold)))

(: dist-prob-gt2-inner (-> Number Number (List (Number Number)) Number Number))
(= (dist-prob-gt2-inner $xa $wa () $acc) $acc)
(= (dist-prob-gt2-inner $xa $wa (cons ($xb $wb) $tail) $acc)
   (let $nacc (+ $acc (if (> $xa $xb) (* $wa $wb) 0.0)) (dist-prob-gt2-inner $xa $wa $tail $nacc)))

(: dist-prob-gt2 (-> (List (Number Number)) (List (Number Number)) Number))
(= (dist-prob-gt2 () $pairsb) 0.0)
(= (dist-prob-gt2 (cons ($xa $wa) $taila) $pairsb)
   (+ (dist-prob-gt2-inner $xa $wa $pairsb 0.0) (dist-prob-gt2 $taila $pairsb)))

(: particle-map-pairs (-> (-[det]-> $input $output) (List ($input Number)) (List ($output Number)) (List ($output Number))))
(= (particle-map-pairs $fun () $acc) $acc)
(= (particle-map-pairs $fun (cons ($x $w) $tail) $acc)
   (let*
      (($y ($fun $x))
        ($nacc (dist-add-mass $acc $y $w)))
      (particle-map-pairs $fun $tail $nacc)))

(: particle-map2-inner (-> (-[det]-> $left $right $output) $left Number (List ($right Number)) (List ($output Number)) (List ($output Number))))
(= (particle-map2-inner $fun $xa $wa () $acc) $acc)
(= (particle-map2-inner $fun $xa $wa (cons ($xb $wb) $tail) $acc)
   (let*
      (($y ($fun $xa $xb))
        ($nacc (dist-add-mass $acc $y (* $wa $wb))))
      (particle-map2-inner $fun
         $xa
         $wa
         $tail
         $nacc)))

(: particle-map2-pairs (-> (-[det]-> $left $right $output) (List ($left Number)) (List ($right Number)) (List ($output Number)) (List ($output Number))))
(= (particle-map2-pairs $fun () $pairsb $acc) $acc)
(= (particle-map2-pairs $fun (cons ($xa $wa) $taila) $pairsb $acc)
   (let $nacc (particle-map2-inner $fun $xa $wa $pairsb $acc)
      (particle-map2-pairs $fun $taila $pairsb $nacc)))

(: DistMapFormula (-> (-[det]-> $input $output) Distribution Distribution))
(= (DistMapFormula $fun $dist) (ParticleMap $fun $dist))

(: DistMap2Formula (-> (-[det]-> $left $right $output) Distribution Distribution Distribution))
(= (DistMap2Formula $fun $dista $distb) (ParticleMap2 $fun $dista $distb))

(: dist-add-numbers (-[det]-> Number Number Number))
(= (dist-add-numbers $left $right) (+ $left $right))

(: DistSumCountAcc (-> DistributionSumCount Distribution DistributionSumCount))
(= (DistSumCountAcc (SumCount $sumdist $count) $hdist)
   (SumCount
      (DistMap2Formula dist-add-numbers $sumdist $hdist)
      (+ $count 1)))

(: dist-divide-by (-[det]-> Number Number Number))
(= (dist-divide-by $divisor $value) (/ $value $divisor))

(: DistAverageFromSumCount (-> DistributionSumCount Distribution))
(= (DistAverageFromSumCount (SumCount $sumdist $count))
   (DistMapFormula (dist-divide-by $count) $sumdist))

(: DistValueCountAcc (-> DistributionPairCounts $value DistributionPairCounts))
(= (DistValueCountAcc (PairCounts $pairs) $x) (PairCounts (dist-add-mass $pairs $x 1.0)))

(: PairCountsToDist (-> DistributionPairCounts Distribution))
(= (PairCountsToDist (PairCounts $pairs)) (ParticleFromPairs $pairs))

(: numeric-distance2 (-> $left $right Number))
(: numeric-distance2-result
   (-> (| Number (Error $detail $context)) Number))
(= (numeric-distance2-result $mdelta)
   (if (= $mdelta (cons Error $_)) 1000000.0
      (let $delta (checked-number $mdelta) (* $delta $delta))))

(= (numeric-distance2 $a $b)
   (let $mdelta (catch (- (the Number $a) (the Number $b)))
      (numeric-distance2-result $mdelta)))

(: struct-distance2 (-> $a $b Number))
(: struct-distance2-list (-> (List $a) (List $b) Number))
(= (struct-distance2-list () $rest) (if (== $rest ()) 0.0 1000000.0))
(= (struct-distance2-list (cons $_head $_tail) ()) 1000000.0)
(= (struct-distance2-list (cons $a $as) (cons $b $bs))
   (+ (struct-distance2 $a $b) (struct-distance2-list $as $bs)))

(= (struct-distance2 $a $b)
   (if (== $a $b) 0.0
      (if (and (is-expr $a) (is-expr $b))
         (if (== (car-atom $a) (car-atom $b))
            (struct-distance2-list (cdr-atom $a) (cdr-atom $b))
            1000000.0)
         (numeric-distance2 $a $b))))

(: kernel-mass (-> Number Number Number))
(= (kernel-mass $dist2 $bandwidth)
   (if (<= $bandwidth 0.0)
      (if (== $dist2 0.0) 1.0 0.0)
      (/ 1.0 (+ 1.0 (/ $dist2 (* $bandwidth $bandwidth))))))

(: joint-cond-add-sample (-> $input Number (Pair $input $output) Number Number (List ($output Number)) (List ($output Number))))
(= (joint-cond-add-sample $input $inputw (Pair $sample $output) $samplew $bandwidth $acc)
   (let*
      (($sim (kernel-mass (struct-distance2 $sample $input) $bandwidth))
        ($mass (* $inputw (* $samplew $sim))))
      (if (> $mass 0.0) (dist-add-mass $acc $output $mass) $acc)))

(: joint-cond-inner (-> $input Number (List ((Pair $input $output) Number)) Number (List ($output Number)) (List ($output Number))))
(= (joint-cond-inner $_input $_inputw () $_bandwidth $acc) $acc)
(= (joint-cond-inner $input $inputw (cons ($key $samplew) $tail) $bandwidth $acc)
   (let $nacc (joint-cond-add-sample $input $inputw $key $samplew $bandwidth $acc)
      (joint-cond-inner $input $inputw $tail $bandwidth $nacc)))

(: joint-cond-pairs (-> (List ($input Number)) (List ((Pair $input $output) Number)) Number (List ($output Number)) (List ($output Number))))
(= (joint-cond-pairs () $_jointpairs $_bandwidth $acc) $acc)
(= (joint-cond-pairs (cons ($input $inputw) $tail) $jointpairs $bandwidth $acc)
   (let $nacc (joint-cond-inner $input $inputw $jointpairs $bandwidth $acc)
      (joint-cond-pairs $tail $jointpairs $bandwidth $nacc)))

(: CondDistFromJoint (-> Distribution Distribution Number Distribution))
(= (CondDistFromJoint $jointDist $inputDist $bandwidth)
   (let*
      (($jointpairs (ParticlePairs $jointDist))
        ($inputpairs (ParticlePairs $inputDist))
        ($zpairs (joint-cond-pairs $inputpairs $jointpairs $bandwidth ())))
      (ParticleFromPairs $zpairs)))

(: ParticleAddBernoulliFromSTV (-> Distribution TV Distribution))
(= (ParticleAddBernoulliFromSTV $pd $tv)
   (let*
      (($pid (particle-dist-id $pd))
        ($scale (particle-dist-scale $pd))
        ($p (tv-probability $tv))
        ($pairs (particle-fetch-pairs $pid))
        ($updated (dist-add-bernoulli-pairs $pairs $p)))
      (particle-build-dist $scale $updated)))

(: ParticleMap (-> (-[det]-> $input $output) Distribution Distribution))
(= (ParticleMap $fun $pd)
   (let*
      (($pid (particle-dist-id $pd))
        ($scale (particle-dist-scale $pd))
        ($pairs (particle-fetch-pairs $pid))
        ($mapped (particle-map-pairs $fun $pairs ())))
      (particle-build-dist $scale $mapped)))

(: ParticleMap2 (-> (-[det]-> $left $right $output) Distribution Distribution Distribution))
(= (ParticleMap2 $fun $pda $pdb)
   (let*
      (($pida (particle-dist-id $pda))
        ($pidb (particle-dist-id $pdb))
        ($scalea (particle-dist-scale $pda))
        ($scaleb (particle-dist-scale $pdb))
        ($pairsa (particle-fetch-pairs $pida))
        ($pairsb (particle-fetch-pairs $pidb))
        ($mapped (particle-map2-pairs $fun $pairsa $pairsb ())))
      (particle-build-dist (* $scalea $scaleb) $mapped)))
