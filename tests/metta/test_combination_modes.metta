!(import! &self ../../pettachainer/metta/petta_chainer)

;; Forward views of one statement combine by the mode its stored outcomes
;; prefer: revision, odds or noisy-OR (docs/metta/combination_modes.md). Two
;; rules give views of (C x) from (A1 x) and (A2 x); each case stores both
;; antecedents and then its outcome. k = 5.
!(set-evidence-confidence-k 5)

(: add-cases! (-[det]-> KB (List Atom) Atom))
(= (add-cases! $kb ()) ())
(= (add-cases! $kb (cons ($i $a1 $a2 $c) $rest))
   (let* (($_a1 (collapse (compileadd $kb (: o (A1 $i) (STV $a1 1)))))
          ($_a2 (collapse (compileadd $kb (: o (A2 $i) (STV $a2 1)))))
          ($_c (collapse (compileadd $kb (: o (C $i) (STV $c 1))))))
      (add-cases! $kb $rest)))

(: rules! (-[det]-> KB Number Number Number Number Atom))
(= (rules! $kb $t1 $f1 $t2 $f2)
   (let* (($_r1 (collapse (compileadd $kb (: r1 (Implication (A1 $x) (C $x)) (CTV (STV $t1 1) (STV $f1 1))))))
          ($_r2 (collapse (compileadd $kb (: r2 (Implication (A2 $x) (C $x)) (CTV (STV $t2 1) (STV $f2 1)))))))
      ()))

;; The answer for a new case with both antecedents true.
(: both-true (-[nondet]-> KB AnnotatedStatement))
(= (both-true $kb)
   (let* (($_a1 (collapse (compileadd $kb (: q1 (A1 q) (STV 1 1)))))
          ($_a2 (collapse (compileadd $kb (: q2 (A2 q) (STV 1 1))))))
      (query 20 $kb (: $p (C q) $tv))))

;; Signs of C, independent given C: P(C) = 0.3, P(A1 | C) = 0.85 against
;; 0.15, P(A2 | C) = 0.8 against 0.2; 60 sampled cases, 16 with C. Each
;; outcome is predicted from the outcomes before it: odds scores -12.19,
;; revision -18.92, noisy-OR -19.12, a Bayes factor of e^6.7 for odds. The
;; prior is (16 + 1) / (60 + 2), and
;; logit P = logit 0.7083 + logit 0.6316 - logit (17/62): 0.91680.
!(rules! oddsKb 0.7083 0.07031 0.6316 0.09677)
!(add-cases! oddsKb ((1 0 1 0) (2 1 1 1) (3 0 0 0) (4 0 1 0) (5 0 0 0) (6 0 0 0) (7 0 1 0) (8 1 1 1) (9 0 0 0) (10 0 1 0) (11 1 0 0) (12 0 1 0) (13 0 0 0) (14 0 0 0) (15 0 0 0) (16 1 1 1) (17 0 0 0) (18 0 0 0) (19 0 0 0) (20 0 0 0) (21 0 0 0) (22 0 1 0) (23 0 0 0) (24 0 0 0) (25 0 0 0) (26 0 0 0) (27 0 0 0) (28 1 1 1) (29 0 0 0) (30 1 1 1) (31 0 1 1) (32 0 0 0) (33 0 1 1) (34 1 0 0) (35 1 1 1) (36 1 0 0) (37 1 0 1) (38 1 1 1) (39 1 0 0) (40 1 1 1) (41 0 1 0) (42 1 0 0) (43 0 0 0) (44 0 0 0) (45 0 0 0) (46 1 0 0) (47 1 0 0) (48 0 1 0) (49 0 0 0) (50 1 0 0) (51 1 1 1) (52 1 1 1) (53 0 0 0) (54 0 0 0) (55 1 1 1) (56 0 0 0) (57 0 1 0) (58 1 1 1) (59 0 1 0) (60 1 1 1)))
!(test (both-true oddsKb)
   (: (combination odds (prior (STV 0.27419354838709675 0.9230769230769231)) ((by r1 q1) (by r2 q2))) (C q) (STV 0.916802744544546 0.9693544808244096)))

;; Independent causes of C (noisy-OR): P(A1) = P(A2) = 0.3, a leak of 0.05
;; and weights 0.8 and 0.7; 60 cases, 29 with C. Noisy-OR scores -19.68,
;; odds -20.00, revision -27.38. With the prior 30/62,
;; 1 - P = (1 - 30/62) (0.1501 / (32/62)) (0.2166 / (32/62)): 0.93701.
!(rules! causesKb 0.8499 0.2495 0.7834 0.278)
!(add-cases! causesKb ((1 0 0 0) (2 1 0 1) (3 0 0 0) (4 0 0 0) (5 0 0 0) (6 0 0 0) (7 0 1 1) (8 1 0 1) (9 0 0 0) (10 0 1 1) (11 0 1 1) (12 0 0 0) (13 0 0 0) (14 0 0 0) (15 0 0 0) (16 1 0 1) (17 0 0 0) (18 0 0 0) (19 0 0 0) (20 0 0 0) (21 0 0 0) (22 0 0 0) (23 0 1 0) (24 0 0 0) (25 0 0 0) (26 0 0 0) (27 0 0 0) (28 1 0 1) (29 0 1 0) (30 1 0 1) (31 1 0 1) (32 0 0 0) (33 1 0 1) (34 0 1 1) (35 1 0 1) (36 0 1 0) (37 1 1 1) (38 1 1 1) (39 0 1 0) (40 1 1 1) (41 0 0 0) (42 0 1 1) (43 0 0 0) (44 0 0 0) (45 0 1 1) (46 0 1 1) (47 0 1 1) (48 0 0 0) (49 0 1 1) (50 0 1 1) (51 1 1 1) (52 1 1 1) (53 0 0 0) (54 0 1 1) (55 1 0 1) (56 0 0 0) (57 0 0 1) (58 1 0 1) (59 0 1 1) (60 1 1 1)))
!(test (both-true causesKb)
   (: (combination noisy-or (prior (STV 0.4838709677419355 0.9230769230769231)) ((by r1 q1) (by r2 q2))) (C q) (STV 0.93700865875 0.9948553294711998)))

;; Redundant antecedents: A2 is a copy of A1. Products count the one
;; observation twice and lose (odds -20.39, noisy-OR -37.98, revision
;; -18.25): the views revise, 0.7083.
!(rules! copyKb 0.7083 0.07031 0.7083 0.07031)
!(add-cases! copyKb ((1 1 1 1) (2 0 0 0) (3 0 0 0) (4 0 0 0) (5 1 1 1) (6 0 0 0) (7 1 1 0) (8 0 0 0) (9 0 0 1) (10 1 1 0) (11 1 1 1) (12 0 0 0) (13 1 1 1) (14 1 1 1) (15 0 0 0) (16 1 1 1) (17 1 1 1) (18 1 1 1) (19 0 0 0) (20 0 0 0) (21 0 0 0) (22 1 1 1) (23 0 0 0) (24 0 0 0) (25 0 0 0) (26 0 0 0) (27 0 0 0) (28 0 0 0) (29 1 1 1) (30 0 0 0) (31 1 1 1) (32 0 0 0) (33 0 0 0) (34 0 0 0) (35 0 0 0) (36 1 1 0) (37 1 1 1) (38 0 0 0) (39 0 0 0) (40 0 0 0) (41 0 0 0) (42 0 0 0) (43 0 0 0) (44 0 0 0) (45 1 1 1) (46 1 1 0) (47 0 0 0) (48 0 0 0) (49 0 0 0) (50 0 0 0) (51 0 0 1) (52 0 0 0) (53 0 0 0) (54 0 0 0) (55 0 0 0) (56 0 0 0) (57 1 1 1) (58 1 1 1) (59 0 0 0) (60 0 0 0)))
!(test (both-true copyKb) (: (merge/revision (by r1 q1) (by r2 q2)) (C q) (STV 0.7083 0.9999500024013799)))

;; Few outcomes: the first ten signs cases favour odds (-1.17 against -2.88)
;; by a factor of e^1.7, below 10, so the views still revise.
!(rules! smallKb 0.7083 0.07031 0.6316 0.09677)
!(add-cases! smallKb ((1 0 1 0) (2 1 1 1) (3 0 0 0) (4 0 1 0) (5 0 0 0) (6 0 0 0) (7 0 1 0) (8 1 1 1) (9 0 0 0) (10 0 1 0)))
!(test (both-true smallKb) (: (merge/revision (by r2 q2) (by r1 q1)) (C q) (STV 0.6699499857967988 0.999950002419896)))

;; Refined rules are scored with what they learned. The signs cases again,
;; with both rules stated as weak hypotheses and refined from the cases. Once
;; reviewed, an outcome's views read each rule's learned truth, not its prior
;; (0.5 in both branches, which scores every mode alike and so kept
;; revision), and odds wins as with the stated rates. Outcomes are scored when
;; a merge first asks for the mode, so with what the rules know then.
!(set-rule-refinement refinedOddsKb true)
!(compileadd refinedOddsKb (: r1 (Implication (A1 $x) (C $x)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(compileadd refinedOddsKb (: r2 (Implication (A2 $x) (C $x)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(add-cases! refinedOddsKb ((1 0 1 0) (2 1 1 1) (3 0 0 0) (4 0 1 0) (5 0 0 0) (6 0 0 0) (7 0 1 0) (8 1 1 1) (9 0 0 0) (10 0 1 0) (11 1 0 0) (12 0 1 0) (13 0 0 0) (14 0 0 0) (15 0 0 0) (16 1 1 1) (17 0 0 0) (18 0 0 0) (19 0 0 0) (20 0 0 0) (21 0 0 0) (22 0 1 0) (23 0 0 0) (24 0 0 0) (25 0 0 0) (26 0 0 0) (27 0 0 0) (28 1 1 1) (29 0 0 0) (30 1 1 1) (31 0 1 1) (32 0 0 0) (33 0 1 1) (34 1 0 0) (35 1 1 1) (36 1 0 0) (37 1 0 1) (38 1 1 1) (39 1 0 0) (40 1 1 1) (41 0 1 0) (42 1 0 0) (43 0 0 0) (44 0 0 0) (45 0 0 0) (46 1 0 0) (47 1 0 0) (48 0 1 0) (49 0 0 0) (50 1 0 0) (51 1 1 1) (52 1 1 1) (53 0 0 0) (54 0 0 0) (55 1 1 1) (56 0 0 0) (57 0 1 0) (58 1 1 1) (59 0 1 0) (60 1 1 1)))
!(test
   (let (: $p $t $tv) (query 20 refinedOddsKb (: $p (RuleTruth (Implication (A1 $x) (C $x))) $tv)) $tv)
   (STV 0.6357340720221606 0.815512048192771))
!(test
   (let (: $p $t $tv) (query 20 refinedOddsKb (: $p (RuleTruth (Implication (A2 $x) (C $x))) $tv)) $tv)
   (STV 0.5996324392502989 0.8338853455528261))
!(test (both-true refinedOddsKb)
   (: (combination odds (prior (STV 0.27419354838709675 0.9230769230769231)) ((by r1 q1) (by r2 q2))) (C q) (STV 0.873722302450798 0.8694974289494)))
