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
;; Views are computed in the order rows were created and refreshed in a few
;; passes; they persist in &sk_view until something below them changes.

(: SkeletonFilter Type)
;; the proof and truth-value pattern a consumer asks for
(: sk-filter (-[det]-> Proof TV SkeletonFilter))
(: sk-any-filter SkeletonFilter)
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
(: sk-collect! (-[semidet]-> Atom SkeletonKey Atom))

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
         (fold-semidet (sk-keep-leaf $key) ()
            (case $filter (
               ((sk-filter $proof $tv) (sk-leaf-facts $type $kbctx $proof $tv))
               (sk-any-filter (sk-leaf-facts $type $kbctx $_proof $_tv))))))
      ($_fold ()))))

;; --- Values -----------------------------------------------------------------

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof, overlapping evidence keeps the view
;; whose evidence contains the other's or else the more confident one, and
;; disjoint evidence revises. A dominated view contributes neither evidence
;; nor dependencies.
(: sk-fact-proof (-[det]-> SkFact Proof))
(= (sk-fact-proof ($_type $_kbctx $proof $_tv)) $proof)

(: sk-merge-facts
   (-[det]-> SkFact (List Evidence) (List Number) SkFact (List Evidence) (List Number)
       SkeletonValue))
(= (sk-merge-facts $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-fact-proof $a))
          ($proof-b (sk-fact-proof $b)))
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

;; Tries the pattern on fresh copies so neither side gets bound.
(: sk-fact-matches? (-[det]-> SkeletonFilter SkFact Bool))
(= (sk-fact-matches? $filter $fact)
   (case (copy_term $filter) (
      (sk-any-filter true)
      ((sk-filter $want-proof $want-tv)
         (if (is-var $want-proof)
            (if (is-var $want-tv) true (sk-pattern-matches? $want-proof $want-tv (copy_term $fact)))
            (sk-pattern-matches? $want-proof $want-tv (copy_term $fact)))))))

(: sk-pattern-matches? (-[det]-> Proof TV SkFact Bool))
(= (sk-pattern-matches? $want-proof $want-tv ($_type $_kbctx $got-proof $got-tv))
   (if (= $got-proof $want-proof) (= $got-tv $want-tv) false))

;; Each row keeps the versions of its view in the order they were computed.
;; A consumer takes, per row, the latest version that does not depend on the
;; excluded key and matches its pattern; an older version stays usable when a
;; newer one came to depend on that key.
(: sk-admit-step
   (-[semidet]-> Number SkeletonFilter (List SkeletonVersion) SkeletonVersion
       (List SkeletonVersion)))
(= (sk-admit-step $exclude $filter $kept (sk-version $rhash $view))
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (stored-list-member? $exclude $deps) $kept
            (if (sk-fact-matches? $filter $fact) (sk-put-version $rhash $view $kept) $kept)))
      ((sk-goal-val $_goal $_proof $_ev $deps)
         (if (stored-list-member? $exclude $deps) $kept (sk-put-version $rhash $view $kept)))
      (sk-none $kept))))

;; Versions arrive oldest first, so a later one replaces an earlier one of the
;; same row in place.
(: sk-put-version
   (-[det]-> Number SkeletonValue (List SkeletonVersion) (List SkeletonVersion)))
(= (sk-put-version $rhash $view ()) (cons (sk-version $rhash $view) ()))
(= (sk-put-version $rhash $view (cons (sk-version $other $old) $rest))
   (if (== $rhash $other) (cons (sk-version $rhash $view) $rest)
      (cons (sk-version $other $old) (sk-put-version $rhash $view $rest))))

(: sk-version-view (-[semidet]-> (List SkeletonValue) SkeletonVersion (List SkeletonValue)))
(= (sk-version-view $views (sk-version $_rhash $view)) (cons $view $views))

(: sk-stored-views (-[det]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-stored-views $hash $key)
   (collapse (match &sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) (sk-version $rhash $view) (empty)))))

(: sk-store-view! (-[det]-> Number SkeletonKey Number SkeletonValue Atom))
(= (sk-store-view! $hash $key $rhash $view)
   (let $_view (add-atom &sk_view ($hash $key $rhash $view)) ()))

;; --- Folds ------------------------------------------------------------------

(: sk-fold-node-member (-[det]-> SkPattern (List SkPattern)))
(= (sk-fold-node-member $node)
   (let $hash (sk-node-hash $node)
      (collapse (once (match &sk_fold ($hash $stored $member)
         (if (=alpha $stored $node) $member (empty)))))))

(: sk-fold-members (-[det]-> SkPattern (List SkeletonKey)))
(= (sk-fold-members $node)
   (case (sk-fold-node-member $node) (
      (() ())
      ((cons $member $_rest) (sk-answers $member)))))

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
(: sk-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-fold-view $hash $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
            (if (base-rate-cache-user-present? $entries)
               (sk-cached-fold-view $hash $args $entries)
               (let* (($view (sk-computed-fold-view $hash $args $entries))
                      ($_stored
                         (case $view (
                            ((sk-goal-val (CPU $_f $_a (STV $s $c)) $_p $_ev $_deps)
                               (store-produced-base-rate! $kbid $pattern (STV $s $c) computed $mode))
                            ($_other ())))))
                  $view))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args ())))))

(: sk-cached-fold-view (-[semidet]-> Number ScalarFoldSpec (List BaseRateEntry) SkeletonValue))
(= (sk-cached-fold-view $hash $args (cons $entry $_rest))
   (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) ()
      (cons $hash ())))

(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec (List BaseRateEntry) SkeletonValue))
(= (sk-computed-fold-view $hash $args $entries)
   (let* ((($_kb $_pattern $extractor $init $function $finish $_mode) $args)
          ($goal (CPU FoldAllCompiled $args $_result)))
      (case (sk-fold-node-member $goal) (
         (()
            (if (== $entries ())
               (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate $finish $init))
                  (brand Proof cpu) () (cons $hash ()))
               (sk-cached-fold-view $hash $args $entries)))
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

(: sk-keep-view (-[det]-> Number SkeletonKey SkeletonValue (List SkeletonVersion)))
(= (sk-keep-view $hash $key $view)
   (let $_stored (sk-store-view! $hash $key 0 $view) (cons (sk-version 0 $view) ())))

;; The merged value of a key on behalf of a consumer: leaves first, then one
;; version per row in the order the rows were found.
(= (sk-value $key $filter $exclude)
   (let* (($hash (index-hash $key))
          ($stored (sk-stored-views $hash $key))
          ($versions (if (== $stored ()) (sk-fold-views $hash $key) $stored))
          ($views
             (fold-semidet sk-cons-step ()
                (fold-semidet sk-version-view ()
                   (fold-semidet (sk-admit-step $exclude $filter) () $versions)))))
      (fold-semidet sk-merge-step
         (fold-semidet sk-merge-step sk-none (map-semidet (sk-leaf-view $hash) (sk-key-leaves $key $filter)))
         $views)))

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
                        (if (= $premise $fact)
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

;; --- Evaluation order and passes ----------------------------------------------

(: sk-reached? (-[det]-> Number SkeletonKey Bool))
(= (sk-reached? $hash $key)
   (not (== (collapse (once (match &sk_reach ($hash $stored)
               (if (=alpha $stored $key) true (empty)))))
            ())))

;; The keys a row reads: its fact premises and folds, and for a fold the keys
;; of its members.
(: sk-premise-key-step (-[semidet]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-premise-key-step $keys $premise)
   (case $premise (
      ((CPU FoldAllCompiled $fold-args $_fold-res)
         (fold-semidet sk-cons-step (cons (sk-fold $fold-args) $keys)
            (sk-fold-members (CPU FoldAllCompiled $fold-args $_result))))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res)
         (case (sk-group-members (sk-group $group-args) $group-args) (
            ((sk-group-found $_member $members)
               (fold-semidet sk-cons-step (cons (sk-group $group-args) $keys) $members))
            (sk-group-missing (cons (sk-group $group-args) $keys)))))
      ((CPU $_fun $_args $_res) $keys)
      (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $keys)))))

;; The rows the roots can reach are listed with their creation numbers.
(= (sk-collect! $_acc $key)
   (let $hash (index-hash $key)
      (if (sk-reached? $hash $key) ()
         (let* (($_mark (add-atom &sk_reach ($hash $key)))
                ($items
                   (collapse (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
                      (if (=alpha $stored $key)
                         (sk-row-item $seq $hash $stored $rhash (sk-row $ident $concl $premises $seq))
                         (empty))))))
            (fold-semidet sk-collect-row () $items)))))

(: sk-collect-row (-[semidet]-> Atom SkeletonItem Atom))
(= (sk-collect-row $_acc (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $s)))
   (let $_listed
      (add-atom &sk_order (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $s)))
      (fold-semidet sk-collect! () (fold-semidet sk-premise-key-step () $premises))))

(: sk-changed-in? (-[det]-> Number Number Bool))
(= (sk-changed-in? $pass $hash)
   (not (== (collapse (once (match &sk_changed (sk-changed $pass $hash) true))) ())))

;; A key changed in this pass or the previous one.
(: sk-reads-changed? (-[det]-> Number (List SkeletonKey) Bool))
(= (sk-reads-changed? $_pass ()) false)
(= (sk-reads-changed? $pass (cons $key $rest))
   (let $hash (index-hash $key)
      (if (sk-changed-in? $pass $hash) true
         (if (sk-changed-in? (- $pass 1) $hash) true (sk-reads-changed? $pass $rest)))))

;; A fold read in a pass after one of its members changed is recomputed.
(: sk-refresh-fold! (-[semidet]-> Number SkeletonKey (List SkeletonKey) Atom))
(= (sk-refresh-fold! $pass $key $members)
   (if (sk-reads-changed? $pass $members)
      (let* (($hash (index-hash $key))
             ($_dropped
                (collapse (match &sk_view ($hash $stored 0 $view)
                   (if (=alpha $stored $key)
                      (remove-atom &sk_view ($hash $stored 0 $view))
                      (empty))))))
         ())
      ()))

(: sk-refresh-fold-step (-[semidet]-> Number Atom SkPattern Atom))
(= (sk-refresh-fold-step $pass $_acc $premise)
   (case $premise (
      ((CPU FoldAllCompiled $fold-args $_fold-res)
         (sk-refresh-fold! $pass (sk-fold $fold-args)
            (sk-fold-members (CPU FoldAllCompiled $fold-args $_result))))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res)
         (case (sk-group-members (sk-group $group-args) $group-args) (
            ((sk-group-found $_member $members) (sk-refresh-fold! $pass (sk-group $group-args) $members))
            (sk-group-missing ()))))
      ($_other ()))))

(: sk-row-versions (-[det]-> Number SkeletonKey Number (List SkeletonValue)))
(= (sk-row-versions $hash $key $rhash)
   (collapse (match &sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) $view (empty)))))

(: sk-known-version? (-[det]-> SkeletonValue (List SkeletonValue) Bool))
(= (sk-known-version? $_view ()) false)
(= (sk-known-version? $view (cons $version $rest))
   (if (=alpha $view $version) true (sk-known-version? $view $rest)))

;; Views are computed in the order rows were created, so a first pass reads
;; only what was derived earlier, as a proof is built from proofs that already
;; exist. Support found later reaches earlier readers in further passes: a row
;; is recomputed when a key it reads changed in this pass or the previous one.
;; A new version is kept only if it differs from every earlier one, so the
;; passes end.
(: sk-compute-step (-[semidet]-> Number Atom SkeletonItem Atom))
(= (sk-compute-step $pass $_acc (sk-row-item $_seq $hash $key $rhash $row))
   (let* (((sk-row $_ident $_concl $premises $_s) $row)
          ($versions (sk-row-versions $hash $key $rhash)))
      (if (if (== $versions ()) (== $pass 0)
             (sk-reads-changed? $pass (fold-semidet sk-premise-key-step () $premises)))
         (let* (($_folds (fold-semidet (sk-refresh-fold-step $pass) () $premises))
                ($new (sk-row-view $hash (copy_term $row))))
            (case $new (
               (sk-none ())
               ($_view
                  (if (sk-known-version? $new $versions) ()
                     (let $_stored (sk-store-view! $hash $key $rhash $new)
                        (let $_changed (add-atom &sk_changed (sk-changed $pass $hash)) ())))))))
         ())))

(: sk-run-passes! (-[semidet]-> Number (List SkeletonItem) Atom))
(= (sk-run-passes! $pass $items)
   (let $_pass (fold-semidet (sk-compute-step $pass) () $items)
      (if (< (+ $pass 1) 4)
         (if (not (== (collapse (once (match &sk_changed (sk-changed $pass $_hash) true))) ()))
            (sk-run-passes! (+ $pass 1) $items)
            ())
         ())))

(: sk-evaluate! (-[semidet]-> (List SkeletonKey) Atom))
(= (sk-evaluate! $keys)
   (let* (($_reach (collapse (match &sk_reach ($hash $key) (remove-atom &sk_reach ($hash $key)))))
          ($_order
             (collapse (match &sk_order (sk-row-item $seq $hash $key $rhash $row)
                (remove-atom &sk_order (sk-row-item $seq $hash $key $rhash $row)))))
          ($_changed (collapse (match &sk_changed (sk-changed $pass $hash) (remove-atom &sk_changed (sk-changed $pass $hash)))))
          ($_collect (fold-semidet sk-collect! () $keys)))
      (sk-run-passes! 0
         (sort-atom
            (collapse (match &sk_order (sk-row-item $seq $hash $key $rhash $row)
               (sk-row-item $seq $hash $key $rhash $row)))))))

;; --- Invalidation -----------------------------------------------------------

;; Every view that read a changed key is dropped, following use edges up to the
;; roots. Walking stops at keys this flush already visited.
(: sk-invalidate-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-invalidate-step $_acc $key)
   (let $hash (index-hash $key)
      (if (sk-invalidated? $hash $key) ()
         (let* (($_seen (add-atom &sk_dirty_seen ($hash $key)))
                ($_drop
                   (collapse (match &sk_view ($hash $stored $rhash $view)
                      (if (=alpha $stored $key)
                         (remove-atom &sk_view ($hash $stored $rhash $view))
                         (empty)))))
                ($parents
                   (collapse (match &sk_use ($hash $stored $parent)
                      (if (=alpha $stored $key) $parent (empty))))))
            (fold-semidet sk-invalidate-step () $parents)))))

(: sk-invalidated? (-[det]-> Number SkeletonKey Bool))
(= (sk-invalidated? $hash $key)
   (not (== (collapse (once (match &sk_dirty_seen ($hash $stored)
               (if (=alpha $stored $key) true (empty)))))
            ())))

(: sk-flush-dirty! (-[semidet]-> Atom))
(= (sk-flush-dirty!)
   (let $seeds
      (collapse (match &sk_dirty (sk-dirty $key)
         (let $_removed (remove-atom &sk_dirty (sk-dirty $key)) $key)))
      (if (== $seeds ()) ()
         (let* (($_walk (fold-semidet sk-invalidate-step () $seeds))
                ($_clear (collapse (match &sk_dirty_seen ($hash $key) (remove-atom &sk_dirty_seen ($hash $key))))))
            ()))))

;; --- Base-rate API ----------------------------------------------------------

;; A user base rate replaces whatever every fold over its pattern computed, so
;; all cached values are dropped.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv user any)))
          ($_values (collapse (match &sk_view ($hash $key $rhash $view) (remove-atom &sk_view ($hash $key $rhash $view))))))
      ()))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (let* (($_old (base-rate-cache-remove! $kbid $pattern))
          ($_values (collapse (match &sk_view ($hash $key $rhash $view) (remove-atom &sk_view ($hash $key $rhash $view))))))
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
            (let $change (chainer-first-or no-forward-change (collapse (once (upsert-materialized! $fact $ev))))
               (let $_applied (forward-apply-unqueued-change! $change) ()))
            ()))
      ($_other ()))))

;; --- Entry points -----------------------------------------------------------

(: sk-root-keys-step (-[semidet]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-root-keys-step $keys $goal)
   (case $goal (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled) (cons (sk-fold $args) $keys)
            (if (== $fun GroupedFoldAllCompiled)
               (fold-semidet sk-cons-step $keys (sk-answers $goal))
               $keys)))
      ($_fact (fold-semidet sk-cons-step $keys (sk-answers $goal))))))

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
      ((sk-val $fact $_ev $_deps) (cons (brand RuntimeResult $fact) $kept))
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

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $goals $materialize?)
   (let* (($_seen (collapse (match &sk_seen ($hash $node) (remove-atom &sk_seen ($hash $node)))))
          ($_fresh (collapse (match &sk_fresh (sk-fresh $node) (remove-atom &sk_fresh (sk-fresh $node)))))
          ($_budget (change-state! sk_budget $steps))
          ($_rows (change-state! sk_row_budget (* 10 $steps)))
          ($_activate (sk-activate-pending!))
          ($_parked (sk-park-deliveries!))
          ($_search (sk-search! 0 $goals ()))
          ($_before (sk-flush-dirty!))
          ($_evaluated (sk-evaluate! (fold-semidet sk-root-keys-step () $goals)))
          ($results (map-semidet (sk-root-results $materialize?) $goals))
          ($_temp (sk-clear-temp!))
          ($_after (sk-flush-dirty!)))
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
