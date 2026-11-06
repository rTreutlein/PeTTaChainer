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
            (if (if (== $value sk-none) (<= (search-id-value sk_eval_budget) 0) false) ()
               (context-add! &sk_representative ($hash $key $rhash $given $exclude $value))))))))


;; The dependency sets the stores hold; every other node can go.
(: sk-deps-roots (-[det]-> (List Number)))
(= (sk-deps-roots)
   (append-flat (collapse (match &ctx_sk_latest ($_h $_k (sk-version $_s $_r $view)) (sk-view-deps-step 0 $view)))
   (append-flat (collapse (match &ctx_sk_summary_reference ($_rh $_rk $_rr $_pins $_cuts $_filter $ref) (sk-view-deps-step 0 $ref)))
   (append-flat (collapse (match &ctx_sk_representative ($_rh $_rk $_rr $_rep-given $_rep-exclude $rep) (sk-view-deps-step 0 $rep)))
   (append-flat (collapse (match &ctx_sk_view ($_vh $_vk $_vr $old) (sk-view-deps-step 0 $old)))
   (append-flat (collapse (match &ctx_sk_merged ($_mh $_mk $mdeps $_mv $_mroot) $mdeps))
   (append-flat (collapse (match &ctx_sk_merged ($_nh $_nk $_nd $value $_nroot) (sk-view-deps-step 0 $value)))
   (append-flat (collapse (match &ctx_sk_branch ($_slot2 $_bk2 $_br2 $_cuts $_fresh2 $branch) (sk-view-deps-step 0 $branch)))
   (append-flat (collapse (match &ctx_sk_support ($_sh $_sr $support) $support))
   (append-flat (collapse (match &sk_forward_stored ($_fh $_fk $_ff $_fe $fdeps) $fdeps))
   (append-flat (collapse (match &sk_forward_taken ($_th $_tk $taken) (sk-view-deps-step 0 $taken)))
      (collapse (match &sk_summary ($_yh $_yk $_yf $_ye $ydeps) $ydeps)))))))))))))
