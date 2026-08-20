;; Frontier part algebra: the truth-value and admissibility semantics of a
;; conjunction frontier, independent of any scheduling order.
;;
;; This layer decides what a premise proof contributes to a partially
;; consumed (And ...) frontier — an independent part, a projection pooled
;; with other projections of the same source, or a poison value that forces
;; rejection — and what the folded TV, score, and remaining potential of a
;; part list are. It also holds the admissibility rules the scheduler
;; consults before feeding a proof to a frontier: cycle-key conditions (a
;; recursive proof must not be consumed by its own ancestors), the
;; shared-evidence allowance for compiler-generated joins, and which proof
;; representation (raw, merged, parent-conditioned) a bundle requires.
;;
;; It is a separate layer because these rules are the logical soundness of
;; conjunction evidence combination and must hold under any scheduling. The
;; file owns no spaces and mutates nothing; proof facts reach it only through
;; proof_store accessors, so the same inputs always yield the same answers.
;; The part row shapes are declared (for load order) in demand.metta, where
;; the pooling model is documented alongside them.

(: frontier-part-tv
   (-[semidet]-> (| FrontierPart UnpoolablePart) TV))
(= (frontier-part-tv $part)
   (case $part (
      ((indep-part $tv) $tv)
      ((pool-part $_base $btv $n $idxs $_ev $mtv)
         (if (== (list-len $idxs) $n) $btv $mtv))
      (unpoolable-part (empty)))))

(: frontier-parts-fold-acc
   (-[semidet]-> TV
       (List (| FrontierPart UnpoolablePart)) TV))
(= (frontier-parts-fold-acc $acc ()) $acc)
(= (frontier-parts-fold-acc $acc (cons $part $rest))
   (frontier-parts-fold-acc (AndFormula $acc (frontier-part-tv $part)) $rest))

(: frontier-parts-fold
   (-[semidet]->
       (List (| FrontierPart UnpoolablePart)) TV))
(= (frontier-parts-fold (cons $first $rest))
   (frontier-parts-fold-acc (frontier-part-tv $first) $rest))

(: frontier-premise-part
   (-[semidet]-> ProofSupport
       (| FrontierPart SkipPart UnpoolablePart)))
(= (frontier-premise-part $support)
   (let (proof-support $_score $evidence $contribution)
      $support
      (case $contribution (
         ((independent-contribution $tv)
            (indep-part $tv))
         ((projected-contribution $key $source-tv $arity $idx $marginal-tv)
            (pool-part $key $source-tv $arity
               ($idx) $evidence $marginal-tv))
         (skip-contribution skip-part)
         (unpoolable-contribution unpoolable-part)))))

(: frontier-parts-idx-union
   (-[det]-> (List Number) (List Number) (List Number)))
(= (frontier-parts-idx-union $a ()) $a)
(= (frontier-parts-idx-union $a (cons $i $rest))
   (frontier-parts-idx-union
      (if (stored-list-member? $i $a)
         $a
         (append-number $a $i))
      $rest))

(: frontier-pool-key
   (-[det]-> (| FrontierPart UnpoolablePart)
       (| ProofOutputKey NoPoolKey)))
(= (frontier-pool-key $part)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv) $key)
      ($_ no-pool-key))))

(: frontier-parts-same-pool
   (-[det]-> (List (| FrontierPart UnpoolablePart))
       ProofOutputKey (| FrontierPart NoPool)))
(= (frontier-parts-same-pool () $_key) no-pool)
(= (frontier-parts-same-pool (cons $head $rest) $key)
   (case $head (
      ((pool-part $head-key $btv $n $idxs $ev $mtv)
         (if (=alpha $head-key $key)
            (pool-part $head-key $btv $n $idxs $ev $mtv)
            (frontier-parts-same-pool $rest $key)))
      ($_other (frontier-parts-same-pool $rest $key)))))

(: frontier-parts-join-pool
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       FrontierPart
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-join-pool () $pool) (cons $pool ()))
(= (frontier-parts-join-pool (cons $head $rest) (pool-part $key $btv $n $idxs $ev $mtv))
   (if (=alpha (frontier-pool-key $head) $key)
      (let (pool-part $okey $obtv $on $oidxs $oev $omtv) $head
         (cons
            (pool-part $okey $obtv $on
               (frontier-parts-idx-union $oidxs $idxs)
               (list_to_set (append-evidence $oev $ev))
               $omtv)
            $rest))
      (cons $head (frontier-parts-join-pool $rest (pool-part $key $btv $n $idxs $ev $mtv)))))

(: frontier-parts-add
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart SkipPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(: frontier-parts-append-one
   (-[det]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-append-one () $part)
   (cons $part ()))
(= (frontier-parts-append-one
      (cons $head $rest) $part)
   (cons $head
      (frontier-parts-append-one $rest $part)))
(= (frontier-parts-add $parts $part)
   (case $part (
      (skip-part $parts)
      ((pool-part $base $btv $n $idxs $ev $mtv)
         (frontier-parts-join-pool $parts (pool-part $base $btv $n $idxs $ev $mtv)))
      ((indep-part $tv)
         (frontier-parts-append-one
            $parts (indep-part $tv)))
      (unpoolable-part
         (frontier-parts-append-one
            $parts unpoolable-part)))))

;; Projections score with their source's confidence: a partial pool's marginal
;; confidence (0 for a strength-0 source) says nothing about the completed
;; pool's, and would starve the frontier before the join that completes it.
(: frontier-part-score
   (-[det]-> (| FrontierPart SkipPart UnpoolablePart) Number Number))
(= (frontier-part-score $part $pscore)
   (case $part (
      ((pool-part $_base $btv $_n $_idxs $_ev $_mtv) (max $pscore (tv-confidence $btv)))
      ($_ $pscore))))

;; A partial pool's marginal TV can have zero confidence (strength-0 source),
;; which zeroes the remaining chain's expected confidence and would starve the
;; frontier before the join that completes the pool. The pool's source
;; confidence is the frontier's real potential.
(: frontier-pool-potential
   (-[det]-> (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-pool-potential ()) 0.0)
(= (frontier-pool-potential (cons $part $rest))
   (case $part (
      ((pool-part $_k $btv $n $idxs $_ev $_mtv)
         (if (< (list-len $idxs) $n)
            (max (tv-confidence $btv) (frontier-pool-potential $rest))
            (frontier-pool-potential $rest)))
      ($_ (frontier-pool-potential $rest)))))

(: frontier-remaining-score
   (-[det]-> AndBundle (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-remaining-score $bundle $parts)
   (max
      (premises-expected-confidence
         (copy_term (and-bundle-premises $bundle)))
      (frontier-pool-potential $parts)))

(: frontier-and-step-premise? (-[det]-> $premise Bool))
(= (frontier-and-step-premise? $prem)
   (if (is-expr $prem)
      (if (== (car-atom $prem) CPU)
         (== (car-atom (cdr-atom $prem)) AndFormula)
         false)
      false))

;; Pop the consumed premise AND its AndFormula step, binding the step's output
;; to the parts fold (the chain's pairwise application would double count the
;; pooled source). Yields () when the premise is not directly followed by its
;; AndFormula step; the caller then drops the proof as before.
(: frontier-pooled-bundle
   (-[semidet]-> AndBundle Number TV
       (| AndBundle (List $none))))
(= (frontier-pooled-bundle $bundle $pid $folded)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
         ((cons $prem (cons $step $rest))
            (if (frontier-and-step-premise? $step)
               (if (= $prem (proof-output-atom-by-id $pid))
                  (if (= (CPU AndFormula $_fargs $folded) $step)
                     (and-bundle $goal $rest)
                     ())
                  ())
               ()))
         ($_ ())))))

(: advance-frontier-bundle
   (-[semidet]-> AndBundle Number
       (| AndBundle (List $none))))
(= (advance-frontier-bundle $bundle $pid)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (() ())
           ((cons $prem $rest)
              (if (= $prem (proof-output-atom-by-id $pid))
                 (and-bundle $goal $rest) ()))))))

;; These compiler-generated joins keep their premise TVs separate instead of
;; combining them through AndFormula. Their premises may therefore share
;; evidence: total implication compares positive/refuting contexts, while a
;; member-inheritance sample pairs an antecedent membership with a consequent
;; that may itself have been derived from that antecedent. The resulting proof
;; still carries the union of both evidence sets, and normal cycle checks apply.
(: shared-evidence-frontier-proof? (-[det]-> $proof Bool))
(= (shared-evidence-frontier-proof? $proof)
   (case $proof (
      ((total-implication-frontier $_inner) true)
      ((inheritance-query-result $inner)
         (shared-evidence-frontier-proof? $inner))
      ((member-inheritance-sample $_antecedent $_consequent) true)
      ($_other false))))

(: frontier-allows-shared-evidence? (-[det]-> AndBundle Bool))
(= (frontier-allows-shared-evidence? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($_type $_kb $proof $_tv)
            (shared-evidence-frontier-proof? $proof))
         ($_other false)))))

(: frontier-needs-raw-proofs? (-[det]-> AndBundle Bool))
(= (frontier-needs-raw-proofs? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($_type $_kb $proof $_tv)
            (proof-term-conjunction-dependency?
               (brand Proof $proof)))
         ($_other false)))))

;; A premise proof joins the frontier's pool for its projection source when a
;; pool for that source already exists and any evidence overlap is fully
;; explained by it. The join applies with or without overlap: projections of
;; one source are never independent, and forward-chained materialization can
;; hide their shared provenance behind distinct fact atoms. Overlap not
;; explained by a pool keeps the double-counting rejection.
(: frontier-pool-join?
   (-[det]-> (| FrontierPart SkipPart UnpoolablePart) (List (| FrontierPart UnpoolablePart)) (List Evidence) (List Evidence) Bool))
(= (frontier-pool-join? $part $parts $seen $pev)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv)
         (let $existing (frontier-parts-same-pool $parts $key)
            (case $existing (
               (no-pool false)
               ((pool-part $_k $_btv2 $_n2 $_idxs2 $oev $_mtv2)
                  (evidence-subset?
                     (evidence-intersection
                        (fact-evidence-only $seen)
                        (fact-evidence-only $pev))
                     (fact-evidence-only $oev)))))))
      ($_ false))))

;; Select proof paths against the consumer's cycle key before equivalent outputs
;; are merged. A globally valid recursive proof must remain queryable, but it
;; cannot be allowed to poison an independent proof when the same proposition is
;; consumed by one of its own ancestors.
(: noncyclic-proof-source-step
   (-[semidet]-> Number (List (| ProofOutputKey ClosedGoalKey))
       (List Number) Number (List Number)))
(= (noncyclic-proof-source-step $consumer-gid $cycle-keys $acc $pid)
   (if (proof-depends-on-cycle-keys?
         $pid $consumer-gid $cycle-keys)
      $acc
      (cons $pid $acc)))

(: proof-depends-on-cycle-keys?
   (-[semidet]-> Number Number
       (List (| ProofOutputKey ClosedGoalKey)) Bool))
(= (proof-depends-on-cycle-keys? $_pid $_consumer-gid ()) false)
(= (proof-depends-on-cycle-keys?
      $pid $consumer-gid (cons $cycle-key $rest))
   (if (proof-depends-on-goal-seen?
         $pid $consumer-gid $cycle-key ())
      true
      (proof-depends-on-cycle-keys?
         $pid $consumer-gid $rest)))

(: noncyclic-proof-source-ids
   (-[semidet]-> Number (List (| ProofOutputKey ClosedGoalKey))
       Number (List Number)))
(= (noncyclic-proof-source-ids $consumer-gid $cycle-keys $source-gid)
   (reverse-number-list
      (proof-fold-flat-semidet
         (noncyclic-proof-source-step $consumer-gid $cycle-keys)
         ()
         (goal-live-proof-ids $source-gid))))

;; Compound goals are lowered into their child premises, so their proof DAG may
;; not contain a node for the compound itself. Include every recursively lowered
;; leaf in the consumer condition to retain the logical cycle boundary after
;; compilation.
(: compound-cycle-leaf-keys
   (-[det]-> Statement KBContext
       (List (| ProofOutputKey ClosedGoalKey))))
(= (compound-cycle-leaf-keys $type $kb)
   (if (compound-source? $type)
      (compound-cycle-leaf-list-keys
         (the (List Atom) (cdr-atom $type)) $kb)
      (cons
         (proof-output-key (quote ($type $kb))) ())))

(: compound-cycle-leaf-list-keys
   (-[det]-> (List Atom) KBContext
       (List (| ProofOutputKey ClosedGoalKey))))
(= (compound-cycle-leaf-list-keys () $_kb) ())
(= (compound-cycle-leaf-list-keys (cons $type $rest) $kb)
   (append-cycle-keys
      (compound-cycle-leaf-keys
         (brand Statement $type) $kb)
      (compound-cycle-leaf-list-keys $rest $kb)))

(: append-cycle-keys
   (-[det]-> (List (| ProofOutputKey ClosedGoalKey))
       (List (| ProofOutputKey ClosedGoalKey))
       (List (| ProofOutputKey ClosedGoalKey))))
(= (append-cycle-keys () $right) $right)
(= (append-cycle-keys (cons $key $rest) $right)
   (cons $key (append-cycle-keys $rest $right)))

(: frontier-cycle-keys
   (-[semidet]-> Number AndBundle
       (List (| ProofOutputKey ClosedGoalKey))))
(= (frontier-cycle-keys $parent-gid $bundle)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($root-key
          (candidate-cycle-key $parent-gid (rule $goal))))
      (case $goal (
         (($type $kb $proof $_tv)
            (the (List (| ProofOutputKey ClosedGoalKey))
               (cons $root-key
                  (if
                     (if (compound-source? (brand Statement $type))
                        (compound-reconstruction-proof?
                           (brand Proof $proof))
                        false)
                     (compound-cycle-leaf-keys
                        (brand Statement $type)
                        (brand KBContext $kb))
                     ()))))
         ($_other
            (the (List (| ProofOutputKey ClosedGoalKey))
               (cons $root-key ())))))))

(: proof-nested-head? (-[det]-> Proof Atom Bool))
(= (proof-nested-head? $proof $expected)
   (if (is-expr $proof)
      (let $outer-head (car-atom $proof)
         (if (is-expr $outer-head)
            (let $head (car-atom $outer-head)
               (if (is-var $head) false
                  (== $head $expected)))
            false))
      false))

(: bi-direction-proof-label? (-[det]-> Atom Bool))
(= (bi-direction-proof-label? $label)
   (if (is-expr $label)
      (let $head (car-atom $label)
         (if (is-var $head) false
            (if (== $head bi-forward) true
               (== $head bi-backward))))
      false))

(: bi-direction-proof? (-[det]-> Proof Bool))
(= (bi-direction-proof? $proof)
   (if (is-expr $proof)
      (let $head (car-atom $proof)
         (if (is-var $head) false
            (if (== $head by)
               (case (cdr-atom $proof) (
                  ((cons $label (cons $_source ()))
                     (bi-direction-proof-label? $label))
                  ($_other false)))
               false)))
      false))

(: compound-reconstruction-proof? (-[det]-> Proof Bool))
(= (compound-reconstruction-proof? $proof)
   (if (bi-direction-proof? $proof) true
      (proof-nested-head? $proof inverted)))

(: frontier-needs-conditioned-proofs? (-[det]-> AndBundle Bool))
(= (frontier-needs-conditioned-proofs? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($type $_kb $proof $_tv)
            (if (is-var $proof)
               false
               (if (proof-nested-head?
                     (brand Proof $proof) proj)
                  true
                  (if (compound-source? (brand Statement $type))
                     (compound-reconstruction-proof?
                        (brand Proof $proof))
                     false))))
         ($_other false)))))

(: frontier-compatible-source-ids
   (-[semidet]-> Number AndBundle Number (List Number)))
(= (frontier-compatible-source-ids $parent-gid $bundle $child-gid)
   (noncyclic-proof-source-ids
      $parent-gid
      (frontier-cycle-keys $parent-gid $bundle)
      $child-gid))

(: frontier-existing-proof-ids
   (-[semidet]-> Number AndBundle Number (List Number)))
(= (frontier-existing-proof-ids $parent-gid $bundle $gid)
   (if (frontier-needs-conditioned-proofs? $bundle)
      (let*
         (($compatible
             (frontier-compatible-source-ids
                $parent-gid $bundle $gid))
          ($representatives
             (proof-output-group-representative-pids $gid
                (proof-output-groups $compatible))))
         (if (frontier-needs-raw-proofs? $bundle)
            (list_to_set
               (append-numbers $compatible $representatives))
            $representatives))
      (if (frontier-needs-raw-proofs? $bundle)
         (list_to_set
            (append-numbers
               (goal-live-proof-ids $gid)
               (goal-merged-proof-ids $gid)))
         (goal-merged-proof-ids $gid))))
