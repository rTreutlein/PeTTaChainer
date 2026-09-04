;; Opt-in counters for diagnosing bounded backward-query cost. Native scalar
;; storage keeps disabled hooks cheap and is never consulted by reasoning.

(: query_metrics_enabled (-[det]-> Bool))
(: query_metrics_set_enabled (-[det]-> Bool Bool))
(: query_metric_value (-[det]-> Atom Number))
(: query_metric_set (-[det]-> Atom Number Number))
(: query_metric_increment (-[det]-> Atom Number))
(: query_metric_liveness_event (-[det]-> Atom Atom))

(: set-backward-query-metrics (-[det]-> Bool Bool))
(= (set-backward-query-metrics $enabled)
   (query_metrics_set_enabled $enabled))

(: increment-backward-query-metric! (-[det]-> Atom Number))
(= (increment-backward-query-metric! $key)
   (query_metric_increment $key))

(: backward-query-counter-keys (-[det]-> (List Atom)))
(= (backward-query-counter-keys)
   (agenda-pushes
    agenda-pops
    search-aborts
    stale-agenda-entries
    goal-demand-evaluations
    goal-demand-cache-hits
    goal-demand-cache-misses
    demand-revision-bumps
    current-proof-goal-lookups
    current-result-goal-lookups
    candidate-comparisons
    dominance-checks
    proofs-stored))

(: set-space-row-count-metric! (-[det]-> Atom $space Number))
(= (set-space-row-count-metric! $key $space)
   (query_metric_set $key (match-count $space $_row)))

(: begin-backward-query-metrics! (-[det]-> Number))
(= (begin-backward-query-metrics!)
   (if (query_metrics_enabled)
      (let* (($_clear
                (map-flat
                   (|-> ($key) (query_metric_set $key 0))
                   (backward-query-counter-keys)))
              ($_proofs
                (set-space-row-count-metric!
                   durable-proof-rows-before &proof))
              ($_goal-index
                (set-space-row-count-metric!
                   durable-goal-index-rows-before &proof_goal))
              ($_result-index
                (set-space-row-count-metric!
                   durable-result-index-rows-before &proof_result))
              ($_pid-boundary
                (query_metric_set durable-pid-boundary
                   (search-id-value bwd_pid))))
         0)
      0))

(: end-backward-query-metrics! (-[det]-> Number))
(= (end-backward-query-metrics!)
   (set-space-row-count-metric! durable-proof-rows-after &proof))

(: BackwardQueryMetric Type)
(: query-metric (-[det]-> Atom Number BackwardQueryMetric))
(: backward-query-metrics (-[det]-> (List BackwardQueryMetric)))
(= (backward-query-metrics)
   (map-flat
      (|-> ($key) (query-metric $key (query_metric_value $key)))
      (cons durable-proof-rows-before
         (cons durable-proof-rows-after
            (cons durable-goal-index-rows-before
               (cons durable-result-index-rows-before
                  (backward-query-counter-keys)))))))
