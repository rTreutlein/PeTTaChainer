!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule is not started when one of its premises can be proved only through
;; its own conclusion, the same instance of it (docs/metta/dormant_rules.md).

(: concluding-rows (-[det]-> Atom Number))
(= (concluding-rows $head)
   (list-len (collapse (match &sk_row ($_kh (sk-key ($head $_a) $_c) $_rh $_row) true))))

;; Consequence chains: C1 and C2 are derived only from A, so the inverted rules
;; C1 -> A and C2 -> C1 can only support themselves and stay dormant.
!(compileadd chainKb (: a1 (A x) (STV 0.8 0.9)))
!(compileadd chainKb (: ac1 (Implication (A $v) (C1 $v)) (CTV (STV 0.7 1.0) (STV 0.2 1.0))))
!(compileadd chainKb (: c1c2 (Implication (C1 $v) (C2 $v)) (CTV (STV 0.7 1.0) (STV 0.2 1.0))))
!(test (query 100 chainKb (: $p (A x) $tv)) (: a1 (A x) (STV 0.8 0.9)))
!(test (concluding-rows C1) 0)

;; A fact for C1 gives the inverted rule independent support: it wakes, and
;; the observation moves A.
!(compileadd chainKb (: c1fact (C1 x) (STV 1.0 1.0)))
!(test (case (query 100 chainKb (: $p (A x) $tv)) (((: $p (A x) (STV $s $c)) (> $c 0.9)))) True)

;; Recursion through the same predicate at another instance stays active.
!(compileadd pathKb (: e12 (Edge n1 n2) (STV 1.0 1.0)))
!(compileadd pathKb (: e23 (Edge n2 n3) (STV 1.0 1.0)))
!(compileadd pathKb (: base (Implication (Edge $a $b) (Path $a $b)) (STV 1.0 1.0)))
!(compileadd pathKb (: step (Implication (And (Path $a $b) (Edge $b $c)) (Path $a $c)) (STV 1.0 1.0)))
!(test (case (query 100 pathKb (: $p (Path n1 n3) $tv)) (((: $p (Path n1 n3) (STV $s $c)) $s))) 0.9999992413791272)

;; A settled rule supports its conclusion only through a certain stored fact
;; that settles its compound (docs/metta/connective_settling.md). Here (L x)
;; follows from (S x) itself, or from (N x) settling the And false; (N x) is
;; true, so it settles nothing, and the rule (L x) -> (S x) stays dormant:
;; neither (L x) nor (N x) is expanded.
(: expanded? (-[det]-> Atom Atom Bool))
(= (expanded? $kb $head)
   (not (== (collapse (match &sk_expanded ($_h (($head $_x) ($kb $_c $_v) $_p $_t)) true)) ())))
!(compileadd settleSleepKb (: nx (N x) (STV 1 1)))
!(compileadd settleSleepKb (: nsl (Implication (And (N $u) (S $u)) (L $u)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd settleSleepKb (: ls (Implication (L $u) (S $u)) (CTV (STV 0.8 1) (STV 0.3 1))))
!(test (query 100 settleSleepKb (: $p (S x) $tv)) ())
!(test (map-flat (expanded? settleSleepKb) (S L N)) (True False False))

;; A false (N x) settles the And: (L x) follows by the negative branch, and
;; (S x) from it.
!(compileadd settleWakeKb (: nx (N x) (STV 0 1)))
!(compileadd settleWakeKb (: nsl (Implication (And (N $u) (S $u)) (L $u)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd settleWakeKb (: ls (Implication (L $u) (S $u)) (CTV (STV 0.8 1) (STV 0.3 1))))
!(test (query 100 settleWakeKb (: $p (S x) $tv))
   (: (by ls (by nsl (settled nx))) (S x) (STV 0.35000000000000003 0.9999146445782099)))
