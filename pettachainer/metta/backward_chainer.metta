(= (goal-by-id $gid) (match &goal ($gid $depth $goal $expanded $pending) ($depth $goal $expanded $pending)))

(= (aggregate-by-id $agg-gid)
   (match &aggregate ($agg-gid $child-gid $args $base-score $pending $current-pid)
      ($child-gid $args $base-score $pending $current-pid)))

(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
       ($goal-key (goal-key $stored-goal))
       ($lookup-key (copy_term $goal-key))
       ($hits
          (collapse
             (once
                (match &goal_lookup ($lookup-key $stored-key $gid)
                   (if (=alpha $stored-key $goal-key) $gid (empty)))))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
             ($index-key (copy_term $goal-key))
             ($_1 (chainer-add-atom &goal ($gid $depth $stored-goal false 0.0)))
             ($_2 (chainer-add-atom &goal_lookup ($index-key $goal-key $gid))))
            $gid)
         (car-atom $hits))))

(= (schedule-goal-heap $agenda $score $gid)
   (let*
      ((($depth $goal $expanded $current) (goal-by-id $gid)))
      (if $expanded $agenda
         (if (>= $current $score) $agenda
            (let*
               (($closed-proof-bonus (if (goal-has-type-vars? $goal) 0.0 1.0))
                ($bonus (if (= $goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) $closed-proof-bonus 2.0))
                ($priority (+ (* 1000000000.0 $depth) (- 0 (+ (* 1000000.0 $score) $bonus))))
                ($nagenda (add_to_heap $agenda $priority (qgoal $score $gid)))
                ($_set
                   (progn (remove-atom &goal ($gid $depth $goal $expanded $current))
                      (chainer-add-atom &goal ($gid $depth $goal $expanded $score)))))
               $nagenda)))))

(= (schedule-aggregate-heap $agenda $agg-gid)
   (let*
      ((($child-gid $args $base-score $current $current-pid) (aggregate-by-id $agg-gid))
       (($depth $_goal $_expanded $_goal-pending) (goal-by-id $agg-gid)))
      (if (>= $current $base-score) $agenda
         (let*
            (($priority (+ (+ (* 1000000000.0 (+ 1 $depth)) (- 0 (* 1000000.0 $base-score))) 0.1))
             ($nagenda (add_to_heap $agenda $priority (qagg $base-score $agg-gid)))
             ($_set
                (progn
                   (remove-atom &aggregate ($agg-gid $child-gid $args $base-score $current $current-pid))
                   (chainer-add-atom &aggregate ($agg-gid $child-gid $args $base-score $base-score $current-pid)))))
            $nagenda))))

;; FoldAllCompiled and GroupedFoldAllCompiled both carry the kb and pattern as
;; the first two args; the child goal is the compiled query for that pattern.
(= (aggregate-child-goal (CPU $_fun $args $_goalres))
   (let*
      (($kb (car-atom $args))
       ($pattern (car-atom (cdr-atom $args)))
       ((compiled-query $child-goal $adds) (mm2compileQuery $kb (: $prf $pattern $tvin)))
       ($_ (inject-compiled-adds $adds)))
      $child-goal))

(= (aggregate-step-value (extract-value $pattern $value) $child-atom $_child-tv)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))
(= (aggregate-step-value (extract-inheritance-tv $kbid $_pattern) $child-atom $child-tv)
   (let ((Inheritance $subj $_concept) ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom)
      (WeightedTv (inheritance-subject-prior-tv $kbid $subj) $child-tv)))
(= (aggregate-step-value extract-tv $_child-atom $child-tv) $child-tv)
(= (aggregate-step-group-value $pattern $group $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $group))

(= (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv)
   (eval ($fun $acc (aggregate-step-value $extractor $child-atom $child-tv))))

(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc) (reduce (reduce (DistAverageFromSumCount $acc))))
(= (aggregate-finish base-rate $acc) (BaseRateTv $acc))
(= (aggregate-finish weighted-base-rate $acc) (WeightedBaseRateTv $acc))
(= (aggregate-finish weighted-base-rate-with-prior $acc) (WeightedBaseRateWithPriorTv $acc))
(= (aggregate-finish (member-inheritance $kbid) $acc)
   (member-inheritance-tv $kbid $acc))
(= (aggregate-finish (weighted-base-rate-in-universe $kbid) $acc)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedBaseRateTv $acc)
         (WeightedUniverseBaseRateTv $universe-size $acc))))
(= (aggregate-finish (weighted-base-rate-with-prior-in-universe $kbid) (BaseRateEvidenceWithPrior $prior $ev))
   (let $universe-size (kb-universe-size $kbid)
      (BaseRateWithPriorFormula
         (resolve-base-rate-prior $prior)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv $universe-size $ev)))))
(= (aggregate-finish uniform-prior $acc) (UniformPriorTv $acc))
(= (aggregate-finish uniform-prior-known $acc) (UniformPriorKnownTv $acc))

;; --- Frontier pooling of same-source projections -----------------------------
;; A conjunction frontier rejects a premise proof whose fact evidence overlaps
;; evidence already consumed (AndFormula would double count it). When the
;; overlapping proofs are marginal projections of the *same* stored or derived
;; (And ...) source, the sharing is exactly accountable: the group of premises
;; is one joint projection of that source. Such premises are pooled into a
;; single part whose TV is the marginal projection while the pool is partial
;; and the source's own TV once every conjunct of the source is in the pool.
;; Parts are folded with AndFormula across parts only, so frontiers whose parts
;; are all independent reproduce the unpooled TVs exactly; pooling only adds
;; results that were previously dropped. Overlap that is not fully explained by
;; a same-source pool keeps today's rejection.

(= (expr-arity $e) (if (== $e ()) 0 (+ 1 (expr-arity (cdr-atom $e)))))

;; Parts, one per consumed premise, in premise order:
;;   (indep-part $tv)                                -- ordinary premise
;;   (pool-part $base $base-tv $arity $idxs $ev $marginal-tv)
;;                                                   -- projections of one source
;;   skip-part                                       -- AndFormula chain steps
;;   unpoolable-part                                 -- unclassifiable premise;
;;                                                      poisons folds so joins
;;                                                      fall back to rejection
(= (frontier-part-tv $part)
   (case $part (
      ((indep-part $tv) $tv)
      ((pool-part $_base $btv $n $idxs $_ev $mtv)
         (if (== (expr-arity $idxs) $n) $btv $mtv)))))

(= (frontier-parts-fold-acc $acc ()) $acc)
(= (frontier-parts-fold-acc $acc (cons $part $rest))
   (frontier-parts-fold-acc (AndFormula $acc (frontier-part-tv $part)) $rest))

(= (frontier-parts-fold (cons $first $rest))
   (frontier-parts-fold-acc (frontier-part-tv $first) $rest))

;; TV and conjunct count of a projection's source conjunction. Stored proof
;; outputs carry (proof-ref $pid) handles instead of proof terms, so the real
;; projection term lives in the proof node's kind; its base is a (proof-ref
;; $bpid) for chained sources (facts and derived conjunctions alike) or a
;; statement name for kb-materialized projection facts.
(= (frontier-and-source-info ($type $_kb $_prf $tv))
   (if (is-expr $type)
      (if (== (car-atom $type) And)
         (source-info $tv (expr-arity (cdr-atom $type)))
         no-source-info)
      no-source-info))

;; Pools are keyed by the source's output key (type + kb), not by its proof
;; node: different conjuncts can instantiate a projection rule's source premise
;; differently (open vs ground goals), producing distinct proof nodes for the
;; same source proposition.
(= (frontier-source-entry-from-atom $atom)
   (let $i (frontier-and-source-info $atom)
      (if (== $i no-source-info) no-source-entry
         (source-entry (candidate-output-key $atom) $i))))

(= (frontier-source-entry $base)
   (if (= $base (proof-ref $bpid))
      (frontier-source-entry-from-atom (proof-output-atom $bpid))
      (let $hits
         (collapse
            (match &kb ($type $kb $base $tv)
               (let $e (frontier-source-entry-from-atom ($type $kb $base $tv))
                  (if (== $e no-source-entry) (empty) $e))))
         (if (== $hits ()) no-source-entry (car-atom $hits)))))

(= (frontier-proof-term $kind)
   (case $kind (
      ((rule $term) $term)
      ((leaf $term) $term)
      ($_ no-term))))

(= (frontier-proof-projection $kind)
   (let $term (frontier-proof-term $kind)
      (if (= $term ($_t $_kb $prf $_tv))
         (if (is-var $prf) no-projection
            (if (= $prf (marginal-proj $idx $base))
               (projection $idx $base)
               no-projection))
         no-projection)))

(= (frontier-atom-part $pid ($_type $_kb $_prf $tv))
   (let $proj (frontier-proof-projection (proof-kind-by-id $pid))
      (if (= $proj (projection $idx $base))
         (let $entry (frontier-source-entry $base)
            (if (= $entry (source-entry $key (source-info $btv $n)))
               (pool-part $key $btv $n ($idx) (snd (proof-stats-by-id $pid)) $tv)
               (indep-part $tv)))
         (indep-part $tv))))

(= (frontier-premise-part $pid)
   (let $out (proof-output-atom $pid)
      (if (= $out (CPU $f $args $res))
         (if (== $f AndFormula) skip-part (indep-part (cpu-premise-tv $f $args $res)))
         (frontier-atom-part $pid $out))))

(= (frontier-parts-idx-union $a ()) $a)
(= (frontier-parts-idx-union $a (cons $i $rest))
   (frontier-parts-idx-union (if (is-member $i $a) $a (append $a ($i))) $rest))

(= (frontier-pool-key $part)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv) $key)
      ($_ no-pool-key))))

(= (frontier-parts-same-pool () $_key) no-pool)
(= (frontier-parts-same-pool (cons $head $rest) $key)
   (if (=alpha (frontier-pool-key $head) $key)
      $head
      (frontier-parts-same-pool $rest $key)))

(= (frontier-parts-join-pool () $pool) ($pool))
(= (frontier-parts-join-pool (cons $head $rest) (pool-part $key $btv $n $idxs $ev $mtv))
   (if (=alpha (frontier-pool-key $head) $key)
      (let (pool-part $okey $obtv $on $oidxs $oev $omtv) $head
         (cons
            (pool-part $okey $obtv $on
               (frontier-parts-idx-union $oidxs $idxs)
               (list_to_set (append $oev $ev))
               $omtv)
            $rest))
      (cons $head (frontier-parts-join-pool $rest (pool-part $key $btv $n $idxs $ev $mtv)))))

(= (frontier-parts-add $parts $part)
   (case $part (
      (skip-part $parts)
      ((pool-part $base $btv $n $idxs $ev $mtv)
         (frontier-parts-join-pool $parts (pool-part $base $btv $n $idxs $ev $mtv)))
      ($other (append $parts ($other))))))

;; Projections score with their source's confidence: a partial pool's marginal
;; confidence (0 for a strength-0 source) says nothing about the completed
;; pool's, and would starve the frontier before the join that completes it.
(= (frontier-part-score $part $pscore)
   (case $part (
      ((pool-part $_base $btv $_n $_idxs $_ev $_mtv) (max $pscore (tv-confidence $btv)))
      ($_ $pscore))))

;; A partial pool's marginal TV can have zero confidence (strength-0 source),
;; which zeroes the remaining chain's expected confidence and would starve the
;; frontier before the join that completes the pool. The pool's source
;; confidence is the frontier's real potential.
(= (frontier-pool-potential ()) 0.0)
(= (frontier-pool-potential (cons $part $rest))
   (case $part (
      ((pool-part $_k $btv $n $idxs $_ev $_mtv)
         (if (< (expr-arity $idxs) $n)
            (max (tv-confidence $btv) (frontier-pool-potential $rest))
            (frontier-pool-potential $rest)))
      ($_ (frontier-pool-potential $rest)))))

(= (frontier-remaining-score $bundle $parts)
   (max (premises-expected-confidence (copy_term (and-bundle-premises $bundle)))
      (frontier-pool-potential $parts)))

(= (frontier-and-step-premise? $prem)
   (if (is-expr $prem)
      (if (== (car-atom $prem) CPU)
         (== (car-atom (cdr-atom $prem)) AndFormula)
         false)
      false))

;; Pop the consumed premise AND its AndFormula step, binding the step's output
;; to the parts fold (the chain's pairwise application would double count the
;; pooled source). Yields () when the premise is not directly followed by its
;; AndFormula step; the caller then drops the proof as before.
(= (frontier-pooled-bundle $bundle $pid $folded)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
         ((cons $prem (cons $step $rest))
            (if (frontier-and-step-premise? $step)
               (if (= $prem (proof-output-atom $pid))
                  (if (= (CPU AndFormula $_fargs $folded) $step)
                     (make-and-bundle $goal $rest)
                     ())
                  ())
               ()))
         ($_ ())))))

(= (make-and-bundle $goal $args) (cons and-bundle (cons $goal $args)))
(= (and-bundle-goal $bundle) (car-atom (cdr-atom $bundle)))
(= (and-bundle-premises $bundle) (cdr-atom (cdr-atom $bundle)))

(= (advance-frontier-bundle $bundle $pid)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (() ())
           ((cons $prem $rest)
              (if (= $prem (proof-output-atom $pid)) (make-and-bundle $goal $rest) ()))))))

(= (waiter-live? (frontier-waiter $_parent-gid $_bundle $_score $_seen $_parts $rev-pids))
   (proof-list-live? $rev-pids))

;; These compiler-generated joins keep their premise TVs separate instead of
;; combining them through AndFormula. Their premises may therefore share
;; evidence: total implication compares positive/refuting contexts, while a
;; member-inheritance sample pairs an antecedent membership with a consequent
;; that may itself have been derived from that antecedent. The resulting proof
;; still carries the union of both evidence sets, and normal cycle checks apply.
(= (shared-evidence-frontier-proof? $proof)
   (case $proof (
      ((total-implication-frontier $_inner) true)
      ((inheritance-query-result $inner)
         (shared-evidence-frontier-proof? $inner))
      ((member-inheritance-sample $_antecedent $_consequent) true)
      ($_other false))))

(= (frontier-allows-shared-evidence? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (if (= $goal ($_type $_kb $proof $_tv))
         (shared-evidence-frontier-proof? $proof)
         false)))

(= (advance-frontier-waiter-heap $agenda (frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids) $pid)
   (if (not (waiter-live? (frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids))) $agenda
      (let*
         ((($pscore $pev) (proof-stats-by-id $pid))
          ($frontier-pscore (frontier-proof-score $pid $pscore))
          ($part-hits (collapse (frontier-premise-part $pid)))
          ($part (if (== $part-hits ()) unpoolable-part (car-atom $part-hits)))
          ($overlap
             (and (not (frontier-allows-shared-evidence? $bundle))
                (premise-evidence-overlap? $seen $pev))))
         (if (frontier-pool-join? $part $parts $seen $pev)
            (frontier-advance-pooled-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids
               $pid $pev $part)
            (if $overlap $agenda
               (let $next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)
                  (if (== $next-bundle ()) $agenda
                     (let*
                        (($nparts (frontier-parts-add $parts $part))
                         ($next-score
                            (min-atom ($score
                                       (frontier-part-score $part $frontier-pscore)
                                       (frontier-remaining-score $next-bundle $nparts)))))
                        (spawn-frontier-heap $agenda
                           $parent-gid
                           $next-bundle
                           $next-score
                           (list_to_set (append $seen $pev))
                           $nparts
                           (cons $pid $rev-pids))))))))))

;; A premise proof joins the frontier's pool for its projection source when a
;; pool for that source already exists and any evidence overlap is fully
;; explained by it. The join applies with or without overlap: projections of
;; one source are never independent, and forward-chained materialization can
;; hide their shared provenance behind distinct fact atoms. Overlap not
;; explained by a pool keeps the double-counting rejection.
(= (frontier-pool-join? $part $parts $seen $pev)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv)
         (let $existing (frontier-parts-same-pool $parts $key)
            (if (== $existing no-pool) false
               (let (pool-part $_k $_btv2 $_n2 $_idxs2 $oev $_mtv2) $existing
                  (evidence-subset?
                     (intersection-atom (fact-evidence-only $seen) (fact-evidence-only $pev))
                     (fact-evidence-only $oev))))))
      ($_ false))))

(= (frontier-advance-pooled-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids $pid $pev $part)
   (let*
      (($nparts (frontier-parts-add $parts $part))
       ($folded-hits (collapse (frontier-parts-fold $nparts))))
      (if (== $folded-hits ()) $agenda
         (let $next-bundle (frontier-pooled-bundle (copy_term $bundle) $pid (car-atom $folded-hits))
            (if (== $next-bundle ()) $agenda
               (let $next-score
                  (min-atom ($score
                             (frontier-part-score $part 0.000001)
                             (frontier-remaining-score $next-bundle $nparts)))
                  (spawn-frontier-heap $agenda
                     $parent-gid
                     $next-bundle
                     $next-score
                     (list_to_set (append $seen $pev))
                     $nparts
                     (cons $pid $rev-pids))))))))

(= (frontier-waiter-step $waiter $rest)
   (if (and (is-expr $waiter) (== (car-atom $waiter) frontier-waiter))
      (cons $waiter $rest)
      $rest))

(= (aggregate-waiter-step $waiter $rest)
   (case $waiter (((aggregate-waiter $agg-gid) (cons $agg-gid $rest)) ($_other $rest))))

(= (spawn-frontier-goal-heap $agenda $score $gid $waiter)
   (let*
      (($_1 (chainer-add-atom &goal_waiter ($gid $waiter)))
       ($agenda1
          (fold-flat (|-> ($acc $pid) (advance-frontier-waiter-heap $acc $waiter $pid))
             $agenda
             (goal-merged-proof-ids $gid)))
       ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
      $nagenda))

(= (base-rate-finish? $finish)
   (case $finish (
      (base-rate true)
      (weighted-base-rate true)
      (weighted-base-rate-with-prior true)
      ((weighted-base-rate-in-universe $_kbid) true)
      ((weighted-base-rate-with-prior-in-universe $_kbid) true)
      ($_other false))))

(= (base-rate-aggregate-key $args)
   (if (= $args ($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode))
      (if (base-rate-finish? $finish)
         ($kbid $pattern $finish)
         ())
      ()))

(= (commit-cached-aggregate-heap $agenda $agg-gid $args $tv)
   (let*
      (($result (CPU FoldAllCompiled $args $tv))
       ($pid (store-proof-candidate $agg-gid (aggregate-result-candidate $result () ()))))
      (wake-proof-commit-heap $agenda $agg-gid $pid)))

(= (base-rate-refine-score $score) (* 0.25 $score))

(= (ensure-aggregate-child-goal $agg-gid $goal-view $args $score)
   (let*
      (($child-goal (aggregate-child-goal $goal-view))
       (($depth $_goal $_expanded $_pending) (goal-by-id $agg-gid))
       ($child-gid (ensure-goal-at-depth $child-goal (+ 1 $depth)))
       ($hits (collapse (once (match &aggregate ($agg-gid $_child $_args $_base $_pending1 $_current) true))))
       ($_agg
          (if (== $hits ())
             (chainer-add-atom &aggregate ($agg-gid $child-gid $args $score 0.0 ()))
             ())))
      $child-gid))

(= (spawn-refining-aggregate-heap $agenda $score $agg-gid $goal-view $args $tv $source)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($pid (store-proof-candidate $agg-gid (aggregate-result-candidate (CPU FoldAllCompiled $args $tv) () ())))
       ($_source
          (if (== $source forward-approx)
             (add-atom &aggregate_forward_approx ($agg-gid))
             ()))
       ($_set
          (progn
             (remove-atom &aggregate ($agg-gid $child-gid $args $score 0.0 ()))
             (chainer-add-atom &aggregate ($agg-gid $child-gid $args $score 0.0 $pid))))
       ($_wait (chainer-add-atom &goal_waiter ($child-gid (aggregate-waiter $agg-gid))))
       ($agenda1 (wake-proof-commit-heap $agenda $agg-gid $pid))
       ($nagenda (schedule-goal-heap $agenda1 (base-rate-refine-score $score) $child-gid)))
      $nagenda))

(= (spawn-aggregate-goal-heap $agenda $score $agg-gid $goal-view)
   (let*
      (($args (copy_term (let (CPU $_agg-fun $view-args $_goalres) $goal-view $view-args)))
       ($cache-key (base-rate-aggregate-key $args))
       ($entries
          (if (== $cache-key ()) ()
             (let ($kbid $pattern $mode) $cache-key (base-rate-cache-entries-for-mode $kbid $pattern $mode)))))
      (if (== $entries ())
         (spawn-aggregate-goal-live-heap $agenda $score $agg-gid $goal-view $args)
         (let (base-rate $_kbid $_stored $tv $source $_mode) (car-atom $entries)
            (if (== $source user)
               (commit-cached-aggregate-heap $agenda $agg-gid $args $tv)
               (spawn-refining-aggregate-heap
                  $agenda $score $agg-gid $goal-view $args $tv $source))))))

(= (spawn-aggregate-goal-live-heap $agenda $score $agg-gid $goal-view $args)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($_wait (chainer-add-atom &goal_waiter ($child-gid (aggregate-waiter $agg-gid))))
       ($agenda1 (schedule-goal-heap $agenda $score $child-gid))
       ($nagenda (schedule-aggregate-heap $agenda1 $agg-gid)))
      $nagenda))

(= (aggregate-args-grouped? $args)
   (if (= $args ($_kb $_pattern $_group $_extractor $_init $_fun $_finish $_tv-mode)) true false))

(= (aggregate-proof-fold-step $args (aggregate-state $acc $ev $children) $pid)
   (let*
      ((($_agg-kb $_agg-pattern $extractor $_agg-init $fun $_agg-finish $_agg-tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($child-tv (if (= $child-atom ($_type $_kb $_prf $tv)) $tv no-tv))
       ($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
       ($nev (list_to_set (append $ev $pev)))
       ($nchildren (append $children ($pid))))
      (aggregate-state $nacc $nev $nchildren)))

(= (aggregate-noncyclic-source-step $agg-gid $acc $pid)
   (if (proof-depends-on-goal-seen? $pid $agg-gid closed-goal ()) $acc (append $acc ($pid))))

;; Cycle rejection must happen before equivalent outputs are merged.  Otherwise
;; one recursive proof can make a merged representative look cyclic and hide an
;; independent direct proof of the same grounded atom from the aggregate.
(= (aggregate-fold-source-ids $agg-gid $child-gid)
   (proof-output-group-representative-pids $child-gid
      (proof-output-groups
         (fold-flat (aggregate-noncyclic-source-step $agg-gid)
            ()
            (goal-live-proof-ids $child-gid)))))

(= (aggregate-final-state $agg-gid $child-gid $args)
   (let*
      ((($_kb $_pattern $_extractor $init-acc $_fun $_finish $_tv-mode) (copy_term $args)))
      (fold-flat (aggregate-proof-fold-step $args)
         (aggregate-state $init-acc () ())
         (aggregate-fold-source-ids $agg-gid $child-gid))))

(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid ())
   (let*
      (($nacc (aggregate-foldall-step-acc $extractor $fun $init $child-atom $child-tv))
       ($nev (list_to_set $pev)))
      ((aggregate-group-state $group $nacc $nev ($pid)))))
(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid (cons (aggregate-group-state $old-group $acc $ev $children) $rest))
   (if (== $group $old-group)
      (let*
         (($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
          ($nev (list_to_set (append $ev $pev)))
          ($nchildren (append $children ($pid))))
         (cons (aggregate-group-state $old-group $nacc $nev $nchildren) $rest))
      (cons (aggregate-group-state $old-group $acc $ev $children)
         (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $rest))))

(= (grouped-aggregate-proof-fold-step $args $states $pid)
   (let*
      ((($_agg-kb $pattern $group-template $extractor $init $fun $_finish $_tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($group (aggregate-step-group-value $pattern $group-template $child-atom))
       ($child-tv (if (= $child-atom ($_type $_kb $_prf $tv)) $tv no-tv)))
      (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $states)))

(= (grouped-aggregate-final-states $agg-gid $child-gid $args)
   (fold-flat (grouped-aggregate-proof-fold-step $args)
      ()
      (aggregate-fold-source-ids $agg-gid $child-gid)))

(= (grouped-aggregate-result $args (aggregate-group-state $group $acc $_ev $_children))
   (let*
      ((($kb $pattern $_group-template $extractor $init $fun $finish $tv-mode) $args))
      (CPU GroupedFoldAllCompiled ($kb $pattern $group $extractor $init $fun $finish $tv-mode) (aggregate-finish $finish $acc))))

(= (commit-grouped-aggregate-state-heap $agg-gid $args $agenda (aggregate-group-state $group $acc $ev $children))
   (let*
      (($result (grouped-aggregate-result $args (aggregate-group-state $group $acc $ev $children)))
       ($score (term-confidence $result))
       ($accepted (classify-goal-proof-candidate $agg-gid $result $ev $score)))
      (commit-grouped-aggregate-candidate-heap $agenda
         $agg-gid
         $accepted
         (aggregate-result-candidate $result $ev $children))))

(= (append-grouped-aggregate-current-pid! $agg-gid $pid)
   (let*
      ((($child-gid $args $base-score $pending $current-pids) (aggregate-by-id $agg-gid))
       ($next-pids (cons $pid $current-pids)))
      (progn
         (remove-atom &aggregate ($agg-gid $child-gid $args $base-score $pending $current-pids))
         (chainer-add-atom &aggregate ($agg-gid $child-gid $args $base-score $pending $next-pids)))))

(= (commit-grouped-aggregate-candidate-heap $agenda $agg-gid $accepted (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $agg-gid $kind $children) $agenda
         (let*
            (($pid (store-proof-candidate $agg-gid (proof-candidate $kind $score $ev $children)))
             ($_set (append-grouped-aggregate-current-pid! $agg-gid $pid))
             ($_cache-invalidate (invalidate-proof-live-caches)))
            (wake-proof-commit-heap $agenda $agg-gid $pid)))))

(= (run-grouped-aggregate-heap $agenda $agg-gid $child-gid $args)
   (fold-flat (commit-grouped-aggregate-state-heap $agg-gid $args)
      $agenda
      (grouped-aggregate-final-states $agg-gid $child-gid $args)))

(= (run-aggregate-heap $agenda $agg-gid)
   (let*
      ((($child-gid $args $base-score $pending $current-pid) (aggregate-by-id $agg-gid))
       ($grouped? (aggregate-args-grouped? $args))
       ($next-current-pid (if $grouped? () $current-pid))
       ($_clear
          (progn
             (remove-atom &aggregate ($agg-gid $child-gid $args $base-score $pending $current-pid))
             (chainer-add-atom &aggregate ($agg-gid $child-gid $args $base-score 0.0 $next-current-pid)))))
      (if $grouped?
         (run-grouped-aggregate-heap $agenda $agg-gid $child-gid $args)
         (let*
            (((aggregate-state $acc $ev $children) (aggregate-final-state $agg-gid $child-gid $args))
             (($_kb $_pattern $_extractor $_init $_fun $finish $_tv-mode) $args)
             ($result (CPU FoldAllCompiled $args (aggregate-finish $finish $acc)))
             ($commit-ev (if (background-aggregate-finish? $finish) () $ev)))
            (if (base-rate-refinement-degrades? $agg-gid $finish $current-pid $result)
               $agenda
               (if (aggregate-snapshot-changed? $current-pid $result $commit-ev)
                  (commit-aggregate-snapshot-heap $agenda $agg-gid $result $commit-ev $children)
                  $agenda))))))

; Background aggregates (node priors / base rates) summarise the whole store
; rather than chaining specific evidence, so their committed proof carries no
; evidence dependency -- this keeps them from forming evidence cycles with the
; very premises they are computed alongside.
(= (background-aggregate-finish? $finish)
   (if (base-rate-finish? $finish) true
      (if (== $finish uniform-prior) true (== $finish uniform-prior-known))))

(= (base-rate-refinement-degrades? $agg-gid $finish $current-pid $result)
   (if (not (==
         (collapse (once (match &aggregate_forward_approx ($agg-gid) true)))
         ()))
      false
      (if (base-rate-finish? $finish)
      (if (== $current-pid ()) false
         (let*
            (($new-tv (let (CPU $_fun $_args $ntv) $result $ntv))
             ($current-tv (let (CPU $_cfun $_cargs $ctv) (proof-output-atom $current-pid) $ctv)))
            (if (= $current-tv (STV $_cs $_cc))
               (if (= $new-tv (STV $_ns $_nc))
                  (< (tv-confidence $new-tv) (tv-confidence $current-tv))
                  true)
               false)))
      false)))

(= (direct-goal-results-view $steps (CPU $fun $args $_res))
   (CPU $fun $args (reduce (cpu-call $steps $fun $args))))
(= (direct-goal-results-view $steps ($type $kb $prf $tv))
   (match &kb ($type $kb $prf $tv)
      ($type $kb $prf $tv)))

(= (expand-direct-goal-step $gid $_goal $agenda $result)
   (let*
      (($score (term-confidence $result))
       ($ev (leaf-evidence-for-result $result))
       ($accepted (classify-goal-proof-candidate $gid $result $ev $score))
       ($nagenda (commit-proof-candidate-heap $agenda $gid $accepted (leaf-result-candidate $result $ev))))
      $nagenda))

(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (let*
      (($results (collapse (direct-goal-results-view $steps $goal)))
       ($agenda1 (fold-flat (expand-direct-goal-step $gid $goal) $agenda $results)))
      (expand-rule-goal-heap $agenda1 $gid $goal)))

(= (inject-compiled-query-adds (compiled-query $_goal $adds)) (inject-compiled-adds $adds))

(= (inject-implication-subgoal-query-adds ($type ($kbid MAIN Nil) $prf $tv))
   (if (= $type (Implication (cons Premises $_premises) (cons Conclusions $_conclusions)))
      (let $compiled-queries (collapse (mm2compileQuery $kbid (: $prf $type $tv)))
         (foreach-flat inject-compiled-query-adds $compiled-queries))
      ()))
(= (inject-implication-subgoal-query-adds $_goal) ())

(= (open-rule-goal? $goal)
   (if (= $goal ($type $_kb $_prf $_tv))
      (not (== (extract-vars $type) ()))
      false))

(= (rule-goal-head-view-for-key ($goal $parent-gid) $key)
   (match ccls_head_index ($key $rule-id)
      (match rules ($rule-id $goal $args)
         ($rule-id $args $goal $parent-gid))))

;; Look up rules by the goal's concrete head *and* the `any` wildcard bucket, so
;; an open goal still reaches variable-headed conclusions (which only live under
;; `any`). This mirrors the forward chainer's direct+wildcard union and removes
;; the behavioural gap between open and closed goals.
(= (rule-goal-head-view ($goal $parent-gid))
   (let $key (forward-indexable-premise-key $goal)
      (if (== $key ())
         ()
         (let $wildcard-key (forward-premise-wildcard-key $goal)
            (superpose (
               (rule-goal-head-view-for-key ($goal $parent-gid) $key)
               (if (== $key $wildcard-key) (empty)
                  (rule-goal-head-view-for-key ($goal $parent-gid) $wildcard-key))))))))

(= (rule-goal-contextual? $goal)
   (if (= $goal ($_type ($_kbid $ctx $_vars) $_prf $_tv))
      (not (== $ctx MAIN))
      false))

(= (rule-goal-full-view ($goal $parent-gid))
   (match ccls_index ($goal $rule-id)
      (match rules ($rule-id $goal $args)
         ($rule-id (contextualize-rule-args $goal $args) $goal $parent-gid))))

(= (same-var-in-list? $_var ()) false)
(= (same-var-in-list? $var (cons $head $tail))
   (or (== $var $head) (same-var-in-list? $var $tail)))

(= (any-same-var? () $_vars) false)
(= (any-same-var? (cons $var $rest) $vars)
   (or (same-var-in-list? $var $vars) (any-same-var? $rest $vars)))

(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false
      (any-same-var? (extract-vars $type) $vars)))

(= (contextualize-rule-premise ($type ($kbid $prem-ctx $prem-vars) $prf $tv)
      ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv))
   (if (and (== $prem-ctx MAIN) (and (not (== $ctx MAIN)) (context-vars-in-type? $type $vars)))
      ($type ($kbid $ctx $vars) $prf $tv)
      ($type ($kbid $prem-ctx $prem-vars) $prf $tv)))
(= (contextualize-rule-premise (CPU $fun $args $res) $_goal) (CPU $fun $args $res))

(= (contextualize-rule-args $_goal ()) ())
(= (contextualize-rule-args $goal (cons $premise $rest))
   (cons (contextualize-rule-premise $premise $goal)
      (contextualize-rule-args $goal $rest)))

(= (rule-goal-view ($goal $parent-gid))
   (if (open-rule-goal? $goal)
      (if (rule-goal-contextual? $goal)
         (rule-goal-full-view ($goal $parent-gid))
         (rule-goal-head-view ($goal $parent-gid)))
      (rule-goal-full-view ($goal $parent-gid))))

(= (spawn-frontier-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (()
              (let*
                 (($pid-list (reverse $rev-pids))
                  ($candidate
                     (normalize-proof-candidate-evidence
                        (proof-candidate (rule $goal) $score $seen $pid-list)))
                  ((proof-candidate $_kind $_candidate-score $candidate-ev $_children) $candidate))
                 (commit-proof-candidate-heap $agenda
                    $parent-gid
                    (classify-goal-proof-candidate $parent-gid $goal $candidate-ev $score)
                    $candidate)))
           ((cons $prem $_rest)
              (let*
                 ((($parent-depth $_goal1 $_expanded $_pending) (goal-by-id $parent-gid))
                  ($gid (ensure-goal-at-depth $prem (+ 1 $parent-depth)))
                  ($stored-bundle (copy_term $bundle)))
                 (spawn-frontier-goal-heap $agenda
                    $score
                    $gid
                    (frontier-waiter $parent-gid
                       $stored-bundle
                       $score
                       $seen
                       $parts
                       $rev-pids))))))))

(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (fold-flat expand-rule-goal-fold
      $agenda
      (collapse (rule-goal-view ($goal $parent-gid)))))

;; Cached expected score, computed at rule-add time (store-rule-expected-score!).
;; The cache assumes the goal's TV slot is unbound (the value depends only on
;; premise structure and stored TVs then); a goal queried with a known TV falls
;; back to computing against the bound bundle, as before.
(= (inheritance-lift-rule-goal? $goal)
   (case $goal (
      (($_type $_kb ((inheritance-rule-lift $_rule) $_source $_instance) $_tv)
         true)
      ($_other false))))

(= (rule-expected-score $rule-id $goal $args)
   ;; A specialized lift is a completeness bridge for evidence that cannot
   ;; execute directly in the hypothetical context. Native implication views
   ;; must be allowed to finish before that bridge closes the parent goal.
   (if (inheritance-lift-rule-goal? $goal) 0.000001
      (if (if (= $goal ($_gtype $_gkb $_gprf $gtv)) (is-var $gtv) false)
         (let $hits (collapse (match rule_expected ($rule-id $score) $score))
            (if (== $hits ()) (premises-expected-confidence (copy_term $args)) (car-atom $hits)))
         (premises-expected-confidence (copy_term $args)))))

;; --- Premise pre-filter (opt-in via set-backward-premise-prefilter) ---------
;; Walks a copy of a candidate rule's premise list before any frontier state is
;; created: ground deterministic CPU premises are evaluated eagerly (binding
;; e.g. computed step variables for later premises), and a fully ground atom
;; premise prunes the rule when no fact matches it AND no rule can conclude its
;; head. In KBs where every premise head is also some rule's conclusion the
;; filter never prunes, so behavior degrades to the unfiltered search.

(= (set-backward-premise-prefilter $enabled) (change-state! bwd_premise_prefilter $enabled))
(= (backward-premise-prefilter?)
   (let $enabled (catch (get-state bwd_premise_prefilter))
      (if-error $enabled false $enabled)))

(= (prefilter-head-concludable? $prem)
   (let $key (forward-indexable-premise-key $prem)
      (if (== $key ()) true
         (let $wildcard (forward-premise-wildcard-key $prem)
            (or (not (== (collapse (once (match ccls_head_index ($key $_id) true))) ()))
               (if (== $key $wildcard) false
                  (not (== (collapse (once (match ccls_head_index ($wildcard $_wid) true))) ()))))))))

(= (prefilter-fact-missing? ($type ($kbid $_ctx $_vars) $_prf $_tv))
   (== (collapse (once (match &kb ($type ($kbid $_c2 $_v2) $_p2 $_t2) true))) ()))

;; CPU functions the filter must not run eagerly: aggregate folds have their own
;; search machinery and store-scanning formulas are too costly for a filter.
(= (prefilter-cpu-opaque? $fun)
   (is-member $fun (FoldAllCompiled GroupedFoldAllCompiled ConceptNodePriorFormula)))

(= (prefilter-premise-blocks? (CPU $fun $args $res))
   (if (prefilter-cpu-opaque? $fun) false
      ;; Only run a CPU premise eagerly when its argument list is fully ground
      ;; ($args is inspected as-is; building an ($fun ...) expression here would
      ;; make the runtime apply $fun to unevaluated arguments).
      (if (and (not (is-var $fun)) (== (extract-vars $args) ()))
         (let $hits (collapse (cpu-call 0 $fun $args))
            (if (== $hits ()) true
               (if (= $res (car-atom $hits)) false true)))
         false)))
(= (prefilter-premise-blocks? ($type ($kbid $ctx $vars) $prf $tv))
   (if (== (extract-vars $type) ())
      (if (prefilter-fact-missing? ($type ($kbid $ctx $vars) $prf $tv))
         (not (prefilter-head-concludable? ($type ($kbid $ctx $vars) $prf $tv)))
         false)
      false))

(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

;; The walk runs on a copy (eager CPU evaluation binds variables) inside a
;; collapse so a premise shape neither clause covers makes the walk yield
;; nothing and the rule is kept, never dropped.
(= (rule-premise-prefilter-prunes? $args)
   (if (backward-premise-prefilter?)
      (let $hits (collapse (prefilter-prunes-walk (copy_term $args)))
         (if (== $hits ()) false (car-atom $hits)))
      false))

(= (expand-rule-goal-fold $agenda ($rule-id $args $goal $parent-gid))
   (if (rule-premise-prefilter-prunes? $args) $agenda
      (let*
         (($expected-score (rule-expected-score $rule-id $goal $args))
          ($bound (rule-marginal-score (goal-current-confidence $parent-gid) $expected-score))
          ($bundle (copy_term (make-and-bundle $goal $args))))
         (spawn-frontier-heap $agenda
            $parent-gid
            $bundle
            $bound
            ()
            ()
            ()))))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      ((($depth $goal $expanded $pending) (goal-by-id $gid))
       ($_expand
          (progn (remove-atom &goal ($gid $depth $goal $expanded $pending))
             (chainer-add-atom &goal ($gid $depth $goal true $pending))))
       ($_query-adds (if (> $depth 0) (inject-implication-subgoal-query-adds $goal) ()))
       ($nagenda0
          (if (and (= $goal (CPU $fun $_args $_res)) (or (== $fun FoldAllCompiled) (== $fun GroupedFoldAllCompiled)))
             (spawn-aggregate-goal-heap $agenda $score $gid $goal)
             (expand-direct-goal-heap $agenda $steps $gid $goal)))
       ($nagenda (if (== $nagenda0 ()) (empty_heap) $nagenda0)))
      $nagenda))

(= (search-agenda-step $steps $agenda (qgoal $score $gid))
   (let*
      ((($depth $goal $expanded $pending) (goal-by-id $gid)))
      (if (and (not $expanded) (== $pending $score))
         (let*
            (($_clear
                 (progn (remove-atom &goal ($gid $depth $goal $expanded $pending))
                    (chainer-add-atom &goal ($gid $depth $goal $expanded 0.0))))
             ($next-steps (- $steps 1))
             ($nagenda (bounded-agenda-prune $next-steps (expand-goal-heap $agenda $steps $score $gid))))
            (search-agenda-heap $next-steps $nagenda))
         (search-agenda-heap $steps $agenda))))

(= (search-agenda-step $steps $agenda (qagg $score $agg-gid))
   (let*
      ((($_child-gid $_args $_base-score $pending $_current-pid) (aggregate-by-id $agg-gid)))
      (if (== $pending $score)
         (let*
            (($next-steps (- $steps 1))
             ($nagenda (bounded-agenda-prune $next-steps (run-aggregate-heap $agenda $agg-gid))))
            (search-agenda-heap $next-steps $nagenda))
         (search-agenda-heap $steps $agenda))))

(= (search-agenda-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0)) (search-state $steps $agenda)
      (let*
         (($rest (get_from_heap $agenda $_priority $item)))
         (search-agenda-step $steps $rest $item))))

(= (harvest-base-rate-entry $args $current-pid)
   (let $key (base-rate-aggregate-key $args)
      (if (== $key ()) ()
         (if (== $current-pid ()) ()
            (let $output (proof-output-atom $current-pid)
               (if (= $output (CPU $_fun $_out-args (STV $s $c)))
                  (let ($kbid $pattern $mode) $key
                     (store-computed-base-rate! $kbid $pattern (STV $s $c) $mode))
                  ()))))))

(= (harvest-base-rates)
   (let $_
      (collapse
         (match &aggregate ($_agg-gid $_child $args $_base $_pending $current-pid)
            (harvest-base-rate-entry $args $current-pid)))
      ()))

(= (chainer-run $steps $goal)
   (let*
      (($_clear (foreach-flat remove-all-atoms (&goal &goal_lookup &goal_waiter &aggregate &aggregate_forward_approx &proof &proof_parent &proof_invalidated_epoch &proof_live_cache &goal_live_cache &proof_static_live &proof_superseded)))
       ($_reset (foreach-flat (|-> ($key) (change-state! $key 0)) (bwd_gid bwd_pid bwd_live_epoch)))
       ($root-gid (ensure-goal-at-depth $goal 0))
       ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid))
       ((search-state $_steps-left $_agenda1)
          (once (if (<= $steps 0) (search-state 0 $agenda0) (search-agenda-heap (+ $steps 1) $agenda0))))
       ($_harvest (harvest-base-rates)))
      (chainer-run-result $root-gid (once (goal-results $root-gid)))))

(= (chainer $steps $goal)
   (let (chainer-run-result $_root-gid $results) (chainer-run $steps $goal)
      $results))

(= (chainer-materialize $steps $goal)
   (let (chainer-run-result $root-gid $results) (chainer-run $steps $goal)
      (let $_materialized (materialize-goal-proofs-to-kb $root-gid)
         $results)))
