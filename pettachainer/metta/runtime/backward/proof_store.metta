;; Durable proof DAG storage, indexes, liveness, and aggregate snapshots.
(: goal-by-id
   (-[semidet]-> Number StoredGoalRow))
(= (goal-by-id $gid)
   (once
      (match &goal
         (stored-goal-row
            $gid $depth $goal $expanded $pending)
         (stored-goal-row
            $gid $depth $goal $expanded $pending))))

(: proof-goal-key-by-goal-id (-[semidet]-> Number ProofGoalKey))
(= (proof-goal-key-by-goal-id $gid)
   (let
      (stored-goal-row
         $_stored-gid $_depth $goal $_expanded $_pending)
      (goal-by-id $gid)
      (brand ProofGoalKey (goal-key $goal))))

(: proof-owner-goal-key (-[det]-> ProofOwner ProofGoalKey))
(= (proof-owner-goal-key $owner)
   (case $owner (
      ((proof-goal $key) $key)
      ((merged-proof-group $key) $key))))

(: index-proof-for-goal! (-[det]-> ProofGoalKey Number Bool))
(= (index-proof-for-goal! $key $pid)
   (let* (($lookup-key (copy_term $key))
          ($row (make-space-row3 $lookup-key $key $pid)))
      (add-space-atom! &proof_goal $row)))

(: index-proof-result-for-goal! (-[det]-> ProofGoalKey Number Bool))
(= (index-proof-result-for-goal! $key $pid)
   (let* (($lookup-key (copy_term $key))
          ($row (make-space-row3 $lookup-key $key $pid)))
      (add-space-atom! &proof_result $row)))

(: aggregate-by-id
   (-[semidet]-> Number StoredAggregateRow))
(= (aggregate-by-id $agg-gid)
   (once
      (match &aggregate
         (stored-aggregate-row
            $agg-gid $child-gid $args
            $base-score $pending $current-pid)
         (stored-aggregate-row
            $agg-gid $child-gid $args
            $base-score $pending $current-pid))))

(: ProofOutputKey Type)
(: proof-output-key (-[det]-> $term ProofOutputKey))
(: ClosedGoalKey Type)
(: closed-goal ClosedGoalKey)
(: ProofOutputGroup Type)
(: proof-output-group
   (-[det]-> ProofOutputKey (List Number) ProofOutputGroup))
(: NoCTV Type)
(: no-ctv NoCTV)
(: NoTV Type)
(: no-tv NoTV)
(: ProofCandidate Type)
(: proof-candidate
   (-[det]-> ProofKind Number (List Evidence) (List Number) ProofCandidate))

;; Store lookups are partial for an arbitrary numeric id. Preserve their
;; fail-propagating behavior across list traversals without weakening the
;; callback to nondeterministic.
(: proof-map-flat-semidet
   (-[semidet]-> (-[semidet]-> $input $output)
       (List $input) (List $output)))
(= (proof-map-flat-semidet $_fun ()) ())
(= (proof-map-flat-semidet $fun (cons $item $rest))
   (cons ($fun $item)
      (proof-map-flat-semidet $fun $rest)))

(: proof-fold-flat-semidet
   (-[semidet]-> (-[semidet]-> $accumulator $item $accumulator)
       $accumulator (List $item) $accumulator))
(= (proof-fold-flat-semidet $_fun $accumulator ())
   $accumulator)
(= (proof-fold-flat-semidet $fun $accumulator (cons $item $rest))
   (proof-fold-flat-semidet
      $fun ($fun $accumulator $item) $rest))

(: proof-output-identity
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))))
(= (proof-output-identity $term) $term)

;; The structural fact arm of the Goal-or-fact union cannot currently be
;; narrowed as a whole by case. Restore the erased roles field-by-field and
;; validate only the TV payload that affects numeric inference.
(: replace-stored-runtime-proof
   (-[det]-> Atom Atom Atom Atom Number
       (Statement KBContext Proof TV)))
(= (replace-stored-runtime-proof $type $kb $_proof $tv $pid)
   (data
      (brand Statement $type)
      (brand KBContext $kb)
      (brand Proof (proof-ref $pid))
      (the TV $tv)))

(: normalize-proof-output-atom-kind
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Number
       (| Goal (Statement KBContext Proof TV))))
(= (normalize-proof-output-atom-kind $term $pid)
   (case $term (
      ((CPU $fun $args $result)
         (CPU $fun $args $result))
      ((: $kb $proof $statement $tv)
         (: $kb $proof $statement $tv))
      (($type $kb $proof $tv)
         (replace-stored-runtime-proof
            $type $kb $proof $tv $pid))
      ($_other (proof-output-identity $term)))))

(: proof-output-atom-kind
   (-[semidet]-> ProofKind Number
       (| Goal (Statement KBContext Proof TV))))
(= (proof-output-atom-kind (leaf $term) $pid) (normalize-proof-output-atom-kind $term $pid))
(= (proof-output-atom-kind (rule $term) $pid) (normalize-proof-output-atom-kind $term $pid))
(= (proof-output-atom-kind (aggregate $term) $_pid) $term)

(: proof-output-atom
   (-[nondet]-> Number
      (| Goal (Statement KBContext Proof TV))))
(= (proof-output-atom $pid)
   (match &proof
      (stored-proof-row
         $pid $_gid $output $_kind $_support $_children)
      $output))

(: proof-output-atom-by-id
   (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))))
(= (proof-output-atom-by-id $pid)
   (once (proof-output-atom $pid)))

(: proof-fact-output-by-id
   (-[semidet]-> Number (Statement KBContext Proof TV)))
(= (proof-fact-output-by-id $pid)
   (let $output (proof-output-atom-by-id $pid)
      (case $output (
         ((CPU $_formula $_arguments $_result)
            (empty))
         (($type $kb $proof $tv)
            (assemble-stored-runtime-fact
               $type $kb $proof $tv))
         ($_other (empty))))))

(: candidate-output-key
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       ProofOutputKey))
(= (candidate-output-key $term)
   (case $term (
      ((CPU $formula $arguments $result)
         (proof-output-key
            (quote (CPU $formula $arguments $result))))
      (($type $kb $_prf $_tv)
         (proof-output-key (quote ($type $kb))))
      ($_other (proof-output-key $term)))))

(: proof-output-key-by-id (-[semidet]-> Number ProofOutputKey))
(= (proof-output-key-by-id $pid)
   (candidate-output-key (proof-output-atom-by-id $pid)))

(: materialize-proof-refs (-[semidet]-> $term $term))
(= (materialize-proof-refs $term)
   (if (is-expr $term)
      (if (is-var (car-atom $term))
         (cons (car-atom $term)
            (proof-map-flat-semidet
               materialize-proof-refs (cdr-atom $term)))
         (case $term (
            ((proof-ref $pid)
               (materialize-proof-refs
                  (materialize-proof $pid)))
            ($_other
               (cons (materialize-proof-refs (car-atom $term))
                  (proof-map-flat-semidet
                     materialize-proof-refs (cdr-atom $term)))))))
      $term))

(: materialize-result-atom
   (-[semidet]-> (| Goal (Statement KBContext Proof TV))
       RuntimeResult))
(= (materialize-result-atom $atom)
   (case $atom (
      ((CPU $formula $arguments $result)
         (brand RuntimeResult
            (CPU $formula $arguments $result)))
      (($type $kb $prf $tv)
         (brand RuntimeResult
            (materialize-fact-result-atom $atom)))
      ($_other (brand RuntimeResult $atom)))))

(: materialize-fact-result-atom
   (-[semidet]-> (| Goal (Statement KBContext Proof TV))
       (Statement KBContext Proof TV)))
(= (materialize-fact-result-atom $atom)
   (case $atom
      ((($type $kb $prf $tv)
         (let $materialized (materialize-proof-refs $prf)
            (assemble-stored-runtime-fact
               $type $kb $materialized $tv))))))

(: materialize-proof-kind (-[semidet]-> ProofKind Number Proof))
(= (materialize-proof-kind (leaf $raw) $_pid)
   (case $raw (
      ((CPU $_fun $_args $_res) (brand Proof cpu))
      (($_type ($_kbid $_ctx $_vars) $prf $_tv)
         $prf)
      ($_other (brand Proof $raw)))))
(: aggregate-proof-label (-[semidet]-> $aggregate Proof))
(= (aggregate-proof-label (CPU FoldAllCompiled $args $_res))
   (brand Proof
      (case $args (
         (($_kb $_pattern $_extractor $_init OrFormula $_finish $_tv-mode)
            disjunction)
         ($_other foldall-proof)))))
(= (aggregate-proof-label (CPU GroupedFoldAllCompiled $args $_res))
   (brand Proof
      (case $args (
         (($_kb $_pattern $_group $_extractor $_init OrFormula $_finish $_tv-mode)
            disjunction)
         ($_other foldall-proof)))))
(: proof-ref-list (-[det]-> (List Number) (List ProofRef)))
(= (proof-ref-list ()) ())
(= (proof-ref-list (cons $pid $rest)) (cons (proof-ref $pid) (proof-ref-list $rest)))
(: aggregate-child-proof-tokens
   (-[semidet]-> (List Number) (List Proof)))
(= (aggregate-child-proof-tokens ()) ())
(= (aggregate-child-proof-tokens (cons $pid $rest))
   (let $output (proof-output-atom-by-id $pid)
      (if (or (= $output (CPU FoldAllCompiled $_args $_res)) (= $output (CPU GroupedFoldAllCompiled $_gargs $_gres)))
         (cons (materialize-proof $pid) (aggregate-child-proof-tokens $rest))
         (aggregate-child-proof-tokens $rest))))

(: ProofTokenReplacement Type)
(: proof-token-replacement
   (-[det]-> $term (List Proof) ProofTokenReplacement))

(: replace-cpu-proof-token-list
   (-[det]-> (List $term) (List Proof) ProofTokenReplacement))
(= (replace-cpu-proof-token-list () $proofs)
   (proof-token-replacement () $proofs))
(= (replace-cpu-proof-token-list (cons $head $tail) $proofs)
   (let*
      (((proof-token-replacement $new-head $proofs1)
          (replace-cpu-proof-token $head $proofs))
       ((proof-token-replacement $new-tail $proofs2)
          (replace-cpu-proof-token-list $tail $proofs1)))
      (proof-token-replacement
         (cons $new-head $new-tail) $proofs2)))
(: replace-cpu-proof-token
   (-[det]-> Atom (List Proof) ProofTokenReplacement))
(= (replace-cpu-proof-token $term $proofs)
   (if (is-var $term)
      (proof-token-replacement $term $proofs)
      (if (== $term cpu)
         (if (= $proofs (cons $proof $rest))
            (proof-token-replacement $proof $rest)
            (proof-token-replacement cpu ()))
         (if (is-expr $term)
            (let
               (proof-token-replacement $new-list $rest-proofs)
               (replace-cpu-proof-token-list
                  (the (List Atom) $term) $proofs)
               (proof-token-replacement $new-list $rest-proofs))
            (proof-token-replacement $term $proofs)))))
(: materialize-rule-token (-[semidet]-> Proof Number Proof))
(= (materialize-rule-token $prf $pid)
   (let*
      (($base-prf (materialize-proof-refs $prf))
       ($aggregate-proofs (aggregate-child-proof-tokens (proof-children-by-id $pid)))
       ((proof-token-replacement $new-prf $_unused)
          (replace-cpu-proof-token $base-prf $aggregate-proofs)))
      (brand Proof $new-prf)))
(= (materialize-proof-kind (aggregate $raw) $pid)
   (let $children (proof-children-by-id $pid)
      (brand Proof
         (if (== $children ()) cpu
            (cons (aggregate-proof-label $raw)
               (proof-map-flat-semidet materialize-proof-refs
                  (proof-ref-list $children)))))))
(= (materialize-proof-kind (merged $output) $_pid)
   (brand Proof
      (case $output (
         (($_type $_kb $prf $_tv)
            (materialize-proof-refs $prf))
         ($_other $output)))))
(: rule-kind-proof-token (-[det]-> Atom Proof))
(= (rule-kind-proof-token $term)
   (brand Proof
      (if (is-expr $term)
         (let $tail1 (cdr-atom $term)
            (if (== $tail1 ()) $term
               (let $tail2 (cdr-atom $tail1)
                  (if (== $tail2 ()) $term
                     (car-atom $tail2)))))
         $term)))
(: materialize-rule-expression (-[det]-> Proof Proof))
(= (materialize-rule-expression $rule-prf)
   (if (is-expr $rule-prf)
      (if (= (car-atom $rule-prf) (Implication $_premises $_conclusions))
         (if (== (cdr-atom (cdr-atom $rule-prf)) ())
            (brand Proof (car-atom (cdr-atom $rule-prf)))
            $rule-prf)
         $rule-prf)
      $rule-prf))
(= (materialize-proof-kind (rule $term) $pid)
   (let $prf (rule-kind-proof-token $term)
      (if (== $prf $term) $prf
         (let $rule-prf (materialize-rule-token $prf $pid)
            (materialize-rule-expression $rule-prf)))))

(: materialize-proof (-[semidet]-> Number Proof))
(= (materialize-proof $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_owner $_output $kind $_support $_children)
         (materialize-proof-kind $kind $pid))))

(: proof-output-satisfies-goal?
   (-[semidet]-> Number (| Goal (Statement KBContext Proof TV)) Bool))
(= (proof-output-satisfies-goal? $pid $goal)
   (let*
      (($result
         (materialize-result-atom
            (proof-output-atom-by-id $pid)))
       ($result-copy (copy_term $result))
       ($goal-copy (copy_term $goal)))
      (if (= $goal-copy $result-copy) true false)))

(: goal-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-proof-ids $gid)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_pending)
            (goal-by-id $gid))
          ($key (proof-goal-key-by-goal-id $gid))
          ($lookup-key (copy_term $key)))
      (collapse
         (match &proof_goal
            ($lookup-key $stored-key $pid)
            (if (=alpha $stored-key $key)
               (let $stored-pid (stored-number $pid)
                  (if (proof-output-satisfies-goal?
                         $stored-pid $goal)
                     $stored-pid
                     (empty)))
               (empty))))))

(: proof-goal-key-by-id (-[semidet]-> Number ProofGoalKey))
(= (proof-goal-key-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $owner $_output $_kind $_support $_children)
         (proof-owner-goal-key $owner))))

(: proof-children-by-id (-[semidet]-> Number (List Number)))
(= (proof-children-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_owner $_output $_kind $_support $children)
         $children)))

(: proof-kind-by-id (-[semidet]-> Number ProofKind))
(= (proof-kind-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_owner $_output $kind $_support $_children)
         $kind)))

(: materializable-proof-kind? (-[det]-> $kind Bool))
(= (materializable-proof-kind? $kind)
   (case $kind (((rule $_term) true) ($_other false))))

(: materializable-proof-tv? (-[det]-> $tv Bool))
(= (materializable-proof-tv? $tv)
   (if (is-var $tv)
      false
      (case $tv
         (((STV $_strength $_confidence)
             (== (extract-vars $tv) ()))
          ($_other false)))))

(: materializable-proof-output? (-[det]-> $output Bool))
(= (materializable-proof-output? $output)
   (case $output (
      (($type ($_kbid MAIN Nil) $_prf $tv)
         (if (== (extract-vars $type) ())
            (materializable-proof-tv? $tv)
            false))
      ($_other false))))

(: materialize-proof-node-to-kb (-[semidet]-> Number (List $none)))
(= (materialize-proof-node-to-kb $pid)
   (let*
      (($kind (proof-kind-by-id $pid))
       ($output (proof-output-atom-by-id $pid)))
      (if (materializable-proof-kind? $kind)
         (if (materializable-proof-output? $output)
            (let*
               (($fact (materialize-fact-result-atom $output))
                (($_score $ev) (proof-stats-by-id $pid))
                ($changes
                   (collapse
                      (once
                         (forward-candidate-upsert!
                            (forward-derived $fact $ev)))))
                ($change
                   (if (== $changes ()) no-forward-change
                      (car-atom $changes))))
               (progn
                  (forward-apply-unqueued-change! $change)
                  ()))
            ())
         ())))

(: materialize-proof-tree-to-kb (-[det]-> Number (List $none)))
(= (materialize-proof-tree-to-kb $pid)
   (let $_children (collapse (materialize-proof-list-to-kb (proof-children-by-id $pid)))
      (let $_node (collapse (materialize-proof-node-to-kb $pid))
         ())))

(: materialize-proof-list-to-kb (-[det]-> (List Number) (List $none)))
(= (materialize-proof-list-to-kb ()) ())
(= (materialize-proof-list-to-kb (cons $pid $rest))
   (let $_head (collapse (materialize-proof-tree-to-kb $pid))
      (materialize-proof-list-to-kb $rest)))

(: ProofLiveCacheRow Type)
(: proof-live-cache-row
   (-[det]-> Number Number Bool ProofLiveCacheRow))

(: GoalLiveCacheRow Type)
(: goal-live-cache-row
   (-[det]-> Number Number (List Number) GoalLiveCacheRow))

(: proof-live-cache-epoch (-[det]-> Number))
(= (proof-live-cache-epoch)
   (let $values
      (collapse (catch (get-state bwd_live_epoch)))
      (if (== $values ())
         0
         (if-error-number (car-atom $values) 0))))

(: invalidate-proof-live-caches (-[det]-> Bool))
(= (invalidate-proof-live-caches)
   (let $epoch (proof-live-cache-epoch)
      (change-state! bwd_live_epoch (+ $epoch 1))))

(: cache-proof-live! (-[det]-> Number Bool Bool))
(= (cache-proof-live! $pid $alive)
   (let $epoch (proof-live-cache-epoch)
      (once
         (add-atom &proof_live_cache
            (proof-live-cache-row $epoch $pid $alive)))))

(: cached-proof-live? (-[nondet]-> Number  Bool))
(= (cached-proof-live? $pid)
   (let $epoch (proof-live-cache-epoch)
      (match &proof_live_cache
         (proof-live-cache-row $epoch $pid $alive)
         $alive)))

(: goal-live-cache-store! (-[det]-> Number (List Number) Bool))
(= (goal-live-cache-store! $gid $pids)
   (let $epoch (proof-live-cache-epoch)
      (once
         (add-atom &goal_live_cache
            (goal-live-cache-row $epoch $gid $pids)))))

(: goal-live-cache-remove! (-[det]-> Number (List Number) Bool))
(= (goal-live-cache-remove! $gid $pids)
   (let $epoch (proof-live-cache-epoch)
      (let $removed
         (collapse
            (remove-atom &goal_live_cache
               (goal-live-cache-row $epoch $gid $pids)))
         (not (== $removed ())))))

(: cached-goal-live-proof-ids (-[nondet]-> Number  (List Number)))
(= (cached-goal-live-proof-ids $gid)
   (let $epoch (proof-live-cache-epoch)
      (match &goal_live_cache
         (goal-live-cache-row $epoch $gid $pids)
         $pids)))

(: append-goal-live-cache!
   (-[det]-> Number Number (| Bool (List $none))))
(= (append-goal-live-cache! $gid $pid)
   (let*
      (($epoch (proof-live-cache-epoch))
       ($hits
          (collapse
             (once
                (match &goal_live_cache
                   (goal-live-cache-row $epoch $gid $pids)
                   $pids)))))
      (if (== $hits ())
         ()
         (let*
            (($pids (car-atom $hits))
             ($npids (append-number $pids $pid)))
            (progn
               (goal-live-cache-remove! $gid $pids)
               (goal-live-cache-store! $gid $npids))))))

(: register-proof-parent-edge!
   (-[det]-> Number Number (| Bool (List $none))))
(= (register-proof-parent-edge! $parent-pid $child-pid)
   (once
      (add-atom &proof_parent ($child-pid $parent-pid))))

(: register-proof-parent-edges!
   (-[det]-> Number (List Number) (List $none)))
(= (register-proof-parent-edges! $parent-pid $children)
   (foreach-flat
      (register-proof-parent-edge! $parent-pid)
      $children))

(: invalidate-proof-dependent-step
   (-[semidet]-> Number Number (List $none)))

(: remove-proof-live-cache-row!
   (-[det]-> ProofLiveCacheRow Bool))
(= (remove-proof-live-cache-row! $row)
   (remove-atom &proof_live_cache $row))

(: remove-goal-live-cache-row!
   (-[det]-> GoalLiveCacheRow Bool))
(= (remove-goal-live-cache-row! $row)
   (remove-atom &goal_live_cache $row))

(: invalidate-proof-dependent! (-[semidet]-> Number Number (List $none)))
(= (invalidate-proof-dependent! $epoch $parent-pid)
   (let $seen
      (collapse
         (once
            (match &proof_invalidated_epoch (($epoch $parent-pid)) true)))
      (if (not (== $seen ())) ()
         (let*
            (($_mark
                (once
                   (add-atom &proof_invalidated_epoch
                      (($epoch $parent-pid)))))
             ($_proof-cache
                (foreach-flat
                   remove-proof-live-cache-row!
                   (collapse
                      (match &proof_live_cache
                         (proof-live-cache-row
                            $epoch $parent-pid $alive)
                         (proof-live-cache-row
                            $epoch $parent-pid $alive)))))
             ($_goal-cache
                (foreach-flat
                   remove-goal-live-cache-row!
                   (collapse
                      (match &goal_live_cache
                         (goal-live-cache-row
                            $epoch $_gid $pids)
                         (goal-live-cache-row
                            $epoch $_gid $pids)))))
             ($_parents
                (foreach-flat
                   (invalidate-proof-dependent-step $epoch)
                   (collapse
                      (match &proof_parent ($parent-pid $dependent-pid)
                         (stored-number $dependent-pid))))))
            ()))))

(= (invalidate-proof-dependent-step $epoch $parent-pid)
   (invalidate-proof-dependent! $epoch $parent-pid))

(: invalidate-proof-dependents!
   (-[semidet]-> Number Number (List $none)))
(= (invalidate-proof-dependents! $epoch $child-pid)
   (foreach-flat
      (invalidate-proof-dependent-step $epoch)
      (collapse
         (match &proof_parent ($child-pid $parent-pid)
            (stored-number $parent-pid)))))

(: latest-proof-id (-[semidet]-> (List Number) Number))
(= (latest-proof-id (cons $pid $rest))
   (fold-flat max $pid $rest))

(: latest-proof-output-group-ids
   (-[semidet]-> (List ProofOutputGroup) (List Number)))
(= (latest-proof-output-group-ids ()) ())
(= (latest-proof-output-group-ids
      (cons (proof-output-group $_key $pids) $rest))
   (cons (latest-proof-id $pids)
      (latest-proof-output-group-ids $rest)))

(: aggregate-current-pid-live?
   (-[det]-> (| Number (List Number)) Number Bool))
(= (aggregate-current-pid-live? $current-pid $pid)
   (if (== $current-pid ()) false
      (if (is-expr $current-pid)
         (not (== (collapse (is-member $pid $current-pid)) ()))
         (== $current-pid $pid))))

;; Membership only compares stored ids, so it does not need to revalidate each
;; numeric element from the erased aggregate row.
(: stored-list-member? (-[det]-> Atom Atom Bool))
(= (stored-list-member? $needle $values)
   (case $values (
      (() false)
      ((cons $first $rest)
         (if (== $needle $first) true
            (stored-list-member? $needle $rest)))
      ($_other false))))

(: first-aggregate-current-pid
   (-[semidet]-> (List (| Number (List Number)))
       (| Number (List Number))))
(= (first-aggregate-current-pid (cons $current $_rest))
   $current)

(: proof-ids-for-goal-key
   (-[semidet]-> ProofGoalKey (List Number)))
(= (proof-ids-for-goal-key $key)
   (let $lookup-key (copy_term $key)
      (collapse
         (match &proof_goal
            ($lookup-key $stored-key $pid)
            (if (=alpha $stored-key $key)
               (stored-number $pid)
               (empty))))))

(: durable-aggregate-representative? (-[semidet]-> Number Bool))
(= (durable-aggregate-representative? $pid)
   (let $latest
      (latest-proof-output-group-ids
         (aggregate-snapshot-groups
            (proof-ids-for-goal-key
               (proof-goal-key-by-id $pid))))
      (stored-list-member? $pid $latest)))

(: proof-live-compute (-[semidet]-> Number Bool))
(= (proof-live-compute $pid)
   (let*
      (($key (proof-goal-key-by-id $pid))
       ($kind (proof-kind-by-id $pid))
       ($current-hits
          (collapse
             (once
                (match &aggregate
                   (stored-aggregate-row
                      $gid $_child $_args
                      $_base $_pending $current-pid)
                   (if (=alpha
                          (proof-goal-key-by-goal-id $gid) $key)
                      $current-pid
                      (empty)))))))
      (if (== $current-hits ())
         (if (= $kind (aggregate $_output))
            (if (durable-aggregate-representative? $pid)
               (proof-list-live? (proof-children-by-id $pid))
               false)
            (if (= $kind (merged $_output))
            (proof-list-node-live? (proof-children-by-id $pid))
            (if (proof-kind-keeps-raw-children? $kind)
               (proof-list-node-live? (proof-children-by-id $pid))
               (proof-list-live? (proof-children-by-id $pid)))))
         (aggregate-current-pid-live?
            (first-aggregate-current-pid $current-hits) $pid))))

;; A conjunction dependency records one specific compatible combination of
;; premise proofs. It remains valid when another derivation later changes a
;; child's revised representative. Other rule applications consume revised
;; child evidence and therefore become stale with that representative.
(: proof-term-conjunction-dependency? (-[det]-> Proof Bool))
(= (proof-term-conjunction-dependency? $proof)
   (if (is-expr $proof)
      (if (== $proof ()) false
         (if (== (car-atom $proof) conjunction) true
            (case $proof (
               ((by $_rule $dependency)
                  (proof-term-conjunction-dependency?
                     (brand Proof $dependency)))
               ((negated $inner)
                  (proof-term-conjunction-dependency?
                     (brand Proof $inner)))
               ($_other false)))))
      false))

(: proof-kind-keeps-raw-children? (-[det]-> ProofKind Bool))
(= (proof-kind-keeps-raw-children? $kind)
   (case $kind (
      ((rule ($_type $_kb $proof $_tv))
         (proof-term-conjunction-dependency?
            (brand Proof $proof)))
      ($_other false))))

;; A merged representative owns its raw alternatives, so those children only
;; need to remain valid proof nodes. Supersession invalidates ordinary revised
;; parents; conjunction dependencies deliberately ignore the marker.
(: proof-list-node-live? (-[semidet]-> (List Number) Bool))
(= (proof-list-node-live? ())
   true)
(= (proof-list-node-live? (cons $pid $rest))
   (if (proof-live? $pid)
      (proof-list-node-live? $rest)
      false))

(: proof-current-representative? (-[det]-> Number Bool))
(= (proof-current-representative? $pid)
   (== (collapse (once (match &proof_superseded ($pid) true))) ()))

(: proof-list-live? (-[semidet]-> (List Number) Bool))
(= (proof-list-live? ())
   true)
(= (proof-list-live? (cons $pid $rest))
   (if (proof-live? $pid)
      (if (proof-current-representative? $pid)
         (proof-list-live? $rest)
         false)
      false))

(: proof-statically-live? (-[det]-> Number Bool))
(= (proof-statically-live? $pid)
   (not (== (collapse (once (match &proof_static_live ($pid) true))) ())))

(: mark-proof-static!
   (-[det]-> Number Number ProofKind (List Number) (| Bool (List $none))))
(= (mark-proof-static! $gid $pid $kind $children)
   (if (= $kind (aggregate $_term)) ()
      (if (== $children ())
         (if (==
                (collapse
                   (once
                      (match &aggregate
                         (stored-aggregate-row
                            $gid $_child $_args
                            $_base $_pending $_current)
                         true)))
                ())
            (once
               (add-atom &proof_static_live ($pid)))
            ())
         ())))

(: proof-live? (-[semidet]-> Number Bool))
(= (proof-live? $pid)
   (if (proof-statically-live? $pid) true
      (let*
         (($hits (collapse (once (cached-proof-live? $pid)))))
         (if (== $hits ())
            (let*
               (($alive (proof-live-compute $pid))
                ($_cache (cache-proof-live! $pid $alive)))
               $alive)
            (car-atom $hits)))))

(: goal-live-proof-step
   (-[semidet]-> (List Number) Number (List Number)))
(= (goal-live-proof-step $acc $pid)
   (if (proof-live? $pid)
      (append-number $acc $pid)
      $acc))

(: append-number
   (-[det]-> (List Number) Number (List Number)))
(= (append-number () $value) (cons $value ()))
(= (append-number (cons $first $rest) $value)
   (cons $first (append-number $rest $value)))

(: append-numbers
   (-[det]-> (List Number) (List Number) (List Number)))
(= (append-numbers () $right) $right)
(= (append-numbers (cons $first $rest) $right)
   (cons $first (append-numbers $rest $right)))

(: goal-live-proof-ids-compute (-[semidet]-> Number (List Number)))
(= (goal-live-proof-ids-compute $gid)
   (proof-fold-flat-semidet
      goal-live-proof-step () (goal-live-source-proof-ids $gid)))

(: goal-live-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-live-proof-ids $gid)
   (let*
      (($hits (collapse (once (cached-goal-live-proof-ids $gid)))))
      (if (== $hits ())
         (let*
            (($pids (goal-live-proof-ids-compute $gid))
             ($_cache (goal-live-cache-store! $gid $pids)))
            $pids)
         (car-atom $hits))))

(: proof-output-groups-add
   (-[semidet]-> (List ProofOutputGroup) Number (List ProofOutputGroup)))
(= (proof-output-groups-add () $pid)
   (cons (proof-output-group (proof-output-key-by-id $pid) ($pid)) ()))
(= (proof-output-groups-add (cons (proof-output-group $key $pids) $rest) $pid)
   (let $pid-key (proof-output-key-by-id $pid)
      (if (=alpha $pid-key $key)
         (cons
            (proof-output-group $key (append-number $pids $pid))
            $rest)
         (cons (proof-output-group $key $pids) (proof-output-groups-add $rest $pid)))))

(: proof-output-groups
   (-[semidet]-> (List Number) (List ProofOutputGroup)))
(= (proof-output-groups $pids)
   (proof-fold-flat-semidet proof-output-groups-add () $pids))

;; Aggregate values change as monotonic child proofs arrive. Their ordinary
;; proof output key includes the result so distinct CPU values are never merged;
;; snapshot selection instead keys FoldAll by its stable arguments and grouped
;; FoldAll by its grounded group arguments, ignoring only the changing result.
(: aggregate-snapshot-key-by-id (-[semidet]-> Number ProofOutputKey))
(= (aggregate-snapshot-key-by-id $pid)
   (let $output (proof-output-atom-by-id $pid)
      (case $output (
         ((CPU FoldAllCompiled $arguments $_result)
            (proof-output-key
               (quote (CPU FoldAllCompiled $arguments))))
         ((CPU GroupedFoldAllCompiled $arguments $_result)
            (proof-output-key
               (quote (CPU GroupedFoldAllCompiled $arguments))))
         ($_other (candidate-output-key $output))))))

(: aggregate-snapshot-groups-add
   (-[semidet]-> (List ProofOutputGroup) Number
       (List ProofOutputGroup)))
(= (aggregate-snapshot-groups-add () $pid)
   (cons
      (proof-output-group (aggregate-snapshot-key-by-id $pid) ($pid))
      ()))
(= (aggregate-snapshot-groups-add
      (cons (proof-output-group $key $pids) $rest) $pid)
   (let $pid-key (aggregate-snapshot-key-by-id $pid)
      (if (=alpha $pid-key $key)
         (cons
            (proof-output-group $key (append-number $pids $pid))
            $rest)
         (cons (proof-output-group $key $pids)
            (aggregate-snapshot-groups-add $rest $pid)))))

(: aggregate-snapshot-groups
   (-[semidet]-> (List Number) (List ProofOutputGroup)))
(= (aggregate-snapshot-groups $pids)
   (proof-fold-flat-semidet aggregate-snapshot-groups-add () $pids))

(: aggregate-goal? (-[semidet]-> Number Bool))
(= (aggregate-goal? $gid)
   (let
      (stored-goal-row $_stored-gid $_depth $goal $_expanded $_pending)
      (goal-by-id $gid)
      (case $goal (
         ((CPU FoldAllCompiled $_arguments $_result) true)
         ((CPU GroupedFoldAllCompiled $_arguments $_result) true)
         ($_other false)))))

(: aggregate-execution-row? (-[det]-> Number Bool))
(= (aggregate-execution-row? $gid)
   (not
      (==
         (collapse
            (once
               (match &aggregate
                  (stored-aggregate-row
                     $gid $_child $_args $_base $_pending $_current)
                  true)))
         ())))

(: goal-live-source-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-live-source-proof-ids $gid)
   (let $pids (goal-proof-ids $gid)
      (if (aggregate-goal? $gid)
         (if (aggregate-execution-row? $gid)
            $pids
            (latest-proof-output-group-ids
               (aggregate-snapshot-groups $pids)))
         $pids)))

(: merge-proof-id-output-step
   (-[semidet]-> (Statement KBContext Proof TV)
       Number (Statement KBContext Proof TV)))
(= (merge-proof-id-output-step $acc $pid)
   (merge-proof-atoms $acc (proof-fact-output-by-id $pid)))
