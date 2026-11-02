;; Hypothesis mining (docs/metta/hypothesis_rules.md, "Mining hypotheses").
;;
;; An opt-in KB proposes its own hypotheses from the true facts added to it
;; whose predicates have a declared place in time (set-predicate-time): an
;; added fact is related to the recent true facts sharing a constant with it
;; at its time point or at the previous or next one (set-time-link), and the
;; time each refers to orders them, never the order they arrive in: causes
;; precede effects, and within a time point the declared layers order them.
;; A pair is proposed at once, a single once it recurs where no pair explains
;; it. A hypothesis is a refined rule with a weak prior, which the data then
;; confirms or rejects. Off, a fact costs one lookup of the KB's setting. On,
;; it costs a bounded number of index lookups and at most `max-new` new
;; rules, so adding stays constant time. Reviewing and dropping hypotheses is
;; the review's work (hypothesis_review.metta).

(: hm-screen-changed! (-[det]-> Number SkeletonKey Atom))
(= (hm-screen-changed! $hash $key)
   (collapse (once (match &hm_screened ($hash $kb $stored $_name $_rule)
      (if (=alpha $stored $key)
         (if (space-row-present? &hm_screen_dirty ($hash $kb $key)) ()
            (add-atom &hm_screen_dirty ($hash $kb $key)))
         (empty))))))

(: hm-window (-[det]-> Number))
(= (hm-window) 24)

(: set-hypothesis-mining (-[det]-> KB Number Number Bool))
(= (set-hypothesis-mining $kb $max-new $max-live)
   (let* (($_old (remove-data-rows! &hypothesis_mining (quote ($kb $_new $_live))))
          ($on (> $max-new 0))
          ($_set (if $on (let $_row (add-atom &hypothesis_mining ($kb $max-new $max-live)) (set-rule-refinement $kb true)) false)))
      $on))

;; `($link $earlier $later)` facts say that time point $earlier immediately
;; precedes $later.
(: set-time-link (-[det]-> KB Atom Bool))
(= (set-time-link $kb $link)
   (let* (($_old (remove-data-rows! &hm_link (quote ($kb $_link))))
          ($_row (add-atom &hm_link ($kb $link))))
      true))

;; --- Outcomes of consequent patterns ---------------------------------------

(: hm-pattern-hash (-[det]-> KB Atom Number))
(= (hm-pattern-hash $kb $pattern) (index-hash (quote ($kb $pattern))))

;; A pattern's count, 0 before its first hypothesis.
(: hm-outcomes (-[det]-> KB Atom Number))
(= (hm-outcomes $kb $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (chainer-first-or 0 (collapse (once (match &hm_outcomes ($hash $kb $stored $count)
         (if (=alpha $stored $pattern) $count (empty))))))))

(: hm-count-outcome! (-[det]-> KB Atom Atom))
(= (hm-count-outcome! $kb $pattern)
   (let $hash (hm-pattern-hash $kb $pattern)
      (collapse (once (match &hm_outcomes ($hash $kb $stored $count)
         (if (=alpha $stored $pattern)
            (let* (($_old (remove-atom &hm_outcomes ($hash $kb $stored $count)))
                   ($count1 (+ $count 1)))
               (add-atom &hm_outcomes ($hash $kb $stored $count1)))
            (empty)))))))

;; --- Recent facts by constant ----------------------------------------------

(: hm-record! (-[det]-> KB Atom Number Atom Atom Atom Atom))
(= (hm-record! $kb $type $seq $time $layer $value)
   (let* (($hash (hm-pattern-hash $kb $value))
          ($count (chainer-first-or 0 (collapse (once (match &hm_value_count ($hash $kb $value $n) $n)))))
          ($_count (remove-data-rows! &hm_value_count (quote ($hash $kb $value $_old))))
          ($next (+ $count 1))
          ($_new-count (add-atom &hm_value_count ($hash $kb $value $next)))
          ($_row (add-atom &hm_recent ($hash $kb $value $count $seq $type $time $layer)))
          ($expired (- $count (hm-window))))
      (remove-data-rows! &hm_recent (quote ($hash $kb $value $expired $_seq $_stmt $_time $_layer)))))

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

;; A candidate is proposed unless it was proposed before, its consequent's
;; predicate is positive-only (nothing could refute it), or its consequent
;; pattern has no room: a pair at once (the most specific candidates), a
;; single when it recurs. One through a link is not proposed once a live
;; hypothesis concludes its consequent from its own time point: the present
;; causes first, the past only for what they leave unexplained (in SupplyNet
;; a route stays blocked because its region's storm persists, and the
;; route's own persistence would count the storm's twice). It is proposed as an STV
;; when a conjunct of its antecedent stores only true instances (no instance
;; where it fails could teach a CTV's negative branch), otherwise as a CTV,
;; both at strength 0.5 with the evidence of a hundredth of an observation,
;; so the first samples decide whatever k is. Its instance fold reads every
;; earlier instance, so a single proposed when it recurs loses none.
(: hm-consider! (-[det]-> KB Number Number (Number (List AnnotatedStatement)) (Atom Atom Atom) (Number (List AnnotatedStatement))))
(= (hm-consider! $kb $max-new $max-live ($count $picked) ($antecedent $consequent $sighting))
   (let* (($rule (Implication (brand Statement $antecedent) (brand Statement $consequent)))
          ($hash (index-hash (quote ($kb $rule))))
          ($phash (hm-pattern-hash $kb $consequent))
          ;; A failure's sightings recur only with failures' (hm-mine!).
          ($seen-rule (case $sighting (((failed $_instance $_context) (failed $rule)) ($_other $rule))))
          ($seen-hash (index-hash (quote ($kb $seen-rule)))))
      (if (space-row-present? &hm_tried ($hash $kb $rule)) ($count $picked)
         (if (positive-only-pattern? $kb (brand Statement $consequent)) ($count $picked)
            (if (case $sighting (
                   (none true)
                   ((failed $instance $context) (hm-recurs? $kb $seen-hash $seen-rule (the Number $instance) $context))
                   (($instance $context) (hm-recurs? $kb $seen-hash $seen-rule (the Number $instance) $context))))
               (if (>= $count $max-new) ($count $picked)
                  (if (let $live (collapse (match &hm_live ($phash $kb $stored $_name $live-antecedent $_born)
                                              (if (=alpha $stored $consequent) $live-antecedent (empty))))
                         (if (>= (size-atom $live) $max-live) true
                            (if (hm-across? $kb $antecedent) (fold-flat (hm-explained? $kb) false (the (List Atom) $live)) false)))
                     ($count $picked)
                     (let* (($_unseen (remove-data-rows! &hm_seen (quote ($seen-hash $kb $seen-rule $_first $_seen))))
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
                        ($next (cons (: (brand Proof $name) $rule $tv) $picked)))))
               ($count $picked))))))

;; Whether an antecedent reads the previous time point through a link.
(: hm-across? (-[det]-> KB Atom Bool))
(= (hm-across? $kb $antecedent)
   (case $antecedent (
      ((And ($link $_earlier $_later) $_fact) (space-row-present? &hm_link ($kb $link)))
      ($_other false))))

;; Whether a live hypothesis concludes a pattern from its own time point.
(: hm-explained? (-[det]-> KB Bool Atom Bool))
(= (hm-explained? $kb $explained $antecedent)
   (if $explained true (not (hm-across? $kb $antecedent))))

;; The fact is counted in the outcomes of the consequent patterns it is an
;; instance of. Its features are the recent true facts sharing a constant
;; with it at its time point and at the ones its links make the previous and
;; the next. A true fact is recorded and related to them in singles and
;; pairs, either way round as time and layer order them, the recurring
;; singles first. A false one is concluded from them where a live hypothesis
;; predicted it, in the pairs that contain a fact the prediction read, which
;; can learn where it fails; and, as a true fact is (a pair at once, a single
;; when it recurs among failures), where no live hypothesis concluded the
;; candidate's consequent before, so a statement that never holds (an
;; operation that never succeeds) gets hypotheses that learn its failure.
;; Once one concludes it, its other failures say nothing more about what
;; makes it hold. At most max-new are proposed.
;; Candidate proposal changes neither observation counts nor the recent window:
;; a late link joins existing observations without ingesting them a second time.
(datatype HmMiningLimits (hm-limits Number Number))

(datatype HmObservation (hm-observation Atom Number Atom Atom))
(: hm-propose-observation! (-[det]-> KB HmMiningLimits (Number (List AnnotatedStatement)) HmObservation (Number (List AnnotatedStatement))))

(= (hm-propose-observation! $kb (hm-limits $max-new $max-live) $state (hm-observation $type $s $layer $features))
   (if (> $s 0.5)
      (fold-flat (hm-consider! $kb $max-new $max-live) $state (hypothesis-candidates $type $layer $features))
         (let* (($patterns (hypothesis-patterns $type))
                ($live (collapse (let* (($pattern (superpose $patterns))
                                        ($phash (hm-pattern-hash $kb $pattern)))
                                     (match &hm_live ($phash $kb $consequent $_name $antecedent $_born)
                                        (if (=alpha $consequent $pattern) ($antecedent $consequent) (empty))))))
                ($exceptions (fold-flat (hm-consider! $kb $max-new $max-live) $state (hypothesis-exception-pairs $type $layer $features $live)))
                ($result (fold-flat (hm-consider! $kb $max-new $max-live) $exceptions (hypothesis-failure-candidates $type $layer $features $live))))
            $result)))

(: hm-mine! (-[det]-> KB Atom Number Atom Atom HmMiningLimits (List AnnotatedStatement)))
(= (hm-mine! $kb $type $s $time $layer $setting)
   (let* (($patterns (hypothesis-patterns $type))
          ($_counted (collapse (let $pattern (superpose $patterns) (hm-count-outcome! $kb $pattern))))
          ($constants (hypothesis-constants $type))
          ($rows (collapse (let* (($value (superpose $constants))
                                  ($hash (hm-pattern-hash $kb $value)))
                              (match &hm_recent ($hash $kb $value $_count $seq $stmt $t $l) ($seq $stmt $t $l)))))
          ($links (collapse (match &hm_links ($time $kb $link) $link)))
          ($features (hypothesis-features $type $time $rows $links (hm-window)))
          ($period-hash (hm-pattern-hash $kb $time))
          ($seq (next-search-id hm_seq))
          ($_horizon
             (if (space-row-present? &hm_period ($period-hash $kb $time $_seq $_fact $_truth $_layer)) ()
                (let* (($count (chainer-first-or 0 (collapse (once (match &hm_period_count ($kb $n) $n)))))
                       ($_period-count (remove-data-rows! &hm_period_count (quote ($kb $_old))))
                       ($next-period (+ $count 1))
                       ($_next (add-atom &hm_period_count ($kb $next-period)))
                       ($_new-order (add-atom &hm_period_order ($count $kb $time $period-hash)))
                       ($expired (- $count (hm-window)))
                       ($_expired (collapse (match &hm_period_order ($expired $kb $old-time $old-hash)
                          (let* (($_rows (remove-data-rows! &hm_period (quote ($old-hash $kb $old-time $_seq $_fact $_truth $_layer))))
                                 ($_old-order (remove-atom &hm_period_order ($expired $kb $old-time $old-hash)))) ())))))
                   ())))
          ($_old-period (remove-data-rows! &hm_period (quote ($period-hash $kb $time $_seq $type $_s $_l))))
          ($_period (add-atom &hm_period ($period-hash $kb $time $seq $type $s $layer)))
          ($_recorded (if (> $s 0.5)
                         (collapse (let $constant (superpose $constants) (hm-record! $kb $type $seq $time $layer $constant)))
                         ())))
      (let ($_proposed $picked) (hm-propose-observation! $kb $setting (0 ()) (hm-observation $type $s $layer $features))
         $picked)))

(: hm-observe! (-[det]-> KB AnnotatedStatement (List AnnotatedStatement)))
(= (hm-observe! $kb $stmt)
   (case (collapse (once (match &hypothesis_mining ($kb $max-new $max-live) (hm-limits $max-new $max-live)))) (
      (() ())
      ((cons $setting $_rest)
         (case $stmt (
            ((: $_prf $type (STV $s $_c))
               (case (hypothesis-place $kb $type) (
                  (($time $layer) (hm-mine! $kb $type $s $time $layer $setting))
                  (() (case $type (
                     (($link $earlier $later)
                        (if (and (> $s 0.5) (space-row-present? &hm_link ($kb $link)))
                           (if (space-row-present? &hm_links (data $earlier $kb $type)) ()
                           (let* (($_e (add-atom &hm_links ($earlier $kb $type)))
                                  ($_l (add-atom &hm_links ($later $kb $type)))
                                  ($ends (collapse (let* (($end (superpose ($earlier $later)))
                                                          ($end-hash (hm-pattern-hash $kb $end)))
                                             (match &hm_period ($end-hash $kb $end $seq $fact $truth $fact-layer) (data $seq $end $fact $truth $fact-layer)))))
                                  ($observations (hypothesis-link-observations $type $ends (hm-window)))
                                  (($_count $picked) (fold-flat (hm-propose-observation! $kb $setting) (0 ()) (the (List HmObservation) $observations))))
                              $picked))
                           ()))
                     ($_other ())))))))
            ($_other ())))))))
