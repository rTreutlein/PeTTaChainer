!(import! &self ../petta_chainer)

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
