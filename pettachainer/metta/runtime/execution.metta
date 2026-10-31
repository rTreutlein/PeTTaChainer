;; Query execution, evaluation scope and allowance ownership.

!(change-state! sk_branch_budget 0)
!(change-state! sk_root_claim_budget 0)
!(change-state! sk_root_claim_cap 0)
!(change-state! sk_representative_budget 0)
!(change-state! sk_branch_at 0)

;; Row computations a query may spend per step of its budget beyond the reserve.
(: sk-evaluation-per-step (-[det]-> Number))
(= (sk-evaluation-per-step) 2)

;; A request cannot crowd out ordinary evaluation, restales or conditioning.
;; This is a ceiling within the existing allowance, not an extra allowance.
;; Root refinement gets one eighth of evaluation, at most 256 units
;; (512 conditioned rows). The fixed ceiling retains cheap 2p/4p cuts without
;; making long-history root retries consume the whole query. All roots share it.
(: sk-root-claim-share (-[det]-> Number))
(= (sk-root-claim-share) 0.125)
(: sk-root-claim-limit (-[det]-> Number))
(= (sk-root-claim-limit) 256)

(: sk-branch-share (-[det]-> Number))
(= (sk-branch-share) 0.125)

;; Expanded nodes a query's walk may pass through per step of its budget.
(: sk-walk-per-step (-[det]-> Number))
(= (sk-walk-per-step) 1)

(: sk-take! (-[det]-> CounterKey Number Bool))
(= (sk-take! $counter $cost)
   (let $left (search-id-value $counter)
      (if (<= $left 0) false (progn (change-state! $counter (- $left $cost)) true))))

;; A row or fold within two steps of a root adds to a query's reserve (see
;; sk-near-root-reserve-take!); a forward run has none.
(: sk-reserve-near! (-[det]-> Number Atom))
(= (sk-reserve-near! $depth)
   (if (if (== (search-id-value sk_forward_run) 1) false (<= $depth (sk-evaluation-free-depth)))
      (let $_added (change-state! sk_near_reserve (+ (search-id-value sk_near_reserve) (sk-evaluation-near-root-reserve))) ())
      ()))

;; One owner for invocation allowances and their bounded nested slices.

(: execution-allowances! (-[det]-> Number Bool Atom))
(= (execution-allowances! $units $backward?)
   (let* (($_evaluation (change-state! sk_eval_budget $units))
          ($_branches (change-state! sk_branch_budget (* $units (sk-branch-share))))
          ($_roots (if $backward?
             (let $root (min (sk-root-claim-limit) (floor-math (* $units (sk-root-claim-share))))
                (progn (change-state! sk_root_claim_budget $root) (change-state! sk_root_claim_cap $root))) ())))
      ()))

(: execution-open-slice! (-[det]-> Number EvaluationSlice))
(= (execution-open-slice! $room)
   (let* (($before (search-id-value sk_eval_budget))
          ($_slice (change-state! sk_eval_budget $room)))
      (evaluation-slice $before $room)))

;; Returning a slice debits exactly its work to the containing allowance and
;; optionally its root or branch tier. Queue bookkeeping costs at least one.
(: execution-close-slice! (-[det]-> EvaluationSlice EvaluationTier Number))
(= (execution-close-slice! (evaluation-slice $before $room) $tier)
   (let* (($spent (- $room (search-id-value sk_eval_budget)))
          ($_restore (change-state! sk_eval_budget (- $before $spent)))
          ($_tier (case $tier (
             (root-slice (change-state! sk_root_claim_budget (- (search-id-value sk_root_claim_budget) $spent)))
             (branch-slice (change-state! sk_branch_budget (- (search-id-value sk_branch_budget) (max 1 $spent))))
             (ordinary-slice true)))))
      $spent))

(: execution-open-frame! (-[det]-> (List Number) (Number Number)))
(= (execution-open-frame! $exclude)
   (let* (($parent (search-id-value sk_branch_at))
          ($frame (+ 1 (next-search-id sk_branch_frame)))
          ($_cuts (add-atom &sk_branch_cuts ($frame $exclude ())))
          ($_enter (change-state! sk_branch_at $frame)))
      ($parent $frame)))

(: execution-close-frame! (-[semidet]-> Number Number (List Number) (List Number)))
(= (execution-close-frame! $parent $frame $exclude)
   (let* (((cons $found $_rest) (collapse (once (match &sk_branch_cuts ($frame $_exclude $recorded) $recorded))))
          ($cuts (hash-intersection (the (List Number) $found) $exclude))
          ($_leave (change-state! sk_branch_at $parent))
          ($_frame (remove-data-rows! &sk_branch_cuts (quote ($frame $_exclude $_found)))))
      $cuts))

(: execution-reset-frames! (-[det]-> Atom))
(= (execution-reset-frames!)
   (let* (($_claim (sk-close-claim!))
          ($_frame (change-state! sk_branch_at 0))
          ($_cuts (remove-data-rows! &sk_branch_cuts (quote ($_frame $_exclude $_cuts))))) ()))

(: execution-finish-backward! (-[semidet]-> Atom Atom))
(= (execution-finish-backward! $_unit)
   (let* (($_held (if (== (search-id-value sk_holding) 1) (sk-stale-held!) ()))
          ($_frames (execution-reset-frames!))
          ($_temp (sk-clear-temp!))) ()))

(: execute-backward
   (-[nondet]-> Number (List ExecutionGoal) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $requested $materialize?)
   (execution-finally (execute-backward-run $steps $requested $materialize?) execution-finish-backward!))

(: execute-backward-run
   (-[nondet]-> Number (List ExecutionGoal) Bool Atom (List (List RuntimeResult))))
(= (execute-backward-run $steps $requested $materialize? $_unit)
   (let* (($_value-caches (sk-clear-query-values!))
          ($_representative-budget (change-state! sk_representative_budget 256))
          ($_frames (execution-reset-frames!))
          ($goals (map-semidet execution-search-goal $requested))
          ($_seen (remove-data-rows! &sk_seen (quote ($hash $node))))
          ($_fresh (remove-data-rows! &sk_fresh (quote ($fhash $node))))
          ($_parked (sk-park-deliveries!))
          ($_old-roots (remove-data-rows! &sk_roots (quote ($hash $root))))
          ;; What was stored since the last query is activated before the
          ;; walk: facts against the nodes that were there before (so a root
          ;; new to the skeleton still starts from its population prior),
          ;; rules once the roots are registered, since a query's own rules
          ;; build its roots' rows. Their answers are delivered at once, from
          ;; an allowance of their own, ten rows per new fact and per step:
          ;; reading new evidence is the deferred cost of storing it, so it
          ;; neither waits for a walk to come back to it nor takes the rows
          ;; the search needs, and the allowance bounds what new facts set off
          ;; through recursive rules. Deliveries beyond it are made from the
          ;; query's allowance (docs/metta/fact_absorption.md).
          ($started (inference-clock))
          ($_absorbing (change-state! sk_row_budget (* 10 (+ (length (collapse (match &sk_pending_facts $fact $fact))) $steps))))
          ($_facts (sk-activate-facts!))
          ($_scored (fold-semidet sk-root-score-step () $goals))
          ($_rules (sk-activate-rules!))
          ($_thawed (sk-activate-thawed!))
          ($_absorbed (sk-drain!))
          ($_budget (change-state! sk_budget $steps))
          ($_rows (change-state! sk_row_budget (* 10 $steps)))
          ($_evaluation (execution-allowances! (* (sk-evaluation-per-step) $steps) true))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) $steps)))
          ($_pushes (change-state! sk_push_seq 0))
          ($_context-start (map-semidet execution-start-seed! (context-seeds $any-context)))
          ($_inversions (fold-semidet sk-root-reader-step () $goals))
          ($_search (sk-walk! $goals))
          ($_world-invalidated (sk-invalidate-world!))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_reserve (change-state! sk_near_reserve 0))
          ($_needed (sk-need-roots! (fold-semidet sk-root-keys-step () $goals)))
          ($context-reserve (search-id-value sk_near_reserve))
          ($_holding (change-state! sk_holding 1))
          ($_evaluated (sk-evaluate!))
          ($_inferred (inference-add! $started))
          ($main-results (map-semidet (sk-root-results $materialize?) $goals))
          ($_held (sk-stale-held!))
          ;; Keep the entire visited path while any of its world refreshes
          ;; remains unpaid. Current ancestors must still lead the next need
          ;; to deeper debt; they do not need another computation themselves.
          ($world-unpaid (not (== (collapse (once (match &sk_world_done ($wh $wr)
             (if (if (space-row-present? &ctx_sk_stale ($wh $wr)) true
                     (space-row-present? &ctx_sk_given_pending ($wh $wr $_cost))) true (empty))))) ())))
          ($_world-done (collapse (match &sk_world_done ($wkhash $wrhash)
             (let $_taken (remove-atom &sk_world_done ($wkhash $wrhash))
                (if $world-unpaid () (remove-atom &sk_world_stale ($wkhash $wrhash)))))))
          ($results (execution-context-results (* (sk-evaluation-per-step) $steps) $context-reserve $requested $main-results)))
      $results))


;; Forward-chains from caller-selected facts within `$units` row
;; computations, stores the values of the derived keys it built on and returns
;; them, most recent first, with proof references as stored: expanding each
;; proof would cost as much as the derivation history behind it. The run works
;; the seeds no run has taken yet, its own facts and those earlier calls
;; queued, first, for a share of its units, then everything on the carried
;; agenda with them, and carries what it leaves. A run without units only
;; queues its facts. A run has one result: backtracking into it would repeat
;; its work.

(: forward-chain
   (-[nondet]-> Number KB (List (Statement KBContext Proof TV))
       (List (Statement KBContext Proof TV))))
(= (forward-chain $units $kb $facts)
   (execution-finally (execution-forward-run $units $kb $facts) execution-finish-forward!))

(: execution-forward-run
   (-[nondet]-> Number KB (List (Statement KBContext Proof TV)) Atom
       (List (Statement KBContext Proof TV))))
(= (execution-forward-run $units $kb $facts $_unit)
   (let* (($started (inference-clock))
          ($_frames (execution-reset-frames!))
          ($_mode (change-state! sk_forward_run 1))
          ($_seen (remove-data-rows! &sk_seen (quote ($hash $node))))
          ($_budget (change-state! sk_budget (+ $units 1)))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) (+ $units 1))))
          ($_rows (change-state! sk_row_budget (* 10 (+ $units 1))))
          ($_evaluation (execution-allowances! $units false))
          ($_reserve (change-state! sk_near_reserve 0))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_activate (sk-activate-pending!))
          ($carried (collapse (match &sk_forward_agenda ($kb $priority $item) ($priority $item))))
          ($_cleared (remove-data-rows! &sk_forward_agenda (quote ($kb $priority $item))))
          ((sk-run $own $first)
             (sk-forward-loop! (* $units (- 1 (forward-seed-share)))
                (fold-flat (sk-carried-step true)
                   (fold-semidet sk-seed-step (empty_heap) (list_to_set $facts)) $carried)
                ()))
          ((sk-run $left $taken) (sk-forward-loop! 0 (fold-flat (sk-carried-step false) $own $carried) $first))
          ($_carry (sk-carry! $kb (bounded-agenda-target-size) $left))
          ($_off (change-state! sk_forward_run 0))
          ($results (fold-semidet sk-key-result () $taken))
          ($_inferred (inference-add! $started)))
      $results))

(: execution-finish-forward! (-[det]-> Atom Atom))
(= (execution-finish-forward! $_unit)
   (let* (($_mode (change-state! sk_forward_run 0))
          ($_frames (execution-reset-frames!))) ()))

;; Temporary additions and Assuming contexts stay installed through proof
;; externalization and pretty printing. The executor closes this bracket on success, failure and exceptions.
(: run-query-execution-plan
   (-[nondet]-> Number QueryExecutionPlan Bool Bool (List (Number AnnotatedStatement))))
(= (run-query-execution-plan $steps $plan $materialize? $expand?)
   (execution-finally (execution-query-run $steps $plan $materialize? $expand?) execution-query-finish!))

(: execution-query-run
   (-[nondet]-> Number QueryExecutionPlan Bool Bool Atom (List (Number AnnotatedStatement))))
(= (execution-query-run $steps (query-execution-plan $roots $adds) $materialize? $expand? $_unit)
   (let*
      (($_clear-temp-before (clear-temp-query-adds))
       ($_scopes (map-semidet execution-install-scope! $roots))
       ($_inject (collapse (once (inject-compiled-adds (map-flat context-addition $adds)))))
       ($goals (map-flat query-plan-runtime-goal $roots))
       ($runtime-results
          (execute-backward $steps $goals $materialize?))
       ($rows (present-query-plan-results $expand? $roots $runtime-results))
       ($_old-proofs (remove-data-rows! &query_proofs (quote ($_proof))))
       ($_answer-proofs (if $expand? () (map-flat retain-query-proof! $rows))))
      $rows))

(: execution-query-finish! (-[semidet]-> Atom Atom))
(= (execution-query-finish! $_unit)
   (let* (($_clear-overlay (context-clear!))
          ($_clear-temp (clear-temp-query-adds))
          ($_retired (sk-retire-searches!))
          ($_collected (if (deps-gc-due?) (deps-gc! (sk-deps-roots)) true))
          ($_refs (stored-refs-gc-step!)))
      ()))

;; Scope declarations are inert compiler products. Installation happens once
;; the executor owns their temporary additions and cleanup.
(: execution-install-scope! (-[semidet]-> (Number Statement AnnotatedStatement CompiledQueryGoal) Atom))
(= (execution-install-scope! ($_id $_written $_canonical $goal))
   (if (head-is? $goal query-scope)
      (let (query-scope $scope $_facts $_inner $_proof $_tv) $goal
         (let $_created (context-create! (the KBContext $scope)) ()))
      ()))

(: execution-search-goal (-[semidet]-> ExecutionGoal SkPattern))
(= (execution-search-goal $requested)
   (case $requested (
      ((query-scope $scope $facts $inner $proof $tv)
         (let* (($started (inference-clock))
                (($_kb $ctx $_vars) $scope)
                ($_prepared (context-prepare! $scope $facts $proof $tv))
                ($_seeds (map-semidet execution-register-seed! (context-seeds $ctx)))
                ($_rules (map-semidet execution-activate-rule! (context-rule-rows $ctx)))
                ($_inferred (inference-add! $started)))
            (typed-runtime-premise $inner)))
      ($_ordinary (typed-runtime-premise $requested)))))

(: execution-register-seed! (-[semidet]-> SkFact Atom))
(= (execution-register-seed! ($type $scope $_proof $_tv)) (sk-register-key! (sk-key $type $scope)))
(: execution-start-seed! (-[semidet]-> SkFact Atom))
(= (execution-start-seed! ($type $scope $_proof $_tv)) (sk-forward-start! (sk-key $type $scope)))
(: execution-activate-rule! (-[semidet]-> (Atom Number SkFact (List SkPattern)) Atom))
(= (execution-activate-rule! ($_tag $id $conclusion $premises))
   (sk-activate-rule-row $id () (sk-rule-def $conclusion $premises)))

(: context-answer-seeds! (-[semidet]-> SkPattern Atom))
(= (context-answer-seeds! $node) (let $_added (map-semidet (sk-add-answer! $node) (context-answer-keys $node)) true))

;; Independent cold reads run all their maintenance in MAIN. Locality is
;; decided from the indexed inputs actually read by the evaluator.
(: context-cold-merged (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
(= (context-cold-merged $hash $key $filter)
   (let $ctx (context-current)
      (if (if (== $ctx main) false (not (execution-local-prior? $ctx $key)))
         (context-with-scope main (|-> ($_unit) (sk-merge-open! $hash $key $filter)))
         (sk-merge-open! $hash $key $filter))))

(: execution-local-key? (-[det]-> Atom SkeletonKey Bool))
(= (execution-local-key? $ctx $key) (context-key-local? $ctx (index-hash $key) $key))
(: execution-local-inputs? (-[semidet]-> Atom Number SkeletonKey Bool))
(= (execution-local-inputs? $ctx $hash $key)
   (if (not (== (collapse (once (match &sk_row ($hash $stored $_row (sk-row $_id $_conclusion $premises $_seq))
          (if (=alpha $stored $key)
             (if (any-flat? (execution-local-key? $ctx) (fold-flat sk-direct-key-step () $premises)) true (empty))
             (empty))))) ())) true
      (case $key (
         ((sk-fold $args)
            (any-flat? (|-> ($node) (any-flat? (execution-local-key? $ctx) (sk-answers $node)))
               (sk-fold-node-member (CPU FoldAllCompiled $args $result))))
         ((sk-group $args)
            (case (sk-group-members $key $args) (
               ((sk-group-found $_member $keys) (any-flat? (execution-local-key? $ctx) $keys))
               (sk-group-missing false))))
         ((sk-prior $args)
            (any-flat? (execution-local-prior? $ctx) (sk-prior-inputs (compound-rate-goals $args false $_rate))))
         ((sk-evidence ($_kb $type $_other $scope))
            (execution-local-prior? $ctx (sk-key $type $scope)))
         ($_ordinary false)))))
(: execution-local-prior? (-[det]-> Atom SkeletonKey Bool))
(= (execution-local-prior? $ctx $key)
   (if (execution-local-key? $ctx $key) true
      (not (== (collapse (once
         (if (execution-local-inputs? $ctx (index-hash $key) $key) true (empty)))) ()))))

;; Reader-specific views matter even when their merge is dominated. Storage
;; supplies snapshots and their pairs; the executor applies the reuse policy.
(: context-propagate? (-[semidet]-> SkeletonKey Bool))
(= (context-propagate? $key)
   (if (if (== (context-current) main) false (head-is? $key sk-key))
      (let $threshold (context-reuse-threshold)
         (if (== $threshold 0) true
            (let* (($before (case (context-propagated $key) (
                       (context-unread (context-with-scope main (|-> ($_unit)
                          (context-snapshot (sk-value $key sk-any-filter ()) (context-views $key)))))
                       ($snapshot $snapshot))))
                   ((context-snapshot $old $old-views) $before)
                   ($new (sk-value $key sk-any-filter ()))
                   ($views (context-views $key)))
               (if (if (execution-numerical-change? $threshold $old $new) true
                       (any-flat? (execution-view-changed? $threshold)
                          (context-view-changes (the (List (Number SkeletonValue)) $old-views) $views)))
                  (let $_stored (context-store-propagated! $key $new $views) true)
                  false))))
      true))

(: execution-numerical-change? (-[det]-> Number SkeletonValue SkeletonValue Bool))
(= (execution-numerical-change? $threshold $old $new)
   (let $scalar (case $old (
          (sk-none (case $new (((sk-val ($_t $_s $_p (STV $_mean $_c)) $_ev $_deps) true) ($_other false))))
          ((sk-val ($type $scope $_proof (STV $_s $_c)) $_ev $_deps)
             (case $new (
                (sk-none true)
                ((sk-val ($new-type $new-scope $_p (STV $_ns $_nc)) $_ne $_nd)
                   (=alpha ($type $scope) ($new-type $new-scope)))
                ($_other false))))
          ($_other false)))
      (if $scalar (> (sk-change $new $old) $threshold) (not (sk-same-view? $new $old)))))

(: execution-context-results
   (-[semidet]-> Number Number (List ExecutionGoal) (List (List RuntimeResult)) (List (List RuntimeResult))))
(= (execution-context-results $_allowance $_reserve () ()) ())
(= (execution-context-results $allowance $reserve (cons $goal $goals) (cons $base $bases))
   (cons
      (case $goal (
         ((query-scope $scope $facts $inner $proof $tv)
            (let ($_kb $ctx $_vars) $scope
               (context-with-scope $ctx (execution-context-run $allowance $reserve $scope $facts $inner $proof $tv))))
         ($_ordinary $base)))
      (execution-context-results $allowance $reserve $goals $bases)))

(: execution-context-run
   (-[semidet]-> Number Number KBContext Statement Atom Proof TV Atom (List RuntimeResult)))
(= (execution-context-run $allowance $reserve ($kb $ctx $_vars) $facts $inner $want-proof $want-tv $_unit)
   (let* (($_allowance (execution-allowances! $allowance true))
          ($_reserve (change-state! sk_near_reserve $reserve))
          ($started (inference-clock))
          ($_holding (change-state! sk_holding 1))
          ($_refresh (sk-refresh-near!))
          ($_dirty (map-flat execution-dirty-seed! (context-seeds $ctx)))
          ($_evaluate (sk-evaluate!))
          ($_inferred (inference-add! $started))
          ($answers (sk-root-results false (typed-runtime-premise $inner)))
          ($results (collapse (let ($type $_scope $proof $tv) (superpose $answers)
             (if (terms-unifiable? ($want-proof $want-tv) ((assuming $proof) $tv))
                (brand RuntimeResult (data (Assuming $facts $type) ($kb MAIN Nil) (assuming $proof) $tv))
                (empty)))))
          ($_held (sk-stale-held!)))
      $results))

(: execution-dirty-seed! (-[det]-> SkFact Atom))
(= (execution-dirty-seed! ($type $scope $_proof $_tv))
   (let* (($key (sk-key $type $scope)) ($_dropped (sk-drop-merged! $key))) (sk-dirty! $key)))

;; Keep the typed pair destructure at this callback boundary: the compiled
;; lambda erases it and cannot certify the Boolean callback's determinism.
(: execution-view-changed? (-[det]-> Number (SkeletonValue SkeletonValue) Bool))
(= (execution-view-changed? $threshold ($before $after))
   (execution-numerical-change? $threshold $before $after))

(: chainer-many
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) (List (List RuntimeResult))))
(= (chainer-many $steps $goals) (execute-backward $steps $goals false))

(: chainer (-[nondet]-> Number (| Goal (Statement KBContext Proof TV)) (List RuntimeResult)))
(= (chainer $steps $goal) (chainer-first-or () (execute-backward $steps ($goal) false)))

(: chainer-materialize
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV)) (List RuntimeResult)))
(= (chainer-materialize $steps $goal) (chainer-first-or () (execute-backward $steps ($goal) true)))

(: chainer-many-materialize
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) (List (List RuntimeResult))))
(= (chainer-many-materialize $steps $goals) (execute-backward $steps $goals true))
