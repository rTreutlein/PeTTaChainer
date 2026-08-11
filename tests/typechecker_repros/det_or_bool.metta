(: either-true (-[det]-> Bool Bool Bool))
(= (either-true $left $right)
   (or $left $right))

!(test (either-true false true) true)
