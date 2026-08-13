;; Opt-in counters for diagnosing bounded backward-query cost. Native scalar
;; storage keeps disabled hooks cheap and is never consulted by reasoning.

(: query_metrics_enabled (-[det]-> Bool))
(: query_metrics_set_enabled (-[det]-> Bool Bool))
(: query_metric_value (-[det]-> Atom Number))
(: query_metric_set (-[det]-> Atom Number Number))
(: query_metric_increment (-[det]-> Atom Number))

(: backward-query-metrics-enabled? (-[det]-> Bool))
(= (backward-query-metrics-enabled?)
   (query_metrics_enabled))

(: set-backward-query-metrics (-[det]-> Bool Bool))
(= (set-backward-query-metrics $enabled)
   (query_metrics_set_enabled $enabled))

(: backward-query-metric-value (-[det]-> Atom Number))
(= (backward-query-metric-value $key)
   (query_metric_value $key))

(: set-backward-query-metric! (-[det]-> Atom Number Number))
(= (set-backward-query-metric! $key $value)
   (query_metric_set $key $value))

(: increment-backward-query-metric! (-[det]-> Atom Number))
(= (increment-backward-query-metric! $key)
   (query_metric_increment $key))

(: begin-backward-query-metrics! (-[det]-> Number))
(= (begin-backward-query-metrics!)
   (if (backward-query-metrics-enabled?)
      (let* (($_clear
                (map-flat
                   (|-> ($key)
                      (set-backward-query-metric! $key 0))
                   (agenda-pushes
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
                    current-proof-goal-lookups
                    current-result-goal-lookups
                    candidate-comparisons
                    dominance-checks
                    proofs-stored)))
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
       current-proof-goal-lookups
       current-result-goal-lookups
       candidate-comparisons
       dominance-checks
       proofs-stored)))
