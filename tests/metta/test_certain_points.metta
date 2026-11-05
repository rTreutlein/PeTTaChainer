!(import! &self ../../pettachainer/metta/petta_chainer)

;; A certain value is a point mass (zero variance), however long the chain.
;; Internally it keeps confidence 1; a computed point is published at .9999,
;; a stored source keeps its stated 1 (docs/metta/event_node_contract.md).
!(compileadd pointKb (: x0 (X0 e) (STV 1 1)))
!(compileadd pointKb (: r1 (Implication (X0 e) (X1 e)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd pointKb (: r2 (Implication (X1 e) (X2 e)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd pointKb (: r3 (Implication (X2 e) (X3 e)) (CTV (STV 1 1) (STV 0 1))))
!(test (query 50 pointKb (: $p (X3 e) $tv)) (: (by r3 (by r2 (by r1 x0))) (X3 e) (STV 1 0.9999)))
!(test (query 50 pointKb (: $p (X0 e) $tv)) (: x0 (X0 e) (STV 1 1)))
!(test (let (sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps)
          (sk-value (sk-key (X3 e) (kbctx pointKb)) sk-any-filter ()) $tv)
   (STV 1 1.0))

;; The written truth-value pattern constrains the published value, so a
;; computed point matches .9999 and not 1.
!(test (query 50 pointKb (: $p (X2 e) (STV 1 0.9999))) (: (by r2 (by r1 x0)) (X2 e) (STV 1 0.9999)))
!(test (collapse (query 50 pointKb (: $p (X2 e) (STV 1 1)))) ())

;; A source with a structured proof is still a source: it keeps confidence 1.
!(compileadd sourceKb (: (sensor source) (A e) (STV 0.3 1)))
!(test (query 0 sourceKb (: $p (A e) $tv)) (: (sensor source) (A e) (STV 0.3 1)))

;; Variables the statement shares with the truth-value pattern stay shared.
!(compileadd sharedKb (: bad (P 0.2) (STV 0.7 1)))
!(compileadd sharedKb (: good (P 0.7) (STV 0.7 1)))
!(test (collapse (query 0 sharedKb (: $p (P $s) (STV $s 1)))) ((: good (P 0.7) (STV 0.7 1))))
!(test (collapse (query 0 sharedKb (: $p (Not (P $s)) (STV $t 1)))) ((: (negated bad) (Not (P 0.2)) (STV 0.30000000000000004 1)) (: (negated good) (Not (P 0.7)) (STV 0.30000000000000004 1))))

;; Every reader of an evidence count reads a point first: it has no finite count.
!(test (ideal-var 0.5 1) 0.0)
!(test (ideal-conf-from-var 0.5 0.0) 1.0)
!(test (AndMarginalProjection (STV 0.4 1)) (STV 0.4 1.0))
!(test (AndMarginalProjection (STV 0.0 1)) (STV 0.0 0.0))
;; A point rule over finite base rates is never drained; three points stay.
!(test (ConsistentTriple (STV 0.4 0.9) (STV 0.2 0.9) (STV 0.99 1))
   (stv-triple (STV 0.21910974354654797 0.8736605530832511) (STV 0.2169186461110825 0.8924504731366664) (STV 0.99 1)))
!(test (ConsistentTriple (STV 0.4 1) (STV 0.2 1) (STV 0.99 1))
   (stv-triple (STV 0.4 1) (STV 0.2 1) (STV 0.99 1)))
!(test (merge-stvs (STV 0.7 1) (STV 0.2 0.9)) (STV 0.7 1))
!(set-forgetting 1 0.5)
!(test (sk-decayed-tv (STV 0.74 1)) (STV 0.74 1))
!(set-forgetting 0 1.0)
!(set-base-rate-smoothing pointKb true)
!(test (smoothed-base-rate-tv pointKb (STV 0.74 1)) (STV 0.74 1))
!(set-base-rate-smoothing pointKb false)
!(test (hm-decision pointKb () (hm-reviewed test (A e) (B e) 0 (STV 1 1))) true)
!(test (hm-informative? (CTV (STV 0.9 1) (STV 0.1 1)) 0.9 1) true)
!(test (hm-informative? (CTV (STV 0.1 1) (STV 0.1 1)) 0.1 1) false)
!(test (sk-fold-child-score () 1.0 ((base-rate pointKb (X0 $x) (STV 0.5 1) computed rate))) 0.0)
!(test (let $point (sk-value (sk-key (X3 e) (kbctx pointKb)) sk-any-filter ())
          (data (sk-change $point $point) (sk-change $point sk-none)))
   (data 0.0 1.0e300))
;; The forward minimum evidence never holds back a point.
!(set-forward-min-evidence 100)
!(compileadd forwardKb (: y0 (Y0 e) (STV 1 1)))
!(compileadd forwardKb (: q1 (Implication (Y0 e) (Y1 e)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd forwardKb (: q2 (Implication (Y1 e) (Y2 e)) (CTV (STV 1 1) (STV 0 1))))
!(test (let $seeds (collapse (match &kb ((Y0 e) (forwardKb MAIN Nil) $prf $tv) ((Y0 e) (forwardKb MAIN Nil) $prf $tv)))
          (let (($y1 $_c1 $_p1 $tv1) ($y2 $_c2 $_p2 $tv2))
             (forward-chain 50 forwardKb (the (List (Statement KBContext Proof TV)) $seeds))
             (data $y1 $tv1 $y2 $tv2)))
   (data (Y1 e) (STV 1 0.9999) (Y2 e) (STV 1 0.9999)))
