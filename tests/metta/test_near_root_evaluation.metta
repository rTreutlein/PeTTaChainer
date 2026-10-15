!(import! &self ../../pettachainer/metta/petta_chainer)

;; Evaluation near a query's roots is bounded too: the rows and folds within
;; two steps of a root draw on a reserve of eight computations for each one the
;; query's need reached, and then on the allowance of two per step, like the
;; rows below them (docs/metta/runtime_design_assumptions.md, "Evaluation is
;; bounded too").

;; The rows and folds within two steps of a root the last query reached.
(: near-root-item-count (-[det]-> Number Atom Number))
(= (near-root-item-count $acc ($hash $key))
   (+ $acc
      (case $key (
         ((sk-key $_type $_kbctx)
            (length (collapse (match &sk_row ($hash $stored $rhash $_row) (if (=alpha $stored $key) $rhash (empty))))))
         ($_fold 1)))))

(: near-root-items (-[det]-> Number))
(= (near-root-items)
   (fold-flat near-root-item-count 0
      (collapse (match &sk_needed ($hash $key $depth) (if (<= $depth 2) ($hash $key) (empty))))))

!(set-backward-query-metrics true)

;; Relations over five objects closed under symmetry and transitivity: the
;; rows near the root read each other through inverted rules, and each change
;; schedules their readers again.
!(compileadd relKb (: r1 (Implication (Same $a $b) (Same $b $a)) (STV 1.0 0.9)))
!(compileadd relKb (: r2 (Implication (And (Same $a $c) (Same $c $b)) (Same $a $b)) (STV 1.0 0.9)))
!(compileadd relKb (: r3 (Implication (Opposite $a $b) (Opposite $b $a)) (STV 1.0 0.9)))
!(compileadd relKb (: r4 (Implication (And (Opposite $a $c) (Opposite $c $b)) (Same $a $b)) (STV 1.0 0.9)))
!(compileadd relKb (: f1 (Same A1 B1) (STV 1.0 0.9)))
!(compileadd relKb (: f2 (Same A1 C1) (STV 1.0 0.9)))
!(compileadd relKb (: f3 (Opposite A1 B2) (STV 1.0 0.9)))
!(compileadd relKb (: f4 (Opposite A1 C2) (STV 1.0 0.9)))

!(begin-backward-query-metrics!)
!(test (let (: $p $t $tv) (query 25 relKb (: $p (Same C1 B1) $tv)) $tv) (STV 1.0 0.8999998199501539))
!(test (<= (query_metric_value row-computes) (+ (* 2 25) (* 8 (near-root-items)))) true)

;; A query without budget has no allowance and still brings what its root
;; reads current: a new fact reaches it from the reserve alone.
!(compileadd relKb (: f5 (Same C1 D1) (STV 1.0 0.9)))
!(begin-backward-query-metrics!)
!(test (let (: $p $t $tv) (query 0 relKb (: $p (Same D1 C1) $tv)) $tv) (STV 1.0 0.8999999461940172))
!(test (<= (query_metric_value row-computes) (* 8 (near-root-items))) true)
