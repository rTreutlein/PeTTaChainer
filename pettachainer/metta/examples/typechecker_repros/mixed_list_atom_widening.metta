(: Item Type)
(: item (-> Number Item))

(: mixed-values (-> (List Atom)))
(= (mixed-values)
   (cons ()
      (cons (item 1) ())))

!(test (mixed-values) (() (item 1)))
