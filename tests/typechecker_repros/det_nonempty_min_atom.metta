(: min-known-pair (-[det]-> Number Number Number))
(= (min-known-pair $a $b)
   (min-atom ($a $b)))

!(test (min-known-pair 3 2) 2)
