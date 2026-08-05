;; Exact inverse goals for the built-in binary arithmetic Compute subset.
;;
;; The compiler calls this only after proving that the Compute result and every
;; input except the selected argument are already known. The original forward
;; CPU goal is retained after the inverse goal as a validation step.

(: ComputeInverseGoalResult Type)
(: inverse-compute-goal
   (-[det]-> Goal ComputeInverseGoalResult))
(: no-compute-inverse-goal ComputeInverseGoalResult)

(: configured-compute-inverse-mode
   (-[det]-> Atom Number Atom))
(= (configured-compute-inverse-mode $function $unknown-index)
   (case $function (
      (+
         (case $unknown-index (
            (0 inverse-add-left)
            (1 inverse-add-right)
            ($_index no-compute-inverse-mode))))
      (-
         (case $unknown-index (
            (0 inverse-subtract-left)
            (1 inverse-subtract-right)
            ($_index no-compute-inverse-mode))))
      ($_function no-compute-inverse-mode))))

(: compute-inverse-goal-or-none
   (-[det]-> Atom Number Atom Atom ComputeInverseGoalResult))
(= (compute-inverse-goal-or-none
      $function $unknown-index $args $result)
   (case
      (configured-compute-inverse-mode
         $function $unknown-index)
      ((inverse-add-left
         (case $args (
            ((cons $unknown (cons $right ()))
               (inverse-compute-goal
                  (CPU - (quote ($result $right)) $unknown)))
            ($_args no-compute-inverse-goal))))
       (inverse-add-right
         (case $args (
            ((cons $left (cons $unknown ()))
               (inverse-compute-goal
                  (CPU - (quote ($result $left)) $unknown)))
            ($_args no-compute-inverse-goal))))
       (inverse-subtract-left
         (case $args (
            ((cons $unknown (cons $right ()))
               (inverse-compute-goal
                  (CPU + (quote ($result $right)) $unknown)))
            ($_args no-compute-inverse-goal))))
       (inverse-subtract-right
         (case $args (
            ((cons $left (cons $unknown ()))
               (inverse-compute-goal
                  (CPU - (quote ($left $result)) $unknown)))
            ($_args no-compute-inverse-goal))))
       ($_mode no-compute-inverse-goal))))
