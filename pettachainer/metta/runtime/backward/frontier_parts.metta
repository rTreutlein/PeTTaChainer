;; Frontier part algebra: the truth-value and admissibility semantics of a
;; conjunction frontier, independent of any scheduling order.
;;
;; This layer decides what a premise proof contributes to a partially
;; consumed (And ...) frontier — an independent part, a projection pooled
;; with other projections of the same source, or a poison value that forces
;; rejection — and what the folded TV, score, and remaining potential of a
;; part list are. It also holds the admissibility rules the scheduler
;; consults before feeding a proof to a frontier: cycle-key conditions (a
;; recursive proof must not be consumed by its own ancestors), the
;; shared-evidence allowance for compiler-generated joins, and which proof
;; representation (raw, merged, parent-conditioned) a bundle requires.
;;
;; It is a separate layer because these rules are the logical soundness of
;; conjunction evidence combination and must hold under any scheduling. The
;; file owns no spaces and mutates nothing; proof facts reach it only through
;; proof_store accessors, so the same inputs always yield the same answers.
;; The part row shapes are declared (for load order) in demand.metta, where
;; the pooling model is documented alongside them.
;; An exhausted pool contributes zero remaining potential: any floor above
;; the neutral element keeps dead frontiers alive on the agenda and buys
;; extra proof work for nothing.

;; Compiler-marked joins whose premises intentionally share source evidence.
(: shared-evidence-frontier-proof? (-[det]-> Proof Bool))
(= (shared-evidence-frontier-proof? $proof)
   (if (is-var $proof)
      false
      (if (is-expr $proof)
         (let $head (car-atom $proof)
            (if (is-var $head)
               false
               (if (stored-list-member? $head
                      (total-implication-frontier member-inheritance-sample))
                  true
                  (if (== $head inheritance-query-result)
                     (shared-evidence-frontier-proof?
                        (brand Proof (car-atom (cdr-atom $proof))))
                     false))))
         false)))
(: frontier-allows-shared-evidence? (-[det]-> AndBundle Bool))
(= (frontier-allows-shared-evidence?
      (and-bundle $goal $_premises))
   (case $goal (
      (($_type $_kb $proof $_tv)
         (shared-evidence-frontier-proof? (brand Proof $proof)))
      ($_other false))))
;; Projection evidence belongs to the pool key: revisions of one proposition
;; are not one joint observation.
(: frontier-premise-part (-[det]-> ProofSupport
      (| FrontierPart SkipPart UnpoolablePart)))
(= (frontier-premise-part
      (proof-support $_score $evidence $contribution))
   (case $contribution (
      ((independent-contribution $tv)
         (indep-part $tv))
      ((projected-contribution $base $base-tv $arity $idx $marginal-tv)
         (pool-part $base $base-tv $arity
            (cons $idx ()) $evidence $marginal-tv))
      (skip-contribution skip-part)
      (unpoolable-contribution unpoolable-part))))
(: frontier-parts-same-pool? (-[det]->
      (| FrontierPart SkipPart UnpoolablePart)
      (| FrontierPart SkipPart UnpoolablePart) Bool))
(= (frontier-parts-same-pool? $left $right)
   (case $left (
      ((pool-part $base $base-tv $arity $_idxs $evidence $_marginal-tv)
         (case $right (
            ((pool-part $other-base $other-base-tv $other-arity
                  $_other-idxs $other-evidence $_other-marginal-tv)
               (if (=alpha $base $other-base)
                  (if (== $base-tv $other-base-tv)
                     (if (== $arity $other-arity)
                        (== $evidence $other-evidence)
                        false)
                     false)
                  false))
            ($_other false))))
      ($_other false))))
(: frontier-parts-contain-pool? (-[det]->
      (| FrontierPart SkipPart UnpoolablePart)
      (List (| FrontierPart UnpoolablePart)) Bool))
(= (frontier-parts-contain-pool? $_part ()) false)
(= (frontier-parts-contain-pool? $part (cons $head $rest))
   (if (frontier-parts-same-pool? $part $head)
      true
      (frontier-parts-contain-pool? $part $rest)))
(: frontier-pool-join? (-[det]->
      (| FrontierPart SkipPart UnpoolablePart)
      (List (| FrontierPart UnpoolablePart))
      (List Evidence) (List Evidence) Bool))
(= (frontier-pool-join? $part $parts $seen $evidence)
   (case $part (
      ((pool-part $_base $_base-tv $_arity $_idxs $_part-evidence
            $_marginal-tv)
         (if (premise-evidence-overlap? $seen $evidence)
            (frontier-parts-contain-pool? $part $parts)
            false))
      ($_other false))))
(: frontier-parts-put (-[det]->
      (List (| FrontierPart UnpoolablePart))
      (| FrontierPart UnpoolablePart)
      (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-put () $part) (cons $part ()))
(= (frontier-parts-put (cons $head $rest) $part)
   (case $head (
      ((pool-part $base $base-tv $arity $idxs $evidence $marginal-tv)
         (case $part (
            ((pool-part $_other-base $_other-base-tv $_other-arity
                  $other-idxs $_other-evidence $_other-marginal-tv)
               (if (frontier-parts-same-pool? $head $part)
                  (cons
                     (pool-part $base $base-tv $arity
                        (list_to_set
                           (append-flat $other-idxs $idxs))
                        $evidence $marginal-tv)
                     $rest)
                  (cons $head
                     (frontier-parts-put $rest $part))))
            ($_other
               (cons $head (frontier-parts-put $rest $part))))))
      ($_other
         (cons $head (frontier-parts-put $rest $part))))))
(: frontier-parts-add (-[det]->
      (List (| FrontierPart UnpoolablePart))
      (| FrontierPart SkipPart UnpoolablePart)
      (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-add $parts $part)
   (case $part (
      (skip-part $parts)
      ($_other
         (frontier-parts-put $parts
            (the (| FrontierPart UnpoolablePart) $part))))))
(: frontier-part-tv
   (-[semidet]-> (| FrontierPart SkipPart UnpoolablePart) TV))
(= (frontier-part-tv $part)
   (case $part (
      ((indep-part $tv) $tv)
      ((pool-part $_base $base-tv $arity $idxs $_evidence $marginal-tv)
         (if (== (list-count $idxs) $arity)
            $base-tv
            $marginal-tv))
      ($_other (empty)))))
(: frontier-and-tv
   (-[semidet]-> TV (| FrontierPart UnpoolablePart) TV))
(= (frontier-and-tv $acc $part)
   (AndFormula $acc (frontier-part-tv $part)))
(: frontier-parts-fold
   (-[semidet]-> (List (| FrontierPart UnpoolablePart)) TV))
(= (frontier-parts-fold (cons $part $rest))
   (proof-fold-flat-semidet frontier-and-tv (frontier-part-tv $part) $rest))
(: frontier-part-score
   (-[det]-> (| FrontierPart SkipPart UnpoolablePart)
       Number Number))
(= (frontier-part-score $part $fallback)
   (case $part (
      ((pool-part $_base $base-tv $_arity $_idxs $_evidence $_marginal-tv)
         (tv-confidence $base-tv))
      ($_other $fallback))))
(: frontier-pool-potential-step
   (-[det]-> Number (| FrontierPart UnpoolablePart) Number))
(= (frontier-pool-potential-step $acc $part)
   (max $acc (frontier-part-score $part 0.0)))
(: frontier-pool-potential
   (-[det]-> (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-pool-potential $parts)
   (fold-flat frontier-pool-potential-step 0.0 $parts))
(: frontier-remaining-score (-[det]-> AndBundle
       (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-remaining-score
      (and-bundle $_goal $premises) $parts)
   (max
      (premises-expected-confidence (copy_term $premises))
      (frontier-pool-potential $parts)))

;; Pooled advancement also consumes the generated AndFormula step and binds its
;; result to the fold, so shared projections are not multiplied independently.
(: frontier-goal-proof-view (-[det]->
      (| Goal (Statement KBContext Proof TV))
      (| Goal (Statement KBContext Proof TV))))
(= (frontier-goal-proof-view $goal)
   (case $goal (
      (($type $kb $proof $tv)
         (if (is-var $proof)
            $goal
            (if (is-expr $proof)
               (if (is-var (car-atom $proof))
                  (let $tail (cdr-atom $proof)
                     (if (== $tail ())
                        $goal
                        (if (== (cdr-atom $tail) ())
                           (let $inner (car-atom $tail)
                              (assemble-stored-runtime-fact
                                 $type $kb $inner $tv))
                           $goal)))
                  $goal)
               $goal)))
      ($_other $goal))))
(: advance-frontier-bundle
   (-[semidet]-> AndBundle Number Atom))
(= (advance-frontier-bundle
      (and-bundle $goal (cons $premise $rest)) $pid)
   (let $output (proof-output-atom-by-id $pid)
      (if (= $premise $output)
         (and-bundle (frontier-goal-proof-view $goal) $rest)
         ())))
(: frontier-pooled-bundle
   (-[semidet]-> AndBundle Number TV Atom))
(= (frontier-pooled-bundle $bundle $pid $folded-tv)
   (let $advanced (advance-frontier-bundle $bundle $pid)
      (case $advanced (
         ((and-bundle $goal
               (cons (CPU AndFormula $_arguments $result) $rest))
            (if (= $result $folded-tv)
               (and-bundle $goal $rest)
               ()))
         ($_other ())))))
(: frontier-bundle-proof (-[det]-> AndBundle (| Proof NoPoolKey)))
(= (frontier-bundle-proof (and-bundle $goal $_premises))
   (case $goal (
      (($_type $_kb $proof $_tv)
         (if (is-var $proof)
            no-pool-key
            (brand Proof $proof)))
      ($_other no-pool-key))))
(: frontier-needs-raw-proofs? (-[det]-> AndBundle Bool))
(= (frontier-needs-raw-proofs? (and-bundle $goal $_premises))
   (case $goal (
      (($_type $_kb $proof $_tv)
         (proof-term-conjunction-dependency? (brand Proof $proof)))
      ($_other false))))
(: frontier-compatible-source-id-step (-[semidet]-> Number Atom
      (List Number) Number (List Number)))
(= (frontier-compatible-source-id-step
      $parent-gid $cycle-key $acc $pid)
   (if (proof-depends-on-goal-seen?
          $pid $parent-gid
          (the (| ProofOutputKey ClosedGoalKey) $cycle-key) ())
      $acc
      (cons $pid $acc)))
(: noncyclic-proof-source-ids (-[semidet]-> Number Atom
      Number (List Number)))
(= (noncyclic-proof-source-ids $parent-gid $cycle-key $child-gid)
   (let $compatible (reverse-number-list
      (proof-fold-flat-semidet
         (frontier-compatible-source-id-step $parent-gid $cycle-key) ()
         (goal-source-proof-ids $child-gid
            (proof-revision (proof-goal-key-by-goal-id $child-gid)))))
      (proof-fold-flat-semidet prefer-compatible-derivation-step () $compatible)))
;; Opposite directions of one BiImplication are one definition. Reject the
;; immediate reverse even when lowering flattened its intermediate proof node.
(: frontier-opposite-bi-direction? (-[det]-> Proof Proof Bool))
(= (frontier-opposite-bi-direction? $parent $child)
   (case $parent (
      ((by (bi-forward $name) $_dependency)
         (case $child (
            ((by (bi-backward $other) $_other-dependency)
               (== $name $other))
            ($_other false))))
      ((by (bi-backward $name) $_dependency)
         (case $child (
            ((by (bi-forward $other) $_other-dependency)
               (== $name $other))
            ($_other false))))
      ($_other false))))
