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
