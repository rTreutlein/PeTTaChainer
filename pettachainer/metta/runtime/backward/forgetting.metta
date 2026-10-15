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
   (sk-drop-row! $hash $stored $rhash $row))

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
                   ($_unindex (kb-unindex-fact! $old))
                   ($_rules (forget-stored-rules! forward $hash $key)))
               (remove-atom &sk_forward_stored ($hash $stored $old $old-ev $old-deps)))
            (empty))))
      ()))

;; A frozen key nothing reads any more, and that is a member of no fold but
;; base rates and implication instance folds (which keep their members'
;; contributions), is buried: it leaves
;; the answers of open nodes, so a join or fold over an open pattern no longer
;; meets it, and its key and reader registrations, unifier cache, uses and
;; merged value go. Its summary stays a fact, and its own ground node still
;; answers with it, so a query for it reads the summary.
(: sk-read? (-[det]-> Number SkeletonKey Bool))
(= (sk-read? $hash $key)
   (if (space-row-present? &sk_reader ($hash $key $_khash $_rhash)) true
      (if (space-row-present? &sk_stale_reader ($hash $key $_skhash $_srhash)) true
         (not (== (collapse (once (match &sk_use ($hash $stored $fold)
                     (if (=alpha $stored $key) (if (sk-rate-fold? $fold) (empty) true) (empty)))))
                  ())))))

(: sk-open-node? (-[det]-> SkPattern Bool))
(= (sk-open-node? $node)
   (case $node (
      (($type $kbctx $_proof $_tv) (not (== (extract-vars (data $type $kbctx)) ())))
      ($_cpu false))))

(: sk-bury-answer! (-[det]-> SkeletonKey Atom (Number SkPattern) Atom))
(= (sk-bury-answer! $key $_acc ($nhash $node))
   (let* (($_answer (remove-atom &sk_answer ($nhash $node $key)))
          ($digest (link-digest (sk-answer-link $node $key)))
          ($_link (remove-atom &sk_link ($digest))))
      ()))

(: sk-bury! (-[semidet]-> Atom SkeletonFrozen Atom))
(= (sk-bury! $_acc (sk-frozen $hash $key))
   (if (sk-read? $hash $key) ()
      (case $key (
         ((sk-key $type $kbctx)
            (let* (($answers
                      (collapse (match &sk_answered ($hash $stored $nhash $node)
                         (if (=alpha $stored $key)
                            (let $_row (remove-atom &sk_answered ($hash $stored $nhash $node))
                               (if (sk-open-node? $node) ($nhash $node) (empty)))
                            (empty)))))
                   ($_answers (fold-flat (sk-bury-answer! $key) () $answers))
                   ($_uses
                      (collapse (match &sk_use ($hash $stored $fold)
                         (if (=alpha $stored $key) (remove-atom &sk_use ($hash $stored $fold)) (empty)))))
                   ($_unifiers
                      (collapse (match &sk_unifiers ($hash $stored $hashes)
                         (if (=alpha $stored $key) (remove-atom &sk_unifiers ($hash $stored $hashes)) (empty)))))
                   ($_merged (sk-drop-merged! $key))
                   ($_keys (remove-variant-row! &sk_keys (quote ($hash $key))))
                   ($_terms (sk-unindex-key! $type $kbctx $hash)))
               (remove-variant-row! &sk_frozen (quote ($hash $key)))))
         ($_fold ())))))

;; The dependency sets the stores hold; every other node can go.
(: sk-deps-roots (-[det]-> (List Number)))
(= (sk-deps-roots)
   (append-flat (collapse (match &sk_latest ($_h $_k (sk-version $_s $_r $view)) (sk-view-deps-step 0 $view)))
   (append-flat (collapse (match &sk_view ($_vh $_vk $_vr $old) (sk-view-deps-step 0 $old)))
   (append-flat (collapse (match &sk_merged ($_mh $_mk $mdeps $_mv) $mdeps))
   (append-flat (collapse (match &sk_merged ($_nh $_nk $_nd $value) (sk-view-deps-step 0 $value)))
   (append-flat (collapse (match &sk_support ($_sh $_sr $support) $support))
   (append-flat (collapse (match &sk_forward_stored ($_fh $_fk $_ff $_fe $fdeps) $fdeps))
   (append-flat (collapse (match &sk_forward_taken ($_th $_tk $taken) (sk-view-deps-step 0 $taken)))
      (collapse (match &sk_summary ($_yh $_yk $_yf $_ye $ydeps) $ydeps))))))))))

;; Ends an epoch and freezes the keys idle for the horizon. Returns the new
;; epoch.
(: advance-epoch (-[semidet]-> Number))
(= (advance-epoch)
   (let* (($epoch (+ (next-search-id sk_epoch) 1))
          ($horizon (search-id-value forgetting_horizon)))
      (if (<= $horizon 0) $epoch
         (let* (($cutoff (- $epoch $horizon))
                ($idle (collapse (match &sk_key_epoch ($hash $key $last)
                          (if (<= $last $cutoff)
                             ;; A model parameter keeps reading its live tally:
                             ;; freezing the truth disconnects future samples.
                             (if (sk-rule-truth-key? $key) (empty) (sk-frozen $hash $key))
                             (empty)))))
                ($_frozen (fold-semidet (sk-freeze! $epoch) () $idle))
                ($_buried (fold-semidet sk-bury! () (collapse (match &sk_frozen ($fhash $fkey) (sk-frozen $fhash $fkey)))))
                ($_collected (deps-gc! (sk-deps-roots))))
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
   (let* (($value (fold-semidet (sk-merge-step true (sk-unifier-hashes $hash $key)) sk-none (sk-admitted $hash $key sk-any-filter ())))
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
          ($_epoch (remove-data-rows! &sk_key_epoch (quote ($hash $key $_last))))
          ($_frozen (add-atom &sk_frozen ($hash $key))))
      (case $value (
         ((sk-val ($type $kbctx $proof $tv) $ev $_deps)
            (let* (($summary (assemble-runtime-fact $type $kbctx (brand Proof (forgotten $hash $epoch)) (sk-decayed-tv $tv)))
                   ($_provenance (record-summary-rules! $hash $epoch $proof))
                   ($_registered (record-stored-rules! summary $hash $key (brand Proof (forgotten $hash $epoch))))
                   ($_stored (add-atom &sk_summary ($hash $key $summary $ev $deps)))
                   ($_kb (add-atom &kb $summary)))
               (kb-index-fact! live $summary)))
         ($_none ())))))

;; Retirement visits only physical copies registered for a withdrawn identity.
;; A dead summary cannot preserve only its live contributors: thaw the key and
;; queue its live rules for reconstruction on the next search.
(= (sk-retire-store! (retired-store $kind $hash $key))
   (let* (($_removed
      (case $kind (
         (materialized
            (case $key (((sk-key $type $kbctx)
               (foreach-flat remove-materialized! (materialized-rows (forward-output-key $kbctx $type))))
                      ($_fold ()))))
         (forward (sk-forget-forward-copy! $hash $key))
         (summary
            (let* (($_summaries
                     (collapse (match &sk_summary ($hash $stored $fact $ev $deps)
                        (if (=alpha $stored $key)
                           (let* (($_kb (remove-atom &kb $fact))
                                  ($_index (kb-unindex-fact! $fact)))
                              (remove-atom &sk_summary ($hash $stored $fact $ev $deps)))
                           (empty)))))
                   ($key-digest (link-digest $key))
                   ($_joins (remove-data-rows! &sk_join_link (quote ($key-digest $_digest))))
                   ($_frozen (remove-variant-row! &sk_frozen (quote ($hash $key))))
                   ($_queued (add-atom &sk_thawed ($hash $key))))
               ())))))
          ($_merged (sk-drop-merged! $key)))
      (case $key (((sk-key $type $kbctx) (sk-note-fact! $type $kbctx)) ($_fold ())))))
