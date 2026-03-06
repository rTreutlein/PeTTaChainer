!(import! &self compile)
!(import! &self mining)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))

!(import! &self chainer_utils)
!(import! &self forward_chainer)

!(bind! &goal_by_id (new-space))

!(bind! &goal_lookup (new-space))

!(bind! &goal_expanded (new-space))

!(bind! &goal_pending_score (new-space))

!(bind! &goal_waiter (new-space))

!(bind! &and_node (new-space))

!(bind! &frontier (new-space))

!(bind! &goal_proof (new-space))

!(bind! &proof_goal (new-space))

!(bind! &proof_score (new-space))

!(bind! &proof_evidence (new-space))

!(bind! &proof_kind (new-space))

!(bind! &proof_tv (new-space))

!(bind! &proof_children (new-space))

!(bind! &proof_status (new-space))

!(bind! &particle_store (new-space))

!(bind! &bench_meta (new-space))

!(bind! &rule_proof_ids (new-space))

!(import! &self dist_formulas)
!(import! &self tv_formulas)
!(import! &self backward_chainer)

(= (nextid)
   (let*
      (($mn (catch (get-state ruleid)))
        ($n (if-error $mn 0 $mn)))
      (progn (change-state! ruleid (+ $n 1)) $n)))

(= (add-prem $vars $id $idx $prem) (progn (add-atom &prem_index ($prem $id $idx)) (+ $idx 1)))

(= (add-to-kb $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($vars (extract-vars $expr))
           ($id (nextid))
           ($_1 (fold-flat (add-prem $vars $id) 0 $args))
           ($_2 (add-atom &ccls_index ($ccls $id)))
           ($_3 (add-atom &rules ($id $ccls $args)))
           ($_4 (forward-register-added-rule $args $ccls)))
         ())
      (progn (add-atom &kb $expr) (forward-register-added-expr $expr))))

(= (compileadd-add-all $acc $atom) (progn (add-to-kb $atom) $acc))

(= (register-source-proof-id (: $prf $type $_tv))
   (if (= $type (Implication (cons Premises $_premises) (cons Conclusions $_conclusions)))
      (add-atom &rule_proof_ids ($prf true))
      ()))

(= (compileadd $kb $stmt)
   (let*
      (($atoms (collapse (mm2compile $kb $stmt)))
        ($iatoms (map-flat internalize-proof-structure $atoms))
        ($eatoms (map-flat externalize-proof-structure $iatoms))
        ($_ (fold-flat compileadd-add-all () $iatoms))
        ($_ (register-source-proof-id $stmt))
        ($_ (process-on-add $kb $stmt)))
      (superpose
         $eatoms)))

(= (query $steps $kb $stmt)
   (let*
      (($compiled (map-flat internalize-proof-structure (collapse (mm2compileQuery $kb $stmt))))
        ((cons (goal $query) $adds) $compiled)
        ($_ (inject-compiled-adds $adds))
        ($res (reduce (chainer $steps $query)))
        ($eres (map-flat externalize-proof-structure $res)))
      (pretty (superpose $eres))))
