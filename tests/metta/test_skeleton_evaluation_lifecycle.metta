!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd lifecycleKb (: seed (Input a) (STV 1.0 0.8)))
!(compileadd lifecycleKb (: (no_inverse step) (Implication (Input a) (Output a)) (CTV (STV 1 1) (STV 0 1))))
!(test (length (collapse (query 200 lifecycleKb (: $p (Output a) $tv)))) 1)

;; Three unchanged queries reuse the same publications, without computing
;; rows, allocating class nodes, or allocating fresh proof identifiers.
!(test
   (let* (($before (search-id-value proof_id))
          ($_metrics (begin-backward-query-metrics!))
          ($_one (query 200 lifecycleKb (: $p (Output a) $tv)))
          ($_two (query 200 lifecycleKb (: $p (Output a) $tv)))
          ($_three (query 200 lifecycleKb (: $p (Output a) $tv))))
      (data (query_metric_value row-computes)
            (query_metric_value context-nodes-created)
            (query_metric_value merged-cache-misses)
            (== (search-id-value proof_id) $before)))
   (0 0 0 true))
!(test (collapse (match &sk_context_queued ($_id $_priority) true)) ())

;; A changed input publishes through the producer-node subscriptions. The
;; result has the new strength; no stale result is served in its place.
!(compileadd lifecycleKb (: observed (Input a) (STV 0 1)))
!(test (let (: $_proof $_type (STV $s $_c)) (query 200 lifecycleKb (: $p (Output a) $tv)) $s) 0)
!(test (not (== (collapse (match &sk_context_reader ($_producer $_reader) true)) ())) true)
