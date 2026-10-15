!(import! &self ../../pettachainer/metta/petta_chainer)

;; #54: B was first built from revision(mf, xm(xf)). A reader excluding X
;; must rebuild mb(mf), even though no query ever stored that branch.
!(compileadd historyKb (: mf (M a) (STV 1 0.8)))
!(compileadd historyKb (: xf (X a) (STV 1 0.8)))
!(compileadd historyKb (: (no_inverse xm) (Implication (X $x) (M $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd historyKb (: (no_inverse mb) (Implication (M $x) (B $x)) (CTV (STV 1 1) (STV 0 1))))
!(collapse (query 200 historyKb (: $p (M a) $tv)))
!(collapse (query 200 historyKb (: $p (B a) $tv)))

;; Rebuilding has no free recursive expansion. An unpaid read keeps no
;; inadmissible view, and records staleness so its consumers can retry.
!(change-state! sk_eval_budget 0)
!(test
   (sk-value (sk-key (B a) (historyKb MAIN Nil)) sk-any-filter
      (cons (index-hash (sk-key (X a) (historyKb MAIN Nil))) ()))
   sk-none)
!(test (search-id-value sk_eval_budget) 0)
!(test
   (let $bh (index-hash (sk-key (B a) (historyKb MAIN Nil)))
      (match &sk_row ($bh $_key $rhash $_row)
         (space-row-present? &sk_stale ($bh $rhash))))
   true)

;; One paid row suffices: xm necessarily reads X and cannot help, while mb
;; reads M's authored mf. Only {M,B} are dependencies and mf is the evidence.
!(change-state! sk_eval_budget 1)
!(test
   (let* (($key (sk-key (B a) (historyKb MAIN Nil)))
          ($mh (index-hash (sk-key (M a) (historyKb MAIN Nil))))
          ($bh (index-hash $key))
          ($xh (index-hash (sk-key (X a) (historyKb MAIN Nil))))
          ((sk-val ($_type $_ctx $proof $tv) $ev $deps)
             (sk-value $key sk-any-filter (cons $xh ()))))
      ((sk-full-proof (the Proof $proof)) $tv
       (deps-within? (the Number $deps) (deps-union (deps-key $mh) (deps-key $bh)))
       (deps-meet? (cons $xh ()) (the Number $deps))
       (== $ev (evidence-set (cons (fact-evidence-entry (historyKb MAIN Nil) mf (M a)) ())))))
   ((by (no_inverse mb) mf) (STV 1 0.7999359651197002) true false true))
!(test (search-id-value sk_eval_budget) 0)

!(compileadd historyKb (: (no_inverse bx) (Implication (B $x) (X $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (query 200 historyKb (: $p (X a) $tv))
   (: (merge/revision xf (by (no_inverse bx) (by (no_inverse mb) mf))) (X a) (STV 1.0 0.888849375588311)))
