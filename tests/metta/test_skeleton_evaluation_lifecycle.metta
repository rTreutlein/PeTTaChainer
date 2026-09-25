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
             ($_first (sk-force-cause! $hash $rhash 111))
             ($_second (sk-force-cause! $hash $rhash 222))
             ($_repeat (sk-force-cause! $hash $rhash 111))
             ($_other-key (sk-force-cause! -1 $rhash 444))
             ($_other-row (sk-force-cause! $hash -1 555))
             ($before (collapse (match &sk_forced ($hash $rhash $cause) $cause)))
             ($_computed (sk-compute 0 (sk-work (empty_heap) (empty_heap))
                (sk-row-item $seq $hash (sk-key (ForceRoot) (forceKb MAIN Nil)) $rhash
                   (sk-row $ident $concl $premises $seq))))
             ($after (collapse (match &sk_forced ($hash $rhash $cause) $cause)))
             ($_again (sk-force-cause! $hash $rhash 111))
             ($_third (sk-force-cause! $hash $rhash 333)))
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
              (collapse (match &sk_forced_used ($key $row $cause) true))
              (collapse (match &sk_queued ($pass $key $row) true))
              (collapse (match &sk_fold_pending ($fold $member) true))))
          ($_reuse (sk-force-cause! -1 -1 111)))
      ($cleared (collapse (match &sk_forced (-1 -1 $cause) $cause))))
   ((() () () ()) (111)))
!(test
   (collapse (query 0 forceKb (: $proof (ForceRoot) $tv)))
   ((: (by (no_inverse forceRule) seed) (ForceRoot) (STV 1.0 0.7999359651197002))))
