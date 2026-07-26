(: known-name? (-[det]-> Atom Bool))
(= (known-name? $value)
   (is-member $value (alpha beta)))

!(test (known-name? alpha) true)
!(test (known-name? other) false)
