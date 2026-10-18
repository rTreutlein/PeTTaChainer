!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd forceKb (: seed (ForceSeed) (STV 1.0 0.8)))
!(compileadd forceKb
   (: (no_inverse forceRule) (Implication (ForceSeed) (ForceRoot))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (length (collapse (query 20 forceKb (: $proof (ForceRoot) $tv)))) 1)

;; Consuming a row's pending causes preserves their first-arrival order and
;; their evaluation-wide deduplication. Other keys and rows remain pending.
!(test
   (match &sk_row ($hash (sk-key (ForceRoot) (forceKb MAIN Nil)) $rhash
                     (sk-row $ident $concl $premises $seq))
      (let* (($_reset (sk-evaluate!))
             ($_first (sk-force-causes! $hash $rhash ()))
             ($_second (sk-force-causes! $hash $rhash (111 222 111)))
             ($_repeat (sk-force-causes! $hash $rhash (222 111)))
             ($_other-key (sk-force-causes! -1 $rhash (444)))
             ($_other-row (sk-force-causes! $hash -1 (555)))
             ($before (collapse (match &sk_forced ($hash $rhash $cause) $cause)))
             ($_computed (sk-compute 0 $seq (sk-work (empty_heap) (empty_heap))
                (sk-row-item $seq $hash (sk-key (ForceRoot) (forceKb MAIN Nil)) $rhash
                   (sk-row $ident $concl $premises $seq))))
             ($after (collapse (match &sk_forced ($hash $rhash $cause) $cause)))
             ($_again (sk-force-causes! $hash $rhash (111)))
             ($_third (sk-force-causes! $hash $rhash (333))))
         ($before $after
          (collapse (match &sk_forced ($hash $rhash $cause) $cause))
          (collapse (match &sk_forced (-1 $rhash $cause) $cause))
          (collapse (match &sk_forced ($hash -1 $cause) $cause)))))
   ((111 222) () (333) (444) (555)))

;; The next evaluation clears every temporary tuple, including open first
;; columns, and allows a previously used cause again. Repeated empty resets
;; remain deterministic and preserve durable proofs.
!(add-atom &sk_queued (99 88 77))
!(add-atom &sk_fold_pending (66 55))
!(test
   (let* (($_first (sk-evaluate!))
          ($_empty (sk-evaluate!))
          ($cleared
             ((collapse (match &sk_forced ($key $row $cause) true))
              (collapse (match &sk_queued ($pass $key $row) true))
              (collapse (match &sk_fold_pending ($fold $member) true))))
          ($_reuse (sk-force-causes! -1 -1 (111))))
      ($cleared (collapse (match &sk_forced (-1 -1 $cause) $cause))))
   ((() () ()) (111)))
!(test
   (collapse (query 0 forceKb (: $proof (ForceRoot) $tv)))
   ((: (by (no_inverse forceRule) seed) (ForceRoot) (STV 1.0 0.7999359651197002))))

;; Invalidation re-requests every held exclusion context on this slot. The
;; hold journal is query-local and leaves when answers have been captured.
!(test
   (match &sk_row ($hash (sk-key (ForceRoot) (forceKb MAIN Nil)) $rhash
                     (sk-row $ident $concl $premises $seq))
      (let* (($key (sk-key (ForceRoot) (forceKb MAIN Nil)))
             ($slot (index-hash ($hash $rhash)))
             ($view (sk-latest-view $hash $key $rhash))
             ($_cached (sk-cache-branch! $slot $hash $key $rhash
                (cons (sk-key (ForceSeed) (forceKb MAIN Nil)) ()) () true $view))
             ($_holding (change-state! sk_holding 1))
             ($_reading (add-atom &sk_reading ($hash $key $rhash)))
             ($_first (sk-hold-branch-reader! $slot $key $rhash (111)))
             ($_second (sk-hold-branch-reader! $slot $key $rhash (222)))
             ($_read (remove-variant-row! &sk_reading (quote ($hash $key $rhash))))
             ($_dirty (sk-stale-branch! () $slot))
             ($requested (collapse (match &ctx_sk_branch_wanted ($slot $hash $key $rhash $exclude) $exclude)))
             ($_released (sk-stale-held!)))
         ($requested (collapse (match &ctx_sk_branch_hold ($slot $_h $_k $_r $_e) true)))))
   (((111) (222)) ()))
