(: pick-value (-> Atom (| Number (List Atom))))
(= (pick-value $tag)
   (case $tag
      ((number 1)
       ($_other (a b)))))

!(test (pick-value number) 1)
!(test (pick-value other) (a b))
