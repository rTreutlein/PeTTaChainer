;; Evaluation over the skeleton and the public backward entry points.
;;
;; Every row keeps one current view: its conclusion computed by the rule's
;; formulas from its premises' current values, with the evidence behind it and
;; the set of keys it depends on. A key's value merges its leaf facts and the
;; views of its rows; overlapping evidence resolves by dominance, disjoint
;; evidence revises.
;;
;; A premise contributes only the views of its key that do not depend on the
;; row's own conclusion. Dependency sets are transitive, so no value supports
;; itself, through inverted rules or any longer cycle. Evaluation computes
;; each missing view once, in the order the rows were created. Views persist
;; in &sk_view until something below them changes.

(: SkeletonValue Type)
;; fact-or-fold-result evidence key-hashes-it-depends-on
(: sk-val (-[det]-> Atom Atom Atom SkeletonValue))
(: sk-none SkeletonValue)
(: SkeletonFilter Type)
(: sk-filter (-[det]-> Atom Atom SkeletonFilter))
(: SkeletonFoldResult Type)
;; the fold's CPU goal with its result, and the proof that replaces a `cpu` token
(: sk-fold-result (-[det]-> Atom Atom SkeletonFoldResult))
(: SkeletonFold Type)
(: sk-fold-state (-[det]-> Atom Atom Atom Atom SkeletonFold))
(: SkeletonRowState Type)
(: sk-acc (-[det]-> Atom Atom Atom SkeletonRowState))
(: sk-fail SkeletonRowState)
(: SkeletonVersion Type)
(: sk-version (-[det]-> Atom Atom SkeletonVersion))
(: SkeletonChanged Type)
(: sk-changed (-[det]-> Atom Atom SkeletonChanged))
(: SkeletonItem Type)
;; key-hash key row-hash row-body
(: sk-row-item (-[det]-> Atom Atom Atom Atom SkeletonItem))

;; Signatures of the mutually recursive functions below.
(: sk-collect! (-[semidet]-> %Undefined% Atom))
(: sk-collect-step (-[semidet]-> %Undefined% %Undefined% Atom))
(: sk-fold-view (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-group-view (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-store-view! (-[det]-> %Undefined% %Undefined% %Undefined% %Undefined% Atom))

(: sk-union (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-union $left $right) (list_to_set (fold-semidet sk-cons-step $right $left)))

;; --- Leaves -----------------------------------------------------------------

(: sk-key-leaves (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-key-leaves $key (sk-filter $proof $tv))
   (let* (((sk-key $type $kbctx) (copy_term $key))
          ($facts (sk-leaf-facts (assemble-stored-runtime-fact $type $kbctx $proof $tv))))
      (fold-semidet (sk-keep-leaf $key) () $facts)))

(: sk-keep-leaf (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-keep-leaf $key $kept $fact)
   (if (=alpha (sk-fact-key $fact) $key) (cons $fact $kept) $kept))

;; Hypothetical assumptions are not evidence.
(: leaf-evidence-for-result (-[det]-> %Undefined% (List Evidence)))
(= (leaf-evidence-for-result ($type $kb $proof $tv))
   (let $typed-proof (brand Proof $proof)
      (if (assumption-proof? $typed-proof) ()
         (forward-fact-evidence (brand Statement $type) (brand KBContext $kb)
            $typed-proof (the TV $tv)))))

(: sk-leaf-view (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-leaf-view $hash $fact)
   (sk-val $fact (leaf-evidence-for-result $fact) (cons $hash ())))

;; --- Values -----------------------------------------------------------------

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof, overlapping evidence keeps the view
;; whose evidence contains the other's or else the more confident one, and
;; disjoint evidence revises. A dominated view contributes neither evidence
;; nor dependencies.
(: sk-merge-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-merge-step $acc $view)
   (case $acc (
      (sk-none $view)
      ((sk-val $fact $ev $deps)
         (case $view (
            ((sk-val $other $other-ev $other-deps)
               (sk-merge-views $fact $ev $deps $other $other-ev $other-deps))))))))

(: sk-merge-views (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-merge-views $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* ((($_ta $_ca $proof-a $_tva) $a)
          (($_tb $_cb $proof-b $_tvb) $b))
      (if (== $a $b) (sk-val $a (sk-union $ev-a $ev-b) $deps-a)
         (if (projection-dominates? (brand Proof $proof-a) (brand Proof $proof-b)) (sk-val $a $ev-a $deps-a)
            (if (projection-dominates? (brand Proof $proof-b) (brand Proof $proof-a)) (sk-val $b $ev-b $deps-b)
               (if (sk-overlap? $ev-a $ev-b)
                  (if (sk-subset? $ev-a $ev-b) (sk-val $b $ev-b $deps-b)
                     (if (sk-subset? $ev-b $ev-a) (sk-val $a $ev-a $deps-a)
                        (if (>= (sk-confidence $a) (sk-confidence $b))
                           (sk-val $a $ev-a $deps-a)
                           (sk-val $b $ev-b $deps-b))))
                  (let $pooled (sk-union $ev-a $ev-b)
                     (if (>= (sk-confidence $a) (sk-confidence $b))
                        (sk-val (sk-revise $a $b) $pooled (sk-union $deps-a $deps-b))
                        (sk-val (sk-revise $b $a) $pooled (sk-union $deps-a $deps-b))))))))))

(: sk-confidence (-[det]-> %Undefined% Number))
(= (sk-confidence ($_type $_kbctx $proof $tv))
   (case $proof (
      ((marginal-proj $_idx $_base) (* 0.99 (tv-confidence $tv)))
      ($_other (tv-confidence $tv)))))

(: sk-revise (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-revise ($type $kbctx $proof-a $tv-a) ($_t $_c $proof-b $tv-b))
   (let* (($tv
             (case $tv-a (
                ((STV $m1 $c1)
                   (case $tv-b (
                      ((STV $m2 $c2)
                         (merge-stv-fields (the Number $m1) (the Number $c1) (the Number $m2) (the Number $c2)))
                      ($_other $tv-a))))
                ($_other $tv-a))))
          ($proof (merge/revision $proof-a $proof-b)))
      (assemble-stored-runtime-fact $type $kbctx $proof $tv)))

(: sk-overlap? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-overlap? () $_other) false)
(= (sk-overlap? (cons $entry $rest) $other)
   (if (stored-list-member? $entry $other) true (sk-overlap? $rest $other)))

(: sk-subset? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-subset? () $_other) true)
(= (sk-subset? (cons $entry $rest) $other)
   (if (stored-list-member? $entry $other) (sk-subset? $rest $other) false))

;; Premises may share rules but not facts.
(: sk-fact-overlap? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-fact-overlap? () $_other) false)
(= (sk-fact-overlap? (cons $entry $rest) $other)
   (case $entry (
      ((rule-ev $_kb $_name) (sk-fact-overlap? $rest $other))
      ($_fact (if (stored-list-member? $entry $other) true (sk-fact-overlap? $rest $other))))))

;; Each row keeps the versions of its view in the order they were computed.
;; A consumer takes, per row, the latest version that does not depend on the
;; excluded key and matches the requested proof and truth-value pattern; an
;; older version stays usable when a newer one came to depend on that key.
(: sk-admit-step (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-admit-step $exclude $filter $kept (sk-version $rhash $view))
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (stored-list-member? $exclude $deps) $kept
            (if (sk-view-matches? $filter $fact) (sk-put-version $rhash $view $kept) $kept)))
      ($_none $kept))))

;; Versions arrive oldest first, so a later one replaces an earlier one of the
;; same row in place.
(: sk-put-version (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-put-version $rhash $view ()) (cons (sk-version $rhash $view) ()))
(= (sk-put-version $rhash $view (cons (sk-version $other $old) $rest))
   (if (== $rhash $other) (cons (sk-version $rhash $view) $rest)
      (cons (sk-version $other $old) (sk-put-version $rhash $view $rest))))

(: sk-version-view (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-version-view $views (sk-version $_rhash $view)) (cons $view $views))

(: sk-fact-matches? (-[semidet]-> %Undefined% %Undefined% Bool))
(= (sk-fact-matches? $filter $fact)
   (case $fact (
      (($_type $_kbctx $proof $tv)
         (let* (((sk-filter $want-proof $want-tv) (copy_term $filter))
                (($_t $_c $got-proof $got-tv) (copy_term $fact)))
            (= (quote ($got-proof $got-tv)) (quote ($want-proof $want-tv))))))))

(: sk-view-matches? (-[semidet]-> %Undefined% %Undefined% Bool))
(= (sk-view-matches? $filter $fact)
   (case $fact (
      ((sk-fold-result $_goal $_proof) true)
      ($_any-fact
         (let* (((sk-filter $want-proof $want-tv) $filter))
            (if (is-var $want-proof)
               (if (is-var $want-tv) true (sk-fact-matches? $filter $fact))
               (sk-fact-matches? $filter $fact)))))))

(: sk-stored-views (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-stored-views $hash $key)
   (collapse (match &sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) (sk-version $rhash $view) (empty)))))

;; A fold or group gets its view when first read, from its members' views at
;; that point; it is kept until one of them changes.
(: sk-fold-views (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-fold-views $hash $key)
   (case $key (
      ((sk-fold $args) (sk-keep-view $hash $key (sk-fold-view $hash $key $args)))
      ((sk-group $args) (sk-keep-view $hash $key (sk-group-view $hash $key $args)))
      ($_fact ()))))

(: sk-keep-view (-[det]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-keep-view $hash $key $view)
   (let $_stored (sk-store-view! $hash $key 0 $view) (cons (sk-version 0 $view) ())))

;; The merged value of a key on behalf of a consumer: leaves first, then the
;; row views in the order the rows were found.
(: sk-value (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-value $key $filter $exclude)
   (let* (($hash (index-hash $key))
          ($leaves
             (case $key (
                ((sk-key $_type $_kbctx)
                   (map-semidet (sk-leaf-view $hash) (sk-key-leaves $key $filter)))
                ($_fold ()))))
          ($stored (sk-stored-views $hash $key))
          ($views (if (== $stored ()) (sk-fold-views $hash $key) $stored))
          ($admitted
             (fold-semidet sk-cons-step ()
                (fold-semidet sk-version-view ()
                   (fold-semidet (sk-admit-step $exclude $filter) () $views)))))
      (fold-semidet sk-merge-step (fold-semidet sk-merge-step sk-none $leaves) $admitted)))

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

;; --- Token replacement ------------------------------------------------------

;; A compiled query adapter proves (_ inner) with an open head; its proof is
;; the inner proof.
(: sk-unwrap-proof (-[det]-> %Undefined% Atom))
(= (sk-unwrap-proof $proof)
   (if (is-expr $proof)
      (if (== $proof ()) $proof
         (if (is-var (car-atom $proof))
            (let $tail (cdr-atom $proof)
               (if (== $tail ()) $proof
                  (if (== (cdr-atom $tail) ()) (car-atom $tail) $proof)))
            $proof))
      $proof))

;; A rule proof marks each fold premise with a `cpu` token; the tokens are
;; replaced, in premise order, by the folds' proofs.
(: TokenReplacement Type)
(: token-state (-[det]-> Atom Atom TokenReplacement))
(: replace-token (-[det]-> %Undefined% %Undefined% TokenReplacement))
(: replace-token-list (-[det]-> %Undefined% %Undefined% TokenReplacement))
(= (replace-token-list () $proofs) (token-state () $proofs))
(= (replace-token-list (cons $head $tail) $proofs)
   (let* (((token-state $new-head $proofs1) (replace-token $head $proofs))
          ((token-state $new-tail $proofs2) (replace-token-list $tail $proofs1)))
      (token-state (cons $new-head $new-tail) $proofs2)))
(= (replace-token $term $proofs)
   (if (is-var $term) (token-state $term $proofs)
      (if (== $term cpu)
         (if (= $proofs (cons $proof $rest)) (token-state $proof $rest) (token-state cpu ()))
         (if (is-expr $term)
            (let* (((token-state $new-list $rest-proofs)
                      (replace-token-list $term $proofs)))
               (token-state $new-list $rest-proofs))
            (token-state $term $proofs)))))

;; --- Accumulation -----------------------------------------------------------

(: ScalarFoldSpec
   (Alias (KB Statement (| ExtractValue ExtractInheritanceTV ExtractTV) $a
             (-[semidet]-> $b $c $b) AggregateFinish AggregateTVMode)))
(: GroupedFoldSpec
   (Alias (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b
             (-[semidet]-> $c $d $c) AggregateFinish AggregateTVMode)))

(: sk-accumulate-grouped (-[semidet]-> GroupedFoldSpec %Undefined% %Undefined% Atom))
(= (sk-accumulate-grouped $spec $acc $fact)
   (let* ((($_kb $_pattern $_group $extractor $_init $fun $_finish $_mode) $spec)
          (($_type $_kbctx $_proof $tv) $fact))
      (ba-step-acc $extractor $fun $acc $fact $tv)))

(: sk-accumulate-scalar (-[semidet]-> ScalarFoldSpec %Undefined% %Undefined% Atom))
(= (sk-accumulate-scalar $spec $acc $fact)
   (let* ((($_kb $_pattern $extractor $_init $fun $_finish $_mode) $spec)
          (($_type $_kbctx $_proof $tv) $fact))
      (ba-step-acc $extractor $fun $acc $fact $tv)))

(: sk-accumulate (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-accumulate $args $acc $fact)
   (case $args (
      (($_kbctx $_pattern $_group $_extractor $_init $_fun $_finish $_mode)
         (sk-accumulate-grouped (the GroupedFoldSpec (copy_term $args)) $acc $fact))
      ($_scalar
         (sk-accumulate-scalar (the ScalarFoldSpec (copy_term $args)) $acc $fact)))))

(: ba-step-acc (-[semidet]-> $x (-[semidet]-> $a Atom $a) $a %Undefined% %Undefined% $a))
(= (ba-step-acc $extractor $fun $acc $fact $tv)
   (case $extractor (
      ((extract-value $pattern $value)
         (let* ((($pattern ($_kb $_ctx $_vars) $_proof $_tv) (copy_term $fact)))
            ($fun $acc $value)))
      ((extract-inheritance-tv $kbid $_statement)
         (let* ((((Inheritance $subject $_concept) ($_kb $_ctx $_vars) $_proof $_tv) (copy_term $fact)))
            ($fun $acc (WeightedTv (inheritance-subject-prior-tv (brand KB $kbid) (brand Statement $subject)) $tv))))
      (extract-tv ($fun $acc $tv)))))

;; Folds that finish as base rates carry no evidence of their own; the others
;; carry their members' evidence.

(: sk-fold-evidence (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-fold-evidence $finish $ev)
   (if (base-rate-finish? $finish) ()
      (if (== $finish uniform-prior) ()
         (if (== $finish uniform-prior-known) () $ev))))

;; A fold with members proves by its members, in the order they were found.
(: sk-fold-proof (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-fold-proof $args $proofs)
   (if (== $proofs ()) cpu
      (cons
         (if (== (sk-fold-function-name $args) OrFormula) disjunction foldall-proof)
         (fold-semidet sk-cons-step () $proofs))))

(: sk-fold-function-name (-[det]-> %Undefined% Atom))
(= (sk-fold-function-name $args)
   (case $args (
      (($_kbctx $_pattern $_group $_extractor $_init $fun $_finish $_mode) $fun)
      (($_kbid $_pattern $_extractor $_init $fun $_finish $_mode) $fun))))

(: sk-group-node (-[det]-> %Undefined% Atom))
(= (sk-group-node $key)
   (let $hash (index-hash $key)
      (collapse (once (match &sk_group_of ($hash $stored $node)
         (if (=alpha $stored $key) $node (empty)))))))

(: sk-keep-group-member (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-keep-group-member $args $kept $key)
   (if (sk-group-member? $args $key) (cons $key $kept) $kept))

(: sk-group-member? (-[semidet]-> %Undefined% %Undefined% Bool))
(= (sk-group-member? $args $key)
   (let* ((($kbctx $pattern $_group $_e $_i $_f $_fi $_m) (copy_term $args))) (= (sk-key $pattern $kbctx) (copy_term $key))))

;; --- Row views --------------------------------------------------------------

;; Each premise reads its key's value without the views that depend on the
;; row's conclusion. The state carries the fold proofs newest first.
(: sk-row-view (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-row-view $khash ($_ident $concl $premises $_seq))
   (let* ((($type $kbctx $proof $tv) $concl)
          ($shared (shared-evidence-frontier-proof? (brand Proof $proof)))
          ($state (fold-semidet (sk-premise-step $khash $shared) (sk-acc () () ()) $premises)))
      (case $state (
         ((sk-acc $fold-proofs $ev $deps)
            (let* (((token-state $full-proof $_unused)
                      (replace-token $proof (fold-semidet sk-cons-step () $fold-proofs)))
                   ($final-proof (sk-unwrap-proof $full-proof))
                   ($fact (assemble-stored-runtime-fact $type $kbctx $final-proof $tv)))
               (sk-val $fact (rule-result-evidence $fact (the (List Evidence) $ev)) (cons $khash $deps))))
         (sk-fail sk-none)))))

(: sk-premise-step (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-premise-step $exclude $shared $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-acc $fold-proofs $ev $deps)
         (case $premise (
            ((CPU $fun $args $res)
               (if (== $fun FoldAllCompiled)
                  (sk-consume-fold $state $res (sk-value (sk-fold $args) (sk-filter () ()) $exclude))
                  (if (== $fun GroupedFoldAllCompiled)
                     (sk-consume-fold $state $res (sk-value (sk-group $args) (sk-filter () ()) $exclude))
                     (case (collapse (once (cpu-call 0 $fun $args))) (
                        (() sk-fail)
                        ((cons $result $_rest) (if (= $res $result) $state sk-fail)))))))
            (($type $kbctx $proof $tv)
               (case (sk-value (sk-key $type $kbctx) (sk-filter $proof $tv) $exclude) (
                  (sk-none sk-fail)
                  ((sk-val $fact $premise-ev $premise-deps)
                     (if (if $shared false
                            (sk-fact-overlap? $ev $premise-ev))
                        sk-fail
                        (if (= $premise $fact)
                           (sk-acc $fold-proofs (sk-union $ev $premise-ev) (sk-union $deps $premise-deps))
                           sk-fail))))))))))))

(: sk-consume-fold (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-consume-fold (sk-acc $fold-proofs $ev $deps) $res $value)
   (case $value (
      (sk-none sk-fail)
      ((sk-val (sk-fold-result (CPU $_fun $_args $result) $proof) $fold-ev $fold-deps)
         (if (= $res $result)
            (sk-acc (cons $proof $fold-proofs) (sk-union $ev $fold-ev) (sk-union $deps $fold-deps))
            sk-fail)))))

;; --- Fold views -------------------------------------------------------------

(: sk-fold-node-member (-[det]-> %Undefined% Atom))
(= (sk-fold-node-member $node)
   (let $hash (sk-node-hash $node)
      (collapse (once (match &sk_fold ($hash $stored $member)
         (if (=alpha $stored $node) $member (empty)))))))

;; Members are read without the views that depend on the fold itself: a
;; member derived through this fold's own output is left out of it.
(: sk-fold-step (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-fold-step $args $filter $exclude $state $key)
   (let* (((sk-fold-state $acc $proofs $ev $deps) $state))
      (case (sk-value $key $filter $exclude) (
         (sk-none $state)
         ((sk-val $fact $member-ev $member-deps)
            (let* ((($_type $_kbctx $proof $_tv) $fact))
               (sk-fold-state (sk-accumulate $args $acc $fact) (cons $proof $proofs)
                  (sk-union $ev $member-ev) (sk-union $deps $member-deps))))))))

(: sk-fold-over (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-fold-over $args $init $finish $members $member-filter $exclude)
   (let* (((sk-fold-state $acc $proofs $ev $deps)
             (fold-semidet (sk-fold-step $args $member-filter $exclude)
                (sk-fold-state $init () () ()) $members)))
      (sk-fold-state (finish-aggregate $finish $acc) (sk-fold-proof $args $proofs)
         (sk-fold-evidence $finish $ev) $deps)))

(: sk-member-filter (-[det]-> %Undefined% Atom))
(= (sk-member-filter $member)
   (case (copy_term $member) (
      (($_type $_kbctx $proof $tv) (sk-filter $proof $tv))
      ($_cpu (sk-filter () ())))))

(: sk-fold-val (-[det]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-fold-val $hash $args $value $proof $ev $deps)
   (sk-val (sk-fold-result (CPU FoldAllCompiled $args $value) $proof) $ev (cons $hash $deps)))

;; A user base rate is authoritative. An unexpanded fold falls back to a cached
;; estimate when one exists. A computed base rate is cached for reuse.
(= (sk-fold-view $hash $key $args)
   (let* ((($_kbid $_pattern $_extractor $init $_fun $finish $_mode) $args))
      (case (base-rate-aggregate-key $args) (
         ((base-rate-aggregate-key-value $br-kb $br-pattern $br-mode)
            (let* (($entries (base-rate-cache-entries-for-mode $br-kb $br-pattern $br-mode)))
               (if (base-rate-cache-user-present? $entries)
                  (sk-fold-val $hash $args (base-rate-entry-tv (the BaseRateEntry (car-atom $entries))) cpu () ())
                  (let* (($value (sk-computed-fold-view $hash $args $init $finish $entries))
                         ($_store
                            (case $value (
                               ((sk-val (sk-fold-result (CPU $_f $_a $tv) $_p) $_ev $_deps)
                                  (store-produced-base-rate! $br-kb $br-pattern (the TV $tv) computed $br-mode))
                               ($_other ())))))
                     $value))))
         (no-base-rate-aggregate-key
            (sk-computed-fold-view $hash $args $init $finish ()))))))

(: sk-computed-fold-view (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(= (sk-computed-fold-view $hash $args $init $finish $entries)
   (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
      (()
         (case $entries (
            ((cons $entry $_rest)
               (sk-fold-val $hash $args (base-rate-entry-tv (the BaseRateEntry $entry)) cpu () ()))
            (() (sk-fold-val $hash $args (finish-aggregate $finish $init) cpu () ())))))
      ((cons $member $_rest)
         (let* (((sk-fold-state $value $proof $ev $deps)
                   (sk-fold-over $args $init $finish (sk-answers $member) (sk-member-filter $member) $hash)))
            ;; A base rate is an estimate about the population, like a prior:
            ;; it carries no evidence and ties its readers to none of its
            ;; members.
            (sk-fold-val $hash $args $value $proof $ev
               (if (base-rate-finish? $finish) () $deps)))))))

(= (sk-group-view $hash $key $args)
   (let* ((($_kbctx $_pattern $_group $_extractor $init $_fun $finish $_mode) $args))
      (case (sk-group-members $key $args) (
         ((sk-group-found $member $members)
            (let* (((sk-fold-state $value $proof $ev $deps)
                      (sk-fold-over $args $init $finish $members (sk-member-filter $member) $hash)))
               (sk-val (sk-fold-result (CPU GroupedFoldAllCompiled $args $value) $proof)
                  $ev (cons $hash $deps))))
         ($_missing sk-none)))))

(: SkeletonGroup Type)
(: sk-group-found (-[det]-> Atom Atom SkeletonGroup))
(: sk-group-missing SkeletonGroup)

;; The group's member node and the member keys belonging to this group.
(: sk-group-members (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-group-members $key $args)
   (case (sk-group-node $key) (
      (() sk-group-missing)
      ((cons $node $_rest)
         (case (sk-fold-node-member $node) (
            (() sk-group-missing)
            ((cons $member $_more)
               (sk-group-found $member
                  (fold-semidet sk-cons-step ()
                     (fold-semidet (sk-keep-group-member $args) () (sk-answers $member)))))))))))

;; --- Evaluation order ---------------------------------------------------------

;; The rows the roots can reach are listed with their creation numbers.
(= (sk-collect! $key)
   (let $hash (index-hash $key)
      (if (sk-reached? $hash $key) ()
         (let* (($_mark (add-space-atom! &sk_reach (make-space-pair $hash $key))))
            (fold-semidet sk-collect-row () (sk-key-rows $hash $key))))))

(: sk-reached? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-reached? $hash $key)
   (not (== (collapse (once (match &sk_reach ($hash $stored)
               (if (=alpha $stored $key) true (empty)))))
            ())))

(: sk-collect-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-collect-step $_acc $key) (sk-collect! $key))

(: sk-collect-row (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-collect-row $_acc $item)
   (let* (((sk-row-item $_hash $_key $_rhash ($_ident $_concl $premises $seq)) $item)
          ($_listed (add-space-atom! &sk_order (make-space-pair $seq $item))))
      (fold-semidet sk-collect-step () (sk-read-keys $premises))))

;; The rows concluding a key, as items, in creation order. A fold or group key
;; has none: it is computed from its members when first read.
(: sk-key-rows (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-key-rows $hash $key)
   (collapse (match &sk_row ($hash $stored $rhash $body)
      (if (=alpha $stored $key) (sk-row-item $hash $stored $rhash $body) (empty)))))

;; The keys a row reads: its fact premises and folds, and for a fold the keys
;; of its members.
(: sk-read-keys (-[semidet]-> %Undefined% Atom))
(= (sk-read-keys $premises)
   (fold-semidet sk-cons-step () (fold-semidet sk-premise-key-step () $premises)))

(: sk-premise-key-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-premise-key-step $keys $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled)
            (fold-semidet sk-cons-step (cons (sk-fold $args) $keys)
               (sk-fold-member-keys (CPU FoldAllCompiled $args $_result)))
            (if (== $fun GroupedFoldAllCompiled)
               (case (sk-group-members (sk-group $args) $args) (
                  ((sk-group-found $_member $members)
                     (fold-semidet sk-cons-step (cons (sk-group $args) $keys) $members))
                  ($_missing (cons (sk-group $args) $keys))))
               $keys)))
      (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $keys)))))

(: sk-fold-member-keys (-[semidet]-> %Undefined% Atom))
(= (sk-fold-member-keys $node)
   (case (sk-fold-node-member $node) (
      (() ())
      ((cons $member $_rest) (sk-answers $member)))))

;; A fold read in a pass after one of its members changed is recomputed.
(: sk-refresh-fold-step (-[semidet]-> Number %Undefined% %Undefined% Atom))
(= (sk-refresh-fold-step $pass $_acc $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled)
            (sk-refresh-fold! $pass (sk-fold $args)
               (sk-fold-member-keys (CPU FoldAllCompiled $args $_result)))
            (if (== $fun GroupedFoldAllCompiled)
               (case (sk-group-members (sk-group $args) $args) (
                  ((sk-group-found $_member $members) (sk-refresh-fold! $pass (sk-group $args) $members))
                  ($_missing ())))
               ())))
      ($_fact ()))))

(: sk-refresh-fold! (-[semidet]-> Number %Undefined% %Undefined% Atom))
(= (sk-refresh-fold! $pass $key $members)
   (if (sk-reads-changed? $pass (fold-semidet sk-hash-step () $members))
      (let* (($hash (index-hash $key))
             ($_dropped
                (collapse (match &sk_view ($hash $stored 0 $view)
                   (if (=alpha $stored $key)
                      (let $row (make-space-row4 $hash $stored 0 $view) (remove-atom &sk_view $row))
                      (empty))))))
         ())
      ()))

;; Views are computed in the order rows were created, so a first pass reads
;; only what was derived earlier, as a proof is built from proofs that already
;; exist. Support found later reaches earlier readers in further passes: a row
;; is recomputed when a key it reads changed in this pass or the previous one.
;; Every pass keeps the dependency check, and passes stop when nothing changes.
(: sk-compute-step (-[semidet]-> Number %Undefined% %Undefined% Atom))
(= (sk-compute-step $pass $_acc ($_seq (sk-row-item $hash $key $rhash $body)))
   (let* ((($_ident $_concl $premises $_s) $body)
          ($versions (sk-row-versions $hash $key $rhash)))
      (if (if (== $versions ()) (== $pass 0) (sk-reads-changed? $pass (sk-read-hashes $premises)))
         (let* (($_folds (fold-semidet (sk-refresh-fold-step $pass) () $premises))
                ($new (sk-row-view $hash (copy_term $body))))
            (case $new (
               (sk-none ())
               ($_view
                  (if (sk-known-version? $new $versions) ()
                     (let $_stored (sk-store-view! $hash $key $rhash $new)
                        (sk-note-change! $pass $hash)))))))
         ())))

(: sk-row-versions (-[det]-> %Undefined% %Undefined% %Undefined% Atom))
(= (sk-row-versions $hash $key $rhash)
   (collapse (match &sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) $view (empty)))))

(: sk-known-version? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-known-version? $_view ()) false)
(= (sk-known-version? $view (cons $version $rest))
   (if (=alpha $view $version) true (sk-known-version? $view $rest)))

(: sk-read-hashes (-[semidet]-> %Undefined% Atom))
(= (sk-read-hashes $premises) (fold-semidet sk-hash-step () (sk-read-keys $premises)))

(: sk-hash-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-hash-step $hashes $key) (cons (index-hash $key) $hashes))

(: sk-note-change! (-[det]-> Number %Undefined% Atom))
(= (sk-note-change! $pass $hash) (let $_row (add-atom &sk_changed (sk-changed $pass $hash)) ()))

(: sk-reads-changed? (-[det]-> Number %Undefined% Bool))
(= (sk-reads-changed? $_pass ()) false)
(= (sk-reads-changed? $pass (cons $hash $rest))
   (let $previous (- $pass 1)
      (if (space-row-present? &sk_changed (sk-changed $pass $hash)) true
         (if (space-row-present? &sk_changed (sk-changed $previous $hash)) true
            (sk-reads-changed? $pass $rest)))))

(: sk-run-passes! (-[semidet]-> Number %Undefined% Atom))
(= (sk-run-passes! $pass $rows)
   (let* (($_pass (fold-semidet (sk-compute-step $pass) () $rows))
          ($next (+ $pass 1)))
      (if (< $next 4)
         (if (space-row-present? &sk_changed (sk-changed $pass $_hash))
            (sk-run-passes! $next $rows)
            ())
         ())))

(= (sk-store-view! $hash $key $rhash $view)
   (let $_view (add-space-atom! &sk_view (make-space-row4 $hash $key $rhash $view)) ()))

(: sk-evaluate! (-[semidet]-> %Undefined% Atom))
(= (sk-evaluate! $keys)
   (let* (($_reach (remove-all-atoms &sk_reach))
          ($_order (remove-all-atoms &sk_order))
          ($_changed (remove-all-atoms &sk_changed))
          ($_collect (fold-semidet sk-collect-step () $keys)))
      (sk-run-passes! 0 (sort-atom (collapse (match &sk_order $entry $entry))))))

;; --- Invalidation -----------------------------------------------------------

;; Every view that read a changed key is dropped, following use edges up to the
;; roots. Walking stops at keys this flush already visited.
(: sk-flush-dirty! (-[semidet]-> Atom))
(= (sk-flush-dirty!)
   (let $seeds
      (collapse (match &sk_dirty (sk-dirty $key)
         (let $_removed (remove-atom &sk_dirty (sk-dirty $key)) $key)))
      (if (== $seeds ()) ()
         (let* (($_walk (fold-semidet sk-invalidate-step () $seeds))
                ($_clear (remove-all-atoms &sk_dirty_seen)))
            ()))))

(: sk-invalidate-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-invalidate-step $_acc $key)
   (let $hash (index-hash $key)
      (if (space-row-present? &sk_dirty_seen ($hash $key)) ()
         (let* (($_seen (add-space-atom! &sk_dirty_seen (make-space-pair $hash $key)))
                ($_drop
                   (collapse (match &sk_view ($hash $stored $rhash $view)
                      (if (=alpha $stored $key)
                         (let $row (make-space-row4 $hash $stored $rhash $view)
                            (remove-atom &sk_view $row))
                         (empty)))))
                ($parents
                   (collapse (match &sk_use ($hash $stored $parent)
                      (if (=alpha $stored $key) $parent (empty))))))
            (fold-semidet sk-invalidate-step () $parents)))))

;; --- Base-rate API ----------------------------------------------------------

;; A user base rate replaces whatever every fold over its pattern computed, so
;; all cached values are dropped.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache (base-rate $kbid $stored $tv user any)))
          ($_values (remove-all-atoms &sk_view)))
      ()))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (let* (($_old (base-rate-cache-remove! $kbid $pattern))
          ($_values (remove-all-atoms &sk_view)))
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
(: upsert-materialized! (-[nondet]-> (Statement KBContext Proof TV) (List Evidence) ForwardOutputChange))
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

(: materializable-result? (-[det]-> %Undefined% Bool))
(= (materializable-result? $result)
   (case $result (
      (($type ($_kbid MAIN Nil) $_prf $tv)
         (if (== (extract-vars $type) ())
            (case $tv (
               ((STV $_s $_c) (== (extract-vars $tv) ()))
               ($_other false)))
            false))
      ($_other false))))

(: sk-materialize! (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-materialize! $_acc (sk-val $fact $ev $_deps $_cuts))
   (if (materializable-result? $fact)
      (let $changes (collapse (once (upsert-materialized! (the (Statement KBContext Proof TV) $fact) (the (List Evidence) $ev))))
         (progn
            (forward-apply-unqueued-change!
               (if (== $changes ()) no-forward-change (car-atom $changes)))
            ()))
      ()))

;; --- Entry points -----------------------------------------------------------

(: sk-root-keys-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-root-keys-step $keys $goal)
   (case $goal (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled) (cons (sk-fold $args) $keys)
            (if (== $fun GroupedFoldAllCompiled)
               (fold-semidet sk-cons-step $keys (sk-answers $goal))
               $keys)))
      ($_fact (fold-semidet sk-cons-step $keys (sk-answers $goal))))))

(: sk-root-values (-[semidet]-> %Undefined% Atom))
(= (sk-root-values $goal)
   (case $goal (
      ((CPU $fun $args $res)
         (if (== $fun FoldAllCompiled)
            (cons (sk-value (sk-fold $args) (sk-filter () ()) -1) ())
            (if (== $fun GroupedFoldAllCompiled)
               (map-semidet sk-root-group-value (sk-answers $goal))
               (collapse (let $result (cpu-call 0 $fun $args)
                  (if (= $res $result) (sk-val (CPU $fun $args $result) () ()) (empty)))))))
      (($_type $_kbctx $proof $tv)
         (map-semidet (sk-root-fact-value (sk-filter $proof $tv)) (sk-answers $goal))))))

(: sk-root-group-value (-[semidet]-> %Undefined% Atom))
(= (sk-root-group-value $key) (sk-value $key (sk-filter () ()) -1))

(: sk-root-fact-value (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-root-fact-value $filter $key) (sk-value $key $filter -1))

;; Proven values in root order; a fold root answers with its goal.
(: sk-result-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-result-step $kept $value)
   (case $value (
      ((sk-val (sk-fold-result $goal $_proof) $_ev $_deps) (cons $goal $kept))
      ((sk-val $fact $_ev $_deps) (cons $fact $kept))
      ($_none $kept))))

(: sk-proven-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-proven-step $kept $value)
   (case $value (
      ((sk-val $_fact $_ev $_deps) (cons $value $kept))
      ($_none $kept))))

(: sk-materialize! (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-materialize! $_acc (sk-val $fact $ev $_deps))
   (if (materializable-result? $fact)
      (let $changes
         (collapse (once (upsert-materialized! (the (Statement KBContext Proof TV) $fact)
            (the (List Evidence) $ev))))
         (progn
            (forward-apply-unqueued-change!
               (if (== $changes ()) no-forward-change (car-atom $changes)))
            ()))
      ()))

(: sk-root-results (-[semidet]-> Bool %Undefined% Atom))
(= (sk-root-results $materialize? $goal)
   (let* (($values (fold-semidet sk-cons-step () (fold-semidet sk-proven-step () (sk-root-values $goal))))
          ($_materialized
             (if $materialize?
                (case $values (
                   (() ())
                   ((cons $first $_rest) (sk-materialize! () $first))))
                ())))
      (fold-semidet sk-cons-step () (fold-semidet sk-result-step () $values))))

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $goals $materialize?)
   (let* (($_seen (remove-all-atoms &sk_seen))
          ($_fresh (remove-all-atoms &sk_fresh))
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
      (the (List (List RuntimeResult)) $results)))

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
