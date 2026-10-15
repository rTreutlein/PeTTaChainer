!(import! &self ../../pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 1)

;; A variance floor must not move the null mean: large, equally observed
;; general and specific rules with the same rate are still indistinguishable.
!(test (hm-differs? 1 1 1000) false)
!(test (hm-differs? 0 0 1000) false)
!(test (hm-differs? 0.999 0.999 1000) false)
!(test (hm-differs? 0.999 0.5 1000) true)

;; Strict equivalence power boundaries using the same band as screening.
!(test (< (hm-error-band 0.5 400) (hm-equivalence-margin)) false)
!(test (< (hm-error-band 0.5 401) (hm-equivalence-margin)) true)
!(test (< (hm-error-band 1 75) (hm-equivalence-margin)) false)
!(test (< (hm-error-band 1 77) (hm-equivalence-margin)) true)

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

;; Eighty distinct cases, reused to cross the equivalence power boundary
;; and to teach a previously screened rule's retained fold new instances.
(: recover-batch-case! (-[det]-> KB Number Number Number Number Atom))
(= (recover-batch-case! $kb $offset $a $b $index)
   (let $i (+ $offset $index) (recover-case! $kb ($i $a $b))))
(: recover-batch! (-[det]-> KB Number Number Number Atom))
(= (recover-batch! $kb $offset $a $b)
   (map-flat (recover-batch-case! $kb $offset $a $b) (1 2 3 4 5 6 7 8 9 10
      11 12 13 14 15 16 17 18 19 20
      21 22 23 24 25 26 27 28 29 30
      31 32 33 34 35 36 37 38 39 40
      41 42 43 44 45 46 47 48 49 50
      51 52 53 54 55 56 57 58 59 60
      61 62 63 64 65 66 67 68 69 70
      71 72 73 74 75 76 77 78 79 80)))

(: recover-live (-[det]-> Number))
(= (recover-live) (size-atom (collapse (match &hm_live ($_h recoverKb $_c $_name $_a $_born) true))))
(: recover-pair? (-[det]-> Bool))
(= (recover-pair?)
   (not (== (collapse (match &hm_live ($_h recoverKb $_c $_name $a $_born)
      (if (=alpha $a (And (F0 $t) (F1 $t))) true (empty)))) ())))

;; Balanced outcomes give exactly identical learned .5 rates, even with
;; the weak prior and the general's two extra observations. Neither STV
;; has a negative branch, so this isolates screening from informativeness.
!(set-rule-change-hazard equalKb 0)
!(set-positive-only-predicate equalKb F0)
!(set-positive-only-predicate equalKb F1)
!(set-hypothesis-mining equalKb 2 2)
!(set-predicate-time equalKb F0 1 0)
!(set-predicate-time equalKb F1 1 0)
!(set-predicate-time equalKb T 1 1)
!(map-flat (recover-case! equalKb) ((1 1 1) (2 1 1) (3 1 0) (4 1 0) (5 0 1) (6 0 0)))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $status) (review-hypotheses 100 equalKb $goal)
   ($s $status))) ((0.5 kept) (0.5 kept)))
!(test (collapse (match &hm_screened ($_h equalKb $_key $_name $_rule) true)) ())
;; 480 further balanced observations cross the .5-rate power boundary.
!(recover-batch! equalKb 100 1 1)
!(recover-batch! equalKb 200 1 0)
!(recover-batch! equalKb 300 1 1)
!(recover-batch! equalKb 400 1 0)
!(recover-batch! equalKb 500 1 1)
!(recover-batch! equalKb 600 1 0)
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $status) (review-hypotheses 0 equalKb $goal)
   ((< (abs-math (- (the Number $s) 0.5)) 1e-12) $status))) ((true dropped) (true kept)))
!(test (size-atom (collapse (match &hm_screened ($_h equalKb $_key $_name $_rule) true))) 1)

;; Identical-rate pair and single at four observations: uncertainty is not
;; equivalence. This assertion fails on f30e40eb's non-difference screen.
!(map-flat (recover-case! recoverKb) ((1 1 1) (2 1 1) (3 1 1) (4 1 1) (5 0 1) (6 0 1)))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) $_tv $status) (review-hypotheses 100 recoverKb $goal)
   (if (=alpha $a (And (F0 $t) (F1 $t))) $status (empty)))) (kept))
!(test (recover-pair?) true)
!(test (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule) true)) ())
;; With 84 successes both rates are identical and the two-SE band is below
;; .05: the same pair is now redundant with enough power to screen it.
!(recover-batch! recoverKb 100 1 1)
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
!(recover-case! recoverKb (1001 0 1))
!(collapse (review-hypotheses 0 recoverKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule) true))) 1)
!(test (recover-pair?) false)

;; Current folds show that the degraded single no longer screens the pair. Reconsideration clears only
;; the tried marker. It never allocates a live rule or bypasses capacity.
!(set-hypothesis-mining recoverKb 2 1)
!(recover-batch! recoverKb 2000 0 0)
!(map-flat (recover-case! recoverKb) ((3001 0 0) (3002 0 0) (3003 0 0) (3004 0 0) (3005 0 0) (3006 0 0) (3007 0 0)))
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
!(recover-batch! withdrawKb 100 1 1)
!(map-flat (recover-case! withdrawKb) ((1 0 1) (2 0 1)))
!(collapse (review-hypotheses 100 withdrawKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule) true))) 1)
!(collapse (match &hm_live ($_h withdrawKb $c $name $a $_born)
   (if (=alpha $a (F1 $t)) (hm-drop! withdrawKb $name $c) (empty))))
!(collapse (review-hypotheses 0 withdrawKb $goal))
!(test (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule) true)) ())
!(recover-case! withdrawKb (11 1 1))
!(test (size-atom (collapse (match &hm_live ($_h withdrawKb $_c $_name $a $_born)
   (if (=alpha $a (And (F0 $t) (F1 $t))) true (empty))))) 1)

;; Real subset counts with a powered initial screen: 80 pair and single
;; successes. After withdrawal the pair's retained fold gets 480 further
;; successes, and the single gets 12 failures. Its drift (~.021) is below
;; the old drop-time SE (~.024), but the current pair count (560) resolves
;; it (two-SE band ~.018). A frozen-SE movement trigger would miss recovery.
!(set-rule-change-hazard currentKb 0)
!(set-positive-only-predicate currentKb F0)
!(set-positive-only-predicate currentKb F1)
!(set-hypothesis-mining currentKb 2 2)
!(set-predicate-time currentKb F0 1 0)
!(set-predicate-time currentKb F1 1 0)
!(set-predicate-time currentKb T 1 1)
!(recover-batch! currentKb 100 1 1)
!(map-flat (recover-case! currentKb) ((1 0 1) (2 0 1)))
!(collapse (review-hypotheses 100 currentKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h currentKb $_key $_name $_rule) true))) 1)
!(set-hypothesis-mining currentKb 2 1)
!(recover-batch! currentKb 1000 1 1)
!(recover-batch! currentKb 2000 1 1)
!(recover-batch! currentKb 3000 1 1)
!(recover-batch! currentKb 4000 1 1)
!(recover-batch! currentKb 5000 1 1)
!(recover-batch! currentKb 6000 1 1)
!(map-flat (recover-case! currentKb) ((9001 0 0) (9002 0 0) (9003 0 0) (9004 0 0) (9005 0 0) (9006 0 0) (9007 0 0) (9008 0 0) (9009 0 0) (9010 0 0) (9011 0 0) (9012 0 0)))
!(collapse (review-hypotheses 0 currentKb $goal))
!(test (collapse (match &hm_screened ($_h currentKb $_key $_name $_rule) true)) ())
!(set-hypothesis-mining currentKb 2 2)
!(recover-case! currentKb (51 1 1))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $status) (review-hypotheses 100 currentKb $goal)
   (if (=alpha $a (And (F0 $t) (F1 $t))) ((> (the Number $s) 0.99) $status) (empty)))) ((true kept)))
