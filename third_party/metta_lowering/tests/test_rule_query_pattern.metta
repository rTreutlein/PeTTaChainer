!(import! &self ../../../pettachainer/metta/petta_chainer)

;; Ordinary variable-headed expressions must remain proper expressions.
!(test
   (rule-query-pattern (Measure $x $scale $value meter))
   (Measure $x $scale $value meter))

!(test
   (rule-query-pattern (MoreBy $scale $left $right $amount $unit))
   (MoreBy $scale $left $right $amount $unit))

;; Only the compiler's exact internal witness form becomes an open query term.
!(test
   (let $pattern
      (rule-query-pattern
         (And (A $x) (B (exists witness-rule 0 ($x)))))
      (if (= $pattern (And (A $same) (B $witness)))
         (and (== $same $x) (is-var $witness))
         false))
   true)

;; A literal `exists` predicate with another arity is ordinary source syntax.
!(test
   (rule-query-pattern (exists user-data two-fields))
   (exists user-data two-fields))

;; A witness shared by several conjuncts becomes one query variable, so the
;; scan keeps them joined; distinct witnesses stay distinct.
!(test
   (let $pattern
      (rule-query-pattern
         (And (A (exists r 0 ($y)) (exists r 1 ($y))) (B (exists r 1 ($y)) $y)))
      (if (= $pattern (And (A $first $second) (B $shared $y2)))
         (and (== $second $shared) (and (is-var $first) (not (== $first $second))))
         false))
   true)
