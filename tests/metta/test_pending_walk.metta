;; A query walks only the nodes whose search may still have work: a node
;; that is unexpanded or holds parked deliveries, deferred joins or deferred
;; rows, and every node above one (docs/metta/runtime_design_assumptions.md,
;; "Queries read what their roots reach"). Once a walk took the work, nothing
;; is pending, around cycles too.

!(import! &self ../../pettachainer/metta/petta_chainer)

!(set-backward-query-metrics true)

;; expansions and expanded nodes walked through by the last query
(: WalkCost Type)
(: walk-cost (-[det]-> Number Number WalkCost))

(: walked-query (-[det]-> Number KB AnnotatedStatement WalkCost))
(= (walked-query $steps $kb $goal)
   (let* (($_reset (begin-backward-query-metrics!))
          ($_answers (collapse (query $steps $kb $goal))))
      (walk-cost (query_metric_value expansions) (query_metric_value nodes-walked))))

;; A chain searched in full: asking again walks nothing.
!(compileadd chainKb (: c1 (Implication (P $x) (Q $x)) (STV 1.0 0.9)))
!(compileadd chainKb (: c2 (Implication (Q $x) (R $x)) (STV 1.0 0.9)))
!(compileadd chainKb (: f1 (P a) (STV 1.0 0.9)))
!(test (let (walk-cost $expanded $_walked) (walked-query 50 chainKb (: $p (R a) $tv)) (> $expanded 0)) true)
!(test (walked-query 50 chainKb (: $p (R a) $tv)) (walk-cost 0 0))

;; A rule added later starts on the node it concludes, (Q a), and its premise
;; is a new node: the walk goes down to it through the nodes above it and
;; expands it, and the next query finds nothing left.
!(compileadd chainKb (: c3 (Implication (S $x) (Q $x)) (STV 1.0 0.9)))
!(compileadd chainKb (: f2 (S a) (STV 1.0 0.9)))
!(test (let (walk-cost $expanded $walked) (walked-query 50 chainKb (: $p (R a) $tv)) (if (> $expanded 0) (> $walked 0) false)) true)
!(test (let (: $p $s $tv) (query 50 chainKb (: $p (R a) $tv)) $p) (by c2 (merge/revision (by c1 f1) (by c3 f2))))
!(test (walked-query 50 chainKb (: $p (R a) $tv)) (walk-cost 0 0))

;; Around a cycle every node reaches every other, so new work on it makes the
;; whole cycle pending, and taking the work leaves all of it idle.
!(compileadd cycKb (: s1 (Implication (Same $a $b) (Same $b $a)) (STV 1.0 0.9)))
!(compileadd cycKb (: f1 (Same A B) (STV 1.0 0.5)))
!(test (let (walk-cost $expanded $_walked) (walked-query 50 cycKb (: $p (Same B A) $tv)) (> $expanded 0)) true)
!(test (walked-query 50 cycKb (: $p (Same B A) $tv)) (walk-cost 0 0))
!(compileadd cycKb (: s2 (Implication (Link $a $b) (Same $a $b)) (STV 1.0 0.9)))
!(compileadd cycKb (: f2 (Link B A) (STV 1.0 0.9)))
!(test (let (walk-cost $expanded $walked) (walked-query 50 cycKb (: $p (Same B A) $tv)) (if (> $expanded 0) (> $walked 0) false)) true)
!(test (walked-query 50 cycKb (: $p (Same B A) $tv)) (walk-cost 0 0))

;; Deliveries a query could not make wait parked at their node, which stays
;; pending: a query whose walk allowance does not reach the node leaves them,
;; and one that reaches it makes them. Then nothing is pending.
!(compileadd parkKb (: g1 (Implication (Good $x) (Fine $x)) (STV 1.0 0.9)))
!(compileadd parkKb (: g2 (Implication (Fine $x) (Great $x)) (STV 1.0 0.9)))
!(compileadd parkKb (: m1 (Good m1) (STV 1.0 0.9)))
!(compileadd parkKb (: m2 (Good m2) (STV 1.0 0.9)))
!(compileadd parkKb (: m3 (Good m3) (STV 1.0 0.9)))
!(compileadd parkKb (: m4 (Good m4) (STV 1.0 0.9)))
!(compileadd parkKb (: m5 (Good m5) (STV 1.0 0.9)))
!(compileadd parkKb (: m6 (Good m6) (STV 1.0 0.9)))
!(compileadd parkKb (: m7 (Good m7) (STV 1.0 0.9)))
!(compileadd parkKb (: m8 (Good m8) (STV 1.0 0.9)))
!(compileadd parkKb (: m9 (Good m9) (STV 1.0 0.9)))
!(compileadd parkKb (: m10 (Good m10) (STV 1.0 0.9)))
!(compileadd parkKb (: m11 (Good m11) (STV 1.0 0.9)))
!(compileadd parkKb (: m12 (Good m12) (STV 1.0 0.9)))
!(compileadd parkKb (: m13 (Good m13) (STV 1.0 0.9)))
!(compileadd parkKb (: m14 (Good m14) (STV 1.0 0.9)))
!(compileadd parkKb (: m15 (Good m15) (STV 1.0 0.9)))
!(compileadd parkKb (: m16 (Good m16) (STV 1.0 0.9)))
!(compileadd parkKb (: m17 (Good m17) (STV 1.0 0.9)))
!(compileadd parkKb (: m18 (Good m18) (STV 1.0 0.9)))
!(compileadd parkKb (: m19 (Good m19) (STV 1.0 0.9)))
!(compileadd parkKb (: m20 (Good m20) (STV 1.0 0.9)))
!(compileadd parkKb (: m21 (Good m21) (STV 1.0 0.9)))
!(compileadd parkKb (: m22 (Good m22) (STV 1.0 0.9)))
!(compileadd parkKb (: m23 (Good m23) (STV 1.0 0.9)))
!(compileadd parkKb (: m24 (Good m24) (STV 1.0 0.9)))
!(compileadd parkKb (: m25 (Good m25) (STV 1.0 0.9)))
!(compileadd parkKb (: m26 (Good m26) (STV 1.0 0.9)))
!(compileadd parkKb (: m27 (Good m27) (STV 1.0 0.9)))
!(compileadd parkKb (: m28 (Good m28) (STV 1.0 0.9)))
!(compileadd parkKb (: m29 (Good m29) (STV 1.0 0.9)))
!(compileadd parkKb (: m30 (Good m30) (STV 1.0 0.9)))
!(walked-query 2 parkKb (: $p (Great $x) $tv))
!(walked-query 2 parkKb (: $p (Great $x) $tv))
!(walked-query 2 parkKb (: $p (Great $x) $tv))
!(test (> (match-count &sk_parked $_d) 0) true)
!(test (let (walk-cost $_expanded $walked) (walked-query 6 parkKb (: $p (Great $x) $tv)) (if (> $walked 0) (match-count &sk_parked $_d) -1)) 0)
!(test (walked-query 6 parkKb (: $p (Great $x) $tv)) (walk-cost 0 0))
