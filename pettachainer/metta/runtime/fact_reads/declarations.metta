(: set-positive-only-predicate (-[det]-> KB Atom Bool))
(= (set-positive-only-predicate $kb $head)
   (let $_declared (declared-head! $head)
      (if (== (collapse (once (match &positive_only_predicates ($kb $head) true))) ())
         (let $_row (add-atom &positive_only_predicates ($kb $head)) true)
         true)))

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
