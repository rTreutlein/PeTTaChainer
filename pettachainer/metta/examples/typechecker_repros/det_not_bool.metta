(: invert (-[det]-> Bool Bool))
(= (invert $value)
   (not $value))

!(test (invert false) true)
