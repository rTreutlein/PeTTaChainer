(= (clamp01 $x) (max 0.0 (min 1.0 $x)))

(= (tv-probability $tv) (if (= $tv (STV $s $c)) (clamp01 (* $s $c)) 1.0))

(= (next-particle-id)
   (let $mn (catch (get-state particleid))
      (let $n (if-error $mn 0 $mn) (progn (change-state! particleid (+ $n 1)) $n))))

(= (particle-dist-id $pd) (case $pd (((ParticleDist $pid $_scale) $pid))))

(= (particle-dist-scale $pd) (case $pd (((ParticleDist $_pid $scale) $scale))))

(= (particle-fetch-pairs $pid) (collapse (match &particle_store (particle $pid $x $w) ($x $w))))

(= (particle-store-pairs $pid ()) ())
(= (particle-store-pairs $pid (cons ($x $w) $tail))
   (progn (add-atom &particle_store (particle $pid $x $w)) (particle-store-pairs $pid $tail)))

(= (list-count ()) 0)
(= (list-count (cons $_x $tail)) (+ 1 (list-count $tail)))

(= (pairs-stats ()) (Stats 0.0 0.0 0))
(= (pairs-stats (cons ($_x $w) $tail))
   (let (Stats $sum $sumsq $count) (pairs-stats $tail)
      (Stats (+ $w $sum) (+ (* $w $w) $sumsq) (+ 1 $count))))

(= (ParticleStoreCount) (list-count (collapse (match &particle_store (particle $pid $x $w) ($pid $x $w)))))

(= (ParticleStoreClear) (progn (remove-all-atoms &particle_store) (change-state! particleid 0)))

(= (particle-ids-in-term (ParticleDist $pid $_scale)) ($pid))
(= (particle-ids-in-term $term)
   (if (is-var $term) ()
      (if (is-expr $term)
         (fold-flat
            (|-> ($acc $elem) (append $acc (particle-ids-in-term $elem)))
            ()
            $term)
         ())))

(= (ParticleStorePruneKB)
   (let*
      (($keep
           (list_to_set
              (collapse
                 (match &kb
                    (: $_kb $_prf $_type $tv)
                    (append (particle-ids-in-term $_type) (particle-ids-in-term $tv))))))
        ($atoms (collapse (match &particle_store (particle $pid $x $w) ($pid $x $w))))
        ($_pruned
           (fold-flat
              (|-> ($acc ($pid $x $w))
                 (progn (if (is-member $pid $keep) () (remove-atom &particle_store (particle $pid $x $w)))
                    $acc))
              ()
              $atoms))
        ($maxid (fold-flat (|-> ($acc $pid) (max $acc $pid)) -1 $keep))
        ($_reset (change-state! particleid (+ $maxid 1))))
      (ParticleStoreCount)))

(= (particle-neff-from-pairs $pairs)
   (let*
      (($norm (normalize-pairs $pairs))
        ((Stats $_sum $sumsq $_count) (pairs-stats $norm)))
      (if (<= $sumsq 0.0) 0.0 (/ 1.0 $sumsq))))

(= (particle-confidence-k) 20.0)

(= (particle-confidence-from-neff $neff) (if (<= $neff 0.0) 0.0 (/ $neff (+ $neff (particle-confidence-k)))))

(= (particle-confidence-from-pairs $pairs) (particle-confidence-from-neff (particle-neff-from-pairs $pairs)))

(= (normalize-pairs $pairs)
   (let (Stats $total $_sumsq $_count) (pairs-stats $pairs)
      (if (<= $total 0.0) () (scale-dist-pairs $pairs (/ 1.0 $total)))))

(= (pairs-to-cdf-acc () $acc) ())
(= (pairs-to-cdf-acc (cons ($x $w) $tail) $acc)
   (let $nacc (+ $acc $w) (cons ($x $nacc) (pairs-to-cdf-acc $tail $nacc))))

(= (pairs-to-cdf $pairs) (pairs-to-cdf-acc $pairs 0.0))

(= (cdf-select $u (cons ($x $cum) $tail)) (if (or (<= $u $cum) (== $tail ())) $x (cdf-select $u $tail)))

(= (resample-counts $cdf $n $i $acc)
   (if (>= $i $n) $acc
      (let*
         (($u (/ (+ $i 0.5) $n))
           ($x (cdf-select $u $cdf))
           ($nacc (dist-add-mass $acc $x 1.0)))
         (resample-counts $cdf $n (+ $i 1) $nacc))))

(= (pairs-resample-systematic $pairs $n)
   (if (or (== $pairs ()) (<= $n 0)) ()
      (let*
         (($cdf (pairs-to-cdf (normalize-pairs $pairs)))
           ($counts (resample-counts $cdf $n 0 ())))
         (scale-dist-pairs $counts (/ 1.0 $n)))))

(= (particle-budget-default) 512)

(= (ParticleSetBudget $n) (change-state! particle_budget $n))

(= (ParticleGetBudget)
   (let $mb (catch (get-state particle_budget)) (if-error $mb (particle-budget-default) $mb)))

(= (particle-budget) (ParticleGetBudget))

(= (compress-pairs $pairs)
   (let*
      (($norm (normalize-pairs $pairs))
        ((Stats $_sum $_sumsq $count) (pairs-stats $norm)))
      (if (<= $count (particle-budget)) $norm (pairs-resample-systematic $norm (particle-budget)))))

(= (particle-build-dist $scale $pairs)
   (let*
      (($pid (next-particle-id))
        ($compressed (compress-pairs $pairs))
        ($_store (particle-store-pairs $pid $compressed)))
      (ParticleDist $pid $scale)))

(= (ParticleFromPairs $pairs) (particle-build-dist 1.0 $pairs))

(= (PointMass $x) (ParticleFromPairs (($x 1.0))))

(= (normal-kernel-9)
   ((-2.0 0.027630550638898826) (-1.5 0.0662822452863612)
      (-1.0 0.1238315368057753)
      (-0.5 0.18017382291138087)
      (0.0 0.20416368871516764)
      (0.5 0.18017382291138087)
      (1.0 0.1238315368057753)
      (1.5 0.0662822452863612)
      (2.0 0.027630550638898826)))

(= (affine-pairs () $mu $sigma) ())
(= (affine-pairs (cons ($x $w) $tail) $mu $sigma)
   (cons ((+ $mu (* $sigma $x)) $w) (affine-pairs $tail $mu $sigma)))

(= (ParticleFromNormal $mu $sigma) (ParticleFromPairs (affine-pairs (normal-kernel-9) $mu $sigma)))

(= (ParticlePairs $pd)
   (scale-dist-pairs (particle-fetch-pairs (particle-dist-id $pd)) (particle-dist-scale $pd)))

(= (scale-dist-pairs () $w) ())
(= (scale-dist-pairs (cons ($x $p) $tail) $w) (cons ($x (* $p $w)) (scale-dist-pairs $tail $w)))

(= (dist-add-mass () $x $m) (cons ($x $m) ()))
(= (dist-add-mass (cons ($k $p) $tail) $x $m)
   (if (== $k $x) (cons ($k (+ $p $m)) $tail) (cons ($k $p) (dist-add-mass $tail $x $m))))

(= (dist-add-bernoulli-step $acc $p ($n $mass))
   (let $acc0 (dist-add-mass $acc $n (* $mass (- 1.0 $p))) (dist-add-mass $acc0 (+ $n 1) (* $mass $p))))

(= (dist-add-bernoulli-pairs $pairs $p)
   (fold-flat (|-> ($acc $item) (dist-add-bernoulli-step $acc $p $item)) () $pairs))

(= (dist-prob-gt () $threshold) 0.0)
(= (dist-prob-gt (cons ($x $p) $tail) $threshold)
   (+ (if (> $x $threshold) $p 0.0) (dist-prob-gt $tail $threshold)))

(= (dist-prob-gt2-inner $xa $wa () $acc) $acc)
(= (dist-prob-gt2-inner $xa $wa (cons ($xb $wb) $tail) $acc)
   (let $nacc (+ $acc (if (> $xa $xb) (* $wa $wb) 0.0)) (dist-prob-gt2-inner $xa $wa $tail $nacc)))

(= (dist-prob-gt2 () $pairsb) 0.0)
(= (dist-prob-gt2 (cons ($xa $wa) $taila) $pairsb)
   (+ (dist-prob-gt2-inner $xa $wa $pairsb 0.0) (dist-prob-gt2 $taila $pairsb)))

(= (particle-map-pairs $fun () $acc) $acc)
(= (particle-map-pairs $fun (cons ($x $w) $tail) $acc)
   (let*
      (($call (cons $fun (cons $x ())))
        ($y (reduce (reduce $call)))
        ($nacc (dist-add-mass $acc $y $w)))
      (particle-map-pairs $fun $tail $nacc)))

(= (particle-map2-inner $fun $xa $wa () $acc) $acc)
(= (particle-map2-inner $fun $xa $wa (cons ($xb $wb) $tail) $acc)
   (let*
      (($call (cons $fun (cons $xa (cons $xb ()))))
        ($y (reduce (reduce $call)))
        ($nacc (dist-add-mass $acc $y (* $wa $wb))))
      (particle-map2-inner $fun
         $xa
         $wa
         $tail
         $nacc)))

(= (particle-map2-pairs $fun () $pairsb $acc) $acc)
(= (particle-map2-pairs $fun (cons ($xa $wa) $taila) $pairsb $acc)
   (let $nacc (particle-map2-inner $fun $xa $wa $pairsb $acc)
      (particle-map2-pairs $fun $taila $pairsb $nacc)))

(= (DistMapFormula $fun $dist) (ParticleMap $fun $dist))

(= (DistMap2Formula $fun $dista $distb) (ParticleMap2 $fun $dista $distb))

(= (DistSumCountAcc (SumCount $sumdist $count) $hdist)
   (SumCount (DistMap2Formula + $sumdist $hdist) (+ $count 1)))

(= (DistAverageFromSumCount (SumCount $sumdist $count)) (DistMapFormula (|-> ($x) (/ $x $count)) $sumdist))

(= (ParticleAddBernoulliFromSTV $pd $tv)
   (let*
      (($pid (particle-dist-id $pd))
        ($scale (particle-dist-scale $pd))
        ($p (tv-probability $tv))
        ($pairs (particle-fetch-pairs $pid))
        ($updated (dist-add-bernoulli-pairs $pairs $p)))
      (particle-build-dist $scale $updated)))

(= (ParticleMap $fun $pd)
   (let*
      (($pid (particle-dist-id $pd))
        ($scale (particle-dist-scale $pd))
        ($pairs (particle-fetch-pairs $pid))
        ($mapped (particle-map-pairs $fun $pairs ())))
      (particle-build-dist $scale $mapped)))

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
