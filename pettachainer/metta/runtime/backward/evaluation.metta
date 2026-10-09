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
;; a premise had values, all overlapping the evidence the row already used:
;; the statements of the shared facts, and a bound on the rows conditioning
;; on them evaluates
(: sk-clash (-[det]-> (List SkeletonKey) Number SkeletonRowState))
;; a key a conditioned read takes as known true or false, or a complete
;; statement a closed read takes as unfounded (docs/metta/complete_predicates.md)
(: SkeletonGiven Type)
(: sk-given (-[det]-> Number SkeletonKey Bool SkeletonGiven))
(: sk-unfounded (-[det]-> Number SkeletonKey SkeletonGiven))
(: SkeletonFold Type)
;; accumulator, member proofs (newest first), evidence, dependency hashes
(: sk-fold-state (-[det]-> Atom (List Proof) (List (List Evidence)) (List Number) SkeletonFold))
(: SkeletonGroup Type)
(: sk-group-found (-[det]-> SkPattern (List SkeletonKey) SkeletonGroup))
(: sk-group-missing SkeletonGroup)
(: TokenReplacement Type)
(: token-state (-[det]-> Atom (List Proof) TokenReplacement))

(: sort-atom (-[det]-> (List $item) (List $item)))

;; Signatures of the mutually recursive functions below.
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(: sk-row-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue))

(: sk-union (-[det]-> (List $item) (List $item) (List $item)))
(= (sk-union $left $right) (list_to_set (append-flat $left $right)))

;; --- Leaves -----------------------------------------------------------------

;; Hypothetical assumptions are not evidence.
(: leaf-evidence-for-result (-[det]-> SkFact (List Evidence)))
(= (leaf-evidence-for-result ($type $kb $proof $tv))
   (if (assumption-proof? $proof) () (cons (fact-evidence-entry $kb $proof $type) ())))

;; A stored fact is its own evidence and depends on its own key. The fact a
;; forward run stored for a key carries its value's evidence and what that value
;; was derived through (see sk-forward-store!), and a frozen key's summary its
;; value's evidence and the keys near it (forgetting.metta).
(: sk-leaf-view (-[det]-> Number SkFact SkeletonValue))
(= (sk-leaf-view $hash $fact)
   (case (collapse (once (match &sk_forward_stored ($hash $_key $fact $ev $deps) (sk-val $fact $ev $deps)))) (
      ((cons $stored $_rest) $stored)
      (() (case (collapse (once (match &sk_summary ($hash $_skey $fact $sev $sdeps) (sk-val $fact $sev $sdeps)))) (
             ((cons $summary $_more) $summary)
             (() (sk-val $fact (leaf-evidence-for-result $fact) (deps-key $hash)))))))))

;; A frozen key's summary stands for its past, so it counts as a fact: kept
;; beside the rows the key gets later.
(: sk-summary-fact? (-[det]-> SkFact Bool))
(= (sk-summary-fact? ($_type $_kbctx $proof $_tv))
   (case $proof (
      ((forgotten $_hash $_epoch) true)
      ($_other false))))

;; The fact a forward run stored for a key is a copy of the key's own value: it
;; lets a reader reach the key without searching for it, and stands for the
;; value only while the key has no computed versions; a frozen key's summary
;; stands beside them. A reader that must not depend on what either was
;; derived through leaves it out.
(: sk-leaf-step (-[semidet]-> Number Bool (List Number) (List SkeletonValue) SkFact (List SkeletonValue)))
(= (sk-leaf-step $hash $computed $exclude $kept $fact)
   (let $view (sk-leaf-view $hash $fact)
      (if (== (sk-view-deps-step 0 $view) (deps-key $hash)) (cons $view $kept)
         (if (if $computed (not (sk-summary-fact? $fact)) false) $kept
            (if (deps-meet? $exclude (sk-view-deps-step 0 $view)) $kept (cons $view $kept))))))

(: sk-leaf-views (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-leaf-views $hash $key $filter $exclude)
   (let $computed (if (== (sk-latest-versions $hash $key) ()) false true)
      (fold-semidet sk-cons-step ()
         (fold-semidet (sk-leaf-step $hash $computed $exclude) () (sk-key-leaves $key $filter)))))

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

;; --- Prior-factored merge (docs/metta/prior_factored_merge.md) ---------------

;; Updates of one prior add up on a link's scale: log-odds for observations
;; independent given the statement (Bayes' rule), log-survival for
;; independent causes (noisy-OR; docs/metta/combination_modes.md). The result
;; is the prior's link plus each view's link over it, with the link-scale
;; variances of the views over the prior's added to the prior's once.
(: sk-link (-[det]-> Atom Number Number))
(= (sk-link $link $p)
   (let $c (ideal-clip $p)
      (log-math 2.718281828459045 (if (== $link odds) (/ $c (- 1.0 $c)) (- 1.0 $c)))))

;; dx/dg(x), by which the delta method converts variances.
(: sk-link-slope (-[det]-> Atom Number Number))
(= (sk-link-slope $link $p)
   (let $c (ideal-clip $p) (if (== $link odds) (* $c (- 1.0 $c)) (- 1.0 $c))))

(: sk-link-var (-[det]-> Atom Number Number Number))
(= (sk-link-var $link $s $c)
   (let $q (sk-link-slope $link $s) (/ (ideal-var $s $c) (* $q $q))))

(: sk-factored-tv (-[det]-> Atom Number Number Number Number Number Number STVType))
(= (sk-factored-tv $link $sp $cp $sa $ca $sb $cb)
   (let* (($vp (sk-link-var $link $sp $cp))
          ($x (- (+ (sk-link $link $sa) (sk-link $link $sb)) (sk-link $link $sp)))
          ($v (+ $vp (+ (max 0.0 (- (sk-link-var $link $sa $ca) $vp)) (max 0.0 (- (sk-link-var $link $sb $cb) $vp)))))
          ($s (if (== $link odds) (/ 1.0 (+ 1.0 (pow-math 2.718281828459045 (- 0.0 $x))))
                 (max 0.0 (- 1.0 (pow-math 2.718281828459045 $x)))))
          ($q (sk-link-slope $link $s)))
      (STV $s (ideal-conf-from-var $s (* (* $q $q) $v)))))

;; Two certain views that contradict each other combine by no product.
(: sk-contradict? (-[det]-> Number Number Bool))
(= (sk-contradict? $sa $sb)
   (if (>= $sa 0.999999) (<= $sb 0.000001) (if (<= $sa 0.000001) (>= $sb 0.999999) false)))

;; A view as updates of a prior: an inversion or an antecedent completion, or
;; a factored merge of several, updates its prior; any other view is its own
;; prior, updated by nothing.
(: SkeletonPriorUpdate Type)
(: sk-prior-update (-[det]-> Proof Proof (List Proof) SkeletonPriorUpdate))

(: sk-prior-update-of (-[det]-> Proof TV SkeletonPriorUpdate))
(= (sk-prior-update-of $proof $tv)
   (case (sk-step-proof $proof) (
      (((inverted $_rule with $prior (prior $prior-tv)) $_observation)
         (sk-prior-update $prior (brand Proof (prior $prior-tv)) (cons $proof ())))
      (((antecedent-completion $_completed $_idx with $completion-prior (prior $completion-prior-tv)) $_known)
         (sk-prior-update $completion-prior (brand Proof (prior $completion-prior-tv)) (cons $proof ())))
      ((factored-revision $prior $prior-tv $parts) (sk-prior-update $prior $prior-tv $parts))
      ($_other (sk-prior-update $proof (brand Proof (prior $tv)) ())))))

;; The prior an observation's value was formed under, for an inversion that
;; reads the value as a likelihood ratio over it (ObservationRatioFormula):
;; the prior a view updates. A view updating nothing, a stored fact or a
;; forward conclusion, is a value of its own, read under the prior the
;; inversion implies for it, as modus ponens reads it.
(: sk-observation-prior (-[det]-> Proof TV TV))
(= (sk-observation-prior $proof $tv)
   (case (sk-prior-update-of $proof $tv) (
      ((sk-prior-update $_prior $_own ()) no-evidence)
      ((sk-prior-update $_prior (prior $prior-tv) $_parts) (the TV $prior-tv)))))

;; The forward conclusions a view combines: a rule application is one, a
;; combination of forward views (docs/metta/combination_modes.md) its parts.
(: sk-forward-parts (-[det]-> Proof (List Proof)))
(= (sk-forward-parts $proof)
   (let $step (sk-step-proof $proof)
      (if (rule-application-proof? $step) (cons $proof ())
         (case $step (
            ((combination $_mode $_prior $parts) (proof-children $parts))
            ($_other ()))))))

;; The prior a completion reads its consequence's value under. A forward
;; conclusion predicts the consequence from its causes, the completed conjunct
;; among them, and an unfounded value is a closed read's hypothesis: neither
;; observes the consequence, and the completion reads neither.
(: sk-consequence-prior (-[semidet]-> Proof TV TV))
(= (sk-consequence-prior $proof $tv)
   (if (if (== (sk-step-proof $proof) unfounded) true (not (== (sk-forward-parts $proof) ())))
      (empty)
      (sk-observation-prior $proof $tv)))

;; The observations of the updates a view merges (an inversion's observation,
;; each witness of a completion) and the rules whose truth is an estimate, the
;; rules carrying evidence (`register-rule-evidence!`), by hash (defined at the
;; end of the file). Updates through a rule with given truth are independent
;; given their prior. A list of proofs is walked by recursion: the determinism
;; checker rejects a fold over Proof, a newtype of Atom.
(: sk-part-sources (-[det]-> KB (List Proof) (List Number)))
(: sk-sources-meet? (-[det]-> KB (List Proof) (List Proof) Bool))

;; Two views updating the same prior with different rules and observations
;; merge by Bayes' rule; over a base rate, which carries no evidence, they
;; must also share no evidence, since an observation may be read below the
;; witnesses the sources compare. A view updating the population base rate (`cpu`)
;; merges the same way into a derived, uncertain view over another prior, or
;; updating nothing, that shares none of its evidence: that view takes the
;; base rate's place, as the instance's prior given its other evidence. A
;; stored fact is counted in the base rate itself, and a certain view stays as
;; it is. Anything else is left to the rules below, and so are two certain
;; views that contradict each other.
(: sk-factored-merge
   (-[det]-> SkFact (List Evidence) Number SkFact (List Evidence) Number SkeletonValue))
(= (sk-factored-merge ($type $kbctx $proof-a $tv-a) $ev-a $deps-a ($btype $bkbctx $proof-b $tv-b) $ev-b $deps-b)
   (case (data (sk-prior-update-of $proof-a $tv-a) (sk-prior-update-of $proof-b $tv-b) $tv-a $tv-b) (
      (((sk-prior-update $base-a (prior (STV $spa $cpa)) $parts-a)
        (sk-prior-update $base-b (prior (STV $spb $cpb)) $parts-b)
        (STV $sa $ca) (STV $sb $cb))
         (let* (($population-a (== (sk-step-proof $base-a) cpu))
                ($population-b (== (sk-step-proof $base-b) cpu)))
            (if (if $population-a (if $population-b false true) false)
               (sk-factored-merge (data $btype $bkbctx $proof-b $tv-b) $ev-b $deps-b (data $type $kbctx $proof-a $tv-a) $ev-a $deps-a)
               (if (if (sk-contradict? (the Number $sa) (the Number $sb)) false
                      (if (=alpha $base-a $base-b)
                         (if (== $spa $spb) (if (== $cpa $cpb) (if (== $parts-a ()) false (if (== $parts-b ()) false (if (if $population-a (evidence-sets-overlap? $ev-a $ev-b) false) false (not (sk-sources-meet? (brand KB (car-atom $kbctx)) $parts-a $parts-b))))) false) false)
                         (if $population-b
                            (if (if (is-expr $base-a) (< $ca 1.0) false) (if (evidence-sets-overlap? $ev-a $ev-b) false true) false)
                            false)))
                  (sk-val ($type $kbctx (brand Proof (factored-revision $base-a (prior (STV $spa $cpa)) (append-flat $parts-a $parts-b)))
                              (sk-factored-tv odds (the Number $spb) (the Number $cpb) (the Number $sa) (the Number $ca) (the Number $sb) (the Number $cb)))
                     (sk-union $ev-a $ev-b) (deps-union $deps-a $deps-b))
                  sk-none))))
      ($_other sk-none))))

;; --- Learned combination modes (docs/metta/combination_modes.md) -------------

;; Per consequent predicate: the outcomes counted, their sum, and the log score
;; of each mode on the outcomes several disjoint forward views met on.
(: CombinationTally Type)
(: combination-tally (-[det]-> Number Number Number Number Number CombinationTally))
(: &combination_tally (SpaceOf (Number Atom Atom CombinationTally)))
!(bind! &combination_tally (new-space))

;; A premise of a forward rule applied to stored facts: a ground statement
;; reads its stored facts merged, adding their evidence; a computation runs.
;; A fold, an open statement, a missing fact or a settled variant gives no
;; view.
(: sk-stored-premise-step (-[semidet]-> (List Evidence) Atom (List Evidence)))
(= (sk-stored-premise-step $ev $premise)
   (case $premise (
      ((CPU $fun $args $res)
         (if (if (aggregate-fold-function? $fun) true (== $fun SettlesFormula)) (empty)
            (case (collapse (once (cpu-call 0 $fun $args))) (
               ((cons $result $_rest) (if (= $res $result) $ev (empty)))))))
      (($type $kbctx $proof $tv)
         (if (== (extract-vars $type) ())
            (case (stored-statement-candidate (brand Statement $type) (brand KBContext $kbctx) false) (
               ((forward-derived ($_stype $_skbctx $stored-proof $stored-tv) $stored-ev)
                  (if (= ($proof $tv) ($stored-proof $stored-tv)) (append-flat $stored-ev $ev) (empty)))))
            (empty))))))

(: sk-disjoint-view-step (-[semidet]-> Atom Atom Atom))
(= (sk-disjoint-view-step ($tvs $seen) ($tv $ev))
   (if (evidence-sets-overlap? (the (List Evidence) $ev) (the (List Evidence) $seen)) (empty) (data (cons $tv $tvs) (append-flat $ev $seen))))

;; The views the forward rules concluding a statement give from its
;; antecedents' stored facts, when there are several and their evidence is
;; disjoint.
(: sk-outcome-views (-[det]-> Atom Atom (List STVType)))
(= (sk-outcome-views $type $kbctx)
   (case (collapse (once (fold-semidet sk-disjoint-view-step (data () ())
            (collapse (match ccls_index (($type $kbctx (by $_rule $_premise) $tv) $_id $args)
               (let $ev (fold-semidet sk-stored-premise-step () $args) (data $tv $ev))))))) (
      ((cons $found $_none)
         (case $found (
            (((cons $_one ()) $_seen) ())
            (($tvs $_evidence) (the (List STVType) $tvs)))))
      (() ()))))

(: sk-mode-step (-[semidet]-> Atom STVType STVType STVType STVType))
(= (sk-mode-step $mode (STV $sp $cp) (STV $sa $ca) (STV $sb $cb)) (sk-factored-tv $mode $sp $cp $sa $ca $sb $cb))

;; The log probability a prediction gave an outcome.
(: sk-log-score (-[det]-> Number STVType Number))
(= (sk-log-score $outcome (STV $s $_c))
   (let $q (ideal-clip $s)
      (+ (* $outcome (log-math 2.718281828459045 $q)) (* (- 1.0 $outcome) (log-math 2.718281828459045 (- 1.0 $q))))))

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
                       ($_new (add-atom &combination_tally ($hash $kb $head $scored))))
                   $scored))))
      (case $current (
         ((combination-tally $n $sum $revision $odds $noisy)
            (let $prior (STV (/ (+ $sum 1.0) (+ $n 2.0)) (count-confidence $n))
               (if (>= $odds $noisy)
                  (if (>= (- $odds $revision) 2.302585092994046) (data odds $prior) revision)
                  (if (>= (- $noisy $revision) 2.302585092994046) (data noisy-or $prior) revision))))))))

;; Disjoint forward views of a consequent whose outcomes prefer a product mode
;; combine by it; two certain views that contradict each other revise.
(: sk-combined-merge (-[det]-> SkFact SkFact (List Evidence) Number SkeletonValue))
(= (sk-combined-merge ($type $kbctx $proof-a $tv-a) ($_btype $_bkbctx $proof-b $tv-b) $ev $deps)
   (let* (($parts-a (sk-forward-parts $proof-a))
          ($parts-b (sk-forward-parts $proof-b)))
      (if (if (== $parts-a ()) true (== $parts-b ())) sk-none
         (case (collapse (once (sk-combination-mode (brand KB (car-atom $kbctx)) $type))) (
            ((cons $choice $_none)
               (case (data $choice $tv-a $tv-b) (
                  ((($mode (STV $sp $cp)) (STV $sa $ca) (STV $sb $cb))
                     (if (sk-contradict? (the Number $sa) (the Number $sb)) sk-none
                        (sk-val ($type $kbctx (brand Proof (combination $mode (prior (STV $sp $cp)) (append-flat $parts-a $parts-b)))
                                    (sk-factored-tv $mode (the Number $sp) (the Number $cp) (the Number $sa) (the Number $ca) (the Number $sb) (the Number $cb)))
                           $ev $deps)))
                  ($_revision sk-none))))
            (() sk-none))))))

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof and a settled step to its complete
;; one, overlapping evidence keeps the view whose evidence strictly contains
;; the other's or else the more confident one, and disjoint evidence revises,
;; or combines forward views by the mode their predicate's outcomes prefer.
;; A dominated view contributes neither evidence nor dependencies.
(: sk-merge-facts
   (-[det]-> SkFact (List Evidence) Number SkFact (List Evidence) Number
       SkeletonValue))
(= (sk-merge-facts $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-fact-step-proof $a))
          ($proof-b (sk-fact-step-proof $b)))
      (if (== $a $b) (sk-val $a (sk-union $ev-a $ev-b) $deps-a)
         (if (proof-dominates? $proof-a $proof-b) (sk-val $a $ev-a $deps-a)
            (if (proof-dominates? $proof-b $proof-a) (sk-val $b $ev-b $deps-b)
               (let $factored (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b)
               (if (not (== $factored sk-none)) $factored
               (if (evidence-sets-overlap? $ev-a $ev-b)
                  (let* (($a-in-b (evidence-subset? $ev-a $ev-b))
                         ($b-in-a (evidence-subset? $ev-b $ev-a)))
                     (if (if $a-in-b (if $b-in-a false true) false) (sk-val $b $ev-b $deps-b)
                        (if (if $b-in-a (if $a-in-b false true) false) (sk-val $a $ev-a $deps-a)
                           (if (>= (term-confidence $a) (term-confidence $b))
                              (sk-val $a $ev-a $deps-a)
                              (sk-val $b $ev-b $deps-b)))))
                  (let* (($pooled (sk-union $ev-a $ev-b))
                         ($deps (deps-union $deps-a $deps-b))
                         ($combined (sk-combined-merge $a $b $pooled $deps)))
                     (if (not (== $combined sk-none)) $combined
                        (if (>= (term-confidence $a) (term-confidence $b))
                           (sk-val (RevisionMergeProof $a $b) $pooled $deps)
                           (sk-val (RevisionMergeProof $b $a) $pooled $deps))))))))))))

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
      (sk-union $ev $other-ev) (deps-union $deps $other-deps)))

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
;; usable when a newer one came to depend on one of them. An older view whose
;; dependencies include all of a newer one's is admitted only where the newer
;; one is, so storing a view drops those.
(: sk-admits? (-[det]-> SkeletonFilter (List Number) SkeletonValue Bool))
(= (sk-admits? $filter $exclude $view)
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (deps-meet? $exclude $deps) false (sk-fact-matches? $filter $fact)))
      ((sk-goal-val $_goal $_proof $_ev $deps)
         (if (deps-meet? $exclude $deps) false true))
      (sk-none false))))

(: sk-admit-older (-[det]-> SkeletonFilter (List Number) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-admit-older $filter $exclude $kept $view)
   (if (sk-admits? $filter $exclude $view) $view $kept))

(: sk-admit-step
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion) SkeletonVersion
       (List SkeletonVersion)))
(= (sk-admit-step $hash $key $filter $exclude $kept (sk-version $seq $rhash $view))
   (if (sk-admits? $filter $exclude $view) (cons (sk-version $seq $rhash $view) $kept)
      (case (fold-semidet (sk-admit-older $filter $exclude) sk-none (sk-older-views $hash $key $rhash)) (
         (sk-none $kept)
         ($older (cons (sk-version $seq $rhash $older) $kept))))))

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
          ($deps (sk-view-deps-step 0 $view))
          ($_moved
             (collapse (match &sk_latest ($hash $stored (sk-version $old-seq $rhash $old))
                (if (=alpha $stored $key)
                   (let $_removed (remove-atom &sk_latest ($hash $stored (sk-version $old-seq $rhash $old)))
                      (if (sk-dominated? $deps $old) () (add-atom &sk_view ($hash $stored $rhash $old))))
                   (empty)))))
          ($_pruned
             (collapse (match &sk_view ($hash $stored $rhash $older)
                (if (=alpha $stored $key)
                   (if (sk-dominated? $deps $older) (remove-variant-row! &sk_view (quote ($hash $stored $rhash $older))) (empty))
                   (empty)))))
          ($support (deps-union (sk-row-support $hash $rhash) $deps))
          ($_old-support (remove-data-rows! &sk_support (quote ($hash $rhash $_had))))
          ($_support (add-atom &sk_support ($hash $rhash $support)))
          ($_added (add-atom &sk_latest ($hash $key (sk-version $seq $rhash $view)))))
      $view))

(: sk-dominated? (-[semidet]-> Number SkeletonValue Bool))
(= (sk-dominated? $deps $older) (deps-mask-within? $deps (sk-view-deps-step 0 $older)))

(: sk-row-support (-[det]-> Number Number Number))
(= (sk-row-support $hash $rhash)
   (case (collapse (once (match &sk_support ($hash $rhash $deps) $deps))) (
      ((cons $deps $_rest) $deps)
      (() 0))))

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
      ((extract-with-truth $pattern $truth $value)
         (let* ((($pattern ($_kb $_ctx $_vars) $_proof $truth) (copy_term $fact)))
            ($fun $acc $value)))
      ((extract-inheritance-tv $kbid $_statement)
         (let* ((((Inheritance $subject $_concept) ($_kb $_ctx $_vars) $_proof $tv) (copy_term $fact)))
            ($fun $acc (WeightedTv (inheritance-subject-prior-tv $kbid (brand Statement $subject)) $tv))))
      (extract-tv
         (let* ((($_type $_kbctx $_proof $tv) $fact))
            ($fun $acc $tv))))))

;; Members are read without the views that depend on the fold itself: a
;; member derived through this fold's own output is left out of it. Their
;; evidence and dependencies are collected per member and joined once, when the
;; fold keeps them.
(: sk-fold-step
   (-[semidet]-> (-[semidet]-> $acc SkFact $acc) SkeletonFilter (List Number) SkeletonFold SkeletonKey
       SkeletonFold))
(= (sk-fold-step $step $filter $exclude (sk-fold-state $acc $proofs $ev $deps) $key)
   (case (sk-value $key $filter $exclude) (
      ((sk-val $fact $member-ev $member-deps)
         (let* ((($_type $_kbctx $proof $_tv) $fact))
            (sk-fold-state ($step $acc $fact) (cons $proof $proofs)
               (cons $member-ev $ev) (cons $member-deps $deps))))
      ($_none (sk-fold-state $acc $proofs $ev $deps)))))

;; The distinct evidence of a fold's members.
(: sk-join-evidence (-[det]-> (List (List Evidence)) (List Evidence)))
(= (sk-join-evidence $parts) (list_to_set (foldr-flat append-flat () $parts)))

;; A fold with members proves by its members, in the order they were found.
(: sk-fold-proof (-[semidet]-> Atom (List Proof) Proof))
(= (sk-fold-proof $function $proofs)
   (if (== $proofs ()) (brand Proof cpu)
      (brand Proof
         (cons (if (== $function OrFormula) disjunction foldall-proof)
            (fold-semidet sk-cons-step () $proofs)))))

;; A fold's or group's view over its member keys; with no members it is the
;; finished initial value, proved by `cpu`. Base rates estimate the population
;; and carry neither member evidence nor member dependencies.
(: sk-folded-view
   (-[semidet]-> Number Atom $args (-[semidet]-> $acc SkFact $acc) Atom $acc AggregateFinish
       (List SkeletonKey) SkeletonFilter SkeletonValue))
(= (sk-folded-view $hash $kind $args $step $function $init $finish $members $filter)
   (let* (((sk-fold-state $acc $proofs $ev $deps)
             (fold-semidet (sk-fold-step $step $filter (cons $hash ()))
                (sk-fold-state $init () () ()) $members))
          ($base-rate (base-rate-finish? $finish)))
      (sk-goal-val (CPU $kind $args (finish-aggregate (brand KB (car-atom $args)) $finish $acc))
         (sk-fold-proof $function $proofs)
         ;; Priors, implication instance estimates and folds that read their
         ;; members' truth values as data, like base rates, are not revised
         ;; against their members' evidence; their dependencies still reach
         ;; their readers.
         (if $base-rate ()
            (if (stored-list-member? $finish (uniform-prior uniform-prior-known implication-instance)) ()
               (case $args (
                  (($_kb $_pattern (extract-with-truth $_p $_t $_v) $_init $_fn $_fin $_mode) ())
                  ($_other (sk-join-evidence $ev))))))
         (if $base-rate (deps-key $hash) (deps-join (cons (deps-key $hash) $deps))))))

;; A base rate is one estimate per pattern, kept by the forward aggregate of the
;; fold's premise as each member's contribution (runtime/forward/aggregates.metta).
;; Forward steps and folds both update it and neither replaces the other: a
;; fold takes the members that joined or changed since it last read the
;; estimate, each with its current value, and reads the estimate back. A user
;; base rate stays authoritative. An estimate a reader finds missing is seeded
;; from the facts already stored (sk-rate-entries). The fold key watches the
;; cache entry. Any other fold is computed from its members.
(: sk-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(= (sk-fold-view $hash $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let* (($key (sk-fold $args))
                ($cache-hash (base-rate-cache-hash $kbid $pattern))
                ($_watched
                   (if (== (collapse (once (match &sk_rate_folds ($cache-hash $stored)
                              (if (=alpha $stored $key) true (empty))))) ())
                      (add-atom &sk_rate_folds ($cache-hash $key))
                      true))
                ($entries (sk-rate-entries $args))
                ($_taken (sk-rate-take! $hash $args)))
            (case (base-rate-cache-entries-for-mode $kbid $pattern $mode) (
               ((cons $entry $_rest) (sk-cached-fold-view $hash $args $entry))
               (()
                  (let* ((($_kb $_pattern $_extractor $init $_function $finish $_mode) $args))
                     (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate (brand KB $kbid) $finish $init))
                        (brand Proof cpu) () (deps-key $hash))))))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args)))))

;; Takes the members of a base-rate fold that joined or changed into its
;; estimate, each with its current value without the versions derived through
;; the rate. A key left without such a value leaves the tally; every step costs
;; the members that changed, never the population.
(: sk-rate-take-step (-[semidet]-> Number SkeletonKey Number ForwardAggregateDescriptor Atom SkeletonKey Atom))
(= (sk-rate-take-step $hash $fold $id $descriptor $_acc $member)
   (let $_clean (remove-variant-row! &sk_rate_dirty (quote ($hash $fold $member)))
      (case (sk-value $member sk-any-filter (cons $hash ())) (
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
   (let $key (sk-fold $args)
      (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)) (
         ((cons (fa-subscription $identity $descriptor $trigger $both $second) $_none)
            (let* (($_registered (fa-register! $identity $descriptor $trigger $both $second))
                   ($changed
                      (collapse (match &sk_rate_dirty ($hash $fold $member)
                         (if (=alpha $fold $key) $member (empty))))))
               (case (collapse (fa-id $identity)) (
                  ((cons $id $_more)
                     (let $_linked (link-aggregate-fold! $id $hash)
                        (fold-semidet (sk-rate-take-step $hash $key $id $descriptor) () $changed)))
                  (() ())))))
         ($_other ())))))

(: sk-cached-fold-view (-[semidet]-> Number ScalarFoldSpec BaseRateEntry SkeletonValue))
(= (sk-cached-fold-view $hash $args $entry)
   (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) ()
      (deps-key $hash)))

;; --- Coverage of exact folds (docs/metta/partial_folds.md) -------------------

;; A member without a value is still to come while one of its key's rows is
;; stale, was never computed, or waits for conditioning; once every row is
;; computed and current and none derives anything, it is no member.
(: sk-row-current? (-[det]-> Number Number Bool))
(= (sk-row-current? $khash $rhash)
   (if (space-row-present? &sk_stale ($khash $rhash)) false
      (if (space-row-present? &sk_given_pending ($khash $rhash $_cost)) false
         (space-row-present? &sk_support ($khash $rhash $_deps)))))

(: sk-member-pending? (-[det]-> SkeletonKey Bool))
(= (sk-member-pending? $key)
   (let $khash (index-hash $key)
      (not (== (collapse (once (match &sk_row ($khash $stored $rhash $_row)
                  (if (=alpha $stored $key) (if (sk-row-current? $khash $rhash) (empty) true) (empty)))))
               ()))))

;; covered members, members still to come
(: SkeletonCover Type)
(: sk-cover (-[det]-> Number Number SkeletonCover))

(: sk-cover-member-step (-[semidet]-> Number SkeletonFilter SkeletonCover SkeletonKey SkeletonCover))
(= (sk-cover-member-step $hash $filter (sk-cover $covered $missing) $key)
   (if (== (sk-value $key $filter (cons $hash ())) sk-none)
      (if (sk-member-pending? $key) (sk-cover $covered (+ $missing 1)) (sk-cover $covered $missing))
      (sk-cover (+ $covered 1) $missing)))

;; The premises of the member node's joins that have no answer yet.
(: sk-unanswered-step (-[det]-> (List SkPattern) SkPattern (List SkPattern)))
(= (sk-unanswered-step $kept $premise) (if (== (sk-answers $premise) ()) (cons $premise $kept) $kept))

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
                (() (if (sk-expanded? $node) (sk-cover 0 0) (sk-cover 0 -1)))
                ((cons $member $_more)
                   (if (sk-expanded? $member)
                      (let* (((sk-cover $found $pending)
                                (fold-semidet (sk-cover-member-step $hash (sk-member-filter $member)) (sk-cover 0 0)
                                   (sk-answers $member)))
                             ((sk-growth $grows $_seen)
                                (fold-semidet sk-grows (sk-growth false ())
                                   (fold-flat sk-unanswered-step () (sk-children $member)))))
                         (sk-cover $found (if $grows (+ $pending 1) $pending)))
                      (sk-cover 0 -1))))))
          ((sk-cover $covered $missing) $cover)
          ($recorded (space-row-present? &sk_partial ($hash $key))))
      (if (== $missing 0)
         (let $_left (if $recorded (remove-variant-row! &sk_partial (quote ($hash $key))) ()) $view)
         (let $_noted (if $recorded () (add-atom &sk_partial ($hash $key)))
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
          ($view
             (case $members (
                (() (sk-folded-view $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init
                       $finish () sk-any-filter))
                ((cons $member $_rest)
                   (sk-folded-view $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init
                      $finish (sk-answers $member) (sk-member-filter $member)))))))
      (if (if (== $finish identity) (not (== $function OrFormula)) false)
         (sk-cover-fold! $hash (sk-fold $args) $node $members $view)
         $view)))

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
(: sk-admitted-versions (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion)))
(= (sk-admitted-versions $hash $key $filter $exclude)
   (let* (($stored (sk-latest-versions $hash $key))
          ($versions (if (== $stored ()) (sk-fold-views $hash $key) $stored)))
      (fold-semidet sk-cons-step () (fold-semidet (sk-admit-step $hash $key $filter $exclude) () $versions))))

(: sk-version-view (-[det]-> SkeletonVersion SkeletonValue))
(= (sk-version-view (sk-version $_seq $_rhash $view)) $view)

(: sk-admitted (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-admitted $hash $key $filter $exclude)
   (map-flat sk-version-view (sk-admitted-versions $hash $key $filter $exclude)))

(: sk-certain-leaf-step (-[det]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-certain-leaf-step $kept $leaf)
   (case $leaf (
      ((sk-val $fact $_ev $_deps)
         (if (sk-certain? (brand Statement (car-atom $fact)) (cons $fact ())) (cons $leaf $kept) $kept))
      ($_other $kept))))

;; A value depending on an incomplete fold is provisional: computed from part
;; of an aggregate that needs all of it (docs/metta/partial_folds.md). A key
;; merges its provisional values only when it has no other.
(: sk-complete-step (-[semidet]-> (List Number) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-complete-step $partial $kept $value)
   (if (deps-meet? $partial (sk-view-deps-step 0 $value)) $kept (cons $value $kept)))

(: sk-complete-values (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-complete-values $values)
   (case (collapse (match &sk_partial ($fold-hash $_fold) $fold-hash)) (
      (() $values)
      ($partial
         (case (fold-semidet (sk-complete-step $partial) () $values) (
            (() $values)
            ($complete (fold-semidet sk-cons-step () $complete))))))))

;; Leaves first, then one version per row in the order the rows were found.
;; A ground statement stored with confidence 1 is its own value, as expansion
;; applies no rule to it: no other proof could change it, so its rows' views
;; add neither evidence nor dependencies. A derived view of confidence 1 is a
;; probability known exactly, not the statement's truth, and merges as usual.
(: sk-merge-key (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $exclude $views)
   (let* (($leaves (sk-leaf-views $hash $key $filter $exclude))
          ($certain (fold-semidet sk-certain-leaf-step () $leaves))
          ($values (sk-complete-values (if (== $certain ()) (append-flat $leaves $views) $certain))))
      (case (sk-lift $values) (
         ((cons $lifted $_rest) $lifted)
         (() (fold-semidet sk-merge-step sk-none $values))))))

(: sk-view-deps-step (-[semidet]-> Number SkeletonValue Number))
(= (sk-view-deps-step $deps $view)
   (case $view (
      ((sk-val $_fact $_ev $view-deps) (deps-union $deps $view-deps))
      ((sk-goal-val $_goal $_proof $_ev $view-deps) (deps-union $deps $view-deps))
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
                ($leaves (sk-leaf-views $hash $key $filter ()))
                ($deps (fold-semidet sk-view-deps-step 0 (append-flat $leaves $views)))
                ($value (sk-merge-key $hash $key $filter () $views))
                ($_cached (add-atom &sk_merged (sk-merged $hash $key $deps $value)))
                ($_factor (sk-note-truth-factor! $hash $key $value)))
            (sk-merged $hash $key $deps $value))))))

;; A rule truth's new value rescores the rules that read it.
(: sk-note-truth-factor! (-[det]-> Number SkeletonKey SkeletonValue Atom))
(= (sk-note-truth-factor! $hash $key $value)
   (case $key (
      ((sk-key $type $_kbctx)
         (if (if (is-expr $type) (== (car-atom $type) RuleTruth) false)
            (case $value (
               ((sk-val ($_vtype $_vkbctx $_proof $tv) $_ev $_deps) (sk-set-truth-factor! $hash (rule-truth-factor $tv)))
               ($_none ())))
            ()))
      ($_fold ()))))

;; The merged value of a key on behalf of a consumer. A proof or truth-value
;; pattern takes the whole merged value when it admits it, and otherwise the
;; merge of the views it admits.

(= (sk-value $key $filter $exclude)
   (let* (($hash (index-hash $key))
          ($merged
             (case (sk-open-value $hash $key sk-any-filter) (
                ((sk-merged $_hash $_key $deps $value)
                   (if (deps-meet? $exclude $deps)
                      (sk-merge-key $hash $key sk-any-filter $exclude (sk-admitted $hash $key sk-any-filter $exclude))
                      $value))))))
      (if (sk-open-filter? $filter) $merged
         (if (sk-admits? $filter () $merged) $merged
            (sk-merge-key $hash $key $filter $exclude (sk-admitted $hash $key $filter $exclude))))))

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
            (sk-acc (cons $proof $fold-proofs) (sk-union $ev $fold-ev) (cons $fold-deps $deps) $parts)
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

;; --- Conditioning -------------------------------------------------------------
;; A premise whose every value shares fact evidence with what the row already
;; used is read conditioned on the statements of the shared facts: the row is
;; evaluated with such a statement known true and again known false, and the
;; two results mix by the statement's value, P(D) = P(K) P(D | K) + (1 - P(K))
;; P(D | not K), so the shared evidence counts once, through the weight. Under
;; a condition a known statement reads as certain with no evidence, and a view
;; depending on one is its row evaluated again under the same condition; other
;; views, and folds, read as they are.

(: sk-given-hash (-[det]-> SkeletonGiven Number))
(= (sk-given-hash (sk-given $hash $_key $_truth)) $hash)
(= (sk-given-hash (sk-unfounded $hash $_key)) $hash)

(: sk-given-hashes (-[det]-> (List SkeletonGiven) (List Number)))
(= (sk-given-hashes $given) (map-flat sk-given-hash $given))

;; Whether a value depends on a given statement.
(: sk-given-meets? (-[semidet]-> (List SkeletonGiven) SkeletonValue Bool))
(= (sk-given-meets? $given $value)
   (if (== $given ()) false
      (deps-meet? (sk-given-hashes $given) (sk-view-deps-step 0 $value))))

(: sk-pinned-step (-[semidet]-> SkeletonKey (List SkeletonValue) SkeletonGiven (List SkeletonValue)))
(= (sk-pinned-step $key $found $pin)
   (case $pin (
      ((sk-given $hash $given-key $truth)
         (if (=alpha $given-key $key)
            (case $key (
               ((sk-key $type $kbctx)
                  (cons (sk-val (assemble-runtime-fact $type $kbctx (brand Proof (given $truth)) (STV (if $truth 1.0 0.0) 1.0))
                           () (deps-key $hash))
                     $found))
               ($_fold $found)))
            $found))
      ((sk-unfounded $hash $unfounded-key)
         (if (=alpha $unfounded-key $key) (cons (sk-unfounded-value $hash $key) $found) $found)))))

;; A view that depends on a given statement, read under the condition. The
;; view read again is admitted as a stored one is: not when it depends on what
;; the reading rows exclude.
(: sk-given-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey SkeletonVersion SkeletonValue))
(= (sk-given-view $given $exclude $hash $key (sk-version $_seq $rhash $view))
   (if (sk-given-meets? $given $view)
      (case (collapse (once (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
               (if (=alpha $stored $key) (sk-row $ident $concl $premises $seq) (empty))))) (
         ((cons $row $_rest)
            (let $again (sk-row-view $given $exclude $hash $key $rhash $row)
               (if (deps-meet? $exclude (sk-view-deps-step 0 $again)) sk-none $again)))
         (() $view)))
      $view))

;; A key's value under a condition: its value, unless that depends on a given
;; statement; then the merge of its leaves and its views read under it.
(: sk-given-value (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-given-value $given $key $filter $exclude)
   (let $value (sk-value $key $filter $exclude)
      (if (sk-given-meets? $given $value)
         (let $hash (index-hash $key)
            (sk-merge-key $hash $key $filter (hash-union $exclude (hash-set (sk-given-hashes $given)))
               (map-semidet (sk-given-view $given $exclude $hash $key)
                  (sk-admitted-versions $hash $key $filter $exclude))))
         $value)))

;; A premise value whose evidence overlaps what the row already uses is
;; replaced by the merge of the key's leaves and views that do not overlap it:
;; the consumer selects the proofs compatible with its other premises.
(: sk-compatible-step (-[semidet]-> (List Evidence) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-compatible-step $ev $acc $view)
   (case $view (
      ((sk-val $_fact $view-ev $_deps)
         (if (premise-evidence-overlap? $ev $view-ev) $acc (sk-merge-step $acc $view)))
      ($_other $acc))))

(: sk-compatible-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) (List Evidence) Bool SkeletonValue))
(= (sk-compatible-value $given $key $filter $exclude $ev $views)
   (let* (($hash (index-hash $key))
          ($leaves (sk-leaf-views $hash $key $filter (hash-union $exclude (hash-set (sk-given-hashes $given))))))
      (fold-semidet (sk-compatible-step $ev) sk-none
         (if $views
            (append-flat $leaves
               (map-semidet (sk-given-view $given $exclude $hash $key) (sk-admitted-versions $hash $key $filter $exclude)))
            $leaves))))

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
                  (sk-acc $fold-proofs (sk-union $ev $premise-ev) (cons $premise-deps $deps)
                     (sk-add-part $parts $part))
                  sk-fail))))
      ($_none sk-fail))))

(: sk-shared-key-step (-[semidet]-> (List SkeletonGiven) (List SkeletonKey) Evidence (List SkeletonKey)))
(= (sk-shared-key-step $given $keys $entry)
   (case $entry (
      ((fact-ev $kbctx $_proof $type)
         (let $key (sk-key $type $kbctx)
            (if (if (certain-fact-evidence? $entry) false (== (fold-semidet (sk-pinned-step $key) () $given) ()))
               (cons $key $keys)
               $keys)))
      ($_other $keys))))

;; Whether a fact is a projection of a stored or derived conjunction.
(: sk-projection? (-[det]-> SkFact Bool))
(= (sk-projection? $fact)
   (let $step (sk-fact-step-proof $fact)
      (if (is-expr $step)
         (let $head (car-atom $step)
            (if (is-var $head) false
               (if (== $head marginal-proj) true
                  (if (is-expr $head) (== (car-atom $head) proj) false))))
         false)))

;; A clash names the statements of the fact evidence the value shares with the
;; row, less those already given. Conditioning on them evaluates at most the
;; value's dependencies once per truth assignment. There is nothing to
;; condition when the premise reads one of those statements itself, since
;; P(K and K) is P(K), or reads a projection: projections of one source share
;; it by construction and pool, and projecting a conjunction known false has no
;; conditional value.
(: sk-clash-on (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonRowState SkeletonValue SkeletonRowState))
(= (sk-clash-on $given $key $state $value)
   (case $state (
      ((sk-acc $_fold-proofs $ev $_deps $_parts)
         (case $value (
            ((sk-val $fact $value-ev $value-deps)
               (let $keys
                  (list_to_set (fold-semidet (sk-shared-key-step $given) ()
                     (evidence-intersection (fact-evidence-only $ev) (fact-evidence-only $value-ev))))
                  (if (if (sk-projection? $fact) true (stored-list-member? $key $keys)) (sk-clash () 0)
                     (sk-clash $keys (* (pow-math 2 (list-len $keys)) (+ 1 (deps-size $value-deps)))))))
            ($_none sk-fail))))
      ($_failed sk-fail))))

;; --- Closed reads (docs/metta/complete_predicates.md) --------------------------
;; A complete statement's derivations through the reading rule's own
;; conclusion are circular and contribute nothing: a rule application of a
;; complete statement that may read none of a complete premise's views reads
;; the premise's rows evaluated again with its own conclusion unfounded,
;; (STV 0 1). A complete statement with no rule application among its rows is
;; unfounded itself. Both only once the statement's search is settled.

(: sk-unfounded-value (-[det]-> Number SkeletonKey SkeletonValue))
(= (sk-unfounded-value $hash $key)
   (case $key (
      ((sk-key $type $kbctx)
         (sk-val (assemble-runtime-fact $type $kbctx (brand Proof unfounded) (STV 0.0 1.0)) () (deps-key $hash)))
      ($_fold sk-none))))

;; Whether a node has answers and its waiting joins took them all: none is
;; parked or queued for it.
(: sk-delivered? (-[semidet]-> SkPattern Bool))
(= (sk-delivered? $node)
   (if (== (sk-answers $node) ()) false
      (let $hash (sk-node-hash $node)
         (== (collapse (once (superpose (
                 (match &sk_parked ($hash $_seq $_delivery) true)
                 (match &sk_answer_queue ($qseq (sk-delivery $queued $qkey)) (if (=alpha $queued $node) true (empty)))))))
             ()))))

(: sk-application-waits? (-[semidet]-> SkPattern Bool SkPattern Bool))
(= (sk-application-waits? $node $found $child)
   (if $found true
      (if (sk-delivered? $child) false
         (let $hash (sk-node-hash $child)
            (not (== (collapse (once (match &sk_wait ($hash $stored (sk-partial $owner $_rule ($_t $_k $proof $_v) $_ps $_rest $_keys))
                        (if (=alpha $stored $child)
                           (if (=alpha $owner $node) (if (rule-application-proof? $proof) true (empty)) (empty))
                           (empty)))))
                     ()))))))

;; A complete statement's search is settled when its general node is
;; expanded, so every rule concluding it was started, no rule application of
;; it waits on a premise whose answers it has not all taken, and no join or
;; row of it was deferred: every way it becomes true was examined.
(: sk-settled? (-[semidet]-> SkeletonKey Bool))
(= (sk-settled? $key)
   (case $key (
      ((sk-key $type $kbctx)
         (let* (($node (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))
                ($hash (sk-node-hash $node)))
            (if (sk-expanded? $node)
               (if (== (collapse (once (superpose (
                         (match &sk_deferred_joins ($hash $_jhash $_join) true)
                         (match &sk_deferred ($hash $_rhash $_deferred) true)))))
                       ())
                  (if (fold-semidet (sk-application-waits? $node) false (sk-children $node)) false true)
                  false)
               false)))
      ($_fold false))))

;; Whether a rule application is among a statement's rows.
(: sk-founded? (-[det]-> Number SkeletonKey Bool))
(= (sk-founded? $hash $key)
   (not (== (collapse (once (match &sk_row ($hash $stored $_rhash (sk-row $_ident ($_t $_k $proof $_v) $_ps $_seq))
               (if (=alpha $stored $key) (if (rule-application-proof? $proof) true (empty)) (empty)))))
            ())))

(: sk-closed-row-step
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey (List SkeletonValue) (Number SkeletonRow)
       (List SkeletonValue)))
(= (sk-closed-row-step $given $exclude $hash $key $kept ($rhash $row))
   (case (sk-row-view $given $exclude $hash $key $rhash $row) (
      (sk-none $kept)
      ($view (cons $view $kept)))))

;; What a row's closed reads take as unfounded: its own conclusion, when the
;; row is a rule application of a complete statement; nothing otherwise, and
;; the row reads no premise closed.
(: sk-closed-pin (-[det]-> Number Atom Atom Atom (List SkeletonGiven)))
(= (sk-closed-pin $khash $type $kbctx $proof)
   (if (if (rule-application-proof? $proof) (complete-statement? $type $kbctx) false)
      (cons (sk-unfounded $khash (sk-key $type $kbctx)) ())
      ()))

;; The pin, the reading conclusion as unfounded, joins the given list; the
;; rows are evaluated again in creation order and merged with the leaves the
;; reader may read.
(: sk-closed-read
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) SkeletonKey SkeletonFilter SkeletonValue))
(= (sk-closed-read $pin $given $exclude $key $filter)
   (if (== $pin ()) sk-none
      (case $key (
         ((sk-key $type $kbctx)
            (if (if (complete-statement? $type $kbctx) (== (sk-given-value $given $key $filter $exclude) sk-none) false)
               (if (sk-settled? $key)
                  (let $hash (index-hash $key)
                     (if (sk-founded? $hash $key)
                        (sk-merge-key $hash $key $filter $exclude
                           (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-closed-row-step (append-flat $pin $given) $exclude $hash $key) ()
                                 (collapse (match &sk_row ($hash $stored $rhash $row)
                                    (if (=alpha $stored $key) ($rhash $row) (empty)))))))
                        (sk-unfounded-value $hash $key)))
                  sk-none)
               sk-none))
         ($_fold sk-none)))))

;; Each premise reads its key's value without the views that depend on the
;; row's conclusion; reading stored facts first, it takes the facts compatible
;; with the row so far when there are any. A given statement reads as known. A
;; rule application of a complete statement, whose pin is not empty, reads a
;; complete premise closed when it may read none of its views.
(: sk-premise-step
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonRowState SkPattern
       SkeletonRowState))
(= (sk-premise-step $pin $given $exclude $shared $facts-first $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-clash $clash-keys $clash-cost) (sk-clash $clash-keys $clash-cost))
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
               (let $key (sk-key $type $kbctx)
                  (case (fold-semidet (sk-pinned-step $key) () $given) (
                     ((cons $pinned $_more) (sk-use-premise $shared $state $premise $pinned))
                     (()
                        (let* (($filter (sk-filter $proof $tv))
                               ($closed (sk-closed-read $pin $given $exclude $key $filter)))
                           (if (== $closed sk-none)
                              (let $value
                                 (if $facts-first (sk-compatible-value $given $key $filter $exclude $ev false)
                                    (sk-given-value $given $key $filter $exclude))
                                 (case (sk-use-premise $shared $state $premise $value) (
                                    (sk-fail
                                       (if $shared sk-fail
                                          (case (sk-use-premise $shared $state $premise
                                                   (sk-compatible-value $given $key $filter $exclude $ev true)) (
                                             (sk-fail
                                                (sk-clash-on $given $key $state
                                                   (if $facts-first (sk-given-value $given $key $filter $exclude) $value)))
                                             ($compatible $compatible)))))
                                    ($taken $taken))))
                              (sk-use-premise $shared $state $premise $closed))))))))))))))

;; A row reads its premises without the views that depend on its key or on a
;; key unifying with it, nor, under a condition, on what the rows conditioned
;; around it exclude. Premises take values greedily in order, so a merged value
;; may hold evidence a later premise needs: on such a clash the row reads
;; again, on a fresh copy, taking stored facts first. A clash over shared facts
;; that remains is resolved by conditioning on them.
(= (sk-row-view $given $exclude $khash $key $rhash $row)
   (let* (((sk-row $_ident ($_type $_kbctx $proof $_tv) $_premises $_seq) $row)
          ($exclusions (hash-union (sk-row-exclusions $khash $key $proof) $exclude))
          ($greedy (copy_term $row))
          ($state (sk-row-state $given $exclusions $khash false $greedy)))
      (case $state (
         ((sk-clash $_first-keys $_first-cost)
            (let* (($retry (copy_term $row))
                   ($again (sk-row-state $given $exclusions $khash true $retry)))
               (case $again (
                  ((sk-clash $keys $cost) (sk-condition $given $exclusions $khash $key $rhash $row $keys $cost))
                  ($_other (sk-row-result $retry $again))))))
         ($_other (sk-row-result $greedy $state))))))

;; Conditioning is paid for from the evaluation allowance: a row outside any
;; condition is conditioned only once the evaluation granted it the cost, and
;; waits for that otherwise (see sk-pay-conditions!); inside a conditioned read
;; it is part of what was paid for. The statements are taken one at a time: a
;; branch still clashing over another conditions on it in turn.
(: sk-condition
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow (List SkeletonKey) Number
       SkeletonValue))
(= (sk-condition $given $exclusions $khash $key $rhash $row $keys $cost)
   (case $keys (
      (() sk-none)
      ((cons $pin $_more)
         (if (if (== $given ()) (== (collapse (once (match &sk_given_granted ($khash $rhash) true))) ()) false)
            (let $_pending (add-atom &sk_given_pending ($khash $rhash $cost)) sk-none)
            (let* (($phash (index-hash $pin))
                   ($weight (sk-given-value $given $pin sk-any-filter $exclusions))
                   ($true (sk-row-view (cons (sk-given $phash $pin true) $given) $exclusions $khash $key $rhash $row))
                   ($false (sk-row-view (cons (sk-given $phash $pin false) $given) $exclusions $khash $key $rhash $row)))
               (case (collapse (once (sk-mix $weight $true $false))) (
                  ((cons $mixed $_rest) $mixed)
                  (() sk-none)))))))))

;; The branches mix by modus ponens over the weight, when all three are simple
;; truth values and the weight's evidence is not in the branches.
(: sk-mix (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue SkeletonValue))
(= (sk-mix (sk-val ($_wtype $_wkbctx $wproof (STV $ws $wc)) $wev $wdeps)
      (sk-val ($type $kbctx $tproof (STV $ts $tc)) $tev $tdeps)
      (sk-val ($_ftype $_fkbctx $fproof (STV $fs $fc)) $fev $fdeps))
   (let $branch-ev (sk-union $tev $fev)
      (if (premise-evidence-overlap? $wev $branch-ev) (empty)
         (sk-val
            (assemble-runtime-fact $type $kbctx (brand Proof (conditioned $wproof $tproof $fproof))
               (CTVModusPonensFormula (STV $ws $wc) (CTV (STV $ts $tc) (STV $fs $fc))))
            (sk-union $wev $branch-ev) (deps-union $wdeps (deps-union $tdeps $fdeps))))))

(: sk-compound-parts (-[det]-> Atom (List Atom)))
(= (sk-compound-parts $term)
   (if (if (is-expr $term) (stored-list-member? (car-atom $term) (And Or)) false)
      (the (List Atom) (cdr-atom $term))
      ()))

;; The statements with, after each compound And or Or, its parts, nested parts
;; included.
(: sk-statement-parts (-[det]-> (List Atom) (List Atom)))
(= (sk-statement-parts ()) ())
(= (sk-statement-parts (cons $term $rest))
   (cons $term (sk-statement-parts (append-flat (sk-compound-parts $term) $rest))))

(: sk-part-exclusions (-[det]-> KBContext Atom (List Number) (List Number)))
(= (sk-part-exclusions $kbctx $part $hashes)
   (let $key (sk-key $part $kbctx)
      (append-flat (sk-unifier-hashes (index-hash $key) $key) $hashes)))

;; A compound And or Or antecedent is lowered into its parts, so what a rule
;; concludes from it depends on the parts' keys, never on the compound's.
;; Inverting that rule concludes the compound again, so its row also excludes
;; views depending on any part: the premise it inverts was derived from them.
(: sk-row-exclusions (-[det]-> Number SkeletonKey Atom (List Number)))
(= (sk-row-exclusions $khash $key $proof)
   (let $own (sk-unifier-hashes $khash $key)
      (if (if (is-expr $proof)
             (let $head (car-atom $proof)
                (if (is-var $head) false
                   (case (copy_term $head) (((inverted $_rule with $_prior $_token) true) ($_other false)))))
             false)
         (case $key (
            ((sk-key $type $kbctx)
               (hash-set (foldr-flat (sk-part-exclusions $kbctx) $own (sk-statement-parts (cons $type ())))))
            ($_fold $own)))
         $own)))

(: sk-row-state (-[semidet]-> (List SkeletonGiven) (List Number) Number Bool SkeletonRow SkeletonRowState))
(= (sk-row-state $given $exclusions $khash $facts-first (sk-row $_ident ($type $kbctx $proof $_tv) $premises $_seq))
   (fold-semidet
      (sk-premise-step (sk-closed-pin $khash $type $kbctx $proof) $given $exclusions
         (shared-evidence-frontier-proof? $proof) $facts-first)
      (sk-acc () (sk-sample-exclusions $type $kbctx) (cons (deps-key $khash) ()) ())
      $premises))

;; An implication instance sample must not restate the implication it
;; estimates: its row starts out excluding every rule whose premises and
;; conclusion match the sample's antecedent and consequent, so a premise value
;; using one of them clashes and the sample reads the key's other proofs. The
;; rules are found through the conclusion index, by the consequent.
(: sk-sample-exclusions (-[semidet]-> Atom KBContext (List Evidence)))
(= (sk-sample-exclusions $type $kbctx)
   (if (if (is-expr $type) (== (car-atom $type) ImplicationInstanceSample) false)
      (let* (((ImplicationInstanceSample $a $b $_atv $_btv) (copy_term $type))
             (($kbid $_ctx $_vars) $kbctx))
         (collapse
            (match ccls_index (($b ($kbid $_rctx $_rvars) $prf $_tv) $_id $prems)
               (if (= (foldr-flat sk-fact-premise-type () $prems) (implication-side-conjuncts (the Statement $a)))
                  (rule-excluded (brand KB $kbid) (rule-evidence-head $prf))
                  (empty)))))
      ()))

(: sk-fact-premise-type (-[det]-> Atom (List Atom) (List Atom)))
(= (sk-fact-premise-type $premise $types)
   (case $premise (
      ((CPU $_fun $_args $_res) $types)
      (((RuleTruth $_implication) $_kbctx $_prf $_tv) $types)
      (($type $_kbctx $_prf $_tv) (cons $type $types)))))

;; The share of an incomplete fold's members it covered; a complete fold's is 1.
(: sk-fold-share-step (-[semidet]-> Number Proof Number))
(= (sk-fold-share-step $share $proof)
   (case (sk-step-proof $proof) (
      ((partial-fold $covered $total $_inner)
         (let* (($c (the Number $covered)) ($t (the Number $total))) (if (> $t 0) (* $share (/ $c $t)) 0.0)))
      ($_complete $share))))

;; A conclusion drawn from incomplete folds is no more confident than the share
;; of their members they covered.
(: sk-cover-tv (-[det]-> Number TV TV))
(= (sk-cover-tv $share $tv)
   (if (>= $share 1) $tv
      (case $tv (
         ((STV $s $c) (STV $s (* $c $share)))
         ((CTV (STV $ps $pc) (STV $ns $nc)) (CTV (STV $ps (* $pc $share)) (STV $ns (* $nc $share))))
         ($_other $tv)))))

(: sk-row-result (-[semidet]-> SkeletonRow SkeletonRowState SkeletonValue))
(= (sk-row-result (sk-row $_ident ($type $kbctx $proof $tv) $_premises $_seq) $state)
   (case $state (
      ((sk-acc $fold-proofs $ev $deps $_parts)
         (let* (((token-state $full-proof $_unused)
                   (replace-token $proof (fold-semidet sk-cons-step () $fold-proofs)))
                ($fact (assemble-runtime-fact $type $kbctx (sk-unwrap-proof $full-proof)
                          (sk-cover-tv (fold-semidet sk-fold-share-step 1 $fold-proofs) $tv))))
            (sk-val $fact (rule-result-evidence $fact $ev) (deps-join $deps))))
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
;; removed query-local row, fold members) caused by the keys with these hashes,
;; with the dependencies of the new view.
(: SkeletonChange Type)
(: sk-view-change (-[det]-> Number SkeletonChange))
(: sk-value-same (-[det]-> Number Number SkeletonChange))
(: sk-outside-change (-[det]-> (List Number) Number SkeletonChange))

(: sk-change-deps (-[det]-> SkeletonChange Number))
(= (sk-change-deps (sk-view-change $deps)) $deps)
(= (sk-change-deps (sk-value-same $deps $_merged-deps)) $deps)
(= (sk-change-deps (sk-outside-change $_causes $deps)) $deps)

;; Every fact premise on the key asks for an open pattern.
(: sk-reads-open? (-[det]-> SkeletonKey Atom SkPattern Bool))
(= (sk-reads-open? $key $open $premise)
   (if $open
      (case $premise (
         (($type $kbctx $proof $tv)
            (if (=alpha (sk-key $type $kbctx) $key) (if (is-var $proof) (is-var $tv) false) true))
         ($_cpu true)))
      false))

;; A reader whose own key the new view depends on does not admit it, unless it
;; reads the key closed: a rule application of a complete statement reading a
;; complete one evaluates the key's rows again, whatever their views depend
;; on. When the key's open merged value did not change, a reader outside its
;; dependencies that reads it openly gets that same value.
(: sk-reads-closed? (-[det]-> SkeletonKey SkeletonRow Bool))
(= (sk-reads-closed? $key (sk-row $_ident ($rtype $rkbctx $rproof $_rtv) $_premises $_seq))
   (case $key (
      ((sk-key $type $kbctx)
         (if (complete-statement? $type $kbctx)
            (if (rule-application-proof? $rproof) (complete-statement? $rtype $rkbctx) false)
            false))
      ($_fold false))))

(: sk-reader-affected? (-[semidet]-> SkeletonKey SkeletonChange SkeletonItem Bool))
(= (sk-reader-affected? $key $change (sk-row-item $_seq $khash $_rkey $_rhash (sk-row $ident $concl $premises $s)))
   (case $change (
      ((sk-outside-change $_causes $_deps) true)
      ((sk-view-change $deps)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s)) true))
      ((sk-value-same $deps $merged-deps)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s))
            (if (deps-has? $merged-deps $khash) true
               (if (fold-semidet (sk-reads-open? $key) true $premises) false true)))))))

;; A reader created after the row that changed its input is still ahead in
;; this pass; an earlier one waits for the next.
(: sk-schedule-reader
   (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonItem SkeletonWork))
(= (sk-schedule-reader $pass $seq $key $change (sk-work $todo $next) $item)
   (if (if (sk-item-needed? $item) false (let $_stale (sk-mark-stale! $item) true)) (sk-work $todo $next)
   (if (let $_forced
          (case $change (
             ((sk-outside-change $causes $_deps) (sk-force! $causes $item))
             ($_view ())))
          (sk-reader-affected? $key $change $item))
      (if (> (sk-item-seq $item) $seq)
         (if (sk-queue-new? $pass $item)
            (sk-work (add_to_heap $todo (sk-item-seq $item) $item) $next)
            (sk-work $todo $next))
         (if (sk-queue-new? (+ $pass 1) $item)
            (sk-work $todo (add_to_heap $next (sk-item-seq $item) $item))
            (sk-work $todo $next)))
      (sk-work $todo $next))))

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
      (fold-semidet (sk-fold-changed $pass $seq $key $change) $scheduled $folds)))

;; A member change of a fold that was read queues the fold's check at the end
;; of the pass, unless the member's new view depends on the fold, which the fold
;; does not admit; so the members changed in one pass recompute it once; until
;; then its readers read the value it had. A fold nobody read since it last
;; changed is computed when next read. A base-rate fold also records the
;; member to take, unless the change came through the rate itself: a past
;; belief that reads the rate as its prior changes whenever the rate moves, and
;; would otherwise be needed and taken again each time. A check queued for this
;; pass is also queued for the next, in case this pass's check already ran.
(: sk-check-seq (-[det]-> Number))
(= (sk-check-seq) 1000000000000000)

(: sk-fold-changed (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-fold-changed $pass $_seq $member $change (sk-work $todo $next) $fold)
   (let $hash (index-hash $fold)
      (if (deps-has? (sk-change-deps $change) $hash) (sk-work $todo $next)
      (let $_rate (sk-rate-dirty! $fold $member)
      (if (== (sk-latest-view $hash $fold 0) sk-none) (sk-work $todo $next)
      (if (if (sk-needed? $hash $fold) false (let $_stale (sk-stale-fold! $fold) true)) (sk-work $todo $next)
         (let* (($mhash (index-hash $member))
                ($_pending (add-atom &sk_fold_pending ($hash $mhash)))
                ($check (sk-fold-check $hash $fold)))
            (if (sk-queue-new? $pass $check) (sk-work (add_to_heap $todo (sk-check-seq) $check) $next)
               (if (sk-queue-new? (+ $pass 1) $check) (sk-work $todo (add_to_heap $next (sk-check-seq) $check))
                  (sk-work $todo $next))))))))))

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

;; Whether a view brings a dependency none of the row's views had.
(: sk-new-support? (-[semidet]-> Number Number SkeletonValue Bool))
(= (sk-new-support? $hash $rhash $new)
   (if (deps-within? (sk-view-deps-step 0 $new) (sk-row-support $hash $rhash)) false true))

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
   (let* (($causes (list_to_set (collapse (match &sk_fold_pending ($hash $member) $member))))
          ($_taken (remove-data-rows! &sk_fold_pending (quote ($hash $member))))
          ($old (sk-latest-view $hash $fold 0)))
      (if (if (== $causes ()) true (== $old sk-none)) $work
         (let* (($_view (sk-drop-fold-view! $fold))
                ($_merged (sk-drop-merged! $fold)))
            (case (sk-fold-views $hash $fold) (
               ((cons (sk-version $_seq $_rhash $new) $_rest)
                  (if (if (sk-same-view? $new $old) (== (sk-view-step-proof $new) (sk-view-step-proof $old)) false)
                     $work
                     (sk-key-changed $pass (sk-check-seq)
                        (sk-outside-change $causes (sk-view-deps-step 0 $new)) $work $fold)))
               (() (sk-key-changed $pass (sk-check-seq) (sk-outside-change $causes 0) $work $fold))))))))

;; A row whose view differs from its latest version stores a new version and
;; changes its key, when it is the row's first view, it was forced, or it
;; brings new support. A forced row also stores a view that differs only in
;; its proof: an outside change such as a completed fold improves provenance.
(: sk-compute (-[semidet]-> Number SkeletonWork SkeletonItem SkeletonWork))
(= (sk-compute $pass $work (sk-fold-check $hash $fold)) (sk-check-fold $pass $work $hash $fold))
(= (sk-compute $pass $work (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_computed (query_metric_increment row-computes))
          ($causes (collapse (match &sk_forced ($hash $rhash $cause) $cause)))
          ($_taken (remove-data-rows! &sk_forced (quote ($hash $rhash $cause))))
          ($forced (not (== $causes ())))
          ($_unpaid (remove-data-rows! &sk_given_pending (quote ($hash $rhash $_cost))))
          ($new (sk-row-view () () $hash $key $rhash $row)))
      (case $new (
         ;; A row forced by an outside change that no longer derives anything
         ;; (a premise fact was removed) drops its views, and its key changed;
         ;; one waiting for conditioning keeps them.
         ;; A row that derived nothing records empty support: it was computed,
         ;; so a fold over its key does not wait for it (sk-member-pending?).
         (sk-none
            (if (if $forced
                   (if (== (sk-latest-view $hash $key $rhash) sk-none) false
                      (== (collapse (once (match &sk_given_pending ($hash $rhash $_waits) true))) ()))
                   false)
               (let* (($_views (sk-drop-row-views! $hash $key $rhash))
                      ($_merged (sk-drop-merged! $key))
                      ($_derived-nothing (add-atom &sk_support ($hash $rhash 0))))
                  (sk-key-changed $pass $seq (sk-outside-change $causes 0) $work $key))
               ;; A closed reader of a complete key evaluates its rows again,
               ;; so a new row that derives nothing, or a forced one, still
               ;; changes the key for it.
               (let $first (not (space-row-present? &sk_support ($hash $rhash $_had)))
                  (let $_nothing (if $first (add-atom &sk_support ($hash $rhash 0)) true)
                     (if (if (if $first true $forced)
                            (case $key (((sk-key $type $kbctx) (complete-statement? $type $kbctx)) ($_fold false)))
                            false)
                        (sk-key-changed $pass $seq (if $forced (sk-outside-change $causes 0) (sk-view-change 0)) $work $key)
                        $work)))))
         ($_view
            (let $latest (sk-latest-view $hash $key $rhash)
            (if (if (sk-same-view? $new $latest)
                   (if $forced (== (sk-view-step-proof $new) (sk-view-step-proof $latest)) true)
                   (if $forced false
                      (if (== $latest sk-none) false
                         (if (sk-new-support? $hash $rhash $new) false
                            (let $_unsupported (query_metric_increment views-without-support) true)))))
               $work
               (let* (($before
                         (collapse (once (match &sk_merged (sk-merged $hash $stored $deps $value)
                            (if (=alpha $stored $key) (sk-merged $hash $stored $deps $value) (empty))))))
                      ($_stored (sk-store-view! $hash $key $seq $rhash $new))
                      ($_stored-count (query_metric_increment views-stored))
                      ($_merged (sk-drop-merged! $key))
                      ($deps (sk-view-deps-step 0 $new)))
                  (sk-key-changed $pass $seq
                     (if (if $forced (not (sk-same-view? $new $latest)) false)
                        (sk-outside-change $causes $deps)
                        (sk-value-change $hash $key $deps $before))
                     $work $key)))))))))

;; An unchanged open merged value is known only when it was cached before.
(: sk-value-change (-[semidet]-> Number SkeletonKey Number (List SkeletonMerged) SkeletonChange))
(= (sk-value-change $hash $key $deps $before)
   (case $before (
      (() (sk-view-change $deps))
      ((cons (sk-merged $_h $_k $old-deps $old-value) $_rest)
         (case (sk-open-value $hash $key sk-any-filter) (
            ((sk-merged $_h2 $_k2 $new-deps $new-value)
               (if (=alpha $old-value $new-value)
                  (sk-value-same $deps (deps-union $old-deps $new-deps))
                  (sk-view-change $deps)))))))))

;; Works off the queued rows and returns the last pass. A row a query needs
;; that the stale cascade reached meanwhile (a fold it reads went stale over a
;; member left stale) is brought current and computed in a further pass, forced
;; by its own key, each such row once per evaluation: the query reads no value
;; from before what it needs. A forward run leaves such rows stale for the
;; query that next needs them, so its cost does not grow with every reader of
;; a fold its new facts change. That includes readers of the keys the run
;; takes: a reader computed early in a wave that a later change in the wave
;; reaches stays stale, so the run can return and store its value from before
;; that change. A query that needs it within the free depth refreshes it
;; first; deeper, it is read like any other stale row.
;; Refreshing those readers in the run (tried Oct 2) changed no StationOps
;; answer and cost forward time growing with the KB (+1% at 10 modules, +9%
;; at 20).
(: sk-work-off! (-[semidet]-> Number SkeletonWork Number))
(= (sk-work-off! $pass (sk-work $todo $next))
   (if (heap-empty? $todo)
      (if (heap-empty? $next)
         (let* (($restale (collapse (match &sk_restale ($khash $rhash) ($khash $rhash))))
                ($_taken (remove-data-rows! &sk_restale (quote ($khash $rhash))))
                ($again (fold-semidet sk-restale-step (empty_heap) $restale)))
            (if (heap-empty? $again) $pass (sk-work-off! (+ $pass 1) (sk-work $again (empty_heap)))))
         (sk-work-off! (+ $pass 1) (sk-work $next (empty_heap))))
      (sk-work-pop! $pass $next (heap_pop $todo))))

(: sk-restale-step (-[semidet]-> (Heap SkeletonItem) (Number Number) (Heap SkeletonItem)))
(= (sk-restale-step $todo ($khash $rhash))
   (if (if (space-row-present? &sk_stale ($khash $rhash)) (not (space-row-present? &sk_restaled ($khash $rhash))) false)
      (case (collapse (once (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
               (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq))))) (
         ((cons (sk-row-item $seq $khash2 $key $rhash2 (sk-row $ident $concl $premises $seq2)) $_rest)
            (let* (($item (sk-row-item $seq $khash2 $key $rhash2 (sk-row $ident $concl $premises $seq2)))
                   ($_seen (add-atom &sk_restaled ($khash $rhash)))
                   ($_relinked (sk-relink-row! $khash $rhash $premises))
                   ($_forced (sk-force! (cons $khash ()) $item)))
               (add_to_heap $todo $seq $item)))
         (() $todo)))
      $todo))

(: sk-work-pop!
   (-[semidet]-> Number (Heap SkeletonItem) (Number SkeletonItem (Heap SkeletonItem)) Number))
;; Each row commits to its one result, so the loop leaves no choice points and
;; runs in constant stack however many rows it computes.
(= (sk-work-pop! $pass $next ($_seq $item $rest))
   (if (if (== (search-id-value sk_forward_run) 1) (sk-take! sk_eval_budget)
          (if (<= (sk-item-depth $item) (sk-evaluation-free-depth)) true (sk-take! sk_eval_budget)))
      (sk-work-off! $pass (once (sk-compute $pass (sk-work $rest $next) $item)))
      (let $_stale (sk-mark-stale! $item) (sk-work-off! $pass (sk-work $rest $next)))))

;; A query computes the rows near its roots in full and spends an allowance on
;; the rest; what the allowance cannot pay for is left stale, as if no query
;; needed it, and a later query that reads it recomputes it from its inputs
;; then. Creation order is kept, so an allowance that covers everything
;; computes what a query without one would.
(: sk-item-depth (-[det]-> SkeletonItem Number))
(= (sk-item-depth (sk-row-item $_seq $khash $key $_rhash $_row)) (sk-need-depth $khash $key))
(= (sk-item-depth (sk-fold-check $hash $fold)) (sk-need-depth $hash $fold))

;; How near a root a key must be for its rows to be computed in full. A
;; forward run computes nothing in full: every row it computes costs one of
;; its units, and its need stops at the readers of the keys it takes.
(: sk-evaluation-free-depth (-[det]-> Number))
(= (sk-evaluation-free-depth) (if (== (search-id-value sk_forward_run) 1) 0 2))

;; Row recomputations a query may spend per step of its budget beyond that.
(: sk-evaluation-per-step (-[det]-> Number))
(= (sk-evaluation-per-step) 2)

;; Expanded nodes a query's walk may pass through per step of its budget.
(: sk-walk-per-step (-[det]-> Number))
(= (sk-walk-per-step) 1)

;; Keys changed outside evaluation: a fold or group key recomputes when next
;; read, and every changed key's readers are scheduled.
(: sk-dirty-seed (-[semidet]-> SkeletonWork SkeletonKey SkeletonWork))
(= (sk-dirty-seed $work $key)
   (let* (($_view
             (case $key (
                ((sk-key $_type $_kbctx) ())
                ($_fold (sk-drop-fold-view! $key)))))
          ($_merged (sk-drop-merged! $key)))
      (sk-key-changed 0 -1 (sk-outside-change (cons (index-hash $key) ()) 0) $work $key)))

;; --- Demand -----------------------------------------------------------------
;; A query brings current only what its roots read: their keys, the premise
;; keys of those keys' rows, and the members of the folds and groups among
;; them. A row outside that set whose input changes is marked stale instead of
;; computed, and so is everything reading it, once; a later query that reads it
;; again recomputes it. A stale row leaves the reader lists of the keys it
;; reads until then, so a change walks only readers that are current, and
;; earlier queries' rows cost nothing per query or per change.

;; Signatures of the mutually recursive functions below.
(: sk-need! (-[semidet]-> Number Atom SkeletonKey Atom))
(: sk-stale-key! (-[det]-> SkeletonKey Atom))

(: sk-needed? (-[det]-> Number SkeletonKey Bool))
(= (sk-needed? $hash $key)
   (not (== (collapse (once (match &sk_needed ($hash $stored $_depth) (if (=alpha $stored $key) true (empty))))) ())))

;; How many rows or folds lie between a needed key and the nearest root.
(: sk-need-depth (-[det]-> Number SkeletonKey Number))
(= (sk-need-depth $hash $key)
   (case (collapse (once (match &sk_needed ($hash $stored $depth) (if (=alpha $stored $key) $depth (empty))))) (
      ((cons $depth $_rest) $depth)
      (() 1000000))))

(: sk-need-premise! (-[semidet]-> Number Atom SkPattern Atom))
(= (sk-need-premise! $depth $_acc $premise)
   (case $premise (
      ((CPU FoldAllCompiled $fold-args $_fold-res) (sk-need! $depth () (sk-fold $fold-args)))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res) (sk-need! $depth () (sk-group $group-args)))
      ((CPU $_fun $_args $_res) ())
      (($type $kbctx $_proof $_tv) (sk-need! $depth () (sk-key $type $kbctx))))))

;; A stale row within the depth computed in full rejoins its keys' readers and
;; is recomputed by the evaluation, and so does a stale row at any depth that
;; has no value yet: a row a forward run created but could not pay for. A
;; deeper stale row keeps its value and stays
;; out of the change path: only a need that reaches it that closely, such as a
;; query asking for it, brings it current. So a change below a long chain, such
;; as a base rate every past belief read, costs once per stale row and never
;; recomputes the history no one asked for.
;;
;; Below that depth the need goes on only through rows never computed or
;; waiting to be conditioned. A current row's inputs are current, since every
;; change reaches the readers of what changed, and a stale one is not brought
;; current, so there is nothing under either to recompute.
;;
;; A stale row brought current leaves the stale set and rejoins its keys'
;; readers.
(: sk-relink-row! (-[semidet]-> Number Number (List SkPattern) Atom))
(= (sk-relink-row! $khash $rhash $premises)
   (let* (($_fresh (remove-atom &sk_stale ($khash $rhash)))
          ($keys (fold-semidet sk-direct-key-step () $premises))
          ($_unmarked (fold-semidet (sk-drop-stale-reader! $khash $rhash) () $keys))
          ($_linked (fold-semidet (sk-add-reader! $khash $rhash) () $keys)))
      ()))

(: sk-need-row! (-[semidet]-> Number Atom SkeletonItem Atom))
(= (sk-need-row! $depth $_acc (sk-row-item $_seq $khash $key $rhash (sk-row $_ident $_concl $premises $_s)))
   (let* (($unseen (== (sk-latest-view $khash $key $rhash) sk-none))
          ($refresh
             (if (if $unseen true (<= $depth (+ (sk-evaluation-free-depth) 1)))
                (not (== (collapse (once (match &sk_stale ($khash $rhash) true))) ()))
                false))
          ($_refreshed
             (if $refresh
                (let $_relinked (sk-relink-row! $khash $rhash $premises) (add-atom &sk_refresh ($khash $rhash)))
                ())))
      (if (if $refresh true
             (if (<= $depth (sk-evaluation-free-depth)) true
                (if $unseen true
                   (not (== (collapse (once (match &sk_given_pending ($khash $rhash $_cost) true))) ())))))
         (fold-semidet (sk-need-premise! $depth) () $premises)
         ())))

;; A key is needed at the fewest steps from a root it is reached by; reaching
;; it more closely than before passes the smaller depth on to what it reads.
(= (sk-need! $depth $_acc $key)
   (let $hash (index-hash $key)
      (case (collapse (once (match &sk_needed ($hash $stored $was)
               (if (=alpha $stored $key) (sk-need-was $stored $was) (empty))))) (
         ((cons (sk-need-was $stored $was) $_rest)
            (if (<= $was $depth) ()
               (let* (($_old (remove-variant-row! &sk_needed (quote ($hash $stored $was))))
                      ($_new (add-atom &sk_needed ($hash $key $depth))))
                  (sk-need-below! $depth $hash $key))))
         (() (let* (($_new (add-atom &sk_needed ($hash $key $depth)))
                    ($_touched (sk-touch-key! $hash $key)))
                (sk-need-below! $depth $hash $key)))))))

(: SkeletonNeedWas Type)
(: sk-need-was (-[det]-> SkeletonKey Number SkeletonNeedWas))

(: sk-need-below! (-[semidet]-> Number Number SkeletonKey Atom))
(= (sk-need-below! $depth $hash $key)
   (let $below (+ $depth 1)
      (case $key (
         ((sk-key $_type $_kbctx)
            (fold-semidet (sk-need-row! $below) ()
               (collapse (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
                  (if (=alpha $stored $key)
                     (sk-row-item $seq $hash $stored $rhash (sk-row $ident $concl $premises $seq))
                     (empty))))))
         ((sk-fold $args)
            (if (sk-rate-fold? $key)
               (let $changed
                  (collapse (match &sk_rate_dirty ($hash $fold $joined)
                     (if (=alpha $fold $key) $joined (empty))))
                  (if (== $changed ()) ()
                     (let* (($_members (fold-semidet (sk-need! $below) () $changed))
                            ($_taken (sk-rate-take! $hash (the ScalarFoldSpec $args))))
                        (sk-mark-dirty! $key))))
               (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
                  ((cons $member $_rest) (fold-semidet (sk-need! $below) () (sk-answers $member)))
                  (() ())))))
         ((sk-group $group-args)
            (case (sk-group-members $key $group-args) (
               ((sk-group-found $_member $members) (fold-semidet (sk-need! $below) () $members))
               (sk-group-missing ()))))))))

(: sk-need-root! (-[semidet]-> Atom SkPattern Atom))
(= (sk-need-root! $_acc $goal) (fold-semidet (sk-need! 0) () (sk-root-keys $goal)))

;; A stale row leaves the reader lists of the keys it reads, so a change walks
;; only current readers; it is kept as a stale reader of those keys, which a
;; forward run taking one of them brings back.
(: sk-unlink-reader! (-[det]-> Number Number (List SkPattern) Atom))
(= (sk-unlink-reader! $khash $rhash $premises)
   (fold-flat (sk-stale-reader! $khash $rhash) () (fold-flat sk-direct-key-step () $premises)))

(: sk-mark-stale! (-[det]-> SkeletonItem Atom))
(= (sk-mark-stale! (sk-row-item $_seq $khash $key $rhash (sk-row $_ident $_concl $premises $_s)))
   (if (== (collapse (once (match &sk_stale ($khash $rhash) true))) ())
      (let* (($_stale (add-atom &sk_stale ($khash $rhash)))
             ($_unlinked (sk-unlink-reader! $khash $rhash $premises)))
         (sk-stale-key! $key))
      ()))
(= (sk-mark-stale! (sk-fold-check $_hash $fold)) (sk-stale-fold! $fold))

;; A fold over a stale key drops its view, so it is recomputed when read.
(: sk-stale-fold! (-[det]-> SkeletonKey Atom))
(= (sk-stale-fold! $fold)
   (if (== (sk-latest-view (index-hash $fold) $fold 0) sk-none) ()
      (let* (($_view (sk-drop-fold-view! $fold))
             ($_merged (sk-drop-merged! $fold)))
         (sk-stale-key! $fold))))

(: sk-stale-reader-step (-[det]-> Atom SkeletonItem Atom))
(= (sk-stale-reader-step $_acc (sk-row-item $seq $khash $key $rhash $row))
   (let $_restale
      (if (if (== (search-id-value sk_forward_run) 0) (sk-needed? $khash $key) false)
         (if (space-row-present? &sk_restale ($khash $rhash)) () (let $_row (add-atom &sk_restale ($khash $rhash)) ()))
         ())
      (sk-mark-stale! (sk-row-item $seq $khash $key $rhash $row))))
(= (sk-stale-reader-step $_acc (sk-fold-check $hash $fold)) (sk-mark-stale! (sk-fold-check $hash $fold)))

(= (sk-stale-key! $key)
   (let* (($hash (index-hash $key))
          ($_readers (fold-flat sk-stale-reader-step () (sk-readers $key))))
      (foreach-flat sk-stale-fold!
         (collapse (match &sk_use ($hash $stored $fold)
            (if (=alpha $stored $key) (if (sk-rate-fold? $fold) (empty) $fold) (empty)))))))

(: sk-item-needed? (-[det]-> SkeletonItem Bool))
(= (sk-item-needed? (sk-row-item $_seq $hash $key $_rhash $_row)) (sk-needed? $hash $key))
(= (sk-item-needed? (sk-fold-check $hash $fold)) (sk-needed? $hash $fold))

(: sk-seed-new (-[det]-> (Heap SkeletonItem) SkeletonItem (Heap SkeletonItem)))
(= (sk-seed-new $todo $item)
   (if (sk-item-needed? $item)
      (if (sk-queue-new? 0 $item) (add_to_heap $todo (sk-item-seq $item) $item) $todo)
      (let $_stale (sk-mark-stale! $item) $todo)))

(: sk-evaluate! (-[semidet]-> Atom))
(= (sk-evaluate!)
   (let* (($_queued (remove-data-rows! &sk_queued (quote ($pass $khash $rhash))))
          ($_cleared-forced (remove-data-rows! &sk_forced (quote ($khash $rhash $cause))))
          ($_used (remove-data-rows! &sk_forced_used (quote ($khash $rhash $cause))))
          ($_pending (remove-data-rows! &sk_fold_pending (quote ($fhash $member))))
          ;; an incomplete fold the query needs is checked again: its members
          ;; may have been searched, or found to derive nothing, since
          ($partial
             (collapse (match &sk_partial ($phash $pfold)
                (if (sk-needed? $phash $pfold)
                   (let $_cause (add-atom &sk_fold_pending ($phash $phash)) (sk-fold-check $phash $pfold))
                   (empty)))))
          ($_granted (remove-data-rows! &sk_given_granted (quote ($khash $rhash))))
          ($_restale (remove-data-rows! &sk_restale (quote ($khash $rhash))))
          ($_restaled (remove-data-rows! &sk_restaled (quote ($khash $rhash))))
          ($new (collapse (match &sk_new (sk-row-item $seq $hash $key $rhash $row)
             (sk-row-item $seq $hash $key $rhash $row))))
          ($_new (remove-data-rows! &sk_new (quote (sk-row-item $seq $hash $key $rhash $row))))
          ($dirty (collapse (match &sk_dirty ($hash $key) $key)))
          ($_dirty (remove-data-rows! &sk_dirty (quote ($hash $key))))
          ;; a stale row the query needs is forced by its own key
          ($refresh
             (collapse (match &sk_refresh ($khash $rhash)
                (let $_taken (remove-atom &sk_refresh ($khash $rhash))
                   (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
                      (let* (($item (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq)))
                             ($_forced (sk-force! (cons $khash ()) $item)))
                         $item))))))
          ($seeded
             (fold-semidet sk-dirty-seed
                (sk-work (fold-semidet sk-seed-new (empty_heap) (append-flat $new (append-flat $refresh $partial)))
                   (empty_heap))
                $dirty)))
      (sk-pay-conditions! (+ (sk-work-off! 0 $seeded) 1))))

;; Rows waiting for conditioning are paid for from what the evaluation
;; allowance has left: nearest a root first, then cheapest, then oldest. The
;; first one the allowance cannot pay for waits, with the rest, for a later
;; query that needs it, so a larger allowance extends the same prefix. A paid
;; row is recomputed, conditioned, with its readers.
(: SkeletonClaim Type)
(: sk-claim (-[det]-> Number Number Number SkeletonItem SkeletonClaim))

(: sk-pay-conditions! (-[semidet]-> Number Atom))
(= (sk-pay-conditions! $pass)
   (case (sort-atom
            (collapse (match &sk_given_pending ($khash $rhash $cost)
               (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
                  (if (sk-needed? $khash $key)
                     (sk-claim (sk-need-depth $khash $key) $cost $seq
                        (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq)))
                     (empty)))))) (
      (() ())
      ((cons (sk-claim $_depth $claim-cost $_seq (sk-row-item $item-seq $item-hash $item-key $item-rhash $item-row)) $_rest)
         (let $left (search-id-value sk_eval_budget)
            (if (> $claim-cost $left) ()
               (let* (($item (sk-row-item $item-seq $item-hash $item-key $item-rhash $item-row))
                      ($_paid (change-state! sk_eval_budget (- $left $claim-cost)))
                      ($_taken (remove-data-rows! &sk_given_pending (quote ($item-hash $item-rhash $_was))))
                      ($_granted (add-atom &sk_given_granted ($item-hash $item-rhash)))
                      ($_forced (sk-force! (cons $item-hash ()) $item))
                      ($last (sk-work-off! $pass (sk-work (add_to_heap (empty_heap) $item-seq $item) (empty_heap)))))
                  (sk-pay-conditions! (+ $last 1)))))))))

;; --- Base-rate API ----------------------------------------------------------

;; Setting or clearing a user base rate changes the folds over its pattern,
;; which recompute with their readers at the next evaluation.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($hash (base-rate-cache-hash $kbid $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (add-atom &base_rate_cache ($hash (base-rate $kbid $stored $tv user any)))))
      (base-rate-readers-changed! $kbid $pattern)))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $pattern)
   (let $_old (base-rate-cache-remove! $kbid $pattern)
      (base-rate-readers-changed! $kbid $pattern)))

;; --- Materialization --------------------------------------------------------

(: materialized-rows (-[det]-> ForwardOutputKey (List MaterializedRow)))
(= (materialized-rows (forward-output-key $kb $type))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (collapse (match &materialized_facts (materialized-row $hash $type $kb $fact $ev)
         (materialized-row $hash $type $kb $fact $ev)))))

(: remove-materialized! (-[det]-> MaterializedRow Atom))
(= (remove-materialized! (materialized-row $hash $type $kb ($type $kb $proof $tv) $ev))
   (let* (($_fact (remove-atom &kb ($type $kb $proof $tv)))
          ($_unindex (kb-unindex-fact! ($type $kb $proof $tv)))
          ($_mark (remove-atom &materialized_facts (materialized-row $hash $type $kb ($type $kb $proof $tv) $ev))))
      ()))

;; A re-materialization of an output key replaces the key's earlier
;; materialized rows. Marked facts are never leaves of the backward search.
(: upsert-materialized! (-[semidet]-> SkFact (List Evidence) Atom))
(= (upsert-materialized! ($type $kb $proof $tv) $ev)
   (let* (($fact (data $type $kb $proof $tv))
          ($hash (forward-output-index-hash (forward-output-key $kb $type)))
          ($row (materialized-row $hash $type $kb $fact $ev)))
      (if (space-row-present? &materialized_facts $row) ()
         (let* (($_remove (foreach-flat remove-materialized! (materialized-rows (forward-output-key $kb $type))))
                ($_add (chainer-add-atom &kb $fact))
                ($_index (kb-index-fact! live $fact))
                ($_mark (add-atom &materialized_facts $row))
                ($_journal (sk-note-fact! $type $kb)))
            (record-fact-inheritance-nodes! $fact false)))))

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
            (upsert-materialized! (sk-full-fact $fact) $ev)
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
;; A complete statement whose settled search found no rule application is
;; unfounded (docs/metta/complete_predicates.md).
(: sk-root-key-value (-[semidet]-> SkPattern SkeletonKey SkeletonValue))
(= (sk-root-key-value $goal $key)
   (case (copy_term $goal) (
      ((CPU $_fun $_args $_res) sk-none)
      (($type $kbctx $proof $tv)
         (let $ground (== (extract-vars $type) ())
            (if (= (sk-key $type $kbctx) (copy_term $key))
               (let $filter (sk-filter $proof $tv)
                  (case (sk-value $key $filter ()) (
                     (sk-none
                        (if (if (complete-statement? $type $kbctx)
                               (if (sk-settled? $key) (not (sk-founded? (index-hash $key) $key)) false)
                               false)
                           (sk-unfounded-value (index-hash $key) $key)
                           (case (sk-materialized-views $type $kbctx $filter) (
                              ((cons $incumbent $_rest) $incumbent)
                              (() (if $ground (sk-population-prior $type $kbctx $filter) sk-none))))))
                     ($current $current))))
               sk-none))))))

(: sk-materialized-views (-[det]-> Statement KBContext SkeletonFilter (List SkeletonValue)))
(= (sk-materialized-views $type $kbctx $filter)
   (if (== (extract-vars $type) ())
      (let $hash (forward-output-index-hash (forward-output-key $kbctx $type))
         (collapse (match &materialized_facts (materialized-row $hash $type $kbctx $fact $ev)
            (if (sk-fact-matches? $filter $fact) (sk-val $fact $ev 0) (empty)))))
      ()))

;; A ground root the search left without a value answers with the base rate
;; of its population: a base rate one of its rules reads over a pattern its
;; statement belongs to, the prior its inversions update. It costs no
;; expansion, so a root the budget did not reach still has an estimate, with
;; the confidence of the members counted; any view the search finds replaces
;; it. A rate of 0 or 1 gives none, as it gives inversions no prior: a
;; knowledge base storing only true instances has rate 1 for every predicate
;; it stores. The prior is the population's value, not the statement's, and
;; is never materialized.
(: sk-population-prior (-[semidet]-> Statement KBContext SkeletonFilter SkeletonValue))
(= (sk-population-prior $type $kbctx $filter)
   (case (collapse
            (let* (((sk-match $_rule $premises $_goal) (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_proof $_tv)))
                   ((CPU FoldAllCompiled $args $_result) (superpose $premises))
                   ((base-rate-aggregate-key-value $_kbid $pattern $_mode) (base-rate-aggregate-key $args)))
               (if (= (copy_term $pattern) (copy_term $type)) $args (empty)))) (
      ((cons $args $_more)
         (case (sk-value (sk-fold $args) sk-any-filter ()) (
            ((sk-goal-val (CPU $_fun $_args (STV $s $c)) $_fold-proof $_ev $deps)
               (let $fact (data $type $kbctx (brand Proof (population-prior (car-atom (cdr-atom $args)))) (STV $s $c))
                  (if (if (uncertain-rate? (STV $s $c)) (sk-fact-matches? $filter $fact) false) (sk-val $fact () $deps) sk-none)))
            ($_none sk-none))))
      (() sk-none))))

;; The keys a root reads, in first-answer order; a ground root reads its own
;; key, answered or not.
(: sk-root-keys (-[semidet]-> SkPattern (List SkeletonKey)))
(= (sk-root-keys $goal)
   (case $goal (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled) (cons (sk-fold $args) ())
            (if (== $fun GroupedFoldAllCompiled) (sk-answers $goal) ())))
      (($type $kbctx $_proof $_tv)
         (alpha_unique_keys
            (append-flat (sk-statement-answers $type $kbctx)
               (if (== (extract-vars $type) ()) (cons (sk-key $type $kbctx) ())
                  (collapse (match &kb ($type $kbctx $_proof $_tv) (sk-key $type $kbctx))))))))))

(: sk-root-values (-[semidet]-> SkPattern (List SkeletonValue)))
(= (sk-root-values $goal)
   (case $goal (
      ((CPU $fun $args $res)
         (if (== $fun FoldAllCompiled)
            (cons (sk-value (sk-fold $args) sk-any-filter ()) ())
            (if (== $fun GroupedFoldAllCompiled)
               (map-semidet (sk-root-value sk-any-filter) (sk-root-keys $goal))
               (collapse (let $result (cpu-call 0 $fun $args)
                  (if (= $res $result)
                     (sk-goal-val (CPU $fun $args $result) (brand Proof cpu) () 0)
                     (empty)))))))
      ($_fact (map-semidet (sk-root-key-value $goal) (sk-root-keys $goal))))))

(: sk-result-step (-[semidet]-> (List RuntimeResult) SkeletonValue (List RuntimeResult)))
(= (sk-result-step $kept $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (cons (brand RuntimeResult (sk-full-fact $fact)) $kept))
      ((sk-goal-val $goal $_proof $_ev $_deps) (cons (brand RuntimeResult $goal) $kept))
      (sk-none $kept))))

;; Proof-indexed subsumption preserves root order (runtime_helpers.pl).
(: prune_answer_instances (-[det]-> (List RuntimeResult) (List RuntimeResult)))

;; Proven answers in root order without redundant instances; a materializing
;; query writes back the first that is not a population prior.
(: sk-root-results (-[semidet]-> Bool SkPattern (List RuntimeResult)))
(= (sk-root-results $materialize? $goal)
   (let* (($values (sk-root-values $goal))
          ($_materialized
             (if $materialize?
                (case (collapse (once (let $value (superpose $values)
                         (case $value (
                            (sk-none (empty))
                            ((sk-val ($_type $_kbctx (population-prior $_pattern) $_tv) $_ev $_deps) (empty))
                            ($found $found)))))) (
                   ((cons $first $_rest) (sk-materialize-answer! $first))
                   (() ())))
                ()))
          ($answers (fold-semidet sk-cons-step () (fold-semidet sk-result-step () $values))))
      (prune_answer_instances $answers)))

;; A root's Member producer is part of its scaffold and installed even when
;; the budget expands nothing.
(: sk-root-score-step (-[semidet]-> Atom SkPattern Atom))
(= (sk-root-score-step $_acc $goal)
   (let* (($hash (sk-node-hash $goal))
          ($_root (add-atom &sk_roots ($hash $goal)))
          ($_indexed (sk-index-node! $goal))
          ($_member
             (case (copy_term $goal) (
                ((CPU $_fun $_args $_res) ())
                (($type $kbctx $_proof $_tv) (install-member-inheritance-rules! $type $kbctx))))))
      (sk-raise-score! $goal 1.0)))

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $goals $materialize?)
   (let* (($_seen (remove-data-rows! &sk_seen (quote ($hash $node))))
          ($_fresh (remove-data-rows! &sk_fresh (quote (sk-fresh $node))))
          ($_budget (change-state! sk_budget $steps))
          ($_rows (change-state! sk_row_budget (* 10 $steps)))
          ($_evaluation (change-state! sk_eval_budget (* (sk-evaluation-per-step) $steps)))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) $steps)))
          ($_activate (sk-activate-pending!))
          ($_parked (sk-park-deliveries!))
          ($_pushes (change-state! sk_push_seq 0))
          ($_old-roots (remove-data-rows! &sk_roots (quote ($hash $root))))
          ($_scored (fold-semidet sk-root-score-step () $goals))
          ($_search (sk-search! (fold-semidet (sk-push 0) (empty_heap) $goals)))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_needed (fold-semidet sk-need-root! () $goals))
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

;; --- Prior-factored merge: sources (declared above) --------------------------

(= (sk-part-sources $_kb ()) ())
(= (sk-part-sources $kb (cons $part $rest))
   (let* (($step (sk-step-proof $part))
          ($rule (rule-evidence-head $step))
          ($witness (car-atom (cdr-atom $step)))
          ($sources
             (append-flat (map-flat index-hash (the (List Atom) (case $witness (((cons conjunction $proofs) $proofs) ($_one (cons $witness ()))))))
                (sk-part-sources $kb $rest))))
      (if (rule-evidence-registered? $kb $rule) (cons (index-hash $rule) $sources) $sources)))

(= (sk-sources-meet? $kb $parts-a $parts-b)
   (not (== (/==\ (sk-part-sources $kb $parts-a) (sk-part-sources $kb $parts-b)) ())))
