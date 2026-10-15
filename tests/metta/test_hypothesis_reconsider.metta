!(import! &self ../../pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 1)

;; A variance floor must not move the null mean: large, equally observed
;; general and specific rules with the same rate are still indistinguishable.
!(test (hm-differs? 1 1 1000) false)
!(test (hm-differs? 0 0 1000) false)
!(test (hm-differs? 0.999 0.999 1000) false)
!(test (hm-differs? 0.999 0.5 1000) true)

;; A genuinely screened pair can return after the single's prediction fails.
;; Both rules first see only successes; then F1 alone has failures. Every
;; F0 AND F1 observation is still true. Positive-only features make these STVs.
!(set-rule-change-hazard recoverKb 0)
!(set-positive-only-predicate recoverKb F0)
!(set-positive-only-predicate recoverKb F1)
!(set-hypothesis-mining recoverKb 2 2)
!(set-predicate-time recoverKb F0 1 0)
!(set-predicate-time recoverKb F1 1 0)
!(set-predicate-time recoverKb T 1 1)

(: recover-case! (-[det]-> KB (Number Number Number) Atom))
(= (recover-case! $kb ($i $a $b))
   (let* (($_a (if (== $a 1) (collapse (compileadd $kb (: (f0 $i) (F0 $i) (STV 1 1)))) ()))
          ($_f1 (collapse (compileadd $kb (: (f1 $i) (F1 $i) (STV 1 1)))))
          ($_t (collapse (compileadd $kb (: (t $i) (T $i) (STV $b 1)))))) ()))

(: recover-live (-[det]-> Number))
(= (recover-live) (size-atom (collapse (match &hm_live ($_h recoverKb $_c $_name $_a $_born) true))))
(: recover-pair? (-[det]-> Bool))
(= (recover-pair?)
   (not (== (collapse (match &hm_live ($_h recoverKb $_c $_name $a $_born)
      (if (=alpha $a (And (F0 $t) (F1 $t))) true (empty)))) ())))

!(map-flat (recover-case! recoverKb) ((1 1 1) (2 1 1) (3 1 1) (4 1 1) (5 1 1) (6 1 1) (7 1 1) (8 1 1) (9 0 1) (10 0 1)))
!(test (recover-live) 2)
!(test (collapse (let (hypothesis $_name (Implication $a $_c) $_tv $status) (review-hypotheses 100 recoverKb $goal)
   (if (=alpha $a (And (F0 $t) (F1 $t))) $status (empty)))) (dropped))
!(test (recover-pair?) false)
!(test (size-atom (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule) true))) 1)

;; An unrelated change and repeated reviews do not revisit the screen.
!(compileadd recoverKb (: unrelated Unrelated (STV 1 1)))
!(collapse (query 20 recoverKb (: $p Unrelated $tv)))
!(test (collapse (match &hm_screen_dirty ($_h recoverKb $_key) true)) ())
!(collapse (review-hypotheses 0 recoverKb $goal))
!(collapse (review-hypotheses 0 recoverKb $goal))
!(test (recover-pair?) false)
!(test (recover-live) 1)

;; A small change that still screens the current pair leaves it dropped.
!(recover-case! recoverKb (101 0 1))
!(collapse (review-hypotheses 0 recoverKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule) true))) 1)
!(test (recover-pair?) false)

;; Current folds show that the degraded single no longer screens the pair. Reconsideration clears only
;; the tried marker. It never allocates a live rule or bypasses capacity.
!(set-hypothesis-mining recoverKb 2 1)
!(map-flat (recover-case! recoverKb) ((11 0 0) (12 0 0) (13 0 0) (14 0 0) (15 0 0) (16 0 0) (17 0 0) (18 0 0) (19 0 0) (20 0 0) (102 0 0)))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $_status) (review-hypotheses 0 recoverKb $goal)
   (if (=alpha $a (F1 $t)) ((> (the Number $s) 0.49) (< (the Number $s) 0.51)) (empty)))) ((true true)))
!(test (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule) true)) ())
!(recover-case! recoverKb (21 1 1))
!(test (recover-live) 1)
!(test (recover-pair?) false)
!(set-hypothesis-mining recoverKb 2 2)
!(recover-case! recoverKb (22 1 1))
!(test (recover-live) 2)
!(test (recover-pair?) true)
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $status) (review-hypotheses 100 recoverKb $goal)
   (if (=alpha $a (And (F0 $t) (F1 $t))) ((> (the Number $s) 0.99) $status) (empty)))) ((true kept)))
!(recover-case! recoverKb (23 1 1))
!(test (recover-live) 2)

;; Withdrawal also invalidates a screen, even while its cached truth survives.
!(set-rule-change-hazard withdrawKb 0)
!(set-positive-only-predicate withdrawKb F0)
!(set-positive-only-predicate withdrawKb F1)
!(set-hypothesis-mining withdrawKb 2 2)
!(set-predicate-time withdrawKb F0 1 0)
!(set-predicate-time withdrawKb F1 1 0)
!(set-predicate-time withdrawKb T 1 1)
!(map-flat (recover-case! withdrawKb) ((1 1 1) (2 1 1) (3 1 1) (4 1 1) (5 1 1) (6 1 1) (7 1 1) (8 1 1) (9 0 1) (10 0 1)))
!(collapse (review-hypotheses 100 withdrawKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule) true))) 1)
!(collapse (match &hm_live ($_h withdrawKb $c $name $a $_born)
   (if (=alpha $a (F1 $t)) (hm-drop! withdrawKb $name $c) (empty))))
!(collapse (review-hypotheses 0 withdrawKb $goal))
!(test (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule) true)) ())
!(recover-case! withdrawKb (11 1 1))
!(test (size-atom (collapse (match &hm_live ($_h withdrawKb $_c $_name $a $_born)
   (if (=alpha $a (And (F0 $t) (F1 $t))) true (empty))))) 1)

;; Real subset counts: the pair has four successes in six cases, the single
;; five in eight. Later the pair strengthens while the single moves .625 to
;; .5, less than its old SE sqrt(.625*.375/8) = .171. A frozen-SE trigger
;; never wakes it; current folds show that it is now distinguishable.
!(set-rule-change-hazard currentKb 0)
!(set-positive-only-predicate currentKb F0)
!(set-positive-only-predicate currentKb F1)
!(set-hypothesis-mining currentKb 2 2)
!(set-predicate-time currentKb F0 1 0)
!(set-predicate-time currentKb F1 1 0)
!(set-predicate-time currentKb T 1 1)
!(map-flat (recover-case! currentKb) ((1 1 1) (2 1 1) (3 1 0) (4 1 1) (5 1 0) (6 1 1) (7 0 1) (8 0 0)))
!(collapse (review-hypotheses 100 currentKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h currentKb $_key $_name $_rule) true))) 1)
!(set-hypothesis-mining currentKb 2 1)
!(map-flat (recover-case! currentKb)
   ((9 1 1) (10 1 1) (11 1 1) (12 1 1) (13 1 1) (14 1 1) (15 1 1) (16 1 1) (17 1 1) (18 1 1)
    (19 1 1) (20 1 1) (21 1 1) (22 1 1) (23 1 1) (24 1 1) (25 1 1) (26 1 1) (27 1 1) (28 1 1)
    (29 0 0) (30 0 0) (31 0 0) (32 0 0) (33 0 0) (34 0 0) (35 0 0) (36 0 0) (37 0 0) (38 0 0)
    (39 0 0) (40 0 0) (41 0 0) (42 0 0) (43 0 0) (44 0 0) (45 0 0) (46 0 0) (47 0 0) (48 0 0) (49 0 0) (50 0 0)))
!(collapse (review-hypotheses 0 currentKb $goal))
!(test (collapse (match &hm_screened ($_h currentKb $_key $_name $_rule) true)) ())
!(set-hypothesis-mining currentKb 2 2)
!(recover-case! currentKb (51 1 1))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $status) (review-hypotheses 100 currentKb $goal)
   (if (=alpha $a (And (F0 $t) (F1 $t))) ((> (the Number $s) 0.9) $status) (empty)))) ((true kept)))
