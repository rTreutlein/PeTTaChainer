!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd constraintKb (: accepted (ConstraintA) (STV 1.0 0.8)))
!(test (query 5 constraintKb (: $proof (ConstraintA) $tv))
   (: accepted (ConstraintA) (STV 1.0 0.8)))

;; Each root must retain its own proof and TV conditions, in either order.
!(test
   (collapse (query-many 0 constraintKb
      ((: accepted (ConstraintA) $tv)
       (: rejected (ConstraintA) $tv))))
   ((query-result 0 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: rejected (ConstraintA) $tv)
       (: accepted (ConstraintA) $tv))))
   ((query-result 1 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: $proof (ConstraintA) (STV 1.0 0.8))
       (: $proof (ConstraintA) (STV 1.0 0.7)))))
   ((query-result 0 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: $proof (ConstraintA) (STV 1.0 0.7))
       (: $proof (ConstraintA) (STV 1.0 0.8)))))
   ((query-result 1 (: accepted (ConstraintA) (STV 1.0 0.8)))))

;; Variable relationships across statement and proof are constraints too.
!(compileadd constraintKb
   (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))
!(test (query 5 constraintKb (: $proof (ConstraintBinding $x) $tv))
   (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))
!(test
   (collapse (query-many 0 constraintKb
      ((: (origin $x) (ConstraintBinding $x) $tv)
       (: (origin $p) (ConstraintBinding $x) $tv))))
   ((query-result 1 (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))))

;; Shortening one constrained request cannot narrow another request. Alpha
;; equivalent full requests still share one goal and receive ordinary lowering.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($open (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (LateConstraint))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof $proof) (STV 1.0 0.8)) 4))
          ($specific (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (LateConstraint))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (STV 1.0 0.8)) 1))
          ((stored-goal-row $_id $before-depth ($_type $_ctx $before-proof $_tv)
             $_expanded $_state) (goal-by-id $open))
          ($same (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (LateConstraint))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof $renamed) (STV 1.0 0.8)) 2))
          ((stored-goal-row $_next-id $after-depth ($_next-type $_next-ctx $after-proof $_next-tv)
             $_next-expanded $_next-state) (goal-by-id $open)))
      ((== $open $specific) (== $open $same)
         $before-depth (is-var $before-proof) $after-depth (is-var $after-proof)))
   (false true 4 true 2 true))

;; A late TV constraint likewise receives a distinct request instead of
;; strengthening the first goal's still-open TV pattern.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($open (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (LateTVConstraint))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (the TV $tv)) 4))
          ($specific (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (LateTVConstraint))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (STV 1.0 0.7)) 1))
          ((stored-goal-row $_id $depth ($_type $_ctx $_proof $stored-tv)
             $_expanded $_state) (goal-by-id $open)))
      ((== $open $specific) $depth (is-var $stored-tv)))
   (false 4 true))

;; Same proposition, different proof requests: both parents must receive the
;; shared source publication. The second attempt to store the same A proof is
;; a duplicate, so waking only the producing goal variant would strand Right.
!(compileadd variantKb (: variant-source (VariantSource) (STV 1.0 1.0)))
!(compileadd variantKb
   (: (no_inverse variant-a-rule)
      (Implication (VariantSource) (VariantA))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd variantKb
   (: (no_inverse variant-left-rule)
      (Implication (VariantA) (VariantLeft))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd variantKb
   (: (no_inverse variant-right-rule)
      (Implication (VariantA) (VariantRight))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test
   (collapse
      (let (query-result $index (: $proof $type $_tv))
         (query-many 20 variantKb
            ((: (by (no_inverse variant-left-rule)
                   (by (no_inverse variant-a-rule) $source))
                (VariantLeft) $tv)
             (: $proof (VariantRight) $tv)))
         ($index $proof $type)))
   ((0 (by (no_inverse variant-left-rule)
          (by (no_inverse variant-a-rule) variant-source)) (VariantLeft))
    (1 (by (no_inverse variant-right-rule)
          (by (no_inverse variant-a-rule) variant-source)) (VariantRight))))

;; A new candidate changes the shared durable proof set. Clear warmed
;; confidence caches for every constrained view, not only the producer.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($open (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (ConstraintA))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof $proof) (the TV $tv)) 0))
          ($specific (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (ConstraintA))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (the TV $other-tv)) 0))
          ($_warm-open (goal-current-confidence $open))
          ($_warm-specific (goal-current-confidence $specific))
          ($before (length (collapse (get-atoms &goal_current_confidence))))
          ($_new (once (store-proof-candidate $open
             (proof-candidate
                (leaf (assemble-runtime-fact (brand Statement (ConstraintA))
                   (brand KBContext (constraintKb MAIN Nil))
                   (brand Proof alternative) (STV 0.5 0.7)))
                0.7 () ()))))
          ($after (length (collapse (get-atoms &goal_current_confidence)))))
      ($before $after))
   (2 0))

;; A score collapse cancels satisfied work only when the current proof also
;; satisfies this view's proof/TV constraints. An incompatible sibling view's
;; proof must leave this request searchable.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($parent-goal (assemble-runtime-fact (brand Statement (CancelConstraintParent))
             (brand KBContext (constraintKb MAIN Nil))
             (brand Proof $parent-proof) (the TV $parent-tv)))
          ($parent (ensure-goal-at-depth $parent-goal 0))
          ($incompatible (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (CancelIncompatible))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (the TV $incompatible-tv)) 1))
          ($compatible (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (CancelCompatible))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof accepted) (the TV $compatible-tv)) 1))
          ($producer (ensure-goal-at-depth
             (assemble-runtime-fact (brand Statement (CancelIncompatible))
                (brand KBContext (constraintKb MAIN Nil))
                (brand Proof $producer-proof) (the TV $producer-tv)) 1))
          ($_root (once (add-atom &root_goal (root-goal $parent))))
          ($_wait-a (register-goal-waiter! $incompatible $parent
             (frontier-waiter $parent (and-bundle $parent-goal ())
                1.0 () () 0 (frontier-value-spec 1.0 1))))
          ($_wait-b (register-goal-waiter! $compatible $parent
             (frontier-waiter $parent (and-bundle $parent-goal ())
                1.0 () () 0 (frontier-value-spec 1.0 1))))
          ($agenda-a (wake-goal-demand-heap (empty_heap) $incompatible))
          (($_priority-a $entry-a $_rest-a) (heap_pop $agenda-a))
          ($agenda-b (wake-goal-demand-heap (empty_heap) $compatible))
          (($_priority-b $entry-b $_rest-b) (heap_pop $agenda-b))
          ($_proof-a (once (store-proof-candidate $producer
             (proof-candidate
                (leaf (assemble-runtime-fact (brand Statement (CancelIncompatible))
                   (brand KBContext (constraintKb MAIN Nil))
                   (brand Proof rejected) (STV 1.0 0.8))) 0.8 () ()))))
          ($_proof-b (once (store-proof-candidate $compatible
             (proof-candidate
                (leaf (assemble-runtime-fact (brand Statement (CancelCompatible))
                   (brand KBContext (constraintKb MAIN Nil))
                   (brand Proof accepted) (STV 1.0 0.8))) 0.8 () ()))))
          ($_parent-proof (once (store-proof-candidate $parent
             (proof-candidate
                (leaf (assemble-runtime-fact (brand Statement (CancelConstraintParent))
                   (brand KBContext (constraintKb MAIN Nil))
                   (brand Proof confidence-raised) (STV 1.0 0.8))) 0.8 () ()))))
          ($_revision (bump-goal-demand-revision! $parent)))
      ((claim-goal-agenda-entry! $entry-a)
       (claim-goal-agenda-entry! $entry-b)))
   (agenda-retoken agenda-cancelled))

;; An open proof constructor is a query pattern, not a compiler marker. Testing
;; for a marker must not bind that head, including its shared statement use.
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement
                   (Implication (MarkerInput $head) (MarkerOutput $head)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote ($head $payload)))
                (the TV $tv))))
          ($after (nextctx)))
      ((is-var $head) (is-var $payload) (- $after $before)))
   (true true 3))

;; The exact marker skips its already-installed scaffold without inspecting
;; or instantiating its payload, even when nested variables are shared.
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement
                   (Implication (MarkerInput $shared) (MarkerOutput $shared)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof
                   (total-implication-frontier (quote ($shared $shared))))
                (the TV $tv))))
          ($after (nextctx)))
      ((is-var $shared) (- $after $before)))
   (true 1))

;; Empty and atomic proofs, or an incorrect marker arity, remain ordinary
;; constraints. Each compiles its scaffold; none may call car-atom on ().
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote ())) (the TV $tv))))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote total-implication-frontier)) (the TV $tv))))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote (total-implication-frontier))) (the TV $tv))))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (assemble-runtime-fact
                (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote (total-implication-frontier one two))) (the TV $tv))))
          ($after (nextctx)))
      (- $after $before))
   3)
