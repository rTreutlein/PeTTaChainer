!(import! &self ../../pettachainer/metta/petta_chainer)

;; An exact fold over members its search has not finished is partial: its
;; value covers the members it has, and a conclusion drawn from it is no more
;; confident than the share it covered (docs/metta/partial_folds.md). Four
;; candidates' leak beliefs are derived at increasing depth; u5 has no leak
;; derivation at all, so its search ends without a member.
!(compileadd kb (: c1 (Cand u1) (STV 1 1)))
!(compileadd kb (: c2 (Cand u2) (STV 1 1)))
!(compileadd kb (: c3 (Cand u3) (STV 1 1)))
!(compileadd kb (: c4 (Cand u4) (STV 1 1)))
!(compileadd kb (: c5 (Cand u5) (STV 1 1)))
!(compileadd kb (: a1 (A1 u1) (STV 1 1)))
!(compileadd kb (: a2 (A2 u2) (STV 1 1)))
!(compileadd kb (: a3 (A3 u3) (STV 1 1)))
!(compileadd kb (: a4 (A4 u4) (STV 1 1)))
!(compileadd kb (: r1 (Implication (A1 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb (: r2 (Implication (A2 $x) (B2 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r2b (Implication (B2 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb (: r3 (Implication (A3 $x) (B3 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r3b (Implication (B3 $x) (C3 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r3c (Implication (C3 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb (: r4 (Implication (A4 $x) (B4 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r4b (Implication (B4 $x) (C4 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r4c (Implication (C4 $x) (D4 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb (: r4d (Implication (D4 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb
   (: total
      (Implication
         (And (FoldAllTruth (And (Cand $v) (Leak $v)) (STV $s $_c) $s 0.0
                 (|-> ($acc $elem) (+ $acc $elem)) -> $sum)
              (Cand $u))
         (Total $u))
      (CTV (STV $sum 1.0) (STV $sum 1.0))))

(= (total-tv $budget)
   (let (: $_proof (Total u1) $tv) (car-atom (collapse (query $budget kb (: $prf (Total u1) $tv)))) $tv))

(= (close? $x $y) (< (abs-math (- $x $y)) 0.0001))

;; Before the fold is searched it has covered nothing and claims nothing.
!(test (let (STV $s $c) (total-tv 1) (and (close? $s 0.0) (close? $c 0.0))) true)

;; One member found while the search for more goes on: at least one more is
;; to come, half the confidence.
!(test (let (STV $s $c) (total-tv 4) (and (close? $s 0.4) (close? $c 0.5))) true)

;; The search goes on from where it stopped: two found, at least one to come.
!(test (let (STV $s $c) (total-tv 16) (and (close? $s 0.8) (close? $c 0.6666))) true)

;; Complete: the sum of all four, with the rule's confidence; u5, whose
;; search ended without a member, is not waited for.
!(test (let (STV $s $c) (total-tv 200) (and (close? $s 1.6) (> $c 0.999))) true)

;; A provisional conclusion gives way to a complete view of its statement.
;; The conclusion through the fold reads everything the other view reads and
;; more, so once the fold is complete it is kept over the other; while the
;; fold is partial, the other view is the value (before partial folds the
;; fold, not yet searched, read as empty and the value was 0 at confidence 1).
!(compileadd kb2 (: c1 (Cand u1) (STV 1 0.9)))
!(compileadd kb2 (: c2 (Cand u2) (STV 1 0.9)))
!(compileadd kb2 (: e1 (Extra u1) (STV 1 0.9)))
!(compileadd kb2 (: a1 (A1 u1) (STV 1 1)))
!(compileadd kb2 (: a2 (A2 u2) (STV 1 1)))
!(compileadd kb2 (: r1 (Implication (A1 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb2 (: r2 (Implication (A2 $x) (B2 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb2 (: r2b (Implication (B2 $x) (C2 $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd kb2 (: r2c (Implication (C2 $x) (Leak $x)) (CTV (STV 0.4 1) (STV 0.1 1))))
!(compileadd kb2
   (: total
      (Implication
         (And (FoldAllTruth (And (Cand $v) (Leak $v)) (STV $s $_c) $s 0.0
                 (|-> ($acc $elem) (+ $acc $elem)) -> $sum)
              (Cand $u)
              (Extra $u))
         (Total $u))
      (CTV (STV $sum 1.0) (STV $sum 1.0))))
!(compileadd kb2 (: prior (Implication (Cand $u) (Total $u)) (CTV (STV 0.5 1) (STV 0 1))))

(= (total2 $budget) (car-atom (collapse (query $budget kb2 (: $prf (Total u1) $tv)))))

!(test (let (: $proof (Total u1) (STV $s $_c)) (total2 4) (and (== $proof (by prior c1)) (close? $s 0.5))) true)
!(test (let (: $proof (Total u1) (STV $s $_c)) (total2 200) (and (== (car-atom $proof) by) (close? $s 0.8))) true)
