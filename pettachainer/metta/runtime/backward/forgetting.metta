;; Forgetting (docs/metta/forgetting_design.md, stage 1).
;;
;; The caller marks time in epochs. A key that got no row and was not needed
;; for the horizon is frozen at an epoch boundary: its value becomes one
;; summary fact in &kb, with a discounted confidence, and its rows, views and
;; caches are dropped. The key is then a leaf its readers keep reading, so
;; what the skeleton holds and what a step costs stop growing with how long
;; the run has been.

;; Epochs a key may stay idle before it is frozen (0: never), and the factor
;; a summary's observation count is multiplied by. Process-wide.
!(change-state! forgetting_horizon 0)
!(change-state! forgetting_decay 1.0)

(: set-forgetting (-[det]-> Number Number Bool))
(= (set-forgetting $horizon $decay)
   (progn (change-state! forgetting_horizon $horizon) (change-state! forgetting_decay $decay)))

(: sk-decayed-tv (-[det]-> TV TV))
(= (sk-decayed-tv $tv)
   (case $tv (
      ((STV $s $c)
         (STV $s (count-confidence (* (search-id-value forgetting_decay) (confidence-to-count $c)))))
      ($_other $tv))))

(: sk-premise-hashes-step (-[det]-> (List Number) (List SkPattern) (List Number)))
(= (sk-premise-hashes-step $acc $premises)
   (append-flat (map-flat index-hash (fold-flat sk-direct-key-step () $premises)) $acc))

(: sk-near-hashes-step (-[det]-> (List Number) Number (List Number)))
(= (sk-near-hashes-step $acc $hash)
   (fold-flat sk-premise-hashes-step $acc
      (collapse (match &sk_row ($hash $_key $_rhash (sk-row $_ident $_concl $premises $_seq)) $premises))))

;; A frozen key's rows leave with their reader links, stale marks and views.
(: SkeletonRowRef Type)
(: sk-row-ref (-[det]-> SkeletonKey Number SkeletonRow SkeletonRowRef))

(: sk-forget-row! (-[semidet]-> Number SkeletonKey Atom SkeletonRowRef Atom))
(= (sk-forget-row! $hash $key $_acc (sk-row-ref $stored $rhash $row))
   (let* (((sk-row $_ident $_concl $premises $_s) $row)
          ($keys (fold-semidet sk-direct-key-step () $premises))
          ($_row (remove-atom &sk_row ($hash $stored $rhash $row)))
          ($_readers (fold-semidet (sk-remove-reader! $hash $rhash) () $keys))
          ($_stale-readers (fold-semidet (sk-drop-stale-reader! $hash $rhash) () $keys))
          ($_stale (remove-atom &sk_stale ($hash $rhash))))
      (sk-drop-row-views! $hash $key $rhash)))

(: sk-forget-taken! (-[det]-> Number SkeletonKey Atom))
(= (sk-forget-taken! $hash $key)
   (let $_removed
      (collapse (match &sk_forward_taken ($hash $stored $value)
         (if (=alpha $stored $key) (remove-atom &sk_forward_taken ($hash $stored $value)) (empty))))
      ()))

(: sk-forget-forward-copy! (-[det]-> Number SkeletonKey Atom))
(= (sk-forget-forward-copy! $hash $key)
   (let $_removed
      (collapse (match &sk_forward_stored ($hash $stored $old $old-ev $old-deps)
         (if (=alpha $stored $key)
            (let* (($_kb (remove-atom &kb $old))
                   ($_unindex (kb-unindex-fact! $old)))
               (remove-atom &sk_forward_stored ($hash $stored $old $old-ev $old-deps)))
            (empty))))
      ()))

;; Ends an epoch and freezes the keys idle for the horizon. Returns the new
;; epoch.
(: advance-epoch (-[semidet]-> Number))
(= (advance-epoch)
   (let* (($epoch (+ (next-search-id sk_epoch) 1))
          ($horizon (search-id-value forgetting_horizon)))
      (if (<= $horizon 0) $epoch
         (let* (($cutoff (- $epoch $horizon))
                ($idle (collapse (match &sk_key_epoch ($hash $key $last)
                          (if (<= $last $cutoff) (sk-frozen $hash $key) (empty)))))
                ($_frozen (fold-semidet (sk-freeze! $epoch) () $idle)))
            $epoch))))

(: SkeletonFrozen Type)
(: sk-frozen (-[det]-> Number SkeletonKey SkeletonFrozen))

;; The summary is the merge of what the key's rows derived; its stored facts
;; stay as they are. It keeps that value's evidence, so overlap with facts
;; stays exact, and depends on the key and the keys within two steps of it, so
;; self-support through a rule and its inversion stays excluded. What lies
;; further back is cut off, also for the values that read the key's views
;; before: their dependency nodes walk the summary's instead. Its confidence
;; is discounted by the decay, so evidence counted twice through what was cut
;; off enters with shrinking weight.
(: sk-freeze! (-[semidet]-> Number Atom SkeletonFrozen Atom))
(= (sk-freeze! $epoch $_acc (sk-frozen $hash $key))
   (let* (($value (fold-semidet sk-merge-step sk-none (sk-admitted $hash $key sk-any-filter ())))
          ($near (sk-near-hashes-step (cons $hash ()) $hash))
          ($window (fold-semidet sk-near-hashes-step $near $near))
          ($deps (deps-join (map-flat deps-key (hash-set $window))))
          ($views (collapse (match &sk_latest ($hash $stored (sk-version $_seq $_rhash $view))
                     (if (=alpha $stored $key) (sk-view-deps-step 0 $view) (empty)))))
          ($older (collapse (match &sk_view ($hash $stored $_rhash $view)
                     (if (=alpha $stored $key) (sk-view-deps-step 0 $view) (empty)))))
          ($_cut (deps-cut! (append-flat $views $older) $deps))
          ($rows (collapse (match &sk_row ($hash $stored $rhash $row)
                    (if (=alpha $stored $key) (sk-row-ref $stored $rhash $row) (empty)))))
          ($_rows (fold-semidet (sk-forget-row! $hash $key) () $rows))
          ($_merged (sk-drop-merged! $key))
          ($_taken (sk-forget-taken! $hash $key))
          ($_copy (sk-forget-forward-copy! $hash $key))
          ($_epoch (remove-data-rows! &sk_key_epoch (quote ($hash $key $_last)))))
      (case $value (
         ((sk-val ($type $kbctx $_proof $tv) $ev $_deps)
            (let* (($summary (assemble-runtime-fact $type $kbctx (brand Proof (forgotten $hash $epoch)) (sk-decayed-tv $tv)))
                   ($_stored (add-atom &sk_summary ($hash $key $summary $ev $deps)))
                   ($_kb (add-atom &kb $summary)))
               (kb-index-fact! live $summary)))
         ($_none ())))))
