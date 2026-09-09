!(import! &self ../../pettachainer/metta/petta_chainer)
(: view-fact (-[det]-> Atom Atom Atom (Statement KBContext Proof TV)))
(= (view-fact $statement $proof $tv)
   (assemble-stored-runtime-fact $statement (consumerViews MAIN Nil) $proof $tv))

;; A's refined derivation gains a G-dependent input. It replaces A's global
;; estimate and Observer's selection, while G retains the independent version
;; of that same derivation. The two consumers must not share path invalidation.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($g (ensure-goal-at-depth (view-fact (G) $gp $gtv) 0))
          ($o (ensure-goal-at-depth (view-fact (Observer) $op $otv) 0))
          ($a (ensure-goal-at-depth (view-fact (A) $ap $atv) 1))
          ($b (ensure-goal-at-depth (view-fact (B) $bp $btv) 2))
          ($h (ensure-goal-at-depth (view-fact (H) $hp $htv) 1))
          ($seed (store-proof-candidate $g
             (leaf-result-candidate (view-fact (G) seed (STV 0.2 0.3))
                ((rule-ev consumerViews seed)))))
          ($base (store-proof-candidate $b
             (leaf-result-candidate (view-fact (B) base (STV 0.8 0.7))
                ((rule-ev consumerViews base)))))
          ($old (store-proof-candidate $a
             (proof-candidate
                (rule (view-fact (A) (by r (proof-ref $base)) (STV 0.8 0.7)))
                0.7 ((rule-ev consumerViews base)) ($base))))
          ($agenda (spawn-frontier-heap (empty_heap) $g
             (and-bundle (view-fact (G) (by gated $pa $ph) $ta)
                ((view-fact (A) $pa $ta) (view-fact (H) $ph $th)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
          ($agenda (spawn-frontier-heap $agenda $o
             (and-bundle (view-fact (Observer) (by observe $oa $oh) $tv)
                ((view-fact (A) $oa $tv) (view-fact (H) $oh $oth)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
          ($old-paths (collapse (match &frontier_path_lookup
             ($view 0 $old $path) (stored-number $path))))
          ($dependent (store-proof-candidate $b
             (proof-candidate
                (rule (view-fact (B) (by from-g (proof-ref $seed)) (STV 0.9 0.8)))
                0.8 ((rule-ev consumerViews seed)) ($seed))))
          ($merged (car-atom (goal-merged-proof-ids $b)))
          ($agenda (commit-proof-candidate-heap $agenda $a
             (proof-candidate
                (rule (view-fact (A) (by r (proof-ref $merged)) (STV 0.9 0.8)))
                0.8 ((rule-ev consumerViews base) (rule-ev consumerViews seed)) ($merged))))
          ($_finish (commit-proof-candidate-heap $agenda $h
             (leaf-result-candidate (view-fact (H) h (STV 1.0 1.0))
                ((rule-ev consumerViews h)))))
          ($current (goal-live-proof-ids $a)))
      ((stored-list-member? $old $current)
       (space-row-present? &proof_alternative ($_hash $_key $old))
       (map-semidet frontier-path-live? $old-paths)
       (collapse (match &proof
          (stored-proof-row $_pid $_owner ((G) $_kb $_proof $value)
             (rule ((G) $_context (by gated $_a $_h) $_tv)) $_support $_children) $value))
       (collapse (match &proof
          (stored-proof-row $_pid $_owner ((Observer) $_kb $_proof $value)
             (rule ((Observer) $_context (by observe $_a $_h) $_tv)) $_support $_children) $value))))
   (false true (true false) ((STV 0.8 0.7)) ((STV 0.9 0.8))))

;; A consumer that has already used shared evidence must select A's independent
;; component. The general estimate remains a merge of both components.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($g (ensure-goal-at-depth (view-fact (EvidenceG) $gp $gtv) 0))
          ($p (ensure-goal-at-depth (view-fact (EvidenceP) $pp $ptv) 1))
          ($a (ensure-goal-at-depth (view-fact (EvidenceA) $ap $atv) 1))
          ($_p (store-proof-candidate $p
             (leaf-result-candidate (view-fact (EvidenceP) p (STV 0.8 0.7))
                ((rule-ev consumerViews shared)))))
          ($_shared (store-proof-candidate $a
             (leaf-result-candidate (view-fact (EvidenceA) shared (STV 0.9 0.8))
                ((rule-ev consumerViews shared)))))
          ($_independent (store-proof-candidate $a
             (leaf-result-candidate (view-fact (EvidenceA) independent (STV 0.2 0.6))
                ((rule-ev consumerViews independent)))))
          ($_finish (spawn-frontier-heap (empty_heap) $g
             (and-bundle (view-fact (EvidenceG) (by evidence-gated $pproof $aproof) $at)
                ((view-fact (EvidenceP) $pproof $pt) (view-fact (EvidenceA) $aproof $at)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
          ($merged (car-atom (goal-merged-proof-ids $a))))
      ((collapse (match &proof
          (stored-proof-row $_pid $_owner ((EvidenceG) $_kb $_proof $value)
             (rule $_term) $_support $_children) $value))
       (length (proof-children-by-id $merged))))
   (((STV 0.2 0.6)) 2))

;; Hash normalization must not bind, or run the constraints of, copied typed
;; variables. The live variable remains constrained and unbound after hashing.
!(test
   (let* (($tv (the TV $value))
          ($_hash (index-hash (quote ($tv)))))
      (is-var $tv))
   true)
