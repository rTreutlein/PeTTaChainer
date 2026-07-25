(: foreach-flat
   (-[det]-> (-[det]-> $item $effect)
       (List $item) (List $none)))
(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs)) (progn ($f $x) (foreach-flat $f $xs)))

;; Reject cyclic terms before they reach a PeTTa space.  This is shared by
;; forward materialization and the backward-search stores, so it belongs below
;; both chainers in the import graph.
(: chainer-add-atom
   (-> $space $expression (| Bool (List $no-result))))
(= (chainer-add-atom $space $expr)
   (if (== (collapse (callPredicate (Predicate (cyclic_term $expr)))) ())
      (add-atom $space $expr)
      (empty)))
