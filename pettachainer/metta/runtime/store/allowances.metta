;; Evaluation allowances, nested claims and frame lifetime.
;; The invocation controller consumes these operations and owns finally brackets.

!(change-state! sk_branch_budget 0)
!(change-state! sk_graph_budget 0)
!(change-state! sk_root_claim_budget 0)
!(change-state! sk_root_claim_cap 0)
!(change-state! sk_branch_at 0)
;; Work this backward run refused or left unpaid (query-many-with-status).
!(change-state! sk_ran_out 0)

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
          ;; Event-graph numeric work has a tier as large as the allowance (event_graph.pl).
          ($_graph (change-state! sk_graph_budget $units))
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
          ($_position (change-state! sk_branch_at 0))
          ($_cuts (remove-data-rows! &sk_branch_cuts (quote ($_stored-frame $_stored-exclude $_stored-cuts))))) ()))

(: sk-open-claim! (-[det]-> Atom))
(= (sk-open-claim!)
   (progn (change-state! sk_claim_state 0) (change-state! sk_claim_cut 0) ()))
(: sk-close-claim! (-[det]-> Bool))
(= (sk-close-claim!)
   (let $exhausted (== (search-id-value sk_claim_state) -2)
      (progn (change-state! sk_claim_state -1) (change-state! sk_claim_cut 0) $exhausted)))


(: sk-evaluation-free-depth (-[det]-> Number))
(= (sk-evaluation-free-depth) (if (== (search-id-value sk_forward_run) 1) 0 2))
(: sk-evaluation-near-root-reserve (-[det]-> Number))
(= (sk-evaluation-near-root-reserve) 8)
