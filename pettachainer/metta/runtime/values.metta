

(: cpu-expected-tv (-[nondet]-> $formula $arguments Atom))
(= (cpu-expected-tv $fun ($a))
   (if (== $fun likelihood-read-tv)
      (likelihood-read-tv (normalize-expected-likelihoods $a))
   (if (== $fun NotFormula)
      (if (is-var $a) (STV 1.0 1.0) (NotFormula (normalize-expected-stv $a)))
      ())))

(= (cpu-expected-tv $fun ($a $b))
   (case $fun
      ((CTVModusPonensFormula
         (CTVModusPonensFormula (normalize-expected-evidence-tv $a) (normalize-expected-ctv $b)))
       (ImplicationModusPonensFormula
         (ImplicationModusPonensFormula
            (normalize-expected-evidence-tv $a)
            (normalize-expected-ctv $b)))
       (CTVFormula (CTVFormula (normalize-expected-evidence-tv $a) (normalize-expected-ctv $b)))
       ;; An open prior read as certain would leave P(A|not B) undefined, so
       ;; the inversion is expected at its rule's confidence, discounted as
       ;; CTVInversionFormula's is.
       (CTVBayesFormula
         (if (is-var $a)
            (let $confidence (* 0.9 (tv-confidence (expected-tv $b)))
               (CTV (STV 1.0 $confidence) (STV 1.0 $confidence)))
            (CTVBayesFormula (normalize-expected-evidence-tv $a)
               (normalize-expected-likelihoods $b))))
       (AndFormula (AndFormula (normalize-expected-stv $a) (normalize-expected-stv $b)))
       (OrFormula (OrFormula (normalize-expected-stv $a) (normalize-expected-stv $b)))
       (LikelierThanFormula
         (LikelierThanFormula (normalize-expected-stv $a) (normalize-expected-stv $b)))
       (() (cons () (cons (expected-tv $a) (cons (expected-tv $b) ()))))
       ($_other ()))))

(= (cpu-expected-tv $fun ($a $b $ctv))
   (if (== $fun CTVInversionFormula)
      (let*
         (($na (expected-tv $a))
          ($nb (expected-tv $b))
          ($nctv (expected-tv $ctv))
          ($confidence
             (* (min-atom
                  ((tv-confidence $na)
                   (tv-confidence $nb)
                   (case $nctv (((CTV $positive $_negative) (tv-confidence $positive)) ($_other (tv-confidence $nctv))))))
                0.9)))
         (if (or (is-var $a) (is-var $b))
            (CTV (STV 1.0 $confidence) (STV 1.0 $confidence))
            (CTVInversionFormula $na $nb (normalize-expected-likelihoods $ctv))))
      ()))

(= (cpu-expected-tv $fun ($a $b $c $d))
   (if (== $fun ImplicationLikelihoodsFormula)
      (ImplicationLikelihoodsFormula (the OptionalSTV (expected-tv $a))
         (the OptionalSTV (expected-tv $b)) (the (| STVType CTVType) (expected-tv $c)) (the Number $d))
      ()))

;; A completion is scored as if its connective had no evidence of its own.
(= (cpu-expected-tv $fun ($a $b $c $d $e))
   (if (== $fun CompletionLikelihoodsFormula)
      (CompletionLikelihoodsFormula $a
         (if (is-var $b) false (case $b ((true true) (false false))))
         false (expected-tv $d) (normalize-expected-likelihoods $e))
      ()))

;; Open proof templates are optimistic bounds, not evidence to resolve.
;; Only a closed observation can be used to select an empirical centre.
(= (cpu-expected-tv $fun ($kb $rule $antecedent $consequent $candidate $context))
   (if (== $fun rule-likelihood-read)
      (if (if (is-var $kb) true (if (is-var $rule) true (not (== (extract-vars $context) ()))))
         (normalize-expected-likelihoods $candidate)
         ;; This module loads before the operator's definition. The inner
         ;; reduction builds its call (cons/quote); the outer executes it.
         ;; One reduction leaves call data instead of the closed read record.
         (let $record (normalize-expected-likelihoods $candidate)
            (the LikelihoodRead (reduce (reduce
               (cons rule-likelihood-read
                  (quote ($kb $rule $antecedent $consequent $record $context))))))))
      ()))

(: first-cpu-expected-tv (-[det]-> $formula $arguments Atom))
(= (first-cpu-expected-tv $fun $args)
   (let $hits (collapse (cpu-expected-tv $fun $args)) (if (== $hits ()) () (car-atom $hits))))

(: cpu-expected-confidence (-[det]-> $formula $arguments Number))
(= (cpu-expected-confidence $fun $args)
   (let $res (first-cpu-expected-tv $fun $args) (if (== $res ()) 1.0 (tv-confidence $res))))

;; The event moment node's answers (prolog/runtime_helpers.pl, event-node-*),
;; STVs; a node with no possible world gives no answer. K is a formula over
;; its atoms; the other atoms come as their reads, proofs and keys. An
;; observed K's message to an atom: (node-message-result TV likelihood), the
;; atom's value from K alone on the uniform prior, and K's likelihood of the
;; atom's two values, which the merge reads with the atom's other messages on
;; its prior.
(: EventNodeMessage (-[semidet]-> Atom Number Proof TV Expression Expression Expression Atom))
(= (EventNodeMessage $formula $index $kproof $ktv $siblings $proofs $keys)
   (event-node-message $formula $index (evidence-confidence-k) (data $kproof $ktv) $siblings $proofs $keys))

(: EventNodeValue (-[semidet]-> Atom Number Proof TV Expression Expression Expression Atom))
(= (EventNodeValue $formula $index $kproof $ktv $siblings $proofs $keys)
   (event-node-value $formula $index (evidence-confidence-k) (data $kproof $ktv) $siblings $proofs $keys))

;; A predicted K's update of an atom: (node-jeffrey-result TV conditionals),
;; its value alone (applied to the uniform prior) and K's probability given
;; the atom true and false, which the merge applies to the atom's other views.
(: EventNodeJeffrey (-[semidet]-> Atom Number Proof TV Expression Expression Expression Atom))
(= (EventNodeJeffrey $formula $index $kproof $ktv $siblings $proofs $keys)
   (event-node-jeffrey $formula $index (evidence-confidence-k) (data $kproof $ktv) $siblings $proofs $keys))

(: EventNodeJoint (-[semidet]-> Atom Expression Proof TV Expression Expression Expression Atom))
(= (EventNodeJoint $formula $goal $kproof $ktv $atoms $proofs $keys)
   (event-node-joint $formula $goal (evidence-confidence-k) (data $kproof $ktv) $atoms $proofs $keys))
