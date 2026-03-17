(= (goal-term-by-id $gid) (match &goal_by_id ($gid $goal) $goal))

(= (backward-load-agenda)
   (let $magenda (catch (get-state bwd_agenda))
      (if-error $magenda (empty_heap) $magenda)))

(= (backward-save-agenda $agenda) (change-state! bwd_agenda $agenda))

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

(= (proof-unify-term $pid)
   (let*
      (($gid (proof-goal-by-id $pid))
        ($goal (goal-term-by-id $gid))
        ($kind (proof-kind-by-id $pid))
        ($tv (proof-tv-by-id $pid)))
      (if (= $goal ($type ($kbid $_ctx $_vars) $_prf $_goal-tv))
         ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)
         (case $kind (
              ((leaf $term) $term)
              ($other (empty)))))))

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
        ((and-bundle ($_type $_kb $prf $_tv) $_rest) (materialize-proof-refs $prf))
        ($other $other))))

(= (materialize-proof $pid)
   (case (proof-kind-by-id $pid) (
        ((leaf ($_type $_kb $prf $_tv)) $prf)
        ((leaf $raw) $raw)
        ((rule $aid)
           (materialize-rule-proof $aid (match &proof_children ($pid $kids) $kids)))
        ($other $other))))

(= (proof-output-atom $pid)
   (let*
      (($gid (proof-goal-by-id $pid))
        (($type ($kbid $_ctx $_vars) $_prf $_goal-tv) (goal-term-by-id $gid))
        ($tv (proof-tv-by-id $pid)))
      ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)))

(= (goal-summary-pid $gid)
   (let $hits (collapse (once (match &goal_summary_proof ($gid $pid) $pid)))
      (if (== $hits ()) () (car-atom $hits))))

(= (goal-results $gid)
   (let $pid (goal-summary-pid $gid)
      (if (== $pid ()) () (cons (materialize-proof-atom (proof-output-atom $pid)) ()))))

(= (ensure-goal $goal)
   (let $hits
      (collapse
         (once
            (if (= $goal ($type ($kbid $_ctx $_vars) $kbprf $_tv))
               (let $sealed-type (sealed (extract-vars $type) $type)
                  (match &goal_lookup
                     (($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv) $gid)
                     (if $gid
                        (goal-key-eq?
                           ($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv)
                           $goal)
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

(= (schedule-goal $score $gid)
   (if (goal-expanded? $gid) ()
      (let $current (goal-pending-score-of $gid)
         (if (>= $current $score) ()
            (let*
               (($agenda (backward-load-agenda))
                 ($goal-class (match &goal_class ($gid $class) $class))
                 ($bonus (if (== $goal-class proof) 0.0 1.0))
                 ($priority (- 0 (+ (* 1000000.0 $score) $bonus)))
                 ($nagenda (add_to_heap $agenda $priority (qitem $score $gid)))
                 ($_save (backward-save-agenda $nagenda)))
               (progn
                  (clear-goal-pending-score $gid)
                  (add-atom &goal_pending_score ($gid $score))
                  ()))))))

(= (goal-has-ancestor-seen? $gid $ancestor $seen)
   (if (== $gid $ancestor) true
      (if (is-member $gid $seen) false
         (let $parents
            (collapse
               (match &goal_waiter ($gid $fid)
                  (match &frontier ($fid $parent $_aid $_bundle $_score $_seen $_rev)
                     $parent)))
            (fold-flat
               (|-> ($found $parent)
                  (or $found
                     (goal-has-ancestor-seen? $parent $ancestor (cons $gid $seen))))
               false
               $parents)))))

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
      (cons (fact-ev ($kbid $_ctx $_vars) $prf $type) ())
      ()))

(= (proof-overlap-dominates-score? $old-ev $old-score $new-ev $new-score)
   (and (evidence-sets-overlap? $old-ev $new-ev)
      (or (> $old-score $new-score)
         (and (== $old-score $new-score) (evidence-subset? $new-ev $old-ev)))))

(= (goal-proof-candidate-step $ev $score false $_oldpid) false)
(= (goal-proof-candidate-step $ev $score $rev-pruned $oldpid)
   (let ($old-score $old-ev) (proof-stats-by-id $oldpid)
      (if (proof-overlap-dominates-score? $old-ev $old-score $ev $score) false
         (if (proof-overlap-dominates-score? $ev $score $old-ev $old-score)
            (cons $oldpid $rev-pruned)
            $rev-pruned))))

(= (classify-goal-proof-candidate $gid $ev $score)
   (fold-flat (goal-proof-candidate-step $ev $score)
      ()
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

(= (commit-proof-candidate $gid false $_candidate) ())
(=
   (commit-proof-candidate $gid
      $rev-pruned
      (proof-candidate $kind $tv-state $score $ev $children))
   (let $pid
      (store-proof-candidate $gid
         (proof-candidate $kind $tv-state $score $ev $children))
      (progn
         (foreach-flat (|-> ($oldpid) (remove-atom &goal_proof ($gid $oldpid)))
            $rev-pruned)
         (add-atom &goal_proof ($gid $pid))
         (let $summary-pid (refresh-goal-summary-proof $gid)
            (if (== $summary-pid ()) ()
               (collapse
                  (advance-frontier (match &goal_waiter ($gid $fid) $fid) $summary-pid)))))))

(= (attach-existing-goal-proofs $fid $gid)
   (let $summary-pid (goal-summary-pid $gid)
      (if (== $summary-pid ()) () (advance-frontier $fid $summary-pid))))

(= (expand-direct-goal $steps $gid $goal)
   (let*
      (($result (direct-goal-results $steps $goal))
        ($score (term-confidence $result))
        ($ev (leaf-evidence-for-result $result))
        ($tv-state
           (if (= $result ($_type ($_kbid $_ctx $_vars) $prf $tv)) (with-tv $tv) no-tv)))
      (commit-proof-candidate $gid
         (classify-goal-proof-candidate $gid $ev $score)
         (proof-candidate (leaf $result) $tv-state $score $ev ()))))

(= (spawn-frontier $parent-gid $aid $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ())
           (build-parent-proof $parent-gid
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
              (if (goal-has-ancestor-seen? $parent-gid $gid ()) ()
                 (progn
                    (add-atom &frontier
                       ($fid $parent-gid $aid $stored-bundle $score $seen $rev-pids))
                    (add-atom &goal_waiter ($gid $fid))
                    (attach-existing-goal-proofs $fid $gid)
                    (schedule-goal $score $gid)
                    ())))))))

(= (frontier-state-by-id $fid)
   (match &frontier ($fid $parent-gid $aid $bundle $score $seen $rev-pids)
      (frontier-state $parent-gid $aid $bundle $score $seen $rev-pids)))

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-unify-term $pid)) (and-bundle $goal $rest) ()))

(= (advance-frontier $fid $pid)
   (let*
      (((frontier-state $parent-gid $aid $bundle $score $seen $rev-pids)
           (frontier-state-by-id $fid))
        (($pscore $pev) (proof-stats-by-id $pid))
        (False (evidence-sets-overlap? $seen $pev))
        ($next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)))
      (if (== $next-bundle ()) ()
         (spawn-frontier $parent-gid
            $aid
            $next-bundle
            (min $score $pscore)
            (list_to_set (list-append $seen $pev))
            (cons $pid $rev-pids)))))

(= (expand-rule-goal $parent-gid $goal)
   (let*
      (($args
           (match ccls_index ($goal $rule-id)
              (match rules ($rule-id $goal $args)
                 $args)))
        ($bound (premises-expected-confidence $args))
        ($bundle (copy_term (and-bundle $goal $args)))
        ($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier $parent-gid $aid $bundle $bound () ())))

(= (expand-goal $steps $gid)
   (let $goal (goal-term-by-id $gid)
      (progn
         (add-atom &goal_expanded ($gid true))
         (collapse (expand-direct-goal $steps $gid $goal))
         (collapse (expand-rule-goal $gid $goal)))))

(= (search-goals $steps)
   (if (or (<= $steps 0) (== (heap_size (@ $agenda (backward-load-agenda))) 0)) ()
      (let*
         (($rest (get_from_heap $agenda $_priority $item))
           ((qitem $score $gid) (tracem pop $item))
           ($_save (backward-save-agenda $rest)))
         (if (and (not (goal-expanded? $gid)) (== (goal-pending-score-of $gid) $score))
            (progn
               (clear-goal-pending-score $gid)
               (expand-goal $steps $gid)
               (search-goals (- $steps 1)))
            (search-goals $steps)))))

(= (instantiate-and-bundle (and-bundle $goal ()) ()) (and-bundle $goal ()))
(= (instantiate-and-bundle (and-bundle $goal (cons $prem $rest)) (cons $pid $pids))
   (if (= $prem (proof-unify-term $pid))
      (instantiate-and-bundle (and-bundle $goal $rest) $pids)
      (empty)))

(=
   (build-parent-proof $parent-gid
      $aid
      (and-bundle ($_type ($_kbid $_ctx $_vars) $_prf $tv) ())
      $score
      $ev
      $pid-list)
   (commit-proof-candidate $parent-gid
      (classify-goal-proof-candidate $parent-gid $ev $score)
      (proof-candidate (rule $aid) (with-tv $tv) $score $ev $pid-list)))

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
        ($_agendareset (backward-save-agenda (empty_heap)))
        ($_gidreset (change-state! bwd_gid 0))
        ($_aidreset (change-state! bwd_aid 0))
        ($_fidreset (change-state! bwd_fid 0))
        ($_pidreset (change-state! bwd_pid 0))
        ($root-gid (ensure-goal $goal))
        ($_sched (schedule-goal 1.0 $root-gid))
        ($_search (if (<= $steps 0) () (search-goals (+ $steps 1)))))
      (let $results (goal-results $root-gid) $results)))

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

(= (inject-compiled-adds $adds)
   (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds))))

(= (run-compiled-query $steps $compiled-query)
   (let*
      (((cons (goal $query) $adds) $compiled-query)
        ($_ (inject-compiled-adds $adds)))
      (chainer $steps $query)))

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
