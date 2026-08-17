!(import! &self ../../pettachainer/metta/petta_chainer)

!(test
   (backward-query-counter-keys)
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
    proofs-stored))

!(test
   (let* (($_enabled (set-backward-query-metrics true))
          ($_seed
             (map-flat
                (|-> ($key)
                   (set-backward-query-metric! $key 7))
                (backward-query-counter-keys)))
          ($_begin (begin-backward-query-metrics!)))
      (map-flat
         backward-query-metric-value
         (backward-query-counter-keys)))
   (0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0))

!(set-backward-query-metrics false)
