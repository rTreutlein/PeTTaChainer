!(import! &self ../../pettachainer/metta/petta_chainer)
!(set-evidence-confidence-k 1)

;; A live general rule in the review snapshot used by the SE unit cases.
!(let $hash (hm-pattern-hash miniatureKb (T $t))
   (add-atom &hm_live ($hash miniatureKb (T $t) single (F1 $t) 0)))

;; The AND2 failure: a very confident pair must not be screened by a single
;; whose own SE exceeds the two-SE comparison tolerance. Master drops it,
;; using only the pair's sample count.
!(let* (($c20 (count-confidence 20))
        ($c4 (count-confidence 4))
        ($pair (hm-reviewed pair (And (F0 $t) (F1 $t)) (T $t) 0 (STV 0.999 $c20)))
        ($single (hm-reviewed single (F1 $u) (T $u) 0 (STV 0.998 $c4))))
   (test (hm-decision miniatureKb (the (List HmReviewed) ($pair $single)) (the HmReviewed $pair)) true))

;; Enough evidence still screens; the reference and its own SE are retained.
!(let* (($c8 (count-confidence 8))
        ($c20 (count-confidence 20))
        ($pair (hm-reviewed pair (And (F0 $t) (F1 $t)) (T $t) 0 (STV 0.999 $c20)))
        ($single (hm-reviewed single (F1 $u) (T $u) 0 (STV 0.998 $c8))))
   (test (case (hm-decision miniatureKb (the (List HmReviewed) ($pair $single)) (the HmReviewed $pair)) (((screen $_rule $_s $_se) true) ($_other false))) true))

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
!(test (size-atom (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule $_s $_se) true))) 1)

;; An unrelated change and repeated reviews do not revisit the screen.
!(compileadd recoverKb (: unrelated Unrelated (STV 1 1)))
!(collapse (query 20 recoverKb (: $p Unrelated $tv)))
!(test (collapse (match &hm_screen_dirty ($_h recoverKb $_key) true)) ())
!(collapse (review-hypotheses 0 recoverKb $goal))
!(collapse (review-hypotheses 0 recoverKb $goal))
!(test (recover-pair?) false)
!(test (recover-live) 1)

;; A small move below the recorded SE keeps the screen, even when notified.
!(recover-case! recoverKb (101 0 1))
!(collapse (review-hypotheses 0 recoverKb $goal))
!(test (size-atom (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule $_s $_se) true))) 1)
!(test (recover-pair?) false)

;; The single degrades beyond its recorded SE. Reconsideration clears only
;; the tried marker. It never allocates a live rule or bypasses capacity.
!(set-hypothesis-mining recoverKb 2 1)
!(map-flat (recover-case! recoverKb) ((11 0 0) (12 0 0) (13 0 0) (14 0 0) (15 0 0) (16 0 0) (17 0 0) (18 0 0) (19 0 0) (20 0 0) (102 0 0)))
!(test (collapse (let (hypothesis $_name (Implication $a $_c) (STV $s $_confidence) $_status) (review-hypotheses 0 recoverKb $goal)
   (if (=alpha $a (F1 $t)) ((> (the Number $s) 0.49) (< (the Number $s) 0.51)) (empty)))) ((true true)))
!(test (collapse (match &hm_screened ($_h recoverKb $_key $_name $_rule $_s $_se) true)) ())
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
!(test (size-atom (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule $_s $_se) true))) 1)
!(collapse (match &hm_live ($_h withdrawKb $c $name $a $_born)
   (if (=alpha $a (F1 $t)) (hm-drop! withdrawKb $name $c) (empty))))
!(collapse (review-hypotheses 0 withdrawKb $goal))
!(test (collapse (match &hm_screened ($_h withdrawKb $_key $_name $_rule $_s $_se) true)) ())
!(recover-case! withdrawKb (11 1 1))
!(test (size-atom (collapse (match &hm_live ($_h withdrawKb $_c $_name $a $_born)
   (if (=alpha $a (And (F0 $t) (F1 $t))) true (empty))))) 1)
