!(import! &self compile)
!(import! &self mining)
!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(import! &self chainer_utils)
!(bind! &resume_cache (new-space))
!(bind! &goal_cache (new-space))
!(bind! &particle_store (new-space))

;;;;;;;;;
;; Nat ;;
;;;;;;;;;

;; Define Nat
(: Nat Type)
(: Z Nat)
(: S (-> Nat Nat))

;; Define cast functions between Nat and Number
(: fromNumber (-> Number Nat))
(= (fromNumber $n) (if (<= $n 0) Z (S (fromNumber (- $n 1)))))
(: fromNat (-> Nat Number))
(= (fromNat Z) 0)
(= (fromNat (S $k)) (+ 1 (fromNat $k)))

;;;;;;;;;;;;;;;;;;
;; Chainer Core ;;
;;;;;;;;;;;;;;;;;;

(= (chainer $steps $goal)
   (let* (($_rclear (remove-all-atoms &resume_cache))
          ($_gclear (remove-all-atoms &goal_cache))
          ((state $pq $_rcache $_gcache) (enqueue-goal-state $steps (state (empty_heap) &resume_cache &goal_cache) 1.0 () $goal))
          ($_ (search-rules $steps $pq &resume_cache &goal_cache)))
     (collapse (match &goal_cache (gmerge $result-goal) $result-goal))))

(= (enqueue-goal-state $steps $state $max-score $cont $goal)
   (let $state1 (fold-flat state-enqueue-item $state (collapse (direct-goal-items $steps $max-score $cont $goal)))
      (fold-flat state-enqueue-item $state1 (collapse (rule-candidate-items $max-score $cont $goal)))))

(= (rule-candidate-items $max-score $cont $goal)
   (match &kb (rules ($args |- $goal))
       (let $score (min $max-score (premises-expected-confidence $args))
            (candidate-item $score $args $goal $cont))))

(= (direct-goal-items $steps $max-score $cont $goal)
   (let* (($proof (if (= $goal (CPU $fun $args $_res))
                           (CPU $fun $args (cpu-call $steps $fun $args))
                           (match &kb $goal $goal)))
          ($score (min $max-score (term-confidence $proof))))
     (candidate-item $score () $proof $cont)))

;; Best-first over partially-applied rule candidates.
(= (payload-cand $payload)
   (if (= $payload (resume-cand $_rid $_type $cand))
       $cand
       $payload))

(= (payload-rid $payload)
   (if (= $payload (resume-cand $rid $_type $_cand))
       $rid
       (nextctx)))

(= (payload-repack $payload $cand)
   (if (= $payload (resume-cand $rid $type $_old-cand))
       (resume-cand $rid $type $cand)
       $cand))

(= (search-rules $steps $heap $rcache $gcache)
   (if (or (== (heap_size $heap) 0) (<= $steps 0))
       ()
       (let* (($pq-rest (get_from_heap $heap $_priority (qitem $score $payload)))
               ((cand ((cons $prem $rest) |- $goal) $cont) (payload-cand $payload))
               ($rid (payload-rid $payload))
               ($resume-template (copy_term (resume-template $prem $rest $goal)))
               ((resume-template $rprem $rrest $rgoal) $resume-template)
               ((state $new-pq $_new-rcache $_new-gcache) (enqueue-goal-state $steps (state $pq-rest $rcache $gcache) $score (cons (resume $rid $rprem $rrest $rgoal $score) $cont) $prem))
              )
             (search-rules (- $steps 1) $new-pq $rcache $gcache))))

(= (state-enqueue-cand (@ $state (state $pq $rcache $gcache)) $prio $payload $cand)
   (case $cand
     (
       ((cand (() |- $item-goal) ())
        (progn (goal-cache-upsert $gcache $item-goal)
               (state $pq $rcache $gcache)))
       ((cand (() |- $proved-goal) $cont)
        (resume-merge-enqueue-cont (state $pq $rcache $gcache) $proved-goal $cont))
        ((cand ((cons $arg $args) |- $item-goal) $cont)
         (if (has-active-premise? (cons $arg $args) $cont)
             (state $pq $rcache $gcache)
             (state (add_to_heap $pq (- 0 $prio)
                      (qitem $prio (payload-repack $payload (cand ((cons $arg $args) |- $item-goal) $cont))))
                    $rcache
                    $gcache)))
      )))

(= (state-enqueue-item (state $pq $rcache $gcache) (qitem $prio $payload))
   (state-enqueue-cand (state $pq $rcache $gcache) $prio $payload (payload-cand $payload)))

(= (premise-goal-keys ()) ())
(= (premise-goal-keys (cons $prem $rest))
       (if (= $prem (: $_kb $_prf $type $_tv))
           (cons $type (premise-goal-keys $rest))
           (premise-goal-keys $rest)
       ))

(= (has-active-premise? $args $cont)
   (let* (($prem-keys (premise-goal-keys $args))
          ($cont-keys (map-flat (|-> ((resume $_rid $_prem $_r (: $_kb $_prf $type $_tv) $_ps)) $type) $cont)))
        (not (== (/=a\ $prem-keys $cont-keys) ()))))

;; CPU functions that need the current step budget as first argument.
(= (cpu-needs-steps $fun)
   (or (== $fun FoldAllFormulaCompiled)
        (or (== $fun FoldAllTVFormulaCompiled)
            (or (== $fun FoldAllTVPatternFormula)
                (or (== $fun FoldAllTVRuntimeFormula)
                    (or (== $fun FoldAllValueFormulaCompiled)
                         (or (== $fun DistAverageFormula)
                             (== $fun Map2DistRuntimeFormula))))))))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $steps $fun $args)
  (let $call
       (if (cpu-needs-steps $fun)
           (cons $fun (cons $steps $args))
           (cons $fun $args))
       (reduce (reduce $call))))

;;;;;;;;;;;;;;;;;;
;; CPU Formulas ;;
;;;;;;;;;;;;;;;;;;

;; Runtime fold helper.
(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (let* (($call (cons $fun (cons $acc (cons $elem ()))))
          ($nacc (reduce (reduce $call))))
     (foldall-eval $fun $nacc $tail)))

(= (extract-proof-tvs ()) ())
(= (extract-proof-tvs (cons (: $_kb $_prf $_type $tv) $tail))
   (cons $tv (extract-proof-tvs $tail)))
(= (extract-proof-tvs (cons $_head $tail))
   (extract-proof-tvs $tail))

(= (inject-compiled-adds $adds)
   (if (= $adds ())
       $_
       (let $sadds (superpose $adds)
            (add-atom &kb $sadds))))

;; Execute a precompiled query plan represented as (goal + adds).
(= (run-compiled-query $steps $compiled-query)
   (let* (((cons (goal $query) $adds) $compiled-query)
          ($_ (inject-compiled-adds $adds)))
     (chainer $steps $query)))

;; FoldAll runtime uses precompiled query, then extracts fold values via pattern match.
(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
  (let $matches (collapse (let (: $kbr $prf $pattern $tvin) (run-compiled-query $steps $compiled-query) $value))
       (foldall-eval $fun $init $matches)))

;; Fold over the TV values of all matches in a precompiled query.
(= (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun)
  (let $matches (extract-proof-tvs (run-compiled-query $steps $compiled-query))
       (foldall-eval $fun $init $matches)))

;; Runtime-compiled TV fold preserving current variable bindings.
(= (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun)
  (let $kctx (fold-kbctx $kb)
  (let $matches (collapse (match &kb (: $kctx $prf $pattern $ptv) $ptv))
       (foldall-eval $fun $init $matches))))

;; Compute Map2Dist premise outputs from queried distribution TVs.
(= (Map2DistRuntimeFormula $steps $kb $fun $a $b)
  (let (: $prfa $a $tva)
       (query $steps $kb (: $prfa $a $tva))
       (let (: $prfb $b $tvb)
            (query $steps $kb (: $prfb $b $tvb))
            (DistMap2Formula $fun $tva $tvb))))

;; Steps parameter kept for uniform CPU call shape.
(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun)
  (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun))

(= (fold-kbctx $kb)
   (if (is-expr $kb)
       (let ($kbid $_ctx $_vars) $kb
            ($kbid MAIN ()))
       ($kb MAIN ())))

;; Fold over TV values by running the given pattern query under current substitutions.
(= (FoldAllTVPatternFormula $steps $kb $pattern $init $fun)
  (let $matches (collapse (let (: $prf $pattern $ptv)
                              (query $steps $kb (: $prf $pattern $ptv))
                              $ptv))
       (foldall-eval $fun $init $matches)))

;; FoldAllValue runtime kept for compatibility with earlier compiled forms.
(= (FoldAllValueFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
  (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun))

;;;;;;;;;;;;;;;;;;;;;;;;;
;; Distribution Helpers ;;
;;;;;;;;;;;;;;;;;;;;;;;;;

(= (clamp01 $x) (max 0.0 (min 1.0 $x)))

(= (tv-probability $tv)
   (if (= $tv (STV $s $c))
       (clamp01 (* $s $c))
       1.0))

(= (next-particle-id)
   (let $mn (catch (get-state particleid))
        (let $n (if-error $mn 0 $mn)
             (progn (change-state! particleid (+ $n 1)) $n))))

(= (particle-dist-id (ParticleDist $pid $scale)) $pid)
(= (particle-dist-id (ParticleDist $pid)) $pid)

(= (particle-dist-scale (ParticleDist $pid $scale)) $scale)
(= (particle-dist-scale (ParticleDist $pid)) 1.0)

(= (particle-fetch-pairs $pid)
   (collapse (match &particle_store (particle $pid $x $w) ($x $w))))

(= (particle-remove-id $pid)
   (collapse (match &particle_store (particle $pid $x $w)
              (remove-atom &particle_store (particle $pid $x $w)))))

(= (particle-store-pairs $pid ()) ())
(= (particle-store-pairs $pid (cons ($x $w) $tail))
   (progn
      (add-atom &particle_store (particle $pid $x $w))
      (particle-store-pairs $pid $tail)))

(= (list-count ()) 0)
(= (list-count (cons $_x $tail))
   (+ 1 (list-count $tail)))

(= (pairs-stats ()) (Stats 0.0 0.0 0))
(= (pairs-stats (cons ($_x $w) $tail))
   (let (Stats $sum $sumsq $count) (pairs-stats $tail)
        (Stats (+ $w $sum)
               (+ (* $w $w) $sumsq)
               (+ 1 $count))))

(= (ParticleStoreCount)
   (list-count (collapse (match &particle_store (particle $pid $x $w) ($pid $x $w)))))

(= (ParticleStoreClear)
   (progn
      (remove-all-atoms &particle_store)
      (change-state! particleid 0)))

(= (ParticleStorePruneKB)
   (let* (($keep
            (list_to_set
              (collapse
                (match &kb (: $_kb $_prf $_type $tv)
                   (if (= $tv (ParticleDist $pid $scale))
                       $pid
                       (if (= $tv (ParticleDist $pid))
                           $pid
                           (empty)))))))
          ($atoms (collapse (match &particle_store (particle $pid $x $w) ($pid $x $w))))
          ($_pruned
            (fold-flat
              (|-> ($acc ($pid $x $w))
                (progn
                   (if (is-member $pid $keep)
                       ()
                       (remove-atom &particle_store (particle $pid $x $w)))
                   $acc))
              ()
              $atoms))
          ($maxid (fold-flat (|-> ($acc $pid) (max $acc $pid)) -1 $keep))
          ($_reset (change-state! particleid (+ $maxid 1))))
      (ParticleStoreCount)))

(= (particle-neff-from-pairs $pairs)
   (let* (($norm (normalize-pairs $pairs))
          ((Stats $_sum $sumsq $_count) (pairs-stats $norm)))
      (if (<= $sumsq 0.0)
          0.0
          (/ 1.0 $sumsq))))

(= (particle-confidence-k) 20.0)

(= (particle-confidence-from-neff $neff)
   (if (<= $neff 0.0)
       0.0
       (/ $neff (+ $neff (particle-confidence-k)))))

(= (particle-confidence-from-pairs $pairs)
   (particle-confidence-from-neff (particle-neff-from-pairs $pairs)))

(= (normalize-pairs $pairs)
   (let (Stats $total $_sumsq $_count) (pairs-stats $pairs)
        (if (<= $total 0.0)
            ()
            (scale-dist-pairs $pairs (/ 1.0 $total)))))

(= (pairs-to-cdf-acc () $acc) ())
(= (pairs-to-cdf-acc (cons ($x $w) $tail) $acc)
   (let $nacc (+ $acc $w)
        (cons ($x $nacc) (pairs-to-cdf-acc $tail $nacc))))

(= (pairs-to-cdf $pairs)
   (pairs-to-cdf-acc $pairs 0.0))

(= (cdf-select $u (cons ($x $cum) ())) $x)
(= (cdf-select $u (cons ($x $cum) $tail))
   (if (<= $u $cum)
       $x
       (cdf-select $u $tail)))

(= (resample-counts $cdf $n $i $acc)
   (if (>= $i $n)
       $acc
       (let* (($u (/ (+ $i 0.5) $n))
              ($x (cdf-select $u $cdf))
              ($nacc (dist-add-mass $acc $x 1.0)))
         (resample-counts $cdf $n (+ $i 1) $nacc))))

(= (pairs-resample-systematic $pairs $n)
   (if (or (== $pairs ()) (<= $n 0))
       ()
       (let* (($cdf (pairs-to-cdf (normalize-pairs $pairs)))
              ($counts (resample-counts $cdf $n 0 ())))
          (scale-dist-pairs $counts (/ 1.0 $n)))))

(= (particle-budget-default) 512)

(= (ParticleSetBudget $n)
   (change-state! particle_budget $n))

(= (ParticleGetBudget)
   (let $mb (catch (get-state particle_budget))
        (if-error $mb (particle-budget-default) $mb)))

(= (particle-budget)
   (ParticleGetBudget))

(= (compress-pairs $pairs)
   (let* (($norm (normalize-pairs $pairs))
          ((Stats $_sum $_sumsq $count) (pairs-stats $norm)))
        (if (<= $count (particle-budget))
            $norm
            (pairs-resample-systematic $norm (particle-budget)))))

(= (ParticleFromPairs $pairs)
   (let* (($pid (next-particle-id))
          ($compressed (compress-pairs $pairs))
          ($_clear (particle-remove-id $pid))
          ($_store (particle-store-pairs $pid $compressed)))
      (ParticleDist $pid 1.0)))

(= (PointMass $x)
   (ParticleFromPairs (($x 1.0))))

(= (normal-kernel-9)
   ((-2.0 0.027630550638898826)
    (-1.5 0.0662822452863612)
    (-1.0 0.1238315368057753)
    (-0.5 0.18017382291138087)
    (0.0 0.20416368871516764)
    (0.5 0.18017382291138087)
    (1.0 0.1238315368057753)
    (1.5 0.0662822452863612)
    (2.0 0.027630550638898826)))

(= (affine-pairs () $mu $sigma) ())
(= (affine-pairs (cons ($x $w) $tail) $mu $sigma)
   (cons ((+ $mu (* $sigma $x)) $w)
         (affine-pairs $tail $mu $sigma)))

(= (ParticleFromNormal $mu $sigma)
   (ParticleFromPairs (affine-pairs (normal-kernel-9) $mu $sigma)))

(= (ParticlePairs (ParticleDist $pid $scale))
   (scale-dist-pairs (particle-fetch-pairs $pid) $scale))

(= (ParticlePairs (ParticleDist $pid))
   (ParticlePairs (ParticleDist $pid 1.0)))

(= (scale-dist-pairs () $w) ())
(= (scale-dist-pairs (cons ($x $p) $tail) $w)
   (cons ($x (* $p $w)) (scale-dist-pairs $tail $w)))

(= (dist-add-mass () $x $m) (cons ($x $m) ()))
(= (dist-add-mass (cons ($k $p) $tail) $x $m)
   (if (== $k $x)
       (cons ($k (+ $p $m)) $tail)
       (cons ($k $p) (dist-add-mass $tail $x $m))))

(= (natdist-bernoulli-step $acc $p ($n $mass))
   (let $acc0 (dist-add-mass $acc $n (* $mass (- 1.0 $p)))
        (dist-add-mass $acc0 (+ $n 1) (* $mass $p))))

(= (natdist-convolve-bernoulli $pairs $p)
   (fold-flat (|-> ($acc $item) (natdist-bernoulli-step $acc $p $item)) () $pairs))

(= (dist-prob-gt () $threshold) 0.0)
(= (dist-prob-gt (cons ($x $p) $tail) $threshold)
   (+ (if (> $x $threshold) $p 0.0)
      (dist-prob-gt $tail $threshold)))

(= (dist-prob-gt2-inner $xa $wa () $acc) $acc)
(= (dist-prob-gt2-inner $xa $wa (cons ($xb $wb) $tail) $acc)
   (let $nacc (+ $acc (if (> $xa $xb) (* $wa $wb) 0.0))
        (dist-prob-gt2-inner $xa $wa $tail $nacc)))

(= (dist-prob-gt2 () $pairsb) 0.0)
(= (dist-prob-gt2 (cons ($xa $wa) $taila) $pairsb)
   (let* (($acc (dist-prob-gt2-inner $xa $wa $pairsb 0.0))
          ($rest (dist-prob-gt2 $taila $pairsb)))
      (+ $acc $rest)))

(= (particle-map-pairs $fun () $acc) $acc)
(= (particle-map-pairs $fun (cons ($x $w) $tail) $acc)
   (let* (($call (cons $fun (cons $x ())))
          ($y (reduce (reduce $call)))
          ($nacc (dist-add-mass $acc $y $w)))
      (particle-map-pairs $fun $tail $nacc)))

(= (particle-map2-inner $fun $xa $wa () $acc) $acc)
(= (particle-map2-inner $fun $xa $wa (cons ($xb $wb) $tail) $acc)
   (let* (($call (cons $fun (cons $xa (cons $xb ()))))
          ($y (reduce (reduce $call)))
          ($nacc (dist-add-mass $acc $y (* $wa $wb))))
      (particle-map2-inner $fun $xa $wa $tail $nacc)))

(= (particle-map2-pairs $fun () $pairsb $acc) $acc)
(= (particle-map2-pairs $fun (cons ($xa $wa) $taila) $pairsb $acc)
   (let $nacc (particle-map2-inner $fun $xa $wa $pairsb $acc)
        (particle-map2-pairs $fun $taila $pairsb $nacc)))

(= (NatDistAddBernoulliFromSTV (NatDist $pairs) $tv)
   (let $p (tv-probability $tv)
        (NatDist (natdist-convolve-bernoulli $pairs $p))))

(= (DistMapFormula $fun $dist)
   (ParticleMap $fun $dist))

(= (DistMap2Formula $fun $dista $distb)
   (ParticleMap2 $fun $dista $distb))

(= (DistSumCountAcc (SumCount $sumdist $count) $hdist)
   (SumCount (DistMap2Formula + $sumdist $hdist) (+ $count 1)))

(= (DistAverageFromSumCount (SumCount $sumdist $count))
   (DistMapFormula (|-> ($x) (/ $x $count)) $sumdist))

(= (DistAverageFormula $steps $kb $pattern)
   (DistAverageFromSumCount
      (FoldAllTVRuntimeFormula $steps $kb $pattern (SumCount (PointMass 0.0) 0) DistSumCountAcc)))

(= (ParticleAddBernoulliFromSTV $pd $tv)
   (let* (($pid (particle-dist-id $pd))
          ($scale (particle-dist-scale $pd))
          ($p (tv-probability $tv))
          ($pairs (particle-fetch-pairs $pid))
          ($updated (fold-flat (|-> ($acc $item) (natdist-bernoulli-step $acc $p $item)) () $pairs))
          ($compressed (compress-pairs $updated))
          ($newid (next-particle-id))
          ($_store (particle-store-pairs $newid $compressed)))
      (ParticleDist $newid $scale)))

(= (ParticleMap $fun $pd)
   (let* (($pid (particle-dist-id $pd))
          ($scale (particle-dist-scale $pd))
          ($pairs (particle-fetch-pairs $pid))
          ($mapped (particle-map-pairs $fun $pairs ()))
          ($compressed (compress-pairs $mapped))
          ($newid (next-particle-id))
          ($_store (particle-store-pairs $newid $compressed)))
      (ParticleDist $newid $scale)))

(= (ParticleMap2 $fun $pda $pdb)
   (let* (($pida (particle-dist-id $pda))
          ($pidb (particle-dist-id $pdb))
          ($scalea (particle-dist-scale $pda))
          ($scaleb (particle-dist-scale $pdb))
          ($pairsa (particle-fetch-pairs $pida))
          ($pairsb (particle-fetch-pairs $pidb))
          ($mapped (particle-map2-pairs $fun $pairsa $pairsb ()))
          ($compressed (compress-pairs $mapped))
          ($newid (next-particle-id))
          ($_store (particle-store-pairs $newid $compressed)))
      (ParticleDist $newid (* $scalea $scaleb))))

;;;;;;;;;;;;;;;;;;;;;
;; Truth Functions ;;
;;;;;;;;;;;;;;;;;;;;;

(= (MpFormula (STV $abs $abc) (STV $as $ac))
   (STV (* $abs $as) (min $abc $ac)))

(= (MpFormula (STV $abs $abc) (NatDist $pairs))
   (NatDist (scale-dist-pairs $pairs (tv-probability (STV $abs $abc)))))

(= (MpFormula (STV $abs $abc) (FloatDist $pairs))
   (FloatDist (scale-dist-pairs $pairs (tv-probability (STV $abs $abc)))))

(= (MpFormula (STV $abs $abc) (ParticleDist $pid $scale))
   (ParticleDist $pid (* $scale (tv-probability (STV $abs $abc)))))

(= (MpFormula (STV $abs $abc) (ParticleDist $pid))
   (MpFormula (STV $abs $abc) (ParticleDist $pid 1.0)))

(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (let* (($sb (min $si $sa))
          ($cb (min $ci $ca)))
     (STV $sb $cb)))

(= (AndFormula (STV $s $c) (NatDist $pairs))
   (NatDist (scale-dist-pairs $pairs (tv-probability (STV $s $c)))))

(= (AndFormula (STV $s $c) (FloatDist $pairs))
   (FloatDist (scale-dist-pairs $pairs (tv-probability (STV $s $c)))))

(= (AndFormula (STV $s $c) (ParticleDist $pid $scale))
   (ParticleDist $pid (* $scale (tv-probability (STV $s $c)))))

(= (AndFormula (STV $s $c) (ParticleDist $pid))
   (AndFormula (STV $s $c) (ParticleDist $pid 1.0)))

(= (AndFormula (NatDist $pairs) (STV $s $c)) (STV $s $c))

(= (AndFormula (FloatDist $pairs) (STV $s $c)) (STV $s $c))

(= (AndFormula (ParticleDist $pid $scale) (STV $s $c)) (STV $s $c))

(= (AndFormula (ParticleDist $pid) (STV $s $c))
   (AndFormula (ParticleDist $pid 1.0) (STV $s $c)))

(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (let* (($sb (min $si $sa))
          ($cb (max $ci $ca)))
     (STV $sb $cb)))

(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb))
   (let* (($c (min $ca $cb)))
     (if (> $sa $sb)
         (STV $sa $c)
         (STV $sb $c))))


(= (AndProjection (STV $s $c)) (STV $s $c))
(= (OrProjection (STV $s $c)) (STV $s $c))

(= (DistGreaterThanFormula (NatDist $pairs) $threshold)
   (STV (dist-prob-gt $pairs $threshold) 1.0))

(= (DistGreaterThanFormula (FloatDist $pairs) $threshold)
   (STV (dist-prob-gt $pairs $threshold) 1.0))

(= (DistGreaterThanFormula (ParticleDist $pid $scale) $threshold)
   (let $pairs (particle-fetch-pairs $pid)
      (STV (* $scale (dist-prob-gt $pairs $threshold))
           (particle-confidence-from-pairs $pairs))))

(= (DistGreaterThanFormula (ParticleDist $pid) $threshold)
   (DistGreaterThanFormula (ParticleDist $pid 1.0) $threshold))

(= (DistGreaterThanDistFormula $pda $pdb)
   (let* (($pida (particle-dist-id $pda))
          ($pidb (particle-dist-id $pdb))
          ($scalea (particle-dist-scale $pda))
          ($scaleb (particle-dist-scale $pdb))
          ($pairsa (particle-fetch-pairs $pida))
          ($pairsb (particle-fetch-pairs $pidb))
          ($ca (particle-confidence-from-pairs $pairsa))
          ($cb (particle-confidence-from-pairs $pairsb)))
      (STV (* (* $scalea $scaleb) (dist-prob-gt2 $pairsa $pairsb))
           (min $ca $cb))))

(= (NotFormula (STV $s $c) (STV (- 1 $s) $c)))

(= (InversionFormula (STV $sa $ca) (STV $sb $cb) (STV $sab $cab)) (STV (/ (* $sb $sab) $sa) (min-atom ($ca $cb $cab)))) 

(= (Equal $a $b) (== $a $b))
(= (NotEqual $a $b) (not (== $a $b)))

;;;;;;;;;;;
;; API   ;;
;;;;;;;;;;;


;; Compile query to goal+adds, inject adds, then run goal through chainer.
(= (query $steps $kb $stmt)
  (let* (((cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt)))
         ($_ (inject-compiled-adds $adds))
         ($res (chainer $steps $query)))
    (pretty (superpose $res))))
