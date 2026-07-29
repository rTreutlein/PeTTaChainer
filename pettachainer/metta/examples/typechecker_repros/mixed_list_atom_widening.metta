(: Item Type)
(: item (-[det]-> Number Item))

(: mixed-values (-[det]-> (List Atom)))
(= (mixed-values)
   (cons ()
      (cons (item 1) ())))

!(test (mixed-values) (() (item 1)))
