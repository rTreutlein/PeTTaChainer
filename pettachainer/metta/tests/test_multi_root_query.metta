!(import! &self ../petta_chainer)

!(compileadd batchKb (: batch-a (BatchA) (STV 1.0 1.0)))
!(compileadd batchKb (: batch-b (BatchB) (STV 0.5 0.8)))
!(compileadd batchKb (: batch-c1 (BatchC one) (STV 1.0 1.0)))
!(compileadd batchKb (: batch-c2 (BatchC two) (STV 1.0 1.0)))

;; Reusing the same source variable names in different roots must not couple
;; their compiled query contexts. Results retain input order and empty roots.
!(test
   (collapse
      (query-many 3 batchKb
         ((: $prf (BatchA) $tv)
          (: $prf (BatchB) $tv)
          (: $prf (BatchMissing) $tv)
          (: $prf (BatchC $x) $tv))))
   ((query-result 0 (: batch-a (BatchA) (STV 1.0 1.0)))
    (query-result 1 (: batch-b (BatchB) (STV 0.5 0.8)))
    (query-result 3 (: batch-c1 (BatchC one) (STV 1.0 1.0)))
    (query-result 3 (: batch-c2 (BatchC two) (STV 1.0 1.0)))))

!(test
   (collapse
      (query-many 0 batchKb
         ((: $prf (BatchA) $tv)
          (: $prf (BatchB) $tv))))
   ())

;; Query-local compiler additions for compound roots are installed beside the
;; other roots once and remain isolated by their compiled contexts.
!(test
   (collapse
      (query-many 10 batchKb
         ((: $prf (And (BatchA) (BatchB)) $tv)
          (: $prf (BatchA) $tv))))
   ((query-result 0
       (: (conjunction batch-a batch-b)
          (And (BatchA) (BatchB))
          (STV 0.5 0.7999999999359401)))
    (query-result 1 (: batch-a (BatchA) (STV 1.0 1.0)))))

!(test
   (let $_set (change-state! bwd_root_count 1500)
      (let $target (bounded-agenda-target-size 1)
         (progn
            (change-state! bwd_root_count 0)
            $target)))
   1500)

!(compileadd sharedBatchKb
   (: shared-batch-fact (SharedBatchPremise) (STV 1.0 1.0)))
!(compileadd sharedBatchKb
   (: shared-to-left
      (Implication (SharedBatchPremise) (SharedBatchLeft))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd sharedBatchKb
   (: shared-to-right
      (Implication (SharedBatchPremise) (SharedBatchRight))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Both roots share one indexed subgoal and one proof computation.
!(test
   (let $_results
      (collapse
         (query-many 6 sharedBatchKb
            ((: $prf (SharedBatchLeft) $tv)
             (: $prf (SharedBatchRight) $tv))))
      (length
         (collapse
            (match &goal
               (stored-goal-row $_gid $_depth
                  ((SharedBatchPremise) (sharedBatchKb MAIN Nil) $_prf $_tv)
                  $_expanded $_pending)
               shared-goal))))
   1)

!(compileadd materializeBatchKb
   (: materialize-batch-seed
      (MaterializeBatchSeed) (STV 1.0 1.0)))
!(compileadd materializeBatchKb
   (: materialize-batch-rule
      (Implication (MaterializeBatchSeed) (MaterializeBatchRoot))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Batch materialization writes the same selected representative that readback
;; returned, including the incumbent fallback path.
!(test
   (let $_results
      (collapse
         (query-many-materialize 3 materializeBatchKb
            ((: $prf (MaterializeBatchRoot) $tv))))
      (not
         (==
            (collapse
               (match &kb
                  ((MaterializeBatchRoot)
                     (materializeBatchKb MAIN Nil) $_prf $_tv)
                  true))
            ())))
   true)
