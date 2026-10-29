!(import! &self (library lib_roman))
!(import! &self (library lib_spaces))
!(import! &self ../../pettachainer/metta/lib/collections)

!(test (reverse-onto (the (List Number) (1 2 3)) (4 5)) (3 2 1 4 5))
!(test (reverse-onto (the (List Number) ()) (4 5)) (4 5))

;; Do not run a later predicate once one element satisfies it.
(: collection-probe (-[det]-> Number Bool))
(= (collection-probe $n)
   (let $_seen (change-state! collection_seen $n) (> $n 0)))
!(test (any-flat? collection-probe (the (List Number) ())) false)
!(test (collapse (any-flat? collection-probe (the (List Number) (0 1 2)))) (true))
!(test (get-state collection_seen) 1)
!(test (any-flat? collection-probe (the (List Number) (0 0))) false)

!(test (append-flat (the (List Number) (1 2)) (3)) (1 2 3))
!(test (map-semidet (+ 1) (the (List Number) (1 2))) (2 3))
!(test (fold-semidet + 0 (the (List Number) (1 2 3))) 6)
!(test
   (let $found (stored-list-member? $a (the (List Atom) ($b)))
      ($found (is-var $a) (is-var $b)))
   (false true true))
!(bind! &collection_rows (new-space))
!(add-atom &collection_rows (7 present))
!(test (space-row-present? &collection_rows (quote ($key present))) true)
!(test (space-row-present? &collection_rows (quote ($key missing))) false)
!(test (foreach-flat collection-probe (the (List Number) (1 2 3))) ())
!(test (get-state collection_seen) 3)
