;; Reviewing mined hypotheses (docs/metta/hypothesis_rules.md, "Mining
;; hypotheses"). A review reads the live hypotheses' truths, which the chainer
;; keeps current as their instances arrive ("Instance tallies"), and drops the
;; ones that do not predict.

;; A hypothesis is judged once its truth rests on hm-min-samples
;; observations: it stays when its strength differs, by more than hm-z
;; standard errors, from the consequent's probability without its antecedent
;; (hm-informative?) and from the strength of every more general live
;; hypothesis judged in the same review.
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

;; A live hypothesis's truth goal.
(: hm-truth-goal (-[det]-> HmReviewed AnnotatedStatement))
(= (hm-truth-goal (hm-reviewed $_name $antecedent $consequent $_born $_truth))
   (: $prf (RuleTruth (Implication $antecedent $consequent)) $tv))

(: hm-confidence (-[det]-> Atom Number))
(= (hm-confidence $tv) (case $tv (((STV $_s $c) $c) ((CTV (STV $_s1 $c1) $_neg) $c1) ($_none 0))))

(: hm-strength (-[det]-> Atom Number))
(= (hm-strength $tv) (case $tv (((STV $s $_c) $s) ((CTV (STV $s1 $_c1) $_neg) $s1) ($_none 0.5))))

;; |s - p| beyond hm-z standard errors of p over n observations. Clamp
;; only its variance estimate, never the comparison center: identical rates
;; at 0 or 1 must remain identical even after many observations.
(: hm-differs? (-[det]-> Number Number Number Bool))
(= (hm-differs? $s $p $n)
   (let $q (min 0.95 (max 0.05 $p))
      (> (abs-math (- $s $p)) (* (hm-z) (sqrt-math (/ (* $q (- 1 $q)) $n))))))

(: hm-decision (-[semidet]-> KB (List HmReviewed) HmReviewed Atom))
(= (hm-decision $kb $reviewed (hm-reviewed $_name $antecedent $consequent $born $truth))
   (let* (($n (confidence-to-count (hm-confidence $truth)))
          ($s (hm-strength $truth))
          ($rule (Implication $antecedent $consequent)))
      (if (< $n (hm-min-samples))
         (< (- (hm-outcomes $kb $consequent) $born) (hm-max-opportunities))
         (if (hm-informative? $truth $s $n)
            (fold-semidet (hm-screen $kb $rule $s $n) true $reviewed)
            false))))

;; Whether the strength differs from the consequent's probability without
;; the antecedent: a CTV's negative branch, once an instance where the
;; antecedent fails taught it. Without one there is no reference: the
;; consequent's observed rate is biased by which instances get observed (a
;; matching-to-sample agent's rewards come mostly from the contexts it
;; believes in), and a tally that started late reads near 0.5.
(: hm-informative? (-[det]-> Atom Number Number Bool))
(= (hm-informative? $truth $s $n)
   (case $truth (
      ((CTV $_pos (STV $s0 $c0)) (if (>= (confidence-to-count $c0) 1) (hm-differs? $s $s0 $n) true))
      ($_stv true))))

;; Screening compares a specific rule with a live syntactic generalization.
;; Return one screening reason.
(: hm-screen (-[det]-> KB Atom Number Number Atom HmReviewed Atom))
(= (hm-screen $kb $rule $s $n $decision (hm-reviewed $name $antecedent $consequent $_born $truth))
   (if (== $decision true)
      (let* (($general (Implication $antecedent $consequent))
             ($phash (hm-pattern-hash $kb $consequent)))
         (if (if (hypothesis-generalizes? $general $rule)
                 (space-row-present? &hm_live ($phash $kb $_stored $name $_antecedent $_born)) false)
            (let $p (hm-strength $truth) (if (hm-differs? $s $p $n) true (screen $general)))
            true))
      $decision))

;; A dropped hypothesis leaves the live set and its rules leave the rule
;; indexes. Its durable joins and views are retired by rule identity, so no
;; later read uses them. The historical proof store stays. A screening
;; reason is registered by the review before retirement.
(: hm-drop! (-[det]-> KB Atom Atom Atom))
(= (hm-drop! $kb $name $consequent)
   (let* (($phash (hm-pattern-hash $kb $consequent))
          ($_screen (collapse (match &hm_live ($phash $kb $consequent $name $antecedent $_born)
             (let* (($key (sk-key (brand Statement (RuleTruth (Implication $antecedent $consequent))) (kbctx $kb)))
                    ($hash (index-hash $key)))
                (hm-screen-changed! $hash $key)))))
          ($_live (remove-data-rows! &hm_live (quote ($phash $kb $_stored $name $_antecedent $_born))))
          ($_unread (remove-data-rows! &hm_unread (quote ($name $kb))))
          ($_rules (withdraw-named-rules! (brand Proof $name))))
      ()))

;; Reads the truths of a group of live hypotheses in one query, with
;; `$steps` for each one no review has read yet, whose first read folds its
;; instances, and none otherwise; appended to those read before.
(: hm-read (-[det]-> Number KB (List HmReviewed) (List HmReviewed) (List HmReviewed)))
(= (hm-read $steps $kb $reviewed $group)
   (let* (($unread (hypothesis-read! $kb $group))
          ($rows (collapse
             (let (query-result $index (: $proof $type $_positive-tv))
                (query-many-refs (* $steps $unread) $kb (map-flat hm-truth-goal $group))
                ;; The review needs both learned storage branches. Public
                ;; query rows deliberately expose only their positive STV.
                (let (sk-val ($_type $_kbctx $_prf $truth) $_ev $_deps)
                   (sk-value (sk-key (brand Statement $type) (kbctx $kb)) sk-any-filter ())
                   (query-result $index (: $proof (brand Statement $type) $truth)))))))
      (append-flat $reviewed (the (List HmReviewed) (hypothesis-truths $group $rows)))))

;; Only a changed screening key causes re-reading of its dropped candidates.
;; Their retained instance folds recover current strengths and counts at no
;; expansion budget, as for live hypotheses already read. Withdrawal also
;; invalidates a screen even while its cached truth survives lazy retirement.
(: hm-reconsider! (-[det]-> KB Atom))
(= (hm-reconsider! $kb)
   (collapse (match &hm_screen_dirty ($hash $kb $key)
      (let* (($_dirty (remove-variant-row! &hm_screen_dirty (quote ($hash $kb $key))))
             ((sk-key (RuleTruth (Implication $antecedent $consequent)) $_context) $key)
             ($phash (hm-pattern-hash $kb $consequent))
             ($live (collapse (once (match &hm_live ($phash $kb $live-consequent $_live-name $live-antecedent $_born)
                (if (=alpha (Implication $live-antecedent $live-consequent) (Implication $antecedent $consequent)) true (empty))))))
             ($candidates (collapse (match &hm_screened ($hash $kb $stored $name (Implication $a $c))
                (if (=alpha $stored $key) (hm-reviewed $name $a $c 0 no-evidence) (empty)))))
             ($current (hm-read 0 $kb () (the (List HmReviewed) $candidates)))
             ($value (if (== $live ()) sk-none (sk-value $key sk-any-filter ()))))
         (collapse (let* (((hm-reviewed $name $a $c $_born $truth) (superpose $current))
                          ($n (confidence-to-count (hm-confidence $truth))))
            (if (case $value (
                   ((sk-val ($_type $_ctx $_proof $general-tv) $_ev $_deps)
                      (if (>= $n (hm-min-samples)) (hm-differs? (hm-strength $truth) (hm-strength $general-tv) $n) false))
                   ($_none true)))
               (let* (($_watch (remove-data-rows! &hm_screened (quote ($hash $kb $_stored $name $_rule))))
                      ($rule (Implication $a $c))
                      ($rhash (index-hash (quote ($kb $rule)))))
                  (remove-variant-row! &hm_tried (quote ($rhash $kb $rule))))
               ())))))))

;; Reviews the live hypotheses that apply to `$goal` (hm-applies?). Their
;; truths are read a consequent layer at a time, the lowest first: a fold
;; resolves its consequent's instances through the hypotheses concluding its
;; antecedent, whose truths are then read already. Returns one (hypothesis
;; name implication truth kept|dropped) per hypothesis reviewed.
(: review-hypotheses (-[nondet]-> Number KB Atom Atom))
(= (review-hypotheses $steps $kb $written-goal)
   (let* (($goal (member-canon $written-goal))
          ($live (collapse (match &hm_live ($_phash $kb $consequent $name $antecedent $born)
                    (if (hm-applies? $kb (Implication $antecedent $consequent) $goal)
                       (hm-reviewed $name $antecedent $consequent $born no-evidence)
                       (empty)))))
          ($groups (the (List (List HmReviewed)) (hypothesis-layers $kb $live)))
          ($reviewed (fold-flat (hm-read $steps $kb) () $groups))
          ($_reconsidered (hm-reconsider! $kb))
          ($verdict (superpose $reviewed))
          ((hm-reviewed $name $antecedent $consequent $born $truth) $verdict)
          ($decision (hm-decision $kb $reviewed $verdict))
          ($kept (== $decision true))
          ($_screen (case $decision (
             ((screen $general)
                (let* (($key (sk-key (brand Statement (RuleTruth $general)) (kbctx $kb)))
                       ($hash (index-hash $key)))
                   (add-atom &hm_screened ($hash $kb $key $name (Implication $antecedent $consequent)))))
             ($_other ()))))
          ($_dropped (if $kept () (hm-drop! $kb $name $consequent))))
      (hypothesis $name (Implication $antecedent $consequent) $truth (if $kept kept dropped))))
