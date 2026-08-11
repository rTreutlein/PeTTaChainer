(: add-one-fact (-[det]-> Bool))
(= (add-one-fact)
   (add-atom &self (fact 1)))

!(test (add-one-fact) true)
