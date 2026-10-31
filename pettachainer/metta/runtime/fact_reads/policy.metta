;; Input selection, proof/TV filtering and MAIN borrowing live in
;; runtime/fact_reads/selection. Construction consumes those indexed facts.

(: sk-fact-key (-[det]-> SkFact SkeletonKey))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))

;; A ground statement stored with confidence 1 is certain: no other proof
;; could change its value. Borrowed world facts cannot retire private search:
;; the judgment may find an assumption-dependent alternative to select instead.
(: sk-certain-step (-[det]-> Bool SkFact Bool))
(= (sk-certain-step $seen ($_type ($_kb $ctx $_vars) $proof $tv))
   (if $seen true
      (if (if (== $ctx MAIN) true (assumption-proof? $proof))
         (case $tv (((STV $_s $c) (>= $c 1.0)) ($_other false))) false)))
(: sk-certain? (-[det]-> Statement (List SkFact) Bool))
(= (sk-certain? $type $facts)
   (if (== (extract-vars $type) ()) (fold-flat sk-certain-step false $facts) false))

;; A stored fact of strength 0 or 1 at confidence 1 makes its statement known:
;; every reader, a conditioned one included, reads it as that fact.
(: sk-known-leaf-step (-[det]-> Bool SkFact Bool))
(= (sk-known-leaf-step $known ($_type ($_kb $ctx $_vars) $proof $tv))
   (if $known true
      (if (if (== $ctx MAIN) true (assumption-proof? $proof)) (certain-tvs? (cons $tv ())) false)))


;; --- Complete predicates (docs/metta/complete_predicates.md) ----------------

;; Whether a statement, or a part of a compound one, has a complete predicate.
(: complete-part? (-[det]-> KB Bool Atom Bool))
(= (complete-part? $kb $found $part)
   (if $found true
      (let ($key $_odd) (canon (brand Statement $part))
         (if (compound-source? $key)
            (let $parts (the (List Atom) (cdr-atom $key)) (fold-flat (complete-part? $kb) false $parts))
            (let $head (if (is-expr $key) (car-atom $key) $key) (complete-predicate? $kb $head))))))

;; A ground statement of a complete predicate in the main context or in an
;; Assuming query's context, which holds the world's facts and rules with its
;; assumptions; an implication query's hypothetical contexts are not complete.
;; A connective with a complete part is complete too: its producers derive it
;; from its parts, so a closed read of it reads them as a rule reading the
;; parts would (#142).
(: complete-statement? (-[det]-> Atom Atom Bool))
(= (complete-statement? $type ($kbid $ctx $_vars))
   (if (== $ctx MAIN)
      (if (== (extract-vars $type) ()) (complete-part? (brand KB $kbid) false $type) false)
      false))
