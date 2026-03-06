!(import! &self compile)
!(import! &self mining)

!(use-module! heaps)

!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))

!(import! &self chainer_utils)
!(import! &self forward_chainer)

!(bind! &goal_store (new-space))

!(bind! &proof_store (new-space))

!(bind! &particle_store (new-space))

!(bind! &bench_meta (new-space))

!(import! &self backward_chainer)
!(import! &self dist_formulas)
!(import! &self tv_formulas)

(= (nextid)
   (let $mn (catch (get-state ruleid))
      (let $n (if-error $mn 0 $mn) (progn (change-state! ruleid (+ $n 1)) $n))))

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

(= (compileadd $kb $stmt)
   (let*
      (($atoms (collapse (mm2compile $kb $stmt)))
        ($_ (fold-flat compileadd-add-all () $atoms))
        ($_ (process-on-add $kb $stmt)))
      (superpose
         $atoms)))

(= (query $steps $kb $stmt)
   (let*
      (((cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt)))
        ($_ (inject-compiled-adds $adds))
        ($res (reduce (chainer $steps $query))))
      (pretty (superpose $res))))
