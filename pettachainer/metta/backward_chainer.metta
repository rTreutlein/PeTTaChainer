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

(=
   (aggregate-child-goal
      (CPU FoldAllCompiled ($kb $pattern $_extractor $_init $_fun $_finish $_tv-mode) $_goalres))
   (let*
      (((compiled-query $child-goal $adds) (mm2compileQuery $kb (: $prf $pattern $tvin)))
       ($_ (inject-compiled-adds $adds)))
      $child-goal))
(=
   (aggregate-child-goal
      (CPU GroupedFoldAllCompiled ($kb $pattern $_group $_extractor $_init $_fun $_finish $_tv-mode) $_goalres))
   (let*
      (((compiled-query $child-goal $adds) (mm2compileQuery $kb (: $prf $pattern $tvin)))
       ($_ (inject-compiled-adds $adds)))
      $child-goal))

(= (aggregate-step-value (extract-value $pattern $value) $child-atom $_child-tv)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))
(= (aggregate-step-value extract-tv $_child-atom $child-tv) $child-tv)
(= (aggregate-step-group-value $pattern $group $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $group))

(= (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv)
   (eval ($fun $acc (aggregate-step-value $extractor $child-atom $child-tv))))

(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc) (reduce (reduce (DistAverageFromSumCount $acc))))
(= (aggregate-finish base-rate $acc) (BaseRateTv $acc))

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

(= (waiter-live? (frontier-waiter $_parent-gid $_bundle $_score $_seen $rev-pids))
   (proof-list-live? $rev-pids))

(= (advance-frontier-waiter-heap $agenda (frontier-waiter $parent-gid $bundle $score $seen $rev-pids) $pid)
   (if (not (waiter-live? (frontier-waiter $parent-gid $bundle $score $seen $rev-pids))) $agenda
      (let*
         ((($pscore $pev) (proof-stats-by-id $pid))
          ($overlap (evidence-sets-overlap? $seen $pev))
          ($next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)))
         (if $overlap $agenda
            (if (== $next-bundle ()) $agenda
               (let $next-score
                  (min-atom ($score $pscore (premises-expected-confidence (copy_term (and-bundle-premises $next-bundle)))))
                  (spawn-frontier-heap $agenda
                     $parent-gid
                     $next-bundle
                     $next-score
                     (list_to_set (append $seen $pev))
                     (cons $pid $rev-pids))))))))

(= (frontier-waiter-step (@ $waiter (head frontier-waiter)) $rest) (cons $waiter $rest))
(= (frontier-waiter-step $_waiter $rest) $rest)

(= (aggregate-waiter-step (aggregate-waiter $agg-gid) $rest) (cons $agg-gid $rest))
(= (aggregate-waiter-step $_waiter $rest) $rest)

(= (spawn-frontier-goal-heap $agenda $score $gid $waiter)
   (let*
      (($_1 (chainer-add-atom &goal_waiter ($gid $waiter)))
       ($agenda1
          (fold-flat (|-> ($acc $pid) (advance-frontier-waiter-heap $acc $waiter $pid))
             $agenda
             (goal-merged-proof-ids $gid)))
       ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
      $nagenda))

(= (spawn-aggregate-goal-heap $agenda $score $agg-gid $goal-view)
   (let*
      (($args (copy_term (let (CPU $_agg-fun $args $_goalres) $goal-view $args)))
       ($child-goal (aggregate-child-goal $goal-view))
       (($depth $_goal $_expanded $_pending) (goal-by-id $agg-gid))
       ($child-gid (ensure-goal-at-depth $child-goal (+ 1 $depth)))
       ($hits (collapse (once (match &aggregate ($agg-gid $_child $_args $_base $_pending1 $_current) true))))
       ($_agg
          (if (== $hits ())
             (chainer-add-atom &aggregate ($agg-gid $child-gid $args $score 0.0 ()))
             ()))
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

(= (aggregate-fold-source-step $agg-gid $acc $pid)
   (if (proof-depends-on-goal-seen? $pid $agg-gid closed-goal ()) $acc (append $acc ($pid))))

(= (aggregate-fold-source-ids $agg-gid $child-gid)
   (fold-flat (aggregate-fold-source-step $agg-gid)
      ()
      (goal-merged-proof-ids $child-gid)))

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
             (($kb $pattern $extractor $init $fun $finish $tv-mode) $args)
             ($result (CPU FoldAllCompiled $args (aggregate-finish $finish $acc)))
             ($commit-ev (if (== $finish base-rate) () $ev)))
            (if (aggregate-snapshot-changed? $current-pid $result $commit-ev)
               (commit-aggregate-snapshot-heap $agenda $agg-gid $result $commit-ev $children)
               $agenda)))))

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

(= (rule-goal-head-view ($goal $parent-gid))
   (let $key (forward-indexable-premise-key $goal)
      (if (== $key ())
         ()
         (match ccls_head_index ($key $rule-id)
            (match rules ($rule-id $goal $args)
               ($args $goal $parent-gid))))))

(= (rule-goal-contextual? $goal)
   (if (= $goal ($_type ($_kbid $ctx $_vars) $_prf $_tv))
      (not (== $ctx MAIN))
      false))

(= (rule-goal-full-view ($goal $parent-gid))
   (match ccls_index ($goal $rule-id)
      (match rules ($rule-id $goal $args)
         ((contextualize-rule-args $goal $args) $goal $parent-gid))))

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

(= (spawn-frontier-heap $agenda $parent-gid $bundle $score $seen $rev-pids)
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
                       $rev-pids))))))))

(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (fold-flat expand-rule-goal-fold
      $agenda
      (collapse (rule-goal-view ($goal $parent-gid)))))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid))
   (let*
      (($expected-score (premises-expected-confidence (copy_term $args)))
       ($bound (rule-marginal-score (goal-current-confidence $parent-gid) $expected-score))
       ($bundle (copy_term (make-and-bundle $goal $args))))
      (spawn-frontier-heap $agenda
         $parent-gid
         $bundle
         $bound
         ()
         ())))

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
      ((($child-gid $args $base-score $pending $current-pid) (aggregate-by-id $agg-gid)))
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

(= (chainer-run $steps $goal)
   (let*
      (($_clear (foreach-flat remove-all-atoms (&goal &goal_lookup &goal_waiter &aggregate &proof &proof_live_cache &goal_live_cache &proof_static_live)))
       ($_reset (foreach-flat (|-> ($key) (change-state! $key 0)) (bwd_gid bwd_pid bwd_live_epoch)))
       ($root-gid (ensure-goal-at-depth $goal 0))
       ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid))
       ((search-state $_steps-left $_agenda1)
          (once (if (<= $steps 0) (search-state 0 $agenda0) (search-agenda-heap (+ $steps 1) $agenda0)))))
      (chainer-run-result $root-gid (once (goal-results $root-gid)))))

(= (chainer $steps $goal)
   (let (chainer-run-result $_root-gid $results) (chainer-run $steps $goal)
      $results))

(= (chainer-materialize $steps $goal)
   (let (chainer-run-result $root-gid $results) (chainer-run $steps $goal)
      (let $_materialized (materialize-goal-proofs-to-kb $root-gid)
         $results)))
