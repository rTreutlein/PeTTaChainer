!(import! &self compile)
!(import! &self mining)

!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))
!(import! &self chainer_utils)
!(import! &self forward_chainer)
!(import! &self dist_formulas)
!(import! &self tv_formulas)
!(import! &self compiled_query_runtime)
!(import! &self backward_chainer)

(= (nextid)
   (let*
      (($mn (catch (get-state ruleid)))
        ($n (if-error $mn 0 $mn)))
      (progn (change-state! ruleid (+ $n 1)) $n)))

(= (add-prem $vars $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn (if (== $key ()) () (add-atom prem_index ($key $prem $id $idx)))
         (+ $idx 1))))

(= (add-to-kb $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($vars (extract-vars $expr))
           ($id (nextid))
           ($_1 (fold-flat (add-prem $vars $id) 0 $args))
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
            (cons (materialize-stmt-lambdas (car-atom $term))
               (materialize-stmt-lambdas-list (cdr-atom $term))))
         $term)))

(= (materialize-stmt-lambdas-list ()) ())
(= (materialize-stmt-lambdas-list (cons $head $tail))
   (cons (materialize-stmt-lambdas $head) (materialize-stmt-lambdas-list $tail)))

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
