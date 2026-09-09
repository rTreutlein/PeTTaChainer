!(import! &self ../../pettachainer/metta/petta_chainer)
(: path-fact (-[det]-> Atom Atom Atom (Statement KBContext Proof TV)))
(= (path-fact $statement $proof $tv)
   (assemble-stored-runtime-fact $statement (deliveryPath MAIN Nil) $proof $tv))

;; A remains a valid independent proof when the global A representative gains
;; a G-dependent component. G must still be able to finish A,H when H arrives.
!(test
   (let* (($_clear (clear-backward-query-state!))
          ($g (ensure-goal-at-depth (path-fact (G) $gp $gtv) 0))
          ($a (ensure-goal-at-depth (path-fact (A) $ap $atv) 1))
          ($h (ensure-goal-at-depth (path-fact (H) $hp $htv) 1))
          ($_root (once (add-atom &root_goal (root-goal $g))))
          ($seed (store-proof-candidate $g
             (leaf-result-candidate (path-fact (G) seed (STV 0.2 0.3))
                ((rule-ev deliveryPath seed)))))
          ($independent (store-proof-candidate $a
             (leaf-result-candidate (path-fact (A) a (STV 0.9 0.8))
                ((rule-ev deliveryPath a)))))
          ($agenda (spawn-frontier-heap (empty_heap) $g
             (and-bundle (path-fact (G) (by gated $pa $ph) $th)
                ((path-fact (A) $pa $ta) (path-fact (H) $ph $th)))
             1.0 () () 0 (frontier-value-spec 1.0 2)))
          ($updated (commit-proof-candidate-heap $agenda $a
             (proof-candidate
                (rule (path-fact (A) (by g-to-a (proof-ref $seed)) (STV 0.2 0.3)))
                0.3 ((rule-ev deliveryPath seed)) ($seed))))
          ($_published (commit-proof-candidate-heap $updated $h
             (leaf-result-candidate (path-fact (H) h (STV 0.8 0.7))
                ((rule-ev deliveryPath h)))))
          ($current (goal-live-proof-ids $a)))
      ((stored-list-member? $independent $current)
       (collapse (match &frontier_path_lookup ($_view 0 $independent $path)
          (frontier-path-live? (stored-number $path))))
       (collapse (match &proof
          (stored-proof-row $_pid $_owner $_output
             (rule ((G) $_kb (by gated $_pa $_ph) $_tv)) $_support $_children) true))))
   (true (true) (true)))
