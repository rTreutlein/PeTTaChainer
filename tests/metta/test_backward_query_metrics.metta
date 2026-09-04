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
   (0 0 0 0 0 0 0 0 0 0 0 0 0))


!(set-backward-query-metrics false)
