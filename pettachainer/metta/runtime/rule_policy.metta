;; Rule identity, evidence registration and predicate/query policy.
;; Shared by compiler and runtime; no lowering or emitted additions belong here.

(: rule-evidence-base-name (-[det]-> Proof Proof))
(= (rule-evidence-base-name $prf)
   (if (= $prf (bi-forward $fwd)) (brand Proof $fwd)
      (if (= $prf (bi-backward $bwd)) (brand Proof $bwd)
         (if (= $prf (no_inverse $inner)) (brand Proof $inner) $prf))))

;; A rule's evidence name is a symbol, or the context token of an implication
;; assumed in an Assuming query, which names that query-local rule as a
;; symbol names a stored one. Other proof expressions are not rule names.
(: rule-name? (-[det]-> Proof Bool))
(= (rule-name? $name) (if (is-expr $name) (head-is? $name ctx) true))

(: rule-evidence-registered? (-[det]-> KB Proof Bool))
(= (rule-evidence-registered? $kbid $name)
   (not (== (collapse (once (match &rule_evidence_names ($name $kbid) true))) ())))

(: given-rule? (-[det]-> KB Proof Bool))
(= (given-rule? $kbid $name) (not (== (collapse (once (match &given_rules ($name $kbid) true))) ())))

;; Whether a rule's applications carry an entry naming it: an estimated rule's
;; or a ground given rule's.
(: named-rule? (-[det]-> KB Proof Bool))
(= (named-rule? $kbid $name) (if (rule-evidence-registered? $kbid $name) true (given-rule? $kbid $name)))

;; A rule's applications carry its evidence when its truth is an estimate, so
;; a proof of the rule (its axiom) and a proof through it are not independent;
;; two applications to different premises are, given the rule's truth (see
;; sk-merge-facts). A rule stated with confidence 1 in every branch is not
;; refined (`refined-rule?`): its truth is given, and carries no evidence. A
;; given rule whose every branch has strength 0 or 1 is deterministic: applied
;; to certain premises it determines its conclusion (sk-determined-row?).
(: register-rule-evidence! (-[det]-> KB Proof TV Bool (List $no-result)))
(= (register-rule-evidence! $kb $prf $tv $ground)
   (let $name (rule-evidence-base-name $prf)
      (if (not (rule-name? $name)) ()
         (if (logic-rule? $name) ()
            (if (rule-evidence-registered? $kb $name) ()
               (case $tv (
                  ((STV $s $c)
                     (let $_named (register-given-name! $kb $name $ground (cons (STV $s $c) ()))
                        (register-given-branches! $kb $name (cons (STV $s $c) ()))))
                  ((CTV $pos $neg)
                     (let $_named (register-given-name! $kb $name $ground (cons $pos (cons $neg ())))
                        (register-given-branches! $kb $name (cons $pos (cons $neg ())))))
                  ($_other (register-rule-evidence-name! $kb $name)))))))))

(: register-given-branches! (-[det]-> KB Proof (List TV) (List $no-result)))
(= (register-given-branches! $kb $name $branches)
   (if (fold-flat given-branch-step true $branches)
      (if (fold-flat deterministic-branch-step true $branches)
         (if (deterministic-rule? $kb $name) ()
            (let $_added (add-atom &deterministic_rules ($name $kb)) ()))
         ())
      (register-rule-evidence-name! $kb $name)))

;; Named apart from the deterministic check, so a rule seen before, or first
;; stated generally, is still named once a ground statement of it is given.
(: register-given-name! (-[det]-> KB Proof Bool (List TV) (List $no-result)))
(= (register-given-name! $kb $name $ground $branches)
   (if (if $ground (fold-flat given-branch-step true $branches) false)
      (if (given-rule? $kb $name) () (let $_added (add-atom &given_rules ($name $kb)) ()))
      ()))

(: given-branch-step (-[det]-> Bool TV Bool))
(= (given-branch-step $given $branch)
   (if $given (case $branch (((STV $_s $c) (if (is-var $c) false (>= $c 1.0))) ($_other false))) false))

(: deterministic-branch-step (-[det]-> Bool TV Bool))
(= (deterministic-branch-step $deterministic $branch)
   (if $deterministic
      (case $branch (((STV $s $_c) (if (is-var $s) false (if (<= $s 0.0) true (>= $s 1.0)))) ($_other false)))
      false))

(: register-rule-evidence-name! (-[det]-> KB Proof (List $no-result)))
(= (register-rule-evidence-name! $kb $name)
   (let $_added (collapse (once (add-atom &rule_evidence_names ($name $kb)))) ()))

(: equivalence-rule? (-[det]-> KB Proof Bool))
(= (equivalence-rule? $kb $prf) (not (== (collapse (once (match &equivalence_rules ($prf $kb) true))) ())))

(: register-equivalence-rule! (-[det]-> KB Proof TV Statement Statement Atom))
(= (register-equivalence-rule! $kb $prf $tv $antecedent $consequent)
   (if (head-is? $prf no_inverse) ()
      (if (if (== (extract-vars $tv) ())
             (if (== (cdr-atom (implication-side-conjuncts $antecedent)) ())
                (if (vars-covered? $antecedent (extract-vars $consequent)) (vars-covered? $consequent (extract-vars $antecedent)) false)
                false)
             false)
         (case $tv (
            ((CTV (STV $ps $pc) (STV $ns $nc))
               (if (if (>= $ps 1.0) (if (>= $pc 1.0) (if (<= $ns 0.0) (>= $nc 1.0) false) false) false)
                  (if (equivalence-rule? $kb $prf) () (let $_added (add-atom &equivalence_rules ($prf $kb)) ()))
                  ()))
            ($_other ())))
         ())))

(: deterministic-rule? (-[det]-> KB Proof Bool))
(= (deterministic-rule? $kbid $name) (not (== (collapse (once (match &deterministic_rules ($name $kbid) true))) ())))

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
