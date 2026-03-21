(= (goal-term-by-id $gid) (match &goal_by_id ($gid $goal) $goal))

(= (next-agid) (next-search-id bwd_agid))

(= (goal-expanded? $gid)
   (not (== (collapse (once (match &goal_expanded ($gid true) true))) ())))

(= (goal-pending-score-of $gid)
   (let $scores (collapse (once (match &goal_pending_score ($gid $score) $score)))
      (if (== $scores ()) 0.0 (car-atom $scores))))

(= (clear-goal-pending-score $gid)
   (progn
      (collapse
         (match &goal_pending_score ($gid $score)
            (remove-atom &goal_pending_score ($gid $score))))
      ()))

(= (proof-goal-by-id $pid) (match &proof_goal ($pid $gid) $gid))

(= (proof-output-term $pid $term)
   (if (= $term ($type ($kbid $_ctx $_vars) $_prf $tv))
      ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)
      $term))

(= (proof-output-atom $pid)
   (case (proof-kind-by-id $pid) (
        ((leaf $term) (proof-output-term $pid $term))
        ((rule $aid $term) (proof-output-term $pid $term))
        ($other (empty)))))

(= (proof-unify-term $pid) (proof-output-atom $pid))

(= (materialize-proof-refs $term)
   (if (= $term (proof-ref $pid)) (materialize-proof-refs (materialize-proof $pid))
      (if (is-expr $term)
         (cons (materialize-proof-refs (car-atom $term))
            (map-flat materialize-proof-refs (cdr-atom $term)))
         $term)))

(= (materialize-proof-atom ($type $kb $prf $tv))
   ($type $kb (materialize-proof-refs $prf) $tv))

(= (materialize-rule-proof $aid $pid-list)
   (case
      (instantiate-and-bundle
         (copy_term (match &and_node ($aid $_parent $_rule $_bound $bundle) $bundle))
         $pid-list) (
        ((and-bundle ($_type $_kb $prf $_tv) $_rest)
           (cons rule-proof
              (cons (materialize-proof-refs (car-atom $prf))
                 (map-flat materialize-proof-refs (cdr-atom $prf)))))
        ($other $other))))

(= (materialize-proof $pid)
   (case (proof-kind-by-id $pid) (
        ((leaf $raw) (if (= $raw ($_type ($_kbid $_ctx $_vars) $prf $_tv)) $prf $raw))
        ((rule $aid $_term)
           (materialize-rule-proof $aid (match &proof_children ($pid $kids) $kids)))
        ($other $other))))

(= (goal-summary-pid $gid)
   (let $hits (collapse (once (match &goal_summary_proof ($gid $pid) $pid)))
      (if (== $hits ()) () (car-atom $hits))))

(= (goal-term-has-type-vars? $goal)
   (if (= $goal ($type ($_kbid $_ctx $_vars) $_prf $_tv))
      (not (== (extract-vars $type) ()))
      false))

(= (goal-has-type-vars? $gid) (goal-term-has-type-vars? (goal-term-by-id $gid)))

(= (rule-expansion-has-id? () $_rule-id) false)
(= (rule-expansion-has-id? (cons ($_args $_goal $_parent-gid $item-rule-id) $rest) $rule-id)
   (or (== $item-rule-id $rule-id) (rule-expansion-has-id? $rest $rule-id)))

(= (rule-expansion-add-unique $acc ($args $goal $parent-gid $rule-id))
   (if (rule-expansion-has-id? $acc $rule-id) $acc
      (cons ($args $goal $parent-gid $rule-id) $acc)))

(= (rule-expansion-list-unique $lst)
   (fold-flat rule-expansion-add-unique () $lst))

(= (goal-result-pids $gid)
   (if (goal-has-type-vars? $gid) (collapse (match &goal_proof ($gid $pid) $pid))
      (let $pid (goal-summary-pid $gid) (if (== $pid ()) () (cons $pid ())))))

(= (goal-open-results-merge $new ()) (cons $new ()))
(= (goal-open-results-merge $new (cons $old $rest))
   (if (goal-key-eq? $new $old) (cons (merge-proof-atoms $old $new) $rest)
      (cons $old (goal-open-results-merge $new $rest))))

(= (goal-open-result-atoms ()) ())
(= (goal-open-result-atoms (cons $pid $rest))
   (goal-open-results-merge (proof-output-atom $pid) (goal-open-result-atoms $rest)))

(= (materialize-proof-atoms ()) ())
(= (materialize-proof-atoms (cons $atom $rest))
   (cons (materialize-proof-atom $atom) (materialize-proof-atoms $rest)))

(= (goal-results $gid)
   (if (goal-has-type-vars? $gid)
      (materialize-proof-atoms (goal-open-result-atoms (goal-result-pids $gid)))
      (let $pid (goal-summary-pid $gid)
         (if (== $pid ()) ()
            (cons (materialize-proof-atom (proof-output-atom $pid)) ())))))

(= (ensure-goal $goal)
   (let $hits
      (collapse
         (once
            (if (= $goal ($type ($kbid $_ctx $_vars) $kbprf $_tv))
               (let $sealed-type (sealed (extract-vars $type) $type)
                  (match &goal_lookup
                     (($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv) $gid)
                     (if
                        (goal-key-eq?
                           ($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv)
                           $goal)
                        $gid
                        (empty))))
               (let $sealed-goal (sealed (extract-vars $goal) $goal)
                  (match &goal_lookup ($sealed-goal $gid)
                     (if (goal-key-eq? $sealed-goal $goal) $gid (empty)))))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
              ($stored-goal (copy_term $goal))
              ($goal-class
                 (if (= $stored-goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) proof
                    direct))
              ($_1 (add-atom &goal_by_id ($gid $stored-goal)))
              ($_2 (add-atom &goal_lookup ($stored-goal $gid)))
              ($_3 (add-atom &goal_class ($gid $goal-class))))
            $gid)
         (car-atom $hits))))

(= (schedule-goal-heap $agenda $score $gid)
   (let*
      (($expanded (goal-expanded? $gid))
        ($current (goal-pending-score-of $gid)))
      (if $expanded $agenda
         (if (>= $current $score) $agenda
            (let*
               (($goal-class (match &goal_class ($gid $class) $class))
                 ($closed-proof-bonus
                    (if (goal-term-has-type-vars? (goal-term-by-id $gid)) 0.0 1.0))
                 ($bonus (if (== $goal-class proof) $closed-proof-bonus 2.0))
                 ($priority (- 0 (+ (* 1000000.0 $score) $bonus)))
                 ($nagenda (add_to_heap $agenda $priority (qitem $score $gid)))
                 ($_clear (clear-goal-pending-score $gid))
                 ($_set (add-atom &goal_pending_score ($gid $score))))
               $nagenda)))))

(= (specialized-runtime-cpu-fun? $fun)
   (is-member $fun
      (()
         FoldAllFormulaCompiled
         FoldAllTVFormulaCompiled
         FoldAllTVRuntimeFormula
         DistAverageFormula
         Map2DistRuntimeFormula)))

(= (compiled-query-goal-head $compiled-query)
   (case (car-atom $compiled-query) (
        ((goal $query) $query)
        ($other (notsupported compiled-query-goal-head $compiled-query $other)))))

(= (compiled-query-adds $compiled-query) (cdr-atom $compiled-query))

(= (aggregate-runtime-goal? $goal)
   (case $goal (
        ((CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $_fun) $_goalres)
           true)
        (((CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $_fun) $_goalres)
              ($_kbid $_ctx $_vars)
              $_prf
              $_tv)
           true)
        ((CPU FoldAllTVFormulaCompiled ($_compiled-query $_init $_fun) $_goalres)
           true)
        (((CPU FoldAllTVFormulaCompiled ($_compiled-query $_init $_fun) $_goalres)
              ($_kbid $_ctx $_vars)
              $_prf
              $_tv)
           true)
        ((CPU FoldAllTVRuntimeFormula ($_kb $_pattern $_init $_fun) $_goalres)
           true)
        (((CPU FoldAllTVRuntimeFormula ($_kb $_pattern $_init $_fun) $_goalres)
              ($_kbid $_ctx $_vars)
              $_prf
              $_tv)
           true)
        ((CPU DistAverageFormula ($_kb $_pattern) $_goalres)
           true)
        (((CPU DistAverageFormula ($_kb $_pattern) $_goalres) ($_kbid $_ctx $_vars)
              $_prf
              $_tv)
           true)
        ($other false))))

(= 
   (aggregate-goal-child-goal
      (CPU FoldAllFormulaCompiled ($compiled-query $_pattern $_value $_init $_fun) $_goalres))
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(= 
   (aggregate-goal-child-goal
      ((CPU FoldAllFormulaCompiled ($compiled-query $_pattern $_value $_init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(= 
   (aggregate-goal-child-goal
      (CPU FoldAllTVFormulaCompiled ($compiled-query $_init $_fun) $_goalres))
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(= 
   (aggregate-goal-child-goal
      ((CPU FoldAllTVFormulaCompiled ($compiled-query $_init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(=
   (aggregate-goal-child-goal
      (CPU FoldAllTVRuntimeFormula ($kb $pattern $_init $_fun) $_goalres))
   (let ($rkbid $rctx $rvars) (runtime-kctx $kb)
      (let $qpattern (runtime-query-pattern $pattern)
         ($qpattern ($rkbid $rctx $rvars) $child-prf $child-tv))))

(=
   (aggregate-goal-child-goal
      (CPU DistAverageFormula ($kb $pattern) $_goalres))
   (let ($rkbid $rctx $rvars) (runtime-kctx $kb)
      (let $qpattern (runtime-query-pattern $pattern)
         ($qpattern ($rkbid $rctx $rvars) $child-prf $child-tv))))

(=
   (aggregate-goal-child-goal
      ((CPU FoldAllTVRuntimeFormula ($kb $pattern $_init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   (let ($rkbid $rctx $rvars) (runtime-kctx $kb)
      (let $qpattern (runtime-query-pattern $pattern)
         ($qpattern ($rkbid $rctx $rvars) $child-prf $child-tv))))
(=
   (aggregate-goal-child-goal
      ((CPU DistAverageFormula ($kb $pattern) $_goalres) ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   (let ($rkbid $rctx $rvars) (runtime-kctx $kb)
      (let $qpattern (runtime-query-pattern $pattern)
         ($qpattern ($rkbid $rctx $rvars) $child-prf $child-tv))))

(=
   (aggregate-goal-init-acc
      (CPU FoldAllTVRuntimeFormula ($_kb $_pattern $init $_fun) $_goalres))
   $init)

(=
   (aggregate-goal-init-acc
      (CPU DistAverageFormula ($_kb $_pattern) $_goalres))
   (SumCount (PointMass 0.0) 0))

(=
   (aggregate-goal-init-acc
      ((CPU FoldAllTVRuntimeFormula ($_kb $_pattern $init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   $init)
(=
   (aggregate-goal-init-acc
      ((CPU DistAverageFormula ($_kb $_pattern) $_goalres) ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   (SumCount (PointMass 0.0) 0))

(=
   (aggregate-goal-init-acc
      (CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $init $_fun) $_goalres))
   $init)

(=
   (aggregate-goal-init-acc
      ((CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   $init)

(=
   (aggregate-goal-init-acc
      (CPU FoldAllTVFormulaCompiled ($_compiled-query $init $_fun) $_goalres))
   $init)

(=
   (aggregate-goal-init-acc
      ((CPU FoldAllTVFormulaCompiled ($_compiled-query $init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv))
   $init)

(=
   (aggregate-goal-step-value
      (CPU FoldAllFormulaCompiled ($_compiled-query $pattern $value $_init $_fun) $_goalres)
      $child-atom)
   (let ($pattern ($_kbid $_ctx $_vars) $_prf $_tv) (copy_term $child-atom) $value))

(=
   (aggregate-goal-step-value
      ((CPU FoldAllFormulaCompiled ($_compiled-query $pattern $value $_init $_fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv)
      $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))

(=
   (aggregate-goal-step-acc
      (CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $fun) $_goalres)
      $acc
      $child-atom
      $_child-tv)
   (reduce
      (reduce
         ($fun
            $acc
            (aggregate-goal-step-value
               (CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $fun)
                  $_goalres)
               $child-atom)))))
(=
   (aggregate-goal-step-acc
      ((CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv)
      $acc
      $child-atom
      $_child-tv)
   (reduce
      (reduce
         ($fun
            $acc
            (aggregate-goal-step-value
               ((CPU FoldAllFormulaCompiled ($_compiled-query $_pattern $_value $_init $fun)
                   $_goalres)
                  ($_kbid $_ctx $_vars)
                  $_prf
                  $_tv)
               $child-atom)))))
(=
   (aggregate-goal-step-acc
      (CPU FoldAllTVFormulaCompiled ($_compiled-query $_init $fun) $_goalres)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce ($fun $acc $child-tv))))
(=
   (aggregate-goal-step-acc
      ((CPU FoldAllTVFormulaCompiled ($_compiled-query $_init $fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce ($fun $acc $child-tv))))
(=
   (aggregate-goal-step-acc
      (CPU FoldAllTVRuntimeFormula ($_kb $_pattern $_init $fun) $_goalres)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce ($fun $acc $child-tv))))

(=
   (aggregate-goal-step-acc
      (CPU DistAverageFormula ($_kb $_pattern) $_goalres)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce (DistSumCountAcc $acc $child-tv))))

(=
   (aggregate-goal-step-acc
      ((CPU FoldAllTVRuntimeFormula ($_kb $_pattern $_init $fun) $_goalres)
         ($_kbid $_ctx $_vars)
         $_prf
         $_tv)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce ($fun $acc $child-tv))))
(=
   (aggregate-goal-step-acc
      ((CPU DistAverageFormula ($_kb $_pattern) $_goalres) ($_kbid $_ctx $_vars)
         $_prf
         $_tv)
      $acc
      $_child-atom
      $child-tv)
   (reduce (reduce (DistSumCountAcc $acc $child-tv))))

(=
   (aggregate-goal-result
      (CPU FoldAllFormulaCompiled ($compiled-query $pattern $value $init $fun) $_goalres)
      $acc)
   (CPU FoldAllFormulaCompiled ($compiled-query $pattern $value $init $fun) $acc))

(= 
   (aggregate-goal-result
      ((CPU FoldAllFormulaCompiled ($compiled-query $pattern $value $init $fun) $_goalres)
         ($kbid $ctx $vars)
         $prf
         $_tv)
      $acc)
   ((CPU FoldAllFormulaCompiled ($compiled-query $pattern $value $init $fun) $acc)
      ($kbid $ctx $vars)
      cpu
      (cpu-premise-tv FoldAllFormulaCompiled ($compiled-query $pattern $value $init $fun) $acc)))

(=
   (aggregate-goal-result
      (CPU FoldAllTVFormulaCompiled ($compiled-query $init $fun) $_goalres)
      $acc)
   (CPU FoldAllTVFormulaCompiled ($compiled-query $init $fun) $acc))

(= 
   (aggregate-goal-result
      ((CPU FoldAllTVFormulaCompiled ($compiled-query $init $fun) $_goalres)
         ($kbid $ctx $vars)
         $prf
         $_tv)
      $acc)
   ((CPU FoldAllTVFormulaCompiled ($compiled-query $init $fun) $acc)
      ($kbid $ctx $vars)
      cpu
      (cpu-premise-tv FoldAllTVFormulaCompiled ($compiled-query $init $fun) $acc)))

(=
   (aggregate-goal-result
      (CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $_goalres)
      $acc)
   (CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $acc))

(=
   (aggregate-goal-result
      (CPU DistAverageFormula ($kb $pattern) $_goalres)
      $acc)
   (let $out (reduce (reduce (DistAverageFromSumCount $acc)))
      (CPU DistAverageFormula ($kb $pattern) $out)))

(= 
   (aggregate-goal-result
      ((CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $_goalres)
         ($kbid $ctx $vars)
         $prf
         $_tv)
      $acc)
   ((CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $acc) ($kbid $ctx $vars)
      cpu
      $acc))
(= 
   (aggregate-goal-result
      ((CPU DistAverageFormula ($kb $pattern) $_goalres) ($kbid $ctx $vars) $prf $_tv)
      $acc)
   (let $out (reduce (reduce (DistAverageFromSumCount $acc)))
      ((CPU DistAverageFormula ($kb $pattern) $out) ($kbid $ctx $vars) cpu $out)))

(= (aggregate-state-by-id $agid)
   (match &aggregate_state ($agid $gid $child-gid $goal $acc $ev)
      (aggregate-state $gid $child-gid $goal $acc $ev)))

(= (set-aggregate-state $agid $gid $child-gid $goal $acc $ev)
   (progn
      (collapse
         (match &aggregate_state
            ($agid $old-gid $old-child-gid $old-goal $old-acc $old-ev)
            (remove-atom &aggregate_state
               ($agid $old-gid $old-child-gid $old-goal $old-acc $old-ev))))
      (add-atom &aggregate_state ($agid $gid $child-gid $goal $acc $ev))))

(= (aggregate-seen-proof? $agid $pid)
   (not (== (collapse (once (match &aggregate_seen ($agid $pid) true))) ())))

(= (aggregate-finalized? $agid)
   (not (== (collapse (once (match &aggregate_finalized ($agid true) true))) ())))

(= (advance-aggregate-heap $agenda $agid $pid)
   (if (aggregate-seen-proof? $agid $pid) $agenda
      (let*
         (((aggregate-state $gid $child-gid $goal $acc $ev)
              (aggregate-state-by-id $agid))
           ($child-atom (proof-output-atom $pid))
           (($_pscore $pev) (proof-stats-by-id $pid))
           ($nacc (aggregate-goal-step-acc $goal $acc $child-atom (proof-tv-by-id $pid)))
           ($nev (list_to_set (list-append $ev $pev)))
           ($_1 (set-aggregate-state $agid $gid $child-gid $goal $nacc $nev))
           ($_2 (add-atom &aggregate_seen ($agid $pid))))
         $agenda)))

(= (attach-existing-aggregate-proofs-heap $agenda $agid $child-gid)
   (fold-flat (|-> ($acc $pid) (advance-aggregate-heap $acc $agid $pid))
      $agenda
      (collapse (match &goal_proof ($child-gid $pid) $pid))))

(= (spawn-aggregate-goal-heap $agenda $score $gid $goal)
   (let*
      (($child-goal (aggregate-goal-child-goal $goal))
        ($child-gid (ensure-goal $child-goal))
        ($agid (next-agid))
        ($stored-goal (copy_term $goal))
        ($_1
           (set-aggregate-state $agid
              $gid
              $child-gid
              $stored-goal
              (aggregate-goal-init-acc $goal)
              ()))
        ($_2 (add-atom &aggregate_waiter ($child-gid $agid)))
        ($agenda1 (attach-existing-aggregate-proofs-heap $agenda $agid $child-gid))
        ($nagenda (schedule-goal-heap $agenda1 $score $child-gid)))
      $nagenda))

(= (finalize-aggregate-heap $agenda $agid)
   (if (aggregate-finalized? $agid) $agenda
      (let*
         (((aggregate-state $gid $child-gid $goal $acc $ev)
              (aggregate-state-by-id $agid))
           ($dep-agids
              (collapse
                 (match &aggregate_state
                    ($dep-agid $child-gid $_dep-child $_dep-goal $_dep-acc $_dep-ev)
                    $dep-agid)))
           ($agenda1 (fold-flat finalize-aggregate-heap $agenda $dep-agids))
           ($_1 (add-atom &aggregate_finalized ($agid true)))
           ($result (aggregate-goal-result $goal $acc)))
         (commit-proof-candidate-heap $agenda1
            $gid
            (classify-goal-proof-candidate $gid $ev (term-confidence $result))
            (leaf-result-candidate $result $ev)))))

(= (finalize-all-aggregates-heap $agenda)
   (fold-flat finalize-aggregate-heap
      $agenda
      (collapse
         (match &aggregate_state ($agid $_gid $_child-gid $_goal $_acc $_ev)
            $agid))))

(= (runtime-kctx $kb)
   (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil)) ($kb MAIN Nil)))

(= (runtime-query-pattern $pattern) (map-nested2 toQuery $pattern))

(= (runtime-match-pattern $qpattern)
   (if (contains-hash? $qpattern) (map-nested unwrap $qpattern) $qpattern))

(= (runtime-direct-match-results $steps $kb $type)
   (let ($rkbid $rctx $rvars) (runtime-kctx $kb)
      (let $qtype (runtime-query-pattern $type)
         (direct-goal-results $steps ($qtype ($rkbid $rctx $rvars) $prf $tv)))))

(= (direct-goal-query-term $goal)
   (if (= $goal ($type ($kbid $_ctx $_vars) $prf $tv))
      (let $qtype
         (if (and (is-expr $type) (contains-hash? $type)) (map-nested unwrap $type)
            $type)
         ($qtype ($kbid $_ctx $_vars) $prf $tv))
      $goal))

(= (direct-goal-fact-match $goal $candidate)
   (let $goal-copy (copy_term $goal) (if (= $goal-copy $candidate) $candidate (empty))))

(=
   (direct-goal-results $steps
      ((CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $_goalres)
         ($kbid $ctx $vars)
         $prf
         $_tv))
   (let*
      (($qpattern (runtime-query-pattern $pattern))
        ($out (reduce (reduce (FoldAllTVRuntimeNoStepsQuery $kb $qpattern $init $fun)))))
      (superpose (
           ((CPU FoldAllTVRuntimeFormula ($kb $pattern $init $fun) $out)
              ($kbid $ctx $vars)
              $prf
              $out)))))
(=
   (direct-goal-results $steps
      ((CPU DistAverageFormula ($kb $pattern) $_goalres) ($kbid $ctx $vars) $prf $_tv))
   (let*
      (($qpattern (runtime-query-pattern $pattern))
        ($sumcount
           (FoldAllTVRuntimeNoStepsQuery $kb
              $qpattern
              (SumCount (PointMass 0.0) 0)
              DistSumCountAcc))
        ($out (reduce (reduce (DistAverageFromSumCount $sumcount)))))
      (superpose (
           ((CPU DistAverageFormula ($kb $pattern) $out) ($kbid $ctx $vars) $prf $out)))))
(=
   (direct-goal-results $steps
      ((CPU Map2DistRuntimeFormula ($kb $fun $a $b) $_goalres) ($kbid $ctx $vars)
         $prf
         $_tv))
   (let ($_a ($akbid $actx $avars) $prfa $tva)
      (runtime-direct-match-results $steps $kb $a)
      (let ($_b ($bkbid $bctx $bvars) $prfb $tvb)
         (runtime-direct-match-results $steps $kb $b)
         (let $out (reduce (reduce (DistMap2Formula $fun $tva $tvb)))
            (superpose (
                 ((CPU Map2DistRuntimeFormula ($kb $fun $a $b) $out) ($kbid $ctx $vars)
                    $prf
                    $out)))))))
(=
   (direct-goal-results $steps
      ((CPU $fun $args $_goalres) ($kbid $ctx $vars) $prf $_tv))
   (if (specialized-runtime-cpu-fun? $fun) (empty)
      (let $res (cpu-call $steps $fun $args)
         (superpose (((CPU $fun $args $res) ($kbid $ctx $vars) $prf $res))))))
(= (direct-goal-results $steps (CPU $fun $args $_res))
   (superpose ((CPU $fun $args (cpu-call $steps $fun $args)))))
(= (direct-goal-results $steps $goal)
   (let $query-goal (direct-goal-query-term $goal)
      (match &kb $candidate
         (direct-goal-fact-match $query-goal $candidate))))

(= (leaf-evidence-for-result $result)
   (if (= $result ($type ($kbid $_ctx $_vars) $prf $_tv))
      (if (contains-hash? $type) () (cons (fact-ev ($kbid $_ctx $_vars) $prf $type) ()))
      ()))

(= (proof-overlap-dominates-score? $old-ev $old-score $new-ev $new-score)
   (and (evidence-sets-overlap? $old-ev $new-ev)
      (or (> $old-score $new-score)
         (and (== $old-score $new-score) (evidence-subset? $new-ev $old-ev)))))

(= (goal-proof-candidate-step $ev $score false $_oldpid) false)
(= (goal-proof-candidate-step $ev $score true $oldpid)
   (let ($old-score $old-ev) (proof-stats-by-id $oldpid)
      (if (proof-overlap-dominates-score? $old-ev $old-score $ev $score) false true)))

(= (classify-goal-proof-candidate $gid $ev $score)
   (fold-flat (goal-proof-candidate-step $ev $score)
      true
      (collapse (match &goal_proof ($gid $oldpid) $oldpid))))

(= (store-proof-tv $pid no-tv) ())
(= (store-proof-tv $pid (with-tv $tv)) (add-atom &proof_tv ($pid $tv)))

(= (store-proof-candidate $gid (proof-candidate $kind $tv-state $score $ev $children))
   (let*
      (($pid (next-pid))
        ($_1 (add-atom &proof_goal ($pid $gid)))
        ($_2 (add-atom &proof_kind ($pid $kind)))
        ($_3 (store-proof-tv $pid $tv-state))
        ($_4 (add-atom &proof_stats ($pid $score $ev)))
        ($_5 (add-atom &proof_children ($pid $children))))
      $pid))

(= (clear-goal-summary-proof $gid)
   (collapse
      (match &goal_summary_proof ($gid $pid)
         (remove-atom &goal_summary_proof ($gid $pid)))))

(= (set-goal-summary-proof $gid $pid)
   (progn (clear-goal-summary-proof $gid) (add-atom &goal_summary_proof ($gid $pid))))

(= (proof-atom-candidate ($type $kb $prf $tv) $ev)
   (proof-candidate (leaf ($type $kb $prf $tv))
      (with-tv $tv)
      (term-confidence ($type $kb $prf $tv))
      $ev
      ()))

(= (leaf-result-candidate $result $ev)
   (if (= $result ($type $_kb $_prf $_tv))
      (proof-atom-candidate $result $ev)
      (proof-candidate (leaf $result) no-tv (term-confidence $result) $ev ())))

(= (proof-depends-on-goal-seen? $pid $gid $seen-pids)
   (if (is-member $pid $seen-pids) false
      (or (== (proof-goal-by-id $pid) $gid)
         (fold-flat
            (|-> ($acc $child-pid)
               (or $acc
                  (proof-depends-on-goal-seen? $child-pid $gid (cons $pid $seen-pids))))
            false
            (match &proof_children ($pid $kids)
               $kids)))))

(= (proof-depends-on-goal? $pid $gid) (proof-depends-on-goal-seen? $pid $gid ()))

(= (candidate-is-cyclic? $gid ()) false)
(= (candidate-is-cyclic? $gid (cons $pid $pids))
   (or (proof-depends-on-goal? $pid $gid) (candidate-is-cyclic? $gid $pids)))

(= (goal-summary-candidate $gid $pids)
   (let*
      (($seed (proof-output-atom (car-atom $pids)))
        ($merged
           (fold-flat
              (|-> ($goal $pid) (merge-proof-atoms $goal (proof-output-atom $pid)))
              $seed
              (cdr-atom $pids)))
        ($ev (proof-atom-evidence-set $merged)))
      (proof-atom-candidate $merged $ev)))

(= (refresh-goal-summary-proof $gid)
   (let $pids (collapse (match &goal_proof ($gid $pid) $pid))
      (if (== $pids ()) (progn (clear-goal-summary-proof $gid) ())
         (if (== (cdr-atom $pids) ())
            (let $pid (car-atom $pids) (progn (set-goal-summary-proof $gid $pid) $pid))
            (let $pid (store-proof-candidate $gid (goal-summary-candidate $gid $pids))
               (progn (set-goal-summary-proof $gid $pid) $pid))))))

(=
   (commit-proof-candidate-heap $agenda
      $gid
      $accepted
      (proof-candidate $kind $tv-state $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $children) $agenda
         (let $pid
            (store-proof-candidate $gid
               (proof-candidate $kind $tv-state $score $ev $children))
            (progn
               (add-atom &goal_proof ($gid $pid))
               ($_summary-pid (refresh-goal-summary-proof $gid))
               (let*
                  (($agenda1
                       (fold-flat
                          (|-> ($acc $fid) (advance-frontier-heap $acc $fid $pid))
                          $agenda
                          (collapse (match &goal_waiter ($gid $fid) $fid))))
                    ($agenda2
                       (fold-flat
                          (|-> ($acc $agid) (advance-aggregate-heap $acc $agid $pid))
                          $agenda1
                          (collapse (match &aggregate_waiter ($gid $agid) $agid)))))
                  $agenda2))))))

(=
   (commit-proof-candidate $gid
      $accepted
      (proof-candidate $kind $tv-state $score $ev $children))
   (if (== $accepted false) ()
      (let $_
         (commit-proof-candidate-heap (empty_heap)
            $gid
            $accepted
            (proof-candidate $kind $tv-state $score $ev $children))
         ())))

(= (attach-existing-goal-proofs-heap $agenda $fid $gid)
   (fold-flat (|-> ($acc $pid) (advance-frontier-heap $acc $fid $pid))
      $agenda
      (collapse (match &goal_proof ($gid $pid) $pid))))

(= (expand-direct-goal-result-heap $agenda $gid $result)
   (let*
      (($score (term-confidence $result))
        ($ev (leaf-evidence-for-result $result))
        ($tv-state
           (if (= $result ($_type ($_kbid $_ctx $_vars) $prf $tv)) (with-tv $tv) no-tv)))
      (commit-proof-candidate-heap $agenda
         $gid
         (classify-goal-proof-candidate $gid $ev $score)
         (proof-candidate (leaf $result) $tv-state $score $ev ()))))

(= (direct-goal-results-exact-hit? $goal ()) false)
(= (direct-goal-results-exact-hit? $goal (cons $result $rest))
   (or (goal-key-eq? $goal $result) (direct-goal-results-exact-hit? $goal $rest)))

(= (expand-direct-goal-results-heap $agenda $gid ()) $agenda)
(= (expand-direct-goal-results-heap $agenda $gid (cons $result $rest))
   (expand-direct-goal-results-heap
      (expand-direct-goal-result-heap $agenda $gid $result)
      $gid
      $rest))

(= (instantiated-bundle-goal $aid $pid-list)
   (case
      (instantiate-and-bundle
         (copy_term (match &and_node ($aid $_parent $_rule $_bound $bundle) $bundle))
         $pid-list) (
        ((and-bundle $goal $_rest) $goal)
        ($other $other))))

(=
   (build-parent-proof-heap $agenda
      $parent-gid
      $aid
      (and-bundle $_goal ())
      $score
      $ev
      $pid-list)
   (let*
      (($goal (instantiated-bundle-goal $aid $pid-list))
        (($_type ($_kbid $_ctx $_vars) $_prf $tv) $goal))
      (commit-proof-candidate-heap $agenda
         $parent-gid
         (classify-goal-proof-candidate $parent-gid $ev $score)
         (proof-candidate (rule $aid $goal) (with-tv $tv) $score $ev $pid-list))))

(= (spawn-frontier-heap $agenda $parent-gid $aid $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ())
           (build-parent-proof-heap $agenda
              $parent-gid
              $aid
              $bundle
              $score
              $seen
              (list-reverse $rev-pids)))
        ((and-bundle $_goal (cons $prem $_rest))
           (let*
              (($gid (ensure-goal $prem))
                ($fid (next-fid))
                ($stored-bundle (copy_term $bundle)))
              (let*
                 (($_1
                      (add-atom &frontier
                         ($fid $parent-gid $aid $stored-bundle $score $seen $rev-pids)))
                   ($_2 (add-atom &goal_waiter ($gid $fid)))
                   ($agenda1 (attach-existing-goal-proofs-heap $agenda $fid $gid))
                   ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
                 $nagenda))))))

(= (frontier-state-by-id $fid)
   (match &frontier ($fid $parent-gid $aid $bundle $score $seen $rev-pids)
      (frontier-state $parent-gid $aid $bundle $score $seen $rev-pids)))

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-unify-term $pid)) (and-bundle $goal $rest) ()))

(= (advance-frontier-heap $agenda $fid $pid)
   (let*
      (((frontier-state $parent-gid $aid $bundle $score $seen $rev-pids)
           (frontier-state-by-id $fid))
        (($pscore $pev) (proof-stats-by-id $pid))
        ($overlap (evidence-sets-overlap? $seen $pev))
        ($next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)))
      (if $overlap $agenda
         (if (== $next-bundle ()) $agenda
            (spawn-frontier-heap $agenda
               $parent-gid
               $aid
               $next-bundle
               (min $score $pscore)
               (list_to_set (list-append $seen $pev))
               (cons $pid $rev-pids))))))

(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (let*
      (($exact
           (collapse
              (match ccls_index ($goal $rule-id)
                 (match rules ($rule-id $goal $args)
                    ($args $goal $parent-gid $rule-id)))))
        ($lst (rule-expansion-list-unique $exact)))
      (fold-flat expand-rule-goal-fold $agenda $lst)))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid $rule-id))
   (let*
      (($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args)))
        ($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier-heap $agenda $parent-gid $aid $bundle $bound () ())))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let $goal (goal-term-by-id $gid)
      (if (aggregate-runtime-goal? $goal)
         (let*
            (($_expand (add-atom &goal_expanded ($gid true)))
              ($nagenda (spawn-aggregate-goal-heap $agenda $score $gid $goal)))
            $nagenda)
         (let*
            (($_expand (add-atom &goal_expanded ($gid true)))
              ($results (collapse (direct-goal-results $steps $goal)))
              ($agenda1 (expand-direct-goal-results-heap $agenda $gid $results))
              ($nagenda
                 (if (direct-goal-results-exact-hit? $goal $results) $agenda1
                    (expand-rule-goal-heap $agenda1 $gid $goal))))
            $nagenda))))

(= (search-goals-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0)) (search-state $steps $agenda)
      (let*
         (($rest (get_from_heap $agenda $_priority $item))
           ((qitem $score $gid) $item))
         (if (and (not (goal-expanded? $gid)) (== (goal-pending-score-of $gid) $score))
            (let*
               (($_clear (clear-goal-pending-score $gid))
                 ($nagenda (expand-goal-heap $rest $steps $score $gid)))
               (search-goals-heap (- $steps 1) $nagenda))
            (search-goals-heap $steps $rest)))))

(= (instantiate-and-bundle (and-bundle $goal ()) ()) (and-bundle $goal ()))
(= (instantiate-and-bundle (and-bundle $goal (cons $prem $rest)) (cons $pid $pids))
   (if (= $prem (proof-unify-term $pid))
      (instantiate-and-bundle (and-bundle $goal $rest) $pids)
      (empty)))

(= (clear-backward-state)
   (let*
      (($_gbyidclear (remove-all-atoms &goal_by_id))
        ($_glookupclear (remove-all-atoms &goal_lookup))
        ($_gclassclear (remove-all-atoms &goal_class))
        ($_gexpandedclear (remove-all-atoms &goal_expanded))
        ($_gpendclear (remove-all-atoms &goal_pending_score))
        ($_gwaitclear (remove-all-atoms &goal_waiter))
        ($_andclear (remove-all-atoms &and_node))
        ($_frontierclear (remove-all-atoms &frontier))
        ($_aggstateclear (remove-all-atoms &aggregate_state))
        ($_aggwaitclear (remove-all-atoms &aggregate_waiter))
        ($_aggseenclear (remove-all-atoms &aggregate_seen))
        ($_aggfinalclear (remove-all-atoms &aggregate_finalized))
        ($_gproofclear (remove-all-atoms &goal_proof))
        ($_gsummaryclear (remove-all-atoms &goal_summary_proof))
        ($_pgoalclear (remove-all-atoms &proof_goal))
        ($_pstatsclear (remove-all-atoms &proof_stats))
        ($_pkindclear (remove-all-atoms &proof_kind))
        ($_ptvclear (remove-all-atoms &proof_tv))
        ($_pchildclear (remove-all-atoms &proof_children)))
      ()))

(= (chainer $steps $goal)
   (let*
      (($_clear (clear-backward-state))
        ($_gidreset (change-state! bwd_gid 0))
        ($_aidreset (change-state! bwd_aid 0))
        ($_agidreset (change-state! bwd_agid 0))
        ($_fidreset (change-state! bwd_fid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($root-gid (ensure-goal $goal))
        ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid)))
      (let (search-state $search-steps-left $agenda1)
         (if (<= $steps 0) (search-state 0 $agenda0)
            (search-goals-heap (+ $steps 1) $agenda0))
         (let $agenda2 (finalize-all-aggregates-heap $agenda1)
            (let (search-state $_search-steps-left2 $_agenda3)
               (if (<= $search-steps-left 0) (search-state $search-steps-left $agenda2)
                  (search-goals-heap $search-steps-left $agenda2))
               (goal-results $root-gid))))))

(= (unwrap $x) (if (== $x #) $any $x))

(= (contains-hash? $x)
   (if (== $x #) true (if (is-expr $x) (contains-hash-expr $x) false)))

(= (contains-hash-expr $expr)
   (or (== (car-atom $expr) #) (contains-hash-list (cdr-atom $expr))))

(= (contains-hash-list ()) false)
(= (contains-hash-list (cons $head $tail))
   (or (contains-hash? $head) (contains-hash-list $tail)))

(= (cpu-call $steps $fun $args)
   (reduce
      (reduce
         (if
           (is-member $fun
               (() FoldAllFormulaCompiled
                  FoldAllTVFormulaCompiled
                  FoldAllTVRuntimeFormula
                  DistAverageFormula
                  Map2DistRuntimeFormula))
            (cons $fun (cons $steps $args))
            (cons $fun $args)))))

(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (foldall-eval $fun (reduce (reduce (cons $fun (cons $acc (cons $elem ()))))) $tail))

(= (extract-proof-tvs ()) ())
(= (extract-proof-tvs (cons ($_type ($_kbid $_ctx $_vars) $_prf $tv) $tail))
   (cons $tv (extract-proof-tvs $tail)))
(= (extract-proof-tvs (cons $_head $tail)) (extract-proof-tvs $tail))

(= (temp-query-rule-id $id) (temp_query_rule $id))

(= (temp-query-has-rule-sig? $args $ccls)
   (not
      (==
         (collapse
            (once (match &temp_query_rule_sig ($ccls $args) true)))
         ())))

(= (temp-query-has-expr? $expr)
   (not (== (collapse (once (match &temp_query_expr_sig $expr true))) ())))

(= (temp-add-prem $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) ()
            (progn
               (add-atom prem_index ($key $prem $id $idx))
               (add-atom &temp_query_prem_index ($key $prem $id $idx))))
         (+ $idx 1))))

(= (temp-add-to-kb $expr)
      (if (= $expr (rules ($args |- $ccls)))
      (if (temp-query-has-rule-sig? $args $ccls) ()
         (let*
            (($raw-id (nextid))
              ($id (temp-query-rule-id $raw-id))
              ($_1 (fold-flat (temp-add-prem $id) 0 $args))
              ($_2 (add-atom ccls_index ($ccls $id)))
              ($_2b (add-atom &temp_query_ccls_index ($ccls $id)))
              ($_3 (add-atom rules ($id $ccls $args)))
              ($_4 (add-atom &temp_query_rule_atom ($id $ccls $args)))
              ($_5 (add-atom &temp_query_rule_sig ($ccls $args))))
            ()))
      (if (temp-query-has-expr? $expr) ()
         (progn
            (add-atom &kb $expr)
            (add-atom &temp_query_expr $expr)
            (add-atom &temp_query_expr_sig $expr)))))

(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_expr $expr
            (progn (remove-atom &kb $expr) (remove-atom &temp_query_expr $expr))))
      (collapse
         (match &temp_query_prem_index ($key $prem $id $idx)
            (progn
               (remove-atom prem_index ($key $prem $id $idx))
               (remove-atom &temp_query_prem_index ($key $prem $id $idx)))))
      (collapse
         (match &temp_query_ccls_index ($key $id)
            (progn
               (remove-atom ccls_index ($key $id))
               (remove-atom &temp_query_ccls_index ($key $id)))))
      (collapse
         (match &temp_query_rule_atom ($id $ccls $args)
            (progn
               (remove-atom rules ($id $ccls $args))
               (remove-atom &temp_query_rule_atom ($id $ccls $args)))))
      (remove-all-atoms &temp_query_rule_sig)
      (remove-all-atoms &temp_query_expr_sig)
      ()))

(= (inject-compiled-adds $adds) (if (= $adds ()) $_ (foreach-flat temp-add-to-kb $adds)))

(= (run-compiled-query $steps $compiled-query)
   (let*
      (($head (car-atom $compiled-query))
        ($adds (cdr-atom $compiled-query))
        ($_clear-temp-before (clear-temp-query-adds))
        ($query
           (case $head (
                ((goal $query) $query)
                ($other (notsupported run-compiled-query $compiled-query $other)))))
        ($_ (inject-compiled-adds $adds))
        ($results (chainer $steps $query))
        ($_clear-temp-after (clear-temp-query-adds)))
      $results))

(= (run-compiled-query-output $steps $compiled-query)
   (let $results (run-compiled-query $steps $compiled-query)
      (let $eres (map-flat externalize-proof-structure $results)
         (pretty (superpose $eres)))))

(= (query $steps $kb $stmt)
   (let*
      (($compiled-query
           (map-flat internalize-proof-structure (collapse (mm2compileQuery $kb $stmt))))
        ($head (car-atom $compiled-query))
        ($adds (cdr-atom $compiled-query))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($goal
           (case $head (
                ((goal $query) $query)
                ($other (notsupported query $steps $kb $stmt $compiled-query $other)))))
        ($results (chainer $steps $goal))
        ($_clear-temp-after (clear-temp-query-adds))
        ($eres (map-flat externalize-proof-structure $results)))
      (pretty (superpose $eres))))

(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (foldall-eval $fun
      $init
      (collapse
         (let ($pattern ($kbid $_ctx $_vars) $prf $tvin)
            (run-compiled-query $steps $compiled-query)
            $value))))

(= (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun)
   (foldall-eval $fun
      $init
      (extract-proof-tvs (run-compiled-query $steps $compiled-query))))

(= (FoldAllTVRuntimeNoStepsQuery $kb $qpattern $init $fun)
   (let*
      (($kctx
           (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil))
              ($kb MAIN Nil)))
        ($upattern (runtime-match-pattern $qpattern))
        ($matches (collapse (match &kb ($upattern $kctx $prf $ptv) $ptv))))
      (foldall-eval $fun $init $matches)))

(= (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun)
   (FoldAllTVRuntimeNoStepsQuery $kb (runtime-query-pattern $pattern) $init $fun))

(= (Map2DistRuntimeFormula $steps $kb $fun $a $b)
   (let ($_a ($akbid $actx $avars) $prfa $tva)
      (runtime-direct-match-results $steps $kb $a)
      (let ($_b ($bkbid $bctx $bvars) $prfb $tvb)
         (runtime-direct-match-results $steps $kb $b)
         (DistMap2Formula $fun $tva $tvb))))

(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun)
   (FoldAllTVRuntimeNoStepsQuery $kb (runtime-query-pattern $pattern) $init $fun))
