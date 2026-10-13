!(import! &self ../../pettachainer/metta/petta_chainer)

;; A KB with hypothesis mining on proposes its own hypotheses from the facts
;; added to it (docs/metta/hypothesis_rules.md, "Mining hypotheses").

(: live-hypotheses (-[det]-> KB Atom))
(= (live-hypotheses $kb)
   (collapse (match &hm_live ($_hash $kb $consequent $_name $antecedent $_born) (Implication $antecedent $consequent))))

(: hm-name-of (-[det]-> KB Atom Atom Atom))
(= (hm-name-of $kb $antecedent $consequent)
   (collapse (match &kb ((RuleTruth (Implication $antecedent $consequent)) ($kb $_ctx $_vars) (rule-axiom $name) $_tv) $name)))

(: hypothesis-tv (-[det]-> KB Atom Atom))
(= (hypothesis-tv $kb $implication)
   (collapse (match &kb ((RuleTruth $implication) ($kb $_ctx $_vars) (rule-axiom $_name) $tv) $tv)))

;; --- Generation -------------------------------------------------------------

;; A hypothesis's prior has the evidence of a hundredth of an observation:
;; with k = 1, confidence 0.01/1.01.
!(set-evidence-confidence-k 1)

;; Within one time point, a fact of a lower layer concludes one of a higher
;; layer: a pair at once; a pair whose features share another constant also
;; gives the relational form. A single is proposed when it recurs at another
;; instance where the other facts below its consequent differ, so that the
;; pairs of its first sighting do not explain it. Sample and Left store only
;; their true instances: their hypotheses are STVs.
!(set-positive-only-predicate mtsKb Sample)
!(set-positive-only-predicate mtsKb Left)
!(set-hypothesis-mining mtsKb 8 16)
!(set-predicate-time mtsKb Sample 2 0)
!(set-predicate-time mtsKb Left 2 0)
!(set-predicate-time mtsKb Reward 2 1)
!(compileadd mtsKb (: s1 (Sample A1 t1) (STV 1 1)))
!(compileadd mtsKb (: l1 (Left B1 t1) (STV 1 1)))
!(test (live-hypotheses mtsKb) ())
!(compileadd mtsKb (: r1 (Reward left t1) (STV 1 1)))
!(test (live-hypotheses mtsKb) ((Implication (And (Left B1 $_0) (Sample A1 $_0)) (Reward left $_0))))
!(test (hypothesis-tv mtsKb (Implication (And (Left B1 $t) (Sample A1 $t)) (Reward left $t))) ((STV 0.5 0.009900990099009901)))
;; A failure says nothing about what co-occurs with a reward, and the same
;; context again gives no single.
!(compileadd mtsKb (: s2 (Sample A2 t2) (STV 1 1)))
!(compileadd mtsKb (: l2 (Left B2 t2) (STV 1 1)))
!(compileadd mtsKb (: r2 (Reward left t2) (STV 0 1)))
!(compileadd mtsKb (: s3 (Sample A1 t3) (STV 1 1)))
!(compileadd mtsKb (: l3 (Left B1 t3) (STV 1 1)))
!(compileadd mtsKb (: r3 (Reward left t3) (STV 1 1)))
!(test (live-hypotheses mtsKb) ((Implication (And (Left B1 $_0) (Sample A1 $_0)) (Reward left $_0))))
;; The sample in another context: its single recurs where the first
;; context's pair does not explain it.
!(compileadd mtsKb (: s4 (Sample A1 t4) (STV 1 1)))
!(compileadd mtsKb (: l4 (Left B2 t4) (STV 1 1)))
!(compileadd mtsKb (: r4 (Reward left t4) (STV 1 1)))
!(test (live-hypotheses mtsKb)
   ((Implication (And (Left B1 $_0) (Sample A1 $_0)) (Reward left $_0))
    (Implication (Sample A1 $_1) (Reward left $_1))
    (Implication (And (Left B2 $_2) (Sample A1 $_2)) (Reward left $_2))))
;; The relational form, where the features share a stimulus.
!(compileadd mtsKb (: s5 (Sample A3 t5) (STV 1 1)))
!(compileadd mtsKb (: l5 (Left A3 t5) (STV 1 1)))
!(compileadd mtsKb (: r5 (Reward left t5) (STV 1 1)))
!(test (size-atom (collapse (match &hm_live ($_h mtsKb $_c $_n $antecedent $_b)
                               (if (=alpha $antecedent (And (Left $x $t) (Sample $x $t))) true (empty)))))
   1)

;; A failure a live hypothesis predicted proposes the pairs of its context,
;; which can learn the exception.
!(set-positive-only-predicate errKb Sample)
!(set-positive-only-predicate errKb Left)
!(set-positive-only-predicate errKb Right)
!(set-hypothesis-mining errKb 8 16)
!(set-predicate-time errKb Sample 2 0)
!(set-predicate-time errKb Left 2 0)
!(set-predicate-time errKb Right 2 0)
!(set-predicate-time errKb Reward 2 1)
!(compileadd errKb (: s1 (Sample A1 t1) (STV 1 1)))
!(compileadd errKb (: l1 (Left B1 t1) (STV 1 1)))
!(compileadd errKb (: r1 (Reward left t1) (STV 1 1)))
!(compileadd errKb (: s2 (Sample A1 t2) (STV 1 1)))
!(compileadd errKb (: l2 (Left B1 t2) (STV 1 1)))
!(compileadd errKb (: x2 (Right B2 t2) (STV 1 1)))
!(compileadd errKb (: r2 (Reward left t2) (STV 0 1)))
!(test (live-hypotheses errKb)
   ((Implication (And (Left B1 $_0) (Sample A1 $_0)) (Reward left $_0))
    (Implication (And (Left B1 $_1) (Right B2 $_1)) (Reward left $_1))
    (Implication (And (Right B2 $_2) (Sample A1 $_2)) (Reward left $_2))))

;; A statement that never holds, such as an operation that never succeeds:
;; its failures propose where no live hypothesis concludes them, as successes
;; do, a single when it recurs among failures, so a rule can learn that it
;; fails. Once one concludes the pattern, a failure in another context
;; proposes nothing more.
!(set-positive-only-predicate failKb Ball)
!(set-hypothesis-mining failKb 4 8)
!(set-predicate-time failKb Ball 2 0)
!(set-predicate-time failKb Reward 2 1)
!(compileadd failKb (: b1 (Ball right t1) (STV 1 1)))
!(compileadd failKb (: r1 (Reward left t1) (STV 0 1)))
!(test (live-hypotheses failKb) ())
!(compileadd failKb (: b2 (Ball right t2) (STV 1 1)))
!(compileadd failKb (: r2 (Reward left t2) (STV 0 1)))
!(test (live-hypotheses failKb) ((Implication (Ball right $_0) (Reward left $_0))))
!(test (hypothesis-tv failKb (Implication (Ball right $t) (Reward left $t))) ((STV 0.5 0.009900990099009901)))
!(compileadd failKb (: b3 (Ball equal t3) (STV 1 1)))
!(compileadd failKb (: r3 (Reward left t3) (STV 0 1)))
!(compileadd failKb (: b4 (Ball equal t4) (STV 1 1)))
!(compileadd failKb (: r4 (Reward left t4) (STV 0 1)))
!(test (live-hypotheses failKb) ((Implication (Ball right $_0) (Reward left $_0))))

;; A failure's sighting of a single does not count towards a success's
;; recurrence: the success after it is the single's first true sighting.
!(set-positive-only-predicate mixKb Ball)
!(set-hypothesis-mining mixKb 4 8)
!(set-predicate-time mixKb Ball 2 0)
!(set-predicate-time mixKb Reward 2 1)
!(compileadd mixKb (: b1 (Ball right t1) (STV 1 1)))
!(compileadd mixKb (: r1 (Reward left t1) (STV 0 1)))
!(compileadd mixKb (: b2 (Ball right t2) (STV 1 1)))
!(compileadd mixKb (: r2 (Reward left t2) (STV 1 1)))
!(test (live-hypotheses mixKb) ())

;; The layers order a time point's facts, not the order they arrive in: the
;; inspected route arrives before its period's storm, and the storm still
;; concludes it. Facts of one layer are not related.
!(set-hypothesis-mining stormKb 8 16)
!(set-predicate-time stormKb Storm 2 0)
!(set-predicate-time stormKb Blocked 2 1)
!(compileadd stormKb (: b1 (Blocked r1 p1) (STV 1 1)))
!(compileadd stormKb (: c1 (Blocked r2 p1) (STV 1 1)))
!(compileadd stormKb (: n1 (Storm north p1) (STV 1 1)))
!(test (live-hypotheses stormKb) ())
!(compileadd stormKb (: n2 (Storm north p2) (STV 1 1)))
!(compileadd stormKb (: b2 (Blocked r1 p2) (STV 1 1)))
!(compileadd stormKb (: c2 (Blocked r2 p2) (STV 1 1)))
!(test (live-hypotheses stormKb)
   ((Implication (Storm north $_0) (Blocked r1 $_0))
    (Implication (Storm north $_1) (Blocked r2 $_1))))
!(test (hypothesis-tv stormKb (Implication (Storm north $p) (Blocked r1 $p))) ((CTV (STV 0.5 0.009900990099009901) (STV 0.5 0.009900990099009901))))

;; Across a link, the earlier fact concludes the later one, with the link as
;; a conjunct and only the time points as variables: persistence of each
;; entity, whichever arrives first. Facts two time points apart are not
;; related.
!(set-hypothesis-mining persistKb 8 16)
!(set-predicate-time persistKb Storm 2 0)
!(set-time-link persistKb NextPeriod)
!(compileadd persistKb (: x2 (NextPeriod p1 p2) (STV 1 1)))
!(compileadd persistKb (: x3 (NextPeriod p2 p3) (STV 1 1)))
!(compileadd persistKb (: x4 (NextPeriod p3 p4) (STV 1 1)))
!(compileadd persistKb (: n1 (Storm north p1) (STV 1 1)))
!(compileadd persistKb (: n3 (Storm north p3) (STV 1 1)))
!(test (live-hypotheses persistKb) ())
!(compileadd persistKb (: n4 (Storm north p4) (STV 1 1)))
!(test (live-hypotheses persistKb) ())
!(compileadd persistKb (: n2 (Storm north p2) (STV 1 1)))
!(test (live-hypotheses persistKb)
   ((Implication (And (NextPeriod $_0 $_1) (Storm north $_0)) (Storm north $_1))))

;; The past concludes only what the present's causes leave unexplained: the
;; route stays blocked because the storm persists, and once the storm
;; concludes the route the route's own persistence is not proposed.
!(set-hypothesis-mining markovKb 8 16)
!(set-predicate-time markovKb Storm 2 0)
!(set-predicate-time markovKb Blocked 2 1)
!(set-time-link markovKb NextPeriod)
(: add-period! (-[det]-> (Atom Atom) Atom))
(= (add-period! ($previous $period))
   (let* (($_x (collapse (compileadd markovKb (: (x $period) (NextPeriod $previous $period) (STV 1 1)))))
          ($_n (collapse (compileadd markovKb (: (n $period) (Storm north $period) (STV 1 1)))))
          ($_b (collapse (compileadd markovKb (: (b $period) (Blocked r1 $period) (STV 1 1))))))
      ()))
!(add-period! (p0 p1))
!(add-period! (p1 p2))
!(add-period! (p2 p3))
!(add-period! (p3 p4))
!(test (live-hypotheses markovKb)
   ((Implication (Storm north $_0) (Blocked r1 $_0))
    (Implication (And (NextPeriod $_1 $_2) (Storm north $_1)) (Storm north $_2))))

;; A predicate without a declared place in time is not mined.
!(set-hypothesis-mining untimedKb 8 16)
!(set-predicate-time untimedKb Storm 2 0)
!(compileadd untimedKb (: n1 (Storm north p1) (STV 1 1)))
!(compileadd untimedKb (: b1 (Blocked r1 p1) (STV 1 1)))
!(compileadd untimedKb (: n2 (Storm north p2) (STV 1 1)))
!(compileadd untimedKb (: b2 (Blocked r1 p2) (STV 1 1)))
!(test (live-hypotheses untimedKb) ())

;; Off, nothing is proposed.
!(set-predicate-time offKb Storm 2 0)
!(set-predicate-time offKb Blocked 2 1)
!(compileadd offKb (: n1 (Storm north p1) (STV 1 1)))
!(compileadd offKb (: b1 (Blocked r1 p1) (STV 1 1)))
!(compileadd offKb (: n2 (Storm north p2) (STV 1 1)))
!(compileadd offKb (: b2 (Blocked r1 p2) (STV 1 1)))
!(test (live-hypotheses offKb) ())

;; --- Budget -----------------------------------------------------------------

;; A fact proposes at most max-new hypotheses, and a consequent pattern keeps
;; at most max-live. Three features give three pairs.
!(set-hypothesis-mining budgetKb 2 3)
!(set-predicate-time budgetKb P1 1 0)
!(set-predicate-time budgetKb P2 1 0)
!(set-predicate-time budgetKb P3 1 0)
!(set-predicate-time budgetKb Q 1 1)
(: add-budget-case! (-[det]-> (Atom Atom) Atom))
(= (add-budget-case! ($i $q))
   (let* (($_1 (collapse (compileadd budgetKb (: (f1 $i) (P1 $i) (STV 1 1)))))
          ($_2 (collapse (compileadd budgetKb (: (f2 $i) (P2 $i) (STV 1 1)))))
          ($_3 (collapse (compileadd budgetKb (: (f3 $i) (P3 $i) (STV 1 1)))))
          ($_q (collapse (compileadd budgetKb (: (q $i) ($q $i) (STV 1 1))))))
      ()))
!(add-budget-case! (i1 Q))
!(test (size-atom (collapse (match &hm_live ($_h budgetKb (Q $_x) $_n $_a $_b) true))) 2)
!(add-budget-case! (i2 Q))
!(add-budget-case! (i3 Q))
!(test (size-atom (collapse (match &hm_live ($_h budgetKb (Q $_x) $_n $_a $_b) true))) 3)

;; --- Pruning ----------------------------------------------------------------

;; B holds in 16 of 20 cases with A and 4 of 20 without; C is unrelated,
;; and of A's layer. A review keeps A -> B, drops C -> B, and drops A and C
;; -> B, which A -> B screens off.
!(set-evidence-confidence-k 5)
!(set-hypothesis-mining pruneKb 8 16)
!(set-predicate-time pruneKb A 1 0)
!(set-predicate-time pruneKb C 1 0)
!(set-predicate-time pruneKb B 1 1)
(: add-case! (-[det]-> (Number Number Number Number) Atom))
(= (add-case! ($i $a $b $c))
   (let* (($_a (collapse (compileadd pruneKb (: (a $i) (A $i) (STV $a 1)))))
          ($_c (collapse (compileadd pruneKb (: (c $i) (C $i) (STV $c 1)))))
          ($_b (collapse (compileadd pruneKb (: (b $i) (B $i) (STV $b 1))))))
      ()))
(: add-cases! (-[det]-> Atom))
(= (add-cases!)
   (map-flat add-case!
   ((1 1 1 1) (2 1 1 0) (3 1 1 1) (4 1 1 0) (5 1 1 1) (6 1 1 0) (7 1 1 1) (8 1 1 0) (9 1 0 1) (10 1 0 0)
    (11 0 1 1) (12 0 1 0) (13 0 0 1) (14 0 0 0) (15 0 0 1) (16 0 0 0) (17 0 0 1) (18 0 0 0) (19 0 0 1) (20 0 0 0)
    (21 1 1 1) (22 1 1 0) (23 1 1 1) (24 1 1 0) (25 1 1 1) (26 1 1 0) (27 1 1 1) (28 1 1 0) (29 1 0 1) (30 1 0 0)
    (31 0 1 1) (32 0 1 0) (33 0 0 1) (34 0 0 0) (35 0 0 1) (36 0 0 0) (37 0 0 1) (38 0 0 0) (39 0 0 1) (40 0 0 0))))
!(add-cases!)
!(test (collapse (let (hypothesis $_name $implication $_tv $verdict) (review-hypotheses 50 pruneKb $goal) ($implication $verdict)))
   (((Implication (And (A $_0) (C $_0)) (B $_0)) dropped)
    ((Implication (A $_1) (B $_1)) kept)
    ((Implication (C $_2) (B $_2)) dropped)))
!(test (live-hypotheses pruneKb) ((Implication (A $_0) (B $_0))))

;; A dropped hypothesis is not proposed again, and no longer applies.
!(add-case! (41 1 1 1))
!(test (live-hypotheses pruneKb) ((Implication (A $_0) (B $_0))))
(: rule-count (-[det]-> KB Atom Atom Number))
(= (rule-count $kb $antecedent $consequent)
   (case (hm-name-of $kb $antecedent $consequent) (
      ((cons $name $_rest) (size-atom (collapse (match rule_name_index ($name $_id) true))))
      (() -1))))
!(test (rule-count pruneKb (C $x) (B $x)) 0)
!(test (> (rule-count pruneKb (A $x) (B $x)) 0) true)

;; Later reviews read the truths with no budget: the chainer took the new
;; instances into them.
(: review-truths (-[det]-> Number Atom))
(= (review-truths $steps)
   (collapse (let (hypothesis $_name $_implication $tv $_verdict) (review-hypotheses $steps pruneKb $goal) $tv)))
!(let* (($before (review-truths 0))
        ($_cases (map-flat add-case! ((42 1 1 0) (43 1 1 0) (44 1 1 0) (45 1 1 0)))))
   (test (== (review-truths 0) $before) false))

;; The review built open joins before withdrawal. A fresh time point must
;; extend only the surviving hypothesis, on both branches of its CTV.
!(set-hypothesis-mining pruneKb 0 0)
!(compileadd pruneKb (: fresh-a (A fresh) (STV 1 1)))
!(compileadd pruneKb (: fresh-c (C fresh) (STV 1 1)))
!(compileadd pruneKb (: false-a (A fresh-false) (STV 0 1)))
!(compileadd pruneKb (: false-c (C fresh-false) (STV 1 1)))
!(test (collapse (let* (((cons $live $_rest) (hm-name-of pruneKb (A $t) (B $t)))
                       ((: $proof $_statement (STV $s $_confidence)) (query 40 pruneKb (: $p (B fresh) $tv))))
                   ((== $proof (by $live fresh-a)) (> $s 0.7))))
   ((true true)))
!(test (collapse (let* (((cons $live $_rest) (hm-name-of pruneKb (A $t) (B $t)))
                       ((: $proof $_statement (STV $s $_confidence)) (query 40 pruneKb (: $p (B fresh-false) $tv))))
                   ((== $proof (by $live false-a)) (< $s 0.3))))
   ((true true)))

;; Link-last ingestion joins stored observations, including false outcomes.
;; The endpoint index must work after the recent constant window expired.
;; A temporal failure's context must retain its same-period causes. Changing
;; that cause changes the context even with the same target and past fact.
!(test (collapse
      (let* (($with-g (hypothesis-link-observations (NextPeriod t0 t1)
                       ((1 t0 (F entity t0) 1 0) (2 t1 (G entity t1) 1 0) (3 t1 (Y entity t1) 0 1)) 24))
             ($with-h (hypothesis-link-observations (NextPeriod t0 t1)
                       ((1 t0 (F entity t0) 1 0) (2 t1 (H entity t1) 1 0) (3 t1 (Y entity t1) 0 1)) 24))
             ((hm-observation (Y entity t1) $_sg $_lg $fg) (superpose $with-g))
             ((hm-observation (Y entity t1) $_sh $_lh $fh) (superpose $with-h))
             ($candidates-g (hypothesis-failure-candidates (Y entity t1) 1 $fg ()))
             ($candidates-h (hypothesis-failure-candidates (Y entity t1) 1 $fh ()))
             (((And (NextPeriod $qg $pg) (F entity $qg)) (Y entity $pg) (failed $_ig $cg))
                (superpose $candidates-g))
             (((And (NextPeriod $qh $ph) (F entity $qh)) (Y entity $ph) (failed $_ih $ch))
                (superpose $candidates-h)))
         (not (== $cg $ch))))
   (true))
!(set-hypothesis-mining linkLastKb 4 8)
!(set-predicate-time linkLastKb F 2 0)
!(set-predicate-time linkLastKb Y 2 0)
!(set-time-link linkLastKb NextPeriod)
!(set-positive-only-predicate linkLastKb NextPeriod)
!(compileadd linkLastKb (: lf0 (F entity t0) (STV 1 1)))
!(compileadd linkLastKb (: ly1 (Y entity t1) (STV 1 1)))
!(compileadd linkLastKb (: lf2 (F entity t2) (STV 1 1)))
!(compileadd linkLastKb (: ly3 (Y entity t3) (STV 1 1)))
!(map-flat (|-> ($i) (collapse (compileadd linkLastKb (: (noise $i) (F entity $i) (STV 1 1)))))
   (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26))
!(compileadd linkLastKb (: lx1 (NextPeriod t0 t1) (STV 1 1)))
!(test (live-hypotheses linkLastKb) ())
!(compileadd linkLastKb (: lx3 (NextPeriod t2 t3) (STV 1 1)))
!(test (live-hypotheses linkLastKb)
   ((Implication (And (NextPeriod $_0 $_1) (F entity $_0)) (Y entity $_1))))
;; A repeated link must not count the outcome again or create another rule.
!(let* (($before (hm-outcomes linkLastKb (Y entity $t)))
        ($_repeat (collapse (compileadd linkLastKb (: lx3-again (NextPeriod t2 t3) (STV 1 1))))))
   (test (hm-outcomes linkLastKb (Y entity $t)) $before))

;; A live conjunction must survive merging both of its general rules. The
;; first general rule wraps it in specializes; the second still sees the
;; same specific reference class, rather than displacing it by confidence.
!(set-evidence-confidence-k 1)
!(set-hypothesis-mining andKb 8 16)
!(set-predicate-time andKb AndA 1 0)
!(set-predicate-time andKb AndC 1 0)
!(set-predicate-time andKb AndD 1 0)
!(set-predicate-time andKb AndB 1 1)
(: add-and-case! (-[det]-> (Number Number Number Number) Atom))
(= (add-and-case! ($i $a $c $d))
   (let* (($truth (* $a $c))
          ($_a (collapse (compileadd andKb (: (aa $i) (AndA $i) (STV $a 1)))))
          ($_c (collapse (compileadd andKb (: (ac $i) (AndC $i) (STV $c 1)))))
          ($_d (collapse (compileadd andKb (: (ad $i) (AndD $i) (STV $d 1)))))
          ($_b (collapse (compileadd andKb (: (ab $i) (AndB $i) (STV $truth 1))))))
      ()))
!(map-flat add-and-case!
   ((1 0 0 0) (2 0 0 1) (3 0 1 0) (4 0 1 1) (5 1 0 0) (6 1 0 1) (7 1 1 0) (8 1 1 1)
    (9 0 0 0) (10 0 0 1) (11 0 1 0) (12 0 1 1) (13 1 0 0) (14 1 0 1) (15 1 1 0) (16 1 1 1)
    (17 0 0 0) (18 0 0 1) (19 0 1 0) (20 0 1 1) (21 1 0 0) (22 1 0 1) (23 1 1 0) (24 1 1 1)
    (25 0 0 0) (26 0 0 1) (27 0 1 0) (28 0 1 1) (29 1 0 0) (30 1 0 1) (31 1 1 0) (32 1 1 1)
    (33 0 0 0) (34 0 0 1) (35 0 1 0) (36 0 1 1) (37 1 0 0) (38 1 0 1) (39 1 1 0) (40 1 1 1)
    (41 0 0 0) (42 0 0 1) (43 0 1 0) (44 0 1 1) (45 1 0 0) (46 1 0 1) (47 1 1 0) (48 1 1 1)))
!(collapse (review-hypotheses 50 andKb $goal))
!(test (size-atom (live-hypotheses andKb)) 3)
!(set-hypothesis-mining andKb 0 0)
!(compileadd andKb (: and-a (AndA fresh) (STV 1 1)))
!(compileadd andKb (: and-c (AndC fresh) (STV 1 1)))
!(compileadd andKb (: and-d (AndD fresh) (STV 1 1)))
!(test (collapse (let (: $_proof $_statement (STV $s $_c)) (query 40 andKb (: $p (AndB fresh) $tv)) (> $s 0.9))) (true))
!(compileadd andKb (: and-false-a (AndA fresh-false) (STV 1 1)))
!(compileadd andKb (: and-false-c (AndC fresh-false) (STV 0 1)))
!(compileadd andKb (: and-false-d (AndD fresh-false) (STV 1 1)))
!(test (collapse (let (: $_proof $_statement (STV $s $_c)) (query 40 andKb (: $p (AndB fresh-false) $tv)) (< $s 0.1))) (true))
