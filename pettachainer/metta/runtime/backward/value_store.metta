;; Value-store owner: publication, retained versions, exclusion branches and
;; query-local value caches leave through the same lifecycle boundary.
;; All writes use the context facade, preserving MAIN/Assuming separation.

(: sk-branch-values (-[semidet]-> Number SkeletonKey Number (List Number) Bool (List SkeletonValue)))
(= (sk-branch-values $slot $key $rhash $exclude $fresh)
   (case (fold-semidet sk-cons-step ()
      (collapse (match &ctx_sk_branch ($slot $stored $rhash $cuts $fresh $view)
         (if (=alpha $stored $key)
            (if (hash-subset? $cuts $exclude)
               (if (sk-excludes? $exclude (sk-view-deps-step 0 $view)) (empty)
                  (if (sk-live-view? $view)
                     (if (if $fresh true (not (== $view sk-none))) (sk-cut-view $cuts $view) (empty)) (empty)))
               (empty)) (empty))))) (
      (() ())
      ((cons (sk-cut-view $used $value) $_rest)
         (let $_cuts (sk-note-cuts! (the (List Number) $used)) (cons $value ()))))))

(: sk-cache-branch!
   (-[semidet]-> Number Number SkeletonKey Number (List SkeletonKey) (List Number) Bool SkeletonValue SkeletonValue))
(= (sk-cache-branch! $slot $hash $key $rhash $inputs $cuts $fresh $view)
   (let* (($deps (sk-view-deps-step 0 $view))
          ($_dominated (if $fresh
             (collapse (match &ctx_sk_branch ($slot $stored $rhash $old-cuts $old-fresh $old)
                (if (=alpha $stored $key)
                   (if (if (hash-subset? $cuts $old-cuts) (deps-within? $deps (sk-view-deps-step 0 $old)) false)
                      (remove-variant-row! &sk_branch (quote ($slot $stored $rhash $old-cuts $old-fresh $old))) (empty))
                   (empty)))) ()))
          ($_owner
             (if (not (== (collapse (once (match &ctx_sk_branch_owner ($slot $hash $stored-owner $rhash $_inputs)
                              (if (=alpha $stored-owner $key) true (empty))))) ()))
                (if (space-row-present? &ctx_sk_branch_dirty ($slot))
                   (fold-semidet (sk-branch-link! $slot) () $inputs) ())
                (let* (($_registered (context-add! &sk_branch_owner ($slot $hash $key $rhash $inputs)))
                       ($_readers (fold-semidet (sk-branch-link! $slot) () $inputs))) ())))
          ($_clean (context-remove! &sk_branch_dirty ($slot)))
          ($_stored (context-add! &sk_branch ($slot $key $rhash $cuts $fresh $view)))
          ($kept (collapse (match &ctx_sk_branch ($slot $kept-key $rhash $kept-cuts $kept-fresh $kept-view)
                    (if (=alpha $kept-key $key) ($kept-key $kept-cuts $kept-fresh $kept-view) (empty)))))
          ($_bounded
             (collapse (let (cons ($oldest-key $oldest-cuts $oldest-fresh $oldest-view) $_rest)
                              (if (> (length $kept) 8) $kept (empty))
                (remove-variant-row! &sk_branch (quote ($slot $oldest-key $rhash $oldest-cuts $oldest-fresh $oldest-view)))))))
      $view))

(: sk-older-views (-[det]-> Number SkeletonKey Number (List SkeletonValue)))
(= (sk-older-views $hash $key $rhash)
   (collapse (match &ctx_sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))

(: sk-latest-view (-[det]-> Number SkeletonKey Number SkeletonValue))
(= (sk-latest-view $hash $key $rhash)
   (chainer-first-or sk-none
      (collapse (once (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
         (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))))

;; A new view becomes the row's latest; the one it replaces is kept.
(: sk-store-view! (-[semidet]-> Number SkeletonKey Number Number SkeletonValue SkeletonValue))
(= (sk-store-view! $hash $key $seq $rhash $view)
   (let* (($deps (sk-view-deps-step 0 $view))
          ($previous
             (collapse (match &ctx_sk_latest ($hash $stored (sk-version $old-seq $rhash $old))
                (if (=alpha $stored $key)
                   (let* (($_invalidated (if (sk-same-view? $view (if (sk-live-view? $old) $old sk-none)) ()
                                            (sk-invalidate-branches! $key)))
                          ($_removed (context-remove! &sk_latest ($hash $stored (sk-version $old-seq $rhash $old)))))
                      (if (sk-dominated? $deps $old) () (context-add! &sk_view ($hash $stored $rhash $old))))
                   (empty)))))
          ($_first (if (== $previous ()) (sk-invalidate-branches! $key) ()))
          ($_pruned
             (collapse (match &ctx_sk_view ($hash $stored $rhash $older)
                (if (=alpha $stored $key)
                   (if (sk-dominated? $deps $older) (remove-variant-row! &sk_view (quote ($hash $stored $rhash $older))) (empty))
                   (empty)))))
          ($support (deps-union (sk-row-support $hash $rhash) $deps))
          ($_old-support (remove-data-rows! &sk_support (quote ($hash $rhash $_had))))
          ($_support (context-add! &sk_support ($hash $rhash $support)))
          ($_added (context-add! &sk_latest ($hash $key (sk-version $seq $rhash $view)))))
      $view))

(: sk-dominated? (-[semidet]-> Number SkeletonValue Bool))
(= (sk-dominated? $deps $older) (deps-mask-within? $deps (sk-view-deps-step 0 $older)))

(: sk-row-support (-[det]-> Number Number Number))
(= (sk-row-support $hash $rhash)
   (chainer-first-or 0 (collapse (once (match &ctx_sk_support ($hash $rhash $deps) $deps)))))

(: sk-branch-link! (-[det]-> Number Atom SkeletonKey Atom))
(: sk-branch-unlink! (-[det]-> Number Atom SkeletonKey Atom))
(: sk-invalidate-branches! (-[det]-> SkeletonKey Atom))
(: sk-drop-branch! (-[det]-> Atom Number Atom))
(: sk-stale-branch! (-[det]-> Atom Number Atom))
(= (sk-branch-link! $slot $_acc $input)
   (let $ihash (index-hash $input) (context-add! &sk_branch_reader ($ihash $input $slot))))

(= (sk-branch-unlink! $slot $_acc $input)
   (let $ihash (index-hash $input)
      (remove-variant-row! &sk_branch_reader (quote ($ihash $input $slot)))))

;; Erase before cascading, so cycles stop at the first already erased owner.
;; The ordinary views remain valid. Only their cached exclusion reads change.
(= (sk-drop-branch! $_acc $slot)
   (let* (($_wanted (remove-data-rows! &sk_branch_wanted (quote ($slot $_hash $_key $_rhash $_exclude))))
          ($_dropped
             (collapse (match &ctx_sk_branch_owner ($slot $hash $key $rhash $inputs)
                (let* (($_owner (remove-variant-row! &sk_branch_owner (quote ($slot $hash $key $rhash $inputs))))
                       ($_views (remove-data-rows! &sk_branch (quote ($slot $_key $_rhash $_cuts $_fresh $_view))))
                       ($_dirty (context-remove! &sk_branch_dirty ($slot)))
                       ($_inputs (fold-semidet (sk-branch-unlink! $slot) () $inputs)))
                   (sk-invalidate-branches! $key))))))
      ()))

(= (sk-stale-branch! $_acc $slot)
   (if (space-row-present? &ctx_sk_branch_dirty ($slot)) ()
      (let $_staled
         (collapse (match &ctx_sk_branch_owner ($slot $_hash $key $_rhash $inputs)
            (let* (($_dirty (context-add! &sk_branch_dirty ($slot)))
                   ($_unlinked (fold-semidet (sk-branch-unlink! $slot) () $inputs))
                   ($_wanted
                      (if (== (search-id-value sk_holding) 1)
                         (collapse (match &ctx_sk_branch_hold ($slot $hash $held $row $exclude)
                            (if (space-row-present? &ctx_sk_branch_wanted ($slot $hash $held $row $exclude)) ()
                               (context-add! &sk_branch_wanted ($slot $hash $held $row $exclude))))) ()))
                   ($_views
                      (collapse (match &ctx_sk_branch ($slot $stored $rhash $cuts true $view)
                         (let $_old (remove-variant-row! &sk_branch (quote ($slot $stored $rhash $cuts true $view)))
                            (context-add! &sk_branch ($slot $stored $rhash $cuts false $view)))))))
               (sk-invalidate-branches! $key))))
         ())))

(= (sk-invalidate-branches! $key)
   (let* (($hash (index-hash $key))
          ($_dropped (collapse (fold-semidet sk-stale-branch! ()
             (collapse (match &ctx_sk_branch_reader ($hash $stored $slot)
                (if (=alpha $stored $key) $slot (empty))))))))
      ()))

;; A row's latest view and the views it replaced.
(: sk-drop-row-views! (-[det]-> Number SkeletonKey Number Atom))
(= (sk-drop-row-views! $hash $key $rhash)
   (let* (($_root (sk-clear-root-cap! $hash $key))
          ($_branches (sk-drop-branch! () (index-hash ($hash $rhash))))
          ($_latest
             (collapse (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
                (if (=alpha $stored $key)
                   (let $_changed (if (== $view sk-none) () (sk-invalidate-branches! $key))
                      (context-remove! &sk_latest ($hash $stored (sk-version $seq $rhash $view))))
                   (empty)))))
          ($_older
             (collapse (match &ctx_sk_view ($hash $stored $rhash $view)
                (if (=alpha $stored $key) (context-remove! &sk_view ($hash $stored $rhash $view)) (empty)))))
          ($_representatives
             (collapse (match &ctx_sk_representative ($hash $rep-key $rhash $rep-given $rep-exclude $rep-value)
                (if (=alpha $rep-key $key)
                   (context-remove! &sk_representative ($hash $rep-key $rhash $rep-given $rep-exclude $rep-value)) (empty)))))
          ($_references
             (collapse (match &ctx_sk_summary_reference ($hash $rep-key $rhash $rep-given $rep-exclude $rep-filter $rep-value)
                (if (=alpha $rep-key $key)
                   (context-remove! &sk_summary_reference ($hash $rep-key $rhash $rep-given $rep-exclude $rep-filter $rep-value)) (empty)))))
          ($_support (remove-data-rows! &sk_support (quote ($hash $rhash $_deps)))))
      ()))

;; Whether a view brings a dependency none of the row's views had.
(: sk-new-support? (-[semidet]-> Number Number SkeletonValue Bool))
(= (sk-new-support? $hash $rhash $new)
   (if (deps-within? (sk-view-deps-step 0 $new) (sk-row-support $hash $rhash)) false true))

;; Confidence can weaken when a filtered premise loses a view even though
;; it adds no logical dependency. Retain that correction just as new support;
;; its strength, evidence and dependency support must be identical.
(: sk-weaker-view? (-[det]-> SkeletonValue SkeletonValue Bool))
(= (sk-weaker-view? $new $old)
   (case (data $new $old) (
      (((sk-val ($type $scope $proof (STV $s $c)) $ev $deps)
        (sk-val ($old-type $old-scope $old-proof (STV $old-s $old-c)) $old-ev $old-deps))
         (if (< $c $old-c)
            (let* (($sources (proof-unsettled-sources $proof))
                   ($old-sources (proof-unsettled-sources $old-proof)))
               (if (hash-subset? $sources $old-sources) false
                  (=alpha (data $type $scope $s $ev $deps) (data $old-type $old-scope $old-s $old-ev $old-deps)))) false))
      ($_other false))))

;; A fold's provenance counts as a change: a complete fold may replace a cached
;; estimate of the same truth value.
(: sk-view-step-proof (-[det]-> SkeletonValue Proof))
(= (sk-view-step-proof $view)
   (case $view (
      ((sk-goal-val $_goal $proof $_ev $_deps) (sk-step-proof $proof))
      ((sk-val ($_type $_scope $proof $_tv) $_ev $_deps) (sk-step-proof $proof))
      (sk-none (brand Proof none)))))

;; Commit evaluation results without scheduling readers or reading recursively.
;; Preserve outside causes. A merge refresh carries the old cache snapshot so
;; the scheduler can distinguish a value change from provenance-only refresh.
(: sk-commit-result! (-[semidet]-> Number SkeletonKey Number Number (List Number) SkeletonValue SkeletonCommit))
(= (sk-commit-result! $hash $key $seq $rhash $causes $new)
   (let $forced (not (== $causes ()))
      (case $new (
         ;; A row forced by an outside change that no longer derives anything
         ;; (a premise fact was removed) drops its views, and its key changed;
         ;; one waiting for conditioning keeps them.
         ;; A row that derived nothing records empty support: it was computed,
         ;; so a fold over its key does not wait for it (sk-member-pending?).
         (sk-none
            (if (if $forced
                   (if (== (sk-latest-view $hash $key $rhash) sk-none) false
                      (not (space-row-present? &ctx_sk_given_pending ($hash $rhash $_waits))))
                   false)
               (let* (($_views (sk-drop-row-views! $hash $key $rhash))
                      ($_merged (sk-drop-merged! $key))
                      ($_derived-nothing (context-add! &sk_support ($hash $rhash 0))))
                  (sk-committed (sk-outside-change $causes 0)))
               ;; A closed reader of a complete key evaluates its rows again,
               ;; so a new row that derives nothing, or a forced one, still
               ;; changes the key for it.
               (let* (($first (not (space-row-present? &ctx_sk_support ($hash $rhash $_had))))
                      ($_nothing (if $first (context-add! &sk_support ($hash $rhash 0)) true)))
                  (if (if (if $first true $forced)
                         (case $key (((sk-key $type $kbctx) (complete-statement? $type $kbctx)) ($_fold false)))
                         false)
                     (sk-committed (if $forced (sk-outside-change $causes 0) (sk-view-change 0 ())))
                     sk-uncommitted))))
         ($_view
            (let $latest (sk-latest-view $hash $key $rhash)
            (if (if (sk-same-view? $new $latest)
                   (if $forced (== (sk-view-step-proof $new) (sk-view-step-proof $latest)) true)
                   (if $forced false
                      (if (== $latest sk-none) false
                         (if (if (sk-new-support? $hash $rhash $new) true (sk-weaker-view? $new $latest)) false
                            (let $_unsupported (query_metric_increment views-without-support) true)))))
               sk-uncommitted
               (let* (($before
                         (collapse (once (match &ctx_sk_merged ($hash $stored $deps $value $cached-root)
                            (if (=alpha $stored $key) (if (sk-live-view? $value) (sk-merged $hash $stored $deps $value) (empty)) (empty))))))
                      ($_stored (sk-store-view! $hash $key $seq $rhash $new))
                      ($_stored-count (query_metric_increment views-stored))
                      ($_merged (sk-drop-merged! $key))
                      ($deps (sk-view-deps-step 0 $new)))
                  (if (if $forced (not (sk-same-view? $new $latest)) false)
                     (sk-committed (sk-outside-change $causes $deps))
                     (sk-merge-refresh $deps $causes $before))))))))))

(: sk-request-branch! (-[det]-> Number Number SkeletonKey Number (List Number) Atom))
(= (sk-request-branch! $slot $hash $key $rhash $exclude)
   (if (== (collapse (once (match &ctx_sk_branch_wanted ($slot $hash $wanted $rhash $exclude)
                  (if (=alpha $wanted $key) true (empty))))) ())
      (context-add! &sk_branch_wanted ($slot $hash $key $rhash $exclude)) ()))

;; Remove the delivered request only after the build, retaining unfinished work.
(: sk-finish-branch-request! (-[semidet]-> Number Number SkeletonKey Number (List Number) Atom))
(= (sk-finish-branch-request! $slot $hash $key $rhash $exclude)
   (let* (($_taken (remove-variant-row! &sk_branch_wanted (quote ($slot $hash $key $rhash $exclude))))
          ($settled (not (== (sk-branch-values $slot $key $rhash $exclude true) ()))))
      (if $settled true (context-add! &sk_branch_wanted ($slot $hash $key $rhash $exclude)))))

(: sk-clear-query-values! (-[det]-> Bool))
(= (sk-clear-query-values!)
   (progn
      (context-remove! &sk_summary_reference (quote ($_hash $_key $_row $_given $_exclude $_filter $_value)))
      (context-remove! &sk_representative (quote ($_rep-hash $_rep-key $_rep-row $_rep-given $_rep-exclude $_rep-value)))))

(: sk-live-view? (-[det]-> SkeletonValue Bool))
(= (sk-live-view? $view)
   (case $view (
      ((sk-val ($_type $_kbctx $proof $_tv) $_ev $_deps) (proof-live? $proof))
      ((sk-goal-val $_goal $proof $_ev $_deps) (proof-live? $proof))
      (sk-none true))))

(: sk-excludes? (-[det]-> (List Number) Number Bool))
(= (sk-excludes? $exclude $deps)
   (if (deps-meet? $exclude $deps)
      (let $_cut (if (== (search-id-value sk_branch_at) 0) ()
                    (sk-note-cuts! (deps-excluded $exclude $deps)))
         true)
      false))

;; Closed reads may use their own pins and direct observations, but cannot
;; cross the exclusions of the branch being rebuilt around them.
(: sk-branch-excludes? (-[semidet]-> Number Bool))
(= (sk-branch-excludes? $deps)
   (let $frame (search-id-value sk_branch_at)
      (if (== $frame 0) false
         (let (cons $exclude $_rest) (collapse (once
                 (match &sk_branch_cuts ($frame $exclude $_cuts) $exclude)))
            (sk-excludes? (the (List Number) $exclude) $deps)))))

(: sk-note-cuts! (-[det]-> (List Number) Atom))
(= (sk-note-cuts! $cuts)
   (let $frame (search-id-value sk_branch_at)
      (if (if (== $frame 0) true (== $cuts ())) ()
         (let $_noted (collapse (match &sk_branch_cuts ($frame $exclude $old)
                (let* (($both (hash-union $old $cuts))
                       ($_old (remove-variant-row! &sk_branch_cuts (quote ($frame $exclude $old)))))
                   (add-atom &sk_branch_cuts ($frame $exclude $both)))))
            ()))))

(: sk-view-deps-step (-[semidet]-> Number SkeletonValue Number))
(= (sk-view-deps-step $deps $view)
   (case $view (
      ((sk-val $_fact $_ev $view-deps) (deps-union $deps $view-deps))
      ((sk-goal-val $_goal $_proof $_ev $view-deps) (deps-union $deps $view-deps))
      (sk-none $deps))))

(: sk-same-view? (-[det]-> SkeletonValue SkeletonValue Bool))
(= (sk-same-view? $new $old)
   (case $new (
      ((sk-val ($type $kbctx $_proof $tv) $ev $deps)
         (case $old (
            ((sk-val ($old-type $old-kbctx $_old-proof $old-tv) $old-ev $old-deps)
               (if (=alpha (data $type $kbctx $tv) (data $old-type $old-kbctx $old-tv))
                  (if (=alpha $ev $old-ev) (=alpha $deps $old-deps) false) false))
            ($_other false))))
      ((sk-goal-val $goal $_proof $ev $deps)
         (case $old (
            ((sk-goal-val $old-goal $_old-proof $old-ev $old-deps)
               (if (=alpha $goal $old-goal) (if (=alpha $ev $old-ev) (=alpha $deps $old-deps) false) false))
            ($_other false))))
      (sk-none (== $old sk-none)))))

(: sk-drop-merged! (-[det]-> SkeletonKey Atom))
(= (sk-drop-merged! $key)
   (let* (($hash (index-hash $key))
          ($_unpaid (remove-data-rows! &sk_given_pending (quote ($hash -1 $_cost)))))
      (sk-uncache! $hash $key)))

;; A merge conditioning a key may read the key again through a shared
;; statement's value, which caches the key's fallback first; the conditioned
;; value replaces it.
(: sk-uncache! (-[det]-> Number SkeletonKey Atom))
(= (sk-uncache! $hash $key)
   (let $_dropped
         (collapse (match &ctx_sk_merged ($hash $stored $deps $value $cached-root)
            (if (=alpha $stored $key)
               (context-remove! &sk_merged ($hash $stored $deps $value $cached-root))
               (empty))))
      ()))

(: sk-cache-summary-reference!
   (-[semidet]-> Number SkeletonKey Number (List SkeletonGiven) (List Number) SkeletonFilter SkeletonValue Atom))
(= (sk-cache-summary-reference! $hash $key $rhash $given $exclude $filter $value)
   (collapse (once (match &sk_row
      ($hash $stored $rhash (sk-row $_id $_concl $premises $_seq))
      (if (=alpha $stored $key)
         (let $volatile (fold-flat
            (|-> ($seen $premise)
               (if $seen true
                  (case $premise (
                     ((CPU rule-likelihood-read $_likelihood-args $_likelihood-res) true)
                     ((CPU $_cpu-fun $_cpu-args $_cpu-res) false)
                     (($premise-type $_premise-scope $_premise-proof $_premise-tv)
                        (head-is? $premise-type RuleTruth))))))
            false $premises)
            (if $volatile ()
               (context-add! &sk_summary_reference ($hash $key $rhash $given $exclude $filter $value))))
         (empty))))))

;; The in-progress marker breaks replay cycles; an exhausted empty replay
;; must not be memoized as a settled absence.
(datatype RepresentativeUpdate sk-representative-enter (sk-representative-result SkeletonValue))
(: sk-update-representative!
   (-[det]-> Number SkeletonKey Number (List SkeletonGiven) (List Number) RepresentativeUpdate Atom))
(= (sk-update-representative! $hash $key $rhash $given $exclude $update)
   (case $update (
      (sk-representative-enter (context-add! &sk_representative ($hash $key $rhash $given $exclude sk-none)))
      ((sk-representative-result $value)
         (let $_left (context-remove! &sk_representative ($hash $key $rhash $given $exclude sk-none))
            (if (if (== $value sk-none) (== (search-id-value sk_representative_budget) 0) false) ()
               (context-add! &sk_representative ($hash $key $rhash $given $exclude $value))))))))
