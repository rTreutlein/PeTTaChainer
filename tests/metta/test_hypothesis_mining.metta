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

;; A fact is concluded from each recent fact sharing a constant with it, and
;; from each pair; a pair whose features share another constant also gives the
;; relational form. Sample and Left store only their true instances, so they
;; are never consequents, and their hypotheses are STVs.
!(set-positive-only-predicate mtsKb Sample)
!(set-positive-only-predicate mtsKb Left)
!(set-hypothesis-mining mtsKb 8 16)
!(compileadd mtsKb (: s1 (Sample A1 t1) (STV 1 1)))
!(compileadd mtsKb (: l1 (Left A1 t1) (STV 1 1)))
!(test (live-hypotheses mtsKb) ())
!(compileadd mtsKb (: r1 (Reward left t1) (STV 1 1)))
!(test (live-hypotheses mtsKb)
   ((Implication (Left A1 $_0) (Reward left $_0))
    (Implication (Sample A1 $_1) (Reward left $_1))
    (Implication (And (Left A1 $_2) (Sample A1 $_2)) (Reward left $_2))
    (Implication (And (Left $_3 $_4) (Sample $_3 $_4)) (Reward left $_4))))
!(test (hypothesis-tv mtsKb (Implication (Sample A1 $t) (Reward left $t))) ((STV 0.5 0.009900990099009901)))

;; Without a positive-only predicate both directions are proposed, as CTVs:
;; correlation does not say which way a rule runs.
!(set-hypothesis-mining stormKb 8 16)
!(compileadd stormKb (: n1 (Storm north p1) (STV 1 1)))
!(compileadd stormKb (: b1 (Blocked r1 p1) (STV 1 1)))
!(test (live-hypotheses stormKb)
   ((Implication (Storm north $_0) (Blocked r1 $_0))
    (Implication (Blocked r1 $_1) (Storm north $_1))))
!(test (hypothesis-tv stormKb (Implication (Storm north $p) (Blocked r1 $p))) ((CTV (STV 0.5 0.009900990099009901) (STV 0.5 0.009900990099009901))))

;; Off, nothing is proposed.
!(compileadd offKb (: n1 (Storm north p1) (STV 1 1)))
!(compileadd offKb (: b1 (Blocked r1 p1) (STV 1 1)))
!(test (live-hypotheses offKb) ())

;; --- Budget -----------------------------------------------------------------

;; A fact proposes at most max-new hypotheses, and a consequent pattern keeps
;; at most max-live. Four features give four singles and six pairs.
!(set-hypothesis-mining budgetKb 2 3)
!(compileadd budgetKb (: f1 (P1 i1) (STV 1 1)))
!(compileadd budgetKb (: f2 (P2 i1) (STV 1 1)))
!(compileadd budgetKb (: f3 (P3 i1) (STV 1 1)))
!(compileadd budgetKb (: f4 (P4 i1) (STV 1 1)))
!(test (size-atom (live-hypotheses budgetKb)) 6)
!(compileadd budgetKb (: q1 (Q i1) (STV 1 1)))
!(test (size-atom (live-hypotheses budgetKb)) 8)
!(compileadd budgetKb (: q2 (P1 i2) (STV 1 1)))
!(compileadd budgetKb (: q3 (Q i2) (STV 1 1)))
!(compileadd budgetKb (: q4 (P2 i3) (STV 1 1)))
!(compileadd budgetKb (: q5 (Q i3) (STV 1 1)))
!(test (size-atom (collapse (match &hm_live ($_h budgetKb (Q $_x) $_n $_a $_b) true))) 3)

;; --- Pruning ----------------------------------------------------------------

;; B holds in 16 of 20 cases with A and 4 of 20 without; C is unrelated. A
;; review keeps A -> B and B -> A, drops what involves C, and drops A and C ->
;; B, which A -> B screens off.
!(set-evidence-confidence-k 5)
!(set-hypothesis-mining pruneKb 8 16)
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
   (((Implication (A $_0) (C $_0)) dropped)
    ((Implication (C $_1) (A $_1)) dropped)
    ((Implication (C $_2) (B $_2)) dropped)
    ((Implication (A $_3) (B $_3)) kept)
    ((Implication (B $_4) (C $_4)) dropped)
    ((Implication (B $_5) (A $_5)) kept)
    ((Implication (And (A $_6) (C $_6)) (B $_6)) dropped)))
!(test (live-hypotheses pruneKb) ((Implication (A $_0) (B $_0)) (Implication (B $_1) (A $_1))))

;; A dropped hypothesis is not proposed again, and no longer applies.
!(add-case! (41 1 1 1))
!(test (live-hypotheses pruneKb) ((Implication (A $_0) (B $_0)) (Implication (B $_1) (A $_1))))
(: rule-count (-[det]-> KB Atom Atom Number))
(= (rule-count $kb $antecedent $consequent)
   (case (hm-name-of $kb $antecedent $consequent) (
      ((cons $name $_rest) (size-atom (collapse (match rule_name_index ($name $_id) true))))
      (() -1))))
!(test (rule-count pruneKb (C $x) (B $x)) 0)
!(test (> (rule-count pruneKb (A $x) (B $x)) 0) true)
