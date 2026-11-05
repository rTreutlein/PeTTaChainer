;; Forgetting (docs/metta/forgetting_design.md, stage 1).
;;
;; The caller marks time in epochs. A key that got no row and was not needed
;; for the horizon is frozen at an epoch boundary: its value becomes one
;; summary fact in &kb, with a discounted confidence, and its rows, views and
;; caches are dropped. The key is then a leaf its readers keep reading, so
;; what the skeleton holds and what a step costs stop growing with how long
;; the run has been.

;; Epochs a key may stay idle before it is frozen (0: never), and the factor
;; a summary's observation count is multiplied by; a point has no finite count
;; and stays a point. Process-wide.
!(change-state! forgetting_horizon 0)
!(change-state! forgetting_decay 1.0)

(: set-forgetting (-[det]-> Number Number Bool))
(= (set-forgetting $horizon $decay)
   (progn (change-state! forgetting_horizon $horizon) (change-state! forgetting_decay $decay)))

(: sk-decayed-tv (-[det]-> TV TV))
(= (sk-decayed-tv $tv)
   (case $tv (
      ((STV $s $c)
         (if (>= $c 1.0) $tv
            (STV $s (count-confidence (* (search-id-value forgetting_decay) (confidence-to-count $c))))))
      ($_other $tv))))

(: sk-premise-hashes-step (-[det]-> (List Number) (List SkPattern) (List Number)))
(= (sk-premise-hashes-step $acc $premises)
   (append-flat (map-flat index-hash (fold-flat sk-direct-key-step () $premises)) $acc))

(: sk-near-hashes-step (-[det]-> (List Number) Number (List Number)))
(= (sk-near-hashes-step $acc $hash)
   (fold-flat sk-premise-hashes-step $acc
      (collapse (match &sk_row ($hash $_key $_rhash (sk-row $_ident $_concl $premises $_seq)) $premises))))

;; A frozen key's rows leave with their reader links, stale marks and views.
(datatype SkeletonRowRef (sk-row-ref SkeletonKey Number SkeletonRow))

;; A frozen key nothing reads any more, and that is a member of no fold but
;; base rates and implication instance folds (which keep their members'
;; contributions), is buried: it leaves
;; the answers of open nodes, so a join or fold over an open pattern no longer
;; meets it, and its key and reader registrations, unifier cache, uses and
;; merged value go. Its summary stays a fact, and its own ground node still
;; answers with it, so a query for it reads the summary.
(: sk-read? (-[det]-> Number SkeletonKey Bool))
(= (sk-read? $hash $key)
   (if (space-row-present? &ctx_sk_reader ($hash $key $_khash $_rhash)) true
      (if (space-row-present? &ctx_sk_stale_reader ($hash $key $_skhash $_srhash)) true
         (not (== (collapse (once (match &sk_use ($hash $stored $fold)
                     (if (=alpha $stored $key) (if (sk-rate-fold? $fold) (empty) true) (empty)))))
                  ())))))

(: sk-forget-row! (-[semidet]-> Number SkeletonKey Atom SkeletonRowRef Atom))
(= (sk-forget-row! $hash $key $_acc (sk-row-ref $stored $rhash $row))
   (let* (($keys (case $row (((sk-row $_i $_c $premises $_s) (fold-semidet sk-direct-key-step () $premises)))))
          ($_row (sk-drop-row! $hash $stored $rhash $row))
          ($_folds (collapse (let $input (superpose $keys)
             (case $input (
                ((sk-key $_t $_c) (empty))
                ($_fold (if (sk-read? (index-hash $input) $input) ()
                   (let $_dropped (sk-drop-fold-view! $input) (sk-drop-merged! $input))))))))))
      ()))

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
                               (if (case $node ((($ntype $nctx $_np $_nt) (not (== (extract-vars (data $ntype $nctx)) ()))) ($_cpu false)))
                                  ($nhash $node) (empty)))
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

;; Aggregate rows and the incidental keys feeding their population search
;; are reconstructible cache entries, not historical observations. A key
;; with its own expanded node retains ordinary historical freezing unless
;; it reads an aggregate itself or is a statistical-fold member.
(: sk-replay-key? (-[det]-> Number SkeletonKey Bool))
(= (sk-replay-key? $hash $key)
   (if (not (== (collapse (once (match &sk_aggregate_row ($hash $stored $_rh)
                   (if (=alpha $stored $key) true (empty))))) ())) true
      (if (not (== (collapse (once (match &sk_use ($hash $member $fold)
                       (if (=alpha $member $key) (if (sk-rate-fold? $fold) true (empty)) (empty))))) ())) true
         (if (not (== (collapse (once (match &sk_expanded ($hash ($type $ctx $_p $_v))
                          (if (=alpha (sk-key $type $ctx) $key) true (empty))))) ())) false
         (let $readers (append-flat
                 (collapse (match &ctx_sk_reader ($hash $input $reader $rhash)
                    (if (=alpha $input $key) ($reader $rhash) (empty))))
                 (collapse (match &ctx_sk_stale_reader ($hash $stale-input $reader $rhash)
                    (if (=alpha $stale-input $key) ($reader $rhash) (empty)))))
            (not (== (collapse (once (let ($rkhash $rrhash) (superpose $readers)
                       (match &sk_aggregate_row ($rkhash $_rk $rrhash) true)))) ())))))))

;; Ends an epoch and freezes the keys idle for the horizon. Returns the new
;; epoch.
(: advance-epoch (-[semidet]-> Number))
(= (advance-epoch)
   (let* (($epoch (+ (next-search-id sk_epoch) 1)) ($horizon (search-id-value forgetting_horizon)))
      (if (<= $horizon 0) $epoch
         (let* (($cutoff (- $epoch $horizon))
                ($idle (collapse (match &sk_key_epoch ($hash $key $last)
                          (if (<= $last $cutoff)
                             (if (sk-rule-truth-key? $key) (empty) ($hash $key (sk-replay-key? $hash $key)))
                             (empty)))))
                ($_frozen (fold-semidet (sk-freeze! $epoch) () $idle))
                ($_buried (fold-semidet sk-bury! () (collapse (match &sk_frozen ($fhash $fkey) (sk-frozen $fhash $fkey)))))
                ($_collected (deps-gc! (sk-deps-roots))))
            $epoch))))

(datatype SkeletonFrozen (sk-frozen Number SkeletonKey))

;; The summary is the merge of what the key's rows derived; its stored facts
;; stay as they are. It keeps that value's evidence, so overlap with facts
;; stays exact, and depends on the key and the keys within two steps of it, so
;; self-support through a rule and its inversion stays excluded. What lies
;; further back is cut off, also for the values that read the key's views
;; before: their dependency nodes walk the summary's instead. Its confidence
;; is discounted by the decay, so evidence counted twice through what was cut
;; off enters with shrinking weight.
(: sk-freeze! (-[semidet]-> Number Atom (Number SkeletonKey Bool) Atom))
(= (sk-freeze! $epoch $_acc ($hash $key $replay))
   (let* (($value (fold-semidet (sk-merge-step (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) true (sk-unifier-hashes $hash $key)) sk-none (map-flat sk-version-view (sk-admitted-versions $hash $key sk-any-filter ()))))
          ($near (sk-near-hashes-step (cons $hash ()) $hash))
          ($window (fold-semidet sk-near-hashes-step $near $near))
          ($deps (deps-join (map-flat deps-key (hash-set $window))))
          ($views (collapse (match &ctx_sk_latest ($hash $stored (sk-version $_seq $_rhash $view))
                     (if (=alpha $stored $key) (sk-view-deps-step 0 $view) (empty)))))
          ($older (collapse (match &ctx_sk_view ($hash $stored $_rhash $view)
                     (if (=alpha $stored $key) (sk-view-deps-step 0 $view) (empty)))))
          ($_cut (deps-cut! (append-flat $views $older) $deps))
          ($rows (collapse (match &sk_row ($hash $stored $rhash $row)
                    (if (=alpha $stored $key) (sk-row-ref $stored $rhash $row) (empty)))))
          ($_rows (fold-semidet (sk-forget-row! $hash $key) () $rows))
          ($_merged (sk-drop-merged! $key))
          ($_taken (sk-forget-taken! $hash $key))
          ($_copy (kb-remove-prediction! $hash $key))
          ($_epoch (remove-data-rows! &sk_key_epoch (quote ($hash $key $_last))))
          ;; Exact-fold members remain registered across epochs. A key
          ;; becomes frozen once, however often the fold needs its fact.
          ($_frozen (if (== (collapse (once (match &sk_frozen ($hash $frozen-key)
                               (if (=alpha $frozen-key $key) true (empty))))) ())
                       (add-atom &sk_frozen ($hash $key)) ())))
      (if $replay
         (let* (($digest (link-digest $key))
                ($_joins (remove-data-rows! &sk_join_link (quote ($digest $_jd))))
                ($_nodes (collapse (match &sk_expanded ($hash $node)
                   (case $node (
                      (($type $ctx $_p $_tv)
                         (if (=alpha (sk-key $type $ctx) $key)
                            (let* (($_expanded (remove-atom &sk_expanded ($hash $node)))
                                   ;; Expanding it again defers its inversions anew.
                                   ($_deferred (collapse (match &sk_deferred_inversion ($hash $drule $downer $dmatch)
                                      (if (=alpha $downer $node)
                                         (remove-variant-row! &sk_deferred_inversion (quote ($hash $drule $downer $dmatch)))
                                         (empty)))))
                                   ($_terms (remove-atom &sk_node_terms ($type $ctx $node)))
                                   ($prefix (sk-node-prefix $type))
                                   ($_open (remove-variant-row! &sk_open_node (quote ($prefix $hash $node)))))
                               (sk-work! $hash $node 1)) (empty)))
                      ($_cpu (empty))))))))
            ())
      (case $value (
         ((sk-val ($type $kbctx $proof $tv) $ev $_deps)
            (kb-publish-summary! $hash $key $epoch
               (sk-val (assemble-runtime-fact $type $kbctx $proof (sk-decayed-tv $tv)) $ev $deps)))
         ($_none ()))))))
