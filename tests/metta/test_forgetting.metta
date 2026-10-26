!(import! &self ../../pettachainer/metta/petta_chainer)

;; Off by default: advancing epochs freezes nothing.
!(compileadd keepKb (: a1 (A x) (STV 0.8 0.9)))
!(compileadd keepKb (: ab (Implication (A $v) (B $v)) (CTV (STV 0.9 0.9) (STV 0.1 0.9))))
!(test (query 50 keepKb (: $p (B x) $tv)) (: (by ab a1) (B x) (STV 0.7400000000000001 0.9136763682045383)))
!(advance-epoch)
!(advance-epoch)
!(test (query 50 keepKb (: $p (B x) $tv)) (: (by ab a1) (B x) (STV 0.7400000000000001 0.9136763682045383)))

;; A key idle for the horizon is frozen: what its rows derived becomes one
;; summary with a discounted confidence, and its stored facts stay.
!(set-forgetting 1 0.5)
!(compileadd fgKb (: a1 (A x) (STV 0.8 0.9)))
!(compileadd fgKb (: ab (Implication (A $v) (B $v)) (CTV (STV 0.9 0.9) (STV 0.1 0.9))))
!(compileadd fgKb (: bc (Implication (B $v) (C $v)) (CTV (STV 0.9 0.9) (STV 0.1 0.9))))
!(query 50 fgKb (: $p (C x) $tv))
!(advance-epoch)
!(advance-epoch)
!(test (case (query 50 fgKb (: $p (C x) $tv)) (((: (forgotten $_h $_e) (C x) $tv) $tv))) (STV 0.6920000000000002 0.8569735134802743))
!(test (query 50 fgKb (: $p (A x) $tv)) (: a1 (A x) (STV 0.8 0.9)))
;; Nothing reads the frozen keys any more, so the next epoch buries them;
;; the summary still answers a query.
!(advance-epoch)
!(test (collapse (match &sk_frozen ($h $k) $k)) ())
!(test (case (query 50 fgKb (: $p (C x) $tv)) (((: (forgotten $_h $_e) (C x) $tv) $tv))) (STV 0.6920000000000002 0.8569735134802743))
!(set-forgetting 0 1.0)

;; A rule's inversion into a compound waits until something besides the
;; rule's joins reads the compound (&sk_deferred_inversion). A replay expands
;; a forgotten node again, and that expansion defers its inversions anew: the
;; replay drops the node's waiting ones, so each stays once.
!(set-forgetting 1 0.5)
!(compileadd deferKb (: rx (Implication (Or (A $t) (B $t)) (X $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd deferKb (: rw (Implication (X $t) (W $t)) (CTV (STV 0.8 1) (STV 0.3 1))))
!(compileadd deferKb (: h1a (A h1) (STV 1 1)))
!(compileadd deferKb (: h1b (B h1) (STV 0 1)))
!(compileadd deferKb (: h1x (X h1) (STV 1 1)))
!(compileadd deferKb (: h2a (A h2) (STV 0 1)))
!(compileadd deferKb (: h2b (B h2) (STV 0 1)))
!(compileadd deferKb (: h2x (X h2) (STV 0 1)))
!(compileadd deferKb (: b (B k) (STV 0.3 0.9)))
!(compileadd deferKb (: xj (X j) (STV 0.8 0.9)))
!(query 200 deferKb (: $p (W k) $tv))
!(query 200 deferKb (: $p (Or (A j) (B j)) $tv))
!(advance-epoch)
!(advance-epoch)
!(query 200 deferKb (: $p (W k) $tv))
!(advance-epoch)
!(advance-epoch)
!(query 200 deferKb (: $p (W k) $tv))
!(test (collapse (match &sk_deferred_inversion ($h $r ($type (deferKb MAIN Nil) $_p $_tv) $m) $type))
   ((Or (A k) (B k)) (Or (A j) (B j))))
!(set-forgetting 0 1.0)
