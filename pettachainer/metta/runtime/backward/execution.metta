;; Invocation controller: discovery, evaluation and scoped presentation.

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
             (if (=? (data $want-proof $want-tv) ((assuming $proof) $tv))
                (brand RuntimeResult (data (Assuming $facts $type) ($kb MAIN Nil) (assuming $proof) $tv))
                (empty)))))
          ($_held (sk-stale-held!)))
      $results))

(: execution-dirty-seed! (-[det]-> SkFact Atom))
(= (execution-dirty-seed! ($type $scope $_proof $_tv))
   (let* (($key (sk-key $type $scope)) ($_dropped (sk-drop-merged! $key))) (sk-dirty! $key)))

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
