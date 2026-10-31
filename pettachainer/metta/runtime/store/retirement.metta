;; Retirement visits only physical copies registered for a withdrawn identity.
;; A dead summary cannot preserve only its live contributors: thaw the key and
;; queue its live rules for reconstruction on the next search.
(= (sk-retire-store! (retired-store $kind $hash $key))
   (let* (($_removed (kb-retire-copy! $kind $hash $key))
          ($_thawed
             (if (== $kind summary)
                (let* (($key-digest (link-digest $key))
                       ($_joins (remove-data-rows! &sk_join_link (quote ($key-digest $_digest))))
                       ($_frozen (remove-variant-row! &sk_frozen (quote ($hash $key))))
                       ($_queued (add-atom &sk_thawed ($hash $key))))
                   ())
                ()))
          ($_merged (sk-drop-merged! $key)))
      (case $key (((sk-key $type $kbctx) (sk-note-fact! $type $kbctx)) ($_fold ())))))
