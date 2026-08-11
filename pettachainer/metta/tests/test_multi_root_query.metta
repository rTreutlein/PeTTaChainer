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
            (match &goal
               (stored-goal-row $_gid $_depth
                  ((SharedBatchPremise) (sharedBatchKb MAIN Nil) $_prf $_tv)
                  $_expanded $_pending)
               shared-goal))))
   1)

;; A moderately useful proof shared by two roots outranks a more useful proof
;; consumed by only one root. Waiters merge by maximum within one root and add
;; across distinct roots, so 0.2 + 0.2 beats 0.3.
!(compileadd summedDemandKb
   (: summed-shared-fact (SummedSharedPremise) (STV 1.0 1.0)))
!(compileadd summedDemandKb
   (: summed-single-fact (SummedSinglePremise) (STV 1.0 1.0)))
!(compileadd summedDemandKb
   (: summed-shared-left
      (Implication (SummedSharedPremise) (SummedSharedLeft))
      (CTV (STV 1.0 1.0) (STV 0.01 1.0))))
!(compileadd summedDemandKb
   (: summed-shared-right
      (Implication (SummedSharedPremise) (SummedSharedRight))
      (CTV (STV 1.0 1.0) (STV 0.01 1.0))))
!(compileadd summedDemandKb
   (: summed-single
      (Implication (SummedSinglePremise) (SummedSingleRoot))
      (CTV (STV 1.0 1.0) (STV 0.01 1.0))))
!(set-base-rate summedDemandKb
   (SummedSharedPremise) (STV 0.2 1.0))
!(set-base-rate summedDemandKb
   (SummedSinglePremise) (STV 0.3 1.0))

!(test
   (collapse
      (query-many 4 summedDemandKb
         ((: $prf (SummedSharedLeft) $tv)
          (: $prf (SummedSharedRight) $tv)
          (: $prf (SummedSingleRoot) $tv))))
   ((query-result 0
       (: (by summed-shared-left summed-shared-fact)
          (SummedSharedLeft) (STV 1.0 0.9998020291758253)))
    (query-result 1
       (: (by summed-shared-right summed-shared-fact)
          (SummedSharedRight) (STV 1.0 0.9998020291758253)))))

;; Two alternative rules from one root are not two independent consumers.
;; Their 0.2 requests merge by maximum, so another root's 0.3 request wins.
!(compileadd duplicateDemandKb
   (: duplicate-shared-fact
      (DuplicateSharedPremise) (STV 1.0 1.0)))
!(compileadd duplicateDemandKb
   (: duplicate-single-fact
      (DuplicateSinglePremise) (STV 1.0 1.0)))
!(compileadd duplicateDemandKb
   (: duplicate-shared-first
      (Implication (DuplicateSharedPremise) (DuplicateSharedRoot))
      (CTV (STV 1.0 1.0) (STV 0.02 1.0))))
!(compileadd duplicateDemandKb
   (: duplicate-shared-second
      (Implication (DuplicateSharedPremise) (DuplicateSharedRoot))
      (CTV (STV 1.0 1.0) (STV 0.02 1.0))))
!(compileadd duplicateDemandKb
   (: duplicate-single
      (Implication (DuplicateSinglePremise) (DuplicateSingleRoot))
      (CTV (STV 1.0 1.0) (STV 0.02 1.0))))
!(set-base-rate duplicateDemandKb
   (DuplicateSharedPremise) (STV 0.2 1.0))
!(set-base-rate duplicateDemandKb
   (DuplicateSinglePremise) (STV 0.3 1.0))

!(test
   (collapse
      (query-many 3 duplicateDemandKb
         ((: $prf (DuplicateSharedRoot) $tv)
          (: $prf (DuplicateSingleRoot) $tv))))
   ((query-result 1
       (: (by duplicate-single duplicate-single-fact)
          (DuplicateSingleRoot) (STV 1.0 0.9998039984003787)))))

;; Once the fast proof establishes the first root, its current-batch demand is
;; removed from still-queued alternatives. Stale 0.35 work for that solved root
;; must not outrank the second root's still-current 0.3 demand.
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
!(set-base-rate refreshedDemandKb
   (RefreshFastPremise) (STV 0.4 1.0))
!(set-base-rate refreshedDemandKb
   (RefreshSlowPremise) (STV 0.35 1.0))
!(set-base-rate refreshedDemandKb
   (RefreshMediumPremise) (STV 0.3 1.0))

!(test
   (collapse
      (query-many 4 refreshedDemandKb
         ((: $prf (RefreshFirstRoot) $tv)
          (: $prf (RefreshSecondRoot) $tv))))
   ((query-result 0
       (: (by refresh-fast refresh-fast-fact)
          (RefreshFirstRoot) (STV 1.0 0.9998059476404358)))
    (query-result 1
       (: (by refresh-medium refresh-medium-fact)
          (RefreshSecondRoot) (STV 1.0 0.9998059476404358)))))

;; Roots that began without an incumbent yield after their first proof. A new
;; query marks the same durable results as historical incumbents, so they remain
;; eligible for bounded refinement rather than being mistaken for solved work
;; from the new batch.
!(test
   (length
      (collapse
         (match &root_goal
            (root-goal $gid false)
            (match &root_goal_completed ($gid) $gid))))
   2)
!(test
   (length
      (collapse
         (query-many 0 refreshedDemandKb
            ((: $prf (RefreshFirstRoot) $tv)
             (: $prf (RefreshSecondRoot) $tv)))))
   2)
!(test
   (length
      (collapse
         (match &root_goal (root-goal $gid true) $gid)))
   2)
!(test
   (collapse (match &root_goal_completed ($gid) $gid))
   ())

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
