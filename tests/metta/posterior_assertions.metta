;; Polynomial moment arithmetic can reassociate the last floating bits. Keep numerical
;; references at 1e-12 while the caller matches the complete proof and statement.
(: posterior-tv-near? (-[det]-> Number Number TV Bool))
(= (posterior-tv-near? $expected-s $expected-c $tv)
   (case $tv (
      ((STV $s $c)
         (and (< (abs-math (- $s $expected-s)) 1e-12)
              (< (abs-math (- $c $expected-c)) 1e-12)))
      ($_other false))))
