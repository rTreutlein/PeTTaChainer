;; Hypothesis mining (docs/metta/hypothesis_rules.md, "Mining hypotheses").
;;
;; An opt-in KB proposes its own hypotheses: each added true fact is
;; concluded from pairs of the recent true facts that share a constant with
;; it, and from one of them once that one recurs where no pair explains it.
;; A hypothesis is a refined rule with a weak prior, which the data then
;; confirms or rejects. Off, a fact costs one lookup of the KB's setting. On,
;; it costs a bounded number of index lookups and at most `max-new` new
;; rules, so adding stays constant time. Reviewing and dropping hypotheses is
;; the review's work (hypothesis_review.metta).

;; kb -> the new hypotheses one fact may add, and the live ones a consequent
;; pattern may have.
(: &hypothesis_mining (SpaceOf (KB Number Number)))
!(bind! &hypothesis_mining (new-space))

;; A fact's features are read from the last `hm-window` true facts recorded
;; for each of its constants, newest first: value hash -> kb, value, the
;; value's count of recorded facts, global sequence number, statement, with
;; the value's count beside.
(: &hm_recent (SpaceOf (Number KB Atom Number Number Atom)))
!(bind! &hm_recent (new-space))
(: &hm_value_count (SpaceOf (Number KB Atom Number)))
!(bind! &hm_value_count (new-space))

;; Pattern hash -> kb, consequent pattern, facts of it seen since its first
;; hypothesis: the opportunities a hypothesis had since it was born.
(: &hm_outcomes (SpaceOf (Number KB Atom Number)))
!(bind! &hm_outcomes (new-space))

;; Consequent hash -> kb, consequent, rule name, antecedent, the
;; consequent's count when it was born. Only live hypotheses.
(: &hm_live (SpaceOf (Number KB Atom Atom Atom Number)))
!(bind! &hm_live (new-space))

;; Live hypotheses no review has read yet: their first read folds their
;; instances and needs budget (hypothesis_review.metta).
(: &hm_unread (SpaceOf (Atom KB)))
!(bind! &hm_unread (new-space))

;; Implication hash -> kb, implication: every hypothesis ever proposed, so a
;; dropped one is not proposed again.
(: &hm_tried (SpaceOf (Number KB Atom)))
!(bind! &hm_tried (new-space))

;; Implication hash -> kb, implication, the instance and the context of its
;; first sighting: singles seen once and not proposed yet.
(: &hm_seen (SpaceOf (Number KB Atom Number Atom)))
!(bind! &hm_seen (new-space))

(: hm-window (-[det]-> Number))
(= (hm-window) 24)

(: set-hypothesis-mining (-[det]-> KB Number Number Bool))
(= (set-hypothesis-mining $kb $max-new $max-live)
   (let* (($_old (remove-data-rows! &hypothesis_mining (quote ($kb $_new $_live))))
          ($on (> $max-new 0))
          ($_set (if $on (let $_row (add-atom &hypothesis_mining ($kb $max-new $max-live)) (set-rule-refinement $kb true)) false)))
      $on))

;; --- Outcomes of consequent patterns ---------------------------------------

(: hm-pattern-hash (-[det]-> KB Atom Number))
(= (hm-pattern-hash $kb $pattern) (index-hash (quote ($kb $pattern))))

;; A pattern's count, 0 before its first hypothesis.
(: hm-outcomes (-[det]-> KB Atom Number))
(= (hm-outcomes $kb $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (case (collapse (once (match &hm_outcomes ($hash $kb $stored $count)
               (if (=alpha $stored $pattern) $count (empty))))) (
         ((cons $count $_rest) $count)
         (() 0)))))

(: HmOutcome Type)
(: hm-outcome (-[det]-> Atom Number HmOutcome))

(: hm-count-outcome! (-[det]-> KB Atom Atom))
(= (hm-count-outcome! $kb $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (case (collapse (once (match &hm_outcomes ($hash $kb $stored $count)
               (if (=alpha $stored $pattern) (hm-outcome $stored $count) (empty))))) (
         ((cons (hm-outcome $stored $count) $_rest)
            (let* (($_old (remove-atom &hm_outcomes ($hash $kb $stored $count)))
                   ($count1 (+ $count 1)))
               (add-atom &hm_outcomes ($hash $kb $stored $count1))))
         (() ())))))

;; --- Recent facts by constant ----------------------------------------------

(: hm-value-hash (-[det]-> KB Atom Number))
(= (hm-value-hash $kb $value) (index-hash (quote ($kb $value))))

;; The true facts recorded for the statement's constants, newest first,
;; without the statement's predicate, at most hm-window.
(: hm-features (-[det]-> KB Atom (List Atom)))
(= (hm-features $kb $type)
   (let* (($values (hypothesis-constants $type))
          ($rows (collapse (let* (($value (superpose $values))
                                  ($hash (hm-value-hash $kb $value)))
                              (match &hm_recent ($hash $kb $value $_count $seq $stmt) ($seq $stmt))))))
      (hypothesis-features $type $rows (hm-window))))

(: hm-record! (-[det]-> KB Atom Number Atom Atom))
(= (hm-record! $kb $type $seq $value)
   (let* (($hash (hm-value-hash $kb $value))
          ($count (case (collapse (once (match &hm_value_count ($hash $kb $value $n) $n))) (
                     ((cons $n $_rest) $n)
                     (() 0))))
          ($_count (remove-data-rows! &hm_value_count (quote ($hash $kb $value $_old))))
          ($next (+ $count 1))
          ($_new-count (add-atom &hm_value_count ($hash $kb $value $next)))
          ($_row (add-atom &hm_recent ($hash $kb $value $count $seq $type)))
          ($expired (- $count (hm-window))))
      (remove-data-rows! &hm_recent (quote ($hash $kb $value $expired $_seq $_stmt)))))

;; --- Proposing --------------------------------------------------------------

;; Whether a single recurs: seen before at another instance and in another
;; context (its other features differ), where the pairs of its first context
;; do not explain it. A first sighting is recorded.
(: hm-recurs? (-[det]-> KB Number Atom Number Atom Bool))
(= (hm-recurs? $kb $hash $rule $instance $context)
   (case (collapse (once (match &hm_seen ($hash $kb $stored $first $seen)
            (if (=alpha $stored $rule) (not (or (== $first $instance) (== $seen $context))) (empty))))) (
      ((cons $recurs $_more) $recurs)
      (() (let $_seen (add-atom &hm_seen ($hash $kb $rule $instance $context)) false)))))

;; A candidate is proposed unless it or its reverse was proposed before, or
;; its consequent pattern has no room: a pair at once (the most specific
;; candidates), a single when it recurs. It is proposed as an STV
;; when a conjunct of its antecedent stores only true instances (no instance
;; where it fails could teach a CTV's negative branch), otherwise as a CTV,
;; both at strength 0.5 with the evidence of a hundredth of an observation,
;; so the first samples decide whatever k is. Its instance fold reads every
;; earlier instance, so a single proposed when it recurs loses none.
(: hm-consider! (-[det]-> KB Number Number Number (Number (List Atom)) (Atom Atom Atom) (Number (List Atom))))
(= (hm-consider! $kb $max-new $max-live $instance ($count $picked) ($antecedent $consequent $context))
   (let* (($rule (Implication $antecedent $consequent))
          ($hash (index-hash (quote ($kb $rule))))
          ($reverse (Implication $consequent $antecedent))
          ($phash (hm-pattern-hash $kb $consequent)))
      (if (space-row-present? &hm_tried ($hash $kb $rule)) ($count $picked)
         (if (space-row-present? &hm_tried ((index-hash (quote ($kb $reverse))) $kb $reverse)) ($count $picked)
            (if (if (== $context none) true (hm-recurs? $kb $hash $rule $instance $context))
               (if (>= $count $max-new) ($count $picked)
                  (if (>= (size-atom (collapse (match &hm_live ($phash $kb $live $_name $_antecedent $_born)
                                                (if (=alpha $live $consequent) true (empty)))))
                          $max-live)
                     ($count $picked)
                     (let* (($_unseen (remove-data-rows! &hm_seen (quote ($hash $kb $rule $_first $_seen))))
                            ($_tried (add-atom &hm_tried ($hash $kb $rule)))
                            ($_outcomes (if (space-row-present? &hm_outcomes ($phash $kb $consequent $_c)) ()
                                           (add-atom &hm_outcomes ($phash $kb $consequent 0))))
                            ($born (hm-outcomes $kb $consequent))
                            ($name (hypothesis-name (next-search-id hm_name)))
                            ($_live (add-atom &hm_live ($phash $kb $consequent $name $antecedent $born)))
                            ($_unread (add-atom &hm_unread ($name $kb)))
                            ($c (count-confidence 0.01))
                            ($tv (if (positive-only-pattern? $kb (brand Statement $antecedent))
                                    (STV 0.5 $c)
                                    (CTV (STV 0.5 $c) (STV 0.5 $c))))
                            ($next (+ $count 1)))
                        ($next (cons (: $name $rule $tv) $picked)))))
               ($count $picked))))))

;; The candidates proposed from one fact's, at most max-new.
(: hm-propose! (-[det]-> KB Number Number Number (List (Atom Atom Atom)) (List AnnotatedStatement)))
(= (hm-propose! $kb $max-new $max-live $instance $candidates)
   (let ($_count $picked) (fold-flat (hm-consider! $kb $max-new $max-live $instance) (0 ()) $candidates) $picked))

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
;; instance of. A true fact is read against the recent true facts sharing a
;; constant with it, recorded, and concluded from them in pairs and singly,
;; the recurring singles first. A false one is concluded from them only when
;; a live hypothesis predicted it: in the pairs that contain a fact the
;; prediction read, which can learn where it fails. Otherwise what co-occurs
;; with a statement that does not hold says nothing about what makes it
;; hold. Nothing concludes a
;; statement whose predicate stores only true instances: nothing could refute
;; it. At most max-new are proposed.
(: hm-mine! (-[det]-> KB Atom Number (Number Number) (List AnnotatedStatement)))
(= (hm-mine! $kb $type $s ($max-new $max-live))
   (let* (($patterns (hypothesis-patterns $type))
          ($_counted (collapse (let $pattern (superpose $patterns) (hm-count-outcome! $kb $pattern))))
          ($features (hm-features $kb $type))
          ($instance (index-hash $type))
          ($positive-only (positive-only-pattern? $kb (brand Statement $type))))
      (if (> $s 0.5)
         (let* (($seq (next-search-id hm_seq))
                ($constants (hypothesis-constants $type))
                ($_recorded (collapse (let $value (superpose $constants) (hm-record! $kb $type $seq $value)))))
            (if $positive-only ()
               (hm-propose! $kb $max-new $max-live $instance (append-flat (hypothesis-singles $type $features) (hypothesis-pairs $type $features)))))
         (if $positive-only ()
            (let $live (collapse (let* (($pattern (superpose $patterns))
                                        ($phash (hm-pattern-hash $kb $pattern)))
                                     (match &hm_live ($phash $kb $consequent $_name $antecedent $_born)
                                        (if (=alpha $consequent $pattern) ($antecedent $consequent) (empty)))))
               (hm-propose! $kb $max-new $max-live $instance (hypothesis-exception-pairs $type $features $live)))))))

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
