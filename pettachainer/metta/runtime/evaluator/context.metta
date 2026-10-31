;; Independent cold reads run all their maintenance in MAIN. Locality is
;; decided from the indexed inputs actually read by the evaluator.
(: context-cold-merged (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
(= (context-cold-merged $hash $key $filter)
   (let $ctx (context-current)
      (if (if (== $ctx main) false (not (execution-local-prior? $ctx $key)))
         (context-with-scope main (|-> ($_unit) (sk-merge-open! $hash $key $filter)))
         (sk-merge-open! $hash $key $filter))))

(: execution-local-key? (-[det]-> Atom SkeletonKey Bool))
(= (execution-local-key? $ctx $key) (context-key-local? $ctx (index-hash $key) $key))
(: execution-local-inputs? (-[semidet]-> Atom Number SkeletonKey Bool))
(= (execution-local-inputs? $ctx $hash $key)
   (if (not (== (collapse (once (match &sk_row ($hash $stored $_row (sk-row $_id $_conclusion $premises $_seq))
          (if (=alpha $stored $key)
             (if (any-flat? (execution-local-key? $ctx) (fold-flat sk-direct-key-step () $premises)) true (empty))
             (empty))))) ())) true
      (case $key (
         ((sk-fold $args)
            (any-flat? (|-> ($node) (any-flat? (execution-local-key? $ctx) (sk-answers $node)))
               (sk-fold-node-member (CPU FoldAllCompiled $args $result))))
         ((sk-group $args)
            (case (sk-group-members $key $args) (
               ((sk-group-found $_member $keys) (any-flat? (execution-local-key? $ctx) $keys))
               (sk-group-missing false))))
         ((sk-prior $args)
            (any-flat? (execution-local-prior? $ctx) (sk-prior-inputs (compound-rate-goals $args false $_rate))))
         ((sk-evidence ($_kb $type $_other $scope))
            (execution-local-prior? $ctx (sk-key $type $scope)))
         ($_ordinary false)))))
(: execution-local-prior? (-[det]-> Atom SkeletonKey Bool))
(= (execution-local-prior? $ctx $key)
   (if (execution-local-key? $ctx $key) true
      (not (== (collapse (once
         (if (execution-local-inputs? $ctx (index-hash $key) $key) true (empty)))) ()))))

;; Reader-specific views matter even when their merge is dominated. Storage
;; supplies snapshots and their pairs; the executor applies the reuse policy.
(: context-propagate? (-[semidet]-> SkeletonKey Bool))
(= (context-propagate? $key)
   (if (if (== (context-current) main) false (head-is? $key sk-key))
      (let $threshold (context-reuse-threshold)
         (if (== $threshold 0) true
            (let* (($before (case (context-propagated $key) (
                       (context-unread (context-with-scope main (|-> ($_unit)
                          (context-snapshot (sk-value $key sk-any-filter ()) (context-views $key)))))
                       ($snapshot $snapshot))))
                   ((context-snapshot $old $old-views) $before)
                   ($new (sk-value $key sk-any-filter ()))
                   ($views (context-views $key)))
               (if (if (execution-numerical-change? $threshold $old $new) true
                       (any-flat? (execution-view-changed? $threshold)
                          (context-view-changes (the (List (Number SkeletonValue)) $old-views) $views)))
                  (let $_stored (context-store-propagated! $key $new $views) true)
                  false))))
      true))

(: execution-numerical-change? (-[det]-> Number SkeletonValue SkeletonValue Bool))
(= (execution-numerical-change? $threshold $old $new)
   (let $scalar (case $old (
          (sk-none (case $new (((sk-val ($_t $_s $_p (STV $_mean $_c)) $_ev $_deps) true) ($_other false))))
          ((sk-val ($type $scope $_proof (STV $_s $_c)) $_ev $_deps)
             (case $new (
                (sk-none true)
                ((sk-val ($new-type $new-scope $_p (STV $_ns $_nc)) $_ne $_nd)
                   (=alpha ($type $scope) ($new-type $new-scope)))
                ($_other false))))
          ($_other false)))
      (if $scalar (> (sk-change $new $old) $threshold) (not (sk-same-view? $new $old)))))

;; Keep the typed pair destructure at this callback boundary: the compiled
;; lambda erases it and cannot certify the Boolean callback's determinism.
(: execution-view-changed? (-[det]-> Number (SkeletonValue SkeletonValue) Bool))
(= (execution-view-changed? $threshold ($before $after))
   (execution-numerical-change? $threshold $before $after))


;; How far a value moved: the KL divergence of its new Beta from its old one.
(: sk-change (-[det]-> SkeletonValue SkeletonValue Number))
(= (sk-change $new $old)
   (let* ((($a1 $b1) (sk-value-beta $new)) (($a2 $b2) (sk-value-beta $old)))
      (beta_kl $a1 $b1 $a2 $b2)))


;; --- Change -----------------------------------------------------------------

;; A value read as a Beta distribution over its strength, from its n
;; observations; no value is Beta(1, 1).
(: sk-value-beta (-[det]-> SkeletonValue (Number Number)))
(= (sk-value-beta $value)
   (case $value (
      ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps)
         (case $tv (
            ((STV $s $c) (sk-beta-of $s $c))
            ((CTV (STV $s $c) $_negative) (sk-beta-of $s $c))
            ($_other (data 1.0 1.0)))))
      ($_none (data 1.0 1.0)))))

(: sk-beta-of (-[det]-> Number Number (Number Number)))
(= (sk-beta-of $s $c)
   (let $n (confidence-to-count $c) (data (+ (* $s $n) 1.0) (+ (* (- 1.0 $s) $n) 1.0))))
