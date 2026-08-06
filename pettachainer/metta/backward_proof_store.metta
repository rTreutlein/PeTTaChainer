(: goal-by-id
   (-[semidet]-> Number StoredGoalRow))
(= (goal-by-id $gid)
   (once
      (match &goal
         (stored-goal-row
            $gid $depth $goal $expanded $pending)
         (stored-goal-row
            $gid $depth $goal $expanded $pending))))

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

(: replace-runtime-proof
   (-[det]-> (Statement KBContext Proof TV) Number
       (Statement KBContext Proof TV)))
(= (replace-runtime-proof ($type $kb $_proof $tv) $pid)
   (quote
      ($type $kb (brand Proof (proof-ref $pid)) $tv)))

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
         $pid $_gid $output $_kind $_score $_ev $_children)
      $output))

(: proof-output-atom-by-id
   (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))))
(= (proof-output-atom-by-id $pid)
   (once (proof-output-atom $pid)))

(: proof-fact-output-by-id
   (-[semidet]-> Number (Statement KBContext Proof TV)))
(= (proof-fact-output-by-id $pid)
   (let $output (proof-output-atom-by-id $pid)
      (case $output
         ((($type $kb $proof $tv)
            (assemble-stored-runtime-fact
               $type $kb $proof $tv))))))

(: candidate-output-key
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       ProofOutputKey))
(= (candidate-output-key $term)
   (case $term (
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
            $pid $_gid $_output $kind $_score $_ev $_children)
         (materialize-proof-kind $kind $pid))))

(: goal-proof-ids (-[det]-> Number (List Number)))
(= (goal-proof-ids $gid)
   (collapse
      (match &proof
         (stored-proof-row
            $pid $gid $_output $_kind $_score $_ev $_children)
         $pid)))

(: proof-goal-id (-[semidet]-> Number (| Number MergedProofGroup)))
(= (proof-goal-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $gid $_output $_kind $_score $_ev $_children)
         (case $gid
            (((merged-proof-group $source-gid)
               (merged-proof-group $source-gid))
             ($number $number))))))

(: proof-children-by-id (-[semidet]-> Number (List Number)))
(= (proof-children-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_gid $_output $_kind $_score $_ev $children)
         $children)))

(: proof-kind-by-id (-[semidet]-> Number ProofKind))
(= (proof-kind-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_gid $_output $kind $_score $_ev $_children)
         $kind)))

(: materializable-proof-kind? (-[det]-> $kind Bool))
(= (materializable-proof-kind? $kind)
   (case $kind (((rule $_term) true) ($_other false))))

(: materializable-proof-output? (-[det]-> $output Bool))
(= (materializable-proof-output? $output)
   (case $output (
      (($type ($_kbid MAIN Nil) $_prf $_tv) (== (extract-vars $type) ()))
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

(: materialize-goal-proofs-to-kb (-[det]-> Number (List $none)))
(= (materialize-goal-proofs-to-kb $gid)
   (let $_materialized (collapse (materialize-proof-list-to-kb (goal-live-proof-ids $gid)))
      ()))

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
            (($gid (proof-goal-id $parent-pid))
             ($_mark
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
                            $epoch $gid $pids)
                         (goal-live-cache-row
                            $epoch $gid $pids)))))
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

(: aggregate-current-pid-live?
   (-[det]-> (| Number (List Number)) Number Bool))
(= (aggregate-current-pid-live? $current-pid $pid)
   (case $current-pid (
      (() false)
      ((cons $first $rest)
         (stored-list-member? $pid (cons $first $rest)))
      ($number (== $number $pid)))))

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

(: proof-live-compute (-[semidet]-> Number Bool))
(= (proof-live-compute $pid)
   (let*
      (($gid (proof-goal-id $pid))
       ($kind (proof-kind-by-id $pid))
       ($current-hits
          (collapse
             (once
                (match &aggregate
                   (stored-aggregate-row
                      $gid $_child $_args
                      $_base $_pending $current-pid)
                   $current-pid)))))
      (if (== $current-hits ())
         (if (= $kind (merged $_output))
            (proof-list-node-live? (proof-children-by-id $pid))
            (if (proof-kind-keeps-raw-children? $kind)
               (proof-list-node-live? (proof-children-by-id $pid))
               (proof-list-live? (proof-children-by-id $pid))))
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
   (-[det]-> (| Number MergedProofGroup) Number ProofKind (List Number) (| Bool (List $none))))
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
      goal-live-proof-step () (goal-proof-ids $gid)))

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

(: merge-proof-id-output-step
   (-[semidet]-> (Statement KBContext Proof TV)
       Number (Statement KBContext Proof TV)))
(= (merge-proof-id-output-step $acc $pid)
   (merge-proof-atoms $acc (proof-fact-output-by-id $pid)))

;; ---------------------------------------------------------------------------
;; Lifting-merge: when several proofs of one grounded output share a premise,
;; pool them by factoring the shared premise out, revising the independent
;; residual implications, and re-applying the premise once. This recovers the
;; confidence that dominance would otherwise discard. The formula that produced
;; each proof's TV is already in the store (its CPU formula children), so a
;; proof is re-evaluated structurally with one leaf fact overridden. Exact for
;; standard implication-shaped proofs (premises -> And-fold -> CTVModusPonensFormula); any
;; other shape disables factoring for the group (revision/dominance instead).
;; ---------------------------------------------------------------------------

(: factor-cpu-child? (-[semidet]-> Number Bool))
(= (factor-cpu-child? $pid)
   (if (= (proof-output-atom-by-id $pid) (CPU $_f $_a $_r))
      true false))
(: factor-split-pc
   (-[semidet]-> (List Number) (List Number) (List Number)
       ((List Number) (List Number))))
(= (factor-split-pc () $p $c) ($p $c))
(= (factor-split-pc (cons $pid $rest) $p $c)
   (if (factor-cpu-child? $pid)
      (factor-split-pc $rest $p (append-number $c $pid))
      (factor-split-pc $rest (append-number $p $pid) $c)))
(: factor-last (-[semidet]-> (List Number) Number))
(= (factor-last (cons $x $rest))
   (if (== $rest ()) $x (factor-last $rest)))
(: factor-find-ctv
   (-[det]-> (List TV) (| CTVType NoCTV)))
(= (factor-find-ctv $values)
   (case $values (
      (() no-ctv)
      ((cons $a $rest)
         (case $a
            (((CTV $pos $neg) (CTV $pos $neg))
             ($_other (factor-find-ctv $rest)))))
      ($_other no-ctv))))
(: factor-and-fold
   (-[semidet]-> (List STVType) STVType))
(= (factor-and-fold (cons $tv $rest))
   (if (== $rest ()) $tv (AndFormula $tv (factor-and-fold $rest))))

(: factor-key-in?
   (-[det]-> ProofOutputKey (List ProofOutputKey) Bool))
(= (factor-key-in? $_k ()) false)
(= (factor-key-in? $k (cons $h $rest)) (if (=alpha $k $h) true (factor-key-in? $k $rest)))

(: factor-reeval-premises
   (-[semidet]-> (List Number) (List ProofOutputKey)
      TV (List STVType)))
(= (factor-reeval-premises () $_keys $_o) ())
(= (factor-reeval-premises (cons $pid $rest) $keys $o)
   (cons
      (the STVType (factor-reeval $pid $keys $o))
      (factor-reeval-premises $rest $keys $o)))

;; structural recompute: fold premise proofs (by child position) and re-apply ctv,
;; with every shared leaf (any key in $keys) overridden to $o
(: factor-reeval-rule
   (-[semidet]-> Number (List ProofOutputKey)
      TV TV  TV))
(= (factor-reeval-rule $pid $keys $o $stored)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) $stored
         (let* (((CPU $lf $la $_r)
                    (proof-output-atom-by-id (factor-last $cpu)))
                ($ctv
                   (factor-find-ctv
                      (the (List TV) $la))))
            (if (== $lf CTVModusPonensFormula)
               (case $ctv
                  (((CTV $pos $neg)
                      (CTVModusPonensFormula
                         (factor-and-fold
                            (factor-reeval-premises
                               $prem $keys $o))
                         (CTV $pos $neg)))
                   (no-ctv $stored)))
               $stored)))))

(: factor-reeval
   (-[semidet]-> Number (List ProofOutputKey) TV  TV))
(= (factor-reeval $pid $keys $o)
   (let $out (proof-output-atom-by-id $pid)
      (case $out (
         ((CPU $_formula $_arguments $_result)
            (empty))
         (($t $kb $prf $tv)
            (let $stored $tv
               (if
                  (factor-key-in?
                     (candidate-output-key $out) $keys)
                  $o
                  (factor-reeval-rule
                     $pid $keys $o $stored))))
         ($_other
            (empty))))))

(: factor-proof? (-[semidet]-> Number Bool))
(= (factor-proof? $pid)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) true
         (let* (((CPU $lf $la $_r)
                    (proof-output-atom-by-id (factor-last $cpu)))
                ($ctv
                   (factor-find-ctv
                      (the (List TV) $la))))
            (if (== $lf CTVModusPonensFormula)
               (if (== $ctv no-ctv) false
                  (factor-all? $prem))
               false)))))
(: factor-all? (-[semidet]-> (List Number) Bool))
(= (factor-all? ()) true)
(= (factor-all? (cons $pid $rest))
   (if (factor-proof? $pid)
      (factor-all? $rest)
      false))

(: factor-pid-facts (-[semidet]-> Number (List Evidence)))
(= (factor-pid-facts $pid)
   (fact-evidence-only
      (snd (proof-stats-by-id $pid))))

(: factor-shared-facts-step
   (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (factor-shared-facts-step $acc $pid)
   (evidence-intersection $acc (factor-pid-facts $pid)))

(: factor-shared-facts
   (-[semidet]-> (List Number) (List Evidence)))
(= (factor-shared-facts (cons $pid $rest))
   (proof-fold-flat-semidet
      factor-shared-facts-step
      (factor-pid-facts $pid) $rest))
(: factor-fact-key (-[semidet]-> Evidence ProofOutputKey))
(= (factor-fact-key (fact-ev $kb $prf $type))
   (proof-output-key (quote ($type $kb))))

;; the shared premise's actual TV, found in the proof DAG by output key
(: factor-checked-tv (-[det]-> $value TV))
(= (factor-checked-tv $tv) (the TV $tv))

(: factor-leaf-tv-work
   (-[semidet]-> (List Number) ProofOutputKey (| TV NoTV)))
(= (factor-leaf-tv-work () $_key) no-tv)
(= (factor-leaf-tv-work (cons $pid $rest) $key)
   (let $out (proof-output-atom-by-id $pid)
      (case $out (
         (($t $kb $prf $tv)
            (if (=alpha (candidate-output-key $out) $key)
               (factor-checked-tv $tv)
               (factor-leaf-tv-work
                  (append-numbers
                     (proof-children-by-id $pid) $rest) $key)))
         ($_other
            (factor-leaf-tv-work
               (append-numbers
                  (proof-children-by-id $pid) $rest) $key))))))

(: factor-leaf-tv
   (-[semidet]-> Number ProofOutputKey (| TV NoTV)))
(= (factor-leaf-tv $pid $key)
   (factor-leaf-tv-work ($pid) $key))

;; Residual of a proof w.r.t. the shared facts: probe their conjunction at
;; strength 1 (all shared leaves -> (1 1)) and 0 (all -> (0 1)). The conclusion
;; is linear in the shared conjunction's strength, so these two points give the
;; residual implication (conjunction-of-shared -> conclusion).
(: factor-revise-ctv
   (-[semidet]-> CTVType CTVType CTVType))
(= (factor-revise-ctv (CTV $p1 $n1) (CTV $p2 $n2)) (CTV (mergetvs $p1 $p2) (mergetvs $n1 $n2)))
(: factor-residual
   (-[semidet]-> Number (List ProofOutputKey) CTVType))
(= (factor-residual $pid $keys)
   (CTV
      (the STVType
         (factor-reeval $pid $keys (STV 1.0 1.0)))
      (the STVType
         (factor-reeval $pid $keys (STV 0.0 1.0)))))
(: factor-revise-residuals
   (-[semidet]-> (List Number) (List ProofOutputKey) CTVType))
(= (factor-revise-residuals (cons $pid ()) $keys) (factor-residual $pid $keys))
(= (factor-revise-residuals
      (cons $pid (cons $next $rest)) $keys)
   (factor-revise-ctv
      (factor-residual $pid $keys)
      (factor-revise-residuals
         (cons $next $rest) $keys)))

;; the shared facts' keys, and their real conjunction TV (And-fold of leaf TVs)
(: factor-shared-keys
   (-[semidet]-> (List Evidence) (List ProofOutputKey)))
(= (factor-shared-keys ()) ())
(= (factor-shared-keys (cons $f $rest)) (cons (factor-fact-key $f) (factor-shared-keys $rest)))
(: factor-required-leaf-tv
   (-[semidet]-> Number ProofOutputKey STVType))
(= (factor-required-leaf-tv $pid $key)
   (the STVType (factor-leaf-tv $pid $key)))
(: factor-real-conj
   (-[semidet]-> Number (List ProofOutputKey) STVType))
(= (factor-real-conj $pid (cons $key ()))
   (factor-required-leaf-tv $pid $key))
(= (factor-real-conj $pid (cons $key (cons $next $rest)))
   (AndFormula
      (factor-required-leaf-tv $pid $key)
      (factor-real-conj $pid (cons $next $rest))))

;; round-trip check: re-applying a proof's residual to the real shared
;; conjunction must reproduce its stored strength. The 2-point probe captures
;; the conclusion's linear dependence on the shared conjunction exactly, so the
;; strength round-trips when the shared facts enter through one conjunction and
;; fails (disabling factoring) when they enter through different conjunctions.
;; Only strength is checked: confidence is non-linear under idealized
;; propagation, so the residual's re-derived branch confidences never reproduce
;; the stored confidence exactly -- checking it would reject every valid group.
(: factor-abs-diff (-[det]-> Number Number Number))
(= (factor-abs-diff $x $y) (let $d (- $x $y) (if (< $d 0.0) (- 0.0 $d) $d)))
(: factor-close? (-[det]-> Number Number Bool))
(= (factor-close? $x $y) (< (factor-abs-diff $x $y) 0.000001))
;; single clause: a bare catch-all (= (factor-tv-close? $a $b) false) would also
;; match the (STV STV) case and make the result non-deterministic.
(: factor-tv-close? (-[det]-> TV TV Bool))
(= (factor-tv-close? $a $b)
   (if (= $a (STV $sa $_ca))
      (if (= $b (STV $sb $_cb))
         (factor-close? $sa $sb)
         false)
      false))
(: factor-roundtrip-one?
   (-[semidet]-> Number (List ProofOutputKey) STVType Bool))
(= (factor-roundtrip-one? $pid $keys $conj)
   (let* ((($_t $_k $_p $stored) (proof-output-atom-by-id $pid))
          ($residuals
             (collapse (once (factor-residual $pid $keys)))))
      (if (== $residuals ()) false
         (let $rebuilt
            (CTVModusPonensFormula $conj
               (car-atom $residuals))
            (factor-tv-close? (the TV $stored) $rebuilt)))))
(: factor-roundtrips?
   (-[semidet]-> (List Number) (List ProofOutputKey)
       STVType Bool))
(= (factor-roundtrips? () $_keys $_conj) true)
(= (factor-roundtrips? (cons $pid $rest) $keys $conj)
   (if (factor-roundtrip-one? $pid $keys $conj)
      (factor-roundtrips? $rest $keys $conj)
      false))

(: factor-ref-of (-[semidet]-> Number Proof))
(= (factor-ref-of $pid)
   (let ($_t $_k $prf $_tv)
      (proof-output-atom-by-id $pid)
      (brand Proof $prf)))
(: factor-merged-prf (-[semidet]-> (List Number) Proof))
(= (factor-merged-prf (cons $pid ())) (factor-ref-of $pid))
(= (factor-merged-prf (cons $pid (cons $next $rest)))
   (brand Proof
      (merge/revision
         (factor-ref-of $pid)
         (factor-merged-prf (cons $next $rest)))))

;; Each proof's residual evidence (full evidence minus the shared facts) must be
;; pairwise disjoint, otherwise the proofs are not independent given the shared
;; premise -- e.g. two derivations that also share an uncertain rule, or one
;; whose evidence subsumes another's -- and pooling them would double count.
;; Such groups fall back to revision/dominance.
(: factor-residual-ev
   (-[semidet]-> Number (List Evidence) (List Evidence)))
(= (factor-residual-ev $pid $shared)
   (let ($_score $ev) (proof-stats-by-id $pid)
      (evidence-subtraction $ev $shared)))
(: factor-residual-evs
   (-[semidet]-> (List Number) (List Evidence)
       (List (List Evidence))))
(= (factor-residual-evs () $_shared) ())
(= (factor-residual-evs (cons $pid $rest) $shared)
   (cons (factor-residual-ev $pid $shared) (factor-residual-evs $rest $shared)))
(: factor-disjoint-from-all?
   (-[det]-> (List Evidence) (List (List Evidence)) Bool))
(= (factor-disjoint-from-all? $_ev ()) true)
(= (factor-disjoint-from-all? $ev (cons $other $rest))
   (if (== (evidence-intersection $ev $other) ())
      (factor-disjoint-from-all? $ev $rest)
      false))
(: factor-pairwise-disjoint?
   (-[det]-> (List (List Evidence)) Bool))
(= (factor-pairwise-disjoint? ()) true)
(= (factor-pairwise-disjoint? (cons $ev $rest))
   (if (factor-disjoint-from-all? $ev $rest)
      (factor-pairwise-disjoint? $rest)
      false))

;; Pool a group when: it shares at least one fact, every proof is standard
;; implication-shaped, the residual evidence sets are pairwise disjoint, and the
;; residuals round-trip (the shared facts factor through one conjunction).
(: group-factorable? (-[semidet]-> (List Number) Bool))
(= (group-factorable? ()) false)
(= (group-factorable? (cons $first-pid $rest-pids))
   (let $pids (cons $first-pid $rest-pids)
   (let* (($shared (factor-shared-facts $pids))
          ($keys (factor-shared-keys $shared)))
      (if (== $shared ()) false
         (if (factor-all? $pids)
            (if
               (factor-pairwise-disjoint?
                  (factor-residual-evs $pids $shared))
               (factor-roundtrips?
                  $pids $keys
                  (factor-real-conj $first-pid $keys))
               false)
            false)))))

(: factor-merge-output
   (-[semidet]-> (List Number) (Statement KBContext Proof TV)))
(= (factor-merge-output (cons $first-pid $rest-pids))
   (let* (($pids (cons $first-pid $rest-pids))
          ($keys (factor-shared-keys (factor-shared-facts $pids)))
          ($conj (factor-real-conj $first-pid $keys))
          ($pooled (once (factor-revise-residuals $pids $keys)))
          ($merged-tv (CTVModusPonensFormula $conj $pooled))
          (($type $kb $_p $_t) (proof-output-atom-by-id $first-pid)))
      (let $merged-prf (factor-merged-prf $pids)
         (assemble-runtime-fact
            (brand Statement $type)
            (brand KBContext $kb)
            $merged-prf $merged-tv))))

(: merge-proof-id-output
   (-[semidet]-> (List Number)
       (| Goal (Statement KBContext Proof TV))))
(= (merge-proof-id-output (cons $pid $rest))
   ;; `and` is eager here.  Keep the singleton check outside it so a lone
   ;; cached derivation is never sent through multi-proof factoring: its leaf
   ;; provenance may refer to upstream facts which are intentionally absent
   ;; from this proof node's child list.
   (if (== $rest ())
      (proof-output-atom-by-id $pid)
      (if (group-factorable? (cons $pid $rest))
         (factor-merge-output (cons $pid $rest))
         (proof-fold-flat-semidet merge-proof-id-output-step
            (proof-fact-output-by-id $pid) $rest))))

(: proof-id-evidence-step
   (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (proof-id-evidence-step $acc $pid)
   (let ($_score $ev) (proof-stats-by-id $pid)
      (list_to_set (append-evidence $acc $ev))))

(: proof-id-evidence-list
   (-[semidet]-> (List Number) (List Evidence)))
(= (proof-id-evidence-list $pids)
   (proof-fold-flat-semidet proof-id-evidence-step () $pids))

(: proof-output-group-representative-pid
   (-[semidet]-> Number ProofOutputGroup Number))
(= (proof-output-group-representative-pid $gid (proof-output-group $_key $pids))
   (case $pids (
      ((cons $pid ()) $pid)
      ($_
         (let*
            (($output (merge-proof-id-output $pids))
             ($score (term-confidence $output))
             ($ev (proof-id-evidence-list $pids))
             ($hits
                (collapse
                   (once
                      (match &proof
                         (stored-proof-row
                            $stored-pid (merged-proof-group $gid)
                            $output (merged $output) $score $ev $pids)
                         $stored-pid)))))
            (if (== $hits ())
               (let*
                   (($pid (next-pid))
                   ($_store
                      (once
                         (chainer-add-atom &proof
                            (stored-proof-row
                               $pid (merged-proof-group $gid) $output
                               (merged $output) $score $ev $pids))))
                   ($_static (mark-proof-static! (merged-proof-group $gid) $pid (merged $output) $pids))
                   ($_parents (register-proof-parent-edges! $pid $pids)))
                  $pid)
               (car-atom $hits)))))))

(: proof-output-group-representative-pids
   (-[semidet]-> Number (List ProofOutputGroup) (List Number)))
(= (proof-output-group-representative-pids $_gid ()) ())
(= (proof-output-group-representative-pids $gid (cons $group $rest))
   (cons (proof-output-group-representative-pid $gid $group)
      (proof-output-group-representative-pids $gid $rest)))

(: goal-merged-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-merged-proof-ids $gid)
   (proof-output-group-representative-pids $gid
      (proof-output-groups (goal-live-proof-ids $gid))))

(: proof-output-group-for-key-step
   (-[semidet]-> ProofOutputKey
       (List Number) Number (List Number)))
(= (proof-output-group-for-key-step $key $pids $pid)
   (if (=alpha (proof-output-key-by-id $pid) $key)
      (append-number $pids $pid)
      $pids))

(: goal-live-proof-ids-for-output-key
   (-[semidet]-> Number ProofOutputKey (List Number)))
(= (goal-live-proof-ids-for-output-key $gid $key)
   (proof-fold-flat-semidet
      (proof-output-group-for-key-step $key)
      ()
      (goal-live-proof-ids $gid)))

(: goal-merged-proof-id-for-pid (-[semidet]-> Number Number Number))
(= (goal-merged-proof-id-for-pid $gid $pid)
   (let $key (proof-output-key-by-id $pid)
      (proof-output-group-representative-pid $gid
         (proof-output-group $key (goal-live-proof-ids-for-output-key $gid $key)))))

(: goal-results
   (-[semidet]-> Number
      (List RuntimeResult)))
(= (goal-results $gid)
   (let*
      (($pids (goal-merged-proof-ids $gid)))
      (proof-map-flat-semidet materialize-result-atom
         (proof-map-flat-semidet proof-output-atom-by-id $pids))))

;; A completed root proof is an incumbent answer even if one of its revised
;; children is superseded near the end of a bounded search. Keep it out of
;; ordinary subgoal reasoning, but use the latest non-superseded root
;; candidates when the live result set is transiently empty. Once a rebuilt
;; root is committed, the normal live result path wins again.
(: goal-incumbent-proof-step
   (-[semidet]-> (List Number) Number (List Number)))
(= (goal-incumbent-proof-step $acc $pid)
   (if (proof-current-representative? $pid)
      (append-number $acc $pid)
      $acc))

(: goal-incumbent-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-incumbent-proof-ids $gid)
   (proof-fold-flat-semidet
      goal-incumbent-proof-step () (goal-proof-ids $gid)))

(: goal-results-for-proof-ids
   (-[semidet]-> Number (List Number) (List RuntimeResult)))
(= (goal-results-for-proof-ids $gid $pids)
   (let $representatives
      (proof-output-group-representative-pids $gid
         (proof-output-groups $pids))
      (proof-map-flat-semidet materialize-result-atom
         (proof-map-flat-semidet
            proof-output-atom-by-id $representatives))))

(: root-goal-results
   (-[semidet]-> Number (List RuntimeResult)))
(= (root-goal-results $gid)
   (let $current (goal-results $gid)
      (if (== $current ())
         (goal-results-for-proof-ids
            $gid (goal-incumbent-proof-ids $gid))
         $current)))

(: goal-current-output
   (-[semidet]-> Number
       (| Goal (Statement KBContext Proof TV) NoCurrentScore)))
(= (goal-current-output $gid)
   (let*
      (($pids (goal-merged-proof-ids $gid))
        ((stored-goal-row
             $_stored-gid $_depth $goal $_expanded $_pending)
           (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal) no-current
         (case $pids (
              (() no-current)
              ((cons $pid $rest) (merge-proof-id-output (cons $pid $rest))))))))

(: goal-current-confidence
   (-[semidet]-> Number (| Number NoCurrentScore)))
(= (goal-current-confidence $gid)
   (let*
      (($pids (goal-merged-proof-ids $gid))
       ((stored-goal-row
            $_stored-gid $_depth $goal $_expanded $_pending)
          (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal) no-current
         (case $pids
            ((() no-current)
             ((cons $pid $rest)
                (term-confidence
                   (merge-proof-id-output
                      (cons $pid $rest)))))))))

(: leaf-evidence-for-stored-fact
   (-[det]-> Atom Atom Atom Atom (List Evidence)))
(= (leaf-evidence-for-stored-fact $type $kb $proof $tv)
   (let $typed-proof (brand Proof $proof)
      (if (assumption-proof? $typed-proof) ()
         (forward-fact-evidence
            (brand Statement $type)
            (brand KBContext $kb)
            $typed-proof
            (the TV $tv)))))

(: leaf-evidence-for-result
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence)))
(= (leaf-evidence-for-result $result)
   (once
      (case $result (
         ((CPU $_formula $_arguments $_result)
            ())
         (($type $kb $proof $tv)
            (leaf-evidence-for-stored-fact
               $type $kb $proof $tv))
         ($_other ())))))

;; A stored proof dominates a new one only when they are genuinely dependent
;; (share a rule or hypothesis). Proofs that overlap only in facts are kept so
;; lifting-merge can pool them at the subgoal -- dropping the lower-scoring one
;; here would discard recoverable confidence, and (since idealized confidence is
;; strength-dependent) the scores rarely tie, so plain overlap would otherwise
;; drop a poolable proof.
(: proof-overlap-dominates-score?
   (-[det]-> (List Evidence) Number (List Evidence) Number Bool))
(= (proof-overlap-dominates-score? $old-ev $old-score $new-ev $new-score)
   (if (evidence-sets-dependent? $old-ev $new-ev)
      (if (> $old-score $new-score) true
         (if (== $old-score $new-score)
            (evidence-subset? $new-ev $old-ev)
            false))
      false))

(: goal-proof-candidate-comparable?
   (-[semidet]-> Bool ProofOutputKey Number Bool))
(= (goal-proof-candidate-comparable? false $_outkey $_oldpid) true)
(= (goal-proof-candidate-comparable? true $outkey $oldpid)
   (== (proof-output-key-by-id $oldpid) $outkey))

(: goal-proof-candidate-step
   (-[semidet]-> Bool ProofOutputKey
       (List Evidence) Number Bool Number Bool))
(= (goal-proof-candidate-step $_open $_outkey $ev $score false $_oldpid) false)
(= (goal-proof-candidate-step $open $outkey $ev $score true $oldpid)
   (if (goal-proof-candidate-comparable? $open $outkey $oldpid)
      (let ($old-score $old-ev) (proof-stats-by-id $oldpid)
         (if (and (== $old-score $score) (== $old-ev $ev)) false
            (if (proof-overlap-dominates-score? $old-ev $old-score $ev $score) false true)))
      true))

(: classify-goal-proof-candidate
   (-[semidet]-> Number (| Goal ($type $kb $proof TV))
       (List Evidence) Number Bool))
(= (classify-goal-proof-candidate $gid $result $ev $score)
   (let*
      (((stored-goal-row
            $_stored-gid $_depth $goal $_expanded $_pending)
          (goal-by-id $gid))
       ($open (goal-has-type-vars? $goal))
       ($outkey (candidate-output-key $result)))
      (proof-fold-flat-semidet
         (goal-proof-candidate-step $open $outkey $ev $score)
         true
         (goal-live-proof-ids $gid))))

(: proof-candidate-stored-evidence
   (-[semidet]-> ProofCandidate (List Evidence)))
(= (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
   (case $kind (
      ((rule ($_type $kb $prf $_tv))
         (rule-result-evidence
            (assemble-runtime-fact
               (brand Statement $_type)
               (brand KBContext $kb)
               (brand Proof $prf)
               (the TV $_tv))
            $ev))
      ($_other $ev))))

(: normalize-proof-candidate-evidence
   (-[semidet]-> ProofCandidate ProofCandidate))
(= (normalize-proof-candidate-evidence (proof-candidate $kind $score $ev $children))
   (proof-candidate $kind $score
      (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
      $children))

;; Rule candidates are normalized before classification; leaf and aggregate
;; candidates already carry their final evidence. Store that accepted evidence
;; directly instead of walking rule proofs a second time.
(: store-proof-candidate (-[nondet]-> Number ProofCandidate  Number))
(= (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
   (let*
      (($pid (next-pid))
        ($output (proof-output-atom-kind $kind $pid))
        ($old-pids
           (goal-live-proof-ids-for-output-key $gid (candidate-output-key $output)))
        ($_1
           (chainer-add-atom &proof
              (stored-proof-row
                 $pid $gid $output $kind $score $ev $children)))
        ($_2 (mark-proof-static! $gid $pid $kind $children))
        ($_parents (register-proof-parent-edges! $pid $children))
        ($_3
           (if (== $old-pids ()) ()
              (let $old-representative
                 (proof-output-group-representative-pid $gid
                    (proof-output-group
                       (candidate-output-key $output) $old-pids))
                 (progn
                    (add-atom &proof_superseded
                       ($old-representative))
                    (invalidate-proof-dependents!
                       (proof-live-cache-epoch)
                       $old-representative)))))
        ($_4 (cache-proof-live! $pid true))
        ($_5 (append-goal-live-cache! $gid $pid)))
      $pid))

(: proof-atom-candidate
   (-[det]-> (Statement KBContext Proof TV)
       (List Evidence) ProofCandidate))
(= (proof-atom-candidate ($type $kb $prf $tv) $ev)
   (let $fact
      (assemble-runtime-fact $type $kb $prf $tv)
      (proof-candidate
         (leaf $fact) (term-confidence $fact) $ev ())))

(: leaf-result-candidate
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence) ProofCandidate))
(= (leaf-result-candidate $result $ev)
   (once
      (case $result (
         ((CPU $_formula $_arguments $_cpu-result)
            (proof-candidate
               (leaf $result)
               (term-confidence $result)
               $ev ()))
         (($type ($kbid $context $variables) $prf $tv)
            (proof-atom-candidate
               (assemble-contextual-runtime-fact
                  $type
                  $kbid
                  $context $variables
                  $prf
                  $tv)
               $ev))
         ($_other
            (proof-candidate
               (leaf $result) (term-confidence $result) $ev ()))))))

(: aggregate-result-candidate
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence) (List Number) ProofCandidate))
(= (aggregate-result-candidate $result $ev $children)
   (proof-candidate (aggregate $result) (term-confidence $result) $ev $children))

(: candidate-kind-term
   (-[semidet]-> ProofKind
       (| Goal (Statement KBContext Proof TV))))
(= (candidate-kind-term (leaf $term)) $term)
(= (candidate-kind-term (rule $term)) $term)
(= (candidate-kind-term (aggregate $term)) $term)

(: cyclic-dependency?
   (-[semidet]-> Number Number
       (| ProofOutputKey ClosedGoalKey) Bool))
(= (cyclic-dependency? $pid $gid $cycle-key)
   (if (== $cycle-key closed-goal)
      (== (proof-goal-id $pid) $gid)
      (=alpha (proof-output-key-by-id $pid) $cycle-key)))

(: proof-depends-on-goal-seen?
   (-[semidet]-> Number Number
       (| ProofOutputKey ClosedGoalKey)
       (List Number) Bool))

(: proof-depends-on-goal-child-step
   (-[semidet]-> Number
       (| ProofOutputKey ClosedGoalKey)
       (List Number) Bool Number Bool))
(= (proof-depends-on-goal-child-step
      $gid $cycle-key $seen-pids $acc $child-pid)
   (if $acc true
      (proof-depends-on-goal-seen?
         $child-pid $gid $cycle-key $seen-pids)))

(= (proof-depends-on-goal-seen? $pid $gid $cycle-key $seen-pids)
   (if (stored-list-member? $pid $seen-pids) false
      (if (cyclic-dependency? $pid $gid $cycle-key) true
         (proof-fold-flat-semidet
            (proof-depends-on-goal-child-step
               $gid $cycle-key (cons $pid $seen-pids))
            false
            (proof-children-by-id $pid)))))

(: candidate-cycle-key
   (-[semidet]-> Number ProofKind
       (| ProofOutputKey ClosedGoalKey)))
(= (candidate-cycle-key $gid $kind)
   (let*
      (((stored-goal-row
            $_stored-gid $_depth $goal $_expanded $_pending)
          (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal)
         (candidate-output-key (candidate-kind-term $kind))
         closed-goal)))

(: candidate-is-cyclic?
   (-[semidet]-> Number ProofKind (List Number) Bool))
(= (candidate-is-cyclic? $gid $_kind ()) false)
(= (candidate-is-cyclic? $gid $kind (cons $pid $pids))
   (let $cycle-key (candidate-cycle-key $gid $kind)
      (if
         (proof-depends-on-goal-seen?
            $pid $gid $cycle-key ())
         true
         (candidate-is-cyclic? $gid $kind $pids))))

(: aggregate-snapshot-changed?
   (-[semidet]-> (| Number (List Number))
       $result (List Evidence) Bool))
(= (aggregate-snapshot-changed? $current-pid $result $ev)
   (if (== $current-pid ()) true
      (let $pid (the Number $current-pid)
         (let*
            (($current-output (proof-output-atom-by-id $pid))
             (($_current-score $current-ev) (proof-stats-by-id $pid)))
            (if (=alpha $current-output $result)
               (if (== $current-ev $ev) false true)
               true)))))
