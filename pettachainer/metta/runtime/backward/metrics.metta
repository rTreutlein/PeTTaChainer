;; Opt-in counters for diagnosing bounded backward-query cost. The metrics
;; space is query-local diagnostic state: it is never consulted by reasoning.

(: backward-query-metrics-enabled? (-[det]-> Bool))
(= (backward-query-metrics-enabled?)
   (let $enabled
      (collapse
         (once
            (match &backward_query_metrics_config
               ($value) $value)))
      (if (== $enabled ()) false (the Bool (car-atom $enabled)))))

(: set-backward-query-metrics (-[det]-> Bool Bool))
(= (set-backward-query-metrics $enabled)
   (let $_old
      (collapse
         (match &backward_query_metrics_config
            ($_value)
            (remove-atom &backward_query_metrics_config ($_value))))
      (let $_new
         (collapse
            (once
               (add-atom &backward_query_metrics_config ($enabled))))
         $enabled)))

(: backward-query-metric-value (-[det]-> Atom Number))
(= (backward-query-metric-value $key)
   (let $values
      (collapse
         (once
            (match &backward_query_metrics
               ($key $value) $value)))
      (if (== $values ()) 0 (the Number (car-atom $values)))))

(: set-backward-query-metric! (-[det]-> Atom Number Number))
(= (set-backward-query-metric! $key $value)
   (if (backward-query-metrics-enabled?)
      (let $_removed
         (collapse
            (match &backward_query_metrics
               ($key $_old)
               (remove-atom &backward_query_metrics ($key $_old))))
         (let $_added
            (collapse
               (once
                  (add-atom &backward_query_metrics ($key $value))))
            $value))
      $value))

(: increment-backward-query-metric! (-[det]-> Atom Number))
(= (increment-backward-query-metric! $key)
   (if (backward-query-metrics-enabled?)
      (set-backward-query-metric! $key
         (+ 1 (backward-query-metric-value $key)))
      0))

(: begin-backward-query-metrics! (-[det]-> Number))
(= (begin-backward-query-metrics!)
   (if (backward-query-metrics-enabled?)
      (let* (($_clear
                (collapse
                   (match &backward_query_metrics $row
                      (remove-atom &backward_query_metrics $row))))
              ($_proofs
                (set-backward-query-metric! durable-proof-rows-before
                   (length
                      (collapse
                         (match &proof $row $row)))))
              ($_goal-index
                (set-backward-query-metric! durable-goal-index-rows-before
                   (length
                      (collapse
                         (match &proof_goal $row $row)))))
              ($_result-index
                (set-backward-query-metric! durable-result-index-rows-before
                   (length
                      (collapse
                         (match &proof_result $row $row)))))
              ($_parent-index
                (set-backward-query-metric! durable-parent-edge-rows-before
                   (length
                      (collapse
                         (match &proof_parent $row $row)))))
              ($_pid-boundary
                (set-backward-query-metric! durable-pid-boundary
                   (search-id-value bwd_pid))))
         0)
      0))

(: end-backward-query-metrics! (-[det]-> Number))
(= (end-backward-query-metrics!)
   (set-backward-query-metric! durable-proof-rows-after
      (length (collapse (match &proof $row $row)))))

(: BackwardQueryMetric Type)
(: query-metric (-[det]-> Atom Number BackwardQueryMetric))
(: backward-query-metric-row (-[det]-> Atom BackwardQueryMetric))
(= (backward-query-metric-row $key)
   (query-metric $key (backward-query-metric-value $key)))

(: backward-query-metrics (-[det]-> (List BackwardQueryMetric)))
(= (backward-query-metrics)
   (map-flat backward-query-metric-row
      (durable-proof-rows-before
       durable-proof-rows-after
       durable-goal-index-rows-before
       durable-result-index-rows-before
       durable-parent-edge-rows-before
       agenda-pushes
       agenda-pops
       stale-agenda-entries
       goal-demand-evaluations
       goal-demand-cache-hits
       goal-demand-cache-misses
       demand-revision-bumps
       proof-liveness-checks
       proof-liveness-cache-hits
       proof-liveness-cache-misses
       durable-proof-considerations
       candidate-comparisons
       dominance-checks
       proofs-stored)))
