!(import! &self ../../pettachainer/metta/petta_chainer)

;; The first temporal premise ranges over all links. A search started for a
;; future outcome used to keep extending that prefix after the outcome was
;; known, leaving a waiter for every later link before the second link failed.
!(set-rule-refinement retireKb true)
!(set-positive-only-predicate retireKb Next)
!(set-positive-only-predicate retireKb At)
!(compileadd retireKb (: r (Implication (And (Next $p $t) (Next $t $u) (At left $p) (At right $t)) (Ball right $u)) (STV 0.5 0.01)))
!(compileadd retireKb (: n1 (Next d1 d2) (STV 1 1)))
!(compileadd retireKb (: a1 (At left d1) (STV 1 1)))
!(compileadd retireKb (: a2 (At right d2) (STV 1 1)))
!(query 100 retireKb (: $p (Ball right d3) $tv))
!(test (> (match-count &sk_wait ($_h $_n (sk-partial $_o $_r ((Ball right d3) (retireKb MAIN Nil) $_p $_tv) $_d $_remaining $_keys))) 0) true)
!(compileadd retireKb (: closed (Ball right d3) (STV 0 1)))
!(test (query 0 retireKb (: $p (Ball right d3) $tv)) (: closed (Ball right d3) (STV 0 1)))
!(test (match-count &sk_wait ($_h $_n (sk-partial $_o $_r ((Ball right d3) (retireKb MAIN Nil) $_p $_tv) $_d $_remaining $_keys))) 0)
!(compileadd retireKb (: n2 (Next d3 d4) (STV 1 1)))
!(compileadd retireKb (: n3 (Next d4 d5) (STV 1 1)))
!(test (query 100 retireKb (: $p (Ball right d3) $tv)) (: closed (Ball right d3) (STV 0 1)))
!(test (match-count &sk_wait ($_h $_n (sk-partial $_o $_r ((Ball right d3) (retireKb MAIN Nil) $_p $_tv) $_d $_remaining $_keys))) 0)
!(test (query 0 retireKb (: $p (Next d1 d2) $tv)) (: n1 (Next d1 d2) (STV 1 1)))

;; Known true behaves the same way. A fractional confidence-1 fact does not:
;; its backward views are still required by conditioning (14147152).
!(compileadd retireKb (: true (Ball right d4) (STV 1 1)))
!(test (query 100 retireKb (: $p (Ball right d4) $tv)) (: true (Ball right d4) (STV 1 1)))
!(test (sk-known-conclusion? ((Ball right d4) (retireKb MAIN Nil) $p $tv)) true)
!(compileadd retireKb (: probability (Ball right d5) (STV 0.4 1)))
!(test (sk-known-conclusion? ((Ball right d5) (retireKb MAIN Nil) $p $tv)) false)
