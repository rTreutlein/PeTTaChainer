(: maybe-number (-[semidet]-> Number Number))
(= (maybe-number $x)
   (if (> $x 0) $x (empty)))

(: add-pair (-[det]-> Number Number (Number Number)))
(= (add-pair $a $b) ($a $b))

(: through-nested-calls (-[semidet]-> Number (Number Number)))
(= (through-nested-calls $x)
   (let ($left $right)
      (add-pair (maybe-number $x) (maybe-number $x))
      ($left $right)))

!(test (through-nested-calls 1) (1 1))
