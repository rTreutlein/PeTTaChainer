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

;; A fold reads a member whose row derived nothing while that row waits to be
;; computed again (here a soft degradation history the antecedent completions
;; of runs read, in an Assuming context): the fold is complete over no member
;; for a moment. When the allowance then leaves the row stale, the fold goes
;; stale and its reader must cease reporting a complete empty fold. A missing
;; context node contributes no answer until the allowance can compute it.
;; Before a8ab91a6 the reader was held stale with the complete view,
;; (Value t1 0.0) at confidence 0.9997 (SupplyNet stage 4, gap 4).
!(set-complete-predicate recomputeKb P)
!(compileadd recomputeKb (: persist (Implication (And (Next $p $t) (D $p)) (D $t)) (CTV (STV 0.75 1) (STV 0.1 1))))
!(compileadd recomputeKb (: runs (Implication (And (Not (D $t)) (On $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd recomputeKb (: (no_inverse out) (Implication (And (Val $v) (P $t)) (Out $t $v)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd recomputeKb (: (no_inverse value) (Implication (And (Decision $t) (FoldAllTruth (Out $t $v) (STV $s $_c) (Weighted $s $v) 0.0 (|-> ($acc (Weighted $p $x)) (+ $acc (* $p $x))) -> $g)) (Value $t $g)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd recomputeKb (: val (Val 4) (STV 1 1)))
!(compileadd recomputeKb (: d-h1 (D h1) (STV 0.2 0.9)))
!(compileadd recomputeKb (: p-h1 (P h1) (STV 0.8 0.9)))
!(compileadd recomputeKb (: on-h1 (On h1) (STV 1 1)))
!(compileadd recomputeKb (: next-h2 (Next h1 h2) (STV 1 1)))
!(compileadd recomputeKb (: d-h2 (D h2) (STV 0.2 0.9)))
!(compileadd recomputeKb (: p-h2 (P h2) (STV 0.8 0.9)))
!(compileadd recomputeKb (: on-h2 (On h2) (STV 1 1)))
!(compileadd recomputeKb (: next-h3 (Next h2 h3) (STV 1 1)))
!(compileadd recomputeKb (: d-h3 (D h3) (STV 0.8 0.9)))
!(compileadd recomputeKb (: p-h3 (P h3) (STV 0.2 0.9)))
!(compileadd recomputeKb (: on-h3 (On h3) (STV 1 1)))
!(compileadd recomputeKb (: next-h4 (Next h3 h4) (STV 1 1)))
!(compileadd recomputeKb (: d-h4 (D h4) (STV 0.8 0.9)))
!(compileadd recomputeKb (: p-h4 (P h4) (STV 0.2 0.9)))
!(compileadd recomputeKb (: on-h4 (On h4) (STV 1 1)))
!(compileadd recomputeKb (: next-h5 (Next h4 h5) (STV 1 1)))
!(compileadd recomputeKb (: d-h5 (D h5) (STV 0.2 0.9)))
!(compileadd recomputeKb (: p-h5 (P h5) (STV 0.8 0.9)))
!(compileadd recomputeKb (: on-h5 (On h5) (STV 1 1)))
!(compileadd recomputeKb (: next-h6 (Next h5 h6) (STV 1 1)))
!(compileadd recomputeKb (: d-h6 (D h6) (STV 0.2 0.9)))
!(compileadd recomputeKb (: p-h6 (P h6) (STV 0.8 0.9)))
!(compileadd recomputeKb (: on-h6 (On h6) (STV 1 1)))
!(compileadd recomputeKb (: next-t1 (Next h6 t1) (STV 1 1)))

!(test
   (case (collapse (query 16 recomputeKb (: $p (Assuming (And (Decision t1) (On t1)) (Value t1 $g)) $tv))) (
      (() true)
      (((: $_proof (Assuming $_facts (Value t1 $value)) (STV $_s $confidence)))
         (if (== $value 0.0) (<= (the Number $confidence) 0.0) true))))
   true)
!(test
   (let (: $_proof (Assuming $_facts (Value t1 $value)) (STV $_s $confidence))
      (query 400 recomputeKb (: $p (Assuming (And (Decision t1) (On t1)) (Value t1 $g)) $tv))
      (and (> (the Number $value) 0.0) (> (the Number $confidence) 0.0)))
   true)
