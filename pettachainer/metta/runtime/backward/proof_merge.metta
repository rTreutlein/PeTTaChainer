;; Proof factoring, revision, dominance, candidate selection, and commitment.
;; ---------------------------------------------------------------------------
;; Lifting-merge: when several proofs of one grounded output share a premise,
;; pool them by factoring the shared premise out, revising the independent
;; residual implications, and re-applying the premise once. This recovers the
;; confidence that dominance would otherwise discard. The formula that produced
;; each proof's TV is already in the store (its CPU formula children), so a
;; proof is re-evaluated structurally with one leaf fact overridden. Exact for
;; standard implication-shaped proofs (premises -> And-fold -> CTVModusPonensFormula); any
;; other shape disables factoring for the group (revision/dominance instead).
;; ---------------------------------------------------------------------------

(: factor-cpu-child? (-[semidet]-> Number Bool))
(= (factor-cpu-child? $pid)
   (if (= (proof-output-atom-by-id $pid) (CPU $_f $_a $_r))
      true false))
(: factor-split-pc
   (-[semidet]-> (List Number) (List Number) (List Number)
       ((List Number) (List Number))))
(= (factor-split-pc () $p $c) ($p $c))
(= (factor-split-pc (cons $pid $rest) $p $c)
   (if (factor-cpu-child? $pid)
      (factor-split-pc $rest $p (append-number $c $pid))
      (factor-split-pc $rest (append-number $p $pid) $c)))
(: factor-last (-[semidet]-> (List Number) Number))
(= (factor-last (cons $x $rest))
   (if (== $rest ()) $x (factor-last $rest)))
(: factor-find-ctv
   (-[det]-> (List TV) (| CTVType NoCTV)))
(= (factor-find-ctv $values)
   (case $values (
      (() no-ctv)
      ((cons $a $rest)
         (case $a
            (((CTV $pos $neg) (CTV $pos $neg))
             ($_other (factor-find-ctv $rest)))))
      ($_other no-ctv))))
(: factor-and-fold
   (-[semidet]-> (List STVType) STVType))
(= (factor-and-fold (cons $tv $rest))
   (if (== $rest ()) $tv (AndFormula $tv (factor-and-fold $rest))))

(: factor-reeval-premises
   (-[semidet]-> (List Number) (List ProofOutputKey)
      TV (List STVType)))
(= (factor-reeval-premises () $_keys $_o) ())
(= (factor-reeval-premises (cons $pid $rest) $keys $o)
   (cons
      (the STVType (factor-reeval $pid $keys $o))
      (factor-reeval-premises $rest $keys $o)))

;; structural recompute: fold premise proofs (by child position) and re-apply ctv,
;; with every shared leaf (any key in $keys) overridden to $o
(: factor-reeval-rule
   (-[semidet]-> Number (List ProofOutputKey)
      TV TV  TV))
(= (factor-reeval-rule $pid $keys $o $stored)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) $stored
         (let* (((CPU $lf $la $_r)
                    (proof-output-atom-by-id (factor-last $cpu)))
                ($ctv
                   (factor-find-ctv
                      (the (List TV) $la))))
            (if (== $lf CTVModusPonensFormula)
               (case $ctv
                  (((CTV $pos $neg)
                      (CTVModusPonensFormula
                         (factor-and-fold
                            (factor-reeval-premises
                               $prem $keys $o))
                         (CTV $pos $neg)))
                   (no-ctv $stored)))
               $stored)))))

(: factor-reeval
   (-[semidet]-> Number (List ProofOutputKey) TV  TV))
(= (factor-reeval $pid $keys $o)
   (let $out (proof-output-atom-by-id $pid)
      (case $out (
         ((CPU $_formula $_arguments $_result)
            (empty))
         (($t $kb $prf $tv)
            (let $stored $tv
               (if
                  (is-alpha-member
                     (candidate-output-key $out) $keys)
                  $o
                  (factor-reeval-rule
                     $pid $keys $o $stored))))
         ($_other
            (empty))))))

(: factor-proof? (-[semidet]-> Number Bool))
(= (factor-proof? $pid)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) true
         (let* (((CPU $lf $la $_r)
                    (proof-output-atom-by-id (factor-last $cpu)))
                ($ctv
                   (factor-find-ctv
                      (the (List TV) $la))))
            (if (== $lf CTVModusPonensFormula)
               (if (== $ctv no-ctv) false
                  (factor-all? $prem))
               false)))))
(: factor-all? (-[semidet]-> (List Number) Bool))
(= (factor-all? ()) true)
(= (factor-all? (cons $pid $rest))
   (if (factor-proof? $pid)
      (factor-all? $rest)
      false))

(: factor-pid-facts (-[semidet]-> Number (List Evidence)))
(= (factor-pid-facts $pid)
   (fact-evidence-only
      (snd (proof-stats-by-id $pid))))

(: factor-shared-facts-step
   (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (factor-shared-facts-step $acc $pid)
   (evidence-intersection $acc (factor-pid-facts $pid)))

(: factor-shared-facts
   (-[semidet]-> (List Number) (List Evidence)))
(= (factor-shared-facts (cons $pid $rest))
   (proof-fold-flat-semidet
      factor-shared-facts-step
      (factor-pid-facts $pid) $rest))
(: factor-fact-key (-[semidet]-> Evidence ProofOutputKey))
(= (factor-fact-key (fact-ev $kb $prf $type))
   (proof-output-key (quote ($type $kb))))

(: factor-leaf-tv-work
   (-[semidet]-> (List Number) ProofOutputKey (| TV NoTV)))
(= (factor-leaf-tv-work () $_key) no-tv)
(= (factor-leaf-tv-work (cons $pid $rest) $key)
   (let $out (proof-output-atom-by-id $pid)
      (case $out (
         ((CPU $_formula $_arguments $_result)
            (factor-leaf-tv-work
               (append-numbers
                  (proof-children-by-id $pid) $rest) $key))
         (($t $kb $prf $tv)
            (if (=alpha (candidate-output-key $out) $key)
               (the TV $tv)
               (factor-leaf-tv-work
                  (append-numbers
                     (proof-children-by-id $pid) $rest) $key)))
         ($_other
            (factor-leaf-tv-work
               (append-numbers
                  (proof-children-by-id $pid) $rest) $key))))))

(: factor-leaf-tv
   (-[semidet]-> Number ProofOutputKey (| TV NoTV)))
(= (factor-leaf-tv $pid $key)
   (factor-leaf-tv-work ($pid) $key))

;; Residual of a proof w.r.t. the shared facts: probe their conjunction at
;; strength 1 (all shared leaves -> (1 1)) and 0 (all -> (0 1)). The conclusion
;; is linear in the shared conjunction's strength, so these two points give the
;; residual implication (conjunction-of-shared -> conclusion).
(: factor-revise-ctv
   (-[semidet]-> CTVType CTVType CTVType))
(= (factor-revise-ctv (CTV $p1 $n1) (CTV $p2 $n2)) (CTV (mergetvs $p1 $p2) (mergetvs $n1 $n2)))
(: factor-residual
   (-[semidet]-> Number (List ProofOutputKey) CTVType))
(= (factor-residual $pid $keys)
   (CTV
      (the STVType
         (factor-reeval $pid $keys (STV 1.0 1.0)))
      (the STVType
         (factor-reeval $pid $keys (STV 0.0 1.0)))))
(: factor-revise-residuals
   (-[semidet]-> (List CTVType) CTVType))
(= (factor-revise-residuals (cons $residual ())) $residual)
(= (factor-revise-residuals
      (cons $residual (cons $next $rest)))
   (factor-revise-ctv
      $residual
      (factor-revise-residuals
         (cons $next $rest))))

;; the shared facts' keys, and their real conjunction TV (And-fold of leaf TVs)
(: factor-shared-keys
   (-[semidet]-> (List Evidence) (List ProofOutputKey)))
(= (factor-shared-keys ()) ())
(= (factor-shared-keys (cons $f $rest)) (cons (factor-fact-key $f) (factor-shared-keys $rest)))
(: factor-required-leaf-tv
   (-[semidet]-> Number ProofOutputKey STVType))
;; A materialized leaf preserves upstream evidence keys without recreating
;; those upstream nodes in the new proof DAG. Let factoring decline cleanly
;; when one of those keys has no local TV to reconstruct.
(= (factor-required-leaf-tv $pid $key)
   (let $tv (factor-leaf-tv $pid $key)
      (case $tv
         ((no-tv (empty))
          ($_other (the STVType $_other))))))
(: factor-real-conj
   (-[semidet]-> Number (List ProofOutputKey) STVType))
(= (factor-real-conj $pid (cons $key ()))
   (factor-required-leaf-tv $pid $key))
(= (factor-real-conj $pid (cons $key (cons $next $rest)))
   (AndFormula
      (factor-required-leaf-tv $pid $key)
      (factor-real-conj $pid (cons $next $rest))))

;; round-trip check: re-applying a proof's residual to the real shared
;; conjunction must reproduce its stored strength. The 2-point probe captures
;; the conclusion's linear dependence on the shared conjunction exactly, so the
;; strength round-trips when the shared facts enter through one conjunction and
;; fails (disabling factoring) when they enter through different conjunctions.
;; Only strength is checked: confidence is non-linear under idealized
;; propagation, so the residual's re-derived branch confidences never reproduce
;; the stored confidence exactly -- checking it would reject every valid group.
(: factor-close? (-[det]-> Number Number Bool))
(= (factor-close? $x $y) (< (abs-math (- $x $y)) 0.000001))
;; single clause: a bare catch-all (= (factor-tv-close? $a $b) false) would also
;; match the (STV STV) case and make the result non-deterministic.
(: factor-tv-close? (-[det]-> TV TV Bool))
(= (factor-tv-close? $a $b)
   (if (= $a (STV $sa $_ca))
      (if (= $b (STV $sb $_cb))
         (factor-close? $sa $sb)
         false)
      false))
(: factor-roundtrip-one?
   (-[semidet]-> TV CTVType STVType Bool))
(= (factor-roundtrip-one? $stored $residual $conj)
   (let $rebuilt
      (CTVModusPonensFormula $conj $residual)
      (factor-tv-close? $stored $rebuilt)))

(: factor-roundtrip-residuals
   (-[semidet]-> (List Number) (List ProofOutputKey) STVType
      (Bool (List CTVType))))
(= (factor-roundtrip-residuals () $_keys $_conj) (data true ()))
(= (factor-roundtrip-residuals (cons $pid $rest) $keys $conj)
   (let* ((($_t $_k $_p $stored) (proof-output-atom-by-id $pid))
          ($residuals
             (collapse (once (factor-residual $pid $keys)))))
      (if (== $residuals ()) (data false ())
         (let $residual (car-atom $residuals)
            (if (factor-roundtrip-one?
                   (the TV $stored) $residual $conj)
               (let ($valid $rest-residuals)
                  (factor-roundtrip-residuals $rest $keys $conj)
                  (if $valid
                     (data true
                        (cons $residual $rest-residuals))
                     (data false ())))
               (data false ()))))))

(: factor-ref-of (-[semidet]-> Number Proof))
(= (factor-ref-of $pid)
   (let ($_t $_k $prf $_tv)
      (proof-output-atom-by-id $pid)
      (brand Proof $prf)))
(: factor-merged-prf (-[semidet]-> (List Number) Proof))
(= (factor-merged-prf (cons $pid ())) (factor-ref-of $pid))
(= (factor-merged-prf (cons $pid (cons $next $rest)))
   (brand Proof
      (merge/revision
         (factor-ref-of $pid)
         (factor-merged-prf (cons $next $rest)))))

;; Each proof's residual evidence (full evidence minus the shared facts) must be
;; pairwise disjoint, otherwise the proofs are not independent given the shared
;; premise -- e.g. two derivations that also share an uncertain rule, or one
;; whose evidence subsumes another's -- and pooling them would double count.
;; Such groups fall back to revision/dominance.
(: factor-residual-ev
   (-[semidet]-> Number (List Evidence) (List Evidence)))
(= (factor-residual-ev $pid $shared)
   (let ($_score $ev) (proof-stats-by-id $pid)
      (evidence-subtraction $ev $shared)))
(: factor-residual-evs
   (-[semidet]-> (List Number) (List Evidence)
       (List (List Evidence))))
(= (factor-residual-evs () $_shared) ())
(= (factor-residual-evs (cons $pid $rest) $shared)
   (cons (factor-residual-ev $pid $shared) (factor-residual-evs $rest $shared)))
(: factor-disjoint-from-all?
   (-[det]-> (List Evidence) (List (List Evidence)) Bool))
(= (factor-disjoint-from-all? $_ev ()) true)
(= (factor-disjoint-from-all? $ev (cons $other $rest))
   (if (evidence-sets-overlap? $ev $other)
      false
      (factor-disjoint-from-all? $ev $rest)))
(: factor-pairwise-disjoint?
   (-[det]-> (List (List Evidence)) Bool))
(= (factor-pairwise-disjoint? ()) true)
(= (factor-pairwise-disjoint? (cons $ev $rest))
   (if (factor-disjoint-from-all? $ev $rest)
      (factor-pairwise-disjoint? $rest)
      false))

;; Pool a group when: it shares at least one fact, every proof is standard
;; implication-shaped, the residual evidence sets are pairwise disjoint, and the
;; residuals round-trip (the shared facts factor through one conjunction).
;; Return a singleton only when factoring succeeds so the caller can preserve
;; the ordinary revision fallback without evaluating it eagerly.
(: factor-lifting-merge-output
   (-[semidet]-> (List Number)
      (List (Statement KBContext Proof TV))))
(= (factor-lifting-merge-output (cons $first-pid $rest-pids))
   (let $pids (cons $first-pid $rest-pids)
      (let $shared (factor-shared-facts $pids)
         (if (== $shared ()) ()
            (if (factor-all? $pids)
               (if
                  (factor-pairwise-disjoint?
                     (factor-residual-evs $pids $shared))
                  (let* (($keys (factor-shared-keys $shared))
                         ($conj
                            (factor-real-conj $first-pid $keys))
                         (($valid $residuals)
                            (factor-roundtrip-residuals
                               $pids $keys $conj)))
                     (if $valid
                        (let* (($pooled
                                  (once
                                     (factor-revise-residuals
                                        $residuals)))
                               ($merged-tv
                                  (CTVModusPonensFormula
                                     $conj $pooled))
                               (($type $kb $_p $_t)
                                  (proof-output-atom-by-id
                                     $first-pid))
                               ($merged-prf
                                  (factor-merged-prf $pids)))
                           (cons
                              (assemble-runtime-fact
                                 (brand Statement $type)
                                 (brand KBContext $kb)
                                 $merged-prf $merged-tv)
                              ()))
                        ()))
                  ())
               ())))))

(: merge-proof-id-output
   (-[semidet]-> (List Number)
       (| Goal (Statement KBContext Proof TV))))
(= (merge-proof-id-output (cons $pid $rest))
   ;; `and` is eager here.  Keep the singleton check outside it so a lone
   ;; cached derivation is never sent through multi-proof factoring: its leaf
   ;; provenance may refer to upstream facts which are intentionally absent
   ;; from this proof node's child list.
   (if (== $rest ())
      (proof-output-atom-by-id $pid)
      (let $factored
         (factor-lifting-merge-output (cons $pid $rest))
         (if (== $factored ())
            (proof-fold-flat-semidet merge-proof-id-output-step
               (proof-fact-output-by-id $pid) $rest)
            (car-atom $factored)))))

(: proof-id-evidence-step
   (-[semidet]-> (List Evidence) Number (List Evidence)))
(= (proof-id-evidence-step $acc $pid)
   (let ($_score $ev) (proof-stats-by-id $pid)
      (list_to_set (append-evidence $acc $ev))))

(: proof-id-evidence-list
   (-[semidet]-> (List Number) (List Evidence)))
(= (proof-id-evidence-list $pids)
   (proof-fold-flat-semidet proof-id-evidence-step () $pids))

(: proof-output-group-representative-pid
   (-[semidet]-> Number ProofOutputGroup Number))
(= (proof-output-group-representative-pid $gid (proof-output-group $_key $pids))
   (proof-output-group-representative-for-key
      (proof-goal-key-by-goal-id $gid)
      (proof-output-group $_key $pids)))

(: proof-output-group-representative-for-key
   (-[semidet]-> ProofGoalKey ProofOutputGroup Number))
(= (proof-output-group-representative-for-key
      $goal-key (proof-output-group $_key $pids))
   (case $pids (
      ((cons $pid ()) $pid)
      ($_
         (let*
            (($owner (merged-proof-group $goal-key))
             ($output (merge-proof-id-output $pids))
             ($score (term-confidence $output))
             ($ev (proof-id-evidence-list $pids))
             ($hits
                (collapse
                   (once
                      (match &proof
                         (stored-proof-row
                            $stored-pid $owner
                            $output (merged $output)
                            (proof-support $score $ev $_contribution) $pids)
                         $stored-pid)))))
            (if (== $hits ())
               (let*
                   (($pid (next-pid))
                   ($_store
                      (once
                         (chainer-add-atom &proof
                            (stored-proof-row
                               $pid $owner $output
                               (merged $output)
                               (proof-support $score $ev
                                  (proof-contribution
                                     (merged $output) $output))
                               $pids))))
                   ($_index (index-proof-result-for-goal! $goal-key $pid))
                   ($_parents (register-proof-parent-edges! $pid $pids)))
                  $pid)
               (car-atom $hits)))))))

(: proof-output-group-representative-pids
   (-[semidet]-> Number (List ProofOutputGroup) (List Number)))
(= (proof-output-group-representative-pids $_gid ()) ())
(= (proof-output-group-representative-pids $gid (cons $group $rest))
   (cons (proof-output-group-representative-pid $gid $group)
      (proof-output-group-representative-pids $gid $rest)))

(: proof-output-group-for-key-step
   (-[semidet]-> ProofOutputKey
       (List Number) Number (List Number)))
(= (proof-output-group-for-key-step $key $pids $pid)
   (if (=alpha (proof-output-key-by-id $pid) $key)
      (cons $pid $pids)
      $pids))

(: goal-live-proof-ids-for-output-key
   (-[semidet]-> Number ProofOutputKey (List Number)))
(= (goal-live-proof-ids-for-output-key $gid $key)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_pending)
            (goal-by-id $gid))
          ($goal-key (proof-goal-key-by-goal-id $gid)))
      (reverse-number-list
         (proof-fold-flat-semidet
            (goal-current-proof-step $goal) ()
            (current-proof-ids-for-goal-output-key
               $goal-key $key)))))

(: supersede-current-proof-result!
   (-[semidet]-> (List Number) Number (List $none)))
(: supersede-current-proof-result-without-replacement!
   (-[semidet]-> (List Number) (List $none)))
(= (supersede-current-proof-result! () $_new-pid) ())
(= (supersede-current-proof-result!
      (cons $old-pid $rest) $new-pid)
   (if (== $old-pid $new-pid) ()
      (supersede-current-proof-result-without-replacement!
         (cons $old-pid $rest))))

(= (supersede-current-proof-result-without-replacement! ()) ())
(= (supersede-current-proof-result-without-replacement!
      (cons $old-pid $_rest))
   (let* (($_mark
             (once
                (add-atom &proof_superseded ($old-pid))))
          ($_dependents
             (invalidate-proof-dependents! $old-pid)))
      ()))

(: refresh-current-proof-result!
   (-[semidet]-> ProofGoalKey ProofOutputKey (List $none)))
(= (refresh-current-proof-result! $goal-key $output-key)
   (let* (($old
             (collapse
                (once
                   (current-proof-result-id-for-output-key
                      $goal-key $output-key))))
          ($pids
             (current-proof-ids-for-goal-output-key
                $goal-key $output-key)))
      (if (== $pids ())
         (let* (($_remove
                   (remove-current-proof-result!
                      $goal-key $output-key))
                ($_supersede
                   (supersede-current-proof-result-without-replacement!
                      $old))
                ($_clean
                   (clear-current-proof-result-dirty!
                      $goal-key $output-key)))
            ())
         (let* (($new-pid
                   (proof-output-group-representative-for-key $goal-key
                      (proof-output-group $output-key $pids)))
                ($_replace
                   (index-current-proof-result!
                      $goal-key $output-key $new-pid))
                ($_supersede
                   (supersede-current-proof-result! $old $new-pid))
                ($_clean
                   (clear-current-proof-result-dirty!
                      $goal-key $output-key)))
            ()))))

(: refresh-current-proof-result-step!
   (-[semidet]-> ProofGoalKey (List $none) ProofOutputKey
       (List $none)))
(= (refresh-current-proof-result-step!
      $goal-key $_none $output-key)
   (refresh-current-proof-result! $goal-key $output-key))

(: refresh-dirty-current-proof-results!
   (-[semidet]-> ProofGoalKey (List $none)))
(= (refresh-dirty-current-proof-results! $goal-key)
   (proof-fold-flat-semidet
      (refresh-current-proof-result-step! $goal-key) ()
      (dirty-current-proof-result-output-keys $goal-key)))

(: refresh-current-proof-result-if-dirty!
   (-[semidet]-> ProofGoalKey ProofOutputKey (List $none)))
(= (refresh-current-proof-result-if-dirty! $goal-key $output-key)
   (if (current-proof-result-dirty? $goal-key $output-key)
      (refresh-current-proof-result! $goal-key $output-key)
      ()))

(: goal-merged-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-merged-proof-ids $gid)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_pending)
            (goal-by-id $gid))
          ($key (proof-goal-key-by-goal-id $gid))
          ($_refresh (refresh-dirty-current-proof-results! $key)))
      (reverse-number-list
         (proof-fold-flat-semidet
            (goal-current-proof-step $goal) ()
            (current-proof-result-ids-for-goal-key $key)))))

(: goal-merged-proof-id-for-pid (-[semidet]-> Number Number Number))
(= (goal-merged-proof-id-for-pid $gid $pid)
   (let* (($goal-key (proof-goal-key-by-goal-id $gid))
          ($output-key (proof-output-key-by-id $pid))
          ($_refresh
             (refresh-current-proof-result-if-dirty!
                $goal-key $output-key)))
      (current-proof-result-id-for-output-key
         $goal-key $output-key)))

;; A completed root proof is an incumbent answer even if one of its revised
;; children is superseded near the end of a bounded search. Keep it out of
;; ordinary subgoal reasoning, but use the latest non-superseded root
;; candidates when the live result set is transiently empty. Once a rebuilt
;; root is committed, the normal live result path wins again.
(: goal-incumbent-proof-step
   (-[semidet]-> (List Number) Number (List Number)))
(= (goal-incumbent-proof-step $acc $pid)
   (if (proof-current-representative? $pid)
      (cons $pid $acc)
      $acc))

(: goal-raw-incumbent-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-raw-incumbent-proof-ids $gid)
   (reverse-number-list
      (proof-fold-flat-semidet
         goal-incumbent-proof-step () (goal-proof-ids $gid))))

(: goal-result-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-result-proof-ids $gid)
   (let* (((stored-goal-row
              $_stored-gid $_depth $goal $_expanded $_pending)
            (goal-by-id $gid))
          ($key (proof-goal-key-by-goal-id $gid))
          ($lookup-key (copy_term $key)))
      (collapse
         (match &proof_result
            ($lookup-key $stored-key $pid)
            (if (=alpha $stored-key $key)
               (let $stored-pid (stored-number $pid)
                  (if (proof-output-satisfies-goal?
                         $stored-pid $goal)
                     $stored-pid
                     (empty)))
               (empty))))))

(: proof-output-key-covered-by?
   (-[semidet]-> (List Number) Number Bool))
(= (proof-output-key-covered-by? () $_pid) false)
(= (proof-output-key-covered-by? (cons $covered-pid $rest) $pid)
   (if (=alpha
         (proof-output-key-by-id $covered-pid)
         (proof-output-key-by-id $pid))
      true
      (proof-output-key-covered-by? $rest $pid)))

(: uncovered-incumbent-proof-step
   (-[semidet]-> (List Number) (List Number) Number (List Number)))
(= (uncovered-incumbent-proof-step $covered $acc $pid)
   (if (proof-output-key-covered-by? $covered $pid)
      $acc
      (cons $pid $acc)))

(: goal-incumbent-proof-ids (-[semidet]-> Number (List Number)))
(= (goal-incumbent-proof-ids $gid)
   (let*
      (($merged
         (latest-proof-output-group-ids
            (proof-output-groups
               (goal-result-proof-ids $gid))))
       ($raw (goal-raw-incumbent-proof-ids $gid))
       ($uncovered
          (reverse-number-list
             (proof-fold-flat-semidet
                (uncovered-incumbent-proof-step $merged)
                () $raw))))
      (append-numbers $merged $uncovered)))

(: root-goal-representative-proof-ids
   (-[semidet]-> Number (List Number)))
(= (root-goal-representative-proof-ids $gid)
   (let $live (goal-live-proof-ids $gid)
      (if (== $live ())
         (proof-output-group-representative-pids $gid
            (proof-output-groups
               (goal-incumbent-proof-ids $gid)))
         (goal-merged-proof-ids $gid))))

(: materialize-root-goal-proofs-to-kb (-[det]-> Number (List $none)))
(= (materialize-root-goal-proofs-to-kb $gid)
   (let $_materialized
      (collapse
         (materialize-proof-list-to-kb
            (root-goal-representative-proof-ids $gid)))
      ()))

(: first-proof-id-list (-[det]-> (List Number) (List Number)))
(= (first-proof-id-list ()) ())
(= (first-proof-id-list (cons $pid $_rest)) (cons $pid ()))

(: root-goal-results-with-materialization
   (-[semidet]-> Number Bool (List RuntimeResult)))
(= (root-goal-results-with-materialization $gid $materialize?)
   (let*
      (($materialized-current
          (let (stored-goal-row
                  $_stored-gid $_depth $goal $_expanded $_pending)
             (goal-by-id $gid)
             (case $goal (
                (($type $kb $_proof $_tv)
                   (let $hash
                      (forward-output-index-hash
                         (forward-output-key $kb $type))
                      (collapse
                         (once
                            (match &materialized_aggregate_lineage
                               (materialized-aggregate-lineage-row
                                  $hash $type $kb $fact $_ev $dependencies)
                               (if (materialized-dependencies-stale?
                                      $dependencies)
                                  (empty)
                                  (let* (($goal-copy (copy_term $goal))
                                         ($fact-copy (copy_term $fact)))
                                     (if (= $goal-copy $fact-copy)
                                        (materialize-result-atom $fact)
                                        (empty)))))))))
                ($_other ())))))
       ($representatives
         (root-goal-representative-proof-ids $gid))
       ($selected
          (if (== $representatives ())
             (goal-incumbent-proof-ids $gid)
             $representatives))
       ($committed
          (if $materialize?
             (first-proof-id-list $selected)
             $selected))
       ($current-hits
         (collapse
            (once
               (proof-map-flat-semidet materialize-result-atom
                  (proof-map-flat-semidet proof-output-atom-by-id
                     $committed)))))
       ($current
          (if (== $current-hits ()) ()
             (car-atom $current-hits)))
       ($_materialized
          (if $materialize?
             (let $_dependencies
                (materialize-root-proof-list-to-kb $committed)
                ())
             ())))
      (if (not (== $materialized-current ()))
         $materialized-current
      (if (== $current ())
         (proof-map-flat-semidet materialize-result-atom
            (proof-map-flat-semidet proof-output-atom-by-id
               (goal-incumbent-proof-ids $gid)))
         $current))))

(: root-goal-results
   (-[semidet]-> Number (List RuntimeResult)))
(= (root-goal-results $gid)
   (root-goal-results-with-materialization $gid false))

(: goal-current-confidence
   (-[semidet]-> Number (| Number NoCurrentScore)))
(= (goal-current-confidence $gid)
   (let $cached
      (collapse
         (once
            (match &goal_current_confidence
               (goal-current-confidence-row $gid $value)
               $value)))
      (if (== $cached ())
         (let*
            (($pids (goal-merged-proof-ids $gid))
             ((stored-goal-row
                  $_stored-gid $_depth $goal $_expanded $_pending)
                (goal-by-id $gid))
             ($value
                (if (goal-has-type-vars? $goal) no-current
                   (case $pids
                      ((() no-current)
                       ((cons $pid $rest)
                          (term-confidence
                             (merge-proof-id-output
                                (cons $pid $rest))))))))
             ($_cache
                (once
                   (add-atom &goal_current_confidence
                      (goal-current-confidence-row $gid $value)))))
            $value)
         (car-atom $cached))))

(: leaf-evidence-for-stored-fact
   (-[det]-> Atom Atom Atom Atom (List Evidence)))
(= (leaf-evidence-for-stored-fact $type $kb $proof $tv)
   (let $typed-proof (brand Proof $proof)
      (if (assumption-proof? $typed-proof) ()
         (forward-fact-evidence
            (brand Statement $type)
            (brand KBContext $kb)
            $typed-proof
            (the TV $tv)))))

(: leaf-evidence-for-result
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence)))
(= (leaf-evidence-for-result $result)
   (once
      (case $result (
         ((CPU $_formula $_arguments $_result)
            ())
         (($type $kb $proof $tv)
            (leaf-evidence-for-stored-fact
               $type $kb $proof $tv))
         ($_other ())))))

;; A stored proof dominates a new one only when they are genuinely dependent
;; (share a rule or hypothesis). Proofs that overlap only in facts are kept so
;; lifting-merge can pool them at the subgoal -- dropping the lower-scoring one
;; here would discard recoverable confidence, and (since idealized confidence is
;; strength-dependent) the scores rarely tie, so plain overlap would otherwise
;; drop a poolable proof.
(: ProofValue Type)
(: proof-value (-[det]-> Proof ProofValue))
(: no-proof-value ProofValue)

(: proof-kind-proof-value (-[det]-> ProofKind ProofValue))
(= (proof-kind-proof-value $kind)
   (once
      (case $kind (
         ((leaf ($_type $_kb $proof $_tv))
            (proof-value (brand Proof $proof)))
         ((rule ($_type $_kb $proof $_tv))
            (proof-value (brand Proof $proof)))
         ((aggregate (CPU $_formula $_arguments $_result))
            no-proof-value)
         ((aggregate ($_type $_kb $proof $_tv))
            (proof-value (brand Proof $proof)))
         ($_other no-proof-value)))))

(: backward-proof-kind-refines?
   (-[det]-> ProofKind (List Evidence) ProofKind (List Evidence) Bool))
(= (backward-proof-kind-refines? $old-kind $old-ev $new-kind $new-ev)
   (let*
      (($old-proof-value (proof-kind-proof-value $old-kind))
       ($new-proof-value (proof-kind-proof-value $new-kind)))
      (if (= $old-proof-value (proof-value $old-proof))
         (if (= $new-proof-value (proof-value $new-proof))
            (and
               (forward-strict-evidence-subset? $old-ev $new-ev)
               (forward-proof-refines?
                  (brand Proof $old-proof)
                  (brand Proof $new-proof)))
            false)
         false)))

(: proof-overlap-dominates-score?
   (-[det]-> ProofKind (List Evidence) Number
       ProofKind (List Evidence) Number Bool))
(= (proof-overlap-dominates-score?
      $old-kind $old-ev $old-score $new-kind $new-ev $new-score)
   (let $_metric
      (increment-backward-query-metric! dominance-checks)
   (if (evidence-sets-dependent? $old-ev $new-ev)
      (if (backward-proof-kind-refines?
             $old-kind $old-ev $new-kind $new-ev)
         false
         (if (backward-proof-kind-refines?
                $new-kind $new-ev $old-kind $old-ev)
            true
            (if (> $old-score $new-score) true
               (if (== $old-score $new-score)
                  (evidence-subset? $new-ev $old-ev)
                  false))))
      false)))

(: goal-proof-candidate-comparable?
   (-[semidet]-> Bool ProofOutputKey Number Bool))
(= (goal-proof-candidate-comparable? false $_outkey $_oldpid) true)
(= (goal-proof-candidate-comparable? true $outkey $oldpid)
   (== (proof-output-key-by-id $oldpid) $outkey))

(: goal-proof-candidate-step
   (-[semidet]-> Bool ProofOutputKey
       ProofKind (List Evidence) Number Bool Number Bool))
(= (goal-proof-candidate-step
      $_open $_outkey $_kind $_ev $_score false $_oldpid) false)
(= (goal-proof-candidate-step $open $outkey $kind $ev $score true $oldpid)
   (let $_metric
      (increment-backward-query-metric! candidate-comparisons)
   (if (goal-proof-candidate-comparable? $open $outkey $oldpid)
      (let*
         ((($old-score $old-ev) (proof-stats-by-id $oldpid))
          ($old-kind (proof-kind-by-id $oldpid)))
         (if (and (== $old-score $score) (== $old-ev $ev)) false
            (if (proof-overlap-dominates-score?
                   $old-kind $old-ev $old-score $kind $ev $score)
               false true)))
      true)))

(: classify-goal-proof-candidate
   (-[semidet]-> Number ProofCandidate Bool))
(= (classify-goal-proof-candidate
      $gid (proof-candidate $kind $score $ev $_children))
   (let*
      (((stored-goal-row
            $_stored-gid $_depth $goal $_expanded $_pending)
          (goal-by-id $gid))
       ($open (goal-has-type-vars? $goal))
       ($result (candidate-kind-term $kind))
       ($outkey (candidate-output-key $result))
       ($pids
          (if $open
             (goal-live-proof-ids-for-output-key $gid $outkey)
             (goal-live-proof-ids $gid))))
      (proof-fold-flat-semidet
         (goal-proof-candidate-step $open $outkey $kind $ev $score)
         true
         $pids)))

(: proof-candidate-stored-evidence
   (-[semidet]-> ProofCandidate (List Evidence)))
(= (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
   (case $kind (
      ((rule ($_type $kb $prf $_tv))
         (rule-result-evidence
            (assemble-runtime-fact
               (brand Statement $_type)
               (brand KBContext $kb)
               (brand Proof $prf)
               (the TV $_tv))
            $ev))
      ($_other $ev))))

(: normalize-proof-candidate-evidence
   (-[semidet]-> ProofCandidate ProofCandidate))
(= (normalize-proof-candidate-evidence (proof-candidate $kind $score $ev $children))
   (proof-candidate $kind $score
      (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
      $children))

;; Rule candidates are normalized before classification; leaf and aggregate
;; candidates already carry their final evidence. Store that accepted evidence
;; directly instead of walking rule proofs a second time.  The first candidate
;; is its own representative.  Later candidates dirty that output group so a
;; consumer rebuilds it once, rather than rebuilding after every insertion.
(: store-proof-candidate (-[nondet]-> Number ProofCandidate  Number))
(= (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
   (let*
      (($_metric (increment-backward-query-metric! proofs-stored))
       ($goal-key (proof-goal-key-by-goal-id $gid))
       ($owner (proof-goal $goal-key))
       ($pid (next-pid))
       ($output (proof-output-atom-kind $kind $pid))
       ($output-key (candidate-output-key $output))
       ($old-representative
           (collapse
              (once
                 (current-proof-result-id-for-output-key
                    $goal-key $output-key))))
        ($result-dirty?
           (current-proof-result-dirty?
              $goal-key $output-key))
        ($_1
           (chainer-add-atom &proof
              (stored-proof-row
                 $pid $owner $output $kind
                 (proof-support $score $ev
                    (proof-contribution $kind $output))
                 $children)))
        ($_index (index-proof-for-goal! $goal-key $pid))
        ($_current
           (index-current-proof-for-goal!
              $goal-key $output-key $pid))
        ($_2 (mark-proof-static! $gid $pid $kind $children))
        ($_parents (register-proof-parent-edges! $pid $children))
        ($_confidence (clear-goal-current-confidence! $gid))
        ($_result
           (if $result-dirty? ()
              (if (== $old-representative ())
                 (index-current-proof-result!
                    $goal-key $output-key $pid)
                 (let* (($_remove-result
                           (remove-current-proof-result-rows!
                              (current-proof-result-rows-for-output-key
                                 $goal-key $output-key)))
                        ($_supersede
                           (supersede-current-proof-result-without-replacement!
                              $old-representative))
                        ($_dirty
                           (mark-current-proof-result-dirty!
                              $goal-key $output-key)))
                    ()))))
        ($_live (cache-proof-live! $pid true)))
      $pid))

(: proof-atom-candidate
   (-[det]-> (Statement KBContext Proof TV)
       (List Evidence) ProofCandidate))
(= (proof-atom-candidate ($type $kb $prf $tv) $ev)
   (let $fact
      (assemble-runtime-fact $type $kb $prf $tv)
      (proof-candidate
         (leaf $fact) (term-confidence $fact) $ev ())))

(: leaf-result-candidate
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence) ProofCandidate))
(= (leaf-result-candidate $result $ev)
   (once
      (case $result (
         ((CPU $_formula $_arguments $_cpu-result)
            (proof-candidate
               (leaf $result)
               (term-confidence $result)
               $ev ()))
         (($type ($kbid $context $variables) $prf $tv)
            (proof-atom-candidate
               (assemble-contextual-runtime-fact
                  $type
                  $kbid
                  $context $variables
                  $prf
                  $tv)
               $ev))
         ($_other
            (proof-candidate
               (leaf $result) (term-confidence $result) $ev ()))))))

(: aggregate-result-candidate
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List Evidence) (List Number) ProofCandidate))
(= (aggregate-result-candidate $result $ev $children)
   (proof-candidate (aggregate $result) (term-confidence $result) $ev $children))

(: store-aggregate-proof-candidate
   (-[semidet]-> Number ProofCandidate Number))
(= (store-aggregate-proof-candidate $agg-gid $candidate)
   (let* (($pid (once (store-proof-candidate $agg-gid $candidate)))
          ((proof-candidate $kind $_score $_ev $_children)
             $candidate)
          ($_revision
             (record-aggregate-proof-revision! $pid $kind)))
      $pid))

(: candidate-kind-term
   (-[semidet]-> ProofKind
       (| Goal (Statement KBContext Proof TV))))
(= (candidate-kind-term (leaf $term)) $term)
(= (candidate-kind-term (rule $term)) $term)
(= (candidate-kind-term (aggregate $term)) $term)

(: cyclic-dependency?
   (-[semidet]-> Number Number
       (| ProofOutputKey ClosedGoalKey) Bool))
(= (cyclic-dependency? $pid $gid $cycle-key)
   (if (== $cycle-key closed-goal)
      (=alpha
         (proof-goal-key-by-id $pid)
         (proof-goal-key-by-goal-id $gid))
      (=alpha (proof-output-key-by-id $pid) $cycle-key)))

(: proof-depends-on-goal-seen?
   (-[semidet]-> Number Number
       (| ProofOutputKey ClosedGoalKey)
       (List Number) Bool))

(: proof-depends-on-goal-child-step
   (-[semidet]-> Number
       (| ProofOutputKey ClosedGoalKey)
       (List Number) Bool Number Bool))
(= (proof-depends-on-goal-child-step
      $gid $cycle-key $seen-pids $acc $child-pid)
   (if $acc true
      (proof-depends-on-goal-seen?
         $child-pid $gid $cycle-key $seen-pids)))

(= (proof-depends-on-goal-seen? $pid $gid $cycle-key ())
   (let $hits
      (collapse
         (once
            (match &proof_cycle_cache
               ($pid $gid $stored-key $result)
               (if (=alpha $stored-key $cycle-key)
                  $result
                  (empty)))))
      (case $hits (
         (()
            (let* (($result
                      (proof-depends-on-goal-seen?
                         $pid $gid $cycle-key (cons -1 ())))
                   (($stored-key $stored-result)
                      (copy_term (quote ($cycle-key $result))))
                   ($_cache
                      (once
                         (add-atom &proof_cycle_cache
                            ($pid $gid $stored-key $stored-result)))))
               $result))
         ((cons $result $_rest) $result)))))
(= (proof-depends-on-goal-seen?
      $pid $gid $cycle-key (cons $seen-pid $rest-seen-pids))
   (let $seen-pids (cons $seen-pid $rest-seen-pids)
   (if (stored-list-member? $pid $seen-pids) false
      (if (cyclic-dependency? $pid $gid $cycle-key) true
         (proof-fold-flat-semidet
            (proof-depends-on-goal-child-step
               $gid $cycle-key (cons $pid $seen-pids))
            false
            (proof-children-by-id $pid))))))

(: candidate-cycle-key
   (-[semidet]-> Number ProofKind
       (| ProofOutputKey ClosedGoalKey)))
(= (candidate-cycle-key $gid $kind)
   (let*
      (((stored-goal-row
            $_stored-gid $_depth $goal $_expanded $_pending)
          (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal)
         (candidate-output-key (candidate-kind-term $kind))
         closed-goal)))

(: candidate-is-cyclic?
   (-[semidet]-> Number ProofKind (List Number) Bool))
(= (candidate-is-cyclic? $gid $_kind ()) false)
(= (candidate-is-cyclic? $gid $kind (cons $pid $pids))
   (let $cycle-key (candidate-cycle-key $gid $kind)
      (if
         (proof-depends-on-goal-seen?
            $pid $gid $cycle-key ())
         true
         (candidate-is-cyclic? $gid $kind $pids))))

(: aggregate-snapshot-changed?
   (-[semidet]-> (List Number)
       $result (List Evidence) Bool))
(= (aggregate-snapshot-changed? $current-pid $result $ev)
   (if (== $current-pid ()) true
      (let (cons $pid $_rest) $current-pid
         (let*
            (($current-output (proof-output-atom-by-id $pid))
             (($_current-score $current-ev) (proof-stats-by-id $pid)))
            (if (=alpha $current-output $result)
               (if (== $current-ev $ev) false true)
               true)))))
