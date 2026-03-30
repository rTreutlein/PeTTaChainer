(= (goal-term-by-id $gid) (match &goal_by_id ($gid $goal) $goal))

(= (next-agid) (next-search-id bwd_agid))

(= (first-or () $default) $default)
(= (first-or (cons $x $_rest) $_default) $x)

(= (one-or-empty $x) (if (== $x ()) () ($x)))

(= (nonempty? ()) false)
(= (nonempty? (cons $_ $_rest)) true)

(= (clear-spaces ()) ())
(= (clear-spaces (cons $space $rest))
   (let $_ (remove-all-atoms $space) (clear-spaces $rest)))

(= (result-tv-state $result)
   (if (= $result ($_type $_kb $_prf $tv)) (with-tv $tv) no-tv))

(= (goal-expanded? $gid)
   (nonempty? (collapse (once (match &goal_expanded ($gid true) true)))))

(= (goal-pending-score-of $gid)
   (first-or (collapse (once (match &goal_pending_score ($gid $score) $score))) 0.0))

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

(= (materialize-result-atom $atom)
   (if (= $atom ($type $kb $prf $tv)) ($type $kb (materialize-proof-refs $prf) $tv)
      $atom))

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
        ((leaf (CPU $_fun $_args $_res)) cpu)
        ((leaf $raw) (if (= $raw ($_type ($_kbid $_ctx $_vars) $prf $_tv)) $prf $raw))
        ((rule $aid $_term)
           (materialize-rule-proof $aid (match &proof_children ($pid $kids) $kids)))
        ($other $other))))

(= (goal-class $goal)
   (if (= $goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) proof direct))

(= (goal-term-has-type-vars? $goal)
   (if (= $goal ($type ($_kbid $_ctx $_vars) $_prf $_tv))
      (nonempty? (extract-vars $type))
      false))

(= (goal-has-type-vars? $gid) (goal-term-has-type-vars? (goal-term-by-id $gid)))

(= (goal-proof-pids $gid)
   (collapse (match &goal_proof ($gid $pid) $pid)))

(= (goal-proof-atoms ()) ())
(= (goal-proof-atoms (cons $pid $rest))
   (cons (proof-output-atom $pid) (goal-proof-atoms $rest)))

(= (goal-merged-proof-atom $gid)
   (let $pids (goal-proof-pids $gid)
      (if (== $pids ()) ()
         (fold-flat
            (|-> ($acc $pid) (merge-proof-atoms $acc (proof-output-atom $pid)))
            (proof-output-atom (car-atom $pids))
            (cdr-atom $pids)))))

(= (materialize-result-atoms ()) ())
(= (materialize-result-atoms (cons $atom $rest))
   (cons (materialize-result-atom $atom) (materialize-result-atoms $rest)))

(= (goal-results $gid)
   (if (goal-has-type-vars? $gid)
      (materialize-result-atoms (goal-proof-atoms (goal-proof-pids $gid)))
      (let $merged (goal-merged-proof-atom $gid)
         (if (== $merged ()) ()
            (cons (materialize-result-atom $merged) ())))))

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
              ($_1 (add-atom &goal_by_id ($gid $stored-goal)))
              ($_2 (add-atom &goal_lookup ($stored-goal $gid))))
            $gid)
         (car-atom $hits))))

(= (schedule-goal-heap $agenda $score $gid)
   (let*
      (($expanded (goal-expanded? $gid))
        ($current (goal-pending-score-of $gid)))
      (if $expanded $agenda
         (if (>= $current $score) $agenda
            (let*
               (($goal (goal-term-by-id $gid))
                 ($closed-proof-bonus
                    (if (goal-term-has-type-vars? $goal) 0.0 1.0))
                 ($bonus (if (== (goal-class $goal) proof) $closed-proof-bonus 2.0))
                 ($priority (- 0 (+ (* 1000000.0 $score) $bonus)))
                 ($nagenda (add_to_heap $agenda $priority (qitem $score $gid)))
                 ($_clear (clear-goal-pending-score $gid))
                 ($_set (add-atom &goal_pending_score ($gid $score))))
               $nagenda)))))

(= (normalize-heap $agenda)
   (if (== $agenda ()) (empty_heap) $agenda))

(= (needs-steps-cpu-fun? $fun) false)

(= (compiled-query-goal-head (goal $query)) $query)
(= (compiled-query-goal-head $compiled-query)
   (case (car-atom $compiled-query) (
        ((goal $query) $query)
        ($other (notsupported compiled-query-goal-head $compiled-query $other)))))

(= (compiled-query-adds (goal $query)) ())
(= (compiled-query-adds $compiled-query) (cdr-atom $compiled-query))

(= (aggregate-compiled-query $kb $pattern)
   (internalize-proof-structure-list (collapse (mm2compileQuery $kb (: $prf $pattern $tvin)))))

(= (aggregate-goal? $goal)
   (if (= $goal (CPU $fun $_args $_goalres))
      (is-member $fun (() FoldAllFormulaCompiled FoldAllTVFormulaCompiled))
      false))

(= (aggregate-compiled-child-goal $compiled-query)
   (let*
      (($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds))
        ($child-goal (compiled-query-goal-head $compiled-query)))
      $child-goal))

(= (aggregate-goal-spec (CPU FoldAllFormulaCompiled ($kb $pattern $value $init $fun) $_goalres))
   (aggregate-spec
      (aggregate-compiled-child-goal (aggregate-compiled-query $kb $pattern))
      $init
      (aggregate-step-fold-value $fun $pattern $value)
      (aggregate-result-bare FoldAllFormulaCompiled ($kb $pattern $value $init $fun) identity)))

(= (aggregate-goal-spec (CPU FoldAllTVFormulaCompiled ($kb $pattern $init $fun $finish) $_goalres))
   (aggregate-spec
      (aggregate-compiled-child-goal (aggregate-compiled-query $kb $pattern))
      $init
      (aggregate-step-fold-tv $fun)
      (aggregate-result-bare FoldAllTVFormulaCompiled ($kb $pattern $init $fun $finish) $finish)))

(= (aggregate-spec-child-goal (aggregate-spec $child-goal $_init $_step-spec $_result-spec))
   $child-goal)

(= (aggregate-spec-init-acc (aggregate-spec $_child-goal $init $_step-spec $_result-spec))
   $init)

(= (aggregate-spec-step (aggregate-spec $_child-goal $_init $step-spec $_result-spec))
   $step-spec)

(= (aggregate-spec-result-spec (aggregate-spec $_child-goal $_init $_step-spec $result-spec))
   $result-spec)

(= (aggregate-spec-step-value (aggregate-step-fold-value $_fun $pattern $value) $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))

(=
   (aggregate-spec-step-acc
      (aggregate-step-fold-value $fun $pattern $value)
      $acc
      $child-atom
      $_child-tv)
   (let $val
      (aggregate-spec-step-value (aggregate-step-fold-value $fun $pattern $value) $child-atom)
      (eval ($fun $acc $val))))

(=
   (aggregate-spec-step-acc
      (aggregate-step-fold-tv $fun)
      $acc
      $_child-atom
      $child-tv)
   (eval ($fun $acc $child-tv)))

(=
   (aggregate-spec-step-acc aggregate-step-dist-average $acc $_child-atom $child-tv)
   (reduce (reduce (DistSumCountAcc $acc $child-tv))))

(= (aggregate-result-output identity $acc) $acc)

(= (aggregate-result-output dist-average $acc)
   (reduce (reduce (DistAverageFromSumCount $acc))))

(=
   (aggregate-spec-result (aggregate-result-bare $fun $args $acc-mode) $acc)
   (let $out (aggregate-result-output $acc-mode $acc)
      (CPU $fun $args $out)))

(= (aggregate-child-key $pid)
   (let $atom (proof-output-atom $pid)
      (let $key (goal-key-components $atom)
         (if (== $key ()) $atom $key))))

(= (aggregate-state-by-id $agid)
   (match &aggregate_state ($agid $gid $child-gid $spec $acc $ev $seen)
      (aggregate-state $gid $child-gid $spec $acc $ev $seen)))

(= (set-aggregate-state $agid $gid $child-gid $spec $acc $ev $seen)
   (progn
      (collapse
         (match &aggregate_state
            ($agid $old-gid $old-child-gid $old-spec $old-acc $old-ev $old-seen)
            (remove-atom &aggregate_state
               ($agid $old-gid $old-child-gid $old-spec $old-acc $old-ev $old-seen))))
      (add-atom &aggregate_state ($agid $gid $child-gid $spec $acc $ev $seen))))

(= (aggregate-finalized? $agid)
   (nonempty? (collapse (once (match &aggregate_finalized ($agid true) true)))))

(= (advance-aggregate-heap $agenda $agid $pid)
   (let*
      (((aggregate-state $gid $child-gid $spec $acc $ev $seen)
           (aggregate-state-by-id $agid))
        ($child-atom (proof-output-atom $pid))
        ($child-key (aggregate-child-key $pid))
        (($_pscore $pev) (proof-stats-by-id $pid))
        ($step-spec (copy_term (aggregate-spec-step $spec))))
      (if (is-member $child-key $seen) $agenda
         (let*
            (($nacc (aggregate-spec-step-acc $step-spec $acc $child-atom (proof-tv-by-id $pid)))
              ($nev (list_to_set (list-append $ev $pev)))
              ($nseen (cons $child-key $seen))
              ($_1 (set-aggregate-state $agid $gid $child-gid $spec $nacc $nev $nseen)))
            $agenda))))

(= (attach-goal-waiter $gid $waiter) (add-atom &goal_waiter ($gid $waiter)))

(= (advance-goal-waiter-heap $agenda (frontier $fid) $pid)
   (advance-frontier-heap $agenda $fid $pid))
(= (advance-goal-waiter-heap $agenda (aggregate $agid) $pid)
   (advance-aggregate-heap $agenda $agid $pid))

(= (attach-existing-aggregate-proofs-heap $agenda $agid $child-gid)
   (fold-flat (|-> ($acc $pid) (advance-aggregate-heap $acc $agid $pid))
      $agenda
      (collapse (match &goal_proof ($child-gid $pid) $pid))))

(= (spawn-aggregate-goal-heap $agenda $score $gid $goal)
   (let*
      (($spec (aggregate-goal-spec $goal))
        ($child-goal (aggregate-spec-child-goal $spec))
        ($child-gid (ensure-goal $child-goal))
        ($agid (next-agid))
        ($stored-spec (copy_term $spec))
        ($_1
           (set-aggregate-state $agid
              $gid
              $child-gid
              $stored-spec
              (aggregate-spec-init-acc $spec)
              ()
              ()))
        ($_2 (attach-goal-waiter $child-gid (aggregate $agid)))
        ($agenda1 (attach-existing-aggregate-proofs-heap $agenda $agid $child-gid))
        ($nagenda (schedule-goal-heap $agenda1 $score $child-gid)))
      $nagenda))

(= (finalize-aggregate-heap $agenda $agid)
   (if (aggregate-finalized? $agid) $agenda
      (let*
         (((aggregate-state $gid $child-gid $spec $acc $ev $_seen)
              (aggregate-state-by-id $agid))
           ($dep-agids
              (collapse
                 (match &aggregate_state
                    ($dep-agid $child-gid $_dep-child $_dep-spec $_dep-acc $_dep-ev $_dep-seen)
                    $dep-agid)))
           ($agenda1 (fold-flat finalize-aggregate-heap $agenda $dep-agids))
           ($_1 (add-atom &aggregate_finalized ($agid true)))
           ($result (aggregate-spec-result (aggregate-spec-result-spec $spec) $acc)))
         (commit-proof-candidate-heap $agenda1
            $gid
            (classify-goal-proof-candidate $gid $ev (term-confidence $result))
            (leaf-result-candidate $result $ev)))))

(= (finalize-all-aggregates-heap $agenda)
   (let $agids
      (collapse
         (match &aggregate_state ($agid $_gid $_child-gid $_goal $_acc $_ev $_seen)
            $agid))
      (fold-flat finalize-aggregate-heap $agenda $agids)))

(= (runtime-kctx $kb)
   (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil)) ($kb MAIN Nil)))

(= (runtime-query-pattern $pattern) (map-nested2 toQuery $pattern))

(= (runtime-match-pattern $qpattern)
   (if (contains-hash? $qpattern) (map-nested unwrap $qpattern) $qpattern))

(= (direct-goal-query-term $goal)
   (if (= $goal ($type ($kbid $_ctx $_vars) $prf $tv))
      (let $qtype
         (if (and (is-expr $type) (contains-hash? $type)) (map-nested unwrap $type)
            $type)
         ($qtype ($kbid $_ctx $_vars) $prf $tv))
      $goal))

(= (direct-goal-fact-match $goal $candidate)
   (let $goal-copy (copy_term $goal) (if (= $goal-copy $candidate) $candidate (empty))))

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

(= (store-proof-candidate $gid (proof-candidate $kind $tv-state $score $ev $children))
   (let*
      (($pid (next-pid))
        ($_1 (add-atom &proof_goal ($pid $gid)))
        ($_2 (add-atom &proof_kind ($pid $kind)))
        ($_3 (add-atom &proof_stats ($pid $score $ev)))
        ($_4 (add-atom &proof_children ($pid $children))))
      $pid))

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
               (fold-flat
                  (|-> ($acc $waiter) (advance-goal-waiter-heap $acc $waiter $pid))
                  $agenda
                  (collapse (match &goal_waiter ($gid $waiter) $waiter))))))))

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
        ($accepted (classify-goal-proof-candidate $gid $ev $score))
        ($tv-state
           (if (= $result ($_type ($_kbid $_ctx $_vars) $prf $tv)) (with-tv $tv) no-tv)))
      (commit-proof-candidate-heap $agenda
         $gid
         $accepted
         (proof-candidate (leaf $result) $tv-state $score $ev ()))))

(= (direct-goal-result-exact-hit? $goal $result)
   (if (= $goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv))
      (let $goal-copy (copy_term $goal) (if (= $goal-copy $result) true false))
      (goal-key-eq? $goal $result)))

(= (instantiated-bundle-goal $aid $pid-list)
   (case
      (instantiate-and-bundle
         (copy_term (match &and_node ($aid $_parent $_rule $_bound $bundle) $bundle))
         $pid-list) (
        ((and-bundle $goal $_rest) $goal)
        )))

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
                   ($_2 (attach-goal-waiter $gid (frontier $fid)))
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
        ($lst $exact))
      (if (== $lst ()) $agenda (fold-flat expand-rule-goal-fold $agenda $lst))))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid $rule-id))
   (let*
      (($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args)))
        ($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier-heap $agenda $parent-gid $aid $bundle $bound () ())))

(= (expand-goal-heap $agenda $steps $score $gid)
   (let $goal (goal-term-by-id $gid)
      (if (aggregate-goal? $goal)
         (let*
            (($_expand (add-atom &goal_expanded ($gid true)))
              ($nagenda0 (spawn-aggregate-goal-heap $agenda $score $gid $goal))
              ($nagenda (normalize-heap $nagenda0)))
            $nagenda)
         (let*
            (($_expand (add-atom &goal_expanded ($gid true)))
              ($results (collapse (direct-goal-results $steps $goal)))
              ($agenda10
                 (fold-flat
                    (|-> ($acc $result) (expand-direct-goal-result-heap $acc $gid $result))
                    $agenda
                    $results))
              ($agenda1 (normalize-heap $agenda10))
              ($exact-hit
                 (fold-flat
                    (|-> ($acc $result)
                       (or $acc (direct-goal-result-exact-hit? $goal $result)))
                    false
                    $results))
              ($nagenda0
                 (if $exact-hit $agenda1
                    (expand-rule-goal-heap $agenda1 $gid $goal)))
              ($nagenda (normalize-heap $nagenda0)))
            $nagenda))))

(= (search-goals-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0))
      (search-state $steps $agenda)
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
   (clear-spaces
      (() &goal_by_id &goal_lookup &goal_expanded &goal_pending_score
         &goal_waiter &and_node &frontier &aggregate_state &aggregate_finalized
         &goal_proof &proof_goal &proof_stats &proof_kind &proof_children)))

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
         (if (needs-steps-cpu-fun? $fun) (cons $fun (cons $steps $args))
            (cons $fun $args)))))

(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (foldall-eval $fun (eval ($fun $acc $elem)) $tail))

(= (assert-space-atom-ref $space $expr)
   (let $term (Predicate (cons $space $expr))
      (let $_ (callPredicate (Predicate (assertz $term $ref)))
         $ref)))

(= (erase-clause-ref $ref)
   (callPredicate (Predicate (erase $ref))))

(= (track-temp-query-ref $ref)
   (add-atom &temp_query_ref (clause_ref $ref)))

(= (temp-query-rule-id $id) (temp_query_rule $id))

(= (temp-add-prem $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) ()
            (let*
               (($ref (assert-space-atom-ref prem_index ($key $prem $id $idx)))
                 ($_track (track-temp-query-ref $ref)))
               ()))
         (+ $idx 1))))

(= (temp-add-to-kb $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($raw-id (nextid))
           ($id (temp-query-rule-id $raw-id))
           ($_1 (fold-flat (temp-add-prem $id) 0 $args))
           ($ccls-ref (assert-space-atom-ref ccls_index ($ccls $id)))
           ($_2 (track-temp-query-ref $ccls-ref))
           ($rule-ref (assert-space-atom-ref rules ($id $ccls $args)))
           ($_3 (track-temp-query-ref $rule-ref)))
         ())
      (progn
         (let $ref (assert-space-atom-ref &kb $expr)
            (track-temp-query-ref $ref)))))

(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn
               (erase_clause_ref $ref)
               (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(= (inject-compiled-adds $adds) (if (= $adds ()) $_ (foreach-flat temp-add-to-kb $adds)))

(= (query $steps $kb $stmt)
   (let*
      (($compiled-query
           (internalize-proof-structure-list (collapse (mm2compileQuery $kb $stmt))))
        ($adds (compiled-query-adds $compiled-query))
        ($_clear-temp-before (clear-temp-query-adds))
        ($_ (inject-compiled-adds $adds))
        ($goal (compiled-query-goal-head $compiled-query))
        ($results (chainer $steps $goal))
        ($_clear-temp-after (clear-temp-query-adds))
        ($eres (map-flat externalize-proof-structure $results))
        ($pres (map-flat pretty $eres)))
      (superpose $pres)))

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

(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun)
   (FoldAllTVRuntimeNoStepsQuery $kb (runtime-query-pattern $pattern) $init $fun))
