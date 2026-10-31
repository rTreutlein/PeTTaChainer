

(: set-positive-only-predicate (-[det]-> KB Atom Bool))
(= (set-positive-only-predicate $kb $head)
   (let $_declared (declared-head! $head)
      (if (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())
         (let $_row (add-atom &positive_only_predicates ($kb $head)) true)
         true)))

(: complete-predicate? (-[det]-> KB Atom Bool))
(= (complete-predicate? $kb $head)
   (not (== (collapse (once (match &complete_predicates ($kb $head) true))) ())))
(: set-complete-predicate (-[det]-> KB Atom Bool))
(= (set-complete-predicate $kb $head)
   (let $_declared (declared-head! $head)
      (if (complete-predicate? $kb $head) true
         (let $_row (add-atom &complete_predicates ($kb $head)) true))))

;; The strength of a rule's negative branch that no rate determines: even odds,
;; but false for a complete conclusion, which only rule applications make true.
(: unknown-branch-centre (-[det]-> KB Statement Number))
(= (unknown-branch-centre $kb $b)
   (let $head (if (is-expr $b) (car-atom $b) $b)
      (if (complete-predicate? $kb $head) 0.0 0.5)))

(: positive-only-pattern? (-[det]-> KB Statement Bool))
(= (positive-only-pattern? $kb $pattern)
   (fold-flat (positive-only-conjunct? $kb) false (implication-side-conjuncts $pattern)))
(: positive-only-conjunct? (-[det]-> KB Bool Atom Bool))
(= (positive-only-conjunct? $kb $seen $conjunct)
   (if $seen true
      (let* ((($statement $_odd) (canon (brand Statement $conjunct)))
             ($head (if (is-expr $statement) (car-atom $statement) $statement)))
         (not (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())))))

;; An implication is also estimated from its instances: one sample per
;; antecedent binding whose consequent is provable, both sides resolved through
;; the backward chainer so derived instances count. Open world: an antecedent
;; instance without a provable consequent is not a sample. A sample never uses
;; a rule that restates the implication (see `sk-sample-exclusions`). The fold's
;; strength is the mass-weighted consequent strength and its confidence
;; count-based. Sampling needs plain predicate conjuncts whose consequent
;; variables the antecedent binds.
(: unsampled-conjunct? (-[det]-> Bool Atom Bool))
(= (unsampled-conjunct? $seen $conjunct)
   (if $seen true
      (if (is-var $conjunct) true
         (head-is-member? $conjunct
            (And Or Not Implication BiImplication Exists Compute
               KnownExistential ExistentialResidual)))))

(: implication-instance-supported? (-[det]-> Statement Statement Bool))
(= (implication-instance-supported? $antecedent $consequent)
   (if (is-var $antecedent) false
      (if (is-expr $consequent)
         (if (fold-flat unsampled-conjunct? false
                (cons $consequent (implication-side-conjuncts $antecedent)))
            false
            (vars-covered? $consequent (list_to_set (extract-vars $antecedent))))
         false)))

(: set-context-polymorphic-facts (-[det]-> KB Bool Bool))
(= (set-context-polymorphic-facts $kb $enabled)
   (let $_old
      (collapse
         (match &context_polymorphic_facts
            ($kb $stored)
            (remove-atom &context_polymorphic_facts ($kb $stored))))
      (let $_added
         (collapse
            (once
               (add-atom &context_polymorphic_facts
                  ($kb $enabled))))
         $enabled)))

(: context-polymorphic-facts? (-[det]-> KB Bool))
(= (context-polymorphic-facts? $kb)
   (space-row-present? &context_polymorphic_facts (quote ($kb true))))

;; Rule refinement is opt-in per KB and set before its rules are added. A
;; refined rule's truth is the goal (RuleTruth (Implication a b)): the stored
;; truth is its axiom, the rule's instance fold a second proof, and the rule
;; applies, forward, backward, inverted and completed, with their revision.
;; Only named user rules whose sides the instance producer samples are refined.
(: set-rule-refinement (-[det]-> KB Bool Bool))
(= (set-rule-refinement $kb $enabled)
   (let* (($_old
             (collapse (match &rule_refinement ($kb $stored)
                (remove-atom &rule_refinement ($kb $stored)))))
          ($_new (add-atom &rule_refinement ($kb $enabled))))
      $enabled))

;; Only a rule certain in every branch is given. An uncertain CTV branch
;; still learns from its instances when the other branch is certain.
(: refined-rule? (-[det]-> KB Proof Statement Statement TV Bool))
(= (refined-rule? $kb $prf $a $b $tv)
   (if (== (collapse (once (match &rule_refinement ($kb true) true))) ()) false
      (let* (($name (rule-evidence-base-name $prf))
             ($c (case $tv (((STV $_s $c) $c)
                ((CTV (STV $_ps $pc) (STV $_ns $nc))
                   (if (is-var $pc) $pc (if (is-var $nc) $nc (min $pc $nc))))))))
         (if (is-expr $name) false
            (if (logic-rule? $name) false
               (if (is-var $c) false
                  (if (>= $c 1.0) false (implication-instance-supported? $a $b))))))))
