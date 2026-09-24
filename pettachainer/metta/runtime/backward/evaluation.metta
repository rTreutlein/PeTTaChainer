;; Evaluation over the skeleton and the public backward entry points.
;;
;; Every row keeps the versions of its view: its conclusion computed by the
;; rule's formulas from its premises' values, with the evidence behind it and
;; the hashes of the keys it depends on. A key's value merges its leaf facts
;; and one version per row; overlapping evidence resolves by dominance,
;; disjoint evidence revises.
;;
;; A premise reads, per row of its key, the latest version that does not
;; depend on the reading row's own conclusion. Dependency sets are transitive,
;; so no value supports itself, through inverted rules or any longer cycle.
;; Views are computed in the order rows were created and refreshed while
;; support grows; they persist until something below them changes.

(: SkeletonRowState Type)
;; fold proofs (newest first), evidence, dependency hashes
(: sk-acc (-[det]-> (List Proof) (List Evidence) (List Number) SkeletonRowState))
(: sk-fail SkeletonRowState)
(: SkeletonFold Type)
;; accumulator, member proofs (newest first), evidence, dependency hashes
(: sk-fold-state (-[det]-> Atom (List Proof) (List Evidence) (List Number) SkeletonFold))
(: SkeletonGroup Type)
(: sk-group-found (-[det]-> SkPattern (List SkeletonKey) SkeletonGroup))
(: sk-group-missing SkeletonGroup)
(: TokenReplacement Type)
(: token-state (-[det]-> Atom (List Proof) TokenReplacement))

(: sort-atom (-[det]-> (List $item) (List $item)))

;; Signatures of the mutually recursive functions below.
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter Number SkeletonValue))

(: sk-union (-[det]-> (List $item) (List $item) (List $item)))
(= (sk-union $left $right) (list_to_set (append-flat $left $right)))

;; --- Leaves -----------------------------------------------------------------

;; Hypothetical assumptions are not evidence.
(: leaf-evidence-for-result (-[det]-> SkFact (List Evidence)))
(= (leaf-evidence-for-result ($type $kb $proof $tv))
   (if (assumption-proof? $proof) () (forward-fact-evidence $type $kb $proof $tv)))

(: sk-leaf-view (-[det]-> Number SkFact SkeletonValue))
(= (sk-leaf-view $hash $fact)
   (sk-val $fact (leaf-evidence-for-result $fact) (cons $hash ())))

(: sk-keep-leaf (-[semidet]-> SkeletonKey (List SkFact) SkFact (List SkFact)))
(= (sk-keep-leaf $key $kept $fact)
   (if (=alpha (sk-fact-key $fact) $key) (cons $fact $kept) $kept))

;; The facts stored for exactly this key that match the requested pattern.
(: sk-key-leaves (-[semidet]-> SkeletonKey SkeletonFilter (List SkFact)))
(= (sk-key-leaves $key $filter)
   (case (copy_term $key) (
      ((sk-key $type $kbctx)
         (fold-semidet (sk-keep-leaf $key) () (sk-leaf-facts $type $kbctx $filter)))
      ($_fold ()))))

;; --- Values -----------------------------------------------------------------

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof, overlapping evidence keeps the view
;; whose evidence contains the other's or else the more confident one, and
;; disjoint evidence revises. A dominated view contributes neither evidence
;; nor dependencies.
;; The last rule application of a fact's proof, with its premise proofs still
;; references.
(: sk-step-proof (-[det]-> SkFact Proof))
(= (sk-step-proof ($_type $_kbctx $proof $_tv))
   (case $proof (
      ((proof-ref $pid)
         (case (collapse (once (match &proof ($pid $stored $_ev $_negated) $stored))) (
            ((cons $stored $_rest) $stored)
            (() $proof))))
      ($_leaf $proof))))

(: sk-merge-facts
   (-[det]-> SkFact (List Evidence) (List Number) SkFact (List Evidence) (List Number)
       SkeletonValue))
(= (sk-merge-facts $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-step-proof $a))
          ($proof-b (sk-step-proof $b)))
      (if (== $a $b) (sk-val $a (sk-union $ev-a $ev-b) $deps-a)
         (if (projection-dominates? $proof-a $proof-b) (sk-val $a $ev-a $deps-a)
            (if (projection-dominates? $proof-b $proof-a) (sk-val $b $ev-b $deps-b)
               (if (evidence-sets-overlap? $ev-a $ev-b)
                  (if (evidence-subset? $ev-a $ev-b) (sk-val $b $ev-b $deps-b)
                     (if (evidence-subset? $ev-b $ev-a) (sk-val $a $ev-a $deps-a)
                        (if (>= (term-confidence $a) (term-confidence $b))
                           (sk-val $a $ev-a $deps-a)
                           (sk-val $b $ev-b $deps-b))))
                  (let* (($pooled (sk-union $ev-a $ev-b))
                         ($deps (sk-union $deps-a $deps-b)))
                     (if (>= (term-confidence $a) (term-confidence $b))
                        (sk-val (RevisionMergeProof $a $b) $pooled $deps)
                        (sk-val (RevisionMergeProof $b $a) $pooled $deps)))))))))

(: sk-merge-step (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-merge-step $acc $view)
   (case $acc (
      (sk-none $view)
      ((sk-val $fact $ev $deps)
         (case $view (
            ((sk-val $other $other-ev $other-deps)
               (sk-merge-facts $fact $ev $deps $other $other-ev $other-deps))
            ($_goal $acc))))
      ($_goal $acc))))

;; Each row keeps its latest view and the views it replaced, in the order
;; they were computed. A consumer takes, per row, the latest view that does
;; not depend on the excluded key and matches its pattern; an older one stays
;; usable when a newer one came to depend on that key.
(: sk-admits? (-[det]-> SkeletonFilter Number SkeletonValue Bool))
(= (sk-admits? $filter $exclude $view)
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (stored-list-member? $exclude $deps) false (sk-fact-matches? $filter $fact)))
      ((sk-goal-val $_goal $_proof $_ev $deps)
         (if (stored-list-member? $exclude $deps) false true))
      (sk-none false))))

(: sk-admit-older (-[det]-> SkeletonFilter Number SkeletonValue SkeletonValue SkeletonValue))
(= (sk-admit-older $filter $exclude $kept $view)
   (if (sk-admits? $filter $exclude $view) $view $kept))

(: sk-admit-step
   (-[semidet]-> Number SkeletonKey SkeletonFilter Number (List SkeletonValue) SkeletonVersion
       (List SkeletonValue)))
(= (sk-admit-step $hash $key $filter $exclude $kept (sk-version $_seq $rhash $view))
   (if (sk-admits? $filter $exclude $view) (cons $view $kept)
      (case (fold-semidet (sk-admit-older $filter $exclude) sk-none (sk-older-views $hash $key $rhash)) (
         (sk-none $kept)
         ($older (cons $older $kept))))))

(: sk-older-views (-[det]-> Number SkeletonKey Number (List SkeletonValue)))
(= (sk-older-views $hash $key $rhash)
   (collapse (match &sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) $view (empty)))))

;; The latest versions of a key's rows, in row creation order.
(: sk-latest-versions (-[det]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-latest-versions $hash $key)
   (sort-atom
      (collapse (match &sk_latest ($hash $stored $version)
         (if (=alpha $stored $key) $version (empty))))))

(: sk-latest-view (-[det]-> Number SkeletonKey Number SkeletonValue))
(= (sk-latest-view $hash $key $rhash)
   (case (collapse (once (match &sk_latest ($hash $stored (sk-version $seq $rhash $view))
            (if (=alpha $stored $key) $view (empty))))) (
      ((cons $view $_rest) $view)
      (() sk-none))))

;; A stored view's proof moves to &proof under a fresh id and the view keeps a
;; reference to it, so a view stays the size of one rule application however
;; deep its derivation is. What the evidence of a proof needs from its whole
;; tree, its leaves and whether it negates anything, is summarized with it.
(: sk-store-proof! (-[semidet]-> Proof Proof))
(= (sk-store-proof! $proof)
   (let* (($pid (next-search-id proof_id))
          ($leaves (list_to_set (once (proof-term-evidence-list-mode proof-walk-in-kb $proof))))
          ($negated (proof-term-contains-negated? $proof))
          ($_row (add-atom &proof ($pid $proof $leaves $negated))))
      (proof-ref $pid)))

(: sk-ref-view! (-[semidet]-> SkeletonValue SkeletonValue))
(= (sk-ref-view! $view)
   (case $view (
      ((sk-val ($type $kbctx $proof $tv) $ev $deps)
         (sk-val (data $type $kbctx (sk-store-proof! $proof) $tv) $ev $deps))
      ((sk-goal-val $goal $proof $ev $deps) (sk-goal-val $goal (sk-store-proof! $proof) $ev $deps))
      (sk-none sk-none))))

;; A new view becomes the row's latest; the one it replaces is kept.
(: sk-store-view! (-[semidet]-> Number SkeletonKey Number Number SkeletonValue SkeletonValue))
(= (sk-store-view! $hash $key $seq $rhash $computed)
   (let* (($view (sk-ref-view! $computed))
          ($_moved
             (collapse (match &sk_latest ($hash $stored (sk-version $old-seq $rhash $old))
                (if (=alpha $stored $key)
                   (let $_removed (remove-atom &sk_latest ($hash $stored (sk-version $old-seq $rhash $old)))
                      (add-atom &sk_view ($hash $stored $rhash $old)))
                   (empty)))))
          ($_added (add-atom &sk_latest ($hash $key (sk-version $seq $rhash $view)))))
      $view))

;; --- Folds ------------------------------------------------------------------

(: sk-fold-node-member (-[det]-> SkPattern (List SkPattern)))
(= (sk-fold-node-member $node)
   (let $hash (sk-node-hash $node)
      (collapse (once (match &sk_fold ($hash $stored $member)
         (if (=alpha $stored $node) $member (empty)))))))

(: sk-member-filter (-[det]-> SkPattern SkeletonFilter))
(= (sk-member-filter $member)
   (case (copy_term $member) (
      (($_type $_kbctx $proof $tv) (sk-filter $proof $tv))
      ($_cpu sk-any-filter))))

;; One fold step: the extractor, copied fresh for each member, picks what the
;; step function accumulates from the member's fact.
(: sk-accumulate (-[semidet]-> $extractor (-[semidet]-> $acc Atom $acc) $acc SkFact $acc))
(= (sk-accumulate $extractor $fun $acc $fact)
   (case (copy_term $extractor) (
      ((extract-value $pattern $value)
         (let* ((($pattern ($_kb $_ctx $_vars) $_proof $_tv) (copy_term $fact)))
            ($fun $acc $value)))
      ((extract-inheritance-tv $kbid $_statement)
         (let* ((((Inheritance $subject $_concept) ($_kb $_ctx $_vars) $_proof $tv) (copy_term $fact)))
            ($fun $acc (WeightedTv (inheritance-subject-prior-tv $kbid (brand Statement $subject)) $tv))))
      (extract-tv
         (let* ((($_type $_kbctx $_proof $tv) $fact))
            ($fun $acc $tv))))))

;; Members are read without the views that depend on the fold itself: a
;; member derived through this fold's own output is left out of it.
(: sk-fold-step
   (-[semidet]-> (-[semidet]-> $acc SkFact $acc) SkeletonFilter Number SkeletonFold SkeletonKey
       SkeletonFold))
(= (sk-fold-step $step $filter $exclude (sk-fold-state $acc $proofs $ev $deps) $key)
   (case (sk-value $key $filter $exclude) (
      ((sk-val $fact $member-ev $member-deps)
         (let* ((($_type $_kbctx $proof $_tv) $fact))
            (sk-fold-state ($step $acc $fact) (cons $proof $proofs)
               (sk-union $ev $member-ev) (sk-union $deps $member-deps))))
      ($_none (sk-fold-state $acc $proofs $ev $deps)))))

;; Folds that finish as base rates carry no evidence of their own; the others
;; carry their members' evidence.
(: sk-fold-evidence (-[det]-> AggregateFinish (List Evidence) (List Evidence)))
(= (sk-fold-evidence $finish $ev)
   (if (base-rate-finish? $finish) ()
      (if (== $finish uniform-prior) ()
         (if (== $finish uniform-prior-known) () $ev))))

;; A fold with members proves by its members, in the order they were found.
(: sk-fold-proof (-[semidet]-> Atom (List Proof) Proof))
(= (sk-fold-proof $function $proofs)
   (if (== $proofs ()) (brand Proof cpu)
      (brand Proof
         (cons (if (== $function OrFormula) disjunction foldall-proof)
            (fold-semidet sk-cons-step () $proofs)))))

(: sk-fold-over
   (-[semidet]-> (-[semidet]-> $acc SkFact $acc) Atom $acc AggregateFinish (List SkeletonKey)
       SkeletonFilter Number SkeletonFold))
(= (sk-fold-over $step $function $init $finish $members $filter $exclude)
   (let* (((sk-fold-state $acc $proofs $ev $deps)
             (fold-semidet (sk-fold-step $step $filter $exclude) (sk-fold-state $init () () ()) $members)))
      (sk-fold-state (finish-aggregate $finish $acc) (cons (sk-fold-proof $function $proofs) ())
         (sk-fold-evidence $finish $ev)
         ;; A base rate is an estimate about the population, like a prior: it
         ;; ties its readers to none of its members.
         (if (base-rate-finish? $finish) () $deps))))

(: sk-fold-goal-val (-[semidet]-> Number Goal SkeletonFold SkeletonValue))
(= (sk-fold-goal-val $hash $goal (sk-fold-state $_acc $proofs $ev $deps))
   (case $proofs (
      ((cons $proof $_rest) (sk-goal-val $goal $proof $ev (cons $hash $deps))))))

;; A user base rate is authoritative. An unexpanded fold falls back to a cached
;; estimate when one exists. A computed base rate is cached for reuse.
;; A base rate's value is its user base rate, or else the better of its
;; estimate and a fold over the members the search found; a fold that improves
;; on the estimate replaces it. Without either it is the empty fold. The fold
;; key watches the cache entry. Any other fold is computed from its members.
(: sk-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-fold-view $hash $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let* (($entries (sk-rate-entries $args))
                ($rate-hash (index-hash (base-rate-aggregate-key-value $kbid $pattern $mode)))
                ($key (sk-fold $args))
                ($_watched
                   (if (== (collapse (once (match &sk_rate_folds ($rate-hash $stored)
                              (if (=alpha $stored $key) true (empty))))) ())
                      (add-atom &sk_rate_folds ($rate-hash $key))
                      true)))
            (case $entries (
               ((cons $entry $_rest)
                  (if (base-rate-entry-user? $entry) (sk-cached-fold-view $hash $args $entry)
                     (sk-better-rate-view $hash $args $kbid $pattern $mode $entry)))
               (() (sk-store-computed-rate $kbid $pattern $mode (sk-computed-fold-view $hash $args)))))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args)))))

(: sk-better-rate-view
   (-[semidet]-> Number ScalarFoldSpec KB Statement $mode BaseRateEntry SkeletonValue))
(= (sk-better-rate-view $hash $args $kbid $pattern $mode $entry)
   (if (== (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) ())
      (sk-cached-fold-view $hash $args $entry)
      (let $computed (sk-computed-fold-view $hash $args)
         (case $computed (
            ((sk-goal-val (CPU $_f $_a $tv) $_p $_ev $_deps)
               (if (>= (tv-confidence $tv) (tv-confidence (base-rate-entry-tv $entry)))
                  (sk-store-computed-rate $kbid $pattern $mode $computed)
                  (sk-cached-fold-view $hash $args $entry)))
            ($_none (sk-cached-fold-view $hash $args $entry)))))))

(: sk-store-computed-rate (-[det]-> KB Statement $mode SkeletonValue SkeletonValue))
(= (sk-store-computed-rate $kbid $pattern $mode $view)
   (let $_stored
      (case $view (
         ((sk-goal-val (CPU $_f $_a (STV $s $c)) $_p $_ev $_deps)
            (store-produced-base-rate! $kbid $pattern (STV $s $c) computed $mode))
         ($_other ())))
      $view))

(: sk-cached-fold-view (-[semidet]-> Number ScalarFoldSpec BaseRateEntry SkeletonValue))
(= (sk-cached-fold-view $hash $args $entry)
   (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) ()
      (cons $hash ())))

(: sk-empty-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-empty-fold-view $hash $args)
   (let* ((($_kb $_pattern $_extractor $init $_function $finish $_mode) $args))
      (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate $finish $init)) (brand Proof cpu) ()
         (cons $hash ()))))

(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-computed-fold-view $hash $args)
   (let* ((($_kb $_pattern $extractor $init $function $finish $_mode) $args)
          ($goal (CPU FoldAllCompiled $args $_result)))
      (case (sk-fold-node-member $goal) (
         (() (sk-empty-fold-view $hash $args))
         ((cons $member $_rest)
            (let* (((sk-fold-state $value $proofs $ev $deps)
                      (sk-fold-over (sk-accumulate $extractor $function) $function $init $finish
                         (sk-answers $member) (sk-member-filter $member) $hash)))
               (sk-fold-goal-val $hash (CPU FoldAllCompiled $args $value)
                  (sk-fold-state $value $proofs $ev $deps))))))))

(: sk-group-node (-[det]-> SkeletonKey (List SkPattern)))
(= (sk-group-node $key)
   (let $hash (index-hash $key)
      (collapse (once (match &sk_group_of ($hash $stored $node)
         (if (=alpha $stored $key) $node (empty)))))))

;; Takes fresh copies of the group's arguments and of the key.
(: sk-group-member? (-[det]-> $spec SkeletonKey Bool))
(= (sk-group-member? ($kbctx $pattern $_group $_e $_i $_f $_fi $_m) $key)
   (= (sk-key $pattern $kbctx) $key))

(: sk-keep-group-member
   (-[semidet]-> $spec (List SkeletonKey) SkeletonKey (List SkeletonKey)))
(= (sk-keep-group-member $args $kept $key)
   (if (sk-group-member? (copy_term $args) (copy_term $key)) (cons $key $kept) $kept))

;; The group's member node and the member keys belonging to this group.
(: sk-group-members (-[semidet]-> SkeletonKey $spec SkeletonGroup))
(= (sk-group-members $key $args)
   (case (sk-group-node $key) (
      ((cons $node $_rest)
         (case (sk-fold-node-member $node) (
            ((cons $member $_more)
               (sk-group-found $member
                  (fold-semidet sk-cons-step ()
                     (fold-semidet (sk-keep-group-member $args) () (sk-answers $member)))))
            (() sk-group-missing))))
      (() sk-group-missing))))

(: sk-group-view (-[semidet]-> Number SkeletonKey GroupedFoldSpec SkeletonValue))
(= (sk-group-view $hash $key $args)
   (let* ((($_kbctx $_pattern $_group $extractor $init $function $finish $_mode) $args))
      (case (sk-group-members $key $args) (
         ((sk-group-found $member $members)
            (let* (((sk-fold-state $value $proofs $ev $deps)
                      (sk-fold-over (sk-accumulate $extractor $function) $function $init $finish
                         $members (sk-member-filter $member) $hash)))
               (sk-fold-goal-val $hash (CPU GroupedFoldAllCompiled $args $value)
                  (sk-fold-state $value $proofs $ev $deps))))
         (sk-group-missing sk-none)))))

;; A fold or group gets its view when first read, from its members' views at
;; that point; it is recomputed once one of them changes.
(: sk-fold-views (-[semidet]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-fold-views $hash $key)
   (case $key (
      ((sk-fold $args) (sk-keep-view $hash $key (sk-fold-view $hash (the ScalarFoldSpec $args))))
      ((sk-group $group-args)
         (sk-keep-view $hash $key (sk-group-view $hash $key (the GroupedFoldSpec $group-args))))
      ((sk-key $_type $_kbctx) ()))))

(: sk-keep-view (-[semidet]-> Number SkeletonKey SkeletonValue (List SkeletonVersion)))
(= (sk-keep-view $hash $key $view)
   (cons (sk-version 0 0 (sk-store-view! $hash $key 0 0 $view)) ()))

;; The versions a consumer takes: per row, the latest one it admits.
(: sk-admitted (-[semidet]-> Number SkeletonKey SkeletonFilter Number (List SkeletonValue)))
(= (sk-admitted $hash $key $filter $exclude)
   (let* (($stored (sk-latest-versions $hash $key))
          ($versions (if (== $stored ()) (sk-fold-views $hash $key) $stored)))
      (fold-semidet sk-cons-step () (fold-semidet (sk-admit-step $hash $key $filter $exclude) () $versions))))

;; Leaves first, then one version per row in the order the rows were found.
(: sk-merge-key (-[semidet]-> Number SkeletonKey SkeletonFilter (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $views)
   (fold-semidet sk-merge-step
      (fold-semidet sk-merge-step sk-none (map-semidet (sk-leaf-view $hash) (sk-key-leaves $key $filter)))
      $views))

(: sk-view-deps-step (-[semidet]-> (List Number) SkeletonValue (List Number)))
(= (sk-view-deps-step $deps $view)
   (case $view (
      ((sk-val $_fact $_ev $view-deps) (sk-union $deps $view-deps))
      ((sk-goal-val $_goal $_proof $_ev $view-deps) (sk-union $deps $view-deps))
      (sk-none $deps))))

(: sk-open-filter? (-[det]-> SkeletonFilter Bool))
(= (sk-open-filter? $filter)
   (case $filter (
      (sk-any-filter true)
      ((sk-filter $proof $tv) (if (is-var $proof) (is-var $tv) false)))))

;; An open read without exclusion is cached per key with the dependencies of
;; the versions it merged. A consumer outside those dependencies admits every
;; latest version, so it reads the same value.
(: sk-open-value (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
(= (sk-open-value $hash $key $filter)
   (case (collapse (once (match &sk_merged (sk-merged $hash $stored $deps $value)
            (if (=alpha $stored $key) (sk-merged $hash $stored $deps $value) (empty))))) (
      ((cons $merged $_rest) (let $_counted (query_metric_increment merged-cache-hits) $merged))
      (()
         (let* (($_counted (query_metric_increment merged-cache-misses))
                ($views (sk-admitted $hash $key $filter -1))
                ($deps (fold-semidet sk-view-deps-step () $views))
                ($value (sk-merge-key $hash $key $filter $views))
                ($_cached (add-atom &sk_merged (sk-merged $hash $key $deps $value))))
            (sk-merged $hash $key $deps $value))))))

;; The merged value of a key on behalf of a consumer.
(= (sk-value $key $filter $exclude)
   (let $hash (index-hash $key)
      (if (sk-open-filter? $filter)
         (case (sk-open-value $hash $key $filter) (
            ((sk-merged $_hash $_key $deps $value)
               (if (stored-list-member? $exclude $deps)
                  (sk-merge-key $hash $key $filter (sk-admitted $hash $key $filter $exclude))
                  $value))))
         (sk-merge-key $hash $key $filter (sk-admitted $hash $key $filter $exclude)))))

(: sk-drop-merged! (-[det]-> SkeletonKey Atom))
(= (sk-drop-merged! $key)
   (let* (($hash (index-hash $key))
          ($_dropped
             (collapse (match &sk_merged (sk-merged $hash $stored $deps $value)
                (if (=alpha $stored $key)
                   (remove-atom &sk_merged (sk-merged $hash $stored $deps $value))
                   (empty))))))
      ()))

;; --- Row views --------------------------------------------------------------

;; Compiler-marked joins whose premises intentionally share source evidence.
(: shared-evidence-frontier-proof? (-[det]-> Proof Bool))
(= (shared-evidence-frontier-proof? $proof)
   (if (is-var $proof) false
      (if (is-expr $proof)
         (let $head (car-atom $proof)
            (if (is-var $head) false
               (if (stored-list-member? $head (total-implication-frontier member-inheritance-sample))
                  true
                  (if (== $head inheritance-query-result)
                     (shared-evidence-frontier-proof? (brand Proof (car-atom (cdr-atom $proof))))
                     false))))
         false)))

;; A rule proof marks each fold premise with a `cpu` token; the tokens are
;; replaced, in premise order, by the folds' proofs.
(: replace-token (-[det]-> Atom (List Proof) TokenReplacement))
(: replace-token-list (-[det]-> Atom (List Proof) TokenReplacement))
(= (replace-token-list () $proofs) (token-state () $proofs))
(= (replace-token-list (cons $head $tail) $proofs)
   (let* (((token-state $new-head $proofs1) (replace-token $head $proofs))
          ((token-state $new-tail $proofs2) (replace-token-list $tail $proofs1)))
      (token-state (cons $new-head $new-tail) $proofs2)))
(= (replace-token $term $proofs)
   (if (is-var $term) (token-state $term $proofs)
      (if (== $term cpu)
         (case $proofs (
            ((cons $proof $rest) (token-state $proof $rest))
            (() (token-state cpu ()))))
         (if (is-expr $term) (replace-token-list $term $proofs) (token-state $term $proofs)))))

;; A compiled query adapter proves (_ inner) with an open head; its proof is
;; the inner proof.
(: sk-unwrap-proof (-[det]-> Atom Proof))
(= (sk-unwrap-proof $proof)
   (brand Proof
      (if (is-expr $proof)
         (if (== $proof ()) $proof
            (if (is-var (car-atom $proof))
               (case (cdr-atom $proof) (
                  ((cons $inner ()) $inner)
                  ($_other $proof)))
               $proof))
         $proof)))

(: sk-consume-fold (-[semidet]-> SkeletonRowState $result SkeletonValue SkeletonRowState))
(= (sk-consume-fold (sk-acc $fold-proofs $ev $deps) $res $value)
   (case $value (
      ((sk-goal-val (CPU $_fun $_args $result) $proof $fold-ev $fold-deps)
         (if (= $res $result)
            (sk-acc (cons $proof $fold-proofs) (sk-union $ev $fold-ev) (sk-union $deps $fold-deps))
            sk-fail))
      ($_none sk-fail))))

;; Each premise reads its key's value without the views that depend on the
;; row's conclusion. Premises may share rules but not facts, except in joins
;; the compiler marked as sharing their sources.
(: sk-premise-step (-[semidet]-> Number Bool SkeletonRowState SkPattern SkeletonRowState))
(= (sk-premise-step $exclude $shared $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-acc $fold-proofs $ev $deps)
         (case $premise (
            ((CPU FoldAllCompiled $fold-args $fold-res)
               (sk-consume-fold $state $fold-res (sk-value (sk-fold $fold-args) sk-any-filter $exclude)))
            ((CPU GroupedFoldAllCompiled $group-args $group-res)
               (sk-consume-fold $state $group-res (sk-value (sk-group $group-args) sk-any-filter $exclude)))
            ((CPU $fun $args $res)
               (case (collapse (once (cpu-call 0 $fun $args))) (
                  ((cons $result $_rest) (if (= $res $result) $state sk-fail))
                  (() sk-fail))))
            (($type $kbctx $proof $tv)
               (case (sk-value (sk-key $type $kbctx) (sk-filter $proof $tv) $exclude) (
                  ((sk-val $fact $premise-ev $premise-deps)
                     (if (if $shared false (premise-evidence-overlap? $ev $premise-ev))
                        sk-fail
                        (if (= $premise (if (is-var $proof) $fact (sk-full-fact $fact)))
                           (sk-acc $fold-proofs (sk-union $ev $premise-ev) (sk-union $deps $premise-deps))
                           sk-fail)))
                  ($_none sk-fail))))))))))

(: sk-row-view (-[semidet]-> Number SkeletonRow SkeletonValue))
(= (sk-row-view $khash (sk-row $_ident $concl $premises $_seq))
   (let* ((($type $kbctx $proof $tv) $concl))
      (case (fold-semidet (sk-premise-step $khash (shared-evidence-frontier-proof? $proof))
               (sk-acc () () (cons $khash ())) $premises) (
         ((sk-acc $fold-proofs $ev $deps)
            (let* (((token-state $full-proof $_unused)
                      (replace-token $proof (fold-semidet sk-cons-step () $fold-proofs)))
                   ($fact (assemble-runtime-fact $type $kbctx (sk-unwrap-proof $full-proof) $tv)))
               (sk-val $fact (rule-result-evidence $fact $ev) $deps)))
         (sk-fail sk-none)))))

;; --- Evaluation -------------------------------------------------------------

;; Evaluation starts from what changed since the last one: rows never
;; evaluated, and the readers of keys whose value changed outside evaluation
;; (added facts, removed query-local rows, new fold members). Rows are computed
;; in creation order, so a first computation reads only what was derived
;; earlier, as a proof is built from proofs that already exist. When a row's
;; view changes, the rows reading its key are scheduled: later rows in the same
;; pass, earlier rows in the next one. Nothing whose inputs did not change is
;; visited.
;;
;; Inverted rules make most of a real skeleton cyclic, so values need not
;; settle. A recomputed view is kept only when it brings support: a dependency
;; the row never had. The keys a row can depend on are finite, so evaluation
;; ends. A truth value that changes without new support, when a reader switches
;; to an older admissible version or a merge's dominance flips, keeps the view
;; it had. A change from outside the rows (a fact, a removed query-local row, a
;; fold member) makes each reader recompute without that test, once per
;; evaluation for each key that caused it.

;; The rows that read a key directly, as fact premise, fold or group.
(: sk-readers (-[det]-> SkeletonKey (List SkeletonItem)))
(= (sk-readers $key)
   (let $hash (index-hash $key)
      (collapse (match &sk_reader ($hash $stored $khash $rhash)
         (if (=alpha $stored $key)
            (match &sk_row ($khash $rkey $rhash (sk-row $ident $concl $premises $seq))
               (sk-row-item $seq $khash $rkey $rhash (sk-row $ident $concl $premises $seq)))
            (empty))))))

(: sk-item-seq (-[det]-> SkeletonItem Number))
(= (sk-item-seq (sk-row-item $seq $_khash $_key $_rhash $_row)) $seq)

(: sk-item-key-hash (-[det]-> SkeletonItem Number))
(= (sk-item-key-hash (sk-row-item $_seq $khash $_key $_rhash $_row)) $khash)

;; this pass's remaining rows and the next pass's rows, by creation number
(: SkeletonWork Type)
(: sk-work (-[det]-> (Heap SkeletonItem) (Heap SkeletonItem) SkeletonWork))

(: sk-queue-new? (-[det]-> Number SkeletonItem Bool))
(= (sk-queue-new? $pass (sk-row-item $_seq $khash $_key $rhash $_row))
   (if (not (== (collapse (once (match &sk_queued ($pass $khash $rhash) true))) ())) false
      (let $_queued (add-atom &sk_queued ($pass $khash $rhash)) true)))

;; What changed for a key's readers: a new row view with its dependencies,
;; the same with the key's open merged value unchanged and the dependencies of
;; that value before and after, or a change from outside the rows (a fact, a
;; removed query-local row, a fold member) caused by the key with that hash.
(: SkeletonChange Type)
(: sk-view-change (-[det]-> (List Number) SkeletonChange))
(: sk-value-same (-[det]-> (List Number) (List Number) SkeletonChange))
(: sk-outside-change (-[det]-> Number SkeletonChange))

;; Every fact premise on the key asks for an open pattern.
(: sk-reads-open? (-[det]-> SkeletonKey Atom SkPattern Bool))
(= (sk-reads-open? $key $open $premise)
   (if $open
      (case $premise (
         (($type $kbctx $proof $tv)
            (if (=alpha (sk-key $type $kbctx) $key) (if (is-var $proof) (is-var $tv) false) true))
         ($_cpu true)))
      false))

;; A reader whose own key the new view depends on does not admit it. When the
;; key's open merged value did not change, a reader outside its dependencies
;; that reads it openly gets that same value.
(: sk-reader-affected? (-[semidet]-> SkeletonKey SkeletonChange SkeletonItem Bool))
(= (sk-reader-affected? $key $change (sk-row-item $_seq $khash $_rkey $_rhash (sk-row $_ident $_concl $premises $_s)))
   (case $change (
      ((sk-outside-change $_cause) true)
      ((sk-view-change $deps) (if (stored-list-member? $khash $deps) false true))
      ((sk-value-same $deps $merged-deps)
         (if (stored-list-member? $khash $deps) false
            (if (stored-list-member? $khash $merged-deps) true
               (if (fold-semidet (sk-reads-open? $key) true $premises) false true)))))))

;; A reader created after the row that changed its input is still ahead in
;; this pass; an earlier one waits for the next.
(: sk-schedule-reader
   (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonItem SkeletonWork))
(= (sk-schedule-reader $pass $seq $key $change (sk-work $todo $next) $item)
   (if (let $_forced
          (case $change (
             ((sk-outside-change $cause) (sk-force! $cause $item))
             ($_view ())))
          (sk-reader-affected? $key $change $item))
      (if (> (sk-item-seq $item) $seq)
         (if (sk-queue-new? $pass $item)
            (sk-work (add_to_heap $todo (sk-item-seq $item) $item) $next)
            (sk-work $todo $next))
         (if (sk-queue-new? (+ $pass 1) $item)
            (sk-work $todo (add_to_heap $next (sk-item-seq $item) $item))
            (sk-work $todo $next)))
      (sk-work $todo $next)))

(: sk-drop-fold-view! (-[det]-> SkeletonKey Atom))
(= (sk-drop-fold-view! $key) (sk-drop-row-views! (index-hash $key) $key 0))

;; A changed key schedules the rows it affects. A fold or group over it is
;; recomputed when next read, and all of its readers are scheduled.
(: sk-key-changed
   (-[semidet]-> Number Number SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-key-changed $pass $seq $change $work $key)
   (let* (($hash (index-hash $key))
          ($folds
             (collapse (match &sk_use ($hash $stored $fold)
                (if (=alpha $stored $key) $fold (empty)))))
          ($scheduled (fold-semidet (sk-schedule-reader $pass $seq $key $change) $work (sk-readers $key))))
      (fold-semidet (sk-fold-changed $pass $seq $hash) $scheduled $folds)))

;; A member change recomputes a fold that was read, and its readers are forced
;; by each member that changes its value. A fold nobody read since it last
;; changed is computed when next read.
(: sk-fold-changed (-[semidet]-> Number Number Number SkeletonWork SkeletonKey SkeletonWork))
(= (sk-fold-changed $pass $seq $member $work $fold)
   (let* (($hash (index-hash $fold))
          ($old (sk-latest-view $hash $fold 0))
          ($_view (sk-drop-fold-view! $fold))
          ($_merged (sk-drop-merged! $fold)))
      (case $old (
         (sk-none $work)
         ($_read
            (case (sk-fold-views $hash $fold) (
               ((cons (sk-version $_seq $_rhash $new) $_rest)
                  (if (sk-same-view? $new $old) $work
                     (sk-key-changed $pass $seq (sk-outside-change $member) $work $fold)))
               (() (sk-key-changed $pass $seq (sk-outside-change $member) $work $fold)))))))))

;; A row is forced once per evaluation by each changed key: a fold's readers
;; follow its members as they arrive, and a fold feeding back into its own
;; members still ends.
(: sk-force! (-[det]-> Number SkeletonItem Atom))
(= (sk-force! $cause (sk-row-item $_seq $khash $_key $rhash $_row))
   (if (== (collapse (once (match &sk_forced_used ($khash $rhash $cause) true))) ())
      (let* (($_used (add-atom &sk_forced_used ($khash $rhash $cause)))
             ($_forced (add-atom &sk_forced ($khash $rhash))))
         ())
      ()))

(: sk-take-forced! (-[det]-> Number Number Bool))
(= (sk-take-forced! $khash $rhash)
   (if (== (collapse (once (match &sk_forced ($khash $rhash) true))) ()) false
      (let $_taken (remove-atom &sk_forced ($khash $rhash)) true)))

;; Whether a view brings a dependency none of the row's views had.
(: sk-new-support? (-[semidet]-> Number SkeletonKey Number SkeletonValue Bool))
(= (sk-new-support? $hash $key $rhash $new)
   (let $had
      (fold-semidet sk-view-deps-step ()
         (cons (sk-latest-view $hash $key $rhash) (sk-older-views $hash $key $rhash)))
      (fold-semidet (sk-gains-step $had) false (fold-semidet sk-view-deps-step () (cons $new ())))))

(: sk-gains-step (-[det]-> (List Number) Bool Number Bool))
(= (sk-gains-step $had $gained $dep) (if $gained true (if (stored-list-member? $dep $had) false true)))

;; Two views of a row are the same when they agree on all but the proof: the
;; stored proof stays a valid derivation of the same value.
(: sk-same-view? (-[det]-> SkeletonValue SkeletonValue Bool))
(= (sk-same-view? $new $old)
   (case $new (
      ((sk-val ($_type $_kbctx $_proof $tv) $ev $deps)
         (case $old (
            ((sk-val ($_old-type $_old-kbctx $_old-proof $old-tv) $old-ev $old-deps)
               (if (=alpha $tv $old-tv) (if (=alpha $ev $old-ev) (=alpha $deps $old-deps) false) false))
            ($_other false))))
      ((sk-goal-val $goal $_proof $ev $deps)
         (case $old (
            ((sk-goal-val $old-goal $_old-proof $old-ev $old-deps)
               (if (=alpha $goal $old-goal) (if (=alpha $ev $old-ev) (=alpha $deps $old-deps) false) false))
            ($_other false))))
      (sk-none (== $old sk-none)))))

;; A row whose view differs from its latest version stores a new version and
;; changes its key, when it is the row's first view, it was forced, or it
;; brings new support.
(: sk-compute (-[semidet]-> Number SkeletonWork SkeletonItem SkeletonWork))
(= (sk-compute $pass $work (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_computed (query_metric_increment row-computes))
          ($forced (sk-take-forced! $hash $rhash))
          ($new (sk-row-view $hash (copy_term $row))))
      (case $new (
         (sk-none $work)
         ($_view
            (let $latest (sk-latest-view $hash $key $rhash)
            (if (if (sk-same-view? $new $latest) true
                   (if $forced false
                      (if (== $latest sk-none) false
                         (if (sk-new-support? $hash $key $rhash $new) false
                            (let $_unsupported (query_metric_increment views-without-support) true)))))
               $work
               (let* (($before
                         (collapse (once (match &sk_merged (sk-merged $hash $stored $deps $value)
                            (if (=alpha $stored $key) (sk-merged $hash $stored $deps $value) (empty))))))
                      ($_stored (sk-store-view! $hash $key $seq $rhash $new))
                      ($_stored-count (query_metric_increment views-stored))
                      ($_merged (sk-drop-merged! $key))
                      ($deps (fold-semidet sk-view-deps-step () (cons $new ()))))
                  (sk-key-changed $pass $seq (sk-value-change $hash $key $deps $before) $work $key)))))))))

;; An unchanged open merged value is known only when it was cached before.
(: sk-value-change (-[semidet]-> Number SkeletonKey (List Number) (List SkeletonMerged) SkeletonChange))
(= (sk-value-change $hash $key $deps $before)
   (case $before (
      (() (sk-view-change $deps))
      ((cons (sk-merged $_h $_k $old-deps $old-value) $_rest)
         (case (sk-open-value $hash $key sk-any-filter) (
            ((sk-merged $_h2 $_k2 $new-deps $new-value)
               (if (=alpha $old-value $new-value)
                  (sk-value-same $deps (sk-union $old-deps $new-deps))
                  (sk-view-change $deps)))))))))

(: sk-work-off! (-[semidet]-> Number SkeletonWork Atom))
(= (sk-work-off! $pass (sk-work $todo $next))
   (if (heap-empty? $todo)
      (if (heap-empty? $next) () (sk-work-off! (+ $pass 1) (sk-work $next (empty_heap))))
      (sk-work-pop! $pass $next (heap_pop $todo))))

(: sk-work-pop!
   (-[semidet]-> Number (Heap SkeletonItem) (Number SkeletonItem (Heap SkeletonItem)) Atom))
;; Each row commits to its one result, so the loop leaves no choice points and
;; runs in constant stack however many rows it computes.
(= (sk-work-pop! $pass $next ($_seq $item $rest))
   (sk-work-off! $pass (once (sk-compute $pass (sk-work $rest $next) $item))))

;; Keys changed outside evaluation: a fold or group key recomputes when next
;; read, and every changed key's readers are scheduled.
(: sk-dirty-seed (-[semidet]-> SkeletonWork SkeletonKey SkeletonWork))
(= (sk-dirty-seed $work $key)
   (let* (($_view
             (case $key (
                ((sk-key $_type $_kbctx) ())
                ($_fold (sk-drop-fold-view! $key)))))
          ($_merged (sk-drop-merged! $key)))
      (sk-key-changed 0 -1 (sk-outside-change (index-hash $key)) $work $key)))

(: sk-seed-new (-[det]-> (Heap SkeletonItem) SkeletonItem (Heap SkeletonItem)))
(= (sk-seed-new $todo $item)
   (if (sk-queue-new? 0 $item) (add_to_heap $todo (sk-item-seq $item) $item) $todo))

(: sk-evaluate! (-[semidet]-> Atom))
(= (sk-evaluate!)
   (let* (($_queued (collapse (match &sk_queued ($pass $khash $rhash) (remove-atom &sk_queued ($pass $khash $rhash)))))
          ($_forced (collapse (match &sk_forced ($khash $rhash) (remove-atom &sk_forced ($khash $rhash)))))
          ($_used (collapse (match &sk_forced_used ($khash $rhash $cause) (remove-atom &sk_forced_used ($khash $rhash $cause)))))
          ($new
             (collapse (match &sk_new (sk-row-item $seq $hash $key $rhash $row)
                (let $_taken (remove-atom &sk_new (sk-row-item $seq $hash $key $rhash $row))
                   (sk-row-item $seq $hash $key $rhash $row)))))
          ($dirty
             (collapse (match &sk_dirty (sk-dirty $key)
                (let $_taken (remove-atom &sk_dirty (sk-dirty $key)) $key))))
          ($seeded
             (fold-semidet sk-dirty-seed
                (sk-work (fold-semidet sk-seed-new (empty_heap) $new) (empty_heap)) $dirty)))
      (sk-work-off! 0 $seeded)))

;; --- Base-rate API ----------------------------------------------------------

;; A user base rate replaces whatever every fold over its pattern computed, so
;; all cached values are dropped.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv user any)))
          ($_values (collapse (match &sk_view ($hash $key $rhash $view) (remove-atom &sk_view ($hash $key $rhash $view)))))
          ($_latest (collapse (match &sk_latest ($hash $key $version) (remove-atom &sk_latest ($hash $key $version)))))
          ($_merged
             (collapse (match &sk_merged (sk-merged $hash $key $deps $value)
                (remove-atom &sk_merged (sk-merged $hash $key $deps $value))))))
      ()))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (let* (($_old (base-rate-cache-remove! $kbid $pattern))
          ($_values (collapse (match &sk_view ($hash $key $rhash $view) (remove-atom &sk_view ($hash $key $rhash $view)))))
          ($_latest (collapse (match &sk_latest ($hash $key $version) (remove-atom &sk_latest ($hash $key $version)))))
          ($_merged
             (collapse (match &sk_merged (sk-merged $hash $key $deps $value)
                (remove-atom &sk_merged (sk-merged $hash $key $deps $value))))))
      ()))

;; --- Materialization --------------------------------------------------------

(: materialized-rows (-[det]-> ForwardOutputKey (List MaterializedRow)))
(= (materialized-rows (forward-output-key $kb $type))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (collapse (match &materialized_facts (materialized-row $hash $type $kb $fact $ev)
         (materialized-row $hash $type $kb $fact $ev)))))

(: remove-materialized! (-[det]-> MaterializedRow Atom))
(= (remove-materialized! (materialized-row $hash $type $kb $fact $ev))
   (let* (($_frontier (remove-atom &forward_frontier (forward-frontier-row $hash $type $kb $fact $ev)))
          ($_mark (remove-atom &materialized_facts (materialized-row $hash $type $kb $fact $ev))))
      ()))

;; A re-materialization of an output key replaces the key's earlier
;; materialized rows. Marked facts are never leaves of the backward search.
(: upsert-materialized! (-[nondet]-> SkFact (List Evidence) ForwardOutputChange))
(= (upsert-materialized! $fact $ev)
   (let* (($okey (forward-fact-key $fact))
          ((forward-output-key $kb $type) $okey)
          ($hash (forward-output-index-hash $okey)))
      (if (forward-frontier-has-exact? $okey $fact $ev) no-forward-change
         (let* (($old (materialized-rows $okey))
                ($_remove (foreach-flat remove-materialized! $old))
                ($_refresh
                   (if (== $old ()) ()
                      (progn
                         (forward-apply-unqueued-change!
                            (chainer-first-or no-forward-change
                               (collapse (once (forward-refresh-output-key! $okey)))))
                         ())))
                ($change (forward-candidate-upsert! (forward-derived $fact $ev) false))
                ($_mark
                   (if (forward-frontier-has-exact? $okey $fact $ev)
                      (once (add-atom &materialized_facts (materialized-row $hash $type $kb $fact $ev)))
                      ())))
            $change))))

(: materializable-result? (-[det]-> SkFact Bool))
(= (materializable-result? ($type ($_kbid $ctx $vars) $_prf $tv))
   (if (== $ctx MAIN)
      (if (== $vars Nil)
         (if (== (extract-vars $type) ())
            (case $tv (
               ((STV $_s $_c) (== (extract-vars $tv) ()))
               ($_other false)))
            false)
         false)
      false))

(: sk-materialize! (-[semidet]-> SkeletonValue Atom))
(= (sk-materialize! $value)
   (case $value (
      ((sk-val $fact $ev $_deps)
         (if (materializable-result? $fact)
            (let $change
               (chainer-first-or no-forward-change (collapse (once (upsert-materialized! (sk-full-fact $fact) $ev))))
               (let $_applied (forward-apply-unqueued-change! $change) ()))
            ()))
      ($_other ()))))

;; --- Query metrics ----------------------------------------------------------

(: set-backward-query-metrics (-[det]-> Bool Bool))
(= (set-backward-query-metrics $enabled) (query_metrics_set_enabled $enabled))

(: backward-query-counter-keys (-[det]-> (List Atom)))
(= (backward-query-counter-keys)
   (expansions rows-created rows-deferred joins-deferred row-computes views-stored
    views-without-support merged-cache-hits merged-cache-misses))

(: sk-counter-reset (-[det]-> Atom Atom Atom))
(= (sk-counter-reset $_acc $key) (let $_zero (query_metric_set $key 0) ()))

(: sk-size-metrics! (-[det]-> Atom Atom Number))
(= (sk-size-metrics! $nodes $rows)
   (let $_nodes (query_metric_set $nodes (match-count &sk_expanded $_node))
      (query_metric_set $rows (match-count &sk_row $_row))))

(: begin-backward-query-metrics! (-[det]-> Number))
(= (begin-backward-query-metrics!)
   (if (query_metrics_enabled)
      (let $_reset (fold-flat sk-counter-reset () (backward-query-counter-keys))
         (sk-size-metrics! skeleton-nodes-before skeleton-rows-before))
      0))

(: end-backward-query-metrics! (-[det]-> Number))
(= (end-backward-query-metrics!)
   (if (query_metrics_enabled) (sk-size-metrics! skeleton-nodes-after skeleton-rows-after) 0))

(: BackwardQueryMetric Type)
(: query-metric (-[det]-> Atom Number BackwardQueryMetric))
(: sk-metric-row (-[det]-> Atom BackwardQueryMetric))
(= (sk-metric-row $key) (query-metric $key (query_metric_value $key)))

(: backward-query-metrics (-[det]-> (List BackwardQueryMetric)))
(= (backward-query-metrics)
   (map-flat sk-metric-row
      (cons skeleton-nodes-before (cons skeleton-nodes-after
         (cons skeleton-rows-before (cons skeleton-rows-after (backward-query-counter-keys)))))))

;; --- Entry points -----------------------------------------------------------

(: sk-root-value (-[semidet]-> SkeletonFilter SkeletonKey SkeletonValue))
(= (sk-root-value $filter $key) (sk-value $key $filter -1))

(: sk-root-values (-[semidet]-> SkPattern (List SkeletonValue)))
(= (sk-root-values $goal)
   (case $goal (
      ((CPU $fun $args $res)
         (if (== $fun FoldAllCompiled)
            (cons (sk-value (sk-fold $args) sk-any-filter -1) ())
            (if (== $fun GroupedFoldAllCompiled)
               (map-semidet (sk-root-value sk-any-filter) (sk-answers $goal))
               (collapse (let $result (cpu-call 0 $fun $args)
                  (if (= $res $result)
                     (sk-goal-val (CPU $fun $args $result) (brand Proof cpu) () ())
                     (empty)))))))
      (($_type $_kbctx $proof $tv)
         (map-semidet (sk-root-value (sk-filter $proof $tv)) (sk-answers $goal))))))

(: sk-proven-step (-[semidet]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-proven-step $kept $value)
   (case $value (
      (sk-none $kept)
      ($_proven (cons $value $kept)))))

(: sk-result-step (-[semidet]-> (List RuntimeResult) SkeletonValue (List RuntimeResult)))
(= (sk-result-step $kept $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (cons (brand RuntimeResult (sk-full-fact $fact)) $kept))
      ((sk-goal-val $goal $_proof $_ev $_deps) (cons (brand RuntimeResult $goal) $kept))
      (sk-none $kept))))

;; Proven answers in root order; a materializing query writes back the first.
(: sk-root-results (-[semidet]-> Bool SkPattern (List RuntimeResult)))
(= (sk-root-results $materialize? $goal)
   (let* (($values (fold-semidet sk-cons-step () (fold-semidet sk-proven-step () (sk-root-values $goal))))
          ($_materialized
             (if $materialize?
                (case $values (
                   ((cons $first $_rest) (sk-materialize! $first))
                   (() ())))
                ())))
      (fold-semidet sk-cons-step () (fold-semidet sk-result-step () $values))))

(: sk-root-score-step (-[det]-> Atom SkPattern Atom))
(= (sk-root-score-step $_acc $goal)
   (let* (($hash (sk-node-hash $goal))
          ($_root (add-atom &sk_roots ($hash $goal))))
      (sk-raise-score! $goal 1.0)))

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $goals $materialize?)
   (let* (($_seen (collapse (match &sk_seen ($hash $node) (remove-atom &sk_seen ($hash $node)))))
          ($_fresh (collapse (match &sk_fresh (sk-fresh $node) (remove-atom &sk_fresh (sk-fresh $node)))))
          ($_budget (change-state! sk_budget $steps))
          ($_rows (change-state! sk_row_budget (* 10 $steps)))
          ($_activate (sk-activate-pending!))
          ($_parked (sk-park-deliveries!))
          ($_pushes (change-state! sk_push_seq 0))
          ($_old-roots (collapse (match &sk_roots ($hash $root) (remove-atom &sk_roots ($hash $root)))))
          ($_scored (fold-semidet sk-root-score-step () $goals))
          ($_search (sk-search! (fold-semidet (sk-push 0) (empty_heap) $goals)))
          ($_evaluated (sk-evaluate!))
          ($results (map-semidet (sk-root-results $materialize?) $goals))
          ($_temp (sk-clear-temp!)))
      $results))

(: chainer-many
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(= (chainer-many $steps $goals)
   (execute-backward $steps $goals false))

(: chainer
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer $steps $goal)
   (chainer-first-or () (execute-backward $steps ($goal) false)))

(: chainer-materialize
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer-materialize $steps $goal)
   (chainer-first-or () (execute-backward $steps ($goal) true)))

(: chainer-many-materialize
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(= (chainer-many-materialize $steps $goals)
   (execute-backward $steps $goals true))
