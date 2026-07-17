(= (normalize-proof-output-atom-kind $term $pid)
   (if (= $term ($type ($kbid $_ctx $_vars) $_prf $tv)) ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)
      $term))

(= (proof-output-atom-kind (leaf $term) $pid) (normalize-proof-output-atom-kind $term $pid))
(= (proof-output-atom-kind (rule $term) $pid) (normalize-proof-output-atom-kind $term $pid))
(= (proof-output-atom-kind (aggregate $term) $_pid) $term)

(= (proof-output-atom $pid) (match &proof ($pid $_gid $output $_kind $_score $_ev $_children) $output))

(= (candidate-output-key $term)
   (if (= $term ($type $kb $_prf $_tv)) ($type $kb) $term))

(= (proof-output-key-by-id $pid)
   (candidate-output-key (proof-output-atom $pid)))

(= (materialize-proof-refs $term)
   (if (is-expr $term)
      (if (is-var (car-atom $term))
         (cons (car-atom $term) (map-flat materialize-proof-refs (cdr-atom $term)))
         (if (== (car-atom $term) proof-ref)
            (materialize-proof-refs (materialize-proof (car-atom (cdr-atom $term))))
            (cons (materialize-proof-refs (car-atom $term)) (map-flat materialize-proof-refs (cdr-atom $term)))))
      $term))

(= (materialize-result-atom $atom)
   (if (= $atom ($type $kb $prf $tv)) ($type $kb (materialize-proof-refs $prf) $tv) $atom))

(= (materialize-proof-kind (leaf $raw) $_pid)
   (if (= $raw (CPU $_fun $_args $_res)) cpu (if (= $raw ($_type ($_kbid $_ctx $_vars) $prf $_tv)) $prf $raw)))
(= (aggregate-proof-label (CPU FoldAllCompiled $args $_res))
   (if (= $args ($_kb $_pattern $_extractor $_init OrFormula $_finish $_tv-mode))
      disjunction
      foldall-proof))
(= (aggregate-proof-label (CPU GroupedFoldAllCompiled $args $_res))
   (if (= $args ($_kb $_pattern $_group $_extractor $_init OrFormula $_finish $_tv-mode))
      disjunction
      foldall-proof))
(= (proof-ref-list ()) ())
(= (proof-ref-list (cons $pid $rest)) (cons (proof-ref $pid) (proof-ref-list $rest)))
(= (aggregate-child-proof-tokens ()) ())
(= (aggregate-child-proof-tokens (cons $pid $rest))
   (let $output (proof-output-atom $pid)
      (if (or (= $output (CPU FoldAllCompiled $_args $_res)) (= $output (CPU GroupedFoldAllCompiled $_gargs $_gres)))
         (cons (materialize-proof $pid) (aggregate-child-proof-tokens $rest))
         (aggregate-child-proof-tokens $rest))))
(= (replace-cpu-proof-token-list () $proofs) (() $proofs))
(= (replace-cpu-proof-token-list (cons $head $tail) $proofs)
   (let*
      ((($new-head $proofs1) (replace-cpu-proof-token $head $proofs))
       (($new-tail $proofs2) (replace-cpu-proof-token-list $tail $proofs1)))
      ((cons $new-head $new-tail) $proofs2)))
(= (replace-cpu-proof-token $term $proofs)
   (if (is-var $term)
      ($term $proofs)
      (if (== $term cpu)
         (if (= $proofs (cons $proof $rest)) ($proof $rest) (cpu ()))
         (if (is-expr $term)
            (let* ((($new-list $rest-proofs) (replace-cpu-proof-token-list $term $proofs)))
               ($new-list $rest-proofs))
            ($term $proofs)))))
(= (materialize-rule-token $prf $pid)
   (let*
      (($base-prf (materialize-proof-refs $prf))
       ($aggregate-proofs (aggregate-child-proof-tokens (proof-children-by-id $pid)))
       (($new-prf $_unused) (replace-cpu-proof-token $base-prf $aggregate-proofs)))
      $new-prf))
(= (materialize-proof-kind (aggregate $raw) $pid)
   (let $children (proof-children-by-id $pid)
      (if (== $children ()) cpu
         (cons (aggregate-proof-label $raw)
            (map-flat materialize-proof-refs (proof-ref-list $children))))))
(= (materialize-proof-kind (merged $output) $_pid)
   (if (= $output ($_type $_kb $prf $_tv)) (materialize-proof-refs $prf) $output))
(= (rule-kind-proof-token $term)
   (if (is-expr $term)
      (let $tail1 (cdr-atom $term)
         (if (== $tail1 ()) $term
            (let $tail2 (cdr-atom $tail1)
               (if (== $tail2 ()) $term
                  (car-atom $tail2)))))
      $term))
(= (materialize-rule-expression $rule-prf)
   (if (is-expr $rule-prf)
      (if (= (car-atom $rule-prf) (Implication $_premises $_conclusions))
         (if (== (cdr-atom (cdr-atom $rule-prf)) ())
            (car-atom (cdr-atom $rule-prf))
            $rule-prf)
         $rule-prf)
      $rule-prf))
(= (materialize-proof-kind (rule $term) $pid)
   (let $prf (rule-kind-proof-token $term)
      (if (== $prf $term) $term
         (let $rule-prf (materialize-rule-token $prf $pid)
            (materialize-rule-expression $rule-prf)))))

(= (materialize-proof $pid)
   (match &proof ($pid $_gid $_output $kind $_score $_ev $_children)
      (materialize-proof-kind $kind $pid)))

(= (goal-proof-ids $gid)
   (collapse (match &proof ($pid $gid $_output $_kind $_score $_ev $_children) $pid)))

(= (proof-goal-id $pid)
   (match &proof ($pid $gid $_output $_kind $_score $_ev $_children) $gid))

(= (proof-children-by-id $pid)
   (match &proof ($pid $_gid $_output $_kind $_score $_ev $children) $children))

(= (proof-kind-by-id $pid)
   (match &proof ($pid $_gid $_output $kind $_score $_ev $_children) $kind))

(= (materializable-proof-kind? (rule $_term)) true)
(= (materializable-proof-kind? $_kind) false)

(= (materializable-proof-output? ($type ($_kbid MAIN Nil) $_prf $_tv))
   (== (extract-vars $type) ()))
(= (materializable-proof-output? $_output) false)

(= (materialize-proof-node-to-kb $pid)
   (let*
      (($kind (proof-kind-by-id $pid))
       ($output (proof-output-atom $pid)))
	      (if (and (materializable-proof-kind? $kind) (materializable-proof-output? $output))
	         (let*
	            (($fact (materialize-result-atom $output))
	             (($_score $ev) (proof-stats-by-id $pid))
	             ($change
	                (forward-candidate-upsert!
	                   (forward-derived $fact $ev))))
	            (progn
	               (forward-apply-unqueued-change! $change)
	               ()))
	         ())))

(= (materialize-proof-tree-to-kb $pid)
   (let $_children (collapse (materialize-proof-list-to-kb (proof-children-by-id $pid)))
      (let $_node (collapse (materialize-proof-node-to-kb $pid))
         ())))

(= (materialize-proof-list-to-kb ()) ())
(= (materialize-proof-list-to-kb (cons $pid $rest))
   (let $_head (collapse (materialize-proof-tree-to-kb $pid))
      (materialize-proof-list-to-kb $rest)))

(= (materialize-goal-proofs-to-kb $gid)
   (let $_materialized (collapse (materialize-proof-list-to-kb (goal-live-proof-ids $gid)))
      ()))

(= (proof-live-cache-epoch)
   (let $n (get-state bwd_live_epoch) (if-error $n 0 $n)))

(= (invalidate-proof-live-caches)
   (let $epoch (proof-live-cache-epoch)
      (change-state! bwd_live_epoch (+ $epoch 1))))

(= (cache-proof-live! $pid $alive)
   (let $epoch (proof-live-cache-epoch)
      (add-atom &proof_live_cache ($epoch $pid $alive))))

(= (cached-proof-live? $pid)
   (let $epoch (proof-live-cache-epoch)
      (match &proof_live_cache ($epoch $pid $alive) $alive)))

(= (goal-live-cache-store! $gid $pids)
   (let $epoch (proof-live-cache-epoch)
      (add-atom &goal_live_cache ($epoch $gid $pids))))

(= (goal-live-cache-remove! $gid $pids)
   (let $epoch (proof-live-cache-epoch)
      (remove-atom &goal_live_cache ($epoch $gid $pids))))

(= (cached-goal-live-proof-ids $gid)
   (let $epoch (proof-live-cache-epoch)
      (match &goal_live_cache ($epoch $gid $pids) $pids)))

(= (append-goal-live-cache! $gid $pid)
   (let*
      (($epoch (proof-live-cache-epoch))
       ($hits (collapse (once (match &goal_live_cache ($epoch $gid $pids) $pids)))))
      (if (== $hits ())
         ()
         (let*
            (($pids (car-atom $hits))
             ($npids (append $pids ($pid))))
            (progn
               (goal-live-cache-remove! $gid $pids)
               (goal-live-cache-store! $gid $npids))))))

(= (register-proof-parent-edges! $parent-pid $children)
   (foreach-flat
      (|-> ($child-pid) (add-atom &proof_parent ($child-pid $parent-pid)))
      $children))

(= (invalidate-proof-dependent! $epoch $parent-pid)
   (let $seen
      (collapse
         (once
            (match &proof_invalidated_epoch (($epoch $parent-pid)) true)))
      (if (not (== $seen ())) ()
         (let*
            (($gid (proof-goal-id $parent-pid))
             ($_mark (add-atom &proof_invalidated_epoch (($epoch $parent-pid))))
             ($_proof-cache
                (foreach-flat
                   (|-> ($alive)
                      (remove-atom &proof_live_cache ($epoch $parent-pid $alive)))
                   (collapse
                      (match &proof_live_cache ($epoch $parent-pid $alive) $alive))))
             ($_goal-cache
                (foreach-flat
                   (|-> ($pids)
                      (remove-atom &goal_live_cache ($epoch $gid $pids)))
                   (collapse
                      (match &goal_live_cache ($epoch $gid $pids) $pids))))
             ($_parents
                (foreach-flat
                   (|-> ($dependent-pid)
                      (invalidate-proof-dependent! $epoch $dependent-pid))
                   (collapse
                      (match &proof_parent ($parent-pid $dependent-pid)
                         $dependent-pid)))))
            ()))))

(= (invalidate-proof-dependents! $epoch $child-pid)
   (foreach-flat
      (|-> ($parent-pid) (invalidate-proof-dependent! $epoch $parent-pid))
      (collapse (match &proof_parent ($child-pid $parent-pid) $parent-pid))))

(= (aggregate-current-pid-live? $current-pid $pid)
   (if (== $current-pid ()) false
      (if (is-expr $current-pid) (is-member $pid $current-pid) (== $current-pid $pid))))

(= (proof-live-compute $pid)
   (let*
      (($gid (proof-goal-id $pid))
       ($kind (proof-kind-by-id $pid))
       ($current-hits
          (collapse
             (once
                (match &aggregate ($gid $_child $_args $_base $_pending $current-pid)
                   $current-pid)))))
      (if (== $current-hits ())
         (if (= $kind (merged $_output))
            (proof-list-node-live? (proof-children-by-id $pid))
            (proof-list-live? (proof-children-by-id $pid)))
         (aggregate-current-pid-live? (car-atom $current-hits) $pid))))

;; A merged representative owns its raw alternatives, so those children only
;; need to remain valid proof nodes. Every other parent edge must point at the
;; current representative of the child's grounded output. If more evidence is
;; merged into that output later, parents built from the old representative
;; become stale while the raw proofs remain available to construct the new one.
(= (proof-list-node-live? ())
   true)
(= (proof-list-node-live? (cons $pid $rest))
   (and (proof-live? $pid) (proof-list-node-live? $rest)))

(= (proof-current-representative? $pid)
   (== (collapse (once (match &proof_superseded ($pid) true))) ()))

(= (proof-list-live? ())
   true)
(= (proof-list-live? (cons $pid $rest))
   (and (proof-live? $pid)
      (and (proof-current-representative? $pid) (proof-list-live? $rest))))

(= (proof-statically-live? $pid)
   (not (== (collapse (once (match &proof_static_live ($pid) true))) ())))

(= (mark-proof-static! $gid $pid $kind $children)
   (if (= $kind (aggregate $_term)) ()
      (if (== $children ())
         (if (==
                (collapse
                   (once
                      (match &aggregate ($gid $_child $_args $_base $_pending $_current) true)))
                ())
            (add-atom &proof_static_live ($pid))
            ())
         ())))

(= (proof-live? $pid)
   (if (proof-statically-live? $pid) true
      (let*
         (($hits (collapse (once (cached-proof-live? $pid)))))
         (if (== $hits ())
            (let*
               (($alive (proof-live-compute $pid))
                ($_cache (cache-proof-live! $pid $alive)))
               $alive)
            (car-atom $hits)))))

(= (goal-live-proof-step $acc $pid)
   (if (proof-live? $pid) (append $acc ($pid)) $acc))

(= (goal-live-proof-ids-compute $gid)
   (fold-flat goal-live-proof-step () (goal-proof-ids $gid)))

(= (goal-live-proof-ids $gid)
   (let*
      (($hits (collapse (once (cached-goal-live-proof-ids $gid)))))
      (if (== $hits ())
         (let*
            (($pids (goal-live-proof-ids-compute $gid))
             ($_cache (goal-live-cache-store! $gid $pids)))
            $pids)
         (car-atom $hits))))

(= (proof-output-groups-add () $pid)
   ((proof-output-group (proof-output-key-by-id $pid) ($pid))))
(= (proof-output-groups-add (cons (proof-output-group $key $pids) $rest) $pid)
   (let $pid-key (proof-output-key-by-id $pid)
      (if (=alpha $pid-key $key)
         (cons (proof-output-group $key (append $pids ($pid))) $rest)
         (cons (proof-output-group $key $pids) (proof-output-groups-add $rest $pid)))))

(= (proof-output-groups $pids)
   (fold-flat proof-output-groups-add () $pids))

(= (merge-proof-id-output-step $acc $pid)
   (merge-proof-atoms $acc (proof-output-atom $pid)))

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

(= (factor-cpu-child? $pid) (if (= (proof-output-atom $pid) (CPU $_f $_a $_r)) true false))
(= (factor-split-pc () $p $c) ($p $c))
(= (factor-split-pc (cons $pid $rest) $p $c)
   (if (factor-cpu-child? $pid)
      (factor-split-pc $rest $p (append $c ($pid)))
      (factor-split-pc $rest (append $p ($pid)) $c)))
(= (factor-last (cons $x ())) $x)
(= (factor-last (cons $x $rest)) (factor-last $rest))
(= (factor-find-ctv ()) no-ctv)
(= (factor-find-ctv (cons $a $rest)) (if (= $a (CTV $_p $_n)) $a (factor-find-ctv $rest)))
(= (factor-and-fold (cons $tv ())) $tv)
(= (factor-and-fold (cons $tv $rest)) (AndFormula $tv (factor-and-fold $rest)))

(= (factor-key-in? $_k ()) false)
(= (factor-key-in? $k (cons $h $rest)) (if (=alpha $k $h) true (factor-key-in? $k $rest)))

(= (factor-reeval-premises () $_keys $_o) ())
(= (factor-reeval-premises (cons $pid $rest) $keys $o)
   (cons (factor-reeval $pid $keys $o) (factor-reeval-premises $rest $keys $o)))

;; structural recompute: fold premise proofs (by child position) and re-apply ctv,
;; with every shared leaf (any key in $keys) overridden to $o
(= (factor-reeval-rule $pid $keys $o $stored)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) $stored
         (let* (((CPU $lf $la $_r) (proof-output-atom (factor-last $cpu)))
                ($ctv (factor-find-ctv $la)))
            (if (and (== $lf CTVModusPonensFormula) (not (== $ctv no-ctv)))
               (CTVModusPonensFormula (factor-and-fold (factor-reeval-premises $prem $keys $o)) $ctv)
               $stored)))))

(= (factor-reeval $pid $keys $o)
   (let $out (proof-output-atom $pid)
      (if (= $out ($t $kb $prf $tv))
         (if (factor-key-in? (candidate-output-key $out) $keys) $o (factor-reeval-rule $pid $keys $o $tv))
         $tv)))

(= (factor-proof? $pid)
   (let* ((($prem $cpu) (factor-split-pc (proof-children-by-id $pid) () ())))
      (if (== $cpu ()) true
         (let* (((CPU $lf $la $_r) (proof-output-atom (factor-last $cpu)))
                ($ctv (factor-find-ctv $la)))
            (if (and (== $lf CTVModusPonensFormula) (not (== $ctv no-ctv))) (factor-all? $prem) false)))))
(= (factor-all? ()) true)
(= (factor-all? (cons $pid $rest)) (and (factor-proof? $pid) (factor-all? $rest)))

(= (factor-pid-facts $pid) (fact-evidence-only (snd (proof-stats-by-id $pid))))
(= (factor-shared-facts (cons $pid $rest))
   (fold-flat (|-> ($acc $p) (intersection-atom $acc (factor-pid-facts $p)))
      (factor-pid-facts $pid) $rest))
(= (factor-fact-key (fact-ev $kb $prf $type)) ($type $kb))

;; the shared premise's actual TV, found in the proof DAG by output key
(= (factor-leaf-tv $pid $key)
   (let $out (proof-output-atom $pid)
      (if (= $out ($t $kb $prf $tv))
         (if (=alpha (candidate-output-key $out) $key) $tv
            (factor-leaf-tv-children (proof-children-by-id $pid) $key))
         no-tv)))
(= (factor-leaf-tv-children () $_key) no-tv)
(= (factor-leaf-tv-children (cons $pid $rest) $key)
   (let $r (factor-leaf-tv $pid $key)
      (if (== $r no-tv) (factor-leaf-tv-children $rest $key) $r)))

;; Residual of a proof w.r.t. the shared facts: probe their conjunction at
;; strength 1 (all shared leaves -> (1 1)) and 0 (all -> (0 1)). The conclusion
;; is linear in the shared conjunction's strength, so these two points give the
;; residual implication (conjunction-of-shared -> conclusion).
(= (factor-revise-ctv (CTV $p1 $n1) (CTV $p2 $n2)) (CTV (mergetvs $p1 $p2) (mergetvs $n1 $n2)))
(= (factor-residual $pid $keys)
   (CTV (factor-reeval $pid $keys (STV 1.0 1.0)) (factor-reeval $pid $keys (STV 0.0 1.0))))
(= (factor-revise-residuals (cons $pid ()) $keys) (factor-residual $pid $keys))
(= (factor-revise-residuals (cons $pid $rest) $keys)
   (factor-revise-ctv (factor-residual $pid $keys) (factor-revise-residuals $rest $keys)))

;; the shared facts' keys, and their real conjunction TV (And-fold of leaf TVs)
(= (factor-shared-keys ()) ())
(= (factor-shared-keys (cons $f $rest)) (cons (factor-fact-key $f) (factor-shared-keys $rest)))
(= (factor-real-conj $pid (cons $key ())) (factor-leaf-tv $pid $key))
(= (factor-real-conj $pid (cons $key $rest))
   (AndFormula (factor-leaf-tv $pid $key) (factor-real-conj $pid $rest)))

;; round-trip check: re-applying a proof's residual to the real shared
;; conjunction must reproduce its stored strength. The 2-point probe captures
;; the conclusion's linear dependence on the shared conjunction exactly, so the
;; strength round-trips when the shared facts enter through one conjunction and
;; fails (disabling factoring) when they enter through different conjunctions.
;; Only strength is checked: confidence is non-linear under idealized
;; propagation, so the residual's re-derived branch confidences never reproduce
;; the stored confidence exactly -- checking it would reject every valid group.
(= (factor-abs-diff $x $y) (let $d (- $x $y) (if (< $d 0.0) (- 0.0 $d) $d)))
(= (factor-close? $x $y) (< (factor-abs-diff $x $y) 0.000001))
;; single clause: a bare catch-all (= (factor-tv-close? $a $b) false) would also
;; match the (STV STV) case and make the result non-deterministic.
(= (factor-tv-close? $a $b)
   (if (= $a (STV $sa $_ca))
      (if (= $b (STV $sb $_cb)) (factor-close? $sa $sb) false)
      false))
(= (factor-roundtrip-one? $pid $keys $conj)
   (let* ((($_t $_k $_p $stored) (proof-output-atom $pid))
          ($rebuilt (CTVModusPonensFormula $conj (factor-residual $pid $keys))))
      (factor-tv-close? $stored $rebuilt)))
(= (factor-roundtrips? () $_keys $_conj) true)
(= (factor-roundtrips? (cons $pid $rest) $keys $conj)
   (and (factor-roundtrip-one? $pid $keys $conj) (factor-roundtrips? $rest $keys $conj)))

(= (factor-ref-of $pid) (let ($_t $_k $prf $_tv) (proof-output-atom $pid) $prf))
(= (factor-merged-prf (cons $pid ())) (factor-ref-of $pid))
(= (factor-merged-prf (cons $pid $rest)) (merge/revision (factor-ref-of $pid) (factor-merged-prf $rest)))

;; Each proof's residual evidence (full evidence minus the shared facts) must be
;; pairwise disjoint, otherwise the proofs are not independent given the shared
;; premise -- e.g. two derivations that also share an uncertain rule, or one
;; whose evidence subsumes another's -- and pooling them would double count.
;; Such groups fall back to revision/dominance.
(= (factor-residual-ev $pid $shared)
   (subtraction-atom (snd (proof-stats-by-id $pid)) $shared))
(= (factor-residual-evs () $_shared) ())
(= (factor-residual-evs (cons $pid $rest) $shared)
   (cons (factor-residual-ev $pid $shared) (factor-residual-evs $rest $shared)))
(= (factor-disjoint-from-all? $_ev ()) true)
(= (factor-disjoint-from-all? $ev (cons $other $rest))
   (and (== (intersection-atom $ev $other) ()) (factor-disjoint-from-all? $ev $rest)))
(= (factor-pairwise-disjoint? ()) true)
(= (factor-pairwise-disjoint? (cons $ev $rest))
   (and (factor-disjoint-from-all? $ev $rest) (factor-pairwise-disjoint? $rest)))

;; Pool a group when: it shares at least one fact, every proof is standard
;; implication-shaped, the residual evidence sets are pairwise disjoint, and the
;; residuals round-trip (the shared facts factor through one conjunction).
(= (group-factorable? $pids)
   (let* (($shared (factor-shared-facts $pids))
          ($keys (factor-shared-keys $shared)))
      (if (== $shared ()) false
         (and (factor-all? $pids)
            (and (factor-pairwise-disjoint? (factor-residual-evs $pids $shared))
               (factor-roundtrips? $pids $keys (factor-real-conj (car-atom $pids) $keys)))))))

(= (factor-merge-output $pids)
   (let* (($keys (factor-shared-keys (factor-shared-facts $pids)))
          ($conj (factor-real-conj (car-atom $pids) $keys))
          ($pooled (factor-revise-residuals $pids $keys))
          ($merged-tv (CTVModusPonensFormula $conj $pooled))
          (($type $kb $_p $_t) (proof-output-atom (car-atom $pids))))
      ($type $kb (factor-merged-prf $pids) $merged-tv)))

(= (merge-proof-id-output (cons $pid $rest))
   ;; `and` is eager here.  Keep the singleton check outside it so a lone
   ;; cached derivation is never sent through multi-proof factoring: its leaf
   ;; provenance may refer to upstream facts which are intentionally absent
   ;; from this proof node's child list.
   (if (== $rest ())
      (proof-output-atom $pid)
      (if (group-factorable? (cons $pid $rest))
         (factor-merge-output (cons $pid $rest))
         (fold-flat merge-proof-id-output-step (proof-output-atom $pid) $rest))))

(= (proof-id-evidence-step $acc $pid)
   (let ($_score $ev) (proof-stats-by-id $pid)
      (list_to_set (append $acc $ev))))

(= (proof-id-evidence-list $pids)
   (fold-flat proof-id-evidence-step () $pids))

(= (proof-output-group-representative-pid $gid (proof-output-group $_key $pids))
   (case $pids (
      ((cons $pid ()) $pid)
      ($_
         (let*
            (($output (merge-proof-id-output $pids))
             ($score (term-confidence $output))
             ($ev (proof-id-evidence-list $pids))
             ($hits
                (collapse
                   (once
                      (match &proof ($stored-pid (merged-proof-group $gid) $output (merged $output) $score $ev $pids)
                         $stored-pid)))))
            (if (== $hits ())
               (let*
                  (($pid (next-pid))
                   ($_store (chainer-add-atom &proof ($pid (merged-proof-group $gid) $output (merged $output) $score $ev $pids)))
                   ($_static (mark-proof-static! (merged-proof-group $gid) $pid (merged $output) $pids))
                   ($_parents (register-proof-parent-edges! $pid $pids)))
                  $pid)
               (car-atom $hits)))))))

(= (proof-output-group-representative-pids $_gid ()) ())
(= (proof-output-group-representative-pids $gid (cons $group $rest))
   (cons (proof-output-group-representative-pid $gid $group)
      (proof-output-group-representative-pids $gid $rest)))

(= (goal-merged-proof-ids $gid)
   (proof-output-group-representative-pids $gid
      (proof-output-groups (goal-live-proof-ids $gid))))

(= (proof-output-group-for-key-step $key $pids $pid)
   (if (=alpha (proof-output-key-by-id $pid) $key)
      (append $pids ($pid))
      $pids))

(= (goal-live-proof-ids-for-output-key $gid $key)
   (fold-flat (proof-output-group-for-key-step $key)
      ()
      (goal-live-proof-ids $gid)))

(= (goal-merged-proof-id-for-pid $gid $pid)
   (let $key (proof-output-key-by-id $pid)
      (proof-output-group-representative-pid $gid
         (proof-output-group $key (goal-live-proof-ids-for-output-key $gid $key)))))

(= (goal-results $gid)
   (let*
      (($pids (goal-merged-proof-ids $gid)))
      (map-flat materialize-result-atom (map-flat proof-output-atom $pids))))

(= (goal-current-output $gid)
   (let*
      (($pids (goal-merged-proof-ids $gid))
        (($_depth $goal $_expanded $_pending) (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal) no-current
         (case $pids (
              (() no-current)
              ((cons $pid $rest) (merge-proof-id-output (cons $pid $rest))))))))

(= (goal-current-confidence $gid)
   (let $current (goal-current-output $gid)
      (if (== $current no-current) no-current (term-confidence $current))))

(= (assumption-proof? $prf)
   (if (is-expr $prf) (== (car-atom $prf) ctx) false))

(= (leaf-evidence-for-result $result)
   (if (= $result ($type ($kbid $_ctx $_vars) $prf $_tv))
      (if (assumption-proof? $prf) () (forward-fact-evidence $result))
      ()))

;; A stored proof dominates a new one only when they are genuinely dependent
;; (share a rule or hypothesis). Proofs that overlap only in facts are kept so
;; lifting-merge can pool them at the subgoal -- dropping the lower-scoring one
;; here would discard recoverable confidence, and (since idealized confidence is
;; strength-dependent) the scores rarely tie, so plain overlap would otherwise
;; drop a poolable proof.
(= (proof-overlap-dominates-score? $old-ev $old-score $new-ev $new-score)
   (and (evidence-sets-dependent? $old-ev $new-ev)
      (or (> $old-score $new-score) (and (== $old-score $new-score) (evidence-subset? $new-ev $old-ev)))))

(= (goal-proof-candidate-comparable? false $_outkey $_oldpid) true)
(= (goal-proof-candidate-comparable? true $outkey $oldpid)
   (== (proof-output-key-by-id $oldpid) $outkey))

(= (goal-proof-candidate-step $_open $_outkey $ev $score false $_oldpid) false)
(= (goal-proof-candidate-step $open $outkey $ev $score true $oldpid)
   (if (goal-proof-candidate-comparable? $open $outkey $oldpid)
      (let ($old-score $old-ev) (proof-stats-by-id $oldpid)
         (if (and (== $old-score $score) (== $old-ev $ev)) false
            (if (proof-overlap-dominates-score? $old-ev $old-score $ev $score) false true)))
      true))

(= (classify-goal-proof-candidate $gid $result $ev $score)
   (let*
      ((($_depth $goal $_expanded $_pending) (goal-by-id $gid))
       ($open (goal-has-type-vars? $goal))
       ($outkey (candidate-output-key $result)))
      (fold-flat (goal-proof-candidate-step $open $outkey $ev $score)
      true
      (goal-live-proof-ids $gid))))

(= (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
   (if (= $kind (rule ($_type $kb $prf $_tv)))
      (rule-result-evidence ($_type $kb $prf $_tv) $ev)
      $ev))

(= (normalize-proof-candidate-evidence (proof-candidate $kind $score $ev $children))
   (proof-candidate $kind $score
      (proof-candidate-stored-evidence (proof-candidate $kind $score $ev $children))
      $children))

;; Rule candidates are normalized before classification; leaf and aggregate
;; candidates already carry their final evidence. Store that accepted evidence
;; directly instead of walking rule proofs a second time.
(= (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
   (let*
      (($pid (next-pid))
        ($output (proof-output-atom-kind $kind $pid))
        ($old-pids
           (goal-live-proof-ids-for-output-key $gid (candidate-output-key $output)))
        ($old-representative
           (if (== $old-pids ()) ()
              (proof-output-group-representative-pid $gid
                 (proof-output-group (candidate-output-key $output) $old-pids))))
        ($_1 (chainer-add-atom &proof ($pid $gid $output $kind $score $ev $children)))
        ($_2 (mark-proof-static! $gid $pid $kind $children))
        ($_parents (register-proof-parent-edges! $pid $children))
        ($_3
           (if (== $old-representative ()) ()
              (progn
                 (add-atom &proof_superseded ($old-representative))
                 (invalidate-proof-dependents!
                    (proof-live-cache-epoch)
                    $old-representative))))
        ($_4 (cache-proof-live! $pid true))
        ($_5 (append-goal-live-cache! $gid $pid)))
      $pid))

(= (proof-atom-candidate ($type $kb $prf $tv) $ev)
   (proof-candidate (leaf ($type $kb $prf $tv)) (term-confidence ($type $kb $prf $tv)) $ev ()))

(= (leaf-result-candidate $result $ev)
   (if (= $result ($type $_kb $_prf $_tv)) (proof-atom-candidate $result $ev)
      (proof-candidate (leaf $result) (term-confidence $result) $ev ())))

(= (aggregate-result-candidate $result $ev $children)
   (proof-candidate (aggregate $result) (term-confidence $result) $ev $children))

(= (candidate-kind-term (leaf $term)) $term)
(= (candidate-kind-term (rule $term)) $term)
(= (candidate-kind-term (aggregate $term)) $term)

(= (cyclic-dependency? $pid $gid $cycle-key)
   (and (== (proof-goal-id $pid) $gid)
      (or (== $cycle-key closed-goal)
         (=alpha (proof-output-key-by-id $pid) $cycle-key))))

(= (proof-depends-on-goal-seen? $pid $gid $cycle-key $seen-pids)
   (if (is-member $pid $seen-pids) false
      (or (cyclic-dependency? $pid $gid $cycle-key)
         (fold-flat
            (|-> ($acc $child-pid)
               (or $acc (proof-depends-on-goal-seen? $child-pid $gid $cycle-key (cons $pid $seen-pids))))
            false
            (match &proof ($pid $_proof-gid $_output $_kind $_score $_ev $kids)
               $kids)))))

(= (candidate-cycle-key $gid $kind)
   (let*
      ((($_depth $goal $_expanded $_pending) (goal-by-id $gid)))
      (if (goal-has-type-vars? $goal)
         (candidate-output-key (candidate-kind-term $kind))
         closed-goal)))

(= (candidate-is-cyclic? $gid $_kind ()) false)
(= (candidate-is-cyclic? $gid $kind (cons $pid $pids))
   (let $cycle-key (candidate-cycle-key $gid $kind)
      (or (proof-depends-on-goal-seen? $pid $gid $cycle-key ()) (candidate-is-cyclic? $gid $kind $pids))))

(= (wake-proof-commit-heap $agenda $gid $pid)
   (let*
      (($waiters (collapse (match &goal_waiter ($gid $waiter) $waiter)))
       ($representative-pid (goal-merged-proof-id-for-pid $gid $pid))
       ($agenda1
          (fold-flat (|-> ($acc $waiter) (advance-frontier-waiter-heap $acc $waiter $representative-pid))
             $agenda
             (foldr-flat frontier-waiter-step () $waiters)))
       ($agenda2
          (fold-flat (|-> ($acc $agg-gid) (schedule-aggregate-heap $acc $agg-gid))
             $agenda1
             (foldr-flat aggregate-waiter-step () $waiters))))
      $agenda2))

(= (commit-proof-candidate-heap $agenda $gid $accepted (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $kind $children) $agenda
         (let $pid (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
            (wake-proof-commit-heap $agenda $gid $pid)))))

(= (aggregate-snapshot-changed? () $_result $_ev)
   true)
(= (aggregate-snapshot-changed? $current-pid $result $ev)
   (let*
      (($current-output (proof-output-atom $current-pid))
       (($_current-score $current-ev) (proof-stats-by-id $current-pid)))
      (or (not (=alpha $current-output $result)) (not (== $current-ev $ev)))))

(= (commit-aggregate-snapshot-heap $agenda $agg-gid $result $ev $children)
   (let*
      ((($child-gid $args $base-score $pending $current-pid) (aggregate-by-id $agg-gid))
       ($pid (store-proof-candidate $agg-gid (aggregate-result-candidate $result $ev $children)))
       ($_set
          (progn
             (remove-atom &aggregate ($agg-gid $child-gid $args $base-score $pending $current-pid))
             (chainer-add-atom &aggregate ($agg-gid $child-gid $args $base-score $pending $pid))))
       ($_cache-invalidate (if (== $current-pid ()) () (invalidate-proof-live-caches)))
       ($nagenda (wake-proof-commit-heap $agenda $agg-gid $pid)))
      $nagenda))
