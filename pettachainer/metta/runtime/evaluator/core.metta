;; Recursive value, row and conditioning reads.

(: rule-likelihood-read
   (-[semidet]-> KB Proof Statement Statement LikelihoodRead LikelihoodContext LikelihoodRead))
(= (rule-likelihood-read $kb $rule $_antecedent $consequent
      (likelihood-read $initial $initial-read $initial-source) (likelihood-context $exclude $observation))
   (let (CTV (STV $_u $cu) (STV $_v $cv)) $initial
      (if (if (>= $cu 1.0) (>= $cv 1.0) false)
         (likelihood-read $initial $initial-read $initial-source)
         (let* (((likelihood-read $raw $read $source)
                   (case $initial-source (
                      ((negative-source $atv $btv $itv)
                         (with-positive-branch $itv
                            (ImplicationLikelihoodsFormula $atv $btv $itv (unknown-branch-centre $kb $consequent))))
                      ((stated $_original) (likelihood-read $initial $initial-read $initial-source)))))
                ($fold (case $source (
                   ((stated (CTV (STV $_s $pc) (STV $_n $nc)))
                      (if (if (<= $pc 0) (<= $nc 0) false) (sk-rule-fold $kb $rule) no-rule-fold))
                   ($_inferred no-rule-fold))))
                ($support (case $fold (
                   ((rule-fold $key) (likelihood-support-counts $key))
                   ($_unknown (support-counts 0 0 0 1 0)))))
                ($centre (if (user-base-rate? $kb $consequent)
                            (case (once (cached-base-rate $kb $consequent)) (
                               ((cons (STV $g $gc) $_rest) (STV $g $gc))
                               ($_none no-evidence)))
                            (case $fold (
                               ((rule-fold $key)
                                  (case (collapse (once (sk-computed-centre (sk-value-reader sk-value) $kb $consequent
                                           (source-list-union (likelihood-sources $key 0) (observation-sources $observation)) $exclude))) (
                                     ((cons $found ()) (the OptionalSTV $found))
                                     (() no-evidence))))
                               ($_unknown no-evidence)))))
                ($centres (case $centre (
                   ((STV $g $gc) (CTV (STV $g $gc) (STV $g $gc)))
                   (no-evidence (likelihood-centres $raw $support)))))
                ($prepared (read-likelihoods $raw $centres $support)))
            (case (data $source $prepared $read) (
               (((inferred-negative $atv $btv $_itv $_centre)
                 (likelihood-read $original (CTV $positive $_negative) $provenance)
                 (CTV $_read-pos $read-negative))
                  (likelihood-read $original (CTV $positive $read-negative)
                     (resolved-negative $atv $btv $provenance)))
               ($_stated $prepared)))))))

;; Condition a target on a compound's parts in order, weighting each part given
;; the compound and preceding parts. A part that cannot mix adds no pin.
(: sk-chain-value (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) SkeletonValue))
(= (sk-chain-value $given $target $wexclude $parts)
   (case $parts (
      (() (sk-target-value $given $target))
      ((cons $part $rest)
         (let* (($phash (index-hash $part))
                ($yes (sk-chain-value (cons (sk-given $phash $part true) $given) $target $wexclude $rest))
                ($no (sk-chain-value (cons (sk-given $phash $part false) $given) $target $wexclude $rest))
                ($weight
                   (case (sk-calibrated-value $given $part sk-any-filter $wexclude
                            (sk-pinned-value $given $part sk-any-filter $wexclude)) (
                      (sk-none
                         (case (sk-cavity-prior (sk-value-reader sk-value) $part (ev-set 0) $wexclude) (
                            (sk-none
                               (case $part (
                                  ((sk-key $type $kbctx)
                                     (sk-val (assemble-runtime-fact $type $kbctx (brand Proof cpu) (STV 0.5 0.0)) (ev-set 0) 0))
                                  ($_fold sk-none))))
                            ($prior $prior))))
                      ($known-weight $known-weight)))))
            (case (collapse (once (sk-mix $weight $yes $no))) (
               ((cons $mixed $_others) $mixed)
               (() (sk-target-value $given $target)))))))))

;; Admit one version per row, reading learned estimates without the consumer's
;; own samples. Missing excluded branches retain an incumbent and request paid
;; rebuilding; they never silently fall back to self-support.
(: sk-admit-step
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion) SkeletonVersion
       (List SkeletonVersion)))
(= (sk-admit-step $hash $key $filter $exclude $kept (sk-version $seq $rhash $view))
   (let $left-view
         (case $key (
         ((sk-fold $args)
            (if (sk-instance-fold? $args)
               (case (sk-left-out $hash $exclude) (
                  (() sk-none)
                  ($left
                     (let ($kb $_pattern $_extractor $_init $_function $_finish $_mode) $args
                        (sk-instance-view $hash (the ScalarFoldSpec $args)
                           (ledger-instance-read-excluding $hash (sk-instance-tally $hash $key $kb) $left))))))
               (sk-rate-without $hash $args $exclude)))
         ((sk-prior $rate-args) (if (sk-leaves-out? $hash $key $exclude) (sk-prior-view (sk-premise-reader sk-premise-step) $hash $rate-args $exclude) sk-none))
         ((sk-evidence $evidence-args) (if (== $exclude ()) sk-none (sk-evidence-view (sk-value-reader sk-value) $hash $evidence-args $exclude)))
         ($_statement
            (if (sk-rule-truth-key? $key)
               (case (collapse (once (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $left-seq))
                        (if (=alpha $stored $key) (sk-row $ident $concl $premises $left-seq) (empty))))) (
                  ((cons (sk-row $row-ident $row-concl $row-premises $row-seq) $_rest)
                     (if (sk-row-leaves-out-step $exclude false $row-premises)
                        (sk-row-view () $exclude $hash $key $rhash (sk-row $row-ident $row-concl $row-premises $row-seq))
                        sk-none))
                  (() sk-none)))
               sk-none))))
      (case (if (sk-admits? $filter $exclude $left-view) $left-view sk-none) (
      (sk-none
         (if (sk-admits? $filter $exclude $view) (cons (sk-version $seq $rhash $view) $kept)
            (let $rebuilt
               (if (sk-excludes? $exclude (sk-view-deps-step 0 $view))
                  (sk-rebuild-view (not (== (search-id-value sk_branch_at) 0)) $hash $key $rhash $exclude)
                  sk-none)
               (case (if (sk-admits? $filter $exclude $rebuilt) $rebuilt
                        (fold-semidet (sk-admit-older $filter $exclude) sk-none (sk-older-views $hash $key $rhash))) (
                  (sk-none $kept)
                  ($admitted (cons (sk-version $seq $rhash $admitted) $kept)))))))
      ($left-out (cons (sk-version $seq $rhash $left-out) $kept))))))

;; Cache branches with their actual exclusion cuts: E1 serves E2 only when its
;; dependencies miss E2 and its cuts are contained in E2. Keep eight contexts per
;; row; ordinary reads request unpaid work rather than building it here.
(: sk-rebuild-view (-[semidet]-> Bool Number SkeletonKey Number (List Number) SkeletonValue))
(= (sk-rebuild-view $build $hash $key $rhash $exclude)
   (if (sk-excludes? $exclude (deps-key $hash)) sk-none
      (let $slot (index-hash ($hash $rhash))
         (case (sk-branch-values $slot $key $rhash $exclude true) (
            ((cons $cached $_rest) (let $_hit (query_metric_increment branch-cache-hits) $cached))
            (()
               (let $_miss (query_metric_increment branch-cache-misses)
               (case (collapse (once (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
                        (if (=alpha $stored $key) (sk-row $ident $concl $premises $seq) (empty))))) (
                  (() (if $build sk-none (chainer-first-or sk-none (sk-branch-values $slot $key $rhash $exclude false))))
                  ((cons (sk-row (sk-ident $rule $keys $result) $concl $premises $seq) $_rows)
                     (let* (($inputs (alpha_unique_keys (fold-semidet sk-direct-key-step () $premises)))
                            ($mandatory (deps-join (map-flat deps-key (map-semidet index-hash $inputs)))))
                        (if (sk-excludes? $exclude $mandatory)
                           (if $build sk-none (chainer-first-or sk-none (sk-branch-values $slot $key $rhash $exclude false)))
                           (if (if $build (sk-take! sk_eval_budget (case $key (((sk-key $type $_kbctx) (term-cost $type)) ($_fold 1)))) false)
                              (let* (($_counted (query_metric_increment row-computes))
                                     ($_build (query_metric_increment branch-builds))
                                     ($incumbent (sk-branch-values $slot $key $rhash $exclude false))
                                     ($_refresh
                                        (if (query_metrics_enabled)
                                           (if (space-row-present? &ctx_sk_branch_dirty ($slot))
                                              (query_metric_increment branch-cache-refreshes) 0) 0))
                                     ($unpaid (search-id-value sk_branch_unpaid))
                                     (($parent $frame) (execution-open-frame! $exclude))
                                     ($view (sk-row-view () $exclude $hash $key $rhash
                                        (sk-row (sk-ident $rule $keys $result) $concl $premises $seq)))
                                     ($cuts (execution-close-frame! $parent $frame $exclude))
                                     ($_parent (sk-note-cuts! $cuts)))
                                 (if (== $unpaid (search-id-value sk_branch_unpaid))
                                    (sk-cache-branch! $slot $hash $key $rhash $inputs $cuts true $view)
                                    (let $_unfinished (next-search-id sk_branch_unpaid)
                                       (if (== $view sk-none) (chainer-first-or sk-none $incumbent)
                                          (if (sk-same-view? $view (chainer-first-or sk-none $incumbent))
                                             (chainer-first-or $view $incumbent)
                                             (sk-cache-branch! $slot $hash $key $rhash $inputs $exclude false $view))))))
                              (let* (($incumbents (sk-branch-values $slot $key $rhash $exclude false))
                                     ($_unpaid
                                        (if $build
                                           (let $_counted (query_metric_increment rows-unpaid) (next-search-id sk_branch_unpaid))
                                           (sk-request-branch! $slot $hash $key $rhash $exclude)))
                                     ($_reader (sk-hold-branch-reader! $slot $key $rhash $exclude)))
                                 (chainer-first-or sk-none $incumbents)))))))))))))))

(: sk-rate-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-rate-take! $hash $args)
   (sk-take-rate (sk-value-reader sk-value) $hash $args))

(: sk-fold-views (-[semidet]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-fold-views $hash $key)
   (case $key (
      ((sk-fold $args) (sk-keep-view $hash $key (sk-fold-view (sk-value-reader sk-value) $hash (the ScalarFoldSpec $args))))
      ((sk-group $group-args)
         (sk-keep-view $hash $key (sk-group-view (sk-value-reader sk-value) $hash $key (the GroupedFoldSpec $group-args))))
      ((sk-prior $rate-args) (sk-keep-view $hash $key (sk-prior-view (sk-premise-reader sk-premise-step) $hash $rate-args ())))
      ((sk-evidence $evidence-args) (sk-keep-view $hash $key (sk-evidence-view (sk-value-reader sk-value) $hash $evidence-args ())))
      ((sk-key $_type $_kbctx) ()))))

;; The versions a consumer takes: per row, the latest one it admits.
(: sk-admitted-versions (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion)))
(= (sk-admitted-versions $hash $key $filter $exclude)
   (let* (($stored (sk-latest-versions $hash $key))
          ($versions (case $key (
             ((sk-key $_type $_kbctx) $stored)
             ($_fold (case $stored (
                ((cons (sk-version $_seq $_rhash $view) $_rest) $stored)
                (() (sk-fold-views $hash $key)))))))))
      (fold-semidet sk-cons-step () (fold-semidet (sk-admit-step $hash $key $filter $exclude) () $versions))))

;; A compound the event graph models has one value, its posterior, whoever
;; reads it outside a condition: a stored report on it is a likelihood on its
;; parts, and its parts' joint is the graph's.
(: sk-report-posterior (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet EventNetworkRead))
(= (sk-report-posterior $given $key $filter $exclude $ev)
   (case (data $given $key) (
      ((() (sk-key $type $_kbctx))
         (if (compound-source? $type) (event-network-read $key $filter $exclude $ev) no-event-model))
      ($_other no-event-model))))

;; A compound's posterior (sk-report-posterior), or leaves first, then one
;; version per row in the order the rows were found; a certain stored fact
;; stands alone (sk-certain-or). Views read under given statements leave out
;; the leaves that depend on them. Views that overlap condition the key on
;; what they share.
(: sk-merge-key
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonGiven) (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $exclude $given $views)
   (case (sk-report-posterior $given $key $filter $exclude (ev-set 0)) (
      ((event-posterior $posterior) $posterior)
      (no-event-model
         (let* (($outside (hash-union $exclude (hash-set (sk-given-hashes $given))))
                ($leaves (sk-leaf-views $hash $key $filter $outside))
                ($sources (sk-judgment-values $key
                   (map-flat (sk-read-value $filter) (append-flat $leaves $views))))
                ($own (sk-own-values (sk-complete-values (sk-certain-or $leaves $sources))))
                ;; The standing views come out of the step reversed; the split restores their order.
                (($messages $updates $standing)
                   (fold-semidet sk-node-split-step (data () () ()) (fold-semidet (sk-standing-step $own) () $own)))
                ($unifiers (sk-unifier-hashes $hash $key))
                ($ignore (hash-union $unifiers $outside))
                (($values $siblings $references) (sk-reference-values (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) (sk-row-reader sk-row-view) $ignore (the (List SkeletonValue) $standing))))
            (sk-node-apply (sk-value-reader sk-value) $key $outside (the (List SkeletonValue) $messages) (the (List SkeletonValue) $updates) (let $state (fold-semidet (sk-pair-merge-step (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) true $ignore) (sk-merging sk-none () 0) (sk-report-values (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $values))
               (case $state (
                  ((sk-merging $merged () $deps)
                     (let $_settled
                        (if (if (== $outside ()) (== $filter sk-any-filter) false)
                           (if (sk-root-claim? $given $hash $key) (sk-clear-root-cap! $hash $key) ()) ())
                        (if (if (== $deps 0) (if $siblings false true) false) $merged
                           (sk-key-fallback (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $ignore $references $values))))
                  ((sk-merging $_provisional $keys $deps)
                     (let* (($merged (sk-key-fallback (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $ignore $references $values))
                            ($near (sk-shared-statements $ignore (deps-near-shared (map-semidet (sk-view-deps-step 0) $values))))
                            ($cut (if (sk-root-claim? $given $hash $key) $keys
                               (fold-semidet (sk-near-key-step $near) () $keys))))
                        (if (== $cut ()) $merged
                           (sk-conditioned $given (sk-key-target $hash $key $filter $exclude) $hash -1
                              (hash-union $exclude $unifiers) $cut (+ 1 (deps-size $deps)) $merged $merged)))))))))))))

(: sk-summary-version
   (-[semidet]-> (List SkeletonGiven) Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion) SkeletonVersion (List SkeletonVersion)))
(= (sk-summary-version $given $hash $key $filter $exclude $kept (sk-version $seq $rhash $_latest))
   (case (collapse (once (match &sk_row ($hash $stored $rhash $row)
            (if (=alpha $stored $key)
               (let* (($copy (copy_term $row))
                      ((sk-row (sk-ident $rule $_keys $_key) ($_type $_scope $proof $_tv) $premises $_seq) $copy)
                      ($cuts (hash-union $exclude (sk-row-exclusions $hash $key $proof)))
                      ($candidate (if (if (rule-live? $rule) (context-rule-visible? $rule) false)
                         (sk-row-result $copy (sk-row-state $given $cuts $hash sk-reference-read $copy)) sk-none)))
                  (if (sk-admits? $filter $exclude $candidate)
                     (case $candidate (
                        ((sk-val ($_ct $_cs $_cp (STV $s $c)) $_ce $_cd)
                           (if (if (> $c 0) (if (<= $s 0) true (>= $s 1)) false)
                              (if (fold-semidet sk-zero-likelihood-step false $premises)
                                 (sk-version $seq $rhash $candidate) (empty)) (empty)))
                        ($_other (empty)))) (empty)))
               (empty))))) (((cons $reference $_rest) (cons $reference $kept)) (() $kept))))

(: sk-cached-summary-version
   (-[semidet]-> (List SkeletonGiven) Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion) SkeletonVersion (List SkeletonVersion)))
(= (sk-cached-summary-version $given $hash $key $filter $exclude $kept (sk-version $seq $rhash $latest))
   (if (sk-row-has-bayes? $hash $key $rhash)
      (if (if (sk-excludes? $exclude (sk-view-deps-step 0 $latest))
              (let* (($slot (index-hash ($hash $rhash)))
                     ($branches (append-flat (sk-branch-values $slot $key $rhash $exclude true)
                                             (sk-branch-values $slot $key $rhash $exclude false))))
                 (== (collapse (let $branch (superpose $branches)
                    (if (sk-admits? $filter $exclude $branch)
                       (if (sk-given-meets? $given $branch) (empty) $branch) (empty)))) ())) false)
         (case (collapse (once (match &ctx_sk_summary_reference
                  ($hash $memo-key $rhash $memo-pins $memo-cuts $memo-filter $memo-value)
                  (if (=alpha $memo-key $key)
                     (if (=alpha $memo-pins $given)
                        (if (== $memo-cuts $exclude) (if (=alpha $memo-filter $filter) $memo-value (empty)) (empty))
                        (empty)) (empty))))) (
            ((cons $hit $_memo-tail)
               (if (== $hit sk-none) $kept (cons (sk-version $seq $rhash $hit) $kept)))
            (()
               (let* (($references (fold-semidet (sk-summary-version $given $hash $key $filter $exclude) ()
                                    (cons (sk-version $seq $rhash $latest) ())))
                      ($value (chainer-first-or sk-none (map-semidet sk-version-view $references)))
                      ($_memo (sk-cache-summary-reference! $hash $key $rhash $given $exclude $filter $value)))
                  (append-flat $references $kept)))))
         $kept)
      $kept))

(: sk-calibrated-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue SkeletonValue))
(= (sk-calibrated-value $given $key $filter $exclude $value)
   (case $value (
      ((sk-val ($_type $_ctx $_proof (STV $_s $_c)) $_ev $_deps)
         (if (== $exclude ()) $value
            (let* (($hash (index-hash $key))
                   ($unaffected (chainer-first-or false
                      (collapse (once (match &ctx_sk_merged ($hash $stored $deps $_merged $_root)
                         (if (=alpha $stored $key)
                            (if (sk-excludes? $exclude $deps) (empty) true) (empty))))))))
               (if $unaffected $value
                  (let* (($versions (sk-latest-versions $hash $key))
                         ($references (fold-semidet (sk-cached-summary-version $given $hash $key $filter $exclude) () $versions))
                         ($reference (chainer-first-or sk-none (map-semidet sk-version-view $references))))
                     (sk-unsettled-value $hash $value $reference))))))
      ($_other $value))))

;; The merged value of a key on behalf of a consumer. A proof or truth-value
;; pattern takes the whole merged value when it admits it, and otherwise the
;; merge of the views it admits. A consumer that leaves one of its own samples
;; out of an instance fold reads the views it admits, never the cached value.
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-value $key $filter $exclude)
   (let $selected (case $filter (
           ((sk-filter $proof $tv)
              (if (head-is? $proof derived-implication) true
                 (if (head-is? $tv STV)
                    (case $key (((sk-key $type $_scope) (implication-type? $type)) ($_other false))) false)))
           ($_any false)))
      (if $selected
         (let $hash (index-hash $key) (sk-merge-key $hash $key $filter $exclude () (map-flat sk-version-view (sk-admitted-versions $hash $key $filter $exclude))))
         (let* (($hash (index-hash $key))
                ($merged
                   (if (sk-leaves-out? $hash $key $exclude)
                      (sk-merge-key $hash $key sk-any-filter $exclude () (map-flat sk-version-view (sk-admitted-versions $hash $key sk-any-filter $exclude)))
                      (case (sk-open-value $hash $key sk-any-filter) (
                         ((sk-merged $_hash $_key $deps $value)
                            (if (sk-excludes? $exclude $deps)
                               (sk-merge-key $hash $key sk-any-filter $exclude () (map-flat sk-version-view (sk-admitted-versions $hash $key sk-any-filter $exclude)))
                               $value)))))))
            (if (sk-open-filter? $filter) $merged
               (if (sk-admits? $filter () $merged) $merged
                  (sk-merge-key $hash $key $filter $exclude () (map-flat sk-version-view (sk-admitted-versions $hash $key $filter $exclude)))))))))

;; Condition the latest view before testing its dependencies against the
;; reader's exclusions: a pin may cut an excluded ancestor. Selecting an older
;; MAIN view first can hide the very dependency the pin must replace. Without
;; such a dependency, ordinary historical-version admission still applies.
(: sk-given-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey SkeletonVersion SkeletonValue))
(= (sk-given-view $given $exclude $hash $key (sk-version $_seq $rhash $view))
   (if (sk-excludes? $exclude (deps-key $hash)) sk-none
   (if (sk-given-meets? $given $view)
      (case (collapse (once (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
               (if (=alpha $stored $key) (sk-row $ident $concl $premises $seq) (empty))))) (
         ((cons $row $_rest)
            (let $again (sk-row-view $given $exclude $hash $key $rhash $row)
               (if (sk-excludes? $exclude (sk-view-deps-step 0 $again)) sk-none $again)))
         (() $view)))
      (case (sk-admit-step $hash $key sk-any-filter $exclude () (sk-version $_seq $rhash $view)) (
         (() sk-none)
         ((cons (sk-version $seq $row $admitted) $_rest)
            (if (sk-given-meets? $given $admitted)
               (sk-given-view $given $exclude $hash $key (sk-version $seq $row $admitted)) $admitted)))))))

;; Paid branches merge under their pins before MAIN admission; historical MAIN
;; views may omit a dependency that the pin must replace. Row hash -2 prevents
;; re-entry when a compound gains a value only under the condition. Original
;; reader and rebuild exclusions still apply (test_history_closed_replay).
(: sk-pinned-value (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-pinned-value $given $key $filter $exclude)
   (let* (($branch (case $key (
                     ((sk-key $_type $_ctx)
                        (if (>= (search-id-value sk_claim_state) 0) (> (fold-flat sk-given-depth-step 0 $given) 0) false))
                     ($_fold false))))
          ($value (if $branch (sk-given-merge $given $key $filter $exclude) (sk-value $key $filter $exclude))))
      (if (if $branch false (sk-given-meets? $given $value)) (sk-given-merge $given $key $filter $exclude)
         (if (if (== $value sk-none) (not (== $given ())) false)
            (case $key (
               ((sk-key $type $kbctx)
                  (let $hash (index-hash $key)
                     (if (if (not (head-is-member? $type (And Or Implication))) true
                            (if (space-row-present? &ctx_sk_conditioning ($hash -2)) true
                               (if (sk-excludes? $exclude (deps-key $hash)) true (sk-branch-excludes? (deps-key $hash))))) sk-none
                        (let* (($_entered (context-add! &sk_conditioning ($hash -2)))
                               ($views
                                  (fold-semidet (sk-given-row-step $given $exclude $hash $key) ()
                                     (collapse (match &sk_row ($hash $stored $rhash $row) (if (=alpha $stored $key) ($rhash $row) (empty))))))
                               ($_left (context-remove! &sk_conditioning ($hash -2))))
                           (if (== $views ()) sk-none (sk-merge-key $hash $key $filter $exclude $given $views))))))
               ($_fold sk-none)))
            $value))))

(: sk-row-view-step
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey (List SkeletonValue) (Number SkeletonRow)
       (List SkeletonValue)))
(= (sk-row-view-step $given $exclude $hash $key $kept ($rhash $row))
   (case (sk-row-view $given $exclude $hash $key $rhash $row) (
      (sk-none $kept)
      ($view (cons $view $kept)))))

(: sk-given-row-step
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey (List SkeletonValue) (Number SkeletonRow)
       (List SkeletonValue)))
(= (sk-given-row-step $given $exclude $hash $key $views ($rhash (sk-row $ident $concl $premises $seq)))
   (if (fold-semidet (sk-reads-given-step (sk-given-hashes $given)) false $premises)
      (sk-row-view-step $given $exclude $hash $key $views ($rhash (sk-row $ident $concl $premises $seq)))
      $views))

;; Its views evaluated again under the condition, and the node rows reading a
;; given statement that have no view: a compound's message holds given the
;; compound although MAIN only predicts it, and fails there. Row hash -2
;; prevents re-entry through those rows, as in sk-pinned-value.
(: sk-given-merge (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-given-merge $given $key $filter $exclude)
   (let* (($hash (index-hash $key))
          ($views (map-semidet (sk-given-view $given $exclude $hash $key)
             (sk-admitted-versions $hash $key $filter (sk-admission-exclusions $given $exclude)))))
      (sk-merge-key $hash $key $filter $exclude $given
         (if (space-row-present? &ctx_sk_conditioning ($hash -2)) $views
            (let* (($_entered (context-add! &sk_conditioning ($hash -2)))
                   ($all (fold-semidet (sk-given-row-step $given $exclude $hash $key) $views
                      (collapse (match &sk_row ($hash $stored $rhash $row)
                         (if (=alpha $stored $key)
                            (if (== (sk-latest-view $hash $key $rhash) sk-none)
                               (let (sk-row $_ident ($_type $_kbctx $proof $_tv) $_premises $_seq) $row
                                  (if (sk-node-row? $proof) ($rhash $row) (empty)))
                               (empty))
                            (empty))))))
                   ($_left (context-remove! &sk_conditioning ($hash -2))))
               $all)))))

;; A compound's posterior, or the leaves and views whose evidence lies outside `$ev`.
(: sk-compatible-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet Bool SkeletonValue))
(= (sk-compatible-value $given $key $filter $exclude $ev $views)
   (case (sk-report-posterior $given $key $filter $exclude $ev) (
      ((event-posterior $posterior) $posterior)
      (no-event-model
         (let* (($hash (index-hash $key))
                ($outside (hash-union $exclude (hash-set (sk-given-hashes $given))))
                ($leaves (sk-leaf-views $hash $key $filter $outside))
                ($ignore (hash-union (sk-unifier-hashes $hash $key) $outside))
                ;; The compatible views come out of the step reversed; the split restores their order.
                (($messages $updates $compatible)
                   (fold-semidet sk-node-split-step (data () () ())
                      (fold-semidet (sk-compatible-step $ev) ()
                      (sk-own-values
                         (sk-judgment-values $key
                            (map-flat (sk-read-value $filter)
                               (if $views
                                  (append-flat $leaves
                                     (map-semidet (sk-given-view $given $exclude $hash $key)
                                        (sk-admitted-versions $hash $key $filter (sk-admission-exclusions $given $exclude))))
                                  $leaves)))))))
                (($selected $siblings $references)
                   (sk-reference-values (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) (sk-row-reader sk-row-view) $ignore (sk-certain-or $leaves (the (List SkeletonValue) $compatible)))))
            (let $value (if $siblings (sk-key-fallback (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $ignore $references $selected)
                           (fold-semidet (sk-merge-step (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) true $ignore) sk-none (sk-report-values (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $selected)))
               (sk-calibrated-value $given $key $filter $outside (sk-node-apply (sk-value-reader sk-value) $key $outside (the (List SkeletonValue) $messages) (the (List SkeletonValue) $updates) $value))))))))

;; Reconstruct one proof per existing row only for an unanswered public root
;; after paid evaluation. Never expand or condition history here.
;; Exact cuts are part of the query-local memo; no MAIN value crosses worlds.
(: sk-representative-row
   (-[semidet]-> (List SkeletonGiven) Number SkeletonKey Number (List Number) SkeletonRow SkeletonValue))
(= (sk-representative-row $givens $hash $key $rhash $exclusions $row)
   (let* (($given (sort-atom (alpha_unique_keys $givens)))
          ($exclude (sort-atom (alpha_unique_keys $exclusions))))
   (let (sk-row (sk-ident $rule $_row-keys $_row-key) $_concl $_row-premises $_row-seq) $row
      (if (if (rule-live? $rule) (context-rule-visible? $rule) false)
         (case (collapse (once (match &ctx_sk_representative ($hash $stored $rhash $given $exclude $cached)
                  (if (=alpha $stored $key) $cached (empty))))) (
            ((cons $cached $_rest) $cached)
            (()
               (if (sk-take! sk_representative_budget 1)
                  (let* (($_entered (sk-update-representative! $hash $key $rhash $given $exclude sk-representative-enter))
                         ($_counted (query_metric_increment representative-reads))
                         ($copy (copy_term $row))
                         ((sk-row (sk-ident $owner $_keys $_key) ($_type $_scope $proof $_tv) $_premises $_seq) $copy)
                         ($cuts (hash-union $exclude (sk-row-exclusions $hash $key $proof)))
                         ($state (sk-row-state $given $cuts $hash sk-representative-read $copy))
                         ($read (case $state (
                            ((sk-entangled $_shared $_base $independent) $independent)
                            ($_other $state))))
                         ($value (sk-reference-view $owner (sk-row-result $copy $read)))
                         ($_memo (sk-update-representative! $hash $key $rhash $given $exclude (sk-representative-result $value))))
                     $value)
            sk-none))))
         sk-none))))

(: sk-representative-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet SkeletonValue))
(= (sk-representative-value $given $key $filter $exclude $ev)
   (let* (($hash (index-hash $key))
          ($pins (sk-given-hashes $given))
          ($outside (collapse (let $cut (superpose $exclude)
             (if (stored-list-member? $cut $pins) (empty) $cut))))
          ($leaf-views (sk-leaf-views $hash $key $filter $exclude))
          ($leaves (collapse (let $leaf (superpose $leaf-views)
             (case $leaf (
                ((sk-val ($_lt $_ls $leaf-proof $_ltv) $_le $_ld)
                   (if (sk-given-meets? $given $leaf) (empty)
                      (if (proof-representative? $leaf-proof) $leaf (empty))))
                ($_none (empty)))))))
          ($stored-views (collapse (match &ctx_sk_latest ($hash $stored-key (sk-version $_seq $rhash $latest))
             (if (=alpha $stored-key $key)
                (let* (($versions (append-flat (sk-older-views $hash $key $rhash) (cons $latest ())))
                       ($pure (collapse (let $view (superpose $versions)
                          (case $view (
                             ((sk-val ($_t $_scope $proof $_tv) $_ev $_deps)
                                (if (sk-live-view? $view)
                                   (if (sk-given-meets? $given $view) (empty)
                                      (if (proof-representative? $proof) $view (empty))) (empty)))
                             ($_none (empty)))))))
                       ($compatible (fold-semidet sk-cons-step ()
                          (fold-semidet (sk-compatible-step $ev) () $pure))))
                   (fold-semidet (sk-admit-older $filter $exclude) sk-none $compatible)) (empty)))))
          ($compatible-stored (fold-semidet sk-cons-step ()
             (fold-semidet (sk-compatible-step $ev) () (append-flat $leaves $stored-views))))
          ($best (fold-semidet sk-representative-best sk-none $compatible-stored)))
      (if (== $best sk-none)
         (let* (($views (collapse (match &sk_row ($hash $stored $rhash $row)
                   (if (=alpha $stored $key)
                      (if (sk-excludes? $exclude (deps-key $hash)) (empty)
                         (let $view (sk-representative-row $given $hash $key $rhash $exclude $row)
                            (if (sk-admits? $filter $outside $view) $view (empty))))
                      (empty)))))
                ($compatible (fold-semidet sk-cons-step ()
                   (fold-semidet (sk-compatible-step $ev) () $views))))
            (fold-semidet sk-representative-best $best $compatible))
         $best)))

;; A complete statement with no value the reader may read, once its search is
;; settled: unfounded when no rule application derives it, whoever reads it;
;; otherwise, for a reader with a pin, its rows evaluated again in creation
;; order with the pin joining the given list, merged with the leaves the
;; reader may read.
;; An excluded key cannot become admissible by closing it. Pins already in
;; the given list are read by sk-premise-step before reaching this operation.
(: sk-closed-read
   (-[semidet]-> SkeletonReadPolicy (List SkeletonGiven) (List SkeletonGiven) (List Number) SkeletonKey SkeletonFilter SkeletonValue))
(= (sk-closed-read $policy $pin $given $exclude $key $filter)
   (case $key (
      ((sk-key $type $kbctx)
         (if (if (complete-statement? $type $kbctx)
                 (if (== $policy sk-representative-read)
                    (== (sk-key-leaves $key $filter) ())
                    (== (sk-pinned-value $given $key $filter $exclude) sk-none)) false)
            (let $hash (index-hash $key)
               (if (if (if (== $policy sk-representative-read)
                           (deps-meet? $exclude (deps-key $hash))
                           (sk-branch-excludes? (deps-key $hash))) false (sk-settled? $key))
                  (if (sk-founded? $hash $key)
                     (if (if (== $policy sk-representative-read) true (== $pin ())) sk-none
                        (sk-merge-key $hash $key $filter $exclude $given
                           (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-row-view-step (append-flat $pin $given) $exclude $hash $key) ()
                                 (collapse (match &sk_row ($hash $stored $rhash $row)
                                    (if (=alpha $stored $key) ($rhash $row) (empty))))))))
                     (sk-unfounded-value $hash $key))
                  sk-none))
            sk-none))
      ($_fold sk-none))))

;; Read each premise without the consumer's key, respecting pins and evidence
;; already used. Complete predicates may close only after search settles.
;; Only antecedent completions read an unobserved instance's population prior;
;; other rows cannot treat a population estimate as an observation.
(: sk-premise-step
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonReadPolicy SkeletonRowState SkPattern
       SkeletonRowState))
(= (sk-premise-step $pin $given $exclude $shared $priors $policy $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-clash $clash-keys $clash-base) (sk-clash $clash-keys $clash-base))
      ((sk-acc $fold-proofs $ev $deps)
         (case $premise (
            ;; This context primitive binds the row's cuts before a likelihood
            ;; is resolved; expected-TV scoring leaves the open read optimistic.
            ((CPU ReadLikelihoodContext $_recipe $res)
               (if (= $res (likelihood-context $exclude $ev)) $state sk-fail))
            ;; An assumed rule applies only in its context. Like a stored rule, it
            ;; is no premise of its applications: two of them share no input.
            ((CPU ContextRule ($_assumption $ctx) $_res)
               (if (context-rule-enabled? $ctx) $state sk-fail))
            ;; Only a diagnostic uses a neutral prior: a certified endpoint
            ;; is invariant to it and no diagnostic value becomes evidence.
            ;; Every actual read, including representatives, uses leave-one-out.
            ((CPU ReadRate ($kb $pattern $raw (rate-plan $goals $rate) $prior) $result)
               (let $observations (hash-set (observation-keys (observation-sources $ev)))
                  (case (collapse (once (if (== $policy sk-reference-read) (STV 0.5 0.0)
                           (sk-rate-read (sk-premise-reader sk-premise-step) (brand KB $kb) (brand Statement $pattern) (the TV $raw)
                              (rate-plan (the (List Goal) $goals) $rate) $exclude $observations)))) (
                     ((cons $admissible ())
                        (let $read (if (the Bool $prior) (population-prior-tv (the TV $admissible)) (the TV $admissible))
                           (if (= $result (rate-read (the TV $admissible) (the TV $read))) $state sk-fail)))
                     (() sk-fail)))))
            ((CPU FoldAllCompiled $fold-args $fold-res)
               (if (== $policy sk-reference-read)
                  (sk-consume-fold $state $fold-res (sk-goal-val (CPU FoldAllCompiled $fold-args (STV 0.5 0.0)) (brand Proof cpu) (ev-set 0) 0))
                  (sk-consume-fold $state $fold-res (sk-value (sk-fold $fold-args) sk-any-filter $exclude))))
            ((CPU CompoundRate $rate-args $rate-res)
               (if (== $policy sk-reference-read)
                  (sk-consume-fold $state $rate-res (sk-goal-val (CPU CompoundRate $rate-args (STV 0.5 0.0)) (brand Proof cpu) (ev-set 0) 0))
                  (sk-consume-fold $state $rate-res (sk-value (sk-prior $rate-args) sk-any-filter $exclude))))
            ;; No evidence of its own is no factor (CompletionEvidenceFormula).
            ((CPU CompoundEvidence $evidence-args $evidence)
               (case (sk-pinned-evidence $given $evidence-args) (
                  (sk-none
                     (case (if (== $policy sk-reference-read) sk-none
                              (sk-value (sk-evidence $evidence-args) sk-any-filter $exclude)) (
                        (sk-none (if (= $evidence (key-evidence no-evidence no-evidence no-evidence)) $state sk-fail))
                        ($value (sk-consume-fold $state $evidence $value)))))
                  ($pinned (sk-consume-fold $state $evidence $pinned)))))
            ((CPU GroupedFoldAllCompiled $group-args $group-res)
               (if (== $policy sk-reference-read) sk-fail
                  (sk-consume-fold $state $group-res (sk-value (sk-group $group-args) sk-any-filter $exclude))))
            ((CPU $fun $args $res)
               (case (collapse (once (cpu-call 0 $fun $args))) (
                  ((cons $result $_rest) (if (= $res $result) $state sk-fail))
                  (() sk-fail))))
            (($type $kbctx $proof $tv)
               (let $key (sk-key $type $kbctx)
                  (case (fold-semidet (sk-pinned-step $key) () $given) (
                     ((cons $pinned $_more) (sk-use-premise $shared $state $premise $pinned))
                     (()
                        (let* (($filter (sk-filter $proof $tv))
                               ($closed (if (== $policy sk-reference-read) sk-none
                                  (sk-closed-read $policy $pin $given $exclude $key $filter))))
                           (if (== $closed sk-none)
                              (let $value
                                 (sk-premise-value $priors
                                    (case $policy (
                                       (sk-facts-read (sk-compatible-value $given $key $filter $exclude $ev false))
                                       (sk-representative-read (sk-representative-value (append-flat $pin $given) $key $filter $exclude $ev))
                                       (sk-reference-read
                                          (if (deps-meet? $exclude (deps-key (index-hash $key))) sk-none
                                             (let* (($facts (sk-key-leaves $key $filter))
                                                    ($local (collapse (let $fact (superpose $facts)
                                                       (let $view (sk-leaf-view (index-hash $key) $fact)
                                                          (if (deps-meet? $exclude (sk-view-deps-step 0 $view)) (empty) $view))))))
                                                (chainer-first-or
                                                   (sk-val (assemble-runtime-fact $type $kbctx (brand Proof summary-unknown) (STV 0.5 0.0))
                                                      (ev-set 0) (deps-key (index-hash $key)))
                                                   $local))))
                                       ($_ordinary (sk-calibrated-value $given $key $filter $exclude (sk-pinned-value $given $key $filter $exclude))))))
                                 (case (sk-use-premise (if (== $policy sk-independent-read) true $shared) $state $premise $value) (
                                    (sk-fail
                                       (if (if $shared true (if (== $policy sk-representative-read) true (== $policy sk-reference-read))) sk-fail
                                          (case (sk-use-premise $shared $state $premise
                                                   (sk-premise-value $priors (sk-compatible-value $given $key $filter $exclude $ev true))) (
                                             (sk-fail
                                                (sk-clash-on $given $state
                                                   (if (== $policy sk-facts-read) (sk-premise-value $priors (sk-calibrated-value $given $key $filter $exclude (sk-pinned-value $given $key $filter $exclude))) $value)))
                                             ($compatible $compatible)))))
                                    ($taken $taken))))
                              (case (sk-use-premise (if (== $policy sk-independent-read) true $shared) $state $premise $closed) (
                                 (sk-fail (if $shared sk-fail (sk-clash-on $given $state $closed)))
                                 ($taken $taken))))))))))))))))

;; Read premises greedily, retrying a clash on a fresh row with compatible facts
;; first. Remaining clashes or shared uncertain statements require conditioning.
;; An entangled row may keep its independent approximation while unpaid; a clash
;; has no approximation. Conditioned reads charge the enclosing claim.
(: sk-row-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue))
(= (sk-row-view $given $exclude $khash $key $rhash $row)
   (if (let (sk-row (sk-ident $rule $_keys $_key) $_concl $_prems $_seq) $row
          (if (rule-live? $rule) (context-rule-visible? $rule) false))
      (if (sk-claim-charge! $given)
         (let* (((sk-row (sk-ident $owner $_owner-keys $_owner-key) ($_type $_kbctx $proof $_tv) $_premises $_seq) $row)
                ($readers (if (== $exclude ()) (sk-push-reader! ($khash $key $rhash)) ()))
                ($exclusions (hash-union (sk-row-exclusions $khash $key $proof) $exclude))
                ($target (sk-row-target $exclusions $khash $key $rhash $row))
                ($greedy (copy_term $row))
                ($state (sk-row-state $given $exclusions $khash sk-greedy-read $greedy))
                ($value
                   (if (case $state (((sk-clash $_k $_b) true) ((sk-entangled $_ek $_eb $_es) true) ($_read false)))
                      (let* (($retry (copy_term $row))
                             ($again (sk-row-state $given $exclusions $khash sk-facts-read $retry)))
                         (case $again (
                            ((sk-clash $keys $base) (sk-conditioned $given $target $khash $rhash $exclusions $keys $base sk-none sk-none))
                            ;; While its conditioning waits, a row keeps the views
                            ;; it had; one that has none takes its approximate value.
                            ((sk-entangled $keys $base $independent)
                               (let $approx (sk-unresolved (sk-row-result $retry $independent))
                                  (sk-conditioned $given $target $khash $rhash $exclusions $keys $base $approx
                                     (if (== (sk-latest-view $khash $key $rhash) sk-none) $approx sk-none))))
                            ($_other (sk-row-result $retry $again)))))
                      (sk-row-result $greedy $state)))
                ($_reader-left (if (== $exclude ()) (sk-restore-readers! $readers) true)))
            ;; Conditioned and closed reads consume this value without
            ;; publishing an ordinary view. Preserve the permanent owner now,
            ;; before a caller wraps it in a judgment, merge or fold.
            (sk-reference-view $owner $value))
         sk-none)
      sk-none))

;; What a target is under a condition.
(: sk-target-value (-[semidet]-> (List SkeletonGiven) SkeletonTarget SkeletonValue))
(= (sk-target-value $given (sk-row-target $exclusions $khash $key $rhash $row))
   (sk-row-view $given $exclusions $khash $key $rhash $row))
(= (sk-target-value $given (sk-key-target $hash $key $filter $exclude)) (sk-given-merge $given $key $filter $exclude))

;; Budgeted cutset conditioning (docs/metta/overlap_conditioning.md).
;; Ordinary reads queue the target for its granted turn. A claim spends the
;; remaining allowance, never the near-root reserve, and retains its deepest
;; completed pass. Nested depth cuts keep the approximation and mark the pass
;; unfinished; a clash has none. Incomplete branches cannot contribute.
(: sk-conditioned
   (-[semidet]-> (List SkeletonGiven) SkeletonTarget Number Number (List Number) (List SkeletonKey) Number
       SkeletonValue SkeletonValue SkeletonValue))
(= (sk-conditioned $given $target $khash $rhash $wexclude $keys $base $approx $waiting)
   (case $keys (
      (() $approx)
      ((cons $_first $_more)
         (if (== $given ())
            (let* (($cost (* 2 $base))
                   ($owner (case $target (
                      ((sk-key-target $_h $target-key $_f $_e) $target-key)
                      ((sk-row-target $_ex $_rh $row-key $_row-hash $_row) $row-key))))
                   ($root (if (== $rhash -1) (sk-root-claim? $given $khash $owner) false))
                   ($cap (search-id-value sk_root_claim_cap))
                   ($blocked (if $root
                      (not (== (collapse (once (match &ctx_sk_root_exhausted ($khash $stored (sk-root-limit $tried $epoch))
                         (if (=alpha $stored $owner)
                            (if (== $epoch (sk-input-epoch $owner)) (if (>= $tried $cap) true (empty)) (empty)) (empty))))) ())) false)))
               (if $blocked (progn (next-search-id sk_branch_unpaid) $waiting)
               ;; Deferred rebuilds may lie outside the ordinary need closure;
               ;; their conditioning uses the same bounded tier slice.
               (if (if (space-row-present? &ctx_sk_given_granted ($khash $rhash)) true
                      (if (== (search-id-value sk_branch_at) 0) false
                         (if (== (search-id-value sk_claim_state) -1)
                            (>= (search-id-value sk_eval_budget) 1) true)))
                  (if (space-row-present? &ctx_sk_conditioning ($khash $rhash)) $waiting
                     (if (== (search-id-value sk_claim_state) -1)
                        (let* (($_entered (context-add! &sk_conditioning ($khash $rhash)))
                               ;; Slice only an outer root-key claim. Nested row and
                               ;; weight work spends this same slice, never the reserve.
                               ($before (search-id-value sk_eval_budget))
                               ($room (if $root (min $before (search-id-value sk_root_claim_budget)) $before))
                               ($slice (execution-open-slice! $room))
                               ($_opened (sk-open-claim!))
                               ($deepest (sk-deepen $given $target $wexclude $keys (== $approx sk-none) (if (== $approx sk-none) 64 1) ()))
                               ($exhausted (sk-close-claim!))
                               ($spent (execution-close-slice! $slice (if $root root-slice ordinary-slice)))
                               ($key-spent (if $root
                                  (let* (($root-was (chainer-first-or 0
                                            (collapse (once (match &ctx_sk_root_spent ($khash $spent-owner $root-units)
                                               (if (=alpha $spent-owner $owner) $root-units (empty)))))))
                                         ($_spent-old (remove-variant-row! &sk_root_spent (quote ($khash $owner $root-was))))
                                         ($root-total (+ $root-was $spent))
                                         ($_spent-new (context-add! &sk_root_spent ($khash $owner $root-total))))
                                     $root-total) 0))
                               ($_left (context-remove! &sk_conditioning ($khash $rhash))))
                           (if $exhausted
                              (if (if $root (if (> $spent 0) (>= $key-spent $cap) false) false)
                                 (let* (($_unfinished (next-search-id sk_branch_unpaid))
                                        ($_old (sk-clear-root-cap! $khash $owner))
                                        ($_capped (context-add! &sk_root_exhausted ($khash $owner (sk-root-limit $cap (sk-input-epoch $owner)))))
                                        ($_pending (remove-data-rows! &sk_given_pending (quote ($khash $rhash $_cost)))))
                                    (chainer-first-or $waiting $deepest))
                                 (sk-wait! $khash $rhash $cost (chainer-first-or $waiting $deepest)))
                              (let $_settled (if $root (sk-clear-root-cap! $khash $owner) ())
                                 (chainer-first-or $waiting $deepest))))
                        (chainer-first-or $waiting (sk-mix-on $given $target $wexclude $keys))))
                  (sk-wait! $khash $rhash $cost $waiting))))
            (if (if (== $approx sk-none) false (>= (fold-flat sk-given-depth-step 0 $given) (search-id-value sk_claim_depth)))
               (progn (change-state! sk_claim_cut 1) $approx)
               (if (== (search-id-value sk_claim_state) -1)
                  (if (< (search-id-value sk_eval_budget) 1) $approx
                     (let* (($_opened (sk-open-claim!))
                            ($deepest (sk-deepen $given $target $wexclude $keys (== $approx sk-none) (if (== $approx sk-none) 64 1) ()))
                            ($_closed (if (sk-close-claim!) (next-search-id sk_branch_unpaid) 0)))
                        (chainer-first-or $approx $deepest)))
                  (case (sk-mix-on $given $target $wexclude $keys) (
                     (() (if (== $approx sk-none) sk-none (progn (change-state! sk_claim_cut 1) $approx)))
                     ((cons $value $_rest) $value))))))))))

;; Keep the deepest completed cutset pass, increasing depth while a pass was cut.
;; A target without an approximation accepts no truncated pass.
(: sk-deepen
   (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) Bool Number (List SkeletonValue)
       (List SkeletonValue)))
(= (sk-deepen $given $target $wexclude $keys $uncut $depth $deepest)
   (let* (($_depth (change-state! sk_claim_depth $depth))
          ($_uncut (change-state! sk_claim_cut 0))
          ($mixed (sk-mix-on $given $target $wexclude $keys)))
      (if (== (search-id-value sk_claim_state) -2) $deepest
         (let* (($cut (== (search-id-value sk_claim_cut) 1))
                ($found (if (== $mixed ()) $deepest (if (if $cut $uncut false) $deepest $mixed))))
            (if (if $cut (< $depth 64) false) (sk-deepen $given $target $wexclude $keys $uncut (+ $depth 1) $found) $found)))))

;; Try shared statements in order. Mix the target's true/false branches by a
;; compatible weight whose evidence lies outside them. Stored facts and compatible
;; views supply that weight; a certain stored fact stands alone.
(: sk-mix-on (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) (List SkeletonValue)))
(= (sk-mix-on $given $target $wexclude $keys)
   (case $keys (
      (() ())
      ((cons $pin $more)
         (let* (($phash (index-hash $pin))
                ($stored (not (== (sk-key-leaves $pin sk-any-filter) ())))
                ($before (search-id-value sk_claim_cut)))
            (case (collapse (once
                     (let* (($parts (sk-pin-parts $pin))
                            ($yes (sk-chain-value (cons (sk-given $phash $pin true) $given) $target $wexclude $parts))
                            ($no (sk-chain-value (cons (sk-given $phash $pin false) $given) $target $wexclude $parts)))
                        (sk-mix
                           (if $stored
                              (case $yes (
                                 ((sk-val $_yfact $yev $_ydeps)
                                    (case $no (
                                       ((sk-val $_nfact $nev $_ndeps)
                                          (let $branch-ev (evidence-union $yev $nev)
                                             (sk-compatible-value $given $pin sk-any-filter $wexclude
                                                (evidence-union $branch-ev (evidence-negated $branch-ev)) true)))
                                       ($_nother sk-none))))
                                 ($_yother sk-none)))
                              (sk-calibrated-value $given $pin sk-any-filter $wexclude (sk-pinned-value $given $pin sk-any-filter $wexclude)))
                           $yes $no)))) (
               (()
                  ;; A discarded candidate's truncated branches do not make a
                  ;; successful alternative incomplete. Preserve all failures
                  ;; only if no candidate mixes.
                  (let* (($failed-cut (search-id-value sk_claim_cut))
                         ($_restored (change-state! sk_claim_cut $before))
                         ($next (sk-mix-on $given $target $wexclude $more))
                         ($_cut (if (== $next ()) (change-state! sk_claim_cut (max $failed-cut (search-id-value sk_claim_cut))) ())))
                     $next))
               ($mixed $mixed))))))))

;; A node row of a compound, its first premise, reads the compound's parts
;; apart from the compound (event-moment-node.md): a part's view carrying the
;; compound's own message would count the compound twice. So the premises
;; after the compound exclude views depending on it.
(: sk-row-state (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonReadPolicy SkeletonRow SkeletonRowState))
(= (sk-row-state $given $exclusions $khash $policy (sk-row (sk-ident $rule $_keys $_key) ($type $kbctx $proof $_tv) $premises $_seq))
   (let* (((application-inputs $derived $shared $node $entangle $completion)
              (application-read-plan $rule (data $type $kbctx $proof $_tv) $premises))
          ($pin (sk-closed-pin $khash $type $kbctx (the Bool $derived)))
          ($start (sk-acc () (evidence-set (sk-sample-exclusions $type $kbctx)) (cons (deps-key $khash) ()))))
      (if (the Bool $node)
         (let* (((cons $premise $parts) $premises)
                (($node-type $node-kbctx $_proof $node-tv) $premise)
                ($compound (sk-key $node-type $node-kbctx)))
            (fold-semidet
               (sk-premise-step $pin $given (hash-union (sk-unifier-hashes (index-hash $compound) $compound) $exclusions)
                  (the Bool $shared) false $policy)
               (sk-premise-step $pin $given $exclusions (the Bool $shared) false $policy $start $premise)
               $parts))
         (case $completion (
            (no-completion-inputs
             (let $state (fold-semidet (sk-premise-step $pin $given $exclusions (the Bool $shared) false $policy) $start $premises)
               (if (if (== $policy sk-independent-read) false
                       (proof-input-entanglement? $entangle))
                  (sk-entangle (hash-union $exclusions (hash-set (sk-given-hashes $given))) $state)
                  $state)))
            ($completion (sk-read-completion $given $exclusions $khash (sk-key $type $kbctx) (the Bool $shared) $policy $start $completion)))))))

(: sk-read-completion
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Bool SkeletonReadPolicy SkeletonRowState CompletionInputs SkeletonRowState))
(= (sk-read-completion $given $exclusions $khash $key $shared $policy $start
      (completion-inputs $compound $before $observation $after $opening))
   (let* ((($ctype $ckbctx $_cproof $_ctv) $observation)
          ($consequence (sk-key $ctype $ckbctx))
          ($chash (index-hash $consequence))
          ($completed (cons (sk-given $khash $key $opening) ()))
          ($apart (hash-union (sk-unifier-hashes (index-hash $compound) $compound) $exclusions))
          ($compound-hash (index-hash $compound))
          ($inverted-inputs (collapse (match &sk_row ($compound-hash $stored $_irhash (sk-row $_iident ($_itype $_ikbctx $iproof $_itv) $ipremises $_iseq))
             (if (=alpha $stored $compound)
                (if (sk-inverted-proof? $iproof) (fold-semidet sk-direct-key-step () $ipremises) (empty)) (empty)))))
          ($observed (hash-set (fold-flat (sk-observed-exclusion-step $consequence) $exclusions (fold-flat append-flat () $inverted-inputs))))
          ($false (fold-semidet sk-known-false-step false (sk-key-leaves $consequence sk-any-filter)))
          ($siblings (if $false $apart (hash-union (sk-unifier-hashes $chash $consequence) $apart)))
          ($state (if $false
             (fold-semidet (sk-completion-sibling-step () $given $exclusions $observed $siblings $consequence $khash $completed $shared $policy) $start $before)
             (fold-semidet (sk-completion-sibling-step (sk-closed-pin $chash $ctype $ckbctx true) $given $exclusions $observed $siblings $consequence $khash $completed $shared $policy) $start $before)))
          ($read (sk-premise-step () $given $observed $shared true $policy $state $observation)))
      (fold-semidet (sk-premise-step () $given $exclusions $shared true $policy) $read $after)))

(: sk-completion-sibling-step
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) (List Number) (List Number) SkeletonKey Number (List SkeletonGiven)
       Bool SkeletonReadPolicy SkeletonRowState SkPattern SkeletonRowState))
(= (sk-completion-sibling-step $pin $given $exclusions $observed $siblings $consequence $khash $completed $shared $policy $state $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) (sk-premise-step () $given $exclusions $shared true $policy $state $premise))
      (($type $kbctx $_proof $_tv)
         (if (=alpha (sk-key $type $kbctx) $consequence)
            (sk-premise-step () $given $observed $shared true $policy $state $premise)
            (case (sk-premise-step $pin $given $siblings $shared true $policy $state $premise) (
               (sk-fail
                  (if (== $state sk-fail) sk-fail
                     (sk-premise-step $pin (append-flat $completed $given)
                        (hash-set (fold-flat (sk-without-hash-step $khash) () $siblings))
                        $shared true $policy $state $premise)))
               ($read $read))))))))

(= (sk-merge-facts $combine $ignore $a $ev-a $deps-a $b $ev-b $deps-b)
   (sk-pair-facts (sk-mode-reader (sk-combination-mode (sk-value-reader sk-value))) $combine $ignore $a $ev-a $deps-a $b $ev-b $deps-b))

;; Native event-graph callers use the evaluator's ordinary value reader.
(: sk-part-prior (-[semidet]-> SkeletonKey EvidenceSet (List Number) SkeletonValue))
(= (sk-part-prior $key $ev $exclude)
   (sk-cavity-prior (sk-value-reader sk-value) $key $ev $exclude))
