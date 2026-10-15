!(import! &self ../../pettachainer/metta/petta_chainer)

;; Queue priority must not change need depths or consume the near-root reserve.
;; An ordinary path discovered after a completion path takes its usual place.
!(test
   (let* (($key (sk-key (Priority q) (priorityKb MAIN Nil)))
          ($hash (index-hash $key))
          ($fact (assemble-runtime-fact (Priority q) (priorityKb MAIN Nil) direct (STV 0.5 0.9)))
          ($row (sk-row (sk-ident 0 () $key) $fact () 7))
          ($item (sk-row-item 7 $hash $key 11 $row))
          ($_depth (add-atom &sk_needed ($hash $key 3)))
          ($reserve (search-id-value sk_near_reserve))
          ($_additional (sk-need-priority! 1 () $key))
          ($later (sk-item-order $item))
          ($_ordinary (sk-need-priority! 0 () $key))
          ($ordinary (sk-item-order $item))
          ($_again (sk-need-priority! 1 () $key)))
      (and (> $later (sk-check-seq))
         (and (== $ordinary 3000000000007)
            (and (== (sk-item-order $item) $ordinary)
               (and (== (sk-need-depth $hash $key) 3)
                  (== (search-id-value sk_near_reserve) $reserve)))))) true)

;; A newly eligible completion row stays behind ordinary rows and fold checks,
;; even when its conclusion is itself a root. It remains a queued, needed row.
!(test
   (let* (($key (sk-key (Priority root) (priorityKb MAIN Nil)))
          ($hash (index-hash $key))
          ($fact (assemble-runtime-fact (Priority root) (priorityKb MAIN Nil) direct (STV 0.5 0.9)))
          ($row (sk-row (sk-ident 0 () $key) $fact () 2))
          ($item (sk-row-item 2 $hash $key 12 $row))
          ($_depth (add-atom &sk_needed ($hash $key 0)))
          ($_root (sk-need-priority! 0 () $key))
          ($_completion (add-atom &sk_completion_work ($hash 12))))
      (and (> (sk-item-order $item) (sk-check-seq)) (sk-item-needed? $item))) true)

;; Forward waves preserve creation order regardless of query priority metadata.
!(change-state! sk_forward_run 1)
!(test
   (let* (($key (sk-key (Priority root) (priorityKb MAIN Nil)))
          ($hash (index-hash $key))
          ($fact (assemble-runtime-fact (Priority root) (priorityKb MAIN Nil) direct (STV 0.5 0.9)))
          ($row (sk-row (sk-ident 0 () $key) $fact () 2)))
      (sk-item-order (sk-row-item 2 $hash $key 12 $row))) 2)
!(test
   (let* (($key (sk-key (Priority fold) (priorityKb MAIN Nil)))
          ($hash (index-hash $key))
          ($_depth (add-atom &sk_needed ($hash $key 3)))
          ($_additional (sk-need-priority! 1 () $key)))
      (== (sk-item-order (sk-fold-check $hash $key)) (sk-check-seq))) true)
!(change-state! sk_forward_run 0)

;; Ordinary readers discovered later also promote a shared key, using the
;; existing reader index rather than annotating every ordinary premise.
!(test
   (let* (($key (sk-key (Priority shared) (priorityKb MAIN Nil)))
          ($hash (index-hash $key))
          ($reader (sk-key (Priority reader) (priorityKb MAIN Nil)))
          ($rhash (index-hash $reader))
          ($_depth (add-atom &sk_needed ($hash $key 3)))
          ($_reader (add-atom &sk_needed ($rhash $reader 0)))
          ($_additional (sk-need-priority! 1 () $key))
          ($before (sk-completion-needed? $hash $key))
          ($_link (add-atom &sk_reader ($hash $key $rhash 15)))
          ($ordinary (sk-completion-needed? $hash $key))
          ($_completion (add-atom &sk_completion_work ($rhash 15))))
      (and $before (and (not $ordinary) (sk-completion-needed? $hash $key)))) true)
