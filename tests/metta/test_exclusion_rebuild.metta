!(import! &self ../../pettachainer/metta/petta_chainer)

;; C1 reads the two independent facts through a directed cycle. Every
;; exclusion miss is scheduled; a result never falls back to an older view.
!(compileadd contextCycleKb (: mf (M a) (STV 1 0.8)))
!(compileadd contextCycleKb (: xf (X a) (STV 1 0.8)))
!(compileadd contextCycleKb (: (no_inverse xm) (Implication (X a) (M a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd contextCycleKb (: (no_inverse mb) (Implication (M a) (B a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd contextCycleKb (: (no_inverse bx) (Implication (B a) (X a)) (CTV (STV 1 1) (STV 0 1))))
!(test (let (: $_p $_type (STV $s $c)) (query 200 contextCycleKb (: $p (X a) $tv))
   (and (< (abs-math (- $s 1)) 1e-12) (< (abs-math (- $c 0.888849375588311)) 1e-12))) true)
!(test (let (: $_p $_type (STV $s $c)) (query 200 contextCycleKb (: $p (B a) $tv))
   (and (< (abs-math (- $s 1)) 1e-12) (< (abs-math (- $c 0.8887901013457523)) 1e-12))) true)

;; Every published row/class value remains admissible under its recorded
;; cuts. The empty class is the ordinary view in this same store.
!(test
   (collapse (match &sk_context ($_digest $_id $_h (sk-key $_type (contextCycleKb MAIN Nil)) $_r $_seq $cuts $cuts $deps $_v true)
      (if (deps-meet? $cuts $deps) bad (empty))))
   ())
!(test (not (== (collapse (match &sk_context ($_d $_id $_h (sk-key (X a) (contextCycleKb MAIN Nil)) $_r $_q () () $_deps $_v true) true)) ())) true)

!(begin-backward-query-metrics!)
!(query 200 contextCycleKb (: $p (X a) $tv))
!(query 200 contextCycleKb (: $p (B a) $tv))
!(test (query_metric_value row-computes) 0)
!(test (query_metric_value context-nodes-created) 0)
!(test (query_metric_value merged-cache-misses) 0)
