!(import! &self ../../pettachainer/metta/petta_chainer)

;; Two completion views share a derived consequent. Neither may throw away
;; the target's independent direct claims while conditioning is unpaid.
;; Construct the views at the merge boundary so no query can pay the cut.
!(compileadd fallbackKb (: uncertain (Shared q) (STV 0.6 0.8)))
!(query 1 fallbackKb (: $p (Shared q) $tv))

(: fallback-view (-[det]-> Proof Number Number Number SkeletonValue))
(= (fallback-view $proof $s $c $deps)
   (sk-val (assemble-runtime-fact (Target q) (fallbackKb MAIN Nil) $proof (STV $s $c))
      (evidence-set (the (List Evidence) (cons (fact-evidence-entry (fallbackKb MAIN Nil) $proof (Target q))
         (if (== $deps 0) () (cons (fact-evidence-entry (fallbackKb MAIN Nil) uncertain (Shared q)) ()))))) $deps))

(: fallback-views (-[det]-> (List SkeletonValue)))
(= (fallback-views)
   (let* (($shared (deps-key (index-hash (sk-key (Shared q) (fallbackKb MAIN Nil)))))
          ($a (fallback-view (brand Proof direct-a) 0.1 0.8 0))
          ($b (fallback-view (brand Proof direct-b) 0.3 0.8 0))
          ($c (fallback-view (brand Proof ((antecedent-completion first 1 with cpu (prior (STV 0.5 0.9))) observation-a)) 0.8 0.85 $shared))
          ($d (fallback-view (brand Proof ((antecedent-completion second 1 with cpu (prior (STV 0.5 0.9))) observation-b)) 0.9 0.9 $shared)))
      (cons $a (cons $b (cons $c (cons $d ()))))))

;; The component's best representative is d. Both independent claims survive
;; in the result, exactly as merging a, b, d without the overlapping c.
!(test
   (let* (((cons $a (cons $b (cons $_c (cons $d ())))) (fallback-views))
          ($expected (sk-merge-step true () (sk-merge-step true () $a $b) $d)))
      (== $expected (sk-key-fallback () (fallback-views)))) true)

;; All 24 orders give the identical proof, TV, evidence and dependencies.
(: fallback-permutations (-[det]-> (List SkeletonValue) (List (List SkeletonValue))))
(= (fallback-permutations (cons $a (cons $b (cons $c (cons $d ())))))
   (cons (cons $a (cons $b (cons $c (cons $d ()))))
   (cons (cons $a (cons $b (cons $d (cons $c ()))))
   (cons (cons $a (cons $c (cons $b (cons $d ()))))
   (cons (cons $a (cons $c (cons $d (cons $b ()))))
   (cons (cons $a (cons $d (cons $b (cons $c ()))))
   (cons (cons $a (cons $d (cons $c (cons $b ()))))
   (cons (cons $b (cons $a (cons $c (cons $d ()))))
   (cons (cons $b (cons $a (cons $d (cons $c ()))))
   (cons (cons $b (cons $c (cons $a (cons $d ()))))
   (cons (cons $b (cons $c (cons $d (cons $a ()))))
   (cons (cons $b (cons $d (cons $a (cons $c ()))))
   (cons (cons $b (cons $d (cons $c (cons $a ()))))
   (cons (cons $c (cons $a (cons $b (cons $d ()))))
   (cons (cons $c (cons $a (cons $d (cons $b ()))))
   (cons (cons $c (cons $b (cons $a (cons $d ()))))
   (cons (cons $c (cons $b (cons $d (cons $a ()))))
   (cons (cons $c (cons $d (cons $a (cons $b ()))))
   (cons (cons $c (cons $d (cons $b (cons $a ()))))
   (cons (cons $d (cons $a (cons $b (cons $c ()))))
   (cons (cons $d (cons $a (cons $c (cons $b ()))))
   (cons (cons $d (cons $b (cons $a (cons $c ()))))
   (cons (cons $d (cons $b (cons $c (cons $a ()))))
   (cons (cons $d (cons $c (cons $a (cons $b ()))))
   (cons (cons $d (cons $c (cons $b (cons $a ()))))
      ())))))))))))))))))))))))))

(: fallback-order-step (-[semidet]-> SkeletonValue Bool (List SkeletonValue) Bool))
(= (fallback-order-step $expected $ok $order)
   (if $ok
      (let* (($key (sk-key (Target q) (fallbackKb MAIN Nil)))
             ($actual (sk-merge-key (index-hash $key) $key sk-any-filter () () $order)))
         (if (== $expected (sk-key-fallback () $order)) (== $expected $actual) false))
      false))
!(test (fold-semidet (fallback-order-step (sk-key-fallback () (fallback-views))) true
         (fallback-permutations (fallback-views))) true)

;; A low-confidence bridge still joins both components after it loses the
;; representative contest. Discarding its dependencies would split the graph.
!(compileadd fallbackKb (: uncertain-r (Shared r) (STV 0.4 0.8)))
!(query 1 fallbackKb (: $p (Shared r) $tv))
!(test
   (let* (($q (deps-key (index-hash (sk-key (Shared q) (fallbackKb MAIN Nil)))))
          ($r (deps-key (index-hash (sk-key (Shared r) (fallbackKb MAIN Nil)))))
          ($a (fallback-view (brand Proof a) 0.2 0.8 $q))
          ($b (fallback-view (brand Proof b) 0.7 0.9 $r))
          ($c (fallback-view (brand Proof c) 0.4 0.2 (deps-union $q $r)))
          ($d (fallback-view (brand Proof d) 0.3 0.8 0))
          ($values (cons $a (cons $b (cons $c (cons $d ())))))
          ($expected (sk-key-fallback () (cons $b (cons $d ())))))
      (fold-semidet (fallback-order-step $expected) true (fallback-permutations $values))) true)
