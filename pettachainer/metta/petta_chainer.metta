!(import! &self compile)
!(import! &self mining)

!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(import! &self chainer_utils)
!(import! &self forward_chainer)
!(import! &self dist_formulas)
!(import! &self tv_formulas)
!(import! &self compiled_query_runtime)
!(import! &self backward_proof_store)
!(import! &self backward_chainer)

(= (add-prem $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn (if (== $key ()) () (add-atom prem_index ($key $prem $id $idx)))
         (+ $idx 1))))

(= (add-to-kb $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($id (next-search-id ruleid))
           ($_1 (fold-flat (add-prem $id) 0 $args))
           ($_2 (add-atom ccls_index ($ccls $id)))
           ($_3 (add-atom rules ($id $ccls $args)))
           ($_4 (forward-register-added-rule $args $ccls)))
         ())
      (progn (add-atom &kb $expr) (forward-register-added-expr $expr))))

(= (materialize-stmt-lambdas $term)
   (if (is-var $term) $term
      (if (is-expr $term)
         (if (== (car-atom $term) |->)
            (eval $term)
            (cons (materialize-stmt-lambdas (car-atom $term)) (map-flat materialize-stmt-lambdas (cdr-atom $term))))
         $term)))

(= (compileadd $kb $stmt)
   (let*
      (($stmt1 (materialize-stmt-lambdas $stmt))
        ($atoms (collapse (mm2compile $kb $stmt1)))
        ($iatoms (map-flat internalize-proof-structure $atoms))
        ($eatoms (map-flat externalize-proof-structure $iatoms))
        ($_ (foreach-flat add-to-kb $iatoms))
        ($_ (process-on-add $kb $stmt1)))
      (superpose
         $eatoms)))
