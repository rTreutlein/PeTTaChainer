!(import! &self ../../pettachainer/metta/petta_chainer)

(: delivery-fact (-[det]-> Atom Atom Atom (Statement KBContext Proof TV)))
(= (delivery-fact $statement $proof $tv)
   (assemble-stored-runtime-fact $statement (deliveryTest MAIN Nil) $proof $tv))

;; G -> H is legal, but H's G-dependent component cannot prove G. When an
;; independent H proof arrives, live delivery must agree with conditioned
;; replay: G can use that component while an unrelated observer can use both.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($g (ensure-goal-at-depth (delivery-fact (G) $gp $gtv) 0))
          ($h (ensure-goal-at-depth (delivery-fact (H) $hp $htv) 1))
          ($observer (ensure-goal-at-depth (delivery-fact (Observer) $op $otv) 0))
          ($_root (once (add-atom &root_goal (root-goal $g))))
          ($seed (store-proof-candidate $g
                   (leaf-result-candidate (delivery-fact (G) seed (STV 0.2 0.3))
                      ((rule-ev deliveryTest seed)))))
          ($dependent (store-proof-candidate $h
             (proof-candidate
                (rule (delivery-fact (H) (by g-to-h (proof-ref $seed)) (STV 0.2 0.3)))
                0.3 ((rule-ev deliveryTest seed)) ($seed))))
          ($bundle (and-bundle
             (delivery-fact (G) (by h-to-g $input) $tv)
             ((delivery-fact (H) $input $tv))))
          ($agenda (spawn-frontier-heap (empty_heap) $g $bundle 1.0 () () 0
                     (frontier-value-spec 1.0 1)))
          ($with-observer (spawn-frontier-heap $agenda $observer
             (and-bundle (delivery-fact (Observer) (by h-to-observer $other) $other-tv)
                ((delivery-fact (H) $other $other-tv)))
             1.0 () () 0 (frontier-value-spec 1.0 1)))
          ($before (collapse (match &proof
             (stored-proof-row $_pid $_owner $_output
                (rule ((G) $_kb (by h-to-g $_input) $_tv)) $_support $_children) true)))
          ($_published (commit-proof-candidate-heap $with-observer $h
             (leaf-result-candidate (delivery-fact (H) independent (STV 0.9 0.8))
                ((rule-ev deliveryTest independent)))))
          ($live-good
             (collapse (match &proof
                (stored-proof-row $pid $_owner
                   ((G) $_kb $_proof (STV 0.9 0.8))
                   (rule ((G) $_ctx (by h-to-g (proof-ref $source)) $_tv)) $_support $_children)
                (proof-depends-on-goal-seen? (stored-number $source) $g closed-goal ()))))
          ($replayed (frontier-selected-proof-ids $h
             (frontier-view-id $g $bundle () () 0)
             (frontier-waiter $g $bundle 1.0 () () 0 (frontier-value-spec 1.0 1))))
          ($replayed-tv (map-semidet
             (|-> ($pid) (let ($_type $_kb $_proof $tv) (proof-output-atom-by-id $pid) $tv))
             $replayed))
          ($merged (car-atom (goal-merged-proof-ids $h))))
      ($before $live-good $replayed-tv
         (proof-depends-on-goal-seen? $merged $g closed-goal ())
         (== (proof-children-by-id (car-atom (goal-merged-proof-ids $observer))) ($merged))))
   (() (false) ((STV 0.9 0.8)) true true))

;; A notification for one binding must not replay other outputs of an open
;; child goal. Stage the existing proofs before registering the live waiter.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($parent (ensure-goal-at-depth (delivery-fact (Observe $x) $p $tv) 0))
          ($child (ensure-goal-at-depth (delivery-fact (Item $y) $q $qtv) 1))
          ($_a (store-proof-candidate $child
             (leaf-result-candidate (delivery-fact (Item a) a (STV 0.4 0.3))
                ((rule-ev deliveryTest a)))))
          ($_b (store-proof-candidate $child
             (leaf-result-candidate (delivery-fact (Item b) b (STV 0.5 0.3))
                ((rule-ev deliveryTest b)))))
          ($_wait (register-goal-waiter! $child $parent
             (frontier-waiter $parent
                (and-bundle (delivery-fact (Observe $z) (by observe $input) $vt)
                   ((delivery-fact (Item $z) $input $vt)))
                1.0 () () 0 (frontier-value-spec 1.0 1))))
          ($_published (commit-proof-candidate-heap (empty_heap) $child
             (leaf-result-candidate (delivery-fact (Item b) b-new (STV 0.9 0.8))
                ((rule-ev deliveryTest b-new))))))
      (collapse (match &proof
         (stored-proof-row $_pid $_owner ((Observe $binding) $_kb $_proof $_tv)
            (rule $_term) $_support $_children) $binding)))
   (b))
