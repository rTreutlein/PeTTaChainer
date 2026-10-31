;; Backward query lifecycle, materialization, metrics and public entry points.
;; The evaluator modules are loaded in dependency order by bootstrap.metta.


(: instance-prior-tv (-[det]-> KB Proof TV TV))
(= (instance-prior-tv $kb $proof $tv)
   (case (sk-prior-update-of $kb $proof $tv) (
      ((sk-prior-update $_source (prior $read) ()) (the TV $read))
      ($_updated $tv))))

(: set-rule-change-hazard (-[det]-> KB Number Bool))
(= (set-rule-change-hazard $kb $hazard)
   (let* (($_old (remove-data-rows! &rule_change_hazard (quote ($kb $_stored))))
          ($_new (add-atom &rule_change_hazard ($kb $hazard)))
          ($_changed (hazards-changed!)))
      (> $hazard 0.0)))

;; The owner of a cold merge controls all maintenance performed by the read.
;; Independent reads in C execute this operation in MAIN; dependent reads keep
;; the overlay active, including conditioning and aggregate maintenance.
(: sk-merge-open! (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
(= (sk-merge-open! $hash $key $filter)
   (let* (($_counted (query_metric_increment merged-cache-misses))
          ($root (sk-root-claim? () $hash $key))
          ;; Changing roots changes which overlaps may be claimed. Clear old
          ;; requests before recomputing; a fresh request survives publication.
          ($_policy (collapse (once (match &ctx_sk_merged ($hash $stored $_deps $_value $cached-root)
             (if (=alpha $stored $key) (if (== $root $cached-root) () (sk-drop-merged! $key)) (empty))))))
          ($views (map-flat sk-version-view (sk-admitted-versions $hash $key $filter ())))
          ($leaves (sk-leaf-views $hash $key $filter ()))
          ($source-deps (fold-semidet sk-view-deps-step 0 (append-flat $leaves $views)))
          ($value (sk-merge-key $hash $key $filter () () $views))
          ($deps (sk-view-deps-step $source-deps $value))
          ($_inner (sk-uncache! $hash $key))
          ($_cached (context-add! &sk_merged ($hash $key $deps $value $root)))
          ($_factor (sk-note-truth-factor! $hash $key $value)))
      (sk-merged $hash $key $deps $value)))

;; A rule truth's new value rescores the rules that read it.
(: sk-note-truth-factor! (-[det]-> Number SkeletonKey SkeletonValue Atom))
(= (sk-note-truth-factor! $hash $key $value)
   (if (sk-rule-truth-key? $key)
      (case $value (
         ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) (sk-set-truth-factor! $hash (rule-truth-factor $tv)))
         ($_none ())))
      ()))

;; --- Base-rate API ----------------------------------------------------------

;; Setting or clearing a user base rate changes the folds over its pattern,
;; which recompute with their readers at the next evaluation, and adds or
;; withdraws the positive-only rows reading it. A rate is set on its
;; pattern's canonical key: one on (Not X) is the complement's on X.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $statement $rate)
   (let* ((($pattern $odd) (canon (brand Statement (member-canon $statement))))
          ($_valid (validate-base-rate! $statement (conjunct-parts (rate-children $pattern)) $rate))
          ($tv (case (data $odd $rate) (((true (STV $s $c)) (STV (- 1.0 $s) $c)) ($_even $rate))))
          ($_input (sk-input-changed! $kbid))
          ($_new (ledger-set-base-rate! $kbid $pattern $tv))
          ($_gated (prior-gated-rate-changed! $kbid $pattern)))
      (base-rate-readers-changed! $kbid $pattern)))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $statement)
   (let* ((($pattern $_odd) (canon (brand Statement (member-canon $statement))))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_input (sk-input-changed! $kbid))
          ($_gated (prior-gated-rate-changed! $kbid $pattern)))
      (base-rate-readers-changed! $kbid $pattern)))

;; --- Materialization --------------------------------------------------------

(: materializable-result? (-[det]-> SkFact Bool))
;; A positive implication judgment is a query result, never a world fact.
(= (materializable-result? ($type ($_kbid $ctx $vars) $_prf $tv))
   (if (if (head-is-member? $type (Implication QuantifiedRule)) false (== $ctx MAIN))
      (if (if (head-is-member? $type (ExistsJudgment ExistentialAlternatives)) false (== $vars Nil))
         (if (== (extract-vars $type) ())
            (case $tv (((STV $_s $_c) (== (extract-vars $tv) ())) ($_other false)))
            false)
         false)
      false))

(: sk-materialize! (-[semidet]-> SkeletonValue Atom))
(= (sk-materialize! $value)
   (case $value (
      ((sk-val $fact $ev $_deps)
         (if (materializable-result? $fact)
            (kb-publish-materialized! (sk-full-fact $fact) $ev (proof-atom-proof $fact))
            ()))
      ($_other ()))))

;; The stored proofs a proof term refers to directly.
(: sk-proof-refs (-[det]-> Atom (List Number)))
(= (sk-proof-refs $term)
   (if (is-expr $term)
      (case $term (((proof-ref $pid) (cons $pid ())) ($_other (sk-proof-refs-in $term))))
      ()))
(: sk-proof-refs-in (-[det]-> Atom (List Number)))
;; Atom parameters take their arguments unevaluated, so each part is bound first.
(= (sk-proof-refs-in $terms)
   (if (== $terms ()) ()
      (let* (($first (car-atom $terms)) ($rest (cdr-atom $terms)))
         (append-flat (sk-proof-refs $first) (sk-proof-refs-in $rest)))))

;; A materialized answer brings the derived facts of its proof along: each
;; stored fact proof it uses materializes that statement's current value, once.
(: sk-materialize-ref! (-[semidet]-> KBContext (List Number) Number (List Number)))
(= (sk-materialize-ref! $kbctx $visited $pid)
   (if (stored-list-member? $pid $visited) $visited
      (let* (($_fact
                (case (collapse (once (match &proof_fact ($pid $statement $_tv) $statement))) (
                   ((cons $statement $_rest) (sk-materialize! (sk-value (sk-key $statement $kbctx) sk-any-filter ())))
                   (() ()))))
             ($step (sk-step-proof (proof-ref $pid))))
         (fold-semidet (sk-materialize-ref! $kbctx) (cons $pid $visited) (sk-proof-refs $step)))))

(: sk-materialize-answer! (-[semidet]-> SkeletonValue Atom))
(= (sk-materialize-answer! $value)
   (let $_answer (sk-materialize! $value)
      (case $value (
         ((sk-val ($type $kbctx $proof $tv) $_ev $_deps)
            ;; A judgment's premises belong to its hypothetical world; they
            ;; are not observations to materialize in the result's MAIN scope.
            (if (head-is-member? $type (Implication QuantifiedRule)) ()
               (let $_derived (fold-semidet (sk-materialize-ref! $kbctx) () (sk-proof-refs (sk-step-proof $proof))) ())))
         ($_other ())))))

;; --- Query metrics ----------------------------------------------------------

(: set-backward-query-metrics (-[det]-> Bool Bool))
(= (set-backward-query-metrics $enabled) (query_metrics_set_enabled $enabled))

(: backward-query-counter-keys (-[det]-> (List Atom)))
(= (backward-query-counter-keys)
   (expansions nodes-walked rows-created rows-deferred joins-deferred row-computes views-stored
    views-without-support merged-cache-hits merged-cache-misses conditioned-evaluations rows-unpaid
    conditions-unpaid representative-reads branch-cache-hits branch-cache-misses branch-builds branch-cache-refreshes))

(: sk-counter-reset (-[det]-> Atom Atom Atom))
(= (sk-counter-reset $_acc $key) (let $_zero (query_metric_set $key 0) ()))

(: sk-size-metrics! (-[det]-> Atom Atom Number))
(= (sk-size-metrics! $nodes $rows)
   (let $_nodes (query_metric_set $nodes (match-count &sk_expanded $_node))
      (query_metric_set $rows (match-count &sk_row $_row))))

(: begin-backward-query-metrics! (-[det]-> Number))
(= (begin-backward-query-metrics!)
   (if (query_metrics_enabled)
      (let $_reset (fold-flat sk-counter-reset () (backward-query-counter-keys))
         (sk-size-metrics! skeleton-nodes-before skeleton-rows-before))
      0))

(: end-backward-query-metrics! (-[det]-> Number))
(= (end-backward-query-metrics!)
   (if (query_metrics_enabled) (sk-size-metrics! skeleton-nodes-after skeleton-rows-after) 0))
(: sk-metric-row (-[det]-> Atom BackwardQueryMetric))
(= (sk-metric-row $key) (query-metric $key (query_metric_value $key)))

(: backward-query-metrics (-[det]-> (List BackwardQueryMetric)))
(= (backward-query-metrics)
   (map-flat sk-metric-row
      (cons skeleton-nodes-before (cons skeleton-nodes-after
         (cons skeleton-rows-before (cons skeleton-rows-after (backward-query-counter-keys)))))))

;; --- Entry points -----------------------------------------------------------

(: sk-clash-waiting (-[semidet]-> Number SkeletonKey Number SkeletonFilter SkeletonRow SkeletonValue))
(= (sk-clash-waiting $hash $key $rhash $filter $row)
   (let* (((sk-row $_ident ($_type $_scope $proof $_tv) $_premises $_seq) $row)
          ($exclude (sk-row-exclusions $hash $key $proof))
          ($representative (sk-representative-row () $hash $key $rhash () $row))
          ((sk-val $fact $_ev $_deps) $representative))
      (if (sk-fact-matches? $filter $fact)
         (let $independent (sk-row-result $row (sk-row-state () $exclude $hash sk-independent-read $row))
            (sk-read-value $filter
               (sk-discounted $representative $independent (term-confidence $fact)))) sk-none)))

(: sk-waiting-root-value (-[semidet]-> SkeletonFilter SkeletonKey (| SkeletonValue SkeletonWaitingAnswer)))
(= (sk-waiting-root-value $filter $key)
   (case (sk-value $key $filter ()) (
      (sk-none
         (let* (($hash (index-hash $key))
                ($ignore (sk-unifier-hashes $hash $key))
                ($before (search-id-value sk_representative_budget))
                ($room (min 128 $before))
                ($_slice (change-state! sk_representative_budget $room))
                ($waiting (fold-semidet (sk-merge-step (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) true $ignore) sk-none
                   (collapse (match &ctx_sk_given_pending ($hash $rhash $_cost)
                      (match &sk_row ($hash $stored $rhash $row)
                         (if (=alpha $stored $key)
                            (sk-clash-waiting $hash $key $rhash $filter (copy_term $row)) (empty)))))))
                ($_restored (change-state! sk_representative_budget
                   (- $before (- $room (search-id-value sk_representative_budget))))))
            (if (== $waiting sk-none) sk-none (sk-waiting $waiting))))
      ($value $value))))

;; A materialized answer is the result an earlier query left, not independent
;; evidence: the root falls back to it when the search has no value for the key.
;; A root's proof and truth-value pattern may share variables with its
;; statement, so each key is read with the pattern instantiated by that key.
;; A complete statement whose settled search found no rule application is
;; unfounded, as to any reader (sk-closed-read).
(: sk-root-key-value (-[semidet]-> SkPattern SkeletonKey (| SkeletonValue SkeletonWaitingAnswer)))
(= (sk-root-key-value $goal $key)
   (case (copy_term $goal) (
      ((CPU $_fun $_args $_res) sk-none)
      (($type $kbctx $proof $tv)
         (let $ground (== (extract-vars $type) ())
            (if (= (sk-key $type $kbctx) (copy_term $key))
               (let $filter (sk-filter $proof $tv)
                  (case (event-network-read $key $filter () (ev-set 0)) (
                     ((event-posterior $posterior) $posterior)
                     (no-event-model
                        (case (sk-waiting-root-value $filter $key) (
                           (sk-none
                              (case (sk-closed-read sk-greedy-read () () () $key $filter) (
                                 (sk-none
                                    (if $ground
                                       (case (sk-materialized-views $type $kbctx $filter) (
                                          ((cons $incumbent $_rest) $incumbent)
                                          (() (sk-population-prior $type $kbctx $filter))))
                                       sk-none))
                                 ($unfounded $unfounded))))
                           ($current $current)))))))
               sk-none))))))

(: sk-materialized-views (-[det]-> Statement KBContext SkeletonFilter (List SkeletonValue)))
(= (sk-materialized-views $type $kbctx $filter)
   (let $hash (forward-output-index-hash (forward-output-key $kbctx $type))
      (collapse (match &materialized_facts (materialized-row $hash $type $kbctx $fact $ev)
         (if (sk-fact-matches? $filter $fact) (sk-val $fact $ev 0) (empty))))))

;; A ground root the search left without a value answers with the base rate
;; of its population: a base rate one of its rules reads over a pattern its
;; statement belongs to, the prior its inversions update. It costs no
;; expansion, so a root the budget did not reach still has an estimate, with
;; the confidence of the members counted; any view the search finds replaces
;; it. It is the prior an inversion reads (population-prior-tv), and a
;; positive-only predicate has none. The prior is the population's value, not
;; the statement's, and is never materialized. A statement nothing derives
;; gets the same prior as a row once expanded (sk-start-prior!).
(: sk-population-prior (-[semidet]-> Statement KBContext SkeletonFilter SkeletonValue))
(= (sk-population-prior $type $kbctx $filter)
   (case (sk-prior-folds $type (collapse (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_proof $_tv)))) (
      ((cons (sk-prior-fold $_rule $args) $_more)
         (case (sk-value (sk-fold $args) sk-any-filter ()) (
            ((sk-goal-val (CPU $_fun $_args (STV $s $c)) $_fold-proof $_ev $deps)
               (let* (($prior (configured-population-prior-tv (brand KB (car-atom $args)) (brand Statement (car-atom (cdr-atom $args))) (STV $s $c)))
                      ($fact (data $type $kbctx (brand Proof (population-prior (car-atom (cdr-atom $args)))) $prior)))
                  (if (sk-fact-matches? $filter $fact) (sk-val $fact (ev-set 0) $deps) sk-none)))
            ($_none sk-none))))
      (() sk-none))))

;; A typed boundary shared by grouped roots and forward evaluation.
(: sk-key-value (-[semidet]-> SkeletonKey SkeletonValue))
(= (sk-key-value $key) (sk-value $key sk-any-filter ()))

(: sk-root-values (-[semidet]-> SkPattern (List (| SkeletonValue SkeletonWaitingAnswer))))
(= (sk-root-values $goal)
   (case $goal (
      ((CPU $fun $args $res)
         (if (aggregate-fold-function? $fun) (map-semidet sk-key-value (sk-root-keys $goal))
            (collapse (let $result (cpu-call 0 $fun $args)
               (if (= $res $result)
                  (sk-goal-val (CPU $fun $args $result) (brand Proof cpu) (ev-set 0) 0)
                  (empty))))))
      ($_fact (map-semidet (sk-root-key-value $goal) (sk-root-keys $goal))))))

(: sk-result-step (-[semidet]-> (List RuntimeResult) (| SkeletonValue SkeletonWaitingAnswer) (List RuntimeResult)))
(= (sk-result-step $kept $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (cons (brand RuntimeResult $fact) $kept))
      ((sk-goal-val $goal $_proof $_ev $_deps) (cons (brand RuntimeResult $goal) $kept))
      ((sk-waiting $waiting) (sk-result-step $kept $waiting))
      (sk-none $kept))))

;; Proven answers in root order without redundant instances; a materializing
;; query writes back the first that is not a population prior. An answer's
;; proof is as its value holds it, references into &proof; only output
;; expands it.
(: sk-root-results (-[semidet]-> Bool SkPattern (List RuntimeResult)))
(= (sk-root-results $materialize? $goal)
   (let* (($values (sk-root-values $goal))
          ($_materialized
             (if $materialize?
                (case (collapse (once (let $value (superpose $values)
                         (case $value (
                            (sk-none (empty))
                            ((sk-waiting $_waiting) (empty))
                            ($found (if (sk-population-prior? $found) (empty) $found))))))) (
                   ((cons $first $_rest) (sk-materialize-answer! $first))
                   (() ())))
                ()))
          ($answers (fold-semidet sk-cons-step () (fold-semidet sk-result-step () $values))))
      (prune_answer_instances $answers)))

;; A root's producers are part of its scaffold and installed even when the
;; budget expands nothing.
(: sk-root-score-step (-[semidet]-> Atom SkPattern Atom))
(= (sk-root-score-step $_acc $goal)
   (let* (($hash (sk-node-hash $goal))
          ($_root (add-atom &sk_roots ($hash $goal)))
          ($_indexed (sk-index-node! $goal))
          ($_member
             (case (copy_term $goal) (
                ((CPU $_fun $_args $_res) ())
                (($type $kbctx $_proof $_tv)
                   (let $_producers (install-producers! temp $type $kbctx) (install-class-link-rules! $type $kbctx)))))))
      (sk-raise-score! $hash $goal 1.0)))

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $requested $materialize?)
   (let* (($_value-caches (sk-clear-query-values!))
          ($_representative-budget (change-state! sk_representative_budget 256))
          ;; a claim or branch frame an exception left open is closed
          ($_claim (sk-close-claim!))
          ($_branch-frame (change-state! sk_branch_at 0))
          ($_branch-cuts (remove-data-rows! &sk_branch_cuts (quote ($_frame $_exclude $_cuts))))
          ($goals (map-flat context-search-goal $requested))
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
          ($_evaluation (change-state! sk_eval_budget (* (sk-evaluation-per-step) $steps)))
          ($_root-claims (change-state! sk_root_claim_budget
             (min (sk-root-claim-limit) (floor-math (* (* (sk-evaluation-per-step) $steps) (sk-root-claim-share))))))
          ($_root-cap (change-state! sk_root_claim_cap (search-id-value sk_root_claim_budget)))
          ($_branches (change-state! sk_branch_budget (* (* (sk-evaluation-per-step) $steps) (sk-branch-share))))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) $steps)))
          ($_pushes (change-state! sk_push_seq 0))
          ($_context-start (context-start!))
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
          ($results (context-finish! (* (sk-evaluation-per-step) $steps) $context-reserve $requested $main-results))
          ($_temp (sk-clear-temp!)))
      $results))

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
