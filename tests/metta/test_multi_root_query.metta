!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd batchKb (: batch-a (BatchA) (STV 1.0 1.0)))
!(compileadd batchKb (: batch-b (BatchB) (STV 0.5 0.8)))
!(compileadd batchKb (: batch-c1 (BatchC one) (STV 1.0 1.0)))
!(compileadd batchKb (: batch-c2 (BatchC two) (STV 1.0 1.0)))

;; Reusing the same source variable names in different roots must not couple
;; their compiled query contexts. Results retain input order and empty roots.
!(test
   (collapse
      (query-many 7 batchKb
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
   ((query-result 0 (: batch-a (BatchA) (STV 1.0 1.0)))
    (query-result 1 (: batch-b (BatchB) (STV 0.5 0.8)))))

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
            (match &sk_expanded
               ($_hash ((SharedBatchPremise) (sharedBatchKb MAIN Nil) $_prf $_tv))
               shared-goal))))
   1)

;; A node's priority is the best score any join waiting on it gives it, however
;; many roots share it, so the more useful proof of one root (0.3) is searched
;; before the proof two roots share (0.2 each).
!(compileadd summedDemandKb
   (: summed-shared-fact (SummedSharedPremise) (STV 1.0 1.0)))
!(compileadd summedDemandKb
   (: summed-single-fact (SummedSinglePremise) (STV 1.0 1.0)))
!(compileadd summedDemandKb
   (: summed-shared-left
      (Implication (SummedSharedPremise) (SummedSharedLeft))
      (CTV (STV 1.0 0.2) (STV 0.01 1.0))))
!(compileadd summedDemandKb
   (: summed-shared-right
      (Implication (SummedSharedPremise) (SummedSharedRight))
      (CTV (STV 1.0 0.2) (STV 0.01 1.0))))
!(compileadd summedDemandKb
   (: summed-single
      (Implication (SummedSinglePremise) (SummedSingleRoot))
      (CTV (STV 1.0 0.3) (STV 0.01 1.0))))

!(test
   (collapse
      (query-many 4 summedDemandKb
         ((: $prf (SummedSharedLeft) $tv)
          (: $prf (SummedSharedRight) $tv)
          (: $prf (SummedSingleRoot) $tv))))
   ((query-result 2
       (: (by summed-single summed-single-fact)
          (SummedSingleRoot) (STV 1.0 0.2999911278320848)))))

;; Two alternative rules from one root are not two independent consumers.
;; Their confidence-based requests merge by maximum, so the stronger single request wins.
!(compileadd duplicateDemandKb
   (: duplicate-shared-fact
      (DuplicateSharedPremise) (STV 1.0 1.0)))
!(compileadd duplicateDemandKb
   (: duplicate-single-fact
      (DuplicateSinglePremise) (STV 1.0 1.0)))
!(compileadd duplicateDemandKb
   (: duplicate-shared-first
      (Implication (DuplicateSharedPremise) (DuplicateSharedRoot))
      (CTV (STV 1.0 0.2) (STV 0.02 1.0))))
!(compileadd duplicateDemandKb
   (: duplicate-shared-second
      (Implication (DuplicateSharedPremise) (DuplicateSharedRoot))
      (CTV (STV 1.0 0.2) (STV 0.02 1.0))))
!(compileadd duplicateDemandKb
   (: duplicate-single
      (Implication (DuplicateSinglePremise) (DuplicateSingleRoot))
      (CTV (STV 1.0 0.3) (STV 0.02 1.0))))

!(test
   (collapse
      (query-many 3 duplicateDemandKb
         ((: $prf (DuplicateSharedRoot) $tv)
          (: $prf (DuplicateSingleRoot) $tv))))
   ((query-result 1
       (: (by duplicate-single duplicate-single-fact)
          (DuplicateSingleRoot) (STV 1.0 0.2999913061574112)))))

;; Roots share one priority order and an answered root is not rescored by its
;; marginal value: with equal rule confidence this budget refines the first root
;; before it reaches the second.
!(compileadd refreshedDemandKb
   (: refresh-fast-fact (RefreshFastPremise) (STV 1.0 1.0)))
!(compileadd refreshedDemandKb
   (: refresh-slow-fact (RefreshSlowPremise) (STV 1.0 1.0)))
!(compileadd refreshedDemandKb
   (: refresh-medium-fact (RefreshMediumPremise) (STV 1.0 1.0)))
!(compileadd refreshedDemandKb
   (: refresh-fast
      (Implication (RefreshFastPremise) (RefreshFirstRoot))
      (CTV (STV 1.0 1.0) (STV 0.03 1.0))))
!(compileadd refreshedDemandKb
   (: refresh-slow
      (Implication (RefreshSlowPremise) (RefreshFirstRoot))
      (CTV (STV 1.0 1.0) (STV 0.03 1.0))))
!(compileadd refreshedDemandKb
   (: refresh-medium
      (Implication (RefreshMediumPremise) (RefreshSecondRoot))
      (CTV (STV 1.0 1.0) (STV 0.03 1.0))))

!(test
   (collapse
      (query-many 4 refreshedDemandKb
         ((: $prf (RefreshFirstRoot) $tv)
          (: $prf (RefreshSecondRoot) $tv))))
   ((query-result 0
       (: (merge/revision (by refresh-fast refresh-fast-fact) (by refresh-slow refresh-slow-fact))
          (RefreshFirstRoot) (STV 1.0 0.9999029644052249)))))

;; A zero-budget batch reads what earlier searches found: only the first root.
!(test
   (length
      (collapse
         (query-many 0 refreshedDemandKb
            ((: $prf (RefreshFirstRoot) $tv)
             (: $prf (RefreshSecondRoot) $tv)))))
   1)
!(test
   (length
      (collapse
         (match &sk_roots ($_hash $root) $root)))
   2)

;; Once every root has an answer, remaining budget continues ordinary marginal
;; refinement instead of treating the batch as complete.
!(test
   (collapse
      (query-many 20 refreshedDemandKb
         ((: $prf (RefreshFirstRoot) $tv)
          (: $prf (RefreshSecondRoot) $tv))))
   ((query-result 0 (: (merge/revision (by refresh-fast refresh-fast-fact) (by refresh-slow refresh-slow-fact)) (RefreshFirstRoot) (STV 1.0 0.9999029644052249))) (query-result 1 (: (by refresh-medium refresh-medium-fact) (RefreshSecondRoot) (STV 1.0 0.9998059476404358)))))

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
         (query-many-materialize 6 materializeBatchKb
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
