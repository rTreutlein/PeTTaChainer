;; Shared proper-list and space operations. Loaded before compiler specialization.
(: fold-semidet (-[semidet]-> (-[semidet]-> $acc $item $acc) $acc (List $item) $acc))
(= (fold-semidet $_fun $acc ()) $acc)
(= (fold-semidet $fun $acc (cons $item $rest)) (fold-semidet $fun ($fun $acc $item) $rest))
(: map-semidet (-[semidet]-> (-[semidet]-> $input $output) (List $input) (List $output)))
(= (map-semidet $_fun ()) ())
(= (map-semidet $fun (cons $item $rest)) (cons ($fun $item) (map-semidet $fun $rest)))
(: append-flat (-[det]-> (List $a) (List $a) (List $a)))
(= (append-flat () $right) $right)
(= (append-flat (cons $head $tail) $right) (cons $head (append-flat $tail $right)))

(: space-row-present? (-[det]-> $space $row Bool))
(= (space-row-present? $space $row) (not (== (collapse (once (match $space $row true))) ())))
(: foreach-flat (-[$e]-> (-[$e]-> $item $effect) (List $item) (List $none)))
(= (foreach-flat $f ()) ())
(= (foreach-flat $f (cons $x $xs)) (progn ($f $x) (foreach-flat $f $xs)))
(: stored-list-member? (-[det]-> $item (List $item) Bool))
(= (stored-list-member? $_needle ()) false)
(= (stored-list-member? $needle (cons $first $rest))
   (if (== $needle $first) true (stored-list-member? $needle $rest)))

;; Reverse a proper list onto a tail without erasing its element type.
(: reverse-onto (-[det]-> (List $item) (List $item) (List $item)))
(= (reverse-onto () $tail) $tail)
(= (reverse-onto (cons $head $rest) $tail)
   (reverse-onto $rest (cons $head $tail)))

;; Evaluate predicates in list order and stop at the first true value.
;; A boolean fold would still visit every remaining element.
(: any-flat? (-[det]-> (-[det]-> $item Bool) (List $item) Bool))
(= (any-flat? $_predicate ()) false)
(= (any-flat? $predicate (cons $item $rest))
   (if ($predicate $item) true (any-flat? $predicate $rest)))


(: sk-cons-step (-[semidet]-> (List $item) $item (List $item)))
(= (sk-cons-step $items $item) (cons $item $items))
