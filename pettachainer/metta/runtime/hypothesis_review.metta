;; Reviewing mined hypotheses (docs/metta/hypothesis_rules.md, "Mining
;; hypotheses"). A review folds the live hypotheses' instances into their
;; truths by querying their RuleTruth goals, and drops the ones that do not
;; predict. Until forward chaining folds new instances into a refined rule's
;; truth as they arrive, the review is also what keeps the truths current.

;; A hypothesis is judged once its truth rests on hm-min-samples
;; observations; it stays when its strength differs from the consequent's
;; probability without its antecedent (hm-baseline), and from the strength of
;; every more general live hypothesis judged in the same review, by more than
;; hm-z standard errors.
;; One that had hm-max-opportunities observations of its consequent without
;; reaching enough samples of its own is dropped too.
(: hm-min-samples (-[det]-> Number))
(= (hm-min-samples) 4)
(: hm-z (-[det]-> Number))
(= (hm-z) 2)
(: hm-max-opportunities (-[det]-> Number))
(= (hm-max-opportunities) 32)

;; A live hypothesis under review: name, antecedent, consequent, its
;; consequent's count when it was born, truth.
(: HmReviewed Type)
(: hm-reviewed (-[det]-> Atom Atom Atom Number Atom HmReviewed))

;; For a ground goal, a hypothesis whose consequent unifies with it and
;; whose antecedent then holds of stored facts; for a variable, any.
(: hm-applies? (-[det]-> KB Atom Atom Bool))
(= (hm-applies? $kb $rule $goal)
   (if (is-var $goal) true
      (if (= (copy_term $rule) (Implication $antecedent $goal))
         (not (== (collapse (once (hm-holds $kb (implication-side-conjuncts (brand Statement $antecedent))))) ()))
         false)))

(: hm-holds (-[nondet]-> KB (List Atom) Bool))
(= (hm-holds $kb $conjuncts)
   (if (== $conjuncts ()) true
      (let* (((cons $conjunct $rest) $conjuncts)
             ($facts (kb-facts (brand Statement $conjunct) (brand KBContext ($kb $_ctx $_vars))))
             (($conjunct $_kbctx $_proof $_tv) (superpose $facts)))
         (hm-holds $kb $rest))))

;; A hypothesis with the most confident answer of its own review query.
(: hm-review-one (-[semidet]-> Number KB HmReviewed HmReviewed))
(= (hm-review-one $steps $kb (hm-reviewed $name $antecedent $consequent $born $_none))
   (let* (($rows (collapse (query-many-refs $steps $kb ((: $prf (RuleTruth (Implication $antecedent $consequent)) $tv)))))
          ($truth (fold-flat hm-best-answer no-evidence $rows)))
      (hm-reviewed $name $antecedent $consequent $born $truth)))

(: hm-best-answer (-[det]-> Atom Atom Atom))
(= (hm-best-answer $best $row)
   (case $row (
      ((query-result $_index (: $_prf $_stmt $tv))
         (if (> (hm-confidence $tv) (hm-confidence $best)) $tv $best))
      ($_other $best))))

(: hm-confidence (-[det]-> Atom Number))
(= (hm-confidence $tv)
   (case $tv (
      ((STV $_s $c) $c)
      ((CTV (STV $_s1 $c1) $_neg) $c1)
      ($_none 0))))

(: hm-strength (-[det]-> Atom Number))
(= (hm-strength $tv)
   (case $tv (
      ((STV $s $_c) $s)
      ((CTV (STV $s1 $_c1) $_neg) $s1)
      ($_none 0.5))))

;; |s - p| beyond hm-z standard errors of a rate p over n observations, p
;; kept within [0.05, 0.95] so a rate of 0 or 1 still has an error.
(: hm-differs? (-[det]-> Number Number Number Bool))
(= (hm-differs? $s $p $n)
   (let $q (min 0.95 (max 0.05 $p))
      (> (abs-math (- $s $q)) (* (hm-z) (sqrt-math (/ (* $q (- 1 $q)) $n))))))

(: hm-keep? (-[semidet]-> KB (List HmReviewed) HmReviewed Bool))
(= (hm-keep? $kb $reviewed (hm-reviewed $_name $antecedent $consequent $born $truth))
   (let* (($n (confidence-to-count (hm-confidence $truth)))
          ($s (hm-strength $truth))
          (($count $sum) (hm-outcomes $kb $consequent))
          ($rule (Implication $antecedent $consequent)))
      (if (< $n (hm-min-samples))
         (< (- $count $born) (hm-max-opportunities))
         (if (hm-differs? $s (hm-baseline $truth (/ (+ $sum 1) (+ $count 2))) $n)
            (fold-semidet (hm-unscreened $rule $s $n) true $reviewed)
            false))))

;; What the consequent's probability is without the antecedent: a CTV's
;; negative branch once an instance where the antecedent fails taught it,
;; otherwise the consequent pattern's rate.
(: hm-baseline (-[det]-> Atom Number Number))
(= (hm-baseline $truth $rate)
   (case $truth (
      ((CTV $_pos (STV $s0 $c0)) (if (>= (confidence-to-count $c0) 1) $s0 $rate))
      ($_stv $rate))))

;; Not screened off by a more general hypothesis judged with it.
(: hm-unscreened (-[semidet]-> Atom Number Number Bool HmReviewed Bool))
(= (hm-unscreened $rule $s $n $unscreened (hm-reviewed $_name $antecedent $consequent $_born $truth))
   (if $unscreened
      (if (let $general (Implication $antecedent $consequent) (hypothesis-generalizes? $general $rule))
         (if (< (confidence-to-count (hm-confidence $truth)) (hm-min-samples)) true
            (hm-differs? $s (hm-strength $truth) $n))
         true)
      false))

;; A dropped hypothesis leaves the live set and its rules leave the rule
;; indexes, so no later search applies it; what it derived stays in the
;; skeleton. It is never proposed again.
(: hm-drop! (-[det]-> KB Atom Atom Atom))
(= (hm-drop! $kb $name $consequent)
   (let* (($phash (hm-pattern-hash $kb $consequent))
          ($_live (remove-data-rows! &hm_live (quote ($phash $kb $_stored $name $_antecedent $_born))))
          ($_rules (withdraw-named-rules! (brand Proof $name))))
      ()))

;; Reviews the live hypotheses that apply to `$goal` (hm-applies?), each by
;; its own query of `$steps`. Returns
;; one (hypothesis name implication truth kept|dropped) per hypothesis
;; reviewed.
(: review-hypotheses (-[nondet]-> Number KB Atom Atom))
(= (review-hypotheses $steps $kb $goal)
   (let* (($live (collapse (match &hm_live ($_phash $kb $consequent $name $antecedent $born)
                    (if (hm-applies? $kb (Implication $antecedent $consequent) $goal)
                       (hm-reviewed $name $antecedent $consequent $born no-evidence)
                       (empty)))))
          ($reviewed (map-semidet (hm-review-one $steps $kb) $live))
          ($verdict (superpose $reviewed))
          ((hm-reviewed $name $antecedent $consequent $born $truth) $verdict)
          ($kept (hm-keep? $kb $reviewed $verdict))
          ($_dropped (if $kept () (hm-drop! $kb $name $consequent))))
      (hypothesis $name (Implication $antecedent $consequent) $truth (if $kept kept dropped))))
