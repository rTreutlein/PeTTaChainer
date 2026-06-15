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
;; Re-evaluation is structural: it folds the premise proofs (identified by child
;; position, never by TV value) and re-applies the rule's CTV, so two premises
;; with equal TVs are never confused. It handles the standard implication shape
;; (premises -> And-fold -> CTVFormula); other shapes return the stored TV.
;; ===========================================================================

;; Split a rule proof's children into premise proofs and formula CPU proofs.
(= (cpu-child? $pid) (if (= (proof-output-atom $pid) (CPU $_f $_a $_r)) true false))
(= (split-pc () $prem $cpu) ($prem $cpu))
(= (split-pc (cons $pid $rest) $prem $cpu)
   (if (cpu-child? $pid)
      (split-pc $rest $prem (append $cpu ($pid)))
      (split-pc $rest (append $prem ($pid)) $cpu)))

(= (last-elem (cons $x ())) $x)
(= (last-elem (cons $x $rest)) (last-elem $rest))
(= (find-ctv ()) no-ctv)
(= (find-ctv (cons $arg $rest)) (if (= $arg (CTV $_p $_n)) $arg (find-ctv $rest)))
(= (and-fold (cons $tv ())) $tv)
(= (and-fold (cons $tv $rest)) (AndFormula $tv (and-fold $rest)))

(= (reeval-premises () $_k $_o) ())
(= (reeval-premises (cons $pid $rest) $key $ov)
   (cons (reeval-proof $pid $key $ov) (reeval-premises $rest $key $ov)))

;; Structural recompute: fold the premise proofs with And and apply the rule's
;; CTV. Each premise is identified by its child position, never by TV value, so
;; two premises with equal TVs are not confused. Standard implication shape only
;; (premises -> And-fold -> CTVFormula); any other shape returns the stored TV.
(= (reeval-rule $pid $key $ov $stored)
   (let* ((($prem $cpu) (split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) $stored
         (let* (((CPU $lastf $lastargs $_r) (proof-output-atom (last-elem $cpu)))
                ($ctv (find-ctv $lastargs)))
            (if (and (== $lastf CTVFormula) (not (== $ctv no-ctv)))
               (CTVFormula (and-fold (reeval-premises $prem $key $ov)) $ctv)
               $stored)))))

;; re-evaluate proof $pid with the leaf whose output-key = $key overridden to $ov
(= (reeval-proof $pid $key $ov)
   (let $output (proof-output-atom $pid)
      (if (= $output ($type $kb $prf $tv))
         (if (=alpha (candidate-output-key $output) $key) $ov (reeval-rule $pid $key $ov $tv))
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

;; Robustness: two premises with equal TVs. (B i) = (A i) AND (A2 i), both 0.5.
;; Factoring (A i) must leave (A2 i) at 0.5 -- by-value substitution would
;; confuse them; structural recompute keeps them distinct by child position.
!(compileadd c (: aa (A i) (STV 0.5 1.0)))
!(compileadd c (: a2 (A2 i) (STV 0.5 1.0)))
!(compileadd c (: rr (Implication (Premises (And (A $z) (A2 $z))) (Conclusions (B $z))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(let $r2 (chainer 40 ((B i) (c MAIN Nil) $prf $tv)) done)
(= (cc-pid) (match &proof ($pid $g $out (rule ((B i) $kb (rr $_) $_tv)) $sc $ev $ch) $pid))

!(test (let $p (car-atom (collapse (cc-pid))) (residual-ctv $p ((A i) (c MAIN Nil))))
   (CTV (STV 0.5 1.0) (STV 0.0 1.0)))
