;; Hypothesis mining (docs/metta/hypothesis_rules.md, "Mining hypotheses").
;;
;; An opt-in KB proposes its own hypotheses: each added fact is paired with
;; the recent facts that share a constant with it, and the pairings become
;; refined rules with a weak prior, which the data then confirms or rejects.
;; Off, a fact costs one lookup of the KB's setting. On, it costs a bounded
;; number of index lookups and at most `max-new` new rules, so adding stays
;; constant time. Reviewing and dropping hypotheses is the review's work
;; (hypothesis_review.metta).

;; kb -> the new hypotheses one fact may add, and the live ones a consequent
;; pattern may have.
(: &hypothesis_mining (SpaceOf (KB Number Number)))
!(bind! &hypothesis_mining (new-space))

;; A fact's features are read from the last `hm-window` facts recorded for
;; each of its constants, newest first: value hash -> kb, value, sequence
;; number, statement, with the value's count of recorded facts beside.
(: &hm_recent (SpaceOf (Number KB Atom Number Atom)))
!(bind! &hm_recent (new-space))
(: &hm_value_count (SpaceOf (Number KB Atom Number)))
!(bind! &hm_value_count (new-space))

;; Pattern hash -> kb, consequent pattern, facts of it seen since its first
;; hypothesis and their summed strength: its rate, and the opportunities a
;; hypothesis had since it was born.
(: &hm_outcomes (SpaceOf (Number KB Atom Number Number)))
!(bind! &hm_outcomes (new-space))

;; Consequent hash -> kb, consequent, rule name, antecedent, the
;; consequent's count when it was born. Only live hypotheses.
(: &hm_live (SpaceOf (Number KB Atom Atom Atom Number)))
!(bind! &hm_live (new-space))

;; Implication hash -> kb, implication: every hypothesis ever proposed, so a
;; dropped one is not proposed again.
(: &hm_tried (SpaceOf (Number KB Atom)))
!(bind! &hm_tried (new-space))

(: hm-window (-[det]-> Number))
(= (hm-window) 24)

(: set-hypothesis-mining (-[det]-> KB Number Number Bool))
(= (set-hypothesis-mining $kb $max-new $max-live)
   (let* (($_old (remove-data-rows! &hypothesis_mining (quote ($kb $_new $_live))))
          ($on (> $max-new 0))
          ($_set (if $on (let $_row (add-atom &hypothesis_mining ($kb $max-new $max-live)) (set-rule-refinement $kb true)) false)))
      $on))

;; A statement whose predicate stores only true instances is no consequent:
;; nothing could refute a hypothesis concluding it.
(: hm-consequent? (-[det]-> KB Atom Bool))
(= (hm-consequent? $kb $type)
   (not (space-row-present? &positive_only_predicates ($kb (car-atom $type)))))

;; --- Outcomes of consequent patterns ---------------------------------------

(: hm-pattern-hash (-[det]-> KB Atom Number))
(= (hm-pattern-hash $kb $pattern) (index-hash (quote ($kb $pattern))))

;; A pattern's (count strength-sum), (0 0) before its first hypothesis.
(: hm-outcomes (-[det]-> KB Atom (Number Number)))
(= (hm-outcomes $kb $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (case (collapse (once (match &hm_outcomes ($hash $kb $stored $count $sum)
               (if (=alpha $stored $pattern) ($count $sum) (empty))))) (
         ((cons $outcome $_rest) $outcome)
         (() (0 0))))))

(: HmOutcome Type)
(: hm-outcome (-[det]-> Atom Number Number HmOutcome))

(: hm-count-outcome! (-[det]-> KB Number Atom Atom))
(= (hm-count-outcome! $kb $s $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (case (collapse (once (match &hm_outcomes ($hash $kb $stored $count $sum)
               (if (=alpha $stored $pattern) (hm-outcome $stored $count $sum) (empty))))) (
         ((cons (hm-outcome $stored $count $sum) $_rest)
            (let* (($_old (remove-atom &hm_outcomes ($hash $kb $stored $count $sum)))
                   ($count1 (+ $count 1))
                   ($sum1 (+ $sum $s)))
               (add-atom &hm_outcomes ($hash $kb $stored $count1 $sum1))))
         (() ())))))

;; --- Recent facts by constant ----------------------------------------------

(: hm-value-hash (-[det]-> KB Atom Number))
(= (hm-value-hash $kb $value) (index-hash (quote ($kb $value))))

;; The facts recorded for the statement's constants, newest first, without
;; the statement's predicate, at most hm-window.
(: hm-features (-[det]-> KB Atom (List Atom)))
(= (hm-features $kb $type)
   (let* (($values (hypothesis-constants $type))
          ($rows (collapse (let* (($value (superpose $values))
                                  ($hash (hm-value-hash $kb $value)))
                              (match &hm_recent ($hash $kb $value $seq $stmt) ($seq $stmt))))))
      (hypothesis-features $type $rows (hm-window))))

(: hm-record! (-[det]-> KB Atom Atom Atom))
(= (hm-record! $kb $type $value)
   (let* (($hash (hm-value-hash $kb $value))
          ($count (case (collapse (once (match &hm_value_count ($hash $kb $value $n) $n))) (
                     ((cons $n $_rest) $n)
                     (() 0))))
          ($_count (remove-data-rows! &hm_value_count (quote ($hash $kb $value $_old))))
          ($next (+ $count 1))
          ($_new-count (add-atom &hm_value_count ($hash $kb $value $next)))
          ($_row (add-atom &hm_recent ($hash $kb $value $count $type)))
          ($expired (- $count (hm-window))))
      (remove-data-rows! &hm_recent (quote ($hash $kb $value $expired $_stmt)))))

;; --- Proposing --------------------------------------------------------------

;; A candidate never proposed before, whose consequent pattern has room, is
;; proposed: as an STV when a conjunct of its antecedent stores only true
;; instances (no instance where it fails could teach a CTV's negative
;; branch), otherwise as a CTV, both at strength 0.5 with the evidence of a
;; hundredth of an observation, so the first samples decide whatever k is.
(: hm-consider! (-[det]-> KB Number Number (Number (List Atom)) (Atom Atom) (Number (List Atom))))
(= (hm-consider! $kb $max-new $max-live ($count $picked) ($antecedent $consequent))
   (if (>= $count $max-new) ($count $picked)
      (let* (($rule (Implication $antecedent $consequent))
             ($hash (index-hash (quote ($kb $rule))))
             ($phash (hm-pattern-hash $kb $consequent)))
         (if (space-row-present? &hm_tried ($hash $kb $rule)) ($count $picked)
            (if (>= (size-atom (collapse (match &hm_live ($phash $kb $stored $_name $_antecedent $_born)
                                          (if (=alpha $stored $consequent) true (empty)))))
                    $max-live)
               ($count $picked)
               (let* (($_tried (add-atom &hm_tried ($hash $kb $rule)))
                      ($_outcomes (if (space-row-present? &hm_outcomes ($phash $kb $consequent $_c $_s)) ()
                                     (add-atom &hm_outcomes ($phash $kb $consequent 0 0))))
                      (($born $_sum) (hm-outcomes $kb $consequent))
                      ($name (hypothesis-name (next-search-id hm_name)))
                      ($_live (add-atom &hm_live ($phash $kb $consequent $name $antecedent $born)))
                      ($c (count-confidence 0.01))
                      ($tv (if (positive-only-pattern? $kb (brand Statement $antecedent))
                              (STV 0.5 $c)
                              (CTV (STV 0.5 $c) (STV 0.5 $c))))
                      ($next (+ $count 1)))
                  ($next (cons (: $name $rule $tv) $picked))))))))

;; A candidate concluding the fact from one feature, or a feature from the
;; fact.
(: hm-single (-[nondet]-> KB Atom (List Atom) (Atom Atom)))
(= (hm-single $kb $type $features)
   (if (hm-consequent? $kb $type)
      (let $singles (hypothesis-singles $type $features) (superpose $singles))
      (empty)))
(= (hm-single $kb $type $features)
   (let* (($feature (superpose $features))
          ($singles (hypothesis-singles $feature ($type))))
      (if (hm-consequent? $kb $feature) (superpose $singles) (empty))))

;; The candidates proposed from a scan, at most max-new.
(: hm-propose! (-[det]-> KB Number Number (List (Atom Atom)) (List AnnotatedStatement)))
(= (hm-propose! $kb $max-new $max-live $scan)
   (let ($_count $picked) (fold-flat (hm-consider! $kb $max-new $max-live) (0 ()) $scan) $picked))

;; A ground statement of a predicate, with a constant argument to join on.
(: hm-minable? (-[det]-> Atom Bool))
(= (hm-minable? $type)
   (if (is-expr $type)
      (if (== (extract-vars $type) ())
         (if (head-is-member? $type (And Or Not Implication BiImplication Exists Compute RuleTruth Inheritance Member)) false
            (not (== (hypothesis-constants $type) ())))
         false)
      false))

;; The fact is counted in the outcomes of the consequent patterns it is an
;; instance of, read against the recent facts sharing a constant with it, and
;; recorded. Its candidates conclude it from one feature, or a feature from
;; it, and then from a pair of features: every single is examined, and of the
;; pairs at most eight per new hypothesis allowed, starting at a different
;; pair each time.
(: hm-mine! (-[det]-> KB Atom Number (Number Number) (List AnnotatedStatement)))
(= (hm-mine! $kb $type $s ($max-new $max-live))
   (let* (($patterns (hypothesis-patterns $type))
          ($_counted (collapse (let $pattern (superpose $patterns) (hm-count-outcome! $kb $s $pattern))))
          ($features (hm-features $kb $type))
          ($constants (hypothesis-constants $type))
          ($_recorded (collapse (let $value (superpose $constants) (hm-record! $kb $type $value))))
          ($singles (collapse (hm-single $kb $type $features)))
          ($pairs (hypothesis-pairs $type $features))
          ($scan (hypothesis-scan (next-search-id hm_offset) (if (hm-consequent? $kb $type) (* 8 $max-new) 0) $pairs)))
      (hm-propose! $kb $max-new $max-live (append-flat $singles $scan))))

;; The hypotheses an added statement proposes, to be compiled by compileadd.
(: hm-observe! (-[det]-> KB AnnotatedStatement (List AnnotatedStatement)))
(= (hm-observe! $kb $stmt)
   (case (collapse (once (match &hypothesis_mining ($kb $max-new $max-live) ($max-new $max-live)))) (
      (() ())
      ((cons $setting $_rest)
         (case $stmt (
            ((: $_prf $type (STV $s $_c))
               (if (hm-minable? $type) (hm-mine! $kb $type $s $setting) ()))
            ($_other ())))))))
