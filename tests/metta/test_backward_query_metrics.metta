!(import! &self ../../pettachainer/metta/petta_chainer)

!(test
   (backward-query-counter-keys)
   (agenda-pushes
    agenda-pops
    search-aborts
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
    proofs-stored))

!(test
   (let* (($_enabled (set-backward-query-metrics true))
          ($_seed
             (map-flat
                (|-> ($key)
                   (query_metric_set $key 7))
                (backward-query-counter-keys)))
          ($_begin (begin-backward-query-metrics!)))
      (map-flat
         query_metric_value
         (backward-query-counter-keys)))
   (0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0))

;; Every proof-live? call records one native liveness event. A retired proof is
;; still a check, but is neither a cache hit nor a cache miss.
!(test
   (let*
      (($_query (clear-backward-query-state!))
       ($goal
          (assemble-runtime-fact
             (MetricLive)
             (brand KBContext (kb MAIN ()))
             (brand Proof $proof)
             (the TV $tv)))
       ($gid (ensure-goal-at-depth $goal 0))
       ($pid
          (store-proof-candidate $gid
             (proof-candidate
                (leaf
                   (assemble-runtime-fact
                      (MetricLive)
                      (brand KBContext (kb MAIN ()))
                      (brand Proof metricLive)
                      (the TV (STV 1.0 0.8))))
                0.8 () ())))
       ($_uncached
          (remove-atom &proof_live_cache
             (proof-live-cache-row $pid true)))
       ($_begin (begin-backward-query-metrics!))
       ($miss (proof-live? $pid))
       ($hit (proof-live? $pid))
       ($_retired (once (add-atom &proof_retired ($pid))))
       ($retired (proof-live? $pid)))
      ($miss $hit $retired
       (query_metric_value proof-liveness-checks)
       (query_metric_value proof-liveness-cache-hits)
       (query_metric_value proof-liveness-cache-misses)))
   (true true false 3 1 1))

!(set-backward-query-metrics false)
