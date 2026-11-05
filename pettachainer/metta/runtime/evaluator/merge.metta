;; View merging and reference-class selection. Readers are supplied by the evaluator.

;; Disjoint forward views of a consequent whose outcomes prefer a product mode
;; combine by it; two certain views that contradict each other revise.
(: sk-combined-merge (-[semidet]-> SkeletonModeReader SkFact SkFact EvidenceSet Number SkeletonValue))
(= (sk-combined-merge $modes ($type $kbctx $proof-a $tv-a) ($_btype $_bkbctx $proof-b $tv-b) $ev $deps)
   (let* (((sk-mode-reader $choose-fn) $modes)
          ($choose (the (-[semidet]-> KB Statement Atom) $choose-fn))
          ($parts-a (sk-forward-parts $proof-a))
          ($parts-b (sk-forward-parts $proof-b)))
      (if (if (== $parts-a ()) true (== $parts-b ())) sk-none
         (case (collapse (once ($choose (brand KB (car-atom $kbctx)) $type))) (
            ((cons $choice $_none)
               (case (data $choice $tv-a $tv-b) (
                  ((($mode (STV $sp $cp)) (STV $sa $ca) (STV $sb $cb))
                     (if (if (== $mode revision) true (sk-contradict? (the Number $sa) (the Number $sb))) sk-none
                        (sk-val ($type $kbctx (brand Proof (combination $mode (prior (STV $sp $cp)) (append-flat $parts-a $parts-b)))
                                    (sk-factored-tv $mode (the Number $sp) (the Number $cp) (the Number $sp) (the Number $cp) (the Number $sa) (the Number $ca) (the Number $sb) (the Number $cb)))
                           $ev $deps)))
                  ($_revision sk-none))))
            (() sk-none))))))

;; Re-evaluating the selected general reads its learned fold under the
;; specific's sample exclusions (ledger-instance-read-excluding). A missing read is the only
;; reason to omit it; the already-selected frontier never promotes ancestors.
(: sk-class-without (-[semidet]-> SkeletonRowReader SkFact EvidenceSet SkeletonValue SkeletonValue))
(= (sk-class-without $rows $specific $specific-ev $general)
   (let* (((sk-row-reader $row-read-fn) $rows)
          ($row-read (the (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue) $row-read-fn)))
      (case $general (
         ((sk-val ($type $ctx $proof $tv) $ev $deps)
            (let* (($sources (sk-class-sources $specific $specific-ev))
                   ($cuts (hash-set (observation-keys $sources))))
               (if (== $sources (source-list (unverified-observation))) sk-none
               (if (== $cuts ())
                  (if (premise-evidence-overlap? $specific-ev $ev) sk-none $general)
                  (let* (($key (sk-key $type $ctx)) ($hash (index-hash $key)))
                     (chainer-first-or sk-none (collapse (once
                        (match &sk_row ($hash $stored $rhash $row)
                           (let* (((sk-row $_id ($_t $_c $row-proof $_tv) $_premises $_seq) (copy_term $row)))
                              (if (if (=alpha $stored $key) (= (copy_term $row-proof) (sk-step-proof $proof)) false)
                                 (let $value ($row-read () $cuts $hash $key $rhash (copy_term $row))
                                    (case $value (
                                       ((sk-val $_fact $new-ev $_new-deps)
                                          (if (premise-evidence-overlap? $specific-ev $new-ev) (empty) $value))
                                       ($_none (empty)))))
                                 (empty))))))))))))
         ($_none sk-none)))))

(: sk-nearest-prior-step (-[semidet]-> SkeletonRowReader (List SkeletonReference) SkFact EvidenceSet (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-nearest-prior-step $rows $references $specific $specific-ev $kept (sk-reference $class $view))
   (if (fold-semidet (sk-outranked-step (sk-reference $class $view)) false $references)
      $kept
      (case (sk-class-without $rows $specific $specific-ev $view) (
         (sk-none $kept)
         ($independent (cons $independent $kept))))))

(: sk-reference-step (-[semidet]-> SkeletonRowReader (List SkeletonReference) (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-reference-step $rows $references $kept $reference)
   (let (sk-reference $class $view) $reference
      (if (== $class no-class) (cons $view $kept)
         (if (fold-semidet (sk-outranked-step $reference) false $references) $kept
            (let $prior
                  (let* (($containing (fold-semidet (sk-class-prior-step $reference) () $references))
                         ((sk-val $specific-fact $specific-ev $_specific-deps) $view)
                         ($nearest (fold-semidet (sk-nearest-prior-step $rows $containing $specific-fact $specific-ev) () $containing)))
                     (sk-class-centre $specific-fact $specific-ev $nearest))
               (cons (case (data $view $prior) (
                  (((sk-val $fact $ev $deps) (sk-val $general $gev $gdeps))
                     (sk-specialized $fact $ev $deps $general $gev $gdeps))
                  ($_none $view))) $kept))))))

(: sk-class-group-step (-[semidet]-> SkeletonModeReader (List Number) (List SkeletonReference) SkeletonClassGroup (List SkeletonReference)))
(= (sk-class-group-step $modes $ignore $kept (sk-class-group $class $views))
   (let $values (fold-semidet sk-cons-step () $views)
      (case (fold-semidet (sk-pair-merge-step $modes false $ignore) (sk-merging sk-none () 0) $values) (
         ((sk-merging $merged () $_deps) (sk-class-view-step $class $kept $merged))
         ($_shared (fold-semidet (sk-class-view-step $class) $kept $values))))))

(: sk-sample-group-step (-[semidet]-> SkeletonSampleGrouping SkeletonSampleView SkeletonSampleGrouping))
(= (sk-sample-group-step $state (sk-sample-view $other-digests $other))
   (case $state (
      ((sk-sample-grouping $digests sk-none $groups)
         (sk-sample-grouping $digests sk-none (cons (sk-sample-view $other-digests $other) $groups)))
      ((sk-sample-grouping $digests $view $kept)
         (if (sk-same-samples? $digests $other-digests)
            (sk-sample-grouping () sk-none
               (cons (sk-sample-view (sk-join-digest-groups (cons $digests (cons $other-digests ())))
                         (sk-sibling-value false (STV 0.5 0.0) $view $other)) $kept))
            (sk-sample-grouping $digests $view (cons (sk-sample-view $other-digests $other) $kept)))))))

(: sk-sample-groups-step (-[semidet]-> (List SkeletonSampleView) SkeletonValue (List SkeletonSampleView)))
(= (sk-sample-groups-step $groups $view)
   (let (sk-sample-grouping $digests $remaining $pooled)
         (fold-semidet sk-sample-group-step (sk-sample-grouping (sk-value-digests $view) $view ()) $groups)
      (if (== $remaining sk-none) $pooled (cons (sk-sample-view $digests $remaining) $pooled))))

(: sk-sample-groups (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-sample-groups $views)
   (case (collapse (once (match &sk_rule_truth ($_id $_truth $_type $_ctx) true))) (
      (() $views)
      ((cons $_present $_more)
         (let $groups (fold-semidet sk-sample-groups-step () $views)
            (if (== (list-len $groups) (list-len $views)) $views
               (collapse (let (sk-sample-view $_digests $view) (superpose $groups) $view))))))))

;; A report's evidence is pooled before its likelihood ratio updates a
;; prediction. Applying several reports separately would multiply their odds
;; instead of performing ordinary evidence-weighted corroboration (#92).
(: sk-report-step (-[semidet]-> SkeletonModeReader (SkeletonValue (List SkeletonValue)) SkeletonValue (SkeletonValue (List SkeletonValue))))
(= (sk-report-step $modes ($report $others) $value)
   (case $value (
      ((sk-val ($_type $_ctx $proof (STV $_s $_c)) $_ev $_deps)
         (if (sk-report-proof? $proof)
            (data (sk-merge-step $modes false () $report $value) $others)
            (data $report (cons $value $others))))
      ($_other (data $report (cons $value $others))))))

(: sk-report-values (-[semidet]-> SkeletonModeReader (List SkeletonValue) (List SkeletonValue)))
(= (sk-report-values $modes $values)
   (if (fold-semidet sk-report-prior-step false $values)
      (let* ((($report $others) (fold-semidet (sk-report-step $modes) (data sk-none ()) $values))
             ($predictions (fold-semidet sk-cons-step () $others)))
         (if (== $report sk-none) $predictions (append-flat $predictions (cons $report ()))))
      $values))

(: sk-reference-values (-[semidet]-> SkeletonModeReader SkeletonRowReader (List Number) (List SkeletonValue) ((List SkeletonValue) Bool (List SkeletonReference))))
(= (sk-reference-values $modes $rows $ignore $values)
   (case $values (
      ((cons $_first (cons $_second $_rest))
         (let* (($original (map-semidet sk-reference-of $values))
                ($known (collapse (let (sk-reference $class $_view) (superpose $original)
                           (if (== $class no-class) (empty) true)))))
            (case $known (
               ((cons $_one (cons $_two $_others))
                  (let* (($references (fold-semidet (sk-class-group-step $modes $ignore) ()
                              (fold-flat sk-same-class-step () (sort-atom $original))))
                         ($selected (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-reference-step $rows $references) () $references))))
                     (data (sk-sample-groups $selected)
                        (if (< (list-len $selected) 2) false
                           (fold-semidet (sk-sibling-values-step $references) false $references)) $references)))
               ($_few (data $values false ()))))))
      ($_single (data $values false ())))))

(: sk-sibling-merge (-[semidet]-> SkeletonModeReader Bool SkeletonValue SkeletonValue SkeletonValue))
(= (sk-sibling-merge $modes $product $a $b)
   (let* (((sk-mode-reader $choose-fn) $modes)
          ($choose (the (-[semidet]-> KB Statement Atom) $choose-fn))
          ((sk-val ($type $ctx $_pa (STV $sa $ca)) $_ea $_da) $a)
          ((sk-val ($_tb $_cb $_pb (STV $sb $cb)) $_eb $_db) $b)
          ($odds? (if $product
                    (if (if (if (>= $ca 1) (>= $cb 1) false) (sk-contradict? $sa $sb) false) false true)
                    false))
          ($population (if $odds?
                     (let ($_mode $population) ($choose (brand KB (car-atom $ctx)) $type) (the STVType $population))
                     (STV 0.5 0.0))))
      (sk-sibling-value $odds? $population $a $b)))

(: sk-sibling-value (-[semidet]-> Bool STVType SkeletonValue SkeletonValue SkeletonValue))
(= (sk-sibling-value $odds? $population (sk-val ($type $ctx $proof-a (STV $sa $ca)) $ev-a $deps-a)
                     (sk-val ($_type $_ctx $proof-b (STV $sb $cb)) $ev-b $deps-b))
   (let* (($mode (if $odds? odds revision))
          ((STV $s $c) (if $odds? (sk-mode-step odds $population (STV $sa $ca) (STV $sb $cb))
                            (mergetvs (STV $sa $ca) (STV $sb $cb)))))
      (sk-val ($type $ctx (brand Proof (combination $mode (prior (if $odds? $population no-evidence))
                  (sort-atom (append-flat (sk-forward-parts $proof-a) (sk-forward-parts $proof-b)))))
                  (STV (if $odds?
                          (if (certain-at? 1.0 $sa $ca) 1.0 (if (certain-at? 1.0 $sb $cb) 1.0
                             (if (certain-at? 0.0 $sa $ca) 0.0 (if (certain-at? 0.0 $sb $cb) 0.0 $s)))) $s)
                       (min $c (min $ca $cb))))
         (evidence-union $ev-a $ev-b) (deps-union $deps-a $deps-b))))
;; Unresolved dependence uses the factored/product/revision estimate, discounted
;; by its log-odds distance from the larger count. Siblings keep their own bound.
(: sk-dependent-merge (-[semidet]-> SkeletonModeReader Bool SkeletonValue SkeletonValue SkeletonValue))
(= (sk-dependent-merge $modes $product $va $vb)
   (if (sk-siblings? false $va $vb) (sk-sibling-merge $modes $product $va $vb)
      (case (data $va $vb) (
         (((sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b))
            (let* (($factored (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b true))
                   ($pooled (evidence-union $ev-a $ev-b))
                   ($deps (deps-union $deps-a $deps-b))
                   ($combined (if (== $factored sk-none) (sk-combined-merge $modes $a $b $pooled $deps) $factored)))
               (sk-discounted (if (== $combined sk-none) (sk-val (RevisionMergeProof $a $b) $pooled $deps) $combined)
                  (sk-larger-count $va $vb) (min (term-confidence $a) (term-confidence $b)))))
         ($_other $va)))))

(: sk-pair-merge-step (-[semidet]-> SkeletonModeReader Bool (List Number) SkeletonMerging SkeletonValue SkeletonMerging))

;; Pairwise merging also records the first conditioning cut and its cost.
;; Its accumulated value is provisional: on overlap the key builds its
;; fallback from connected components of the original views below.
(= (sk-pair-merge-step $modes $combine $ignore (sk-merging $acc $keys $deps) $view)
   (case $acc (
      (sk-none (sk-merging $view $keys $deps))
      ((sk-val $fact $ev $fact-deps)
         (case $view (
            ((sk-val $other $other-ev $other-deps)
               (case (sk-pair-facts $modes $combine $ignore $fact $ev $fact-deps $other $other-ev $other-deps) (
                  ((sk-paired $merged) (sk-merging $merged $keys $deps))
                  ((sk-overlap $shared $shared-deps $fallback)
                     (if (== $keys ()) (sk-merging $fallback $shared $shared-deps) (sk-merging $fallback $keys $deps))))))
            ($_goal (sk-merging $acc $keys $deps)))))
      ($_goal (sk-merging $acc $keys $deps)))))

(: sk-merge-step (-[semidet]-> SkeletonModeReader Bool (List Number) SkeletonValue SkeletonValue SkeletonValue))

;; A merge outside a key's merge takes an overlap's fallback.
(= (sk-merge-step $modes $combine $ignore $acc $view)
   (case (sk-pair-merge-step $modes $combine $ignore (sk-merging $acc () 0) $view) (((sk-merging $merged $_keys $_deps) $merged))))

;; The merge of two connected views, or sk-none for views apart. The second's
;; dependencies and evidence are those of its whole component.
(: sk-fallback-pair (-[semidet]-> SkeletonModeReader (List Number) Number EvidenceSet SkeletonValue Number EvidenceSet SkeletonValue SkeletonValue))
(= (sk-fallback-pair $modes $ignore $view-deps $view-ev $best $other-deps $other-ev $other)
   (let* (($uncertain (fold-semidet (sk-shared-statement-step $ignore) false (deps-shared $view-deps $other-deps)))
          ($shared (if $uncertain true (== (evidence-observed-roles $view-ev $other-ev) observed)))
          ($siblings (sk-siblings? true $best $other))
          ;; A near-shared pair keeps the larger count while its claim waits:
          ;; combining it would count the shared statement twice in strength
          ;; (the forward cycle of test_forward_chainer went .6923 -> .7714).
          ;; The accumulated component's dependency union can put a key nearer
          ;; than in an original view; the actual key cut still requires two
          ;; original near views.
          ($near (if $uncertain
             (if $siblings false
                (not (== (sk-shared-statements $ignore (deps-near-shared (cons $view-deps (cons $other-deps ())))) ())))
             false)))
      (if (if $shared true $siblings)
         (if (if $near (if (sk-siblings? false $best $other) false true) false) (sk-larger-count $best $other)
            (sk-dependent-merge $modes (if $uncertain false
               (if $siblings (if (sk-sample-twins? $best $other) false true) false)) $best $other))
         sk-none)))

;; A component's kind is its original members' (all of one kind), not its
;; merged value's, so the order its members merged in does not change it.
(: sk-component-step (-[semidet]-> SkeletonModeReader (List Number) Bool Number EvidenceSet SkeletonConnecting SkeletonComponent SkeletonConnecting))
(= (sk-component-step $modes $ignore $kind $view-deps $view-ev (sk-connecting (sk-component $best $deps $ev $members) $apart) (sk-component $other $other-deps $other-ev (cons $first $rest)))
   (case (if (== $kind (sk-updates? $first))
            (sk-fallback-pair $modes $ignore $view-deps $view-ev $best $other-deps $other-ev $other) sk-none) (
      (sk-none (sk-connecting (sk-component $best $deps $ev $members) (cons (sk-component $other $other-deps $other-ev (cons $first $rest)) $apart)))
      ($merged (sk-connecting
                  (sk-component $merged (deps-union $deps $other-deps) (evidence-union $ev $other-ev) (append-flat $members (cons $first $rest)))
                  $apart)))))

(: sk-key-merge-step (-[semidet]-> SkeletonModeReader (List Number) (List SkeletonComponent) SkeletonReference (List SkeletonComponent)))
(= (sk-key-merge-step $modes $ignore $components (sk-reference $_class $view))
   (case $view (
      ((sk-val $_fact $ev $deps)
         (let* (($kind (sk-updates? $view))
                ((sk-connecting $connected $apart)
                   (fold-semidet (sk-component-step $modes $ignore $kind $deps $ev)
                      (sk-connecting (sk-component $view $deps $ev (cons $view ())) ()) $components)))
            (cons $connected $apart)))
      ($_goal $components))))

(: sk-overlap-confidence (-[semidet]-> SkeletonModeReader (List SkeletonReference) (List ReferenceClass) KB Statement Number Number Number))
(= (sk-overlap-confidence $modes $references $separators $kb $type $count $confidence)
   (let* (((sk-mode-reader $choose-fn) $modes)
          ($choose (the (-[semidet]-> KB Statement Atom) $choose-fn))
          (($_mode (STV $population $_pc)) ($choose $kb $type))
          ($classes (list_to_set (map-semidet sk-class-parts $separators)))
          ($links (collapse (let $parts (superpose $classes)
                     (if (== $parts ()) (empty)
                        (sk-separator-link $references (sk-class true $parts))))))
          ($range (sk-overlap-range $count (sk-link odds (the Number $population)) $links)))
      (/ $confidence (+ 1.0 (* $range $range)))))

;; This boundary keeps folds over typed list parameters in the strict compiler.
(: sk-sibling-family-value (-[semidet]-> SkeletonModeReader (List SkeletonReference) SkeletonValue (List SkeletonValue) (List ReferenceClass) SkeletonValue))
(= (sk-sibling-family-value $modes $references (sk-val ($type $ctx $proof (STV $s $c)) $ev $deps) $members $separators)
   (let $shared
         ;; A product is safe only after #68's shared uncertain inputs have
         ;; been conditioned. Unpaid revisions stay provisional.
         (case (sk-step-proof $proof) (
            ((combination odds $_prior $_parts)
               (case $separators (
                  ((cons (sk-class true (cons $part $rest)) ())
                     (collapse (sk-separator-value $references (sk-class true (cons $part $rest)))))
                  ($_unresolved ()))))
            ($_not-product ())))
      (case $shared (
         ((cons $general ())
            (sk-sibling-product (the SkeletonValue $general) (sk-val ($type $ctx $proof (STV $s $c)) $ev $deps) $members))
         (()
            (sk-val ($type $ctx $proof (STV $s (sk-overlap-confidence $modes $references $separators
                        (brand KB (car-atom $ctx)) $type (- (list-len $members) 1) $c))) $ev $deps))))))

(: sk-sibling-family (-[semidet]-> SkeletonModeReader (List SkeletonReference) SkeletonValue (List SkeletonValue) SkeletonValue))
(= (sk-sibling-family $modes $references $best $members)
   (case $members (
      ((cons $_only ()) $best)
      ($_multiple
         (let $family (fold-semidet append-flat () (map-semidet sk-family-references $members))
            (if (fold-semidet (sk-sibling-values-step $family) false $family)
               (let $separators (list_to_set (fold-semidet (sk-family-separators-step $family) () $family))
                  (sk-sibling-family-value $modes $references $best $members $separators))
               $best))))))

(: sk-component-order-of (-[semidet]-> SkeletonModeReader Bool (List SkeletonReference) SkeletonComponent SkeletonComponentOrder))
(= (sk-component-order-of $modes $predicted $references (sk-component $best $_deps $_ev $members))
   (let $view (sk-sibling-family $modes $references $best $members)
      (case $view (
         ((sk-val ($_type $_ctx $proof $_tv) $_ev2 $_deps2)
            (sk-component-order (if (sk-updates? $view) 1 (if $predicted (if (sk-report-proof? $proof) 2 0) 0)) $view))
         ($_goal (empty))))))

(: sk-component-merge-step (-[semidet]-> SkeletonModeReader (List Number) SkeletonValue SkeletonComponentOrder SkeletonValue))
(= (sk-component-merge-step $modes $ignore $acc (sk-component-order $order $view))
   (case (if (== $order 1)
            (case (data $acc $view) (
               (((sk-val $_a $acc-ev $acc-deps) (sk-val $_v $view-ev $view-deps))
                  (sk-fallback-pair $modes $ignore $acc-deps $acc-ev $acc $view-deps $view-ev $view))
               ($_none sk-none)))
            sk-none) (
      (sk-none (sk-merge-step $modes true $ignore $acc $view))
      ($merged $merged))))

(: sk-key-fallback (-[semidet]-> SkeletonModeReader (List Number) (List SkeletonReference) (List SkeletonValue) SkeletonValue))
(= (sk-key-fallback $modes $ignore $references $views)
   ;; Combine independent values before applying the updates they are priors
   ;; for. Canonical ordering also fixes confidence ties and floating-point
   ;; fold order, regardless of the order the original views were visited.
   (let $predicted (fold-semidet sk-report-prior-step false $views)
      (fold-semidet (sk-component-merge-step $modes $ignore) sk-none
         (sort-atom (map-semidet (sk-component-order-of $modes $predicted $references)
            (fold-semidet (sk-key-merge-step $modes $ignore) () (sort-atom (map-semidet sk-reference-of (sk-report-values $modes $views)))))))))
;; Compare evidence containment before combining independent views. Shared uncertain
;; statements request conditioning; unresolved overlap keeps a provisional value.
;; Given facts and rule parameters do not create observational dependence.
;; See docs/metta/overlap_conditioning.md and prior_factored_merge.md.
(: sk-pair-facts (-[semidet]-> SkeletonModeReader Bool (List Number) SkFact EvidenceSet Number SkFact EvidenceSet Number SkeletonPairing))
;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof and a complete step to the settled
;; step that decides it. Two views are compared by one relation over their evidence without the
;; certain facts (a certain fact is given, whoever reads it and in which role:
;; views sharing it are independent given it) and over the uncertain statements
;; both depend on:
;; - contained: one's evidence, and every given it used, lies within the other's;
;;   the container stands for both;
;; - conditionable: they share uncertain statements, which the key's merge
;;   conditions on, or reads as fixed marginals when they lie deeper;
;; - overlapping: they share uncertain evidence with nothing left to condition
;;   on; they revise counting the shared evidence once;
;; - independent: none of these. They combine by the prior they update, by the
;;   mode their predicate's outcomes prefer, or by revision.
;; Rules are parameters: sharing one makes no dependence, but a rule's axiom is
;; contained in a proof through it, and a ground given rule is named (its
;; applications carry its entry), so a view that never applied it does not
;; contain one that did. Confidence selects only between estimates of one
;; quantity (twins, equal evidence), near-shared pairs waiting for their claim,
;; and the provisional overlap value. A
;; dominated view contributes neither evidence nor dependencies. The ignored
;; hashes are the merged key's, those of the keys unifying with it, those the
;; reader excludes and the statements given.
(= (sk-pair-facts $modes $combine $ignore $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-fact-step-proof $a))
          ($proof-b (sk-fact-step-proof $b))
          (($_ta $_ca $_pa $tv-a) $a)
          (($_tb $_cb $_pb $tv-b) $b)
          ($va (sk-val $a $ev-a $deps-a))
          ($vb (sk-val $b $ev-b $deps-b)))
      (if (if (== $a $b) true
             (if (== $tv-a $tv-b)
                (if (== $ev-a $ev-b) (same-proof? $proof-a $proof-b) false)
                false))
         (sk-paired (sk-val $a (evidence-union $ev-a $ev-b) (if (== $a $b) $deps-a (deps-union $deps-a $deps-b))))
         (if (proof-dominates? $proof-a $proof-b) (sk-paired $va)
            (if (proof-dominates? $proof-b $proof-a) (sk-paired $vb)
            (if (specialization-includes? $proof-a $proof-b) (sk-paired $va)
            (if (specialization-includes? $proof-b $proof-a) (sk-paired $vb)
            (if (if (more-specific-application? $proof-a $proof-b) (if $combine (if (sk-siblings? true $va $vb) false true) true) false) (sk-paired (sk-specialized $a $ev-a $deps-a $b $ev-b $deps-b))
            (if (if (more-specific-application? $proof-b $proof-a) (if $combine (if (sk-siblings? true $va $vb) false true) true) false) (sk-paired (sk-specialized $b $ev-b $deps-b $a $ev-a $deps-a))
               (let* (;; Views sharing uncertain evidence, or a certain fact both
                      ;; observed, are dependent; views sharing only certain facts
                      ;; one of them read as a condition are independent given
                      ;; them. Of dependent views, one whose evidence, certain
                      ;; facts included, lies within the other's, with every given
                      ;; it used, stands for both. Views apart that share uncertain
                      ;; evidence through uncertain statements both read are
                      ;; partial computations of one posterior: they condition on
                      ;; those statements. Views apart that share no statement
                      ;; are taken as independent until conditioning on entries
                      ;; (design step 4) covers them.
                      ($overlap (evidence-uncertain-overlap? $ev-a $ev-b))
                      ($roles (if $overlap roles-pending (evidence-observed-roles $ev-a $ev-b)))
                      ($touch (if $overlap true (== $roles observed)))
                      ($a-in-b (if $touch (if (evidence-subset? $ev-a $ev-b) (hash-subset? (deps-excluded $ignore $deps-a) (deps-excluded $ignore $deps-b)) false) false))
                      ($b-in-a (if $touch (if (evidence-subset? $ev-b $ev-a) (hash-subset? (deps-excluded $ignore $deps-b) (deps-excluded $ignore $deps-a)) false) false))
                      ($contained (if $a-in-b true $b-in-a))
                      ($shared (if $contained () (if $overlap (sk-shared-statements $ignore (deps-shared $deps-a $deps-b)) ())))
                      ($independent (if $contained false
                         (== $shared ())))
                      ($observed (if $independent
                         (case (if (== $roles roles-pending) (evidence-observed-roles $ev-a $ev-b) $roles) (
                            (no-shared false)
                            (observed true)
                            (a-condition (not (== (sk-forward-parts $proof-a) ())))
                            (b-condition (not (== (sk-forward-parts $proof-b) ()))))) false))
                      ($twins
                         (if $independent
                            (if (sk-derivation-proof? $proof-a) (if (sk-derivation-proof? $proof-b) (sk-sample-twins? $va $vb) false) false)
                            false))
                      ($factored (if $twins sk-none (if $observed sk-none
                                    (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b $independent))))
                      ($siblings (if (== $factored sk-none)
                                    (if $combine (if (== $shared ())
                                       (sk-siblings? true $va $vb) false) false)
                                    false)))
                  ;; Twins are one estimate from the same samples: as for equal
                  ;; evidence, the larger count holds it.
                  (if $twins (sk-paired (sk-larger-count $va $vb))
                  (if (not (== $factored sk-none)) (sk-paired $factored)
                     (if $siblings (sk-paired (sk-sibling-merge $modes true $va $vb))
                     (if (if $independent false (sk-zero-update? $a $b)) (sk-paired $va)
                     (if (if $independent false (sk-zero-update? $b $a)) (sk-paired $vb)
                     (if $independent
                        (let* (($pooled (evidence-union $ev-a $ev-b))
                               ($deps (deps-union $deps-a $deps-b))
                               ($combined (if $combine (if $observed sk-none (sk-combined-merge $modes $a $b $pooled $deps)) sk-none)))
                           (sk-paired
                              (if (not (== $combined sk-none)) $combined
                                 (sk-val (RevisionMergeProof $a $b) $pooled $deps))))
                        (if (if $a-in-b (if $b-in-a false true) false) (sk-paired $vb)
                           (if (if $b-in-a (if $a-in-b false true) false) (sk-paired $va)
                              ;; Equal recorded evidence: the estimate with the larger
                              ;; count holds all of it and stands for both.
                              (if (if $a-in-b $b-in-a false)
                                 (sk-paired (sk-larger-count $va $vb))
                              (if (== $shared ()) (sk-paired (sk-dependent-merge $modes false $va $vb))
                                 ;; Provisional: the key's merge replaces it by its
                                 ;; component fallback. Merges outside a key's own
                                 ;; (premise reads) keep the larger count: combining
                                 ;; here moved pln-reliable .0511 -> .0698.
                                 (sk-overlap $shared (deps-union $deps-a $deps-b)
                                    (sk-larger-count $va $vb))))))))))))))))))))))
