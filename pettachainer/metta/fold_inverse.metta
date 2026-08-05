;; Exact inverse for a finite, nonnegative weighted subset sum.
;;
;; Candidate order defines the canonical order of identities inside each
;; Selection. Candidate identities must be unique. Priors are independent
;; Bernoulli probabilities and contribute on both the selected and unselected
;; branches. The result keeps mutually exclusive configurations in one value;
;; callers may then project per-item conditional probabilities without
;; asserting every member of every alternative as an independent fact.

(: WeightedSubsetCandidate Type)
(: WeightedCandidate
   (-[det]-> Atom Number Number WeightedSubsetCandidate))

(: SubsetSelection Type)
(: Selection (-[det]-> (List Atom) SubsetSelection))

(: WeightedSubsetSolutions Type)
(: WeightedSelections
   (-[det]-> (List (SubsetSelection Number)) WeightedSubsetSolutions))

(: weighted-subset-sum-pairs
   (-[det]-> (List WeightedSubsetCandidate) Number
       (List Atom) Number
       (List (SubsetSelection Number))))

(: append-weighted-selection-pairs
   (-[det]-> (List (SubsetSelection Number))
       (List (SubsetSelection Number))
       (List (SubsetSelection Number))))
(= (append-weighted-selection-pairs () $right) $right)
(= (append-weighted-selection-pairs (cons $item $tail) $right)
   (cons $item (append-weighted-selection-pairs $tail $right)))

(= (weighted-subset-sum-pairs
      () $remaining $selected $weight)
   (if (== $remaining 0)
      (let $selection (Selection (reverse $selected))
         (cons (quote ($selection $weight)) ()))
      ()))
(= (weighted-subset-sum-pairs
      (cons (WeightedCandidate $item $value $prior) $tail)
      $remaining $selected $weight)
   (let $excluded
      (weighted-subset-sum-pairs
         $tail $remaining $selected
         (* $weight (- 1.0 $prior)))
      (if (<= $value $remaining)
         (append-weighted-selection-pairs
            (weighted-subset-sum-pairs
               $tail (- $remaining $value)
               (cons $item $selected)
               (* $weight $prior))
            $excluded)
         $excluded)))

(: weighted-selection-pair-total
   (-[det]-> (List (SubsetSelection Number)) Number))
(= (weighted-selection-pair-total ()) 0.0)
(= (weighted-selection-pair-total
      (cons ($_selection $weight) $tail))
   (+ $weight (weighted-selection-pair-total $tail)))

(: scale-weighted-selection-pairs
   (-[det]-> (List (SubsetSelection Number)) Number
       (List (SubsetSelection Number))))
(= (scale-weighted-selection-pairs () $_scale) ())
(= (scale-weighted-selection-pairs
      (cons ($selection $weight) $tail) $scale)
   (let $scaled (* $weight $scale)
      (cons
         (quote ($selection $scaled))
         (scale-weighted-selection-pairs $tail $scale))))

(: normalize-weighted-selection-pairs
   (-[det]-> (List (SubsetSelection Number))
       (List (SubsetSelection Number))))
(= (normalize-weighted-selection-pairs $pairs)
   (let $total (weighted-selection-pair-total $pairs)
      (if (<= $total 0.0)
         ()
         (scale-weighted-selection-pairs $pairs (/ 1.0 $total)))))

(: WeightedSubsetSumInverse
   (-[det]-> (List WeightedSubsetCandidate) Number
       WeightedSubsetSolutions))
(= (WeightedSubsetSumInverse $candidates $target)
   (WeightedSelections
      (if (< $target 0)
         ()
         (normalize-weighted-selection-pairs
            (weighted-subset-sum-pairs
               $candidates $target () 1.0)))))

(: WeightedSubsetPairs
   (-[det]-> WeightedSubsetSolutions
       (List (SubsetSelection Number))))
(= (WeightedSubsetPairs (WeightedSelections $pairs)) $pairs)

(: subset-selection-contains?
   (-[det]-> (List Atom) Atom Bool))
(= (subset-selection-contains? () $_target) false)
(= (subset-selection-contains? (cons $item $tail) $target)
   (if (== $item $target)
      true
      (subset-selection-contains? $tail $target)))

(: weighted-subset-marginal-pairs
   (-[det]-> (List (SubsetSelection Number)) Atom Number))
(= (weighted-subset-marginal-pairs () $_target) 0.0)
(= (weighted-subset-marginal-pairs
      (cons ((Selection $items) $weight) $tail) $target)
   (+
      (if (subset-selection-contains? $items $target)
         $weight
         0.0)
      (weighted-subset-marginal-pairs $tail $target)))

(: WeightedSubsetMarginal
   (-[det]-> WeightedSubsetSolutions Atom Number))
(= (WeightedSubsetMarginal (WeightedSelections $pairs) $target)
   (weighted-subset-marginal-pairs $pairs $target))
