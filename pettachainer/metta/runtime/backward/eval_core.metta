;; The recursive evaluator: reads, rows, conditioning, merges and folds.
;; Keep this strongly connected component in one plain-import compiler unit.

(: sk-computed-centre (-[semidet]-> KB Statement SourceList (List Number) OptionalSTV))
(= (sk-computed-centre $kb $pattern $sources $exclude)
   (let $left-out (hash-union $exclude (hash-set (observation-keys $sources)))
      (case (base-rate-premises $kb $pattern $_rate) (
         ((cons (CPU FoldAllCompiled $args $_result) ())
            (let* (((cons (fa-subscription $identity $descriptor $_triggers) ())
                      (fa-premise-subscriptions (CPU FoldAllCompiled $args $_out)))
                   ($id (fa-id $identity))
                   ($group (quote (aggregate-support $id))))
               (if (likelihood-support-admissible? $group $sources)
                  (let* (($state (fold-flat fa-subtract-step (fa-state $id) (fa-left-out $id $left-out)))
                         ((forward-aggregate-state $_id $_sum $_mass $members) $state))
                     (if (> $members 0)
                        (let (STV $g $gc) (fa-result $descriptor $state) (STV $g $gc))
                        (empty)))
                  (empty))))
         ;; A compound's centre is the prior every other reader reads.
         ((cons (CPU CompoundRate $rate-args $rate-res) ())
            (if (sk-admissible-step $sources true (CPU CompoundRate $rate-args $rate-res))
               (case (sk-value (sk-prior $rate-args) sk-any-filter $left-out) (
                  ((sk-goal-val (CPU $_fun $_args (STV $s $c)) $_proof $_ev $_deps) (STV $s $c))
                  ($_none (empty))))
               (empty)))))))

;; The watch already applied the row's cuts. Additional observation cuts
;; use the same cached fold evaluator, never a separate raw-tally snapshot.
(: sk-rate-read (-[semidet]-> KB Statement TV RatePlan (List Number) (List Number) TV))
(= (sk-rate-read $kb $pattern $raw (rate-plan $goals $result) $exclude $observations)
   (if (hash-subset? $observations $exclude) $raw
      (if (== $raw no-evidence) no-evidence
         (if (user-base-rate? $kb $pattern) $raw
            (case (fold-semidet
                      (sk-premise-step () () (hash-union $exclude $observations) false false sk-greedy-read)
                      (sk-acc () (ev-set 0) ()) $goals) (
               ((sk-acc $_proofs $_ev $_deps) (the TV $result))
               ($_missing (STV 0.5 0))))))))

(: sk-evidence-view (-[semidet]-> Number $spec (List Number) SkeletonValue))
(= (sk-evidence-view $hash $args $exclude)
   (let* ((($kb $ktype $_ctype $kbctx) $args)
          ($compound (sk-key $ktype $kbctx))
          ($_use (sk-add-use! $compound (sk-evidence $args)))
          ($apart (sk-evidence-apart $args $exclude)))
      (if (if (== (sk-key-leaves $compound sk-any-filter) ()) (== (sk-evidence-rows $args) ()) false)
         sk-none
         (case (sk-premise-value false (sk-value $compound sk-any-filter $apart)) (
            ((sk-val ($_type $_kbctx $proof $tv) $ev $deps)
               (case (collapse (once (sk-observation-prior (brand KB $kb) (the Proof $proof) (the TV $tv) false))) (
                  ((cons $formed ())
                     (sk-goal-val (CPU CompoundEvidence $args (key-evidence $tv $formed $proof))
                        $proof $ev (deps-join (cons (deps-key $hash) (cons (deps-key (index-hash $compound)) (cons $deps ()))))))
                  (() sk-none))))
            ($_none sk-none))))))

;; A compound's prior (#142), computed from the keys its goals read, once per
;; pattern, and recomputed when one of them changes: each is used by the key
;; (&sk_use), so its change checks the key, whose readers change only with its
;; value. A reader excluding keys an input leaves out gets it computed again
;; without them. Like a base rate it carries no member evidence; it carries its
;; inputs' dependencies, so no base rate it reads counts a value derived
;; through it.
(: sk-prior-view (-[semidet]-> Number $spec (List Number) SkeletonValue))
(= (sk-prior-view $hash $args $exclude)
   (let* (($goals (compound-rate-goals $args false $rate))
          ($_uses (fold-flat (sk-use-step! (sk-prior $args)) () (sk-prior-inputs $goals))))
      (case (fold-semidet (sk-premise-step () () $exclude false false sk-greedy-read) (sk-acc () (ev-set 0) ()) $goals) (
         ((sk-acc $_proofs $_ev $deps)
            (sk-goal-val (CPU CompoundRate $args (the TV $rate)) (brand Proof cpu) (ev-set 0) (deps-join (cons (deps-key $hash) $deps))))
         ($_missing sk-none)))))
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
                                  (case (collapse (once (sk-computed-centre $kb $consequent
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

;; A premise of a forward rule applied to stored facts: a ground statement
;; reads its stored facts merged, adding their evidence; a computation runs; a
;; refined rule's truth is its key's current value, so its applications are
;; scored with what it learned, not with its prior. A fold, any other open
;; statement, a missing fact or a settled variant gives no view.
(: sk-stored-premise-step (-[semidet]-> EvidenceSet Atom EvidenceSet))
(= (sk-stored-premise-step $ev $premise)
   (case $premise (
      ((CPU $fun $args $res)
         (if (if (aggregate-fold-function? $fun) true (== $fun SettlesFormula)) (empty)
            (case (collapse (once (cpu-call 0 $fun $args))) (
               ((cons $result $_rest) (if (= $res $result) $ev (empty)))))))
      (($type $kbctx $proof $tv)
         (if (if (head-is? $type RuleTruth) (= $type (RuleTruth $_implication)) false)
            (case (sk-value (sk-key $type $kbctx) sk-any-filter ()) (
               ((sk-val ($_type $_kbctx $truth-proof $truth) $truth-ev $_deps)
                  (if (= ($proof $tv) ($truth-proof $truth)) (evidence-union $truth-ev $ev) (empty)))
               ($_none (empty))))
            (if (== (extract-vars $type) ())
               (case (stored-statement-candidate (brand Statement $type) (brand KBContext $kbctx) false) (
                  ((forward-derived ($_stype $_skbctx $stored-proof $stored-tv) $stored-ev)
                     (if (= ($proof $tv) ($stored-proof $stored-tv)) (evidence-union $stored-ev $ev) (empty)))))
               (empty)))))))

;; The views the forward rules concluding a statement give from its
;; antecedents' stored facts, when there are several and their evidence is
;; disjoint.
(: sk-outcome-views (-[det]-> Atom Atom (List STVType)))
(= (sk-outcome-views $type $kbctx)
   (case (collapse (once
         (let* (($views (collapse (match ccls_index (($type $kbctx (by $rule $premise) $tv) $_id $args)
                          (let $ev (fold-semidet sk-stored-premise-step (ev-set 0) $args)
                             (sk-val (assemble-runtime-fact $type $kbctx (by $rule $premise) $tv) $ev 0)))))
                ($references (map-semidet sk-reference-of $views))
                ($specific (fold-semidet (sk-reference-step false () $references) () $references)))
            (fold-semidet sk-disjoint-view-step (data () (ev-set 0)) (sk-sample-groups $specific))))) (
      ((cons $found $_none)
         (case $found (
            (((cons $_one ()) $_seen) ())
            (($tvs $_evidence) (the (List STVType) $tvs)))))
      (() ()))))

;; An outcome is predicted by each mode from its views and the prior before
;; it, then counted in the prior.
(: sk-score-outcome (-[semidet]-> CombinationTally Atom CombinationTally))
(= (sk-score-outcome (combination-tally $n $sum $revision $odds $noisy) ($type $kbctx $_proof (STV $outcome $_c)))
   (let* (($y (the Number $outcome))
          ($prior (STV (/ (+ $sum 1.0) (+ $n 2.0)) (count-confidence $n))))
      (case (sk-outcome-views $type $kbctx) (
         ((cons $first $rest)
            (combination-tally (+ $n 1) (+ $sum $y)
               (+ $revision (sk-log-score $y (fold-semidet mergetvs $first $rest)))
               (+ $odds (sk-log-score $y (fold-semidet (sk-mode-step odds $prior) $first $rest)))
               (+ $noisy (sk-log-score $y (fold-semidet (sk-mode-step noisy-or $prior) $first $rest)))))
         (() (combination-tally (+ $n 1) (+ $sum $y) $revision $odds $noisy))))))

;; The mode a consequent's outcomes prefer, with its prior: the better product
;; mode once its Bayes factor over revision is at least 10, else revision.
;; Pending outcomes are scored first.
(: sk-combination-mode (-[semidet]-> KB Statement Atom))
(= (sk-combination-mode $kb $type)
   (let* (($head (if (is-expr $type) (car-atom $type) $type))
          ($hash (index-hash (quote ($kb $head))))
          ($stored (case (collapse (match &combination_tally ($hash $kb $head $tally) $tally)) (
                      ((cons $found $_rest) $found)
                      (() (combination-tally 0 0.0 0.0 0.0 0.0)))))
          ($pending (collapse (match &combination_pending ($hash $kb $head $outcome) $outcome)))
          ($current
             (if (== $pending ()) $stored
                (let* (($scored (fold-semidet sk-score-outcome $stored $pending))
                       ($_drained (remove-data-rows! &combination_pending (quote ($hash $kb $head $_outcome))))
                       ($_old (remove-data-rows! &combination_tally (quote ($hash $kb $head $_tally))))
                       ($_new (add-space-atom! &combination_tally (make-space-row4 $hash $kb $head $scored))))
                   $scored))))
      (case $current (
         ((combination-tally $n $sum $revision $odds $noisy)
            (let $prior (STV (/ (+ $sum 1.0) (+ $n 2.0)) (count-confidence $n))
               (if (>= $odds $noisy)
                  (if (>= (- $odds $revision) 2.302585092994046) (data odds $prior) (data revision $prior))
                  (if (>= (- $noisy $revision) 2.302585092994046) (data noisy-or $prior) (data revision $prior)))))))))

;; Disjoint forward views of a consequent whose outcomes prefer a product mode
;; combine by it; two certain views that contradict each other revise.
(: sk-combined-merge (-[det]-> SkFact SkFact EvidenceSet Number SkeletonValue))
(= (sk-combined-merge ($type $kbctx $proof-a $tv-a) ($_btype $_bkbctx $proof-b $tv-b) $ev $deps)
   (let* (($parts-a (sk-forward-parts $proof-a)) ($parts-b (sk-forward-parts $proof-b)))
      (if (if (== $parts-a ()) true (== $parts-b ())) sk-none
         (case (collapse (once (sk-combination-mode (brand KB (car-atom $kbctx)) $type))) (
            ((cons $choice $_none)
               (case (data $choice $tv-a $tv-b) (
                  ((($mode (STV $sp $cp)) (STV $sa $ca) (STV $sb $cb))
                     (if (if (== $mode revision) true (sk-contradict? (the Number $sa) (the Number $sb))) sk-none
                        (sk-val ($type $kbctx (brand Proof (combination $mode (prior (STV $sp $cp)) (append-flat $parts-a $parts-b)))
                                    (sk-factored-tv $mode (the Number $sp) (the Number $cp) (the Number $sp) (the Number $cp) (the Number $sa) (the Number $ca) (the Number $sb) (the Number $cb)))
                           $ev $deps)))
                  ($_revision sk-none))))
            (() sk-none))))))

;; The target conditioned in turn on each of a compound's parts, under the
;; compound's own condition: each part weighs by its value given the compound
;; and the parts before it, so the branches hold only the joint states the
;; compound allows. Where a mix is not possible the target is read once.
(: sk-chain-value (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) SkeletonValue))
(= (sk-chain-value $given $target $wexclude $parts)
   (case $parts (
      (() (sk-target-value $given $target))
      ((cons $part $rest)
         (let* (($phash (index-hash $part))
                ($yes (sk-chain-value (cons (sk-given $phash $part true) $given) $target $wexclude $rest))
                ($no (sk-chain-value (cons (sk-given $phash $part false) $given) $target $wexclude $rest)))
            (case (collapse (once (sk-mix (sk-chain-weight $given $wexclude $part) $yes $no))) (
               ((cons $mixed $_others) $mixed)
               (() (sk-target-value $given $target)))))))))

;; A part's weight: its value under the condition, or, where the condition
;; leaves it uninformed (a false conjunct's sibling), its prior.
(: sk-chain-weight (-[semidet]-> (List SkeletonGiven) (List Number) SkeletonKey SkeletonValue))
(= (sk-chain-weight $given $wexclude $part)
   (case (sk-given-value $given $part sk-any-filter $wexclude) (
      (sk-none
         (case (sk-part-prior $part (ev-set 0) $wexclude) (
            (sk-none
               (case $part (
                  ((sk-key $type $kbctx) (sk-val (assemble-runtime-fact $type $kbctx (brand Proof cpu) (STV 0.5 0.0)) (ev-set 0) 0))
                  ($_fold sk-none))))
            ($prior $prior))))
      ($weight $weight))))

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof and a settled step to its complete
;; one. Two views are compared by one relation over their evidence without the
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
(= (sk-merge-facts $combine $ignore $a $ev-a $deps-a $b $ev-b $deps-b)
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
                     (if $siblings (sk-paired (sk-sibling-merge true $va $vb))
                     (if (if $independent false (sk-zero-update? $a $b)) (sk-paired $va)
                     (if (if $independent false (sk-zero-update? $b $a)) (sk-paired $vb)
                     (if $independent
                        (let* (($pooled (evidence-union $ev-a $ev-b))
                               ($deps (deps-union $deps-a $deps-b))
                               ($combined (if $combine (if $observed sk-none (sk-combined-merge $a $b $pooled $deps)) sk-none)))
                           (sk-paired
                              (if (not (== $combined sk-none)) $combined
                                 (sk-val (RevisionMergeProof $a $b) $pooled $deps))))
                        (if (if $a-in-b (if $b-in-a false true) false) (sk-paired $vb)
                           (if (if $b-in-a (if $a-in-b false true) false) (sk-paired $va)
                              ;; Equal recorded evidence: the estimate with the larger
                              ;; count holds all of it and stands for both.
                              (if (if $a-in-b $b-in-a false)
                                 (sk-paired (sk-larger-count $va $vb))
                              (if (== $shared ()) (sk-paired (sk-dependent-merge false $va $vb))
                                 ;; Provisional: the key's merge replaces it by its
                                 ;; component fallback. Merges outside a key's own
                                 ;; (premise reads) keep the larger count: combining
                                 ;; here moved pln-reliable .0511 -> .0698.
                                 (sk-overlap $shared (deps-union $deps-a $deps-b)
                                    (sk-larger-count $va $vb))))))))))))))))))))))

;; Re-evaluating the selected general reads its learned fold under the
;; specific's sample exclusions (sk-tally-without). A missing read is the only
;; reason to omit it; the already-selected frontier never promotes ancestors.
(: sk-class-without (-[semidet]-> SkFact EvidenceSet SkeletonValue SkeletonValue))
(= (sk-class-without $specific $specific-ev $general)
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
                              (let $value (sk-row-view () $cuts $hash $key $rhash (copy_term $row))
                                 (case $value (
                                    ((sk-val $_fact $new-ev $_new-deps)
                                       (if (premise-evidence-overlap? $specific-ev $new-ev) (empty) $value))
                                    ($_none (empty)))))
                              (empty))))))))))))
      ($_none sk-none))))

(: sk-nearest-prior-step (-[semidet]-> (List SkeletonReference) SkFact EvidenceSet (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-nearest-prior-step $references $specific $specific-ev $kept (sk-reference $class $view))
   (if (fold-semidet (sk-outranked-step (sk-reference $class $view)) false $references)
      $kept
      (case (sk-class-without $specific $specific-ev $view) (
         (sk-none $kept)
         ($independent (cons $independent $kept))))))

(: sk-reference-step (-[semidet]-> Bool (List Number) (List SkeletonReference) (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-reference-step $prior? $ignore $references $kept $reference)
   (let (sk-reference $class $view) $reference
      (if (== $class no-class) (cons $view $kept)
         (if (fold-semidet (sk-outranked-step $reference) false $references) $kept
            (let $prior (if $prior?
                  (let* (($containing (fold-semidet (sk-class-prior-step $reference) () $references))
                         ((sk-val $specific-fact $specific-ev $_specific-deps) $view)
                         ($nearest (fold-semidet (sk-nearest-prior-step $containing $specific-fact $specific-ev) () $containing)))
                     (sk-class-centre $specific-fact $specific-ev $nearest)) sk-none)
               (cons (case (data $view $prior) (
                  (((sk-val $fact $ev $deps) (sk-val $general $gev $gdeps))
                     (sk-specialized $fact $ev $deps $general $gev $gdeps))
                  ($_none $view))) $kept))))))

(: sk-class-group-step (-[semidet]-> (List Number) (List SkeletonReference) SkeletonClassGroup (List SkeletonReference)))
(= (sk-class-group-step $ignore $kept (sk-class-group $class $views))
   (let $values (fold-semidet sk-cons-step () $views)
      (case (fold-semidet (sk-pair-merge-step false $ignore) (sk-merging sk-none () 0) $values) (
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
                         (sk-sibling-merge false $view $other)) $kept))
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
(: sk-report-step (-[semidet]-> (SkeletonValue (List SkeletonValue)) SkeletonValue (SkeletonValue (List SkeletonValue))))
(= (sk-report-step ($report $others) $value)
   (case $value (
      ((sk-val ($_type $_ctx $proof (STV $_s $_c)) $_ev $_deps)
         (if (sk-report-proof? $proof)
            (data (sk-merge-step false () $report $value) $others)
            (data $report (cons $value $others))))
      ($_other (data $report (cons $value $others))))))

(: sk-report-values (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-report-values $values)
   (if (fold-semidet sk-report-prior-step false $values)
      (let* ((($report $others) (fold-semidet sk-report-step (data sk-none ()) $values))
             ($predictions (fold-semidet sk-cons-step () $others)))
         (if (== $report sk-none) $predictions (append-flat $predictions (cons $report ()))))
      $values))

(: sk-reference-values (-[semidet]-> (List Number) (List SkeletonValue) ((List SkeletonValue) Bool (List SkeletonReference))))
(= (sk-reference-values $ignore $values)
   (case $values (
      ((cons $_first (cons $_second $_rest))
         (let* (($original (map-semidet sk-reference-of $values))
                ($known (collapse (let (sk-reference $class $_view) (superpose $original)
                           (if (== $class no-class) (empty) true)))))
            (case $known (
               ((cons $_one (cons $_two $_others))
                  (let* (($references (fold-semidet (sk-class-group-step $ignore) ()
                              (fold-flat sk-same-class-step () (sort-atom $original))))
                         ($selected (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-reference-step true $ignore $references) () $references))))
                     (data (sk-sample-groups $selected)
                        (if (< (list-len $selected) 2) false
                           (fold-semidet (sk-sibling-values-step $references) false $references)) $references)))
               ($_few (data $values false ()))))))
      ($_single (data $values false ())))))

(: sk-sibling-merge (-[semidet]-> Bool SkeletonValue SkeletonValue SkeletonValue))
(= (sk-sibling-merge $product (sk-val ($type $ctx $proof-a (STV $sa $ca)) $ev-a $deps-a)
                     (sk-val ($_type $_ctx $proof-b (STV $sb $cb)) $ev-b $deps-b))
   (let* (($odds? (if $product
                    (if (if (if (>= $ca 1) (>= $cb 1) false) (sk-contradict? $sa $sb) false) false true)
                    false))
          ($population (if $odds?
                     (let ($_mode $population) (sk-combination-mode (brand KB (car-atom $ctx)) $type) (the STVType $population))
                     (STV 0.5 0.0)))
          ($mode (if $odds? odds revision))
          ((STV $s $c) (if $odds? (sk-mode-step odds $population (STV $sa $ca) (STV $sb $cb))
                            (mergetvs (STV $sa $ca) (STV $sb $cb)))))
      (sk-val ($type $ctx (brand Proof (combination $mode (prior (if $odds? $population no-evidence))
                  (sort-atom (append-flat (sk-forward-parts $proof-a) (sk-forward-parts $proof-b)))))
                  (STV (if $odds?
                          (if (certain-at? 1.0 $sa $ca) 1.0 (if (certain-at? 1.0 $sb $cb) 1.0
                             (if (certain-at? 0.0 $sa $ca) 0.0 (if (certain-at? 0.0 $sb $cb) 0.0 $s)))) $s)
                       (min $c (min $ca $cb))))
         (evidence-union $ev-a $ev-b) (deps-union $deps-a $deps-b))))

;; Dependent views that cannot be conditioned (unpaid, or with nothing to
;; condition on) read what they share as fixed marginal inputs: a prior and
;; its update combine by factored odds, other views as independent by the mode
;; their predicate prefers, else revision, and the confidence is discounted by
;; the log-odds range to the larger count (#49: c_min/(1+R^2), R >= 1), so the
;; shared evidence buys no confidence. Sibling forward views keep their own
;; conservative combination. No view is selected.
(: sk-dependent-merge (-[semidet]-> Bool SkeletonValue SkeletonValue SkeletonValue))
(= (sk-dependent-merge $product $va $vb)
   (if (sk-siblings? false $va $vb) (sk-sibling-merge $product $va $vb)
      (case (data $va $vb) (
         (((sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b))
            (let* (($factored (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b true))
                   ($pooled (evidence-union $ev-a $ev-b))
                   ($deps (deps-union $deps-a $deps-b))
                   ($combined (if (== $factored sk-none) (sk-combined-merge $a $b $pooled $deps) $factored)))
               (sk-discounted (if (== $combined sk-none) (sk-val (RevisionMergeProof $a $b) $pooled $deps) $combined)
                  (sk-larger-count $va $vb) (min (term-confidence $a) (term-confidence $b)))))
         ($_other $va)))))
(: sk-pair-merge-step (-[semidet]-> Bool (List Number) SkeletonMerging SkeletonValue SkeletonMerging))

;; Pairwise merging also records the first conditioning cut and its cost.
;; Its accumulated value is provisional: on overlap the key builds its
;; fallback from connected components of the original views below.
(= (sk-pair-merge-step $combine $ignore (sk-merging $acc $keys $deps) $view)
   (case $acc (
      (sk-none (sk-merging $view $keys $deps))
      ((sk-val $fact $ev $fact-deps)
         (case $view (
            ((sk-val $other $other-ev $other-deps)
               (case (sk-merge-facts $combine $ignore $fact $ev $fact-deps $other $other-ev $other-deps) (
                  ((sk-paired $merged) (sk-merging $merged $keys $deps))
                  ((sk-overlap $shared $shared-deps $fallback)
                     (if (== $keys ()) (sk-merging $fallback $shared $shared-deps) (sk-merging $fallback $keys $deps))))))
            ($_goal (sk-merging $acc $keys $deps)))))
      ($_goal (sk-merging $acc $keys $deps)))))
(: sk-merge-step (-[semidet]-> Bool (List Number) SkeletonValue SkeletonValue SkeletonValue))

;; A merge outside a key's merge takes an overlap's fallback.
(= (sk-merge-step $combine $ignore $acc $view)
   (case (sk-pair-merge-step $combine $ignore (sk-merging $acc () 0) $view) (((sk-merging $merged $_keys $_deps) $merged))))

;; The merge of two connected views, or sk-none for views apart. The second's
;; dependencies and evidence are those of its whole component.
(: sk-fallback-pair (-[semidet]-> (List Number) Number EvidenceSet SkeletonValue Number EvidenceSet SkeletonValue SkeletonValue))
(= (sk-fallback-pair $ignore $view-deps $view-ev $best $other-deps $other-ev $other)
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
            (sk-dependent-merge (if $uncertain false
               (if $siblings (if (sk-sample-twins? $best $other) false true) false)) $best $other))
         sk-none)))

;; A component's kind is its original members' (all of one kind), not its
;; merged value's, so the order its members merged in does not change it.
(: sk-component-step (-[semidet]-> (List Number) Bool Number EvidenceSet SkeletonConnecting SkeletonComponent SkeletonConnecting))
(= (sk-component-step $ignore $kind $view-deps $view-ev (sk-connecting (sk-component $best $deps $ev $members) $apart) (sk-component $other $other-deps $other-ev (cons $first $rest)))
   (case (if (== $kind (sk-updates? $first))
            (sk-fallback-pair $ignore $view-deps $view-ev $best $other-deps $other-ev $other) sk-none) (
      (sk-none (sk-connecting (sk-component $best $deps $ev $members) (cons (sk-component $other $other-deps $other-ev (cons $first $rest)) $apart)))
      ($merged (sk-connecting
                  (sk-component $merged (deps-union $deps $other-deps) (evidence-union $ev $other-ev) (append-flat $members (cons $first $rest)))
                  $apart)))))

(: sk-key-merge-step (-[semidet]-> (List Number) (List SkeletonComponent) SkeletonReference (List SkeletonComponent)))
(= (sk-key-merge-step $ignore $components (sk-reference $_class $view))
   (case $view (
      ((sk-val $_fact $ev $deps)
         (let* (($kind (sk-updates? $view))
                ((sk-connecting $connected $apart)
                   (fold-semidet (sk-component-step $ignore $kind $deps $ev)
                      (sk-connecting (sk-component $view $deps $ev (cons $view ())) ()) $components)))
            (cons $connected $apart)))
      ($_goal $components))))

(: sk-overlap-confidence (-[semidet]-> (List SkeletonReference) (List ReferenceClass) KB Statement Number Number Number))
(= (sk-overlap-confidence $references $separators $kb $type $count $confidence)
   (let* ((($_mode (STV $population $_pc)) (sk-combination-mode $kb $type))
          ($classes (list_to_set (map-semidet sk-class-parts $separators)))
          ($links (collapse (let $parts (superpose $classes)
                     (if (== $parts ()) (empty)
                        (sk-separator-link $references (sk-class true $parts))))))
          ($range (sk-overlap-range $count (sk-link odds (the Number $population)) $links)))
      (/ $confidence (+ 1.0 (* $range $range)))))

;; This boundary keeps folds over typed list parameters in the strict compiler.
(: sk-sibling-family-value (-[semidet]-> (List SkeletonReference) SkeletonValue (List SkeletonValue) (List ReferenceClass) SkeletonValue))
(= (sk-sibling-family-value $references (sk-val ($type $ctx $proof (STV $s $c)) $ev $deps) $members $separators)
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
            (sk-val ($type $ctx $proof (STV $s (sk-overlap-confidence $references $separators
                        (brand KB (car-atom $ctx)) $type (- (list-len $members) 1) $c))) $ev $deps))))))

(: sk-sibling-family (-[semidet]-> (List SkeletonReference) SkeletonValue (List SkeletonValue) SkeletonValue))
(= (sk-sibling-family $references $best $members)
   (case $members (
      ((cons $_only ()) $best)
      ($_multiple
         (let $family (fold-semidet append-flat () (map-semidet sk-family-references $members))
            (if (fold-semidet (sk-sibling-values-step $family) false $family)
               (let $separators (list_to_set (fold-semidet (sk-family-separators-step $family) () $family))
                  (sk-sibling-family-value $references $best $members $separators))
               $best))))))
(: sk-component-order-of (-[semidet]-> Bool (List SkeletonReference) SkeletonComponent SkeletonComponentOrder))
(= (sk-component-order-of $predicted $references (sk-component $best $_deps $_ev $members))
   (let $view (sk-sibling-family $references $best $members)
      (case $view (
         ((sk-val ($_type $_ctx $proof $_tv) $_ev2 $_deps2)
            (sk-component-order (if (sk-updates? $view) 1 (if $predicted (if (sk-report-proof? $proof) 2 0) 0)) $view))
         ($_goal (empty))))))

(: sk-component-merge-step (-[semidet]-> (List Number) SkeletonValue SkeletonComponentOrder SkeletonValue))
(= (sk-component-merge-step $ignore $acc (sk-component-order $order $view))
   (case (if (== $order 1)
            (case (data $acc $view) (
               (((sk-val $_a $acc-ev $acc-deps) (sk-val $_v $view-ev $view-deps))
                  (sk-fallback-pair $ignore $acc-deps $acc-ev $acc $view-deps $view-ev $view))
               ($_none sk-none)))
            sk-none) (
      (sk-none (sk-merge-step true $ignore $acc $view))
      ($merged $merged))))

(: sk-key-fallback (-[semidet]-> (List Number) (List SkeletonReference) (List SkeletonValue) SkeletonValue))
(= (sk-key-fallback $ignore $references $views)
   ;; Combine independent values before applying the updates they are priors
   ;; for. Canonical ordering also fixes confidence ties and floating-point
   ;; fold order, regardless of the order the original views were visited.
   (let $predicted (fold-semidet sk-report-prior-step false $views)
      (fold-semidet (sk-component-merge-step $ignore) sk-none
         (sort-atom (map-semidet (sk-component-order-of $predicted $references)
            (fold-semidet (sk-key-merge-step $ignore) () (sort-atom (map-semidet sk-reference-of (sk-report-values $views)))))))))

;; An estimate from a rule's instances is read by a consumer without the
;; samples that read what the consumer excludes, its own key above all: the
;; instance a refined rule is applied to is no evidence of the rule there
;; (leave one out). An implication instance fold read so is its tally less
;; those samples' contributions, found by the keys they read, and a refined
;; rule's truth is its rows evaluated again for the consumer; neither is
;; stored. Older views, which knew fewer instances, are left to every other
;; row.
(: sk-admit-step
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion) SkeletonVersion
       (List SkeletonVersion)))
(= (sk-admit-step $hash $key $filter $exclude $kept (sk-version $seq $rhash $view))
   (case (sk-left-out-view $hash $key $filter $exclude $rhash) (
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
      ($left-out (cons (sk-version $seq $rhash $left-out) $kept)))))

;; Rebuilt branches outlive queries. A branch computed under E1 serves E2
;; exactly when its dependencies miss E2 and its cuts are contained in E2.
;; Record only exclusions that cut a branch. Keep at most eight contexts per row;
;; dropping one changes only how much a later reader must rebuild. A read
;; outside a rebuild (`$build` false) builds no missed branch: it asks the last
;; tier of the evaluation for it (sk-build-wanted!) and keeps the incumbent.
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
                                     ($parent (search-id-value sk_branch_at))
                                     ($frame (+ 1 (next-search-id sk_branch_frame)))
                                     ($_cuts (add-atom &sk_branch_cuts ($frame $exclude ())))
                                     ($_enter (change-state! sk_branch_at $frame))
                                     ($view (sk-row-view () $exclude $hash $key $rhash
                                        (sk-row (sk-ident $rule $keys $result) $concl $premises $seq)))
                                     ((cons $found $_rest) (collapse (once (match &sk_branch_cuts ($frame $_exclude $recorded) $recorded))))
                                     ($cuts (hash-intersection (the (List Number) $found) $exclude))
                                     ($_leave (change-state! sk_branch_at $parent))
                                     ($_frame (remove-data-rows! &sk_branch_cuts (quote ($frame $_exclude $_found))))
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
                                           (if (== (collapse (once (match &ctx_sk_branch_wanted ($slot $hash $wanted $rhash $exclude)
                                                     (if (=alpha $wanted $key) true (empty))))) ())
                                              (context-add! &sk_branch_wanted ($slot $hash $key $rhash $exclude)) ())))
                                     ($_reader (sk-hold-branch-reader! $slot $key $rhash $exclude)))
                                 (chainer-first-or sk-none $incumbents)))))))))))))))

(: sk-left-out-view (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) Number SkeletonValue))
(= (sk-left-out-view $hash $key $filter $exclude $rhash)
   (let $view
      (case $key (
         ((sk-fold $args)
            (if (sk-instance-fold? $args)
               (case (sk-left-out $hash $exclude) (
                  (() sk-none)
                  ($left
                     (let ($kb $_pattern $_extractor $_init $_function $_finish $_mode) $args
                        (sk-instance-view $hash (the ScalarFoldSpec $args)
                           (sk-tally-without $hash (sk-instance-tally $hash $key $kb) $left))))))
               (sk-rate-without $hash $args $exclude)))
         ((sk-prior $rate-args) (if (sk-leaves-out? $hash $key $exclude) (sk-prior-view $hash $rate-args $exclude) sk-none))
         ((sk-evidence $evidence-args) (if (== $exclude ()) sk-none (sk-evidence-view $hash $evidence-args $exclude)))
         ($_statement
            (if (sk-rule-truth-key? $key)
               (case (collapse (once (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
                        (if (=alpha $stored $key) (sk-row $ident $concl $premises $seq) (empty))))) (
                  ((cons (sk-row $row-ident $row-concl $row-premises $row-seq) $_rest)
                     (if (sk-row-leaves-out-step $exclude false $row-premises)
                        (sk-row-view () $exclude $hash $key $rhash (sk-row $row-ident $row-concl $row-premises $row-seq))
                        sk-none))
                  (() sk-none)))
               sk-none))))
      (if (sk-admits? $filter $exclude $view) $view sk-none)))

;; Members are read without the views that depend on the fold itself: a
;; member derived through this fold's own output is left out of it. Their
;; evidence and dependencies are collected per member and joined once, when the
;; fold keeps them.
(: sk-fold-step
   (-[semidet]-> (-[semidet]-> $acc SkFact $acc) SkeletonFilter (List Number) SkeletonFold SkeletonKey
       SkeletonFold))
(= (sk-fold-step $step $filter $exclude (sk-fold-state $acc $proofs $ev $deps) $key)
   (case (sk-premise-value false (sk-value $key $filter $exclude)) (
      ((sk-val $fact $member-ev $member-deps)
         (let* ((($_type $_kbctx $proof $_tv) $fact))
            (sk-fold-state ($step $acc $fact) (cons $proof $proofs)
               (cons $member-ev $ev) (cons $member-deps $deps))))
      ($_none (sk-fold-state $acc $proofs $ev $deps)))))

;; Fact evidence and shared uncertain statements detect overlap: distinct
;; witnesses can project the same derived compound without sharing a fact
;; leaf. A shared RuleTruth parameter alone still leaves trials independent.
;; Only the selected member supports a correlated lower bound. Dependencies
;; retain every member so a later overlap bridge or stronger witness refreshes
;; the judgment. Inspect the full dependency sets: a witness join can put its
;; common source deeper than an ordinary premise's entanglement frontier.
(: sk-existential-step
   (-[semidet]-> Bool SkeletonFilter (List Number) SkeletonExistentialFold SkeletonKey SkeletonExistentialFold))
(= (sk-existential-step $floor $filter $exclude
      (sk-exists-state $tv $best $overlap $proofs $ev $deps) $key)
   (case (sk-premise-value false (sk-value $key $filter $exclude)) (
      ((sk-val $fact $member-ev $member-deps)
         (let ($_type $_ctx $proof (STV $s $c)) $fact
            (if (if (> $c 0) (if $floor true (> $s 0)) false)
               (let $take (case $best (
                       (sk-none true)
                       ((sk-val $old-fact $_old-ev $_old-deps)
                          (sk-existential-preferred? $fact $old-fact))))
                  (sk-exists-state
                     (if $floor $tv (if (== $proofs ()) (STV $s $c) (OrFormula $tv (STV $s $c))))
                     (if $take (sk-val $fact $member-ev $member-deps) $best)
                     (if $floor false
                        (if $overlap true
                           (if (premise-evidence-overlap? $ev $member-ev) true
                              (if (== $deps ()) false
                                 (not (== (sk-shared-statements $exclude
                                    (deps-shared (deps-join $deps) $member-deps)) ()))))))
                     (cons $proof $proofs)
                     (evidence-union $ev $member-ev)
                     (cons $member-deps $deps)))
               (sk-exists-state $tv $best $overlap $proofs $ev $deps))))
      ($_none (sk-exists-state $tv $best $overlap $proofs $ev $deps)))))

;; A fold's or group's view over its member keys. Existence folds have no
;; value when empty, except the residual's requested (0,1) identity. Other
;; folds finish their initial value, proved by `cpu`.
;; Base rates carry neither member evidence nor member dependencies.
(: sk-folded-view
   (-[semidet]-> Number Atom $args (-[semidet]-> $acc SkFact $acc) Atom $acc AggregateFinish
       (List SkeletonKey) SkeletonFilter SkeletonValue))
(= (sk-folded-view $hash $kind $args $step $function $init $finish $members $filter)
   (if (if (== $function OrFormula) true (== $function ExistentialFloor))
      (let* (($floor (== $function ExistentialFloor))
             ((sk-exists-state $exists-tv $exists-best $exists-overlap $exists-proofs $exists-ev $exists-deps)
                (fold-semidet (sk-existential-step $floor $filter (cons $hash ()))
                   (sk-exists-state (STV 0 1) sk-none false () (ev-set 0) ()) $members))
             ($exists-joined-deps (deps-join (cons (deps-key $hash) $exists-deps))))
         (case $exists-best (
            (sk-none
               ;; The residual alone requests the empty disjunction's identity.
               ;; Exists and KnownExistential use zero-confidence initial TVs.
               (let (STV $_initial-s $initial-c) $init
                  (if (> $initial-c 0)
                     (sk-goal-val (CPU $kind $args $init) cpu (ev-set 0) $exists-joined-deps)
                     sk-none)))
            ((sk-val ($_best-type $_best-ctx $best-proof $best-tv) $best-ev $_best-deps)
               (if (if $floor true $exists-overlap)
                  (sk-goal-val (CPU $kind $args $best-tv) $best-proof $best-ev $exists-joined-deps)
                  (sk-goal-val (CPU $kind $args $exists-tv)
                     (sk-fold-proof OrFormula $exists-proofs) $exists-ev $exists-joined-deps))))))
   (let* (((sk-fold-state $acc $proofs $ev $deps)
             (fold-semidet (sk-fold-step $step $filter (cons $hash ()))
                (sk-fold-state $init () () ()) $members))
          ($base-rate (base-rate-finish? $finish)))
      (sk-goal-val (CPU $kind $args (finish-aggregate (brand KB (car-atom $args)) $finish $acc))
         (sk-fold-proof $function $proofs)
         ;; Priors and folds that read their members' truth values as data,
         ;; like base rates, are not revised against their members' evidence;
         ;; their dependencies still reach their readers.
         (if $base-rate (ev-set 0)
            (case $args (
               (($_kb $_pattern (extract-with-truth $_p $_t $_v) $_init $_fn $_fin $_mode) (ev-set 0))
               ($_other (evidence-join $ev)))))
         (if $base-rate (deps-key $hash) (deps-join (cons (deps-key $hash) $deps)))))))

;; A base rate is one estimate per pattern, kept by the forward aggregate of the
;; fold's premise as each member's contribution (runtime/forward/aggregates.metta).
;; Forward steps and folds both update it and neither replaces the other: a
;; fold takes the members that joined or changed since it last read the
;; estimate, each with its current value, and reads the estimate back. A user
;; base rate stays authoritative. An estimate a reader finds missing is seeded
;; from the facts already stored (sk-rate-entries). The fold key watches the
;; cache entry. An implication instance fold is a tally too, of its samples'
;; contributions (&sk_instance_tally); its estimate revises with the rule's
;; stated truth and, like a base rate, carries neither member evidence nor
;; member dependencies: a rule's truth is a parameter of the views through the
;; rule, and its readers leave their own samples out (sk-left-out-view). Any
;; other fold is computed from its members.
(: sk-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-fold-view $hash $args)
   (if (sk-instance-fold? $args)
      (let* (($_taken (sk-instance-take! $hash $args))
             (($kb $_pattern $_extractor $_init $_function $_finish $_mode) $args))
         (sk-instance-view $hash $args (sk-instance-tally $hash (sk-fold $args) $kb)))
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let* (($key (sk-fold $args))
                ($was-dirty (not (== (collapse (once (match &ctx_sk_dirty ($hash $dirty-key)
                   (if (=alpha $dirty-key $key) true (empty))))) ())))
                ($cache-hash (base-rate-cache-hash $kbid $pattern))
                ($_watched
                   (if (== (collapse (once (match &ctx_sk_rate_readers ($cache-hash $stored)
                              (if (=alpha $stored $key) true (empty))))) ())
                      (context-add! &sk_rate_readers ($cache-hash $key))
                      true))
                ($entries (sk-rate-entries $args))
                ($_taken (sk-rate-take! $hash $args))
                ;; This read returns the just-published estimate. Consume only
                ;; its own new notification, preserving incoming dirty work.
                ($_own-update (if $was-dirty () (remove-variant-row! &sk_dirty (quote ($hash $key))))))
            (case (base-rate-cache-entries-for-mode $kbid $pattern $mode) (
               ((cons $entry $_rest)
                  (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) (ev-set 0) (deps-key $hash)))
               (()
                  (let* ((($_kb $_pattern $_extractor $init $_function $finish $_mode) $args))
                     (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate (brand KB $kbid) $finish $init))
                        (brand Proof cpu) (ev-set 0) (deps-key $hash))))))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args))))))

;; A member with no value whose rows are still to be computed is left to take:
;; the evaluation needs it and checks the fold again (sk-instance-checks!). A
;; member no search built, a class-link sample its subject's facts marked
;; (fa-class-link-dirty!), is read from its two sides' stored values; one a
;; side of which only a run's left-out copy holds is still to be computed.
(: sk-instance-take-step (-[semidet]-> Number SkeletonKey ScalarFoldSpec SkeletonFilter Atom SkeletonKey Atom))
(= (sk-instance-take-step $hash $fold $args $filter $_acc $member)
   (let $value (sk-value $member $filter (cons $hash ()))
      (if (== $value sk-none)
         (case (if (sk-member-pending? $member) (sk-waiting sk-none) (sk-stored-sample $member)) (
            ((sk-waiting $_none)
               (if (space-row-present? &ctx_sk_instance_changed ($hash $_stored)) () (context-add! &sk_instance_changed ($hash $fold))))
            ($stored (sk-instance-take-value! $hash $fold $args $member (the SkeletonValue $stored)))))
         (sk-instance-take-value! $hash $fold $args $member $value))))

;; Takes the members of an instance fold that joined or changed since it last
;; took them, each at its current value: every take costs the members that
;; changed, never the instances.
(: sk-instance-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-instance-take! $hash $args)
   (let* (($fold (sk-fold $args)) ($changed (sk-rate-changed $hash $fold)))
      (if (== $changed ()) ()
         (let $filter
               (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
                  ((cons $node $_more) (sk-member-filter $node))
                  (() sk-any-filter)))
            (fold-semidet (sk-instance-take-step $hash $fold $args $filter) () $changed)))))

;; Takes the members of a base-rate fold that joined or changed into its
;; estimate, each with its current value without the versions derived through
;; the rate. A key left without such a value leaves the tally; every step costs
;; the members that changed, never the population.
(: sk-rate-take-step (-[semidet]-> Number SkeletonKey Number ForwardAggregateDescriptor Atom SkeletonKey Atom))
(= (sk-rate-take-step $hash $fold $id $descriptor $_acc $member)
   (let* (($mhash (index-hash $member))
          ($_clean (remove-variant-row! &sk_rate_dirty (quote ($hash $mhash $fold $member))))
          ;; A rate take is a reader too: missing fold-independent views
          ;; request branches, and invalidation must retain their exclusions.
          ;; Row 0 identifies the fold's view, not a rule row. Register it even
          ;; inside another reader: the take has its own fold exclusion context.
          ($readers (sk-push-reader! ($hash $fold 0)))
          ($value (sk-premise-value false (sk-value $member sk-any-filter (cons $hash ()))))
          ($_read (sk-restore-readers! $readers)))
      (case $value (
         ((sk-val $fact $_ev $_deps) (let $_updated (collapse (fa-update! $fact $id (copy_term $descriptor))) ()))
         ($_none
            (case $member (
               ((sk-key $type $kbctx)
                  (let $_removed
                     (collapse (fa-remove! (assemble-runtime-fact $type $kbctx (brand Proof cpu) (STV 0.0 0.0)) $id (copy_term $descriptor)))
                     ()))
               ($_fold ()))))))))

(: sk-rate-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-rate-take! $hash $args)
   (if (sk-instance-fold? $args) (sk-instance-take! $hash $args)
   (let $key (sk-fold $args)
      (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)) (
         ((cons (fa-subscription $identity $descriptor $triggers) $_none)
            (let* (($_registered (fa-register! $identity $descriptor $triggers))
                   ($changed (sk-rate-changed $hash $key)))
               (case (collapse (fa-id $identity)) (
                  ((cons $id $_more)
                     (let $_linked (link-aggregate-fold! $id $hash)
                        (fold-semidet (sk-rate-take-step $hash $key $id $descriptor) () $changed)))
                  (() ())))))
         ($_other ()))))))

(: sk-cover-member-step (-[semidet]-> Number SkeletonFilter SkeletonCover SkeletonKey SkeletonCover))
(= (sk-cover-member-step $hash $filter (sk-cover $covered $missing) $key)
   (if (== (sk-value $key $filter (cons $hash ())) sk-none)
      (if (sk-member-pending? $key) (sk-cover $covered (+ $missing 1)) (sk-cover $covered $missing))
      (sk-cover (+ $covered 1) $missing)))

;; An exact fold (FoldAll, FoldAllValue, FoldAllTruth) is a function of all its
;; members; statistical folds (base rates, implication instances, priors,
;; averages) estimate from a sample, and an existential disjunction bounds its
;; witnesses, so neither is read for completeness here. The coverage of an
;; exact fold is its members with a value against those and the members still
;; to come: the members found whose value is pending, and one more while a
;; premise of the member node's joins has no answer and its search can still
;; give one (rule variants overlap, so premises do not count members). A fold
;; whose member node no search expanded has covered nothing.
;; An incomplete fold proves by (partial-fold covered total proof) and is
;; recorded in &sk_partial; a complete one leaves it. A count of -1 members
;; still to come stands for a member search not yet started.
(: sk-cover-fold! (-[semidet]-> Number SkeletonKey SkPattern (List SkPattern) SkeletonValue SkeletonValue))
(= (sk-cover-fold! $hash $key $node $members $view)
   (let* (($cover
             (case $members (
                (() (if (sk-expanded? (sk-node-hash $node) $node) (sk-cover 0 0) (sk-cover 0 -1)))
                ((cons $member $_more)
                   (if (sk-expanded? (sk-node-hash $member) $member)
                      (let* (((sk-cover $found $pending)
                                (fold-semidet (sk-cover-member-step $hash (sk-member-filter $member)) (sk-cover 0 0)
                                   (sk-answers $member)))
                             ((sk-growth $grows $_seen)
                                (fold-semidet sk-grows (sk-growth false ())
                                   (fold-flat sk-unanswered-step () (sk-children (sk-node-hash $member) $member)))))
                         (sk-cover $found (if $grows (+ $pending 1) $pending)))
                      (sk-cover 0 -1))))))
          ((sk-cover $covered $missing) $cover)
          ($recorded (space-row-present? &ctx_sk_partial ($hash $key))))
      (if (== $missing 0)
         (let $_left (if $recorded (remove-variant-row! &sk_partial (quote ($hash $key))) ()) $view)
         (let $_noted (if $recorded () (context-add! &sk_partial ($hash $key)))
            (case $view (
               ((sk-goal-val $goal $proof $ev $deps)
                  (sk-goal-val $goal
                     (brand Proof (partial-fold $covered (if (< $missing 0) 0 (+ $covered $missing)) $proof))
                     $ev $deps))))))))

(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-computed-fold-view $hash $args)
   (let* ((($_kb $_pattern $extractor $init $function $finish $_mode) $args)
          ($node (CPU FoldAllCompiled $args $_result))
          ($members (sk-fold-node-member $node))
          (($keys $filter)
             (case $members (
                (() (data () sk-any-filter))
                ((cons $member $_rest) (data (sk-answers $member) (sk-member-filter $member))))))
          ($view
             (sk-folded-view $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init
                $finish (the (List SkeletonKey) $keys) (the SkeletonFilter $filter))))
      (if (if (== $finish identity) (if (== $function OrFormula) false (if (== $function ExistentialFloor) false true)) false)
         (sk-cover-fold! $hash (sk-fold $args) $node $members $view)
         $view)))

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
      ((sk-prior $rate-args) (sk-keep-view $hash $key (sk-prior-view $hash $rate-args ())))
      ((sk-evidence $evidence-args) (sk-keep-view $hash $key (sk-evidence-view $hash $evidence-args ())))
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

(: sk-admitted (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-admitted $hash $key $filter $exclude)
   (map-flat sk-version-view (sk-admitted-versions $hash $key $filter $exclude)))

;; Leaves first, then one version per row in the order the rows were found;
;; a certain stored fact stands alone (sk-certain-or). Views read under given
;; statements leave out the leaves that depend on them. Views that overlap
;; condition the key on what they share.
(: sk-merge-key
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonGiven) (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $exclude $given $views)
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
          (($values $siblings $references) (sk-reference-values $ignore (the (List SkeletonValue) $standing))))
      (sk-node-apply $key $filter $outside (ev-set 0) (the (List SkeletonValue) $messages) (the (List SkeletonValue) $updates) (let $state (fold-semidet (sk-pair-merge-step true $ignore) (sk-merging sk-none () 0) (sk-report-values $values))
         (case $state (
            ((sk-merging $merged () $deps)
               (let $_settled
                  (if (if (== $outside ()) (== $filter sk-any-filter) false)
                     (if (sk-root-claim? $given $hash $key) (sk-clear-root-cap! $hash $key) ()) ())
                  (if (if (== $deps 0) (if $siblings false true) false) $merged
                     (sk-key-fallback $ignore $references $values))))
            ((sk-merging $_provisional $keys $deps)
               (let* (($merged (sk-key-fallback $ignore $references $values))
                      ($near (sk-shared-statements $ignore (deps-near-shared (map-semidet (sk-view-deps-step 0) $values))))
                      ($cut (if (sk-root-claim? $given $hash $key) $keys
                         (fold-semidet (sk-near-key-step $near) () $keys))))
                  (if (== $cut ()) $merged
                     (sk-conditioned $given (sk-key-target $hash $key $filter $exclude) $hash -1
                        (hash-union $exclude $unifiers) $cut (+ 1 (deps-size $deps)) $merged $merged))))))))))
(: sk-node-apply (-[semidet]-> SkeletonKey SkeletonFilter (List Number) EvidenceSet (List SkeletonValue) (List SkeletonValue) SkeletonValue SkeletonValue))
(= (sk-node-apply $key $filter $exclude $ev $messages $updates $value)
   (let $observed (if (== $messages ()) $value (sk-messages-on $key $exclude $messages $value))
      (event-network-read $key $filter $exclude $ev (if (== $updates ()) $observed
         (fold-semidet sk-jeffrey-step
            (if (== $observed sk-none) (sk-part-prior $key (fold-semidet sk-value-ev-step (ev-set 0) $updates) $exclude) $observed)
            (the (List SkeletonValue) (jeffrey-order $updates)))))))

;; A statement key's population prior, its cavity rate: the observed rate of
;; its predicate's population, its source facts (sk-leaf-facts, materialized
;; rows left out, and no forward run's copy: a derived member's value can rest
;; on this very node) without one the evidence Ev of the messages or updates
;; it is the prior of holds or one its reader excludes
;; (observed-rate-evidence), read as the base-rate fold reads it; a rate set on the
;; population (set-base-rate) as set. A positive-only pattern has a population
;; prior only from a set rate. The rate is a stored count, read once by the
;; node (its Laplace Beta); the fold's dependencies wake it when the
;; population changes.
(: sk-part-prior (-[semidet]-> SkeletonKey EvidenceSet (List Number) SkeletonValue))
(= (sk-part-prior $key $ev $exclude)
   (case $key (
      ((sk-key $type $kbctx)
         (if (if (is-expr $type) (if (head-is-member? $type (And Or Not)) false true) false)
            (let* (($pattern (cons-atom (car-atom $type) (map-flat sk-fresh-variable (cdr-atom $type))))
                   ($kbid (car-atom $kbctx))
                   ($kb (brand KB $kbid)))
               (if (if (positive-only-pattern? $kb (brand Statement $pattern)) (user-base-rate? $kb (brand Statement $pattern)) true)
                  (case (sk-value (car-atom (sk-direct-key-step () (base-rate-fold $kb (brand Statement $pattern) $_rate))) sk-any-filter ()) (
                     ((sk-goal-val (CPU $_fun $_args $fold-tv) $_proof $_ev $deps)
                        (case (if (user-base-rate? $kb (brand Statement $pattern)) $fold-tv
                                 (let* (($facts (fold-semidet sk-source-fact-step ()
                                                   (sk-leaf-facts (brand Statement $pattern) (kbctx $kb) sk-any-filter)))
                                        ($observed (BaseRateTv (observed-rate-evidence $facts $exclude $ev))))
                                    (smoothed-base-rate-tv $kb $observed))) (
                           ((STV $s $c)
                              (if (> (the Number $c) 0.0)
                                 (sk-val (assemble-runtime-fact $type $kbctx (brand Proof (population-prior $pattern)) (STV $s $c))
                                    (ev-set 0) $deps)
                                 sk-none))
                           ($_unknown sk-none))))
                     ($_none sk-none)))
                  sk-none))
            sk-none))
      ($_fold sk-none))))

(: sk-messages-on (-[semidet]-> SkeletonKey (List Number) (List SkeletonValue) SkeletonValue SkeletonValue))
(= (sk-messages-on $key $exclude $messages $value)
   (let* (($base (if (== $value sk-none) (sk-part-prior $key (fold-semidet sk-value-ev-step (ev-set 0) $messages) $exclude) $value))
          ($base-proof (case $base (((sk-val ($_bt $_bk $bp $_btv) $_bev $_bd) $bp) ($_none (brand Proof cpu)))))
          ($kept (fold-semidet (sk-message-kept-step $base-proof) () $messages)))
      (if (== $kept ()) $value
         (case $key (
            ((sk-key $type $kbctx)
               (let* ((($likelihoods $proofs $mev $mdeps) (fold-semidet sk-message-acc-step (data () () (ev-set 0) 0) $kept)))
                  (case $base (
                     ((sk-val ($_btype $_bkbctx $bproof (STV $bs $bc)) $bev $bdeps)
                        (sk-val (assemble-runtime-fact $type $kbctx
                                   (brand Proof (factored-revision $bproof (prior (STV $bs $bc)) (the (List Proof) $proofs)))
                                   (pearl-moments (evidence-confidence-k) $bproof (STV $bs $bc) (the Expression $likelihoods)))
                           (evidence-union $bev (the EvidenceSet $mev)) (deps-union $bdeps (the Number $mdeps))))
                     (sk-none
                        (sk-val (assemble-runtime-fact $type $kbctx
                                   (case $proofs (
                                      ((cons $one ()) $one)
                                      ($_many (brand Proof (factored-revision cpu (prior (STV 0.5 0.0)) (the (List Proof) $proofs))))))
                                   (pearl-moments (evidence-confidence-k) cpu uniform (the Expression $likelihoods)))
                           (the EvidenceSet $mev) (the Number $mdeps)))
                     ($_other $value)))))
            ($_fold $value))))))

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
                      ($_memo (collapse (once (match &sk_row
                         ($hash $stored $rhash (sk-row $_id $_concl $premises $_seq))
                         (if (=alpha $stored $key)
                            (let $volatile (fold-flat
                               (|-> ($seen $premise)
                                  (if $seen true
                                     (case $premise (
                                        ((CPU rule-likelihood-read $_likelihood-args $_likelihood-res) true)
                                        ((CPU $_cpu-fun $_cpu-args $_cpu-res) false)
                                        (($premise-type $_premise-scope $_premise-proof $_premise-tv)
                                           (head-is? $premise-type RuleTruth))))))
                               false $premises)
                               (if $volatile ()
                                  (context-add! &sk_summary_reference ($hash $key $rhash $given $exclude $filter $value))))
                            (empty)))))))
                  (append-flat $references $kept)))))
         $kept)
      $kept))

(: sk-admitted-merge (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-admitted-merge $hash $key $filter $exclude)
   (sk-merge-key $hash $key $filter $exclude () (sk-admitted $hash $key $filter $exclude)))

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
         (let $hash (index-hash $key) (sk-admitted-merge $hash $key $filter $exclude))
         (let* (($hash (index-hash $key))
                ($merged
                   (if (sk-leaves-out? $hash $key $exclude)
                      (sk-admitted-merge $hash $key sk-any-filter $exclude)
                      (case (sk-open-value $hash $key sk-any-filter) (
                         ((sk-merged $_hash $_key $deps $value)
                            (if (sk-excludes? $exclude $deps)
                               (sk-admitted-merge $hash $key sk-any-filter $exclude)
                               $value)))))))
            (if (sk-open-filter? $filter) $merged
               (if (sk-admits? $filter () $merged) $merged
                  (sk-admitted-merge $hash $key $filter $exclude)))))))

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

;; A paid branch merges in its own context before any ordinary MAIN merge or
;; exclusion-based selection. An older admissible MAIN view can omit a pin
;; dependency, so checking only that view would silently reuse it unchanged.
;; Folds and closed unfounded reads keep their ordinary admission behavior.
;; A compound whose rows read a given statement can acquire a value even when
;; it had none in MAIN; row hash -2 prevents re-entry through those rows. An
;; excluded compound acquires none, by the read's exclusions or the rebuild
;; frame's: a value built from its rows depends on it, and a branch rebuilt
;; without it read it anyway (test_history_closed_replay: FuelArrived through
;; the excluded (Or StockedFuel FuelArrived), never quiet).
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

(: sk-given-value (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-given-value $given $key $filter $exclude)
   (sk-calibrated-value $given $key $filter $exclude (sk-pinned-value $given $key $filter $exclude)))

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

(: sk-compatible-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet Bool SkeletonValue))
(= (sk-compatible-value $given $key $filter $exclude $ev $views)
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
             (sk-reference-values $ignore (sk-certain-or $leaves (the (List SkeletonValue) $compatible)))))
      (let $value (if $siblings (sk-key-fallback $ignore $references $selected)
                     (fold-semidet (sk-merge-step true $ignore) sk-none (sk-report-values $selected)))
         (sk-calibrated-value $given $key $filter $outside (sk-node-apply $key $filter $outside $ev (the (List SkeletonValue) $messages) (the (List SkeletonValue) $updates) $value)))))

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
                  (let* (($_entered (context-add! &sk_representative ($hash $key $rhash $given $exclude sk-none)))
                         ($_counted (query_metric_increment representative-reads))
                         ($copy (copy_term $row))
                         ((sk-row (sk-ident $owner $_keys $_key) ($_type $_scope $proof $_tv) $_premises $_seq) $copy)
                         ($cuts (hash-union $exclude (sk-row-exclusions $hash $key $proof)))
                         ($state (sk-row-state $given $cuts $hash sk-representative-read $copy))
                         ($read (case $state (
                            ((sk-entangled $_shared $_base $independent) $independent)
                            ($_other $state))))
                         ($value (sk-reference-view $owner (sk-row-result $copy $read)))
                         ($_left (context-remove! &sk_representative ($hash $key $rhash $given $exclude sk-none)))
                         ($_memo (if (if (== $value sk-none) (== (search-id-value sk_representative_budget) 0) false) ()
                            (context-add! &sk_representative ($hash $key $rhash $given $exclude $value)))))
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

;; Each premise reads its key's value without the views that depend on the
;; row's conclusion; reading stored facts first, it takes the facts compatible
;; with the row so far when there are any. A given statement reads as known. A
;; settled complete premise no rule application derives reads as unfounded;
;; a rule application of a complete statement, whose pin is not empty, reads
;; any other complete premise closed when it may read none of its views. Only an
;; antecedent completion (`$priors`) reads a population prior: the likelihood
;; of the consequence it inverts marginalises the parts it does not complete
;; over their values, and a part nothing tells about is at the prior of one
;; more member of its population. To any other row the population's value is
;; no value of the statement: a derivation from it would present the
;; population's value as this instance's, and an inversion or a sample would
;; read it as an observation.
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
            ((CPU ReadLikelihoodContext () $res)
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
                           (sk-rate-read (brand KB $kb) (brand Statement $pattern) (the TV $raw)
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
                                       ($_ordinary (sk-given-value $given $key $filter $exclude)))))
                                 (case (sk-use-premise (if (== $policy sk-independent-read) true $shared) $state $premise $value) (
                                    (sk-fail
                                       (if (if $shared true (if (== $policy sk-representative-read) true (== $policy sk-reference-read))) sk-fail
                                          (case (sk-use-premise $shared $state $premise
                                                   (sk-premise-value $priors (sk-compatible-value $given $key $filter $exclude $ev true))) (
                                             (sk-fail
                                                (sk-clash-on $given $state
                                                   (if (== $policy sk-facts-read) (sk-premise-value $priors (sk-given-value $given $key $filter $exclude)) $value)))
                                             ($compatible $compatible)))))
                                    ($taken $taken))))
                              (case (sk-use-premise (if (== $policy sk-independent-read) true $shared) $state $premise $closed) (
                                 (sk-fail (if $shared sk-fail (sk-clash-on $given $state $closed)))
                                 ($taken $taken))))))))))))))))

;; A row reads its premises without the views that depend on its key or on a
;; key unifying with it, nor, under a condition, on what the rows conditioned
;; around it exclude. Premises take values greedily in order, so a merged value
;; may hold evidence a later premise needs, or read a statement another
;; premise reads: then the row reads again, on a fresh copy, taking stored
;; facts first. A clash over shared facts
;; that remains, or premises that read one uncertain statement, are resolved
;; by conditioning on the shared statements. The approximate value is what
;; the row derived before it was conditioned: nothing for a clash, which
;; would count the shared evidence twice; for premises sharing a statement,
;; the premises read as independent. A row read under a condition is charged
;; to the claim it is part of.
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

;; Budgeted cutset conditioning (docs/metta/overlap_conditioning.md). A row
;; or a key's merge whose views share uncertain statements is the mix of the
;; target evaluated with the statement of most impact known true and known
;; false, by that statement's value read without the target. Given it, the
;; views share neither it nor what they read only through it; a branch whose
;; views still share a statement conditions on the next one, down to the
;; depth: the number of statements conditioned on at once, a cutset of
;; 2^depth branches. A conditioning nested at the depth takes its approximate
;; value, the merge's component fallback (sk-key-fallback) or the row's
;; approximate value,
;; and the pass is cut; so it is when no shared statement's mix is possible
;; there and an approximate value stands in. A clash has no approximate
;; value, so it is conditioned at any depth the claim allows.
;;
;; Outside a condition, ordinary evaluation queues the target; the last
;; tier grants it a turn. Conditioned rows pay as they run, including nested
;; conditioning and weight reads. The dependency-count estimate orders turns
;; but is never an admission threshold. A claim keeps its deepest completed
;; pass if the shared evaluation allowance runs out. With no completed pass,
;; it keeps its waiting value; incomplete branches cannot contribute.
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
                               ($_slice (change-state! sk_eval_budget $room))
                               ($_opened (sk-open-claim!))
                               ($deepest (sk-deepen $given $target $wexclude $keys (== $approx sk-none) (if (== $approx sk-none) 64 1) ()))
                               ($exhausted (sk-close-claim!))
                               ($spent (- $room (search-id-value sk_eval_budget)))
                               ($_restore (change-state! sk_eval_budget (- $before $spent)))
                               ($_root-spent (if $root
                                  (change-state! sk_root_claim_budget (- (search-id-value sk_root_claim_budget) $spent)) ()))
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

;; The claim's passes from a depth on: the deepest pass that finished before
;; the claim exhausted its allowance, () if none did. A target without an approximate value
;; (`$uncut`, a clash, which derived nothing before) makes one pass at
;; unbounded depth and takes it only if no nested conditioning had to stand
;; an approximation in, which can leave it worse than the target's other
;; views.
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

;; The target evaluated with a statement known true and known false, mixed
;; by the statement's value read without the target: the first statement in
;; order whose mix is possible, its value's evidence outside the branches.
;; A statement with stored facts weighs by its facts and those of its views
;; whose evidence the branches do not hold, in either polarity, as a premise
;; selects compatible views: a soft fact's rules let reports below the views
;; invert into it, and its merged value would count them again (#94). A fact
;; stored with confidence 1 is the weight alone (sk-certain-or).
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
                              (sk-given-value $given $pin sk-any-filter $wexclude))
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
(= (sk-row-state $given $exclusions $khash $policy (sk-row $_ident ($type $kbctx $proof $_tv) $premises $_seq))
   (let* (($pin (sk-closed-pin $khash $type $kbctx (derivation-proof? $type $proof)))
          ($shared (shared-evidence-frontier-proof? $proof))
          ($start (sk-acc () (evidence-set (sk-sample-exclusions $type $kbctx)) (cons (deps-key $khash) ()))))
      (if (sk-node-row? $proof)
         (sk-node-state $pin $given $exclusions $shared $policy $start $premises)
         (if (sk-completion-proof? $proof)
            (sk-completion-state $given $exclusions $khash (sk-key $type $kbctx) $shared $policy $start $premises)
            (let $state (fold-semidet (sk-premise-step $pin $given $exclusions $shared false $policy) $start $premises)
               (if (if (== $policy sk-independent-read) false
                       (if $shared false (if (rule-application-proof? $proof) true (head-is? $proof conjunction))))
                  (sk-entangle (hash-union $exclusions (hash-set (sk-given-hashes $given))) $state)
                  $state))))))

(: sk-completion-state
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Bool SkeletonReadPolicy SkeletonRowState (List SkPattern)
       SkeletonRowState))
(= (sk-completion-state $given $exclusions $khash $key $shared $policy $start $premises)
   (case (data (fold-flat sk-last-statement-step () $premises) (fold-flat sk-compound-evidence-step () $premises)) (
      (((sk-key $ctype $ckbctx) (sk-key $ktype $kkbctx))
         (let* (($consequence (sk-key $ctype $ckbctx))
                ($chash (index-hash $consequence))
                ($completed (fold-semidet (sk-completed-given-step $khash $key) () $premises))
                ($compound (sk-key $ktype $kkbctx))
                ($apart (hash-union (sk-unifier-hashes (index-hash $compound) $compound) $exclusions))
                ($compound-hash (index-hash $compound))
                ($inverted-inputs (collapse (match &sk_row ($compound-hash $stored $_irhash (sk-row $_iident ($_itype $_ikbctx $iproof $_itv) $ipremises $_iseq))
                   (if (=alpha $stored $compound)
                      (if (if (is-expr $iproof)
                             (let $ihead (car-atom $iproof)
                                (if (is-var $ihead) false
                                   (case (copy_term $ihead) (((inverted $_irule with $_iprior $_itoken) true) ($_iother false)))))
                             false)
                         (fold-semidet sk-direct-key-step () $ipremises) (empty))
                      (empty)))))
                ($observed (hash-set (fold-flat (sk-observed-exclusion-step $consequence) $exclusions (fold-flat append-flat () $inverted-inputs)))))
            (if (fold-semidet sk-known-false-step false (sk-key-leaves $consequence sk-any-filter))
               (fold-semidet
                  (sk-completion-premise-step () $given $exclusions $observed $apart $consequence $completed $shared $policy)
                  $start $premises)
               (fold-semidet
                  (sk-completion-premise-step (sk-closed-pin $chash $ctype $ckbctx true) $given $exclusions $observed
                     (hash-union (sk-unifier-hashes $chash $consequence) $apart) $consequence $completed $shared $policy)
                  $start $premises)))))))

(: sk-completion-premise-step
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) (List Number) (List Number) SkeletonKey (List SkeletonGiven)
       Bool SkeletonReadPolicy SkeletonRowState SkPattern SkeletonRowState))
(= (sk-completion-premise-step $pin $given $exclusions $observed $siblings $consequence $completed $shared $policy $state $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) (sk-premise-step () $given $exclusions $shared true $policy $state $premise))
      (($type $kbctx $_proof $_tv)
         (if (=alpha (sk-key $type $kbctx) $consequence)
            (sk-premise-step () $given $observed $shared true $policy $state $premise)
            (case (sk-premise-step $pin $given $siblings $shared true $policy $state $premise) (
               (sk-fail
                  (case $completed (
                     ((cons (sk-given $khash $_key $_truth) ())
                        (if (== $state sk-fail) sk-fail
                           (sk-premise-step $pin (append-flat $completed $given)
                              (hash-set (fold-flat (sk-without-hash-step $khash) () $siblings))
                              $shared true $policy $state $premise)))
                     ($_none sk-fail))))
               ($read $read))))))))

(: sk-node-state
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool SkeletonReadPolicy SkeletonRowState (List SkPattern)
       SkeletonRowState))
(= (sk-node-state $pin $given $exclusions $shared $policy $start (cons $premise $parts))
   (let* ((($type $kbctx $_proof $_tv) $premise) ($compound (sk-key $type $kbctx)))
      (fold-semidet
         (sk-premise-step $pin $given (hash-union (sk-unifier-hashes (index-hash $compound) $compound) $exclusions)
            $shared false $policy)
         (sk-premise-step $pin $given $exclusions $shared false $policy $start $premise)
         $parts)))
