(= (goal-term-by-id $gid) (match &goal_by_id ($gid $goal) $goal))

(= (backward-load-agenda)
   (let $magenda (catch (get-state bwd_agenda)) (if-error $magenda (empty_heap) $magenda)))

(= (backward-save-agenda $agenda) (change-state! bwd_agenda $agenda))

(= (goal-expanded? $gid) (not (== (collapse (once (match &goal_expanded ($gid true) true))) ())))

(= (goal-pending-score-of $gid)
   (let $scores (collapse (once (match &goal_pending_score ($gid $score) $score)))
      (if (== $scores ()) 0.0 (car-atom $scores))))

(= (clear-goal-pending-score $gid)
   (progn
      (collapse (match &goal_pending_score ($gid $score) (remove-atom &goal_pending_score ($gid $score))))
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
              ((leaf $_ev $term) $term)
              ($other (empty)))))))

(= (materialize-proof-refs $term)
   (if (= $term (proof-ref $pid)) (materialize-proof $pid)
      (if (is-expr $term)
         (cons (materialize-proof-refs (car-atom $term)) (map-flat materialize-proof-refs (cdr-atom $term)))
         $term)))

(= (materialize-proof-atom ($type $kb $prf $tv)) ($type $kb (materialize-proof-refs $prf) $tv))

(= (materialize-rule-proof $aid $pid-list)
   (case
      (instantiate-and-bundle (copy_term (match &and_node ($aid $_parent $_rule $_bound $bundle) $bundle))
         $pid-list) (
        ((and-bundle ($_type $_kb $prf $_tv) $_rest) (materialize-proof-refs $prf))
        ($other $other))))

(= (materialize-proof $pid)
   (case (proof-kind-by-id $pid) (
        ((leaf $_ev $raw) $raw)
        ((rule $aid) (materialize-rule-proof $aid (match &proof_children ($pid $kids) $kids)))
        ((revision $left $right) (merge/revision (materialize-proof $left) (materialize-proof $right)))
        ($other $other))))

(= (proof-output-atom $pid)
   (let*
      (($gid (proof-goal-by-id $pid))
        (($type ($kbid $_ctx $_vars) $_prf $_goal-tv) (goal-term-by-id $gid))
        ($tv (proof-tv-by-id $pid)))
      ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)))

(= (goal-results $gid)
   (let*
      (($pids (collapse (match &goal_proof ($gid $pid) $pid)))
        ($merged
           (if (== $pids ()) ()
              (fold-flat (|-> ($goal $pid) (merge-proof-atoms $goal (proof-output-atom $pid)))
                 (proof-output-atom (car-atom $pids))
                 (cdr-atom $pids)))))
      (if (== $pids ()) () (cons (materialize-proof-atom $merged) ()))))

(= (ensure-goal $goal)
   (let $hits
      (collapse
         (once
            (if (= $goal ($type ($kbid $_ctx $_vars) $kbprf $_tv))
               (let $sealed-type (sealed (extract-vars $type) $type)
                  (match &goal_lookup (($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv) $gid)
                     (if (goal-key-eq? ($sealed-type ($kbid $_ctx $_vars) $_stored-prf $_stored-tv) $goal)
                        $gid
                        (empty))))
               (let $sealed-goal (sealed (extract-vars $goal) $goal)
                  (match &goal_lookup ($sealed-goal $gid)
                     (if (goal-key-eq? $sealed-goal $goal) $gid (empty)))))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
              ($stored-goal (copy_term $goal))
              ($goal-class (if (= $stored-goal ($_type ($_kbid $_ctx $_vars) $_prf $_tv)) proof direct))
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
                  (or $found (goal-has-ancestor-seen? $parent $ancestor (cons $gid $seen))))
               false
               $parents)))))

(= (direct-goal-results $steps $goal)
   (if (= $goal (CPU $fun $args $_res)) ((CPU $fun $args (cpu-call $steps $fun $args)))
      (let ($type ($kbid $_ctx $_vars) $prf $tv) $goal
         (let $kb ($kbid $_ctx $_vars)
            (let $utype (if (and (is-expr $type) (contains-hash? $type)) (map-nested unwrap $type) $type)
               (collapse (match &kb ($utype $kb $prf $tv) ($type $kb $prf $tv))))))))

(= (leaf-evidence-for-result $result)
   (if (= $result ($type ($kbid $_ctx $_vars) $prf $_tv)) (cons (fact-ev ($kbid $_ctx $_vars) $prf $type) ())
      ()))

(= (store-leaf-proof $gid $result)
   (let*
      (($pid (next-pid))
        ($score (term-confidence $result))
        ($ev (leaf-evidence-for-result $result))
        ($_1 (add-atom &proof_goal ($pid $gid)))
        ($_2 (add-atom &proof_score ($pid $score)))
        ($_3 (add-atom &proof_evidence ($pid $ev)))
        ($_4 (add-atom &proof_children ($pid ()))))
      (if (= $result ($_type ($_kbid $_ctx $_vars) $prf $tv))
         (let*
            (($_5 (add-atom &proof_kind ($pid (leaf $ev $prf))))
              ($_6 (add-atom &proof_tv ($pid $tv))))
            $pid)
         (let $_5 (add-atom &proof_kind ($pid (leaf $ev $result))) $pid))))

(= (proof-overlap-dominates? $winner $loser)
   (let*
      (($evw (proof-evidence-by-id $winner))
        ($evl (proof-evidence-by-id $loser))
        ($overlap (evidence-sets-overlap? $evw $evl))
        ($sw (proof-score-by-id $winner))
        ($sl (proof-score-by-id $loser)))
      (and $overlap (>= $sw $sl))))

(= (prune-dominated-goal-proofs $gid $pid)
   (progn
      (collapse
         (match &goal_proof ($gid $oldpid)
            (if (proof-overlap-dominates? $pid $oldpid)
               (progn (remove-atom &goal_proof ($gid $oldpid))
                  (add-atom &proof_status ($oldpid (dominated $pid))))
               ())))
      ()))

(= (goal-proof-rejected? $gid $pid)
   (not
      (==
         (collapse
            (match &goal_proof ($gid $oldpid)
               (if (proof-overlap-dominates? $oldpid $pid) $oldpid (empty))))
         ())))

(= (attach-existing-goal-proofs $fid $gid)
   (foreach-flat (|-> ($pid) (advance-frontier $fid $pid))
      (collapse (match &goal_proof ($gid $pid) $pid))))

(= (register-proof $gid $pid)
   (if (goal-proof-rejected? $gid $pid) (progn (add-atom &proof_status ($pid (dominated existing))) ())
      (progn
         (prune-dominated-goal-proofs $gid $pid)
         (add-atom &goal_proof ($gid $pid))
         (add-atom &proof_status ($pid live))
         (foreach-flat (|-> ($fid) (advance-frontier $fid $pid))
            (collapse (match &goal_waiter ($gid $fid) $fid))))))

(= (emit-leaf-result $gid $result) (register-proof $gid (store-leaf-proof $gid $result)))

(= (expand-direct-goal $steps $gid $goal)
   (foreach-flat (|-> ($result) (emit-leaf-result $gid $result)) (direct-goal-results $steps $goal)))

(= (advance-frontier-bundle (and-bundle $_goal ()) $_pid) ())
(= (advance-frontier-bundle (and-bundle $goal (cons $prem $rest)) $pid)
   (if (= $prem (proof-unify-term $pid)) (and-bundle $goal $rest) ()))

(= (spawn-frontier $aid $bundle $score $seen $rev-pids)
   (case $bundle (
        ((and-bundle $goal ()) (build-parent-proof $aid $bundle $score $seen (list-reverse $rev-pids)))
        ((and-bundle $_goal (cons $prem $_rest))
           (let*
              (($gid (ensure-goal $prem))
                ($parent-gid (and-parent-gid-by-id $aid)))
              (if (goal-has-ancestor-seen? $parent-gid $gid ()) ()
                 (let*
                    (($fid (next-fid))
                      ($stored-bundle (copy_term $bundle))
                      ($_1 (add-atom &frontier ($fid $parent-gid $aid $stored-bundle $score $seen $rev-pids)))
                      ($_2 (add-atom &goal_waiter ($gid $fid))))
                    (progn
                       (attach-existing-goal-proofs $fid $gid)
                       (schedule-goal $score $gid)
                       ()))))))))

(= (and-parent-gid-by-id $aid) (match &and_node ($aid $parent $_rule $_bound $_bundle) $parent))

(= (frontier-state-by-id $fid)
   (match &frontier ($fid $parent-gid $aid $bundle $score $seen $rev-pids)
      (frontier-state $parent-gid
         $aid
         $bundle
         $score
         $seen
         $rev-pids)))

(= (advance-frontier $fid $pid)
   (let*
      (((frontier-state $_parent-gid $aid $bundle $score $seen $rev-pids) (frontier-state-by-id $fid))
        ($pev (proof-evidence-by-id $pid))
        ($pscore (proof-score-by-id $pid)))
      (if (evidence-sets-overlap? $seen $pev) ()
         (let $next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)
            (if (== $next-bundle ()) ()
               (spawn-frontier $aid
                  $next-bundle
                  (min $score $pscore)
                  (list_to_set (list-append $seen $pev))
                  (cons $pid $rev-pids)))))))

(= (register-rule-option $parent-gid (rule-option $rule-id $bound $bundle))
   (let*
      (($aid (next-aid))
        ($_1 (add-atom &and_node ($aid $parent-gid $rule-id $bound $bundle))))
      (spawn-frontier $aid
         $bundle
         $bound
         ()
         ())))

(= (goal-rule-options $goal)
   (collapse
      (let*
         (($id (match &ccls_index ($goal $id) $id))
           (($_id $_matched-goal $args) (match &rules ($id $goal $args) ($_id $_matched-goal $args)))
           ($bound (premises-expected-confidence $args))
           ($bundle (copy_term (and-bundle $goal $args))))
         (rule-option $id $bound $bundle))))

(= (expand-rule-goal $parent-gid $goal)
   (foreach-flat (|-> ($option) (register-rule-option $parent-gid $option)) (goal-rule-options $goal)))

(= (expand-goal $steps $gid)
   (if (goal-expanded? $gid) ()
      (let*
         (($goal (goal-term-by-id $gid))
           ($_1 (add-atom &goal_expanded ($gid true))))
         (progn
            (expand-direct-goal $steps $gid $goal)
            (expand-rule-goal $gid $goal)
            ()))))

(= (search-goals $steps)
   (if (<= $steps 0) ()
      (let $agenda (backward-load-agenda)
         (if (== (heap_size $agenda) 0) ()
            (let $rest (get_from_heap $agenda $_priority $item)
               (let (qitem $score $gid) $item
                  (let $_save (backward-save-agenda $rest)
                     (if (if (goal-expanded? $gid) false (== (goal-pending-score-of $gid) $score))
                        (progn
                           (clear-goal-pending-score $gid)
                           (expand-goal $steps $gid)
                           (search-goals (- $steps 1)))
                        (search-goals $steps)))))))))

(= (instantiate-and-bundle (and-bundle $goal ()) ()) (and-bundle $goal ()))
(= (instantiate-and-bundle (and-bundle $goal (cons $prem $rest)) (cons $pid $pids))
   (if (= $prem (proof-unify-term $pid)) (instantiate-and-bundle (and-bundle $goal $rest) $pids) (empty)))

(= (build-parent-proof $aid (and-bundle ($_type ($_kbid $_ctx $_vars) $_prf $tv) ()) $score $ev $pid-list)
   (let*
      (($parent-gid (and-parent-gid-by-id $aid))
        ($pid (next-pid))
        ($_1 (add-atom &proof_goal ($pid $parent-gid)))
        ($_2 (add-atom &proof_kind ($pid (rule $aid))))
        ($_3 (add-atom &proof_tv ($pid $tv)))
        ($_4 (add-atom &proof_score ($pid $score)))
        ($_5 (add-atom &proof_evidence ($pid $ev)))
        ($_6 (add-atom &proof_children ($pid $pid-list))))
      (register-proof $parent-gid $pid)))

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
        ($_pgoalclear (remove-all-atoms &proof_goal))
        ($_pscoreclear (remove-all-atoms &proof_score))
        ($_pevidenceclear (remove-all-atoms &proof_evidence))
        ($_pkindclear (remove-all-atoms &proof_kind))
        ($_ptvclear (remove-all-atoms &proof_tv))
        ($_pchildclear (remove-all-atoms &proof_children))
        ($_pstatusclear (remove-all-atoms &proof_status)))
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

(= (contains-hash? $x) (if (== $x #) true (if (is-expr $x) (contains-hash-expr $x) false)))

(= (contains-hash-expr $expr) (or (== (car-atom $expr) #) (contains-hash-list (cdr-atom $expr))))

(= (contains-hash-list ()) false)
(= (contains-hash-list (cons $head $tail)) (or (contains-hash? $head) (contains-hash-list $tail)))

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

(= (inject-compiled-adds $adds) (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds))))

(= (run-compiled-query $steps $compiled-query)
   (let*
      (((cons (goal $query) $adds) $compiled-query)
        ($_ (inject-compiled-adds $adds)))
      (chainer $steps $query)))

(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (foldall-eval $fun
      $init
      (collapse
         (let ($pattern ($kbid $_ctx $_vars) $prf $tvin) (run-compiled-query $steps $compiled-query) $value))))

(= (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun)
   (foldall-eval $fun $init (extract-proof-tvs (run-compiled-query $steps $compiled-query))))

(= (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun)
   (let*
      (($kctx (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil)) ($kb MAIN Nil)))
        ($matches (collapse (match &kb ($pattern $kctx $prf $ptv) $ptv))))
      (foldall-eval $fun $init $matches)))

(= (Map2DistRuntimeFormula $steps $kb $fun $a $b)
   (let (: $prfa $a $tva) (query $steps $kb (: $prfa $a $tva))
      (let (: $prfb $b $tvb) (query $steps $kb (: $prfb $b $tvb)) (DistMap2Formula $fun $tva $tvb))))

(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun) (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun))

(= (FoldAllTVPatternFormula $steps $kb $pattern $init $fun)
   (foldall-eval $fun
      $init
      (collapse (let (: $prf $pattern $ptv) (query $steps $kb (: $prf $pattern $ptv)) $ptv))))

(= (FoldAllValueFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun))
