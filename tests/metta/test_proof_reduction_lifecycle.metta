!(import! &self ../../pettachainer/metta/petta_chainer)

(: reduction-test-fact (-[det]-> Proof TV (Statement KBContext Proof TV)))
(= (reduction-test-fact $proof $tv)
   (assemble-runtime-fact (Observation) (brand KBContext (reductionTest MAIN Nil)) $proof $tv))

;; Revision retains independently selected input paths. A fold snapshot
;; replacement invalidates paths consuming that snapshot. Replaying either
;; accepted candidate must neither publish again nor advance the revision.
!(test
   (let* (($_clear (clear-backward-state))
          ($source (ensure-goal-at-depth (reduction-test-fact (brand Proof $proof) (the TV $tv)) 1))
          ($fold (ensure-goal-at-depth (CPU FoldAllCompiled reduction-test $result) 0))
          ($first (leaf-result-candidate (reduction-test-fact first (STV 0.2 0.5))
             ((fact-ev (reductionTest MAIN Nil) first (Observation)))))
          ($second (leaf-result-candidate (reduction-test-fact second (STV 0.8 0.5))
             ((fact-ev (reductionTest MAIN Nil) second (Observation)))))
          ($agenda (commit-proof-candidate-heap (empty_heap) $source $first))
          ((cons $old-source ()) (goal-merged-proof-ids $source))
          ($agenda (commit-proof-candidate-heap $agenda $fold
             (aggregate-result-candidate (CPU FoldAllCompiled reduction-test 1) () ($old-source))))
          ((cons $old-fold ()) (goal-merged-proof-ids $fold))
          ($source-path (ensure-frontier-path 0 0 $old-source))
          ($fold-path (ensure-frontier-path 0 0 $old-fold))
          ($agenda (commit-proof-candidate-heap $agenda $source $second))
          ((cons $new-source ()) (goal-merged-proof-ids $source))
          ($_cap (once (add-atom &search_wake_active ($fold 2))))
          ($before (goal-demand-revision $fold))
          ($snapshot (aggregate-result-candidate (CPU FoldAllCompiled reduction-test 2) () ($new-source)))
          ($agenda (commit-proof-candidate-heap $agenda $fold $snapshot))
          ((cons $new-fold ()) (goal-merged-proof-ids $fold))
          ($after (goal-demand-revision $fold))
          ($source-revision (goal-demand-revision $source))
          ($agenda (commit-proof-candidate-heap $agenda $source $second))
          ($agenda (commit-proof-candidate-heap $agenda $fold $snapshot))
          ($_uncap (remove-atom &search_wake_active ($fold 2))))
      ((== $after (+ $before 1))
       (== (goal-demand-revision $fold) $after)
       (== (goal-demand-revision $source) $source-revision)
       (== (goal-merged-proof-ids $fold) ($new-fold))
       (== (goal-merged-proof-ids $source) ($new-source))
       (proof-live? $old-source)
       (proof-live? $old-fold)
       (frontier-path-live? $source-path)
       (frontier-path-live? $fold-path)
       (length (goal-live-proof-ids $source))
       (length (goal-live-proof-ids $fold))
       (proof-output-atom-by-id $old-fold)
       (heap_size $agenda)))
   (true true true true true true false true false 2 1
      (CPU FoldAllCompiled reduction-test 1) 0))

;; A cached numerical result is a duplicate until materialization requires its
;; source provenance. Acquiring children replaces the seed exactly once, even
;; though its value and evidence do not change.
!(test
   (let* (($_clear (clear-backward-state))
          ($source (ensure-goal-at-depth (reduction-test-fact (brand Proof $proof) (the TV $tv)) 1))
          ($fold (ensure-goal-at-depth (CPU FoldAllCompiled provenance-test $result) 0))
          ($agenda (commit-proof-candidate-heap (empty_heap) $source
             (leaf-result-candidate (reduction-test-fact sample (STV 1.0 0.9))
                ((fact-ev (reductionTest MAIN Nil) sample (Observation))))))
          ((cons $child ()) (goal-merged-proof-ids $source))
          ($agenda (commit-proof-candidate-heap $agenda $fold
             (aggregate-result-candidate (CPU FoldAllCompiled provenance-test 1) () ())))
          ((cons $seed ()) (goal-merged-proof-ids $fold))
          ($refold (aggregate-result-candidate (CPU FoldAllCompiled provenance-test 1) () ($child)))
          ($agenda (commit-proof-candidate-heap $agenda $fold $refold))
          ($unchanged (== (goal-merged-proof-ids $fold) ($seed)))
          ($hash (index-hash (proof-goal-key-by-goal-id $fold)))
          ($_materialized (once (add-atom &materialized_folds ($hash))))
          ($agenda (commit-proof-candidate-heap $agenda $fold $refold))
          ((cons $complete ()) (goal-merged-proof-ids $fold))
          ($revision (goal-demand-revision $fold))
          ($agenda (commit-proof-candidate-heap $agenda $fold $refold)))
      ($unchanged
       (not (== $seed $complete))
       (== (proof-children-by-id $complete) ($child))
       (proof-live? $seed)
       (== (goal-merged-proof-ids $fold) ($complete))
       (== (goal-demand-revision $fold) $revision)
       (heap_size $agenda)))
   (true true true false true true 0))
