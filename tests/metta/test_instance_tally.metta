!(import! &self ../../pettachainer/metta/petta_chainer)

;; A refined rule's truth is a tally of its instances' contributions
;; (docs/metta/hypothesis_rules.md, "Instance tallies"). A new instance moves
;; it at the next evaluation, whatever the query asks, and costs the same
;; however many instances came before; a review only reads it.

;; Two histories of one rule, 4 and 16 instances, three of four positive.
!(set-evidence-confidence-k 5)
!(set-backward-query-metrics true)

(: truth (-[semidet]-> KB Atom))
(= (truth $kb)
   (case (sk-key-value (sk-key (RuleTruth (Implication (A $x) (B $x))) ($kb MAIN Nil))) (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) $tv)
      ($_none none))))

!(set-rule-refinement shortKb true)
!(set-positive-only-predicate shortKb A)
!(compileadd shortKb (: h (Implication (A $x) (B $x)) (STV 0.5 0.02)))
!(compileadd shortKb (: a0 (A i0) (STV 1 1)))
!(compileadd shortKb (: b0 (B i0) (STV 0 1)))
!(compileadd shortKb (: a1 (A i1) (STV 1 1)))
!(compileadd shortKb (: b1 (B i1) (STV 1 1)))
!(compileadd shortKb (: a2 (A i2) (STV 1 1)))
!(compileadd shortKb (: b2 (B i2) (STV 1 1)))
!(compileadd shortKb (: a3 (A i3) (STV 1 1)))
!(compileadd shortKb (: b3 (B i3) (STV 1 1)))

!(set-rule-refinement longKb true)
!(set-positive-only-predicate longKb A)
!(compileadd longKb (: h (Implication (A $x) (B $x)) (STV 0.5 0.02)))
!(compileadd longKb (: a0 (A i0) (STV 1 1)))
!(compileadd longKb (: b0 (B i0) (STV 0 1)))
!(compileadd longKb (: a1 (A i1) (STV 1 1)))
!(compileadd longKb (: b1 (B i1) (STV 1 1)))
!(compileadd longKb (: a2 (A i2) (STV 1 1)))
!(compileadd longKb (: b2 (B i2) (STV 1 1)))
!(compileadd longKb (: a3 (A i3) (STV 1 1)))
!(compileadd longKb (: b3 (B i3) (STV 1 1)))
!(compileadd longKb (: a4 (A i4) (STV 1 1)))
!(compileadd longKb (: b4 (B i4) (STV 0 1)))
!(compileadd longKb (: a5 (A i5) (STV 1 1)))
!(compileadd longKb (: b5 (B i5) (STV 1 1)))
!(compileadd longKb (: a6 (A i6) (STV 1 1)))
!(compileadd longKb (: b6 (B i6) (STV 1 1)))
!(compileadd longKb (: a7 (A i7) (STV 1 1)))
!(compileadd longKb (: b7 (B i7) (STV 1 1)))
!(compileadd longKb (: a8 (A i8) (STV 1 1)))
!(compileadd longKb (: b8 (B i8) (STV 0 1)))
!(compileadd longKb (: a9 (A i9) (STV 1 1)))
!(compileadd longKb (: b9 (B i9) (STV 1 1)))
!(compileadd longKb (: a10 (A i10) (STV 1 1)))
!(compileadd longKb (: b10 (B i10) (STV 1 1)))
!(compileadd longKb (: a11 (A i11) (STV 1 1)))
!(compileadd longKb (: b11 (B i11) (STV 1 1)))
!(compileadd longKb (: a12 (A i12) (STV 1 1)))
!(compileadd longKb (: b12 (B i12) (STV 0 1)))
!(compileadd longKb (: a13 (A i13) (STV 1 1)))
!(compileadd longKb (: b13 (B i13) (STV 1 1)))
!(compileadd longKb (: a14 (A i14) (STV 1 1)))
!(compileadd longKb (: b14 (B i14) (STV 1 1)))
!(compileadd longKb (: a15 (A i15) (STV 1 1)))
!(compileadd longKb (: b15 (B i15) (STV 1 1)))

;; The first review folds every instance.
!(test (let (: $p $t $tv) (query 50 shortKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.7438779711799046 0.4506485110763119))
!(test (let (: $p $t $tv) (query 50 longKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.7484270482958006 0.7630535266350652))

;; A positive instance arrives. A query that does not ask for the truth, with
;; no budget, takes it: (3 + 1) / 5 revised with the prior. It costs three
;; row computations plus its two exclusion-class row computations, with
;; 4 instances before it as with 16.
!(compileadd shortKb (: anew (A new) (STV 1 1)))
!(compileadd shortKb (: bnew (B new) (STV 1 1)))
!(begin-backward-query-metrics!)
!(test (query 0 shortKb (: $p (A i0) $tv)) (: a0 (A i0) (STV 1 1)))
!(test (query_metric_value row-computes) 5)
!(test (truth shortKb) (STV 0.7940973727973338 0.5050260161337391))

!(compileadd longKb (: anew (A new) (STV 1 1)))
!(compileadd longKb (: bnew (B new) (STV 1 1)))
!(begin-backward-query-metrics!)
!(test (query 0 longKb (: $p (A i0) $tv)) (: a0 (A i0) (STV 1 1)))
!(test (query_metric_value row-computes) 5)
!(test (truth longKb) (STV 0.7631380054603719 0.7737740612150117))

;; A review then computes nothing: it reads the truth.
!(begin-backward-query-metrics!)
!(test (let (: $p $t $tv) (query 50 longKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.7631380054603719 0.7737740612150117))
!(test (query_metric_value row-computes) 0)
