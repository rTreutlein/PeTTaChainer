;; Exact finite, nonnegative weighted subset diagnosis.
;;
;; Candidate order defines the canonical order of identities inside each
;; Selection. Candidate identities must be unique. Priors are independent
;; Bernoulli probabilities and contribute on both the selected and unselected
;; branches. `EnumerateWeightedSubsetExplanations` keeps mutually exclusive
;; configurations in one value. `WeightedSubsetPosteriorDP` instead merges
;; probability mass by reachable loss into reusable prefix and postfix rows.

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

;; Exhaustive compatibility entry point. This solves the inverse problem but
;; does not invert a FoldAll rule at runtime; it enumerates every exact subset.
(: EnumerateWeightedSubsetExplanations
   (-[det]-> (List WeightedSubsetCandidate) Number
       WeightedSubsetSolutions))
(= (EnumerateWeightedSubsetExplanations $candidates $target)
   (WeightedSelections
      (if (< $target 0)
         ()
         (normalize-weighted-selection-pairs
            (weighted-subset-sum-pairs
               $candidates $target () 1.0)))))

;; Preserve the original public name for existing rules and examples.
(: WeightedSubsetSumInverse
   (-[det]-> (List WeightedSubsetCandidate) Number
       WeightedSubsetSolutions))
(= (WeightedSubsetSumInverse $candidates $target)
   (EnumerateWeightedSubsetExplanations $candidates $target))

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

;; Compact posterior dynamic program. Prefix row i is the loss distribution
;; before candidate i; postfix row i is the distribution from candidate i to
;; the end. A marginal joins prefix i with postfix i+1 after selecting i.
;; Rows merge equal reachable losses and never retain fault-set paths.

(: WeightedPosteriorCell Type)
(: WeightedDPCell
   (-[det]-> Number Number WeightedPosteriorCell))

(: WeightedPosteriorRow Type)
(: WeightedDPRow
   (-[det]-> (List WeightedPosteriorCell) WeightedPosteriorRow))

(: WeightedSubsetDPValue Type)
(: WeightedSubsetDP
   (-[det]-> Number
       (List WeightedSubsetCandidate)
       (List WeightedPosteriorRow)
       (List WeightedPosteriorRow)
       WeightedSubsetDPValue))

(: scale-shift-weighted-dp-cells
   (-[det]-> (List WeightedPosteriorCell) Number Number Number
       (List WeightedPosteriorCell)))
(= (scale-shift-weighted-dp-cells
      () $_factor $_offset $_target)
   ())
(= (scale-shift-weighted-dp-cells
      (cons (WeightedDPCell $loss $mass) $rest)
      $factor $offset $target)
   (let $shifted-loss (+ $loss $offset)
      (if (> $shifted-loss $target)
         ()
         (cons
            (WeightedDPCell $shifted-loss (* $mass $factor))
            (scale-shift-weighted-dp-cells
               $rest $factor $offset $target)))))

(: merge-weighted-dp-cells
   (-[det]-> (List WeightedPosteriorCell)
       (List WeightedPosteriorCell)
       (List WeightedPosteriorCell)))
(= (merge-weighted-dp-cells () $right) $right)
(= (merge-weighted-dp-cells (cons $left-head $left-rest) ())
   (cons $left-head $left-rest))
(= (merge-weighted-dp-cells
      (cons (WeightedDPCell $left-loss $left-mass) $left-rest)
      (cons (WeightedDPCell $right-loss $right-mass) $right-rest))
   (if (< $left-loss $right-loss)
      (cons
         (WeightedDPCell $left-loss $left-mass)
         (merge-weighted-dp-cells
            $left-rest
            (cons (WeightedDPCell $right-loss $right-mass) $right-rest)))
      (if (> $left-loss $right-loss)
         (cons
            (WeightedDPCell $right-loss $right-mass)
            (merge-weighted-dp-cells
               (cons (WeightedDPCell $left-loss $left-mass) $left-rest)
               $right-rest))
         (cons
            (WeightedDPCell $left-loss (+ $left-mass $right-mass))
            (merge-weighted-dp-cells $left-rest $right-rest)))))

(: weighted-dp-step-cells
   (-[det]-> (List WeightedPosteriorCell)
       WeightedSubsetCandidate Number
       (List WeightedPosteriorCell)))
(= (weighted-dp-step-cells
      $cells
      (WeightedCandidate $_candidate $value $prior)
      $target)
   (let*
      (($excluded-factor (- 1.0 $prior))
       ($without
          (if (> $excluded-factor 0.0)
             (scale-shift-weighted-dp-cells
                $cells $excluded-factor 0 $target)
             (the (List WeightedPosteriorCell) ())))
       ($with
          (if (> $prior 0.0)
             (scale-shift-weighted-dp-cells
                $cells $prior $value $target)
             (the (List WeightedPosteriorCell) ()))))
      (merge-weighted-dp-cells $without $with)))

(: weighted-subset-candidates-valid?
   (-[det]-> (List WeightedSubsetCandidate) Bool))
(= (weighted-subset-candidates-valid? ()) true)
(= (weighted-subset-candidates-valid? (cons $candidate $rest))
   (case $candidate (
      ((WeightedCandidate $_identity $value $prior)
         (if (or (< $value 0)
                 (or (< $prior 0.0) (> $prior 1.0)))
            false
            (weighted-subset-candidates-valid? $rest)))
      ($_invalid-candidate false))))

(: weighted-prefix-dp-rows
   (-[det]-> (List WeightedSubsetCandidate) Number
       (List WeightedPosteriorCell)
       (List WeightedPosteriorRow)))
(= (weighted-prefix-dp-rows () $_target $cells)
   ((WeightedDPRow $cells)))
(= (weighted-prefix-dp-rows
      (cons $candidate $rest) $target $cells)
   (cons
      (WeightedDPRow $cells)
      (weighted-prefix-dp-rows
         $rest $target
         (weighted-dp-step-cells
            $cells $candidate $target))))

(: weighted-postfix-dp-rows
   (-[det]-> (List WeightedSubsetCandidate) Number
       (List WeightedPosteriorRow)))
(: reverse-weighted-candidates-into
   (-[det]-> (List WeightedSubsetCandidate)
       (List WeightedSubsetCandidate)
       (List WeightedSubsetCandidate)))
(= (reverse-weighted-candidates-into () $acc) $acc)
(= (reverse-weighted-candidates-into (cons $candidate $rest) $acc)
   (reverse-weighted-candidates-into $rest (cons $candidate $acc)))

(: reverse-weighted-dp-rows-into
   (-[det]-> (List WeightedPosteriorRow)
       (List WeightedPosteriorRow)
       (List WeightedPosteriorRow)))
(= (reverse-weighted-dp-rows-into () $acc) $acc)
(= (reverse-weighted-dp-rows-into (cons $row $rest) $acc)
   (reverse-weighted-dp-rows-into $rest (cons $row $acc)))

(= (weighted-postfix-dp-rows $candidates $target)
   (reverse-weighted-dp-rows-into
      (weighted-prefix-dp-rows
         (reverse-weighted-candidates-into $candidates ())
         $target
         ((WeightedDPCell 0 1.0)))
      ()))

(: WeightedSubsetPosteriorDP
   (-[det]-> (List WeightedSubsetCandidate) Number
       WeightedSubsetDPValue))
(= (WeightedSubsetPosteriorDP $candidates $target)
   (if (weighted-subset-candidates-valid? $candidates)
      (if (< $target 0)
         (WeightedSubsetDP $target $candidates () ())
         (WeightedSubsetDP
            $target
            $candidates
            (weighted-prefix-dp-rows
               $candidates $target ((WeightedDPCell 0 1.0)))
            (weighted-postfix-dp-rows $candidates $target)))
      (WeightedSubsetDP $target $candidates () ())))

(: weighted-dp-cell-mass
   (-[det]-> (List WeightedPosteriorCell) Number Number))
(= (weighted-dp-cell-mass () $_target) 0.0)
(= (weighted-dp-cell-mass
      (cons (WeightedDPCell $loss $mass) $rest) $target)
   (if (== $loss $target)
      $mass
      (weighted-dp-cell-mass $rest $target)))

(: final-weighted-dp-row-mass
   (-[det]-> (List WeightedPosteriorRow) Number Number))
(= (final-weighted-dp-row-mass () $_target) 0.0)
(= (final-weighted-dp-row-mass
      (cons (WeightedDPRow $cells) ()) $target)
   (weighted-dp-cell-mass $cells $target))
(= (final-weighted-dp-row-mass
      (cons $_row (cons $next $rest)) $target)
   (final-weighted-dp-row-mass (cons $next $rest) $target))

(: WeightedSubsetPosteriorMass
   (-[det]-> WeightedSubsetDPValue Number))
(= (WeightedSubsetPosteriorMass
      (WeightedSubsetDP $target $_candidates $prefix-rows $_postfix-rows))
   (final-weighted-dp-row-mass $prefix-rows $target))

(: weighted-dp-row-convolution-mass
   (-[det]-> (List WeightedPosteriorCell)
       (List WeightedPosteriorCell) Number Number))
(: reverse-weighted-dp-cells-into
   (-[det]-> (List WeightedPosteriorCell)
       (List WeightedPosteriorCell)
       (List WeightedPosteriorCell)))
(= (reverse-weighted-dp-cells-into () $acc) $acc)
(= (reverse-weighted-dp-cells-into (cons $cell $rest) $acc)
   (reverse-weighted-dp-cells-into $rest (cons $cell $acc)))

(: weighted-dp-row-convolution-desc
   (-[det]-> (List WeightedPosteriorCell)
       (List WeightedPosteriorCell) Number Number))
(= (weighted-dp-row-convolution-desc
      () $_postfix-cells $_target)
   0.0)
(= (weighted-dp-row-convolution-desc
      (cons $_prefix-head $_prefix-rest) () $_target)
   0.0)
(= (weighted-dp-row-convolution-desc
      (cons (WeightedDPCell $prefix-loss $prefix-mass) $prefix-rest)
      (cons (WeightedDPCell $postfix-loss $postfix-mass) $postfix-rest)
      $target)
   (let $loss (+ $prefix-loss $postfix-loss)
      (if (< $loss $target)
         (weighted-dp-row-convolution-desc
            $prefix-rest
            (cons
               (WeightedDPCell $postfix-loss $postfix-mass)
               $postfix-rest)
            $target)
         (if (> $loss $target)
            (weighted-dp-row-convolution-desc
               (cons
                  (WeightedDPCell $prefix-loss $prefix-mass)
                  $prefix-rest)
               $postfix-rest
               $target)
            (+
               (* $prefix-mass $postfix-mass)
               (weighted-dp-row-convolution-desc
                  $prefix-rest $postfix-rest $target))))))

(= (weighted-dp-row-convolution-mass
      $prefix-cells $postfix-cells $target)
   (weighted-dp-row-convolution-desc
      $prefix-cells
      (reverse-weighted-dp-cells-into $postfix-cells ())
      $target))

(: weighted-subset-selected-mass
   (-[det]-> (List WeightedSubsetCandidate)
       (List WeightedPosteriorRow)
       (List WeightedPosteriorRow)
       Number Atom Number))
(= (weighted-subset-selected-mass
      () $_prefix-rows $_postfix-rows $_target $_candidate)
   0.0)
(= (weighted-subset-selected-mass
      (cons (WeightedCandidate $identity $value $prior) $candidate-rest)
      (cons (WeightedDPRow $prefix-cells) $prefix-rest)
      (cons $_postfix-row
         (cons (WeightedDPRow $postfix-cells) $postfix-rest))
      $target $candidate)
   (if (== $identity $candidate)
      (if (<= $value $target)
         (*
            $prior
            (weighted-dp-row-convolution-mass
               $prefix-cells $postfix-cells (- $target $value)))
         0.0)
      (weighted-subset-selected-mass
         $candidate-rest
         $prefix-rest
         (cons (WeightedDPRow $postfix-cells) $postfix-rest)
         $target $candidate)))

(: WeightedSubsetPosteriorMarginal
   (-[det]-> WeightedSubsetDPValue Atom Number))
(= (WeightedSubsetPosteriorMarginal
      (WeightedSubsetDP $target $candidates $prefix-rows $postfix-rows)
      $candidate)
   (let $total
      (WeightedSubsetPosteriorMass
         (WeightedSubsetDP
            $target $candidates $prefix-rows $postfix-rows))
      (if (> $total 0.0)
         (/ (weighted-subset-selected-mass
               $candidates $prefix-rows $postfix-rows
               $target $candidate)
            $total)
         0.0)))
