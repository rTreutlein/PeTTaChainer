!(import! &self petta_chainer)

;; ===========================================================================
;; Live re-evaluation over the existing proof store (no storage change)
;;
;; Key finding: the formula that produced a proof's TV is ALREADY in the store.
;; Every rule proof's children are [premise-proofs..., formula-CPU-proofs...],
;; and each CPU child holds its formula with operands and constants, e.g.
;;   (CPU CTVFormula ((STV 0.5 1.0) (CTV (STV 0.6 0.9) (STV 0.0 1.0))) (STV 0.3 0.95))
;; The conclusion TV is the last CPU's result. So lifting-merge needs no new
;; per-node storage: re-evaluation walks the existing DAG, overriding one leaf
;; fact's TV, and recomputes the CPU chain.
;;
;; Caveat: this prototype substitutes operands by value. When wired into the
;; live merge it should substitute structurally (at each formula's known input
;; positions) to avoid a premise TV colliding with a constant sub-term.
;; ===========================================================================

(= (subst-val $old $new $term)
   (if (== $term $old) $new
      (if (is-expr $term) (map-flat (subst-val $old $new) $term) $term)))
(= (apply-substs () $term) $term)
(= (apply-substs (cons ($old $new) $rest) $term)
   (apply-substs $rest (subst-val $old $new $term)))

(= (cpu-child? $pid) (if (= (proof-output-atom $pid) (CPU $_f $_a $_r)) true false))
(= (partition-children () $prem $cpu) ($prem $cpu))
(= (partition-children (cons $pid $rest) $prem $cpu)
   (if (cpu-child? $pid)
      (partition-children $rest $prem (append $cpu ($pid)))
      (partition-children $rest (append $prem ($pid)) $cpu)))

(= (premise-substs () $_key $_ov) ())
(= (premise-substs (cons $pid $rest) $key $ov)
   (let* ((($_t $_k $_p $old) (proof-output-atom $pid))
          ($new (reeval-proof $pid $key $ov)))
      (cons ($old $new) (premise-substs $rest $key $ov))))

(= (reeval-cpu-chain () $_substs $last) $last)
(= (reeval-cpu-chain (cons $pid $rest) $substs $_last)
   (let* (((CPU $f $args $oldres) (proof-output-atom $pid))
          ($nres (reduce (cpu-call 1 $f (apply-substs $substs $args)))))
      (reeval-cpu-chain $rest (append $substs (($oldres $nres))) $nres)))

;; re-evaluate proof $pid with the leaf whose output-key = $key overridden to $ov
(= (reeval-proof $pid $key $ov)
   (let $output (proof-output-atom $pid)
      (if (= $output ($type $kb $prf $tv))
         (if (=alpha (candidate-output-key $output) $key) $ov
            (let* ((($prem $cpu) (partition-children (proof-children-by-id $pid) () ())))
               (if (== $cpu ()) $tv
                  (reeval-cpu-chain $cpu (premise-substs $prem $key $ov) $tv))))
         $tv)))

(= (residual-ctv $pid $key)
   (CTV (reeval-proof $pid $key (STV 1.0 1.0)) (reeval-proof $pid $key (STV 0.0 1.0))))

!(compileadd k (: a (A i) (STV 0.5 1.0)))
!(compileadd k (: ab1 (Implication (Premises (A $x)) (Conclusions (B $x))) (CTV (STV 0.6 0.9) (STV 0.0 1.0))))
!(let $r (chainer 30 ((B i) (k MAIN Nil) $prf $tv)) done)

;; the rule proof (ab1 a), found by its token rather than a hardcoded pid
(= (ab1-pid)
   (match &proof ($pid $g $out (rule ((B i) $kb (ab1 $_arg) $_tv)) $sc $ev $ch) $pid))

;; no override reproduces the stored TV
!(test (let $p (car-atom (collapse (ab1-pid))) (reeval-proof $p ((Nothing n) (k MAIN Nil)) (STV 9 9)))
   (STV 0.3 0.95))

;; overriding A recovers the residual implication, matching the prototype
!(test (let $p (car-atom (collapse (ab1-pid))) (residual-ctv $p ((A i) (k MAIN Nil))))
   (CTV (STV 0.6 0.9) (STV 0.0 1.0)))
