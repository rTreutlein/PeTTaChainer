;; Durable proof DAG storage, indexes, liveness, and aggregate snapshots.
(: next-gid (-[det]-> Number))
(= (next-gid) (next-search-id bwd_gid))

(: next-pid (-[det]-> Number))
(= (next-pid) (next-search-id bwd_pid))

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

;; The durable proof table is historical.  This separate view contains only
;; proofs which ordinary subgoal reasoning may consume now.  One row per proof
;; keeps lookup and localized removal indexed by the semantic goal key; a
;; growing PID list would make every update copy or rescan the complete view.
(: ProofGoalOutputKey Type)
(: proof-goal-output-key
   (-[det]-> ProofGoalKey ProofOutputKey ProofGoalOutputKey))
(: CurrentProofOutputRow Type)
(: current-proof-output-row
   (-[det]-> ProofGoalOutputKey ProofGoalKey ProofOutputKey Number
       CurrentProofOutputRow))
(: CurrentProofResultRow Type)
(: current-proof-result-row
   (-[det]-> Atom ProofGoalKey ProofOutputKey Number
       CurrentProofResultRow))
(: CurrentProofResultGoalRow Type)
(: current-proof-result-goal-row
   (-[det]-> ProofGoalKey ProofGoalKey ProofOutputKey
       CurrentProofResultGoalRow))
(: CurrentProofResultDirtyRow Type)
(: current-proof-result-dirty-row
   (-[det]-> ProofGoalKey ProofGoalKey ProofOutputKey
       CurrentProofResultDirtyRow))
(: GoalCurrentConfidenceRow Type)
(: goal-current-confidence-row
   (-[det]-> Number (| Number NoCurrentScore)
       GoalCurrentConfidenceRow))

(: clear-goal-current-confidence! (-[det]-> Number (List $none)))
(= (clear-goal-current-confidence! $gid)
   (let $_removed
      (collapse
         (match &goal_current_confidence
            (goal-current-confidence-row $gid $value)
            (remove-atom &goal_current_confidence
               (goal-current-confidence-row $gid $value))))
      ()))

(: clear-goal-current-confidence-for-key!
   (-[det]-> ProofGoalKey (List $none)))
(= (clear-goal-current-confidence-for-key! $key)
   (let $lookup-key (copy_term $key)
      (let $_cleared
         (collapse
            (match &goal_lookup
               ($lookup-key $stored-key $gid)
               (if (=alpha $stored-key $key)
                  (clear-goal-current-confidence!
                     (stored-number $gid))
                  (empty))))
         ())))

(: index-current-proof-for-goal!
   (-[det]-> ProofGoalKey ProofOutputKey Number Bool))
(= (index-current-proof-for-goal! $key $output-key $pid)
   (let* (($lookup-key (copy_term $key))
          ($output-lookup-key
             (copy_term (proof-goal-output-key $key $output-key)))
          ($_goal
             (add-space-atom! &proof_current
                (make-space-row3 $lookup-key $key $pid))))
      (add-space-atom! &proof_current_output
         (current-proof-output-row
            $output-lookup-key $key $output-key $pid))))

(: remove-current-proof-for-goal!
   (-[semidet]-> ProofGoalKey Number Bool))
(= (remove-current-proof-for-goal! $key $pid)
   (let* (($lookup-key (copy_term $key))
          ($output-key (proof-output-key-by-id $pid))
          ($output-lookup-key
             (copy_term (proof-goal-output-key $key $output-key)))
          ($_output
             (collapse
                (once
                   (remove-atom &proof_current_output
                      (current-proof-output-row
                         $output-lookup-key $key $output-key $pid)))))
          ($removed
         (collapse
            (once
               (remove-atom &proof_current
                  ($lookup-key $key $pid))))))
      (not (== $removed ()))))

(: current-proof-ids-for-goal-key
   (-[semidet]-> ProofGoalKey (List Number)))
(= (current-proof-ids-for-goal-key $key)
   (let* (($_metric
             (increment-backward-query-metric!
                current-proof-goal-lookups))
          ($lookup-key (copy_term $key)))
      (collapse
         (match &proof_current
            ($lookup-key $stored-key $pid)
            (if (=alpha $stored-key $key)
               (stored-number $pid)
               (empty))))))

(: current-proof-ids-for-goal-output-key
   (-[semidet]-> ProofGoalKey ProofOutputKey (List Number)))
(= (current-proof-ids-for-goal-output-key $key $output-key)
   (let $lookup-key
      (copy_term (proof-goal-output-key $key $output-key))
      (collapse
         (match &proof_current_output
            (current-proof-output-row
               $lookup-key $stored-key $stored-output-key $pid)
            (if (and (=alpha $stored-key $key)
                     (=alpha $stored-output-key $output-key))
               (stored-number $pid)
               (empty))))))

(: remove-current-proof-result-row! (-[det]-> CurrentProofResultRow Bool))
(= (remove-current-proof-result-row!
      (current-proof-result-row
         $lookup-key $key $output-key $pid))
   (remove-atom &proof_current_result_output
      (current-proof-result-row
         $lookup-key $key $output-key $pid)))

(: remove-current-proof-result-rows!
   (-[det]-> (List CurrentProofResultRow) (List $none)))
(= (remove-current-proof-result-rows! ()) ())
(= (remove-current-proof-result-rows! (cons $row $rest))
   (let $_removed (remove-current-proof-result-row! $row)
      (remove-current-proof-result-rows! $rest)))

(: current-proof-result-rows-for-output-key
   (-[det]-> ProofGoalKey ProofOutputKey
       (List CurrentProofResultRow)))
(= (current-proof-result-rows-for-output-key $key $output-key)
   (let $lookup-key
      (copy_term (proof-goal-output-key $key $output-key))
      (collapse
         (match &proof_current_result_output
            (current-proof-result-row
               $lookup-key $stored-key $stored-output-key $pid)
            (if (and (=alpha $stored-key $key)
                     (=alpha $stored-output-key $output-key))
               (current-proof-result-row
                  $lookup-key
                  $stored-key $stored-output-key (stored-number $pid))
               (empty))))))

(: current-proof-result-id-for-output-key
   (-[semidet]-> ProofGoalKey ProofOutputKey Number))
(= (current-proof-result-id-for-output-key $key $output-key)
   (let $rows
      (current-proof-result-rows-for-output-key $key $output-key)
      (case $rows (
         ((cons
             (current-proof-result-row
                $_lookup $_stored-key $_stored-output-key $pid)
             $_rest)
            (stored-number $pid))
         ($_ (empty))))))

(: current-proof-result-goal-row-exists?
   (-[det]-> ProofGoalKey ProofOutputKey Bool))
(= (current-proof-result-goal-row-exists? $key $output-key)
   (let $lookup-key (copy_term $key)
      (not
         (==
            (collapse
               (once
                  (match &proof_current_result
                     (current-proof-result-goal-row
                        $lookup-key $stored-key $stored-output-key)
                     (if (and (=alpha $stored-key $key)
                              (=alpha $stored-output-key $output-key))
                        true
                        (empty)))))
            ()))))

(: index-current-proof-result!
   (-[semidet]-> ProofGoalKey ProofOutputKey Number Bool))
(= (index-current-proof-result! $key $output-key $pid)
   (let* (($goal-lookup-key (copy_term $key))
          ($output-lookup-key
             (copy_term (proof-goal-output-key $key $output-key)))
          ($old
             (current-proof-result-rows-for-output-key
                $key $output-key))
          ($goal-row-exists?
             (current-proof-result-goal-row-exists?
                $key $output-key))
          ($_goal
             (if $goal-row-exists? ()
                (add-space-atom! &proof_current_result
                   (current-proof-result-goal-row
                      $goal-lookup-key $key $output-key))))
          ($_old
             (remove-current-proof-result-rows! $old)))
      (add-space-atom! &proof_current_result_output
         (current-proof-result-row
            $output-lookup-key $key $output-key $pid))))

(: current-proof-result-ids-for-goal-key
   (-[semidet]-> ProofGoalKey (List Number)))
(= (current-proof-result-ids-for-goal-key $key)
   (let* (($_metric
             (increment-backward-query-metric!
                current-result-goal-lookups))
          ($lookup-key (copy_term $key)))
      (list_to_set
         (collapse
            (match &proof_current_result
               (current-proof-result-goal-row
                  $lookup-key $stored-key $output-key)
               (if (=alpha $stored-key $key)
                  (current-proof-result-id-for-output-key
                     $stored-key $output-key)
                  (empty)))))))

(: remove-current-proof-result!
   (-[semidet]-> ProofGoalKey ProofOutputKey (List $none)))
(= (remove-current-proof-result! $key $output-key)
   (let* (($_output
             (remove-current-proof-result-rows!
                (current-proof-result-rows-for-output-key
                   $key $output-key)))
          ($lookup-key (copy_term $key))
          ($_goal
             (collapse
                (match &proof_current_result
                   (current-proof-result-goal-row
                      $lookup-key $stored-key $stored-output-key)
                   (if (and (=alpha $stored-key $key)
                            (=alpha $stored-output-key $output-key))
                      (remove-atom &proof_current_result
                         (current-proof-result-goal-row
                            $lookup-key $stored-key $stored-output-key))
                      (empty))))))
      ()))

(: mark-current-proof-result-dirty!
   (-[det]-> ProofGoalKey ProofOutputKey Bool))
(= (mark-current-proof-result-dirty! $key $output-key)
   (let $lookup-key (copy_term $key)
      (add-space-atom! &proof_current_result_dirty
         (current-proof-result-dirty-row
            $lookup-key $key $output-key))))

(: current-proof-result-dirty?
   (-[det]-> ProofGoalKey ProofOutputKey Bool))
(= (current-proof-result-dirty? $key $output-key)
   (let $lookup-key (copy_term $key)
      (not
         (==
            (collapse
               (once
                  (match &proof_current_result_dirty
                     (current-proof-result-dirty-row
                        $lookup-key $stored-key $stored-output-key)
                     (if (and (=alpha $stored-key $key)
                              (=alpha $stored-output-key $output-key))
                        true
                        (empty)))))
            ()))))

(: dirty-current-proof-result-output-keys
   (-[semidet]-> ProofGoalKey (List ProofOutputKey)))
(= (dirty-current-proof-result-output-keys $key)
   (let $lookup-key (copy_term $key)
      (collapse
         (match &proof_current_result_dirty
            (current-proof-result-dirty-row
               $lookup-key $stored-key $output-key)
            (if (=alpha $stored-key $key)
               $output-key
               (empty))))))

(: clear-current-proof-result-dirty!
   (-[det]-> ProofGoalKey ProofOutputKey (List $none)))
(= (clear-current-proof-result-dirty! $key $output-key)
   (let $lookup-key (copy_term $key)
      (let $_removed
         (collapse
            (match &proof_current_result_dirty
               (current-proof-result-dirty-row
                  $lookup-key $stored-key $stored-output-key)
               (if (and (=alpha $stored-key $key)
                        (=alpha $stored-output-key $output-key))
                  (remove-atom &proof_current_result_dirty
                     (current-proof-result-dirty-row
                        $lookup-key $stored-key $stored-output-key))
                  (empty))))
         ())))

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

;; Single-field aggregate row updates. The removal must see the exact stored
;; row, so callers pass the row they already fetched (or constructed).
(: set-aggregate-pending!
   (-[semidet]-> StoredAggregateRow Number (| Bool (List $none))))
(= (set-aggregate-pending!
      (stored-aggregate-row
         $agg-gid $child-gid $args $base-score $pending $current-pid)
      $next-pending)
   (progn
      (remove-atom &aggregate
         (stored-aggregate-row
            $agg-gid $child-gid $args $base-score $pending $current-pid))
      (once
         (chainer-add-atom &aggregate
            (stored-aggregate-row
               $agg-gid $child-gid $args $base-score $next-pending
               $current-pid)))))

(: set-aggregate-current-pid!
   (-[semidet]-> StoredAggregateRow (List Number)
       (| Bool (List $none))))
(= (set-aggregate-current-pid!
      (stored-aggregate-row
         $agg-gid $child-gid $args $base-score $pending $current-pid)
      $next-current)
   (progn
      (remove-atom &aggregate
         (stored-aggregate-row
            $agg-gid $child-gid $args $base-score $pending $current-pid))
      (once
         (chainer-add-atom &aggregate
            (stored-aggregate-row
               $agg-gid $child-gid $args $base-score $pending
               $next-current)))))

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
      ($_other $term))))

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

(: proof-row-by-id
   (-[semidet]-> Number
      ((| Goal (Statement KBContext Proof TV))
       ProofKind ProofSupport (List Number))))
(= (proof-row-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_owner $output $kind $support $children)
         (data $output $kind $support $children))))

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

(: proof-support-by-id (-[semidet]-> Number ProofSupport))
(= (proof-support-by-id $pid)
   (once
      (match &proof
         (stored-proof-row
            $pid $_owner $_output $_kind $support $_children)
         $support)))

(: proof-projected-contribution-from-source
   (-[det]-> Number TV
       (| Goal (Statement KBContext Proof TV))
       ProofContribution))
(= (proof-projected-contribution-from-source $idx $marginal-tv $source)
   (case $source (
      (($type $_kb $_proof $source-tv)
         (if (is-expr $type)
            (if (== (car-atom $type) And)
               (projected-contribution
                  (candidate-output-key $source)
                  $source-tv
                  (list-len (cdr-atom $type))
                  $idx
                  $marginal-tv)
               (independent-contribution $marginal-tv))
            (independent-contribution $marginal-tv)))
      ($_other (independent-contribution $marginal-tv)))))

(: proof-projected-contribution
   (-[det]-> Number (| Proof ProofRef) TV ProofContribution))
(= (proof-projected-contribution $idx $base $marginal-tv)
   (case $base (
      ((proof-ref $source-pid)
         (let $contributions
            (collapse
               (once
                  (proof-projected-contribution-from-source
                     $idx $marginal-tv
                     (proof-output-atom-by-id $source-pid))))
            (if (== $contributions ())
               (independent-contribution $marginal-tv)
               (car-atom $contributions))))
      ($proof
         (let $contributions
            (collapse
               (match &kb
                  (@ $fact ($_type $_kb $proof $_tv))
                  (proof-projected-contribution-from-source
                     $idx $marginal-tv $fact)))
            (if (== $contributions ())
               (independent-contribution $marginal-tv)
               (car-atom $contributions)))))))

(: proof-fact-contribution
   (-[det]-> ProofKind TV ProofContribution))
(= (proof-fact-contribution $kind $tv)
   (case $kind (
      ((leaf ($_type $_kb (marginal-proj $idx $base) $_source-tv))
         (proof-projected-contribution
            (the Number $idx) (brand Proof $base) $tv))
      ((rule ($_type $_kb (marginal-proj $idx $base) $_source-tv))
         (proof-projected-contribution
            (the Number $idx) (brand Proof $base) $tv))
      ($_other (independent-contribution $tv)))))

(: proof-contribution
   (-[det]-> ProofKind
       (| Goal (Statement KBContext Proof TV))
       ProofContribution))
(= (proof-contribution $kind $output)
   (case $output (
      ((CPU $formula $arguments $result)
         (if (== $formula AndFormula)
            skip-contribution
            (independent-contribution
               (cpu-premise-tv $formula $arguments $result))))
      (($_type $_kb $_proof $tv)
         (proof-fact-contribution $kind $tv))
      ($_other unpoolable-contribution))))

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
(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (or (== $function FoldAllCompiled)
       (== $function GroupedFoldAllCompiled)))
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
      (case $output (
         ((CPU $function $_args $_res)
            (if (aggregate-fold-function? $function)
               (cons (materialize-proof $pid) (aggregate-child-proof-tokens $rest))
               (aggregate-child-proof-tokens $rest)))
         ($_other (aggregate-child-proof-tokens $rest))))))

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
   (-[det]-> Number Bool ProofLiveCacheRow))

;; A frontier path is a query-local cons list with a stable numeric identity.
;; Waiters carry only that identity: extending a frontier stores one new node,
;; and completing it reconstructs the proof list once.  A superseded proof
;; invalidates exactly the path nodes that contain it and their descendants,
;; making repeated waiter liveness checks an indexed lookup instead of a walk
;; over every proof already consumed by the frontier.
(: next-frontier-path-id (-[det]-> Number))
(= (next-frontier-path-id)
   (+ 1 (next-search-id bwd_frontier_path)))

(: ensure-frontier-path (-[semidet]-> Number Number Number))
(= (ensure-frontier-path $parent-path-id $pid)
   (let $hits
      (collapse
         (once
            (match &frontier_path_lookup
               ($parent-path-id $pid $path-id) $path-id)))
      (if (== $hits ())
         (let* (($path-id (next-frontier-path-id))
                ($_lookup
                   (add-space-atom! &frontier_path_lookup
                      (make-space-row3
                         $parent-path-id $pid $path-id)))
                ($_node
                   (add-space-atom! &frontier_path
                      (make-space-row3
                         $path-id $parent-path-id $pid)))
                ($_child
                   (add-space-atom! &frontier_path_child
                      (make-space-pair $parent-path-id $path-id)))
                ($_proof
                   (add-space-atom! &proof_frontier_path
                      (make-space-pair $pid $path-id))))
            $path-id)
         (the Number (car-atom $hits)))))

(: frontier-path-live? (-[det]-> Number Bool))
(= (frontier-path-live? $path-id)
   (==
      (collapse
         (once (match &frontier_path_dead ($path-id) true)))
      ()))

(: frontier-path-rev-proof-ids
   (-[semidet]-> Number (List Number)))
(= (frontier-path-rev-proof-ids $path-id)
   (if (== $path-id 0) ()
      (once
         (match &frontier_path
            ($path-id $stored-parent-path-id $stored-pid)
            (let* (($parent-path-id
                       (stored-number $stored-parent-path-id))
                    ($pid (stored-number $stored-pid)))
               (cons $pid
                  (frontier-path-rev-proof-ids $parent-path-id)))))))

(: invalidate-frontier-path! (-[det]-> Number (List $none)))
(= (invalidate-frontier-path! $path-id)
   (if (frontier-path-live? $path-id)
      (let* (($_dead
                (once (add-atom &frontier_path_dead ($path-id))))
             ($_children
                (foreach-flat
                   invalidate-frontier-path!
                   (the (List Number)
                      (collapse
                         (match &frontier_path_child
                            ($path-id $child-path-id)
                            (stored-number $child-path-id)))))))
         ())
      ()))

(: invalidate-frontier-paths-for-proof!
   (-[det]-> Number (List $none)))
(= (invalidate-frontier-paths-for-proof! $pid)
   (foreach-flat
      invalidate-frontier-path!
      (the (List Number)
         (collapse
            (match &proof_frontier_path
               ($pid $path-id) (stored-number $path-id))))))

(: cache-proof-live! (-[det]-> Number Bool Bool))
(= (cache-proof-live! $pid $alive)
   (once
      (add-atom &proof_live_cache
         (proof-live-cache-row $pid $alive))))

(: cached-proof-live? (-[nondet]-> Number  Bool))
(= (cached-proof-live? $pid)
   (match &proof_live_cache
      (proof-live-cache-row $pid $alive)
      $alive))

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

(: invalidate-proof-dependent-step-in-epoch
   (-[semidet]-> Number Number (List $none)))
(: invalidate-proof-dependent-in-epoch!
   (-[semidet]-> Number Number (List $none)))
(: invalidate-proof-dependents-in-epoch!
   (-[semidet]-> Number Number (List $none)))
(: proof-live-compute (-[semidet]-> Number Bool))
(: deactivate-current-proof! (-[semidet]-> Number (List $none)))
(: deactivate-current-proof-in-epoch!
   (-[semidet]-> Number Number (List $none)))

;; Invalidation runs while aggregate and merged representatives are being
;; replaced.  A proof whose dependencies cannot be resolved at that instant is
;; not part of the current view; that must deactivate the proof, not abort the
;; enclosing search operation.
(: recomputed-proof-live? (-[det]-> Number Bool))
(= (recomputed-proof-live? $pid)
   (let $hits (collapse (once (proof-live-compute $pid)))
      (if (== $hits ()) false
         (the Bool (car-atom $hits)))))

(: remove-proof-live-cache-row!
   (-[det]-> ProofLiveCacheRow Bool))
(= (remove-proof-live-cache-row! $row)
   (remove-atom &proof_live_cache $row))

(: invalidate-proof-dependent! (-[semidet]-> Number (List $none)))
(= (invalidate-proof-dependent! $parent-pid)
   (invalidate-proof-dependent-in-epoch!
      (next-search-id bwd_invalidation_epoch) $parent-pid))

(= (invalidate-proof-dependent-in-epoch! $epoch $parent-pid)
   (let $seen
      (collapse
         (once
            (match &proof_invalidated
               (($epoch $parent-pid)) true)))
      (if (not (== $seen ())) ()
         (let*
            (($_mark
                (once
                   (add-atom &proof_invalidated
                      (($epoch $parent-pid)))))
             ($_proof-cache
                (foreach-flat
                   remove-proof-live-cache-row!
                   (collapse
                      (match &proof_live_cache
                         (proof-live-cache-row $parent-pid $alive)
                         (proof-live-cache-row $parent-pid $alive)))))
             ($alive (recomputed-proof-live? $parent-pid))
             ($_current
                (if $alive
                   (cache-proof-live! $parent-pid true)
                   (deactivate-current-proof-in-epoch!
                      $epoch $parent-pid))))
            ()))))

(= (invalidate-proof-dependent-step-in-epoch $epoch $parent-pid)
   (invalidate-proof-dependent-in-epoch! $epoch $parent-pid))

(: invalidate-proof-dependents!
   (-[semidet]-> Number (List $none)))
(= (invalidate-proof-dependents! $child-pid)
   (invalidate-proof-dependents-in-epoch!
      (next-search-id bwd_invalidation_epoch) $child-pid))

(= (invalidate-proof-dependents-in-epoch! $epoch $child-pid)
   (let* (($_frontiers
             (invalidate-frontier-paths-for-proof! $child-pid))
          ($_proofs
             (foreach-flat
                (invalidate-proof-dependent-step-in-epoch $epoch)
                (collapse
                   (match &proof_parent ($child-pid $parent-pid)
                      (stored-number $parent-pid))))))
      ()))

(= (deactivate-current-proof! $pid)
   (deactivate-current-proof-in-epoch!
      (next-search-id bwd_invalidation_epoch) $pid))

(= (deactivate-current-proof-in-epoch! $epoch $pid)
   (let* (($goal-key (proof-goal-key-by-id $pid))
          ($output-key (proof-output-key-by-id $pid))
          ($_remove (remove-current-proof-for-goal! $goal-key $pid))
          ($_retire
             (once (add-atom &proof_retired ($pid))))
          ($_cache
             (foreach-flat
                remove-proof-live-cache-row!
                (collapse
                   (match &proof_live_cache
                      (proof-live-cache-row $pid $alive)
                      (proof-live-cache-row $pid $alive)))))
          ($_dirty
             (mark-current-proof-result-dirty!
                $goal-key $output-key))
          ($_confidence
             (clear-goal-current-confidence-for-key! $goal-key))
          ($_dependents
             (invalidate-proof-dependents-in-epoch! $epoch $pid)))
      ()))

(: deactivate-current-proofs!
   (-[semidet]-> (List Number) (List $none)))
(= (deactivate-current-proofs! $current)
   (foreach-flat deactivate-current-proof! $current))

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
   (-[det]-> (List Number) Number Bool))
(= (aggregate-current-pid-live? $current-pid $pid)
   (stored-list-member? $pid $current-pid))

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
            (let (cons $current-pids $_rest) $current-hits
               $current-pids)
            $pid))))

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

(: proof-retired? (-[det]-> Number Bool))
(= (proof-retired? $pid)
   (not (== (collapse (once (match &proof_retired ($pid) true))) ())))

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
   (if (proof-retired? $pid)
      (let $_event (query_metric_liveness_event retired)
         false)
      (if (proof-statically-live? $pid)
         (let $_event (query_metric_liveness_event hit)
            true)
         (let*
            (($hits (collapse (once (cached-proof-live? $pid)))))
            (if (== $hits ())
               (let* (($_event (query_metric_liveness_event miss))
                      ($alive (proof-live-compute $pid))
                      ($_cache (cache-proof-live! $pid $alive)))
                  $alive)
               (let $_event (query_metric_liveness_event hit)
                  (car-atom $hits)))))))

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

(: reverse-number-list
   (-[det]-> (List Number) (List Number)))
(: reverse-number-list-into
   (-[det]-> (List Number) (List Number) (List Number)))
(= (reverse-number-list $items)
   (reverse-number-list-into $items ()))
(= (reverse-number-list-into () $acc) $acc)
(= (reverse-number-list-into (cons $item $rest) $acc)
   (reverse-number-list-into $rest (cons $item $acc)))

(: goal-current-proof-step
   (-[semidet]-> (| Goal (Statement KBContext Proof TV))
      (List Number) Number (List Number)))
(= (goal-current-proof-step $goal $acc $pid)
   (if (proof-output-satisfies-goal? $pid $goal)
      (cons $pid $acc)
      $acc))

(: goal-live-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-live-proof-ids $gid)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_pending)
            (goal-by-id $gid))
          ($key (proof-goal-key-by-goal-id $gid)))
      (reverse-number-list
         (proof-fold-flat-semidet
            (goal-current-proof-step $goal) ()
            (current-proof-ids-for-goal-key $key)))))

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

(: merge-proof-id-output-step
   (-[semidet]-> (Statement KBContext Proof TV)
       Number (Statement KBContext Proof TV)))
(= (merge-proof-id-output-step $acc $pid)
   (merge-proof-atoms $acc (proof-fact-output-by-id $pid)))
