(: both-true (-[det]-> Bool Bool Bool))
(= (both-true $left $right)
   (and $left $right))

!(test (both-true true true) true)
