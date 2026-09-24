;; Evaluation over the skeleton and the public backward entry points.
;;
;; Every row keeps the versions of its view: its conclusion computed by the
;; rule's formulas from its premises' values, with the evidence behind it and
;; the hashes of the keys it depends on. A key's value merges its leaf facts
;; and one version per row; overlapping evidence resolves by dominance,
;; disjoint evidence revises, and proofs sharing only fact premises pool by
;; lifting.
;;
;; A premise reads, per row of its key, the latest version that depends
;; neither on the reading row's own conclusion key nor on a key unifying with
;; it. Dependency sets are transitive, so no value supports itself, through
;; inverted rules, longer cycles, or a more general or more specific key.
;; Views are computed in the order rows were created and refreshed while
;; support grows; they persist until something below them changes.

;; A conjunction part: an independent premise, or the projections of one
;; stored (And ...) source pooled back together: source proof, source truth
;; value, source arity, projected indices, the first projection's truth value.
(: SkeletonPart Type)
(: sk-indep-part (-[det]-> TV SkeletonPart))
(: sk-pool-part (-[det]-> Proof TV Number (List Atom) TV SkeletonPart))
(: SkeletonSource Type)
(: sk-source (-[det]-> Statement TV SkeletonSource))
(: SkeletonRowState Type)
;; fold proofs (newest first), evidence, dependency hashes, conjunction parts
(: sk-acc (-[det]-> (List Proof) (List Evidence) (List Number) (List SkeletonPart) SkeletonRowState))
(: sk-fail SkeletonRowState)
;; a premise had values, all overlapping the evidence the row already used
(: sk-clash SkeletonRowState)
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
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue))

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

;; The last rule application of a proof, with its premise proofs still
;; references.
(: sk-step-proof (-[det]-> Proof Proof))
(= (sk-step-proof $proof)
   (case $proof (
      ((proof-ref $pid)
         (case (collapse (once (match &proof ($pid $stored $_ev $_negated) $stored))) (
            ((cons $stored $_rest) $stored)
            (() $proof))))
      ($_leaf $proof))))

(: sk-fact-step-proof (-[det]-> SkFact Proof))
(= (sk-fact-step-proof ($_type $_kbctx $proof $_tv)) (sk-step-proof $proof))

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof, overlapping evidence keeps the view
;; whose evidence strictly contains the other's or else the more confident one, and
;; disjoint evidence revises. A dominated view contributes neither evidence
;; nor dependencies.
(: sk-merge-facts
   (-[det]-> SkFact (List Evidence) (List Number) SkFact (List Evidence) (List Number)
       SkeletonValue))
(= (sk-merge-facts $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-fact-step-proof $a))
          ($proof-b (sk-fact-step-proof $b)))
      (if (== $a $b) (sk-val $a (sk-union $ev-a $ev-b) $deps-a)
         (if (projection-dominates? $proof-a $proof-b) (sk-val $a $ev-a $deps-a)
            (if (projection-dominates? $proof-b $proof-a) (sk-val $b $ev-b $deps-b)
               (if (evidence-sets-overlap? $ev-a $ev-b)
                  (let* (($a-in-b (evidence-subset? $ev-a $ev-b))
                         ($b-in-a (evidence-subset? $ev-b $ev-a)))
                     (if (if $a-in-b (if $b-in-a false true) false) (sk-val $b $ev-b $deps-b)
                        (if (if $b-in-a (if $a-in-b false true) false) (sk-val $a $ev-a $deps-a)
                           (if (>= (term-confidence $a) (term-confidence $b))
                              (sk-val $a $ev-a $deps-a)
                              (sk-val $b $ev-b $deps-b)))))
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

;; --- Lifting merge ------------------------------------------------------------
;; Proofs of one statement that share fact premises but are otherwise
;; independent pool by factoring the shared facts out: each proof's residual
;; implication is read off by evaluating it with the shared facts true and
;; false, the residuals revise, and the conjunction of the shared facts applies
;; once. Every proof of the key must be modus ponens over conjunctions of facts,
;; with nonempty, pairwise disjoint residual evidence and a strength linear in
;; the shared conjunction (a two-point round trip); otherwise the views merge
;; pairwise.

;; The evidence entry of a fact leaf.
(: sk-lift-fact-step (-[det]-> Proof (List Evidence) Evidence (List Evidence)))
(= (sk-lift-fact-step $proof $found $entry)
   (case $entry (
      ((fact-ev $_kbctx $fact-proof $_type) (if (== $fact-proof $proof) (cons $entry $found) $found))
      ($_rule $found))))

(: sk-lift-facts (-[det]-> Proof (List Evidence) (List Evidence)))
(= (sk-lift-facts $proof $ev) (fold-flat (sk-lift-fact-step $proof) () $ev))

(: sk-lift-fact-tv (-[semidet]-> Evidence STVType))
(= (sk-lift-fact-tv (fact-ev $kbctx $proof $type))
   (case (collapse (once (match &kb ($type $kbctx $proof $tv) $tv))) (
      ((cons (STV $s $c) $_rest) (STV $s $c)))))

(: sk-lift-and-step (-[semidet]-> STVType STVType STVType))
(= (sk-lift-and-step $acc $tv) (AndFormula $acc $tv))

;; The rule's CTV, when its conclusion is modus ponens over a conjunction.
(: sk-lift-formula-step (-[semidet]-> (List CTVType) Atom (List CTVType)))
(= (sk-lift-formula-step $found $premise)
   (case $premise (
      ((CPU AndFormula $_and-args $_and-out) $found)
      ((CPU CTVModusPonensFormula ($_premise-tv $ctv) $_mp-out)
         (if (is-var $ctv) (empty)
            (case $ctv (((CTV $pos $neg) (cons (CTV $pos $neg) $found))))))
      ((CPU $_formula $_formula-args $_formula-out) (empty))
      ($_goal $found))))

(: sk-lift-rule-ctv (-[semidet]-> KB Atom CTVType))
(= (sk-lift-rule-ctv $kb $rule)
   (case (collapse (once (match rule_name_index ($rule $id)
            (match rules (runtime-rule-row $id ($_type ($kb $_ctx $_vars) (by $rule $_premise) $_tv) $premises)
               (fold-semidet sk-lift-formula-step () $premises))))) (
      ((cons (cons $ctv ()) $_rest) $ctv))))

;; A proof's strength with the shared facts replaced by the probe.
(: sk-lift-eval (-[semidet]-> KB (List Evidence) (List Evidence) STVType Atom STVType))
(= (sk-lift-eval $kb $ev $shared $probe $proof)
   (let* (($step (sk-step-proof (brand Proof $proof)))
          ($facts (sk-lift-facts $step $ev)))
      (case $facts (
         ((cons $fact $_rest)
            (if (evidence-member? $fact $shared) $probe (sk-lift-fact-tv $fact)))
         (()
            (case $step (
               ((by $rule $premise)
                  (CTVModusPonensFormula (sk-lift-eval $kb $ev $shared $probe $premise)
                     (sk-lift-rule-ctv $kb $rule)))
               ($_other
                  (if (is-expr $step)
                     (if (== (car-atom $step) conjunction)
                        (let (cons $first $rest) (map-semidet (sk-lift-eval $kb $ev $shared $probe) (cdr-atom $step))
                           (fold-semidet sk-lift-and-step $first $rest))
                        (empty))
                     (empty))))))))))

;; A proof's residual implication, kept when it reproduces the proof's strength.
(: sk-lift-residual (-[semidet]-> (List Evidence) STVType SkeletonValue CTVType))
(= (sk-lift-residual $shared $conj $value)
   (case $value (
      ((sk-val ($_type ($kb $_ctx $_vars) $proof (STV $stored $_confidence)) $ev $_deps)
         (let* (($residual
                   (CTV (sk-lift-eval $kb $ev $shared (STV 1.0 1.0) $proof)
                        (sk-lift-eval $kb $ev $shared (STV 0.0 1.0) $proof)))
                ((STV $strength $_strength-confidence) (CTVModusPonensFormula $conj $residual)))
            (if (< (abs-math (- $strength $stored)) 0.000001) $residual (empty)))))))

(: sk-lift-revise-step (-[semidet]-> CTVType CTVType CTVType))
(= (sk-lift-revise-step (CTV $pos1 $neg1) (CTV $pos2 $neg2))
   (CTV (mergetvs $pos1 $pos2) (mergetvs $neg1 $neg2)))

(: sk-lift-shared-step (-[det]-> (List Evidence) SkeletonValue (List Evidence)))
(= (sk-lift-shared-step $shared $value)
   (case $value (
      ((sk-val $_fact $ev $_deps) (evidence-intersection $shared $ev))
      ($_other ()))))

(: sk-lift-residual-ev-step (-[semidet]-> (List Evidence) (List Evidence) SkeletonValue (List Evidence)))
(= (sk-lift-residual-ev-step $shared $seen $value)
   (case $value (
      ((sk-val $_fact $ev $_deps)
         (let $residual (evidence-subtraction $ev $shared)
            (if (== $residual ()) (empty)
               (if (evidence-sets-overlap? $residual $seen) (empty) (append-flat $residual $seen))))))))

(: sk-lift-merge-step (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-lift-merge-step (sk-val ($type $kbctx $proof $tv) $ev $deps)
      (sk-val ($_other-type $_other-kbctx $other $_other-tv) $other-ev $other-deps))
   (sk-val ($type $kbctx (brand Proof (merge/revision $proof $other)) $tv)
      (sk-union $ev $other-ev) (sk-union $deps $other-deps)))

(: sk-lift-with-tv (-[semidet]-> SkeletonValue TV SkeletonValue))
(= (sk-lift-with-tv (sk-val ($type $kbctx $proof $_old) $ev $deps) $tv)
   (sk-val ($type $kbctx $proof $tv) $ev $deps))

(: sk-lift-group (-[semidet]-> (List Evidence) (List SkeletonValue) SkeletonValue))
(= (sk-lift-group $shared (cons $first $rest))
   (let* (($_disjoint (fold-semidet (sk-lift-residual-ev-step $shared) () (cons $first $rest)))
          ((cons $leaf $leaves) (map-semidet sk-lift-fact-tv $shared))
          ($conj (fold-semidet sk-lift-and-step $leaf $leaves))
          ((cons $residual $residuals) (map-semidet (sk-lift-residual $shared $conj) (cons $first $rest)))
          ($tv (CTVModusPonensFormula $conj (fold-semidet sk-lift-revise-step $residual $residuals))))
      (fold-semidet sk-lift-merge-step (sk-lift-with-tv $first $tv) $rest)))

;; The lifted value of a key's leaves and views, or nothing.
(: sk-lift (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-lift $values)
   (case $values (
      ((cons (sk-val $_fact $ev $_deps) (cons $_second $_more))
         (let $shared (fact-evidence-only (fold-flat sk-lift-shared-step $ev $values))
            (if (== $shared ()) () (collapse (once (sk-lift-group $shared $values))))))
      ($_other ()))))

;; Each row keeps its latest view and the views it replaced, in the order
;; they were computed. A consumer takes, per row, the latest view that depends
;; on none of the excluded keys and matches its pattern; an older one stays
;; usable when a newer one came to depend on one of them.
(: sk-excluded? (-[det]-> (List Number) (List Number) Bool))
(= (sk-excluded? () $_deps) false)
(= (sk-excluded? (cons $hash $rest) $deps)
   (if (stored-list-member? $hash $deps) true (sk-excluded? $rest $deps)))

(: sk-admits? (-[det]-> SkeletonFilter (List Number) SkeletonValue Bool))
(= (sk-admits? $filter $exclude $view)
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (sk-excluded? $exclude $deps) false (sk-fact-matches? $filter $fact)))
      ((sk-goal-val $_goal $_proof $_ev $deps)
         (if (sk-excluded? $exclude $deps) false true))
      (sk-none false))))

(: sk-admit-older (-[det]-> SkeletonFilter (List Number) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-admit-older $filter $exclude $kept $view)
   (if (sk-admits? $filter $exclude $view) $view $kept))

(: sk-admit-step
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue) SkeletonVersion
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
         (let* (($ref (sk-store-proof! $proof))
                ($_fact (case $ref (((proof-ref $pid) (add-atom &proof_fact ($pid $type $tv)))))))
            (sk-val (data $type $kbctx $ref $tv) $ev $deps)))
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
   (-[semidet]-> (-[semidet]-> $acc SkFact $acc) SkeletonFilter (List Number) SkeletonFold SkeletonKey
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
       SkeletonFilter (List Number) SkeletonFold))
(= (sk-fold-over $step $function $init $finish $members $filter $exclude)
   (let* (((sk-fold-state $acc $proofs $ev $deps)
             (fold-semidet (sk-fold-step $step $filter $exclude) (sk-fold-state $init () () ()) $members)))
      (sk-fold-state (finish-aggregate $finish $acc) (cons (sk-fold-proof $function $proofs) ())
         (sk-fold-evidence $finish $ev)
         ;; A base rate is an estimate about the population, like a prior: it
         ;; ties its readers to none of its members.
         (if (base-rate-finish? $finish) () $deps))))

;; A fold's or group's view over its member keys; with no members it is the
;; finished initial value, proved by `cpu`.
(: sk-folded-view
   (-[semidet]-> Number Atom $args (-[semidet]-> $acc SkFact $acc) Atom $acc AggregateFinish
       (List SkeletonKey) SkeletonFilter SkeletonValue))
(= (sk-folded-view $hash $kind $args $step $function $init $finish $members $filter)
   (case (sk-fold-over $step $function $init $finish $members $filter (cons $hash ())) (
      ((sk-fold-state $value (cons $proof $_rest) $ev $deps)
         (sk-goal-val (CPU $kind $args $value) $proof $ev (cons $hash $deps))))))

;; A base rate's value is its user base rate, or else the better of its cached
;; estimate and a fold over the members the search found; a fold that improves
;; on the estimate replaces it and is cached for reuse. The fold's own cached
;; value and a forward approximation are partial work, taken before the search
;; found all members, and always give way to the fold. An unexpanded fold reads
;; the estimate, and without one it is the empty fold. The fold key watches the
;; cache entry. Any other fold is computed from its members.
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
                     (sk-better-rate-view $hash $args $rate-hash $kbid $pattern $mode $entry)))
               (() (sk-store-computed-rate $rate-hash $kbid $pattern $mode () (sk-computed-fold-view $hash $args)))))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args)))))

(: sk-better-rate-view
   (-[semidet]-> Number ScalarFoldSpec Number KB Statement $mode BaseRateEntry SkeletonValue))
(= (sk-better-rate-view $hash $args $rate-hash $kbid $pattern $mode $entry)
   (if (== (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) ())
      (sk-cached-fold-view $hash $args $entry)
      (let $computed (sk-computed-fold-view $hash $args)
         (case $computed (
            ((sk-goal-val (CPU $_f $_a $tv) $_p $_ev $_deps)
               (if (if (== (base-rate-entry-source $entry) forward-approx) true
                      (if (== (collapse (once (match &sk_rate_own ($rate-hash $own) $own)))
                              (cons (base-rate-entry-tv $entry) ()))
                         true
                         (>= (tv-confidence $tv) (tv-confidence (base-rate-entry-tv $entry)))))
                  (sk-store-computed-rate $rate-hash $kbid $pattern $mode (cons $entry ()) $computed)
                  (sk-cached-fold-view $hash $args $entry)))
            ($_none (sk-cached-fold-view $hash $args $entry)))))))

;; Caching the computed value the entry already holds would only wake the fold
;; again.
(: sk-store-computed-rate
   (-[det]-> Number KB Statement $mode (List BaseRateEntry) SkeletonValue SkeletonValue))
(= (sk-store-computed-rate $rate-hash $kbid $pattern $mode $cached $view)
   (let $_stored
      (case $view (
         ((sk-goal-val (CPU $_f $_a (STV $s $c)) $_p $_ev $_deps)
            (if (case $cached (
                   ((cons $entry $_rest)
                      (if (== (base-rate-entry-source $entry) computed)
                         (== (base-rate-entry-tv $entry) (STV $s $c))
                         false))
                   (() false)))
               ()
            (let* (($_cached (store-produced-base-rate! $kbid $pattern (STV $s $c) computed $mode))
                   ($_old (collapse (match &sk_rate_own ($rate-hash $old) (remove-atom &sk_rate_own ($rate-hash $old))))))
               (add-atom &sk_rate_own ($rate-hash (STV $s $c))))))
         ($_other ())))
      $view))

(: sk-cached-fold-view (-[semidet]-> Number ScalarFoldSpec BaseRateEntry SkeletonValue))
(= (sk-cached-fold-view $hash $args $entry)
   (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) ()
      (cons $hash ())))

(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-computed-fold-view $hash $args)
   (let* ((($_kb $_pattern $extractor $init $function $finish $_mode) $args))
      (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
         (() (sk-folded-view $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init $finish
            () sk-any-filter))
         ((cons $member $_rest)
            (sk-folded-view $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init
               $finish (sk-answers $member) (sk-member-filter $member)))))))

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
            (sk-folded-view $hash GroupedFoldAllCompiled $args (sk-accumulate $extractor $function) $function
               $init $finish $members (sk-member-filter $member)))
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
(: sk-admitted (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-admitted $hash $key $filter $exclude)
   (let* (($stored (sk-latest-versions $hash $key))
          ($versions (if (== $stored ()) (sk-fold-views $hash $key) $stored)))
      (fold-semidet sk-cons-step () (fold-semidet (sk-admit-step $hash $key $filter $exclude) () $versions))))

;; Leaves first, then one version per row in the order the rows were found.
(: sk-merge-key (-[semidet]-> Number SkeletonKey SkeletonFilter (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $views)
   (let $values (append-flat (map-semidet (sk-leaf-view $hash) (sk-key-leaves $key $filter)) $views)
      (case (sk-lift $values) (
         ((cons $lifted $_rest) $lifted)
         (() (fold-semidet sk-merge-step sk-none $values))))))

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
                ($views (sk-admitted $hash $key $filter ()))
                ($deps (fold-semidet sk-view-deps-step () $views))
                ($value (sk-merge-key $hash $key $filter $views))
                ($_cached (add-atom &sk_merged (sk-merged $hash $key $deps $value))))
            (sk-merged $hash $key $deps $value))))))

;; The merged value of a key on behalf of a consumer. A proof or truth-value
;; pattern takes the whole merged value when it admits it, and otherwise the
;; merge of the views it admits.

(= (sk-value $key $filter $exclude)
   (let* (($hash (index-hash $key))
          ($merged
             (case (sk-open-value $hash $key sk-any-filter) (
                ((sk-merged $_hash $_key $deps $value)
                   (if (sk-excluded? $exclude $deps)
                      (sk-merge-key $hash $key sk-any-filter (sk-admitted $hash $key sk-any-filter $exclude))
                      $value))))))
      (if (sk-open-filter? $filter) $merged
         (if (sk-admits? $filter () $merged) $merged
            (sk-merge-key $hash $key $filter (sk-admitted $hash $key $filter $exclude))))))

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
(= (sk-consume-fold (sk-acc $fold-proofs $ev $deps $parts) $res $value)
   (case $value (
      ((sk-goal-val (CPU $_fun $_args $result) $proof $fold-ev $fold-deps)
         (if (= $res $result)
            (sk-acc (cons $proof $fold-proofs) (sk-union $ev $fold-ev) (sk-union $deps $fold-deps) $parts)
            sk-fail))
      ($_none sk-fail))))

;; --- Conjunction pooling ----------------------------------------------------

;; Projections of one stored (And ...) source are not independent: they share
;; the source's evidence. A conjunction pools them back into the source, whose
;; truth value it takes once every member is projected, and the first
;; projection's marginal truth value before.
(: sk-proof-source (-[det]-> Proof (List SkeletonSource)))
(= (sk-proof-source $base)
   (case $base (
      ((proof-ref $pid) (collapse (once (match &proof_fact ($pid $statement $tv) (sk-source $statement $tv)))))
      ($_leaf (collapse (once (match &kb ($statement $_kbctx $base $tv) (sk-source $statement $tv))))))))

(: sk-premise-part (-[det]-> SkFact SkeletonPart))
(= (sk-premise-part ($_type $_kbctx $proof $tv))
   (case (sk-step-proof $proof) (
      ((marginal-proj $idx $base)
         (case (sk-proof-source (brand Proof $base)) (
            ((cons (sk-source $statement $source-tv) $_rest)
               (if (if (is-expr $statement) (== (car-atom $statement) And) false)
                  (sk-pool-part (brand Proof $base) $source-tv (list-len (cdr-atom $statement)) (cons $idx ()) $tv)
                  (sk-indep-part $tv)))
            (() (sk-indep-part $tv)))))
      ($_other (sk-indep-part $tv)))))

(: sk-same-pool? (-[det]-> SkeletonPart SkeletonPart Bool))
(= (sk-same-pool? $part $other)
   (case $part (
      ((sk-pool-part $base $_tv $_arity $_idxs $_marginal)
         (case $other (
            ((sk-pool-part $other-base $_other-tv $_other-arity $_other-idxs $_other-marginal)
               (=alpha $base $other-base))
            ($_indep false))))
      ($_part-indep false))))

(: sk-joins-pool? (-[det]-> (List SkeletonPart) SkeletonPart Bool))
(= (sk-joins-pool? () $_part) false)
(= (sk-joins-pool? (cons $head $rest) $part)
   (if (sk-same-pool? $part $head) true (sk-joins-pool? $rest $part)))

(: sk-add-part (-[det]-> (List SkeletonPart) SkeletonPart (List SkeletonPart)))
(= (sk-add-part () $part) (cons $part ()))
(= (sk-add-part (cons $head $rest) $part)
   (case $head (
      ((sk-pool-part $base $tv $arity $idxs $marginal)
         (case $part (
            ((sk-pool-part $part-base $_part-tv $_part-arity $new-idxs $_part-marginal)
               (if (=alpha $base $part-base)
                  (cons (sk-pool-part $base $tv $arity (list_to_set (append-flat $idxs $new-idxs)) $marginal) $rest)
                  (cons $head (sk-add-part $rest $part))))
            ($_indep-part (cons $head (sk-add-part $rest $part))))))
      ($_indep-head (cons $head (sk-add-part $rest $part))))))

(: sk-pooled? (-[det]-> (List SkeletonPart) Bool))
(= (sk-pooled? ()) false)
(= (sk-pooled? (cons $head $rest))
   (case $head (
      ((sk-pool-part $_base $_tv $_arity $idxs $_marginal)
         (if (> (list-len $idxs) 1) true (sk-pooled? $rest)))
      ($_indep (sk-pooled? $rest)))))

(: sk-part-tv (-[det]-> SkeletonPart TV))
(= (sk-part-tv $part)
   (case $part (
      ((sk-indep-part $tv) $tv)
      ((sk-pool-part $_base $tv $arity $idxs $marginal)
         (if (== (list-len $idxs) $arity) $tv $marginal)))))

(: sk-parts-tv-step (-[semidet]-> TV SkeletonPart TV))
(= (sk-parts-tv-step $acc $part) (AndFormula $acc (sk-part-tv $part)))

(: sk-parts-tv (-[semidet]-> (List SkeletonPart) TV))
(= (sk-parts-tv (cons $first $rest)) (fold-semidet sk-parts-tv-step (sk-part-tv $first) $rest))

;; A premise value whose evidence overlaps what the row already uses is
;; replaced by the merge of the key's leaves and views that do not overlap it:
;; the consumer selects the proofs compatible with its other premises.
(: sk-compatible-step (-[semidet]-> (List Evidence) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-compatible-step $ev $acc $view)
   (case $view (
      ((sk-val $_fact $view-ev $_deps)
         (if (premise-evidence-overlap? $ev $view-ev) $acc (sk-merge-step $acc $view)))
      ($_other $acc))))

(: sk-compatible-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) (List Evidence) Bool SkeletonValue))
(= (sk-compatible-value $key $filter $exclude $ev $views)
   (let* (($hash (index-hash $key))
          ($leaves (map-semidet (sk-leaf-view $hash) (sk-key-leaves $key $filter))))
      (fold-semidet (sk-compatible-step $ev) sk-none
         (if $views (append-flat $leaves (sk-admitted $hash $key $filter $exclude)) $leaves))))

;; A fact premise takes a value unless its evidence overlaps the row's own,
;; except in joins the compiler marked as sharing their sources and for
;; projections joining a pool of the same source.
(: sk-use-premise (-[semidet]-> Bool SkeletonRowState SkPattern SkeletonValue SkeletonRowState))
(= (sk-use-premise $shared (sk-acc $fold-proofs $ev $deps $parts) ($type $kbctx $proof $tv) $value)
   (case $value (
      ((sk-val $fact $premise-ev $premise-deps)
         (let $part (sk-premise-part $fact)
            (if (if $shared false
                   (if (premise-evidence-overlap? $ev $premise-ev) (not (sk-joins-pool? $parts $part)) false))
               sk-fail
               (if (= ($type $kbctx $proof $tv) (if (is-var $proof) $fact (sk-full-fact $fact)))
                  (sk-acc $fold-proofs (sk-union $ev $premise-ev) (sk-union $deps $premise-deps)
                     (sk-add-part $parts $part))
                  sk-fail))))
      ($_none sk-fail))))

;; Each premise reads its key's value without the views that depend on the
;; row's conclusion; reading stored facts first, it takes the facts compatible
;; with the row so far when there are any.
(: sk-premise-step (-[semidet]-> (List Number) Bool Bool SkeletonRowState SkPattern SkeletonRowState))
(= (sk-premise-step $exclude $shared $facts-first $state $premise)
   (case $state (
      (sk-fail sk-fail)
      (sk-clash sk-clash)
      ((sk-acc $fold-proofs $ev $deps $parts)
         (case $premise (
            ((CPU FoldAllCompiled $fold-args $fold-res)
               (sk-consume-fold $state $fold-res (sk-value (sk-fold $fold-args) sk-any-filter $exclude)))
            ((CPU GroupedFoldAllCompiled $group-args $group-res)
               (sk-consume-fold $state $group-res (sk-value (sk-group $group-args) sk-any-filter $exclude)))
            ;; A conjunction step over pooled projections takes the pooled
            ;; truth value instead of multiplying shared evidence.
            ((CPU $fun $args $res)
               (if (if (== $fun AndFormula) (sk-pooled? $parts) false)
                  (if (= $res (sk-parts-tv $parts)) $state sk-fail)
                  (case (collapse (once (cpu-call 0 $fun $args))) (
                     ((cons $result $_rest) (if (= $res $result) $state sk-fail))
                     (() sk-fail)))))
            (($type $kbctx $proof $tv)
               (let* (($key (sk-key $type $kbctx))
                      ($filter (sk-filter $proof $tv))
                      ($value
                         (if $facts-first (sk-compatible-value $key $filter $exclude $ev false)
                            (sk-value $key $filter $exclude))))
                  (case (sk-use-premise $shared $state $premise $value) (
                     (sk-fail
                        (if $shared sk-fail
                           (case (sk-use-premise $shared $state $premise (sk-compatible-value $key $filter $exclude $ev true)) (
                              (sk-fail (case $value (((sk-val $_fact $_value-ev $_deps) sk-clash) ($_none sk-fail))))
                              ($compatible $compatible)))))
                     ($taken $taken)))))))))))

;; A computation whose arguments were ground when its join was built was
;; computed then and bound its result; recomputing a sampling formula would
;; draw again. The formulas over premise truth values run in evaluation.
(: sk-evaluated-premise-step (-[det]-> (List SkPattern) SkPattern (List SkPattern)))
(= (sk-evaluated-premise-step $kept $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (aggregate-fold-function? $fun) (cons $premise $kept)
            (if (== (extract-vars $args) ()) $kept (cons $premise $kept))))
      ($_fact (cons $premise $kept)))))

;; A row reads its premises without the views that depend on its key or on a
;; key unifying with it. Premises take values greedily in order, so a merged
;; value may hold evidence a later premise needs: on such a clash the row reads
;; again, on a fresh copy, taking stored facts first.
(: sk-row-view (-[semidet]-> Number SkeletonKey SkeletonRow SkeletonValue))
(= (sk-row-view $khash $key $row)
   (let* (($greedy (copy_term $row))
          ($state (sk-row-state $khash $key false $greedy)))
      (case $state (
         (sk-clash
            (let $retry (copy_term $row) (sk-row-result $retry (sk-row-state $khash $key true $retry))))
         ($_other (sk-row-result $greedy $state))))))

(: sk-row-state (-[semidet]-> Number SkeletonKey Bool SkeletonRow SkeletonRowState))
(= (sk-row-state $khash $key $facts-first (sk-row $_ident ($_type $_kbctx $proof $_tv) $premises $_seq))
   (fold-semidet
      (sk-premise-step (sk-unifier-hashes $khash $key) (shared-evidence-frontier-proof? $proof) $facts-first)
      (sk-acc () () (cons $khash ()) ())
      (fold-semidet sk-cons-step () (fold-semidet sk-evaluated-premise-step () $premises))))

(: sk-row-result (-[semidet]-> SkeletonRow SkeletonRowState SkeletonValue))
(= (sk-row-result (sk-row $_ident ($type $kbctx $proof $tv) $_premises $_seq) $state)
   (case $state (
      ((sk-acc $fold-proofs $ev $deps $_parts)
         (let* (((token-state $full-proof $_unused)
                   (replace-token $proof (fold-semidet sk-cons-step () $fold-proofs)))
                ($fact (assemble-runtime-fact $type $kbctx (sk-unwrap-proof $full-proof) $tv)))
            (sk-val $fact (rule-result-evidence $fact $ev) $deps)))
      ($_failed sk-none))))

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
;; evaluation for each key that caused it, and a reader whose value changes
;; passes it on to its own readers the same way.

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
(= (sk-item-seq (sk-fold-check $_hash $_fold)) (sk-check-seq))

;; this pass's remaining rows and the next pass's rows, by creation number
(: SkeletonWork Type)
(: sk-work (-[det]-> (Heap SkeletonItem) (Heap SkeletonItem) SkeletonWork))

(: sk-queued-new? (-[det]-> Number Number Number Bool))
(= (sk-queued-new? $pass $khash $rhash)
   (if (not (== (collapse (once (match &sk_queued ($pass $khash $rhash) true))) ())) false
      (let $_queued (add-atom &sk_queued ($pass $khash $rhash)) true)))

;; A row is queued by its key and row hashes, a fold check by its fold's hash.
(: sk-queue-new? (-[det]-> Number SkeletonItem Bool))
(= (sk-queue-new? $pass (sk-row-item $_seq $khash $_key $rhash $_row)) (sk-queued-new? $pass $khash $rhash))
(= (sk-queue-new? $pass (sk-fold-check $hash $_fold)) (sk-queued-new? $pass $hash -1))

;; What changed for a key's readers: a new row view with its dependencies,
;; the same with the key's open merged value unchanged and the dependencies of
;; that value before and after, or a change from outside the rows (a fact, a
;; removed query-local row, fold members) caused by the keys with these hashes.
(: SkeletonChange Type)
(: sk-view-change (-[det]-> (List Number) SkeletonChange))
(: sk-value-same (-[det]-> (List Number) (List Number) SkeletonChange))
(: sk-outside-change (-[det]-> (List Number) SkeletonChange))

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
             ((sk-outside-change $causes) (sk-force! $causes $item))
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

;; A member change of a fold that was read queues the fold's check at the end
;; of the pass, so the members changed in one pass recompute it once; until
;; then its readers read the value it had. A fold nobody read since it last
;; changed is computed when next read. A check queued for this pass is also
;; queued for the next, in case this pass's check already ran.
(: sk-check-seq (-[det]-> Number))
(= (sk-check-seq) 1000000000000000)

(: sk-fold-changed (-[semidet]-> Number Number Number SkeletonWork SkeletonKey SkeletonWork))
(= (sk-fold-changed $pass $_seq $member (sk-work $todo $next) $fold)
   (let $hash (index-hash $fold)
      (if (== (sk-latest-view $hash $fold 0) sk-none) (sk-work $todo $next)
         (let* (($_pending (add-atom &sk_fold_pending ($hash $member)))
                ($check (sk-fold-check $hash $fold)))
            (if (sk-queue-new? $pass $check) (sk-work (add_to_heap $todo (sk-check-seq) $check) $next)
               (if (sk-queue-new? (+ $pass 1) $check) (sk-work $todo (add_to_heap $next (sk-check-seq) $check))
                  (sk-work $todo $next)))))))

;; A row is forced once per evaluation by each changed key: a fold's readers
;; follow its members as they change, and a fold feeding back into its own
;; members still ends.
(: sk-force-cause! (-[det]-> Number Number Number Atom))
(= (sk-force-cause! $khash $rhash $cause)
   (if (== (collapse (once (match &sk_forced_used ($khash $rhash $cause) true))) ())
      (let* (($_used (add-atom &sk_forced_used ($khash $rhash $cause)))
             ($_forced (add-atom &sk_forced ($khash $rhash $cause))))
         ())
      ()))

(: sk-force! (-[det]-> (List Number) SkeletonItem Atom))
(= (sk-force! $causes (sk-row-item $_seq $khash $_key $rhash $_row))
   (let $_forced (map-flat (sk-force-cause! $khash $rhash) $causes) ()))
(= (sk-force! $_causes (sk-fold-check $_hash $_fold)) ())

;; The keys that forced a row since it was last computed.
(: sk-take-forced! (-[det]-> Number Number (List Number)))
(= (sk-take-forced! $khash $rhash)
   (collapse (match &sk_forced ($khash $rhash $cause)
      (let $_taken (remove-atom &sk_forced ($khash $rhash $cause)) $cause))))

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

;; A fold's provenance counts as a change: a complete fold may replace a cached
;; estimate of the same truth value.
(: sk-view-step-proof (-[det]-> SkeletonValue Proof))
(= (sk-view-step-proof $view)
   (case $view (
      ((sk-goal-val $_goal $proof $_ev $_deps) (sk-step-proof $proof))
      ((sk-val $fact $_ev $_deps) (sk-fact-step-proof $fact))
      (sk-none (brand Proof none)))))

;; A fold check recomputes the fold once for the members that changed since
;; the last one; when its value changed, every reader is forced by those
;; members, in the next pass.
(: sk-check-fold (-[semidet]-> Number SkeletonWork Number SkeletonKey SkeletonWork))
(= (sk-check-fold $pass $work $hash $fold)
   (let* (($causes
             (list_to_set (collapse (match &sk_fold_pending ($hash $member)
                (let $_taken (remove-atom &sk_fold_pending ($hash $member)) $member)))))
          ($old (sk-latest-view $hash $fold 0)))
      (if (if (== $causes ()) true (== $old sk-none)) $work
         (let* (($_view (sk-drop-fold-view! $fold))
                ($_merged (sk-drop-merged! $fold)))
            (case (sk-fold-views $hash $fold) (
               ((cons (sk-version $_seq $_rhash $new) $_rest)
                  (if (if (sk-same-view? $new $old) (== (sk-view-step-proof $new) (sk-view-step-proof $old)) false)
                     $work
                     (sk-key-changed $pass (sk-check-seq) (sk-outside-change $causes) $work $fold)))
               (() (sk-key-changed $pass (sk-check-seq) (sk-outside-change $causes) $work $fold))))))))

;; A row whose view differs from its latest version stores a new version and
;; changes its key, when it is the row's first view, it was forced, or it
;; brings new support. A forced row also stores a view that differs only in
;; its proof: an outside change such as a completed fold improves provenance.
(: sk-compute (-[semidet]-> Number SkeletonWork SkeletonItem SkeletonWork))
(= (sk-compute $pass $work (sk-fold-check $hash $fold)) (sk-check-fold $pass $work $hash $fold))
(= (sk-compute $pass $work (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_computed (query_metric_increment row-computes))
          ($causes (sk-take-forced! $hash $rhash))
          ($forced (not (== $causes ())))
          ($new (sk-row-view $hash $key $row)))
      (case $new (
         ;; A row forced by an outside change that no longer derives anything
         ;; (a premise fact was removed) drops its views, and its key changed.
         (sk-none
            (if (if $forced (not (== (sk-latest-view $hash $key $rhash) sk-none)) false)
               (let* (($_views (sk-drop-row-views! $hash $key $rhash))
                      ($_merged (sk-drop-merged! $key)))
                  (sk-key-changed $pass $seq (sk-outside-change $causes) $work $key))
               $work))
         ($_view
            (let $latest (sk-latest-view $hash $key $rhash)
            (if (if (sk-same-view? $new $latest)
                   (if $forced (== (sk-view-step-proof $new) (sk-view-step-proof $latest)) true)
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
                  (sk-key-changed $pass $seq
                     (if (if $forced (not (sk-same-view? $new $latest)) false)
                        (sk-outside-change $causes)
                        (sk-value-change $hash $key $deps $before))
                     $work $key)))))))))

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
      (sk-key-changed 0 -1 (sk-outside-change (cons (index-hash $key) ())) $work $key)))

(: sk-seed-new (-[det]-> (Heap SkeletonItem) SkeletonItem (Heap SkeletonItem)))
(= (sk-seed-new $todo $item)
   (if (sk-queue-new? 0 $item) (add_to_heap $todo (sk-item-seq $item) $item) $todo))

(: sk-evaluate! (-[semidet]-> Atom))
(= (sk-evaluate!)
   (let* (($_queued (collapse (match &sk_queued ($pass $khash $rhash) (remove-atom &sk_queued ($pass $khash $rhash)))))
          ($_forced (collapse (match &sk_forced ($khash $rhash $cause) (remove-atom &sk_forced ($khash $rhash $cause)))))
          ($_used (collapse (match &sk_forced_used ($khash $rhash $cause) (remove-atom &sk_forced_used ($khash $rhash $cause)))))
          ($_pending (collapse (match &sk_fold_pending ($fhash $member) (remove-atom &sk_fold_pending ($fhash $member)))))
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

;; Setting or clearing a user base rate replaces whatever every fold over its
;; pattern computed, so all views and merged values are dropped.
(: sk-drop-all-views! (-[det]-> Atom))
(= (sk-drop-all-views!)
   (let* (($_older (collapse (match &sk_view ($h $k $r $v) (remove-atom &sk_view ($h $k $r $v)))))
          ($_latest (collapse (match &sk_latest ($h2 $k2 $v2) (remove-atom &sk_latest ($h2 $k2 $v2)))))
          ($_merged
             (collapse (match &sk_merged (sk-merged $h3 $k3 $d3 $v3)
                (remove-atom &sk_merged (sk-merged $h3 $k3 $d3 $v3))))))
      ()))

(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($hash (base-rate-cache-hash $kbid $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache ($hash (base-rate $kbid $stored $tv user any))))
          ($_views (sk-drop-all-views!)))
      ()))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (let* (($_old (base-rate-cache-remove! $kbid $pattern))
          ($_views (sk-drop-all-views!)))
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

;; The stored proofs a proof term refers to directly.
(: sk-proof-refs (-[det]-> Atom (List Number)))
(: sk-proof-refs-in (-[det]-> Atom (List Number)))
(= (sk-proof-refs $term)
   (if (is-expr $term)
      (case $term (
         ((proof-ref $pid) (cons $pid ()))
         ($_other (sk-proof-refs-in $term))))
      ()))
;; Atom parameters take their arguments unevaluated, so each part is bound first.
(= (sk-proof-refs-in $terms)
   (if (== $terms ()) ()
      (let* (($first (car-atom $terms))
             ($rest (cdr-atom $terms)))
         (append-flat (sk-proof-refs $first) (sk-proof-refs-in $rest)))))

;; A materialized answer brings the derived facts of its proof along: each
;; stored fact proof it uses materializes that statement's current value, once.
(: sk-materialize-ref! (-[semidet]-> KBContext (List Number) Number (List Number)))
(= (sk-materialize-ref! $kbctx $visited $pid)
   (if (stored-list-member? $pid $visited) $visited
      (let* (($_fact
                (case (collapse (once (match &proof_fact ($pid $statement $_tv) $statement))) (
                   ((cons $statement $_rest) (sk-materialize! (sk-value (sk-key $statement $kbctx) sk-any-filter ())))
                   (() ()))))
             ($step (sk-step-proof (proof-ref $pid))))
         (fold-semidet (sk-materialize-ref! $kbctx) (cons $pid $visited) (sk-proof-refs $step)))))

(: sk-materialize-answer! (-[semidet]-> SkeletonValue Atom))
(= (sk-materialize-answer! $value)
   (let $_answer (sk-materialize! $value)
      (case $value (
         ((sk-val ($type $kbctx $proof $tv) $_ev $_deps)
            (let $_derived (fold-semidet (sk-materialize-ref! $kbctx) () (sk-proof-refs (sk-step-proof $proof))) ()))
         ($_other ())))))

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
(= (sk-root-value $filter $key) (sk-value $key $filter ()))

;; A root reads the answers of every node of its statement and context,
;; whatever their proof and truth-value patterns: a root whose pattern is new
;; has no answers of its own before it is searched. Its stored facts cost no
;; expansion, as for any premise. A materialized answer is the result an
;; earlier query left, not independent evidence: the root falls back to it when
;; the search has no value for the key.
(: sk-statement-answers (-[det]-> Statement KBContext (List SkeletonKey)))
(= (sk-statement-answers $type $kbctx)
   (let* (($key (sk-key $type $kbctx))
          ($hash (index-hash $key)))
      (collapse (match &sk_answer ($hash ($node-type $node-kbctx $_proof $_tv) $answer)
         (if (=alpha (sk-key $node-type $node-kbctx) $key) $answer (empty))))))

;; A root's proof and truth-value pattern may share variables with its
;; statement, so each key is read with the pattern instantiated by that key.
(: sk-root-key-value (-[semidet]-> SkPattern SkeletonKey SkeletonValue))
(= (sk-root-key-value $goal $key)
   (case (copy_term $goal) (
      ((CPU $_fun $_args $_res) sk-none)
      (($type $kbctx $proof $tv)
         (if (= (sk-key $type $kbctx) (copy_term $key))
            (let $filter (sk-filter $proof $tv)
               (case (sk-value $key $filter ()) (
                  (sk-none
                     (case (sk-materialized-views $type $kbctx $filter) (
                        ((cons $incumbent $_rest) $incumbent)
                        (() sk-none))))
                  ($current $current))))
            sk-none)))))

(: sk-materialized-views (-[det]-> Statement KBContext SkeletonFilter (List SkeletonValue)))
(= (sk-materialized-views $type $kbctx $filter)
   (if (== (extract-vars $type) ())
      (let $hash (forward-output-index-hash (forward-output-key $kbctx $type))
         (collapse (match &materialized_facts (materialized-row $hash $type $kbctx $fact $ev)
            (if (sk-fact-matches? $filter $fact) (sk-val $fact $ev ()) (empty)))))
      ()))

(: sk-root-values (-[semidet]-> SkPattern (List SkeletonValue)))
(= (sk-root-values $goal)
   (case $goal (
      ((CPU $fun $args $res)
         (if (== $fun FoldAllCompiled)
            (cons (sk-value (sk-fold $args) sk-any-filter ()) ())
            (if (== $fun GroupedFoldAllCompiled)
               (map-semidet (sk-root-value sk-any-filter) (sk-answers $goal))
               (collapse (let $result (cpu-call 0 $fun $args)
                  (if (= $res $result)
                     (sk-goal-val (CPU $fun $args $result) (brand Proof cpu) () ())
                     (empty)))))))
      (($type $kbctx $_proof $_tv)
         (map-semidet (sk-root-key-value $goal)
            (fold-semidet sk-cons-step ()
               (fold-flat sk-new-key-step ()
                  (append-flat (sk-statement-answers $type $kbctx)
                     (collapse (match &kb ($type $kbctx $_proof $_tv) (sk-key $type $kbctx)))))))))))

(: sk-new-key-step (-[det]-> (List SkeletonKey) SkeletonKey (List SkeletonKey)))
(= (sk-new-key-step $kept $key) (if (fold-flat (sk-alpha-step $key) false $kept) $kept (cons $key $kept)))

(: sk-alpha-step (-[det]-> SkeletonKey Bool SkeletonKey Bool))
(= (sk-alpha-step $key $found $other) (if $found true (=alpha $key $other)))

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

;; An answer is redundant when another answer has the same proof and a more
;; general statement: it is that derivation instantiated.
(: sk-instance-of? (-[det]-> RuntimeResult RuntimeResult Bool))
(= (sk-instance-of? $answer $general)
   (if (=alpha $answer $general) false
      (case (copy_term $answer) (
         (($type $kbctx $proof $tv)
            (case (copy_term $general) (
               (($general-type $general-kbctx $general-proof $_general-tv)
                  (if (== $proof $general-proof)
                     (if (= $general-type $type) (=alpha $type (sk-fact-type $answer)) false)
                     false))
               ($_goal false))))
         ($_goal-answer false)))))

(: sk-fact-type (-[det]-> RuntimeResult Atom))
(= (sk-fact-type $answer) (case $answer ((($type $_kbctx $_proof $_tv) $type) ($_goal $answer))))

(: sk-subsumed-step (-[semidet]-> (List RuntimeResult) (List RuntimeResult) RuntimeResult (List RuntimeResult)))
(= (sk-subsumed-step $all $kept $answer)
   (if (fold-flat (sk-instance-step $answer) false $all) $kept (cons $answer $kept)))

(: sk-instance-step (-[det]-> RuntimeResult Bool RuntimeResult Bool))
(= (sk-instance-step $answer $found $general) (if $found true (sk-instance-of? $answer $general)))

;; Proven answers in root order without redundant instances; a materializing
;; query writes back the first.
(: sk-root-results (-[semidet]-> Bool SkPattern (List RuntimeResult)))
(= (sk-root-results $materialize? $goal)
   (let* (($values (fold-semidet sk-cons-step () (fold-semidet sk-proven-step () (sk-root-values $goal))))
          ($_materialized
             (if $materialize?
                (case $values (
                   ((cons $first $_rest) (sk-materialize-answer! $first))
                   (() ())))
                ()))
          ($answers (fold-semidet sk-cons-step () (fold-semidet sk-result-step () $values))))
      (fold-semidet sk-cons-step () (fold-semidet (sk-subsumed-step $answers) () $answers))))

;; A root's Member producer is part of its scaffold and installed even when
;; the budget expands nothing.
(: sk-root-score-step (-[semidet]-> Atom SkPattern Atom))
(= (sk-root-score-step $_acc $goal)
   (let* (($hash (sk-node-hash $goal))
          ($_root (add-atom &sk_roots ($hash $goal)))
          ($_member
             (case (copy_term $goal) (
                ((CPU $_fun $_args $_res) ())
                (($type $kbctx $_proof $_tv) (install-member-inheritance-rules! $type $kbctx))))))
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
