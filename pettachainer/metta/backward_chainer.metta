(= (goal-term-by-id $gid) (match &goal_by_id ($gid $goal) $goal))

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

(= (goal-open-index-term $goal)
   (if (= $goal ($type ($kbid $_ctx $_vars) $_prf $_tv))
      ((map-nested2 toQuery $type) ($kbid $qctx $qvars) $qprf $qtv)
      $goal))

(= (goal-has-type-vars? $gid) (goal-term-has-type-vars? (goal-term-by-id $gid)))

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

(= (direct-goal-results $steps $goal)
   (if (= $goal (CPU $fun $args $_res)) (CPU $fun $args (cpu-call $steps $fun $args))
      (let ($type ($kbid $_ctx $_vars) $prf $tv) $goal
         (let $kb ($kbid $_ctx $_vars)
            (let $utype
               (if (and (is-expr $type) (contains-hash? $type))
                  (map-nested unwrap $type)
                  $type)
               (match &kb ($utype $kb $prf $tv)
                  ($type $kb $prf $tv)))))))

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
               (fold-flat (|-> ($acc $fid) (advance-frontier-heap $acc $fid $pid))
                  $agenda
                  (collapse (match &goal_waiter ($gid $fid) $fid))))))))

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

(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (fold-flat (|-> ($acc $result) (expand-direct-goal-result-heap $acc $gid $result))
      $agenda
      (collapse (direct-goal-results $steps $goal))))

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
   (let $lst
      (if (goal-term-has-type-vars? $goal)
         (collapse
            (let $index-goal (goal-open-index-term $goal)
               (match ccls_index ($index-goal $rule-id)
                  (match rules ($rule-id $matched-goal $args)
                     ($args $matched-goal $parent-gid $rule-id)))))
         (collapse
            (match ccls_index ($goal $rule-id)
               (match rules ($rule-id $matched-goal $args)
                  ($args $matched-goal $parent-gid $rule-id)))))
      (fold-flat expand-rule-goal-fold $agenda $lst)))

(= (expand-rule-goal-fold $agenda ($args $goal $parent-gid $rule-id))
   (let*
      (($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args)))
        ($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier-heap $agenda $parent-gid $aid $bundle $bound () ())))

(= (expand-goal-heap $agenda $steps $gid)
   (let $goal (goal-term-by-id $gid)
      (let*
         (($_expand (add-atom &goal_expanded ($gid true)))
           ($agenda1 (expand-direct-goal-heap $agenda $steps $gid $goal))
           ($nagenda (expand-rule-goal-heap $agenda1 $gid $goal)))
         $nagenda)))

(= (search-goals-heap $steps $agenda)
   (if (or (<= $steps 0) (== (heap_size $agenda) 0)) $agenda
      (let*
         (($rest (get_from_heap $agenda $_priority $item))
           ((qitem $score $gid) $item))
         (if (and (not (goal-expanded? $gid)) (== (goal-pending-score-of $gid) $score))
            (let*
               (($_clear (clear-goal-pending-score $gid))
                 ($nagenda (expand-goal-heap $rest $steps $gid)))
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
        ($_fidreset (change-state! bwd_fid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($root-gid (ensure-goal $goal))
        ($agenda0 (schedule-goal-heap (empty_heap) 1.0 $root-gid))
        ($_search
           (if (<= $steps 0) () (collapse (search-goals-heap (+ $steps 1) $agenda0)))))
      (goal-results $root-gid)))

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
         (if (cons $fun (cons $steps $args))
            (is-member $fun
               (() FoldAllFormulaCompiled
                  FoldAllTVFormulaCompiled
                  FoldAllTVPatternFormula
                  FoldAllTVRuntimeFormula
                  FoldAllValueFormulaCompiled
                  DistAverageFormula
                  Map2DistRuntimeFormula))
            (cons $fun $args)))))

(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (foldall-eval $fun (reduce (reduce (cons $fun (cons $acc (cons $elem ()))))) $tail))

(= (extract-proof-tvs ()) ())
(= (extract-proof-tvs (cons ($_type ($_kbid $_ctx $_vars) $_prf $tv) $tail))
   (cons $tv (extract-proof-tvs $tail)))
(= (extract-proof-tvs (cons $_head $tail)) (extract-proof-tvs $tail))

(= (inject-compiled-adds $adds) (if (= $adds ()) $_ (foreach-flat add-to-kb $adds)))

(= (compiled-query-goal (cons (goal $query) $_adds)) $query)

(= (compiled-query-adds (cons (goal $_query) $adds)) $adds)

(= (run-compiled-query $steps $compiled-query)
   (let*
      (($query (compiled-query-goal $compiled-query))
        ($adds (compiled-query-adds $compiled-query))
        ($_ (inject-compiled-adds $adds)))
      (chainer $steps $query)))

(= (run-compiled-query-output $steps $compiled-query)
   (let $results (run-compiled-query $steps $compiled-query)
      (let $eres (map-flat externalize-proof-structure $results)
         (pretty (superpose $eres)))))

(= (query $steps $kb $stmt)
   (run-compiled-query-output $steps
      (map-flat internalize-proof-structure (collapse (mm2compileQuery $kb $stmt)))))

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

(= (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun)
   (let*
      (($kctx
           (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil))
              ($kb MAIN Nil)))
        ($matches (collapse (match &kb ($pattern $kctx $prf $ptv) $ptv))))
      (foldall-eval $fun $init $matches)))

(= (Map2DistRuntimeFormula $steps $kb $fun $a $b)
   (let (: $prfa $a $tva) (query $steps $kb (: $prfa $a $tva))
      (let (: $prfb $b $tvb) (query $steps $kb (: $prfb $b $tvb))
         (DistMap2Formula $fun $tva $tvb))))

(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun)
   (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun))

(= (FoldAllTVPatternFormula $steps $kb $pattern $init $fun)
   (foldall-eval $fun
      $init
      (collapse
         (let (: $prf $pattern $ptv) (query $steps $kb (: $prf $pattern $ptv)) $ptv))))

(= (FoldAllValueFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun))
