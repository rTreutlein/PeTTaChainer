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
(: sk-acc (-[det]-> (List Proof) EvidenceSet (List Number) (List SkeletonPart) SkeletonRowState))
(: sk-fail SkeletonRowState)
;; a premise had values, all overlapping the evidence the row already used:
;; the statements of the shared facts, and one more than the clashing value's
;; dependency count, the rows one conditioned branch evaluates at most
(: sk-clash (-[det]-> (List SkeletonKey) Number SkeletonRowState))
;; a rule application whose premises read a shared uncertain statement:
;; the statements, one more than the premises' dependency count, and the
;; row's state read as if they were independent, its approximate value
(: sk-entangled (-[det]-> (List SkeletonKey) Number SkeletonRowState SkeletonRowState))
;; a key a conditioned read takes as known true or false, or a complete
;; statement a closed read takes as unfounded (docs/metta/complete_predicates.md)
(: SkeletonGiven Type)
(: sk-given (-[det]-> Number SkeletonKey Bool SkeletonGiven))
(: sk-unfounded (-[det]-> Number SkeletonKey SkeletonGiven))
(: SkeletonFold Type)
;; accumulator, member proofs (newest first), evidence, dependency hashes
(: sk-fold-state (-[det]-> Atom (List Proof) (List EvidenceSet) (List Number) SkeletonFold))
(: SkeletonGroup Type)
(: sk-group-found (-[det]-> SkPattern (List SkeletonKey) SkeletonGroup))
(: sk-group-missing SkeletonGroup)
(: TokenReplacement Type)
(: token-state (-[det]-> Atom (List Proof) TokenReplacement))

(: sort-atom (-[det]-> (List $item) (List $item)))

;; The merge of two views, or, for views that share an uncertain statement
;; and neither of which contains the other's evidence, the statements to
;; condition on, the union of their dependencies, and the more confident
;; view, kept when the merge is not conditioned
;; (docs/metta/overlap_conditioning.md)
(: SkeletonPairing Type)
(: sk-paired (-[det]-> SkeletonValue SkeletonPairing))
(: sk-overlap (-[det]-> (List SkeletonKey) Number SkeletonValue SkeletonPairing))
;; a fold over a key's values: the merge so far, and the first overlap's
;; statements and dependencies
(: SkeletonMerging Type)
(: sk-merging (-[det]-> SkeletonValue (List SkeletonKey) Number SkeletonMerging))
;; What conditioning evaluates under a condition: a row (the exclusions it
;; reads under, its key's hash, its key, its hash, the row) or a key's merge
;; (its hash, the key, the reader's filter and exclusions).
(: SkeletonTarget Type)
(: sk-row-target (-[det]-> (List Number) Number SkeletonKey Number SkeletonRow SkeletonTarget))
(: sk-key-target (-[det]-> Number SkeletonKey SkeletonFilter (List Number) SkeletonTarget))

;; Signatures of the mutually recursive functions below.
(: sk-excludes? (-[det]-> (List Number) Number Bool))
(: sk-mixed (-[det]-> (List SkeletonValue) SkeletonValue SkeletonValue))
(: sk-reference-view (-[semidet]-> Number SkeletonValue SkeletonValue))
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(: sk-row-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue))
(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(: sk-member-pending? (-[det]-> SkeletonKey Bool))
(: sk-dependent-merge (-[semidet]-> Bool SkeletonValue SkeletonValue SkeletonValue))
(: sk-given-value (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(: sk-wait! (-[det]-> Number Number Number SkeletonValue SkeletonValue))
(: sk-answer-roots! (-[det]-> (List SkPattern) Bool (List (List RuntimeResult))))
(: sk-conditioned
   (-[semidet]-> (List SkeletonGiven) SkeletonTarget Number Number (List Number) (List SkeletonKey) Number
       SkeletonValue SkeletonValue SkeletonValue))

(: sk-ordinary-versions (-[det]-> Number SkeletonKey (List SkeletonVersion)))
(: sk-ordinary-view (-[det]-> Number SkeletonKey Number SkeletonValue))
(: sk-admitted-versions (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion)))
(: sk-drop-merged! (-[det]-> SkeletonKey Atom))
(: sk-condition-owner (-[det]-> Number Number))
(: sk-context-pending? (-[det]-> Bool))
(: sk-fold-exclusions (-[det]-> Number (List Number)))
(: sk-context-excludes? (-[det]-> Number Bool))
(: sk-need-roots! (-[det]-> (List SkeletonKey) Atom))
(: sk-need-keys! (-[det]-> Number (List SkeletonKey) Atom))
(: sk-need-depth (-[det]-> Number SkeletonKey Number))
(: sk-needed? (-[det]-> Number SkeletonKey Bool))
(: sk-evaluate! (-[det]-> Atom))
(: sk-evaluation-free-depth (-[det]-> Number))
(: sk-evaluation-per-step (-[det]-> Number))
(: sk-walk-per-step (-[det]-> Number))
(: sk-context-metrics! (-[det]-> Atom))

;; --- Leaves -----------------------------------------------------------------

;; A borrowed observation retains its MAIN evidence and dependency identity.
;; Assumptions themselves remain private and carry no empirical evidence.
(: sk-leaf-source (-[det]-> SkFact SkFact))
(= (sk-leaf-source ($type ($kbid $ctx $vars) $proof $tv))
   (let* (($kb (make-kb-context (brand KB $kbid) $ctx $vars))
          ($main (kbctx (brand KB $kbid)))
          ($source (if (if (== $ctx MAIN) true (assumption-proof? $proof)) $kb
                      (if (kb-fact-present? (data $type $main $proof $tv)) $main $kb))))
      (data $type $source $proof $tv)))

(: leaf-evidence-for-result (-[det]-> SkFact EvidenceSet))
(= (leaf-evidence-for-result $fact)
   (let ($type $kb $proof $_tv) (sk-leaf-source $fact)
      (if (assumption-proof? $proof) (ev-set 0)
         (evidence-set (cons (fact-evidence-entry $kb $proof $type) ())))))

(: sk-leaf-deps (-[det]-> Number SkFact Number))
(= (sk-leaf-deps $hash $fact)
   (case $fact (
      (($_type ($_kb MAIN $_vars) $_proof $_tv) (deps-key $hash))
      (($_type ($kbid $ctx $_vars) $proof $_tv)
         (let $source
            (if (assumption-proof? $proof)
               ;; A row can specialize its context variables before reading
               ;; the assumption. Retain the stored key as well as that read's
               ;; key, so necessity does not depend on those later bindings.
               (case (collapse (once (match &kb
                        ($assumed ($kbid $ctx $stored-vars) $proof $stored-tv)
                        (data $assumed (data $kbid $ctx $stored-vars) $proof $stored-tv)))) (
                  ((cons $stored $_rest) $stored)
                  (() $fact)))
               (sk-leaf-source $fact))
            (deps-union (deps-key $hash) (deps-key (index-hash (sk-fact-key (the SkFact $source))))))))))

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
             (() (sk-val $fact (leaf-evidence-for-result $fact) (sk-leaf-deps $hash $fact)))))))))

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
;; Direct facts depend on their key too: a closed re-read may reach a fact
;; whose key an outer reader excluded, even though no ordinary row can use it.
(: sk-leaf-step (-[semidet]-> Number Bool (List Number) (List SkeletonValue) SkFact (List SkeletonValue)))
(= (sk-leaf-step $hash $computed $exclude $kept $fact)
   (let* (($view (sk-leaf-view $hash $fact))
          ($deps (sk-view-deps-step 0 $view)))
      (if (== $deps (sk-leaf-deps $hash $fact))
         (if (sk-context-excludes? $deps) $kept (cons $view $kept))
         (if (if $computed (not (sk-summary-fact? $fact)) false) $kept
            (if (sk-excludes? $exclude $deps) $kept (cons $view $kept))))))

(: sk-leaf-views (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(: sk-subscribe-leaves! (-[det]-> SkeletonKey (List Number) Bool))
(= (sk-leaf-views $hash $key $filter $exclude)
   (let* (($_subscribed (sk-subscribe-leaves! $key $exclude))
          ($computed (if (== (sk-ordinary-versions $hash $key) ()) false true)))
      (fold-semidet sk-cons-step ()
         (fold-semidet (sk-leaf-step $hash $computed $exclude) () (sk-key-leaves $key $filter)))))

(: sk-keep-leaf (-[semidet]-> SkeletonKey SkeletonFilter (List SkFact) SkFact (List SkFact)))
(= (sk-keep-leaf $key $filter $kept $fact)
   (if (if (=alpha (sk-fact-key $fact) $key) (sk-fact-matches? $filter $fact) false) (cons $fact $kept) $kept))

;; The facts stored for exactly this key that match the requested pattern.
(: sk-key-leaves (-[semidet]-> SkeletonKey SkeletonFilter (List SkFact)))
(= (sk-key-leaves $key $filter)
   (case (copy_term $key) (
      ((sk-key $type $kbctx)
         (fold-semidet (sk-keep-leaf $key $filter) () (append-flat (sk-leaf-facts $type $kbctx $filter) (context-leaves $key))))
      ($_fold ()))))

;; --- Values -----------------------------------------------------------------

;; The last rule application of a proof, with its premise proofs still
;; references (runtime_helpers.pl).
(: same-proof? (-[det]-> Proof Proof Bool))

(: sk-fact-step-proof (-[det]-> SkFact Proof))
(= (sk-fact-step-proof ($_type $_kbctx $proof $_tv)) (sk-step-proof $proof))

;; --- Prior-factored merge (docs/metta/prior_factored_merge.md) ---------------

;; Updates of one prior add up on a link's scale: log-odds for observations
;; independent given the statement (Bayes' rule), log-survival for
;; independent causes (noisy-OR; docs/metta/combination_modes.md). The result
;; is view a's link plus view b's link over b's prior. Its link-scale variance
;; is a's, at least a's prior's, plus b's over b's prior: over one prior that
;; adds each view's update to the prior's variance once, and a view in the
;; base rate's place keeps its own variance, however uncertain the rate.
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

(: sk-factored-tv (-[det]-> Atom Number Number Number Number Number Number Number Number STVType))
(= (sk-factored-tv $link $spa $cpa $spb $cpb $sa $ca $sb $cb)
   (let* (($x (- (+ (sk-link $link $sa) (sk-link $link $sb)) (sk-link $link $spb)))
          ($v (+ (max (sk-link-var $link $sa $ca) (sk-link-var $link $spa $cpa))
                 (max 0.0 (- (sk-link-var $link $sb $cb) (sk-link-var $link $spb $cpb)))))
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

;; The prior an observation's value was formed under, for an inversion or a
;; completion that reads the value as a likelihood ratio over it
;; (ObservationRatioFormula): the prior a view updates. A view updating
;; nothing, a stored fact or a forward conclusion, is a value of its own, read
;; under the prior the inversion implies for it, as modus ponens reads it. An
;; unfounded value is a closed read's pin, the reading conclusion taken false
;; to cut its circular support (docs/metta/complete_predicates.md): a
;; hypothesis, not an observation, so nothing is inferred from it.
(: sk-observation-prior (-[semidet]-> Proof TV TV))
(= (sk-observation-prior $proof $tv)
   (if (== (sk-step-proof $proof) unfounded) (empty)
      (case (sk-prior-update-of $proof $tv) (
         ((sk-prior-update $_prior $_own ()) no-evidence)
         ((sk-prior-update $_prior (prior $prior-tv) $_parts) (the TV $prior-tv))))))

;; The forward conclusions a view combines: a rule application is one, a
;; combination of forward views (docs/metta/combination_modes.md) its parts.
(: sk-forward-parts (-[det]-> Proof (List Proof)))
(= (sk-forward-parts $proof)
   (let $step (sk-step-proof $proof)
      (if (rule-application-proof? $step) (cons $proof ())
         (case $step (
            ((combination $mode $_combination-prior $parts)
               (if (== $mode revision) (cons $proof ()) (proof-children $parts)))
            ((merge/revision $left $right)
               (let* (($left-parts (sk-forward-parts (brand Proof $left)))
                      ($right-parts (sk-forward-parts (brand Proof $right))))
                  (if (if (== $left-parts ()) true (== $right-parts ())) () (cons $proof ()))))
            ((specializes $_specific $_general $_raw $_prior-tv) (cons $proof ()))
            ($_other ()))))))

;; The witnesses of the updates a view merges, by hash: with `$siblings`
;; false their observations, an inversion's observation and a completion's
;; consequence, its last witness; with `$siblings` true the other witnesses of
;; a completion, the siblings whose values its likelihood of the consequence
;; reads as given. Updates through one rule are independent given their prior
;; and the rule, whether its truth is given or an estimate (see
;; sk-merge-facts). A list of proofs is walked by recursion: the determinism
;; checker rejects a fold over Proof, a newtype of Atom.
(: sk-part-witnesses (-[det]-> Bool (List Proof) (List Number)))
(= (sk-part-witnesses $_siblings ()) ())
(= (sk-part-witnesses $siblings (cons $part $rest))
   (let* (($witness (car-atom (cdr-atom (sk-step-proof $part))))
          ($last-first (reverse (case $witness (((cons conjunction $proofs) $proofs) ($_one (cons $witness ()))))))
          ($read (the (List Atom) (if $siblings (sk-siblings (cdr-atom $last-first)) (cons (car-atom $last-first) ())))))
      (append-flat (map-flat index-hash $read) (sk-part-witnesses $siblings $rest))))

;; A compound sibling read off its parts, the Or of a completion's other
;; parts, reads each part as given.
(: sk-siblings (-[det]-> (List Atom) (List Atom)))
(= (sk-siblings ()) ())
(= (sk-siblings (cons $proof $rest))
   (append-flat
      (the (List Atom) (case $proof (
         ((cons conjunction $parts) (sk-siblings (the (List Atom) $parts)))
         ($_one (cons $proof ())))))
      (sk-siblings $rest)))

(: sk-sources-meet? (-[det]-> (List Proof) (List Proof) Bool))
(= (sk-sources-meet? $parts-a $parts-b)
   (not (== (/==\ (sk-part-witnesses false $parts-a) (sk-part-witnesses false $parts-b)) ())))

;; The evidence a view holds about its statement apart from what it reads as
;; given: its evidence less the certain facts its completions read as
;; siblings, and, for a complete statement, less the certain complete facts
;; its rule application reads as premises that the other view observes.
;; Given a sibling K, a completion is the likelihood ratio of its consequence
;; alone, P(C | M, K) over P(C | not M, K); it holds no evidence of M through
;; K. So a view that reads K as an observation, an inversion of K's rule
;; P(K | M), or as a premise, a forward view P(M | K), is independent of it
;; given K, and Bayes' rule over both is exact: P(M) P(K | M) P(C | M, K). An
;; uncertain sibling's value is read as independent of M a priori, so it stays
;; evidence. A premise another view observes as M's effect is both M's cause
;; and its effect, which only a loop through M allows. In a loop of complete
;; predicates the cause read as given adds nothing the observation does not:
;; a false disjunct adds nothing to the rule's other causes, and a true one is
;; explained only through M (fuzzer seed 14000138). Elsewhere the two read K
;; twice (a symmetric relation's rule and its completion,
;; test_specializing_rule.metta), so the premise stays shared.
(: sk-update-evidence (-[det]-> SkFact EvidenceSet SkFact EvidenceSet))
(= (sk-update-evidence ($type $kbctx $proof $tv) $ev ($_otype $_okbctx $other $otv))
   (case (data (sk-prior-update-of $proof $tv) (sk-prior-update-of $other $otv)) (
      (((sk-prior-update $_prior $_own $parts) (sk-prior-update $_oprior $_oown $oparts))
         (sk-without-given $ev (sk-part-witnesses true $parts)
            (sk-application-premises $type $kbctx $proof)
            (sk-part-witnesses false $oparts))))))

;; The premises a rule application of a complete statement reads directly, by
;; hash.
(: sk-application-premises (-[det]-> Atom Atom Proof (List Number)))
(= (sk-application-premises $type $kbctx $proof)
   (if (complete-statement? $type $kbctx)
      (case (sk-step-proof $proof) (
         ((by $_rule $premise)
            (map-flat index-hash (the (List Atom) (case $premise (
               ((cons conjunction $names) $names)
               ((settled $part) (cons $part ()))
               ($_one (cons $premise ())))))))
         ($_update ())))
      ()))

;; Evidence less its certain facts that are siblings, or premises observed.
(: sk-without-given (-[det]-> EvidenceSet (List Number) (List Number) (List Number) EvidenceSet))
(= (sk-without-given $ev $siblings $premises $observed)
   (if (if (== $siblings ()) (if (== $premises ()) true (== $observed ())) false) $ev
      (evidence-subtraction $ev
         (evidence-set (fold-flat (sk-given-entry-step $siblings $premises $observed) () (evidence-entries $ev))))))

(: sk-given-entry-step (-[det]-> (List Number) (List Number) (List Number) (List Evidence) Evidence (List Evidence)))
(= (sk-given-entry-step $siblings $premises $observed $kept $entry)
   (case $entry (
      ((fact-ev $kbctx $proof $type)
         (let $hash (index-hash $proof)
            (if (if (stored-list-member? $hash $siblings) true
                   (if (stored-list-member? $hash $observed)
                      (if (stored-list-member? $hash $premises) (complete-statement? $type $kbctx) false)
                      false))
               (if (certain-fact-evidence? $entry) (cons $entry $kept) $kept)
               $kept)))
      ($_other $kept))))

;; Two views updating the same prior with different rules and observations
;; merge by Bayes' rule; over a base rate, which carries no evidence, they
;; must also be independent, sharing no uncertain statement, since an
;; observation may be read below the witnesses the sources compare. A view
;; updating the population base rate (`cpu`) merges the same way into a
;; derived, uncertain view over another prior, or updating nothing, that is
;; independent of it: that view takes the base rate's place, as the instance's
;; prior given its other evidence. A stored fact is counted in the base rate
;; itself, and a certain view stays as it is. Anything else is left to the
;; rules below, and so are two certain views that contradict each other.
(: sk-factored-merge
   (-[det]-> SkFact EvidenceSet Number SkFact EvidenceSet Number Bool SkeletonValue))
(= (sk-factored-merge ($type $kbctx $proof-a $tv-a) $ev-a $deps-a ($btype $bkbctx $proof-b $tv-b) $ev-b $deps-b $independent)
   (case (data (sk-prior-update-of $proof-a $tv-a) (sk-prior-update-of $proof-b $tv-b) $tv-a $tv-b) (
      (((sk-prior-update $base-a (prior (STV $spa $cpa)) $parts-a)
        (sk-prior-update $base-b (prior (STV $spb $cpb)) $parts-b)
        (STV $sa $ca) (STV $sb $cb))
         (let* (($population-a (== (sk-step-proof $base-a) cpu))
                ($population-b (== (sk-step-proof $base-b) cpu)))
            (if (if $population-a (if $population-b false true) false)
               (sk-factored-merge (data $btype $bkbctx $proof-b $tv-b) $ev-b $deps-b (data $type $kbctx $proof-a $tv-a) $ev-a $deps-a $independent)
               (if (if (sk-contradict? (the Number $sa) (the Number $sb)) false
                      (if (=alpha $base-a $base-b)
                         (if (== $spa $spb) (if (== $cpa $cpb) (if (== $parts-a ()) false (if (== $parts-b ()) false (if (if $population-a (if $independent false true) false) false (not (sk-sources-meet? $parts-a $parts-b))))) false) false)
                         (if $population-b
                            (if (if (is-expr $base-a) (< $ca 1.0) false) $independent false)
                            false)))
                  (sk-val ($type $kbctx (brand Proof (factored-revision $base-a (prior (STV $spa $cpa)) (append-flat $parts-a $parts-b)))
                              (sk-factored-tv odds (the Number $spa) (the Number $cpa) (the Number $spb) (the Number $cpb) (the Number $sa) (the Number $ca) (the Number $sb) (the Number $cb)))
                     (evidence-union $ev-a $ev-b) (deps-union $deps-a $deps-b))
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

(: sk-disjoint-view-step (-[semidet]-> Atom SkeletonValue Atom))
(= (sk-disjoint-view-step ($tvs $seen) (sk-val ($_type $_ctx $_proof $tv) $ev $_deps))
   (if (evidence-overlap? (the EvidenceSet $ev) (the EvidenceSet $seen)) (empty) (data (cons $tv $tvs) (evidence-union $ev $seen))))

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

(: sk-mode-step (-[semidet]-> Atom STVType STVType STVType STVType))
(= (sk-mode-step $mode (STV $sp $cp) (STV $sa $ca) (STV $sb $cb)) (sk-factored-tv $mode $sp $cp $sp $cp $sa $ca $sb $cb))

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
   (let* (($parts-a (sk-forward-parts $proof-a))
          ($parts-b (sk-forward-parts $proof-b)))
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

;; --- Overlapping views (docs/metta/overlap_conditioning.md) ------------------

;; A statement both views depend on, with the size of its dependency set,
;; negated so the largest sorts first, that set, and its spread: the largest
;; variance s (1 - s) of its facts' and views' strengths.
(: SkeletonShared Type)
(: sk-shared-key (-[det]-> Number SkeletonKey Number Number SkeletonShared))
;; A statement to condition on with its expected impact, negated so the
;; largest sorts first.
(: SkeletonRanked Type)
(: sk-ranked (-[det]-> Number SkeletonKey SkeletonRanked))

;; A statement is known when a stored fact gives it strength 0 or 1 at
;; confidence 1, or when every view its rows have does. A shared statement is
;; read off its stored facts and its rows' latest views, never by merging it:
;; its merge may read the very key being merged. A rule's truth is no
;; statement: it is a parameter of every view through the rule, and given it
;; the rule's applications are independent.
(: sk-known-view-step (-[det]-> Bool SkeletonValue Bool))
(= (sk-known-view-step $known $view)
   (if $known
      (case $view (
         ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) (certain-tvs? (cons $tv ())))
         ($_other false)))
      false))

(: sk-shared-candidate (-[semidet]-> (List SkeletonShared) SkeletonKey (List SkeletonShared)))
(= (sk-shared-candidate $found $key)
   (if (case $key (((sk-key $type $_kbctx)
            (if (head-is? $type RuleTruth) (= $type (RuleTruth $_implication)) false)) ($_other false))) $found
   (let* (($hash (index-hash $key))
          ($views (map-flat sk-version-view (sk-ordinary-versions $hash $key)))
          ($leaves (sk-key-leaves $key sk-any-filter)))
      (if (if (fold-semidet sk-known-leaf-step false $leaves) true
             (if (== $views ()) (== $leaves ()) (fold-semidet sk-known-view-step true $views)))
         $found
         (let $deps (fold-semidet sk-view-deps-step (deps-key $hash) $views)
            (cons (sk-shared-key (- 0 (deps-size $deps)) $key $deps
                     (fold-semidet sk-view-spread-step (fold-semidet sk-leaf-spread-step 0 $leaves) $views))
               $found))))))

(: sk-spread (-[det]-> Number TV Number))
(= (sk-spread $spread $tv)
   (case $tv (((STV $s $_c) (let $v (* $s (- 1 $s)) (if (> $v $spread) $v $spread))) ($_other $spread))))

(: sk-leaf-spread-step (-[det]-> Number SkFact Number))
(= (sk-leaf-spread-step $spread ($_type $_kbctx $_proof $tv)) (sk-spread $spread $tv))

(: sk-view-spread-step (-[det]-> Number SkeletonValue Number))
(= (sk-view-spread-step $spread $view)
   (case $view (((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) (sk-spread $spread $tv)) ($_other $spread))))

;; A statement's expected impact on what conditioning on it decides: its
;; spread, how far its two branches lie apart in weight, times one more than
;; its dependency count, how much of the views it reaches.
(: sk-shared-rank (-[det]-> SkeletonShared SkeletonRanked))
(= (sk-shared-rank (sk-shared-key $size $key $_deps $spread)) (sk-ranked (* $spread (- $size 1)) $key))

(: sk-ranked-key (-[det]-> SkeletonRanked SkeletonKey))
(= (sk-ranked-key (sk-ranked $_impact $key)) $key)

(: sk-shared-hash-step (-[semidet]-> (List Number) (List SkeletonShared) Number (List SkeletonShared)))
(= (sk-shared-hash-step $ignore $found $hash)
   (if (stored-list-member? $hash $ignore) $found
      (fold-semidet sk-shared-candidate $found (collapse (match &sk_keys ($hash $key) $key)))))

(: sk-below-step (-[det]-> Number Bool SkeletonShared Bool))
(= (sk-below-step $hash $found (sk-shared-key $_size $_key $deps $_spread)) (if $found true (deps-has? $deps $hash)))

(: sk-frontier-step (-[semidet]-> (List SkeletonShared) SkeletonShared (List SkeletonShared)))
(= (sk-frontier-step $kept $shared)
   (case $shared (
      ((sk-shared-key $_size $key $_deps $_spread)
         (if (fold-flat (sk-below-step (index-hash $key)) false $kept) $kept (cons $shared $kept))))))

;; The shared statements, among the keys of the hashes less the ignored ones,
;; whose value is uncertain: first the ones no other one depends on (the
;; largest dependency set decides first), then the others, each the most
;; impact first. A stored fact depends on its own key, and a fold is no
;; statement.
(: sk-shared-statements (-[semidet]-> (List Number) (List Number) (List SkeletonKey)))
(= (sk-shared-statements $ignore $hashes)
   (let* (($candidates (sort-atom (fold-semidet (sk-shared-hash-step $ignore) () $hashes)))
          ($frontier (fold-semidet sk-frontier-step () $candidates)))
      (append-flat (sk-ranked-statements $frontier) (sk-ranked-statements (fold-semidet (sk-below-frontier-step $frontier) () $candidates)))))

(: sk-below-frontier-step (-[det]-> (List SkeletonShared) (List SkeletonShared) SkeletonShared (List SkeletonShared)))
(= (sk-below-frontier-step $frontier $below $shared) (if (stored-list-member? $shared $frontier) $below (cons $shared $below)))

(: sk-ranked-statements (-[semidet]-> (List SkeletonShared) (List SkeletonKey)))
(= (sk-ranked-statements $shared) (map-flat sk-ranked-key (sort-atom (map-flat sk-shared-rank $shared))))

;; Whether a row reads a compound off its parts.
(: sk-compound-proof? (-[det]-> Atom Bool))
(= (sk-compound-proof? $proof)
   (if (is-expr $proof) (let $head (car-atom $proof) (if (is-var $head) false (== $head conjunction))) false))

;; Premises of a rule application, or of a compound read off its parts, that
;; read one uncertain statement are not independent, whatever evidence they
;; name: E <- (Or C B) with C <- B multiplies P(C) and P(B) as if they were
;; (fuzzer seed 1000004), and so does E <- (And C D) with C and D both derived
;; from B. Evidence sets name only the leaves, often certain facts that never
;; clash, so the statements are found in the premises' dependency sets: the
;; keys near the top of two premises' sets (each premise's key and the keys
;; its row read, deps-entangled), uncertain, not given and outside the row's
;; exclusions, ordered as a key's shared statements are. The row is
;; conditioned on them as on a clash; the state read as if the premises were
;; independent is its approximate value. Looking only that deep keeps the
;; test to a few masked lookups per row; a statement shared further down is
;; not found (collecting both sets and testing every shared key doubled
;; SupplyNet scale l's time for no change). Rows reading a fold read its
;; members as data, compiler-marked joins share their sources by design, and
;; projections of one source pool into it.
(: sk-entangle (-[semidet]-> (List Number) SkeletonRowState SkeletonRowState))
(= (sk-entangle $ignore $state)
   (case $state (
      ((sk-acc () $_ev $deps $parts)
         (if (sk-pooled? $parts) $state
            (case (sk-shared-statements $ignore (deps-entangled $deps)) (
               (() $state)
               ($keys (sk-entangled $keys (+ 1 (deps-size (deps-join $deps))) $state))))))
      ($_other $state))))

;; A known fact two views share is evidence twice when some rule concludes
;; its statement: it may be an observation both update on. A fact no rule
;; concludes is a premise either reads as given.
(: sk-concludable-fact? (-[det]-> Statement Atom Bool))
(= (sk-concludable-fact? $type $kbctx) (let $kbid (car-atom $kbctx) (prefilter-head-concludable? $type $kbid)))

(: sk-observation-step (-[det]-> Bool Evidence Bool))
(= (sk-observation-step $found $entry)
   (if $found true
      (if (certain-fact-evidence? $entry)
         (case $entry (
            ((fact-ev $kbctx $_proof $type) (sk-concludable-fact? (the Statement $type) $kbctx))
            ((not-fact-ev $nkbctx $_nproof $ntype) (sk-concludable-fact? (the Statement $ntype) $nkbctx))
            ($_name true)))
         false)))

;; Views merge as proofs do: an identical proof pools its evidence, a
;; projection gives way to its full proof and a settled step to its complete
;; one. Views whose evidence is disjoint, or overlaps only in rules and in
;; facts read as given premises while each holds evidence of its own, are
;; independent (given its truth, a rule's applications are): they
;; combine by the prior they update, by the mode their predicate's outcomes
;; prefer, or by revision. Of dependent views, one whose evidence strictly
;; contains the other's is kept; two that share an uncertain statement are an
;; overlap, which the key's merge conditions on the shared statements; any
;; other pair keeps the more confident view, also the overlap's fallback. A
;; view's evidence is compared without the certain facts it reads as given
;; (sk-update-evidence). A dominated view contributes neither
;; evidence nor dependencies. The ignored
;; hashes are the merged key's, those of the keys unifying with it, those the
;; reader excludes and the statements given.
(: sk-merge-facts
   (-[semidet]-> Bool (List Number) SkFact EvidenceSet Number SkFact EvidenceSet Number
       SkeletonPairing))
(= (sk-merge-facts $combine $ignore $a $ev-a $deps-a $b $ev-b $deps-b)
   (let* (($proof-a (sk-fact-step-proof $a))
          ($proof-b (sk-fact-step-proof $b))
          (($_ta $_ca $_pa $tv-a) $a)
          (($_tb $_cb $_pb $tv-b) $b))
      (if (if (== $a $b) true
             (if (== $tv-a $tv-b)
                (if (== $ev-a $ev-b) (same-proof? $proof-a $proof-b) false)
                false))
         (sk-paired (sk-val $a (evidence-union $ev-a $ev-b) (if (== $a $b) $deps-a (deps-union $deps-a $deps-b))))
         (if (proof-dominates? $proof-a $proof-b) (sk-paired (sk-val $a $ev-a $deps-a))
            (if (proof-dominates? $proof-b $proof-a) (sk-paired (sk-val $b $ev-b $deps-b))
            (if (specialization-includes? $proof-a $proof-b) (sk-paired (sk-val $a $ev-a $deps-a))
            (if (specialization-includes? $proof-b $proof-a) (sk-paired (sk-val $b $ev-b $deps-b))
            (if (if (more-specific-application? $proof-a $proof-b) (if $combine (if (sk-siblings? true (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)) false true) true) false) (sk-paired (sk-specialized $a $ev-a $deps-a $b $ev-b $deps-b))
            (if (if (more-specific-application? $proof-b $proof-a) (if $combine (if (sk-siblings? true (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)) false true) true) false) (sk-paired (sk-specialized $b $ev-b $deps-b $a $ev-a $deps-a))
               (let* (($touch (evidence-overlap? $ev-a $ev-b))
                      ($cmp-a (if $touch (sk-update-evidence $a $ev-a $b) $ev-a))
                      ($cmp-b (if $touch (sk-update-evidence $b $ev-b $a) $ev-b))
                      ($overlap (if $touch (evidence-overlap? $cmp-a $cmp-b) false))
                      ($a-in-b (if $overlap (evidence-subset? $cmp-a $cmp-b) false))
                      ($b-in-a (if $overlap (evidence-subset? $cmp-b $cmp-a) false))
                      ($apart (if $overlap (if $a-in-b false (if $b-in-a false true)) false))
                      ($shared (if $apart (sk-shared-statements $ignore (deps-shared $deps-a $deps-b)) ()))
                      ($independent
                         (if $overlap
                            (if $apart (if (== $shared ()) (if (fold-flat sk-observation-step false (evidence-shared-facts $cmp-a $cmp-b)) false true) false) false)
                            true))
                      ($twins
                         (if $independent
                            (if (sk-derivation-proof? $proof-a) (if (sk-derivation-proof? $proof-b) (sk-sample-twins? (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)) false) false)
                            false))
                      ($factored (if $twins sk-none
                                    (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b $independent)))
                      ($siblings (if (== $factored sk-none)
                                    (if $combine (if (== $shared ())
                                       (sk-siblings? true (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)) false) false)
                                    false)))
                  (if $twins (sk-paired (sk-dependent-merge false (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)))
                  (if (not (== $factored sk-none)) (sk-paired $factored)
                     (if $siblings (sk-paired (sk-sibling-merge true (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)))
                     (if $independent
                        (let* (($pooled (evidence-union $ev-a $ev-b))
                               ($deps (deps-union $deps-a $deps-b))
                               ($combined (if $combine (sk-combined-merge $a $b $pooled $deps) sk-none)))
                           (sk-paired
                              (if (not (== $combined sk-none)) $combined
                                 (if (>= (term-confidence $a) (term-confidence $b))
                                    (sk-val (RevisionMergeProof $a $b) $pooled $deps)
                                    (sk-val (RevisionMergeProof $b $a) $pooled $deps)))))
                        (if (if $a-in-b (if $b-in-a false true) false) (sk-paired (sk-val $b $ev-b $deps-b))
                           (if (if $b-in-a (if $a-in-b false true) false) (sk-paired (sk-val $a $ev-a $deps-a))
                              (sk-overlap $shared (deps-union $deps-a $deps-b)
                                 (sk-dependent-merge false (sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b)))))))))))))))))))

;; Two derivations through different refined rules whose truths were folded
;; from the same samples, observing the same outcomes, are one estimate from
;; one sample applied twice: the history never told the rules apart, so their
;; views count the same outcomes twice. So it is with two hypotheses confirmed
;; through perfectly correlated antecedents (docs/metta/hypothesis_rules.md,
;; gap 5), and with a hypothesis about one outcome and the inversion, through
;; a deterministic rule, of a hypothesis about its complement, when the
;; complement is derived from the stored outcome. Sibling views conservatively
;; pool that estimate once; ordinary proofs keep their existing representative.
;; The samples are compared by their folds' digests.
(: sk-derivation-proof? (-[det]-> Proof Bool))
(= (sk-derivation-proof? $proof)
   (let $step (sk-step-proof $proof)
      (if (rule-application-proof? $step) true
         (case $step (
            ((specializes $specific $_general $_raw $_prior)
               (sk-derivation-proof? (brand Proof $specific)))
            ((combination $_mode $_prior2 $_parts) true)
            ($_other (if (is-expr $step) (is-expr (car-atom $step)) false)))))))

(: SkeletonDigest Type)
(: sk-digest (-[det]-> Number Number SkeletonDigest))

;; Read the rule's own instance fold, excluding containing-class priors.
;; A conservative combination of twins still represents those same samples.
(: sk-rule-digests (-[semidet]-> Statement KBContext Proof (List SkeletonDigest)))
(= (sk-rule-digests $type $ctx $proof)
   (case (sk-step-proof $proof) (
      ((specializes $specific $_general $_raw $_prior)
         (sk-rule-digests $type $ctx (brand Proof $specific)))
      ((by $rule $_premise)
         (list_to_set (collapse (match rule_name_index ($rule $id)
            (match rules (runtime-rule-row $id ($type $ctx (by $rule $_body) $_tv) $_args)
               (match &sk_rule_truth ($id $truth $_statement $_truth-ctx)
                  (sk-digest $truth (fold-semidet sk-fold-digest-step 0
                     (collapse (match &sk_row ($truth $_key $_rhash (sk-row $_owner $_concl $premises $_seq)) $premises))))))))))
      ((combination revision $_prior3 $parts)
         (let $groups (map-semidet (sk-rule-digests $type $ctx) (proof-children $parts))
            (case (collapse (once (let () (superpose $groups) true))) (
               ((cons $_unknown $_rest) ())
               (() (sk-join-digest-groups $groups))))))
      ($_other ()))))

;; Keep the fold over a parameter for PeTTa's determinism specialization.
(: sk-join-digest-groups (-[det]-> (List (List SkeletonDigest)) (List SkeletonDigest)))
(= (sk-join-digest-groups $groups) (list_to_set (fold-flat append-flat () $groups)))

(: sk-same-digest-step (-[det]-> Number Bool SkeletonDigest Bool))
(= (sk-same-digest-step $digest $same (sk-digest $_truth $other))
   (if $same (== $digest $other) false))

(: sk-digests-match (-[det]-> Number Bool (List SkeletonDigest) Bool))
(= (sk-digests-match $digest $same $digests)
   (fold-flat (sk-same-digest-step $digest) $same $digests))

(: sk-value-digests (-[semidet]-> SkeletonValue (List SkeletonDigest)))
(= (sk-value-digests (sk-val ($type $ctx $proof $_tv) $_ev $deps))
   (let $own (sk-rule-digests $type $ctx $proof)
      (if (== $own ())
         (case (sk-truth-digests $deps) (
            ((cons $one ()) (cons $one ()))
            ($_many ())))
         $own)))

(: sk-same-samples? (-[semidet]-> (List SkeletonDigest) (List SkeletonDigest) Bool))
(= (sk-same-samples? $a $b)
   (case $a (
      ((cons (sk-digest $_ta $digest-a) $_rest-a)
         (case $b (
            ((cons (sk-digest $_tb $digest-b) $_rest-b)
               (if (== $digest-a 0) false
                  (if (sk-digests-match $digest-a
                         (sk-digests-match $digest-a (== $digest-a $digest-b) $a) $b)
                     (let $distinct (sk-join-digest-groups (cons $a (cons $b ())))
                        (== (list-len $distinct) (+ (list-len $a) (list-len $b))))
                     false)))
            ($_no-b false))))
      ($_no-a false))))

(: sk-sample-twins? (-[semidet]-> SkeletonValue SkeletonValue Bool))
(= (sk-sample-twins? $a $b)
   (case (collapse (once (match &sk_rule_truth ($_id $_truth $_type $_ctx) true))) (
      (() false)
      ((cons $_present $_more) (sk-same-samples? (sk-value-digests $a) (sk-value-digests $b))))))

;; The refined rule truths a view depends on, each with its instance fold's
;; digest; a truth registered for a rule and its axiom counts once.
(: sk-truth-digests (-[semidet]-> Number (List SkeletonDigest)))
(= (sk-truth-digests $deps)
   (list_to_set (collapse (match &sk_rule_truth ($_id $truth $_type $_kbctx)
      (if (deps-has? $deps $truth)
         (sk-digest $truth
            (fold-semidet sk-fold-digest-step 0
               (collapse (match &sk_row ($truth $_stored $_rhash (sk-row $_ident $_concl $premises $_seq)) $premises))))
         (empty))))))

(: sk-fold-digest-step (-[det]-> Number (List SkPattern) Number))
(= (sk-fold-digest-step $digest $premises) (fold-flat sk-premise-digest-step $digest $premises))

(: sk-premise-digest-step (-[det]-> Number SkPattern Number))
(= (sk-premise-digest-step $digest $premise)
   (case $premise (
      ((CPU FoldAllCompiled $args $_res)
         (if (sk-instance-fold? $args)
            (case (collapse (once (match &ctx_sk_instance_digest ((index-hash (sk-fold $args)) $stored) $stored))) (
               ((cons $found $_rest) $found)
               (() $digest)))
            $digest))
      ($_other $digest))))

;; A rule application reading a proper superset of the facts another rule's
;; application to the same statement reads (`more-specific-application?`) is
;; about a narrower reference class: its antecedent entails the other's, whose
;; rate is a marginal over it and over cases it is not, so the general view is
;; no further evidence of this case (ChainerGame
;; benchmarks/ona/repros/specificity.py: a hypothesis about S that wins a
;; quarter of the time, revised with one about S and L that always wins). It
;; is the prior the specific rate is read under instead: the specific
;; strength under bayes-prior-count pseudo-observations at the general one,
;; as Bayes' rule reads a likelihood (bayes-shrink), so a specific rule with
;; little evidence stays near the general rate.
(: sk-specialized (-[det]-> SkFact EvidenceSet Number SkFact EvidenceSet Number SkeletonValue))
(= (sk-specialized ($type $kbctx $proof $tv) $ev $deps ($_gtype $_gkbctx $general $gtv) $gev $gdeps)
   (case (sk-step-proof $proof) (
      ((specializes $original $previous $original-tv $previous-tv)
         (sk-specialized (assemble-runtime-fact $type $kbctx (brand Proof $original) (the TV $original-tv)) $ev $deps
            (assemble-runtime-fact $type $kbctx (brand Proof (merge/revision $previous $general)) (revision-merge-tv (the TV $previous-tv) $gtv)) $gev $gdeps))
      ($_other
         (case (data $tv $gtv) (
            (((STV $s $c) (STV $gs $_gc))
               (sk-val ($type $kbctx (brand Proof (specializes $proof $general $tv $gtv)) (STV (bayes-shrink $s $c $gs) $c))
                  ;; The general class is a parameter, not another instance
                  ;; observation. Keep its proof and refresh dependencies.
                  $ev (deps-union $deps $gdeps)))
            ($_tv-other (sk-val ($type $kbctx $proof $tv) $ev $deps))))))))

;; Reference classes are compared before any views are combined. Otherwise
;; lifting or a learned combination can hide a contained condition.
(: ReferenceClass Type)
(: no-class ReferenceClass)
(: sk-class (-[det]-> Bool (List Atom) ReferenceClass))
(: SkeletonReference Type)
(: sk-reference (-[det]-> ReferenceClass SkeletonValue SkeletonReference))
(: sk-mixture-class (-[det]-> (List Atom) ReferenceClass))
(: sk-combined-class (-[det]-> (List Atom) ReferenceClass))
(: sk-merge-step (-[semidet]-> Bool (List Number) SkeletonValue SkeletonValue SkeletonValue))
(: sk-antecedent-step (-[semidet]-> EvidenceSet ((List Atom) Number Bool) Proof ((List Atom) Number Bool)))

;; Read the antecedent's already computed value and statements. A settled
;; connective needs only its settling part to identify the active branch;
;; the refined rule's truth supplies its full condition below.
(: sk-antecedent (-[semidet]-> Proof EvidenceSet ((List Atom) Number Bool)))
(= (sk-antecedent $proof $ev)
   (case $proof (
      ((proof-ref $pid)
         (once (match &proof_fact ($pid $type (STV $s $_c)) (data (implication-side-conjuncts (brand Statement $type)) $s true))))
      ((cons conjunction $parts)
         (fold-semidet (sk-antecedent-step $ev) (data () 1.0 true) (proof-children $parts)))
      ((settled $part)
         (let ($parts $s $_complete) (sk-antecedent (brand Proof $part) $ev) (data $parts $s false)))
      ((given $truth) (data () (if (== $truth true) 1.0 0.0) false))
      ($_leaf
         (let $entries (evidence-entries $ev)
            (once (let (fact-ev $ctx $proof $type) (superpose $entries)
               (match &kb ($type $ctx $proof (STV $s $_c)) (data (implication-side-conjuncts (brand Statement $type)) $s true)))))))))

(= (sk-antecedent-step $ev ($types $s $complete) $part)
   (let ($more $strength $more-complete) (sk-antecedent $part $ev)
      (data (append-flat $types $more) (* $s $strength) (if $complete $more-complete false))))

(: sk-condition-class (-[det]-> Number (List Atom) ReferenceClass))
(= (sk-condition-class $s $parts)
   (let $condition (sort-atom $parts)
      (if (>= $s 1.0) (sk-class true $condition)
         (if (<= $s 0.0) (sk-class false $condition) (sk-mixture-class $condition)))))

(: sk-rule-reference (-[nondet]-> SkeletonValue Number SkeletonReference))
(= (sk-rule-reference (sk-val ($type $ctx $proof $tv) $ev $deps) $s)
   (let* (((by $rule $premise) (sk-step-proof $proof))
          ($antecedent
             (case (collapse (once (match rule_name_index ($rule $id)
                       (match rules (runtime-rule-row $id ($type $ctx (by $rule $premise) $_out) $_prems)
                          (match &sk_rule_truth ($id $_truth-hash $truth $_truth-ctx)
                             (let (RuleTruth (Implication $condition $type)) (copy_term $truth) $condition)))))) (
                ((cons $refined $_more) $refined)
                (() (let $ctv (sk-lift-rule-ctv (brand KB (car-atom $ctx)) $rule)
                       (once (match &kb ((Implication $declared $type) $ctx $rule $ctv) $declared))))))))
      (sk-reference (sk-condition-class $s (implication-side-conjuncts (brand Statement $antecedent)))
         (sk-val ($type $ctx $proof $tv) $ev $deps))))

(: sk-application-antecedent (-[semidet]-> Proof EvidenceSet ((List Atom) Number Bool)))
(= (sk-application-antecedent $proof $ev)
   (let* (((by $rule $premise) (sk-step-proof $proof))
          (($parts $s $complete) (sk-antecedent (brand Proof $premise) $ev))
          ($source (sk-step-proof (brand Proof $rule))))
      (if (rule-application-proof? $source)
         (let ($parents $parent-s $parent-complete) (sk-application-antecedent (brand Proof $rule) $ev)
            (data (append-flat $parents $parts) (* $parent-s $s) (if $complete $parent-complete false)))
         (data $parts $s $complete))))

(: sk-reference-for (-[semidet]-> SkeletonValue ((List Atom) Number Bool) SkeletonReference))
(= (sk-reference-for $view ($parts $s $complete))
   (if $complete (sk-reference (sk-condition-class $s $parts) $view)
      (case (collapse (once (sk-rule-reference $view $s))) (
         ((cons $found $_more)
            (let* (((sk-reference $class $_original) (the SkeletonReference $found))
                   ($class-parts (sk-class-parts $class))
                   ((sk-val $fact $_ev $_deps) $view))
               (if (== (extract-vars $class-parts) ()) (the SkeletonReference $found)
                  (case (sk-fact-step-proof $fact) (
                     ((by $_rule (settled $_part)) (the SkeletonReference $found))
                     ($_full (sk-reference (sk-condition-class $s $parts) $view)))))))
         (() (case $view (
            ((sk-val $fact $_ev $_deps)
               (case (sk-fact-step-proof $fact) (
                  ;; A settling part is not the full condition.
                  ((by $_rule (settled $_part)) (sk-reference no-class $view))
                  ($_full (sk-reference (sk-condition-class $s $parts) $view)))))
            ($_goal (sk-reference no-class $view)))))))))

(: sk-reference-of (-[semidet]-> SkeletonValue SkeletonReference))
(= (sk-reference-of $view)
   (case $view (
      ((sk-val ($_type $_ctx $proof $_tv) $ev $_deps)
         (case (sk-step-proof $proof) (
            ((by $_rule $premise)
               (case (collapse (once (sk-application-antecedent $proof $ev))) (
                  ((cons $antecedent $_rest) (sk-reference-for $view (the ((List Atom) Number Bool) $antecedent)))
                  (() (case (collapse (once (sk-rule-reference $view 0.5))) (
                     ((cons $condition $_more) (the SkeletonReference $condition))
                     (() (sk-reference no-class $view))))))))
            ((specializes $specific $_general $_raw $_prior)
               (let (sk-reference $class $_original)
                     (sk-reference-of (sk-val (assemble-runtime-fact $_type $_ctx (brand Proof $specific) $_tv) $ev $_deps))
                  (sk-reference $class $view)))
            ((merge/revision $left $right)
               (let* (((sk-reference $class-left $_left)
                          (sk-reference-of (sk-val (assemble-runtime-fact $_type $_ctx (brand Proof $left) $_tv) $ev $_deps)))
                      ((sk-reference $class-right $_right)
                          (sk-reference-of (sk-val (assemble-runtime-fact $_type $_ctx (brand Proof $right) $_tv) $ev $_deps))))
                  (sk-reference (if (=alpha $class-left $class-right) $class-left no-class) $view)))
            ((combination $_mode $_combination-prior $parts)
               (sk-reference (sk-combined-class
                  (list_to_set (fold-semidet (sk-combined-condition-step $view) () (proof-children $parts)))) $view))
            ($_other (sk-reference no-class $view)))))
      ($_goal (sk-reference no-class $view)))))

(: sk-contained? (-[det]-> SkeletonReference SkeletonReference Bool))
(= (sk-contained? $specific $general)
   (case (data $specific $general) (
      (((sk-reference (sk-class true $parts-a) $_a)
        (sk-reference (sk-class true $parts-b) $_b))
         (if (< (list-len $parts-b) (list-len $parts-a)) (all-members? $parts-a $parts-b) false))
      (((sk-reference (sk-class false $parts-a) $_a)
        (sk-reference (sk-class false $parts-b) $_b))
         (if (< (list-len $parts-a) (list-len $parts-b)) (all-members? $parts-b $parts-a) false))
      ($_other false))))

(: sk-outranked-step (-[semidet]-> SkeletonReference Bool SkeletonReference Bool))
(= (sk-outranked-step $view $found $other) (if $found true (sk-contained? $other $view)))

;; Only containing classes supply a prior; sibling rules remain separate views.
(: sk-class-prior-step (-[semidet]-> (List Number) SkeletonReference SkeletonValue SkeletonReference SkeletonValue))
(= (sk-class-prior-step $ignore $specific $prior $general)
   (case (data $specific $general) (
      (((sk-reference $_class (sk-val $fact $_ev $_deps))
        (sk-reference $_gclass (sk-val $gfact $gev $gdeps)))
         (if (sk-contained? $specific $general)
               (case $prior (
                  (sk-none (sk-val $gfact $gev $gdeps))
                  ((sk-val $previous $pev $pdeps)
                     ;; General class averages revise into the prior; they
                     ;; are not independent signs to combine by odds.
                     (case (sk-merge-facts false $ignore $previous $pev $pdeps $gfact $gev $gdeps) (
                        ((sk-paired $merged) $merged)
                        ((sk-overlap $_keys $_shared $fallback) $fallback))))))
            $prior))
      ($_other $prior))))

(: sk-reference-step (-[semidet]-> Bool (List Number) (List SkeletonReference) (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-reference-step $prior? $ignore $references $kept $reference)
   (let (sk-reference $class $view) $reference
      (if (== $class no-class) (cons $view $kept)
         (if (fold-semidet (sk-outranked-step $reference) false $references) $kept
            (let $prior (if $prior? (fold-semidet (sk-class-prior-step $ignore $reference) sk-none $references) sk-none)
               (cons (case (data $view $prior) (
                  (((sk-val $fact $ev $deps) (sk-val $general $gev $gdeps))
                     (sk-specialized $fact $ev $deps $general $gev $gdeps))
                  ($_none $view))) $kept))))))

(: SkeletonClassGroup Type)
(: sk-class-group (-[det]-> ReferenceClass (List SkeletonValue) SkeletonClassGroup))
(: sk-same-class-step (-[det]-> (List SkeletonClassGroup) SkeletonReference (List SkeletonClassGroup)))
(= (sk-same-class-step $groups (sk-reference $class $view))
   (case $groups (
      ((cons (sk-class-group $previous $views) $rest)
         (if (if (== $class no-class) false (=alpha $class $previous))
            (cons (sk-class-group $class (cons $view $views)) $rest)
            (cons (sk-class-group $class (cons $view ())) $groups)))
      (() (cons (sk-class-group $class (cons $view ())) ())))))

(: sk-class-group-value (-[semidet]-> (List Number) SkeletonClassGroup SkeletonReference))
(= (sk-class-group-value $ignore (sk-class-group $class $views))
   (case $views (
      ((cons $view ()) (sk-reference $class $view))
      ($_many
         (let $values (fold-semidet sk-cons-step () $views)
            (sk-reference $class
               (case (sk-lift false $values) (
                  ((cons $lifted $_more) $lifted)
                  (() (fold-semidet (sk-merge-step false $ignore) sk-none $values))))))))))

(: SkeletonSampleView Type)
(: sk-sample-view (-[det]-> (List SkeletonDigest) SkeletonValue SkeletonSampleView))
(: SkeletonSampleGrouping Type)
(: sk-sample-grouping (-[det]-> (List SkeletonDigest) SkeletonValue (List SkeletonSampleView) SkeletonSampleGrouping))
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

(: sk-reference-values (-[semidet]-> (List Number) (List SkeletonValue) ((List SkeletonValue) Bool)))
(= (sk-reference-values $ignore $values)
   (case $values (
      ((cons $_first (cons $_second $_rest))
         (let* (($original (map-semidet sk-reference-of $values))
                ($known (collapse (let (sk-reference $class $_view) (superpose $original)
                           (if (== $class no-class) (empty) true)))))
            (case $known (
               ((cons $_one (cons $_two $_others))
                  (let* (($references (map-semidet (sk-class-group-value $ignore)
                              (fold-flat sk-same-class-step () (sort-atom $original))))
                         ($selected (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-reference-step true $ignore $references) () $references))))
                     (data (sk-sample-groups $selected)
                        (if (< (list-len $selected) 2) false
                           (fold-semidet (sk-sibling-values-step $references) false $references)))))
               ($_few (data $values false))))))
      ($_single (data $values false)))))

;; Different applicable rule conditions combine; confidence ranks only views
;; of one condition or ordinary proofs that carry no rule condition.
(: sk-class-parts (-[det]-> ReferenceClass (List Atom)))
(= (sk-class-parts $class)
   (case $class (
      ((sk-class $_positive $parts) $parts)
      ((sk-mixture-class $mixture) $mixture)
      ((sk-combined-class $combined) $combined)
      ($_other ()))))

(: sk-reference-siblings? (-[semidet]-> Bool SkeletonReference SkeletonReference Bool))
(= (sk-reference-siblings? $overlap-only $a $b)
   (let* (((sk-reference $class-a $_a) $a)
          ((sk-reference $class-b $_b) $b))
      (if (== $class-a no-class) false
         (if (if (== $class-b no-class) true (=alpha $class-a $class-b)) false
            (if (sk-contained? $a $b) false
               (if (sk-contained? $b $a) false
                  (if $overlap-only
                     (let* (($parts-a (sk-class-parts $class-a))
                            ($parts-b (sk-class-parts $class-b)))
                        (not (== () (collapse (once (let $part (superpose $parts-a)
                           (if (stored-list-member? $part $parts-b) true (empty))))))))
                     true)))))))

(: sk-siblings? (-[semidet]-> Bool SkeletonValue SkeletonValue Bool))
(= (sk-siblings? $overlap-only $a $b)
   (sk-reference-siblings? $overlap-only (sk-reference-of $a) (sk-reference-of $b)))

(: sk-combined-condition-step (-[semidet]-> SkeletonValue (List Atom) Proof (List Atom)))
(= (sk-combined-condition-step (sk-val ($type $ctx $_proof $tv) $ev $deps) $parts $proof)
   (let (sk-reference $class $_view)
         (sk-reference-of (sk-val ($type $ctx $proof $tv) $ev $deps))
      (append-flat $parts (sk-class-parts $class))))

(: sk-sibling-merge (-[semidet]-> Bool SkeletonValue SkeletonValue SkeletonValue))
(= (sk-sibling-merge $product (sk-val ($type $ctx $proof-a (STV $sa $ca)) $ev-a $deps-a)
                     (sk-val ($_type $_ctx $proof-b (STV $sb $cb)) $ev-b $deps-b))
   (let* (($odds? (if $product (if (sk-contradict? $sa $sb) false true) false))
          ($population (if $odds?
                     (let ($_mode $population) (sk-combination-mode (brand KB (car-atom $ctx)) $type) (the STVType $population))
                     (STV 0.5 0.0)))
          ($mode (if $odds? odds revision))
          ((STV $s $c) (if $odds? (sk-mode-step odds $population (STV $sa $ca) (STV $sb $cb))
                            (mergetvs (STV $sa $ca) (STV $sb $cb)))))
      (sk-val ($type $ctx (brand Proof (combination $mode (prior (if $odds? $population no-evidence))
                  (sort-atom (append-flat (sk-forward-parts $proof-a) (sk-forward-parts $proof-b)))))
                  (STV (if $odds?
                          (if (>= $sa 1.0) 1.0 (if (>= $sb 1.0) 1.0
                             (if (<= $sa 0.0) 0.0 (if (<= $sb 0.0) 0.0 $s)))) $s)
                       (min $c (min $ca $cb))))
         (evidence-union $ev-a $ev-b) (deps-union $deps-a $deps-b))))

(= (sk-dependent-merge $product $a $b)
   (if (sk-siblings? false $a $b) (sk-sibling-merge $product $a $b)
      (case (data $a $b) (
         (((sk-val $fact-a $_ea $_da) (sk-val $fact-b $_eb $_db))
            (if (>= (term-confidence $fact-a) (term-confidence $fact-b)) $a $b))
         ($_other $a)))))

;; Pairwise merging also records the first conditioning cut and its cost.
;; Its accumulated value is provisional: on overlap the key builds its
;; fallback from connected components of the original views below.
(: sk-pair-merge-step (-[semidet]-> Bool (List Number) SkeletonMerging SkeletonValue SkeletonMerging))
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

;; A merge outside a key's merge takes an overlap's fallback.
(= (sk-merge-step $combine $ignore $acc $view)
   (case (sk-pair-merge-step $combine $ignore (sk-merging $acc () 0) $view) (((sk-merging $merged $_keys $_deps) $merged))))

;; An unpaid overlap must not discard evidence independent of it. Keep the
;; full dependencies and evidence of each connected component, including its
;; discarded views, and choose one most confident representative inside it.
;; Shared rule truths, population priors and given premises do not connect
;; components, just as they do not make the pairwise merge dependent.
(: SkeletonComponent Type)
(: sk-component (-[det]-> SkeletonValue Number EvidenceSet SkeletonComponent))
(: SkeletonConnecting Type)
(: sk-connecting (-[det]-> SkeletonComponent (List SkeletonComponent) SkeletonConnecting))


;; Connectivity needs existence, not a ranked conditioning cut. Stop at the
;; first uncertain shared statement instead of ranking every shared key.
(: sk-shared-statement-step (-[semidet]-> (List Number) Bool Number Bool))
(= (sk-shared-statement-step $ignore $found $hash)
   (if $found true (not (== (sk-shared-hash-step $ignore () $hash) ()))))

(: sk-component-step (-[semidet]-> (List Number) Number EvidenceSet SkeletonConnecting SkeletonComponent SkeletonConnecting))
(= (sk-component-step $ignore $view-deps $view-ev (sk-connecting (sk-component $best $deps $ev) $apart) (sk-component $other $other-deps $other-ev))
   (let* (($uncertain (fold-semidet (sk-shared-statement-step $ignore) false (deps-shared $view-deps $other-deps)))
          ($shared (if $uncertain true (fold-flat sk-observation-step false (evidence-shared-facts $view-ev $other-ev))))
          ($siblings (sk-siblings? true $best $other)))
      (if (if $shared true $siblings)
         (sk-connecting
            (sk-component (sk-dependent-merge (if $uncertain false
                  (if $siblings (if (sk-sample-twins? $best $other) false true) false)) $best $other)
               (deps-union $deps $other-deps) (evidence-union $ev $other-ev))
            $apart)
         (sk-connecting (sk-component $best $deps $ev) (cons (sk-component $other $other-deps $other-ev) $apart)))))

(: sk-key-merge-step (-[semidet]-> (List Number) (List SkeletonComponent) SkeletonReference (List SkeletonComponent)))
(= (sk-key-merge-step $ignore $components (sk-reference $_class $view))
   (case $view (
      ((sk-val $_fact $ev $deps)
         (let (sk-connecting $connected $apart)
               (fold-semidet (sk-component-step $ignore $deps $ev)
                  (sk-connecting (sk-component $view $deps $ev) ()) $components)
            (cons $connected $apart)))
      ($_goal $components))))

(: SkeletonComponentOrder Type)
(: sk-component-order (-[det]-> Number SkeletonValue SkeletonComponentOrder))
(: sk-component-order-of (-[semidet]-> SkeletonComponent SkeletonComponentOrder))
(= (sk-component-order-of (sk-component $view $_deps $_ev))
   (case $view (
      ((sk-val ($_type $_ctx $proof $tv) $_ev2 $_deps2)
         (case (sk-prior-update-of $proof $tv) (
            ((sk-prior-update $_prior $_own ()) (sk-component-order 0 $view))
            ($_update (sk-component-order 1 $view)))))
      ($_goal (empty)))))

(: sk-component-merge-step (-[semidet]-> (List Number) SkeletonValue SkeletonComponentOrder SkeletonValue))
(= (sk-component-merge-step $ignore $acc (sk-component-order $_order $view)) (sk-merge-step true $ignore $acc $view))

(: sk-key-fallback (-[semidet]-> (List Number) (List SkeletonValue) SkeletonValue))
(= (sk-key-fallback $ignore $views)
   ;; Combine independent values before applying the updates they are priors
   ;; for. Canonical ordering also fixes confidence ties and floating-point
   ;; fold order, regardless of the order the original views were visited.
   (fold-semidet (sk-component-merge-step $ignore) sk-none
      (sort-atom (map-semidet sk-component-order-of
         (fold-semidet (sk-key-merge-step $ignore) () (sort-atom (map-semidet sk-reference-of $views)))))))

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

;; The rule's CTV, when its conclusion is modus ponens over a conjunction (of
;; a statement, or of an implication, docs/metta/derived_implications.md).
(: sk-lift-formula-step (-[semidet]-> (List CTVType) Atom (List CTVType)))
(= (sk-lift-formula-step $found $premise)
   (case $premise (
      ((CPU AndFormula $_and-args $_and-out) $found)
      ((CPU $mp ($_premise-tv $ctv) $_mp-out)
         (if (if (if (== $mp CTVModusPonensFormula) true (== $mp ImplicationModusPonensFormula)) (is-var $ctv) true) (empty)
            (case $ctv (((CTV $pos $neg) (cons (CTV $pos $neg) $found))))))
      ((CPU $_formula $_formula-args $_formula-out) (empty))
      ($_goal $found))))

(: sk-lift-rule-ctv (-[semidet]-> KB Atom CTVType))
(= (sk-lift-rule-ctv $kb $rule)
   (case (collapse (once (match rule_name_index ($rule $id)
            (match rules (runtime-rule-row $id ($_type ($kb $_ctx $_vars) (by $rule $_premise) $_tv) $premises)
               (fold-semidet sk-lift-formula-step () $premises))))) (
      ((cons (cons $ctv ()) $_rest) $ctv))))

;; The CTV a proof applies: a rule's, or a derived implication's, its proof
;; evaluated with the shared facts replaced by the probe.
(: sk-lift-ctv (-[semidet]-> KB (List Evidence) (List Evidence) STVType Atom CTVType))
(= (sk-lift-ctv $kb $ev $shared $probe $rule)
   (if (is-expr $rule)
      (case (sk-step-proof (brand Proof $rule)) (
         ((by $inner $premise)
            (ImplicationModusPonensFormula (sk-lift-eval $kb $ev $shared $probe $premise)
               (sk-lift-ctv $kb $ev $shared $probe $inner)))))
      (sk-lift-rule-ctv $kb $rule)))

;; A proof's strength with the shared facts replaced by the probe.
(: sk-lift-eval (-[semidet]-> KB (List Evidence) (List Evidence) STVType Atom STVType))
(= (sk-lift-eval $kb $ev $shared $probe $proof)
   (let* (($step (sk-step-proof (brand Proof $proof)))
          ($facts (sk-lift-facts $step $ev)))
      (case $facts (
         ((cons $fact $_rest)
            (if (stored-list-member? $fact $shared) $probe (sk-lift-fact-tv $fact)))
         (()
            (case $step (
               ((by $rule $premise)
                  (CTVModusPonensFormula (sk-lift-eval $kb $ev $shared $probe $premise)
                     (sk-lift-ctv $kb $ev $shared $probe $rule)))
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
         (let* (($entries (evidence-entries $ev))
                ($residual
                   (CTV (sk-lift-eval $kb $entries $shared (STV 1.0 1.0) $proof)
                        (sk-lift-eval $kb $entries $shared (STV 0.0 1.0) $proof)))
                ((STV $strength $_strength-confidence) (CTVModusPonensFormula $conj $residual)))
            (if (< (abs-math (- $strength $stored)) 0.000001) $residual (empty)))))))

(: sk-lift-revise-step (-[semidet]-> CTVType CTVType CTVType))
(= (sk-lift-revise-step (CTV $pos1 $neg1) (CTV $pos2 $neg2))
   (CTV (mergetvs $pos1 $pos2) (mergetvs $neg1 $neg2)))

(: sk-value-evidence (-[det]-> SkeletonValue EvidenceSet))
(= (sk-value-evidence $value)
   (case $value (
      ((sk-val $_fact $ev $_deps) $ev)
      ($_other (ev-set 0)))))

(: sk-lift-residual-ev-step (-[semidet]-> EvidenceSet EvidenceSet SkeletonValue EvidenceSet))
(= (sk-lift-residual-ev-step $shared $seen $value)
   (case $value (
      ((sk-val $_fact $ev $_deps)
         (let $residual (evidence-subtraction $ev $shared)
            (if (== $residual (ev-set 0)) (empty)
               (if (evidence-overlap? $residual $seen) (empty) (evidence-union $residual $seen))))))))

(: sk-lift-merge-step (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-lift-merge-step (sk-val ($type $kbctx $proof $tv) $ev $deps)
      (sk-val ($_other-type $_other-kbctx $other $_other-tv) $other-ev $other-deps))
   (sk-val ($type $kbctx (brand Proof (merge/revision $proof $other)) $tv)
      (evidence-union $ev $other-ev) (deps-union $deps $other-deps)))

(: sk-lift-with-tv (-[semidet]-> SkeletonValue TV SkeletonValue))
(= (sk-lift-with-tv (sk-val ($type $kbctx $proof $_old) $ev $deps) $tv)
   (sk-val ($type $kbctx $proof $tv) $ev $deps))

(: sk-lift-group (-[semidet]-> (List Evidence) (List SkeletonValue) SkeletonValue))
(= (sk-lift-group $shared (cons $first $rest))
   (let* (($_disjoint (fold-semidet (sk-lift-residual-ev-step (evidence-set $shared)) (ev-set 0) (cons $first $rest)))
          ((cons $leaf $leaves) (map-semidet sk-lift-fact-tv $shared))
          ($conj (fold-semidet sk-lift-and-step $leaf $leaves))
          ((cons $residual $residuals) (map-semidet (sk-lift-residual $shared $conj) (cons $first $rest)))
          ($tv (CTVModusPonensFormula $conj (fold-semidet sk-lift-revise-step $residual $residuals))))
      (fold-semidet sk-lift-merge-step (sk-lift-with-tv $first $tv) $rest)))

(: sk-sibling-pair-step (-[semidet]-> SkeletonReference Bool SkeletonReference Bool))
(= (sk-sibling-pair-step $first $found $other)
   (if $found true (sk-reference-siblings? true $first $other)))

(: sk-sibling-values-step (-[semidet]-> (List SkeletonReference) Bool SkeletonReference Bool))
(= (sk-sibling-values-step $values $found $reference)
   (if $found true
      (let (sk-reference $class $_original) $reference
         (if (== $class no-class) false (fold-semidet (sk-sibling-pair-step $reference) false $values)))))

;; The lifted value of a key's leaves and views, or nothing.
(: sk-lift (-[semidet]-> Bool (List SkeletonValue) (List SkeletonValue)))
(= (sk-lift $siblings $values)
   (case $values (
      ((cons (sk-val $_fact $_ev $_deps) (cons $_second $_more))
         (if $siblings ()
            (let $shared (evidence-common-facts (map-flat sk-value-evidence $values))
               (if (== $shared ()) () (collapse (once (sk-lift-group $shared $values)))))))
      ($_other ()))))

;; A context node holds one published value. Reuse checks its recorded cuts
;; and dependencies; proof liveness is independent of that compatibility.
(: sk-live-view? (-[det]-> SkeletonValue Bool))
(= (sk-live-view? $view)
   (case $view (
      ((sk-val ($_type $_kbctx $proof $_tv) $_ev $_deps) (proof-live? $proof))
      ((sk-goal-val $_goal $proof $_ev $_deps) (proof-live? $proof))
      (sk-none true))))

(: sk-admits? (-[det]-> SkeletonFilter (List Number) SkeletonValue Bool))
(= (sk-admits? $filter $exclude $view)
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (sk-excludes? $exclude $deps) false (sk-fact-matches? $filter $fact)))
      ((sk-goal-val $_goal $_proof $_ev $deps)
         (if (sk-excludes? $exclude $deps) false true))
      (sk-none false))))

;; An estimate from a rule's instances is read by a consumer without the
;; samples that read what the consumer excludes, its own key above all: the
;; instance a refined rule is applied to is no evidence of the rule there
;; (leave one out). An implication instance fold read so is its tally less
;; those samples' contributions, found by the keys they read, and a refined
;; rule's truth is evaluated in the same exclusion class as its consumer.
(= (sk-reference-view $rule $computed)
   (case $computed (
      ((sk-val ($type $kbctx $proof $tv) $ev $vdeps)
         (let* (($ref (sk-store-proof! $rule $proof))
                ($_fact (case $ref (((proof-ref $pid) (add-atom &proof_fact ($pid $type $tv)))))))
            (sk-val (data $type $kbctx $ref $tv) $ev $vdeps)))
      ((sk-goal-val $goal $goal-proof $gev $gdeps)
         (sk-goal-val $goal (sk-store-proof! $rule $goal-proof) $gev $gdeps))
      (sk-none sk-none))))


;; The members of an implication instance fold that read one of the excluded
;; keys directly, each once.
(: sk-read-members-step (-[det]-> Number (List Number) Number (List Number)))
(= (sk-read-members-step $hash $found $read)
   (append-flat (collapse (match &ctx_sk_instance_read ($read $hash $mhash $_member) $mhash)) $found))

;; A member's sample: its segment in each branch and its contribution.
(: InstanceSample Type)
(: instance-sample (-[det]-> Number Number InstanceEvidenceState InstanceSample))

(: sk-member-sample-step (-[det]-> Number (List InstanceSample) Number (List InstanceSample)))
(= (sk-member-sample-step $hash $found $mhash)
   (append-flat
      (collapse (match &ctx_sk_instance_member ($mhash $hash $_member $pos-seg $neg-seg $contribution)
         (case $contribution (
            ((InstanceEvidence (BaseRateEvidence $_pw 0.0) (BaseRateEvidence $_nw 0.0)) (empty))
            ($sample (instance-sample $pos-seg $neg-seg $sample))))))
      $found))

;; The samples an instance fold read without the excluded keys leaves out; a
;; member that is no sample leaves nothing out.
(: sk-left-out (-[det]-> Number (List Number) (List InstanceSample)))
(= (sk-left-out $hash $exclude)
   (if (== $exclude ()) ()
      (fold-flat (sk-member-sample-step $hash) ()
         (list_to_set (fold-flat (sk-read-members-step $hash) () $exclude)))))

(: sk-rule-truth-key? (-[det]-> SkeletonKey Bool))
(= (sk-rule-truth-key? $key)
   (case $key (
      ((sk-key $type $_kbctx) (if (is-expr $type) (== (car-atom $type) RuleTruth) false))
      ($_fold false))))

;; A tally less a sample, as if it had no value.
(: sk-leave-out-step (-[det]-> Number InstanceRegimeState InstanceSample InstanceRegimeState))
(= (sk-leave-out-step $hash (instance-regimes $hazard $next $pos $neg) (instance-sample $pos-seg $neg-seg (InstanceEvidence $old-pos $old-neg)))
   (let* ((($pos-segs $_pos-at) (regime-take! $hash $hazard 0 $pos $pos-seg $old-pos (BaseRateEvidence 0.0 0.0)))
          (($neg-segs $_neg-at) (regime-take! $hash $hazard 0 $neg $neg-seg $old-neg (BaseRateEvidence 0.0 0.0))))
      (instance-regimes $hazard $next (the (List RegimeSegment) $pos-segs) (the (List RegimeSegment) $neg-segs))))

;; The determinism checker proves a fold over a parameter list.
(: sk-tally-without (-[det]-> Number InstanceRegimeState (List InstanceSample) InstanceRegimeState))
(= (sk-tally-without $hash $tally $left) (fold-flat (sk-leave-out-step $hash) $tally $left))

(: sk-instance-without-view (-[semidet]-> Number ScalarFoldSpec (List Number) SkeletonValue))
(= (sk-instance-without-view $hash $args $exclude)
   (case (sk-left-out $hash $exclude) (
      (() sk-none)
      ($left
         (let ($kb $_pattern $_extractor $_init $_function $_finish $_mode) $args
            (sk-instance-view $hash $args
               (sk-tally-without $hash (sk-instance-tally $hash (sk-fold $args) $kb) $left)))))))

;; A stored view's proof moves to &proof under a fresh id and the view keeps a
;; reference to it, so a view stays the size of one rule application however
;; deep its derivation is. What the evidence of a proof needs from its whole
;; tree, its leaves and whether it negates anything, is summarized with it.
(: sk-store-proof! (-[semidet]-> Number Proof Proof))
(= (sk-store-proof! $rule $proof)
   (let* (($pid (next-search-id proof_id))
          ($owner (record-view-rule! $pid $rule $proof))
          ($leaves (once (proof-term-evidence proof-walk-in-kb $proof)))
          ($flags (+ (* 2 $owner) (if (proof-term-contains-negated? $proof) 1 0)))
          ($_row (add-atom &proof ($pid $proof $leaves $flags))))
      (proof-ref $pid)))

;; A population prior (sk-start-prior!) is the population's value, not the
;; statement's: a key reads it only while nothing else gives it a value.
(: sk-population-prior? (-[det]-> SkeletonValue Bool))
(= (sk-population-prior? $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (let $step (sk-fact-step-proof $fact) (population-prior-proof? $step)))
      ($_other false))))

(: sk-own-value-step (-[det]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-own-value-step $kept $value) (if (sk-population-prior? $value) $kept (cons $value $kept)))

(: sk-own-values (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-own-values $values)
   (case (fold-semidet sk-own-value-step () $values) (
      (() $values)
      ($own (fold-semidet sk-cons-step () $own)))))

(: sk-premise-value (-[semidet]-> Bool SkeletonValue SkeletonValue))
(= (sk-premise-value $priors $value) (if $priors $value (if (sk-population-prior? $value) sk-none $value)))

;; A row is determined when its rule is deterministic (stated with strength 0
;; or 1 and confidence 1 in every branch: register-rule-evidence!) and its
;; premises are all certain statements, reading no fold or group: its
;; conclusion is certain, as a stored fact is. So it is computed when it is
;; built or its premises change, whoever needs it, at the cost of reading a
;; fact: its key then changes as a stored fact's would, and the tallies and
;; base rates over the key take it (docs/metta/runtime_design_assumptions.md,
;; "Determined rows").
(: sk-determined-row? (-[det]-> SkeletonItem Bool))
(= (sk-determined-row? (sk-row-item $_seq $_khash $_key $_rhash (sk-row $_ident ($_type ($kbid $_ctx $_vars) $proof $_tv) $premises $_s)))
   (if (deterministic-rule? (brand KB $kbid) (rule-evidence-head $proof))
      (fold-flat sk-certain-premise-step true (the (List SkPattern) $premises))
      false))
(= (sk-determined-row? (sk-fold-check $_hash $_fold)) false)

(: sk-certain-premise-step (-[det]-> Bool SkPattern Bool))
(= (sk-certain-premise-step $certain $premise)
   (if $certain
      (case $premise (
         ((CPU $fun $_args $_res) (not (if (== $fun FoldAllCompiled) true (== $fun GroupedFoldAllCompiled))))
         (($type $kbctx $_proof $_tv) (sk-certain? $type (sk-leaf-facts $type $kbctx sk-any-filter)))
         ($_other false)))
      false))

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
   (case (sk-premise-value false (sk-value $key $filter $exclude)) (
      ((sk-val $fact $member-ev $member-deps)
         (let* ((($_type $_kbctx $proof $_tv) $fact))
            (sk-fold-state ($step $acc $fact) (cons $proof $proofs)
               (cons $member-ev $ev) (cons $member-deps $deps))))
      ($_none (sk-fold-state $acc $proofs $ev $deps)))))

(: SkeletonExistentialFold Type)
(: sk-exists-state
   (-[det]-> STVType SkeletonValue Bool (List Proof) EvidenceSet (List Number) SkeletonExistentialFold))

;; Compare strength first, evidence confidence only on an exact strength tie.
;; Equal TVs use the canonical statement key, never discovery order or proof id.
(: sk-existential-preferred? (-[det]-> SkFact SkFact Bool))
(= (sk-existential-preferred? ($type $ctx $_proof (STV $s $c))
      ($old-type $old-ctx $_old-proof (STV $old-s $old-c)))
   (if (> $s $old-s) true
      (if (< $s $old-s) false
         (if (> $c $old-c) true
            (if (< $c $old-c) false
               (existential-key-before? (sk-key $type $ctx) (sk-key $old-type $old-ctx)))))))

;; All member evidence detects overlap; only the selected member supports a
;; correlated lower bound. Dependencies still retain every member so a later
;; overlap bridge or stronger witness recomputes the judgment.
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
                     (if $floor $tv
                        (if (== $proofs ()) (STV $s $c) (OrFormula $tv (STV $s $c))))
                     (if $take (sk-val $fact $member-ev $member-deps) $best)
                     (if $floor false
                        (if $overlap true (premise-evidence-overlap? $ev $member-ev)))
                     (cons $proof $proofs)
                     (evidence-union $ev $member-ev)
                     (cons $member-deps $deps)))
               (sk-exists-state $tv $best $overlap $proofs $ev $deps))))
      ($_none (sk-exists-state $tv $best $overlap $proofs $ev $deps)))))

;; A fold with members proves by its members, in the order they were found.
(: sk-fold-proof (-[semidet]-> Atom (List Proof) Proof))
(= (sk-fold-proof $function $proofs)
   (if (== $proofs ()) (brand Proof cpu)
      (brand Proof
         (cons (if (== $function OrFormula) disjunction foldall-proof)
            (fold-semidet sk-cons-step () $proofs)))))

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
                (fold-semidet (sk-existential-step $floor $filter (sk-fold-exclusions $hash))
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
             (fold-semidet (sk-fold-step $step $filter (sk-fold-exclusions $hash))
                (sk-fold-state $init () () ()) $members))
          ($base-rate (base-rate-finish? $finish)))
      ;; An average has no empty result. Identity folds do: keep that result
      ;; and let sk-cover-fold! mark its still-pending members as incomplete.
      (if (if (== $finish dist-average) (if (== $proofs ()) (sk-context-pending?) false) false) sk-none
      (sk-goal-val (CPU $kind $args (finish-aggregate (brand KB (car-atom $args)) $finish $acc))
         (sk-fold-proof $function $proofs)
         ;; Priors and folds that read their members' truth values as data,
         ;; like base rates, are not revised against their members' evidence;
         ;; their dependencies still reach their readers.
         (if $base-rate (ev-set 0)
            (if (stored-list-member? $finish (uniform-prior uniform-prior-known)) (ev-set 0)
               (case $args (
                  (($_kb $_pattern (extract-with-truth $_p $_t $_v) $_init $_fn $_fin $_mode) (ev-set 0))
                  ($_other (evidence-join $ev))))))
         (if $base-rate (deps-key $hash) (deps-join (cons (deps-key $hash) $deps))))))))

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
;; rule, and its readers leave their own samples out (sk-instance-without-view). Any
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
                ($cache-hash (base-rate-cache-hash $kbid $pattern))
                ($_watched
                   (if (== (collapse (once (match &ctx_sk_rate_folds ($cache-hash $stored)
                              (if (=alpha $stored $key) true (empty))))) ())
                      (context-add! &sk_rate_folds ($cache-hash $key))
                      true))
                ($entries (sk-rate-entries $args))
                ($_taken (sk-rate-take! $hash $args)))
            (case (base-rate-cache-entries-for-mode $kbid $pattern $mode) (
               ((cons $entry $_rest) (sk-cached-fold-view $hash $args $entry))
               (()
                  (let* ((($_kb $_pattern $_extractor $init $_function $finish $_mode) $args))
                     (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate (brand KB $kbid) $finish $init))
                        (brand Proof cpu) (ev-set 0) (deps-key $hash))))))))
      (no-base-rate-aggregate-key (sk-computed-fold-view $hash $args))))))

(: sk-instance-tally (-[det]-> Number SkeletonKey Atom InstanceRegimeState))
(= (sk-instance-tally $hash $fold $kb)
   (case (collapse (once (match &ctx_sk_instance_tally ($hash $stored $acc) (if (=alpha $stored $fold) $acc (empty))))) (
      ((cons $found $_rest) $found)
      (() (instance-regimes (rule-change-hazard (brand KB $kb)) 1 () ())))))

(: sk-instance-view (-[semidet]-> Number ScalarFoldSpec InstanceRegimeState SkeletonValue))
(= (sk-instance-view $hash $args (instance-regimes $hazard $_next $pos $neg))
   (let* ((($kb $_pattern $_extractor $_init $_function $finish $_mode) $args)
          ($pos-evidence (regime-evidence $hazard $pos))
          ($neg-evidence (regime-evidence $hazard $neg)))
      (sk-goal-val (CPU FoldAllCompiled $args (finish-aggregate (brand KB $kb) $finish (InstanceEvidence $pos-evidence $neg-evidence)))
         (brand Proof cpu) (ev-set 0) (deps-key $hash))))

;; A member's contribution is its sample alone, read without the fold; the
;; first take of a member records the statements its sample reads.
(: sk-instance-read! (-[det]-> Number Number SkeletonKey KBContext Atom Atom Atom))
(= (sk-instance-read! $hash $mhash $member $kbctx $_acc $statement)
   (let* (($read (index-hash (sk-key $statement $kbctx)))
          ($_row (context-add! &sk_instance_read ($read $hash $mhash $member))))
      ()))

(: sk-instance-reads! (-[det]-> Number Number SkeletonKey Atom))
(= (sk-instance-reads! $hash $mhash $member)
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $b $_atv $_btv) $kbctx)
         (fold-flat (sk-instance-read! $hash $mhash $member $kbctx) ()
            (cons $b (implication-side-conjuncts (the Statement $a)))))
      ($_other ()))))

;; A member with no value whose rows are still to be computed is left to take:
;; the evaluation needs it and checks the fold again (sk-instance-checks!).
(: sk-instance-take-step (-[semidet]-> Number SkeletonKey ScalarFoldSpec SkeletonFilter Atom SkeletonKey Atom))
(= (sk-instance-take-step $hash $fold $args $filter $_acc $member)
   (let $value (sk-value $member $filter (cons $hash ()))
      (if (if (== $value sk-none) (sk-member-pending? $member) false)
         (if (space-row-present? &ctx_sk_instance_changed ($hash $_stored)) () (context-add! &sk_instance_changed ($hash $fold)))
         (sk-instance-take-value! $hash $fold $args $member $value))))

;; A KB's hazard: the prior probability that a sample of a refined rule's
;; branch starts a new regime of its rate (docs/metta/hypothesis_rules.md,
;; "Regimes"); 0 keeps one regime.
(: &rule_change_hazard (SpaceOf (KB Number)))
!(bind! &rule_change_hazard (new-space))

(: set-rule-change-hazard (-[det]-> KB Number Bool))
(= (set-rule-change-hazard $kb $hazard)
   (let* (($_old (remove-data-rows! &rule_change_hazard (quote ($kb $_stored))))
          ($_new (add-atom &rule_change_hazard ($kb $hazard))))
      (> $hazard 0.0)))

(: rule-change-hazard (-[det]-> KB Number))
(= (rule-change-hazard $kb)
   (case (collapse (once (match &rule_change_hazard ($kb $hazard) $hazard))) (
      ((cons $hazard $_more) $hazard)
      (() 0.0001))))

(: sk-instance-take-value! (-[semidet]-> Number SkeletonKey ScalarFoldSpec SkeletonKey SkeletonValue Atom))
(= (sk-instance-take-value! $hash $fold $args $member $value)
   (let* ((($kb $_pattern $extractor $start $function $_finish $_mode) $args)
          ($mhash (index-hash $member))
          ($_clean (remove-variant-row! &sk_rate_dirty (quote ($hash $mhash $fold $member))))
          ($new
             (fa-instance-acc
                (case $value (
                   ((sk-val $fact $_ev $_deps) (sk-accumulate $extractor $function $start $fact))
                   ($_none $start)))))
          ($found
             (collapse (once (match &ctx_sk_instance_member ($mhash $hash $stored $pos-seg $neg-seg $contribution)
                (if (=alpha $stored $member) (instance-sample $pos-seg $neg-seg $contribution) (empty))))))
          ($_digest (sk-instance-digest! $hash $mhash $member $value $new)))
      (sk-instance-store! $hash $fold $mhash $member (sk-instance-tally $hash $fold $kb) $new
         (case $found (
            ((cons (instance-sample $was-pos $was-neg $old) $_others)
               (let $_replaced (remove-variant-row! &sk_instance_member (quote ($mhash $hash $member $was-pos $was-neg $old)))
                  (instance-sample $was-pos $was-neg $old)))
            (() (let $_reads (sk-instance-reads! $hash $mhash $member) (instance-sample 0 0 (fa-instance-acc $start)))))))))

;; A fold's digest sums a signature of each member's sample: the observation
;; of its consequent, the facts of the sample's evidence other than its
;; antecedent's stored facts, and the antecedent's strength, the share of the
;; sample's mass in the positive branch (to six places, so the confidence the
;; consequent is read with does not part samples of one observation). Two
;; folds have equal digests when their samples weigh the same instances alike
;; and observe them through the same facts, whatever statement each sample
;; reads as its consequent: a consequent a deterministic rule derives from a
;; stored outcome observes that outcome (sk-sample-twins?). A member that is
;; no sample adds nothing. The signature a member was taken with is kept, so a
;; changed member replaces its own.
(: SkeletonSampleSig Type)
(: sk-sample-sig (-[det]-> Number Number SkeletonSampleSig))
(: sk-instance-digest! (-[det]-> Number Number SkeletonKey SkeletonValue InstanceEvidenceState Atom))
(= (sk-instance-digest! $hash $mhash $member $value (InstanceEvidence (BaseRateEvidence $_pw $pm) (BaseRateEvidence $_nw $nm)))
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $_b $_atv $_btv) $kbctx)
         (let* (($observed
                  (case $value (
                     ((sk-val $_fact $ev $_deps)
                        (let $kept
                              (evidence-subtraction $ev
                                 (evidence-set (foldr-flat (sk-antecedent-fact-entries $kbctx) () (implication-side-conjuncts (the Statement $a)))))
                           (fold-flat sk-entry-hash-step 0 (evidence-shared-facts $kept $kept))))
                     ($_none 0))))
                ($mass (+ $pm $nm))
                ($sig (if (> $mass 0.0) (index-hash (sk-sample-sig $observed (round-math (* 1000000 (/ $pm $mass))))) 0))
                ($was (case (collapse (once (match &ctx_sk_instance_digest ($hash $stored) $stored))) (((cons $d $_rest) $d) (() 0))))
                ($taken (case (collapse (once (match &ctx_sk_instance_sig ($mhash $hash $stored-sig) $stored-sig))) (((cons $t $_more) $t) (() 0))))
                ($digest (+ (- $was $taken) $sig))
                ($_old (remove-data-rows! &sk_instance_digest (quote ($hash $_d))))
                ($_new (context-add! &sk_instance_digest ($hash $digest)))
                ($_old-sig (remove-data-rows! &sk_instance_sig (quote ($mhash $hash $_s))))
                ($_new-sig (context-add! &sk_instance_sig ($mhash $hash $sig))))
            ()))
      ($_other ()))))

(: sk-antecedent-fact-entries (-[det]-> KBContext Atom (List Evidence) (List Evidence)))
(= (sk-antecedent-fact-entries $kbctx $conjunct $entries)
   (foldr-flat sk-fact-entry-step $entries (kb-facts (the Statement $conjunct) $kbctx)))

(: sk-fact-entry-step (-[det]-> (Statement KBContext Proof TV) (List Evidence) (List Evidence)))
(= (sk-fact-entry-step ($type $kbctx $proof $_tv) $entries) (cons (fact-evidence-entry $kbctx $proof $type) $entries))

;; A set of entries as the sum of their hashes, whatever their order.
(: sk-entry-hash-step (-[det]-> Number Evidence Number))
(= (sk-entry-hash-step $sum $entry) (+ $sum (index-hash $entry)))

;; A member's sample taken into each branch of the tally: one new to a branch
;; is a segment of its own there, numbered by the tally's sample counter
;; (negated in the negative branch), a known one is replaced in its segment.
(: sk-instance-store!
   (-[det]-> Number SkeletonKey Number SkeletonKey InstanceRegimeState InstanceEvidenceState InstanceSample Atom))
(= (sk-instance-store! $hash $fold $mhash $member (instance-regimes $hazard $next $pos $neg) (InstanceEvidence $new-pos $new-neg)
      (instance-sample $pos-seg $neg-seg (InstanceEvidence $old-pos $old-neg)))
   (let* ((($pos-segs $pos-at) (regime-take! $hash $hazard $next $pos $pos-seg $old-pos $new-pos))
          (($neg-segs $neg-at) (regime-take! $hash $hazard (- 0 $next) $neg $neg-seg $old-neg $new-neg))
          ($counted (+ $next 1))
          ($taken (instance-regimes $hazard $counted (the (List RegimeSegment) $pos-segs) (the (List RegimeSegment) $neg-segs)))
          ($_untallied (remove-variant-row! &sk_instance_tally (quote ($hash $fold (instance-regimes $hazard $next $pos $neg)))))
          ($_tallied (context-add! &sk_instance_tally ($hash $fold $taken)))
          ($new (InstanceEvidence $new-pos $new-neg))
          ($_member (context-add! &sk_instance_member ($mhash $hash $member $pos-at $neg-at $new))))
      ()))

;; Takes the members of an instance fold that joined or changed since it last
;; took them, each at its current value: every take costs the members that
;; changed, never the instances.
(: sk-instance-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-instance-take! $hash $args)
   (let* (($fold (sk-fold $args))
          ($changed
             (collapse (match &ctx_sk_rate_dirty ($hash $_mhash $stored $member)
                (if (=alpha $stored $fold) $member (empty))))))
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
   (let $value (sk-premise-value false (sk-value $member sk-any-filter (cons $hash ())))
      ;; PENDING is not a retraction. Keep the sample's previous contribution
      ;; until its context node publishes a value or a settled empty result.
      (if (if (== $value sk-none) (sk-member-pending? $member) false) ()
      (let* (($mhash (index-hash $member))
             ($_clean (remove-variant-row! &sk_rate_dirty (quote ($hash $mhash $fold $member)))))
      (case $value (
         ((sk-val $fact $_ev $_deps) (let $_updated (collapse (fa-update! $fact $id (copy_term $descriptor))) ()))
         ($_none
            (case $member (
               ((sk-key $type $kbctx)
                  (let $_removed
                     (collapse (fa-remove! (assemble-runtime-fact $type $kbctx (brand Proof cpu) (STV 0.0 0.0)) $id (copy_term $descriptor)))
                     ()))
               ($_fold ()))))))))))

(: sk-rate-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-rate-take! $hash $args)
   (if (sk-instance-fold? $args) (sk-instance-take! $hash $args)
   (let $key (sk-fold $args)
      (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)) (
         ((cons (fa-subscription $identity $descriptor $trigger $both $second) $_none)
            (let* (($_registered (fa-register! $identity $descriptor $trigger $both $second))
                   ($changed
                      (collapse (match &ctx_sk_rate_dirty ($hash $_mhash $fold $member)
                         (if (=alpha $fold $key) $member (empty))))))
               (case (collapse (fa-id $identity)) (
                  ((cons $id $_more)
                     (let $_linked (link-aggregate-fold! $id $hash)
                        (fold-semidet (sk-rate-take-step $hash $key $id $descriptor) () $changed)))
                  (() ())))))
         ($_other ()))))))

(: sk-cached-fold-view (-[semidet]-> Number ScalarFoldSpec BaseRateEntry SkeletonValue))
(= (sk-cached-fold-view $hash $args $entry)
   (sk-goal-val (CPU FoldAllCompiled $args (base-rate-entry-tv $entry)) (brand Proof cpu) (ev-set 0)
      (deps-key $hash)))

;; --- Coverage of exact folds (docs/metta/partial_folds.md) -------------------

;; A member without a value is still to come while one of its key's rows is
;; stale, was never computed, or waits for conditioning; once every row is
;; computed and current and none derives anything, it is no member.
;; covered members, members still to come
(: SkeletonCover Type)
(: sk-cover (-[det]-> Number Number SkeletonCover))

(: sk-cover-member-step (-[semidet]-> Number SkeletonFilter SkeletonCover SkeletonKey SkeletonCover))
(= (sk-cover-member-step $hash $filter (sk-cover $covered $missing) $key)
   (if (== (sk-value $key $filter (sk-fold-exclusions $hash)) sk-none)
      (if (sk-member-pending? $key) (sk-cover $covered (+ $missing 1)) (sk-cover $covered $missing))
      (sk-cover (+ $covered 1) $missing)))

;; The premises of the member node's joins that have no answer yet.
(: sk-unanswered-step (-[det]-> (List SkeletonNodeAt) SkeletonNodeAt (List SkeletonNodeAt)))
(= (sk-unanswered-step $kept (sk-node-at $hash $premise))
   (if (== (sk-answers $premise) ()) (cons (sk-node-at $hash $premise) $kept) $kept))

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
      (if (if (== $finish identity) (if (== $function OrFormula) false (if (== $function ExistentialFloor) false true)) false)
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
;; The versions a consumer takes: per row, the latest one it admits.

(: sk-version-view (-[det]-> SkeletonVersion SkeletonValue))
(= (sk-version-view (sk-version $_seq $_rhash $view)) $view)

(: sk-admitted (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-admitted $hash $key $filter $exclude)
   (map-flat sk-version-view (sk-admitted-versions $hash $key $filter $exclude)))

(: sk-certain-leaf-step (-[det]-> (List SkeletonValue) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-certain-leaf-step $sources $kept $leaf)
   (case $leaf (
      ((sk-val $fact $_ev $_deps)
         (if (sk-certain? (brand Statement (car-atom $fact)) (cons $fact ()))
            (if (stored-list-member? $leaf $sources) (cons $leaf $kept) $kept) $kept))
      ($_other $kept))))

;; A value depending on an incomplete fold is provisional: computed from part
;; of an aggregate that needs all of it (docs/metta/partial_folds.md). A key
;; merges its provisional values only when it has no other.
(: sk-complete-step (-[semidet]-> (List Number) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-complete-step $partial $kept $value)
   (if (deps-meet? $partial (sk-view-deps-step 0 $value)) $kept (cons $value $kept)))

(: sk-complete-values (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-complete-values $values)
   (case (collapse (match &ctx_sk_partial ($fold-hash $_fold) $fold-hash)) (
      (() $values)
      ($partial
         (case (fold-semidet (sk-complete-step $partial) () $values) (
            (() $values)
            ($complete (fold-semidet sk-cons-step () $complete))))))))

;; A view that gives way to another view of the key, a projection to its full
;; proof or a settled step to the complete step it settles, adds nothing to
;; it, so it is dropped before the views merge: merged first with a third
;; view, it would stand for the complete step there (fuzzer seed 4000032: a
;; settled forward view revised with an inversion, then met the complete step
;; as an overlap and lost to it).
(: sk-gives-way-step (-[det]-> Proof Bool SkeletonValue Bool))
(= (sk-gives-way-step $proof $found $other)
   (if $found true
      (case $other (
         ((sk-val $fact $_ev $_deps)
            (let $other-proof (sk-fact-step-proof $fact)
               (if (== $other-proof $proof) false (proof-dominates? $other-proof $proof))))
         ($_goal false)))))

(: sk-standing-step (-[semidet]-> (List SkeletonValue) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-standing-step $values $kept $value)
   (case $value (
      ((sk-val $fact $_ev $_deps)
         (if (fold-flat (sk-gives-way-step (sk-fact-step-proof $fact)) false $values) $kept (cons $value $kept)))
      ($_goal (cons $value $kept)))))

;; In a private judgment, an assumption-dependent alternative excludes the
;; assumption-free alternatives of the same key before revision, dominance or
;; certainty can select them. A world-only key remains usable as a co-premise,
;; but cannot itself establish the judgment's consequent. MAIN is unchanged.
(: sk-judgment-dependent-step
   (-[semidet]-> (List Number) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-judgment-dependent-step $assumptions $kept $value)
   (if (deps-meet? $assumptions (sk-view-deps-step 0 $value)) (cons $value $kept) $kept))

(: sk-judgment-values (-[semidet]-> SkeletonKey (List SkeletonValue) (List SkeletonValue)))
(= (sk-judgment-values $key $values)
   (case $key (
      ((sk-key $type ($kbid $ctx $vars))
         (if (== $ctx MAIN) $values
            (let* (($scope (make-kb-context (brand KB $kbid) $ctx $vars))
                   ;; Keep the stored assumption's variable sharing. A
                   ;; computed consequent may have bound this reader's vars.
                   ;; Bind the ctx proof head for the existing fact index;
                   ;; enumerating arbitrary proofs scans unrelated world facts.
                   ($assumptions (collapse
                      (let $proof (superpose ((ctx proof $ctx) (ctx proof $ctx $idx)))
                         (match &kb ($assumed ($kbid $ctx $assumed-vars) $proof $_tv)
                            (index-hash (sk-key $assumed ($kbid $ctx $assumed-vars)))))))
                   ($dependent (fold-semidet (sk-judgment-dependent-step $assumptions) () $values)))
               (case $dependent (
                  (() (if (judgment-consequent? true $type $scope) () $values))
                  ($_found (fold-semidet sk-cons-step () $dependent)))))))
      ($_fold $values))))

;; Leaves first, then one version per row in the order the rows were found.
;; A ground statement stored with confidence 1 is its own value, as expansion
;; applies no rule to it: no other proof could change it, so its rows' views
;; add neither evidence nor dependencies. A derived view of confidence 1 is a
;; probability known exactly, not the statement's truth, and merges as usual.
;; Views read under given statements leave out the leaves that depend on them.
;; Views that overlap condition the key on what they share.
(: sk-merge-key
   (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonGiven) (List SkeletonValue) SkeletonValue))
(= (sk-merge-key $hash $key $filter $exclude $given $views)
   (let* (($outside (hash-union $exclude (hash-set (sk-given-hashes $given))))
          ($leaves (sk-leaf-views $hash $key $filter $outside))
          ($sources (sk-judgment-values $key (append-flat $leaves $views)))
          ($certain (fold-semidet (sk-certain-leaf-step $sources) () $leaves))
          ($own (sk-own-values (sk-complete-values (if (== $certain ()) $sources $certain))))
          ($standing (fold-semidet sk-cons-step () (fold-semidet (sk-standing-step $own) () $own)))
          (($values $siblings) (sk-reference-values (hash-union (sk-unifier-hashes $hash $key) $outside) $standing)))
      (case (sk-lift $siblings $values) (
         ((cons $lifted $_rest) $lifted)
         (()
            (case (fold-semidet (sk-pair-merge-step true (hash-union (sk-unifier-hashes $hash $key) $outside)) (sk-merging sk-none () 0) $values) (
               ;; Every fact view depends on its own key. A nonempty
               ;; overlap dependency set also marks an unconditionable
               ;; overlap (shared observations, with no cut statements).
               ((sk-merging $merged () $deps)
                  (if (if (== $deps 0) (if $siblings false true) false) $merged
                     (sk-key-fallback (hash-union (sk-unifier-hashes $hash $key) $outside) $values)))
               ((sk-merging $_provisional $keys $deps)
                  (let $merged (sk-key-fallback (hash-union (sk-unifier-hashes $hash $key) $outside) $values)
                     (sk-conditioned $given (sk-key-target $hash $key $filter $exclude) $hash -1
                     (hash-union $exclude (sk-unifier-hashes $hash $key)) $keys (+ 1 (deps-size $deps)) $merged $merged))))))))))

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
            (sk-acc (cons $proof $fold-proofs) (evidence-union $ev $fold-ev) (cons $fold-deps $deps) $parts)
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
      ((sk-pool-part $base $tv $arity $_idxs $_marginal)
         (case $other (
            ((sk-pool-part $other-base $other-tv $other-arity $_other-idxs $_other-marginal)
               (if (same-proof? $base $other-base) (=alpha (data $tv $arity) (data $other-tv $other-arity)) false))
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
            ((sk-pool-part $_part-base $_part-tv $_part-arity $new-idxs $_part-marginal)
               (if (sk-same-pool? $head $part)
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
         (if (if (=alpha $given-key $key) true
                  (case (data $given-key $key) (
                     (((sk-key $type ($kbid MAIN Nil)) (sk-key $local-type $scope))
                        (if (if (== (car-atom $scope) $kbid) (=alpha $type $local-type) false)
                           (if (judgment-world-premise? (brand Statement $local-type) (brand KBContext $scope))
                              (not (judgment-assumed-key? $local-type (brand KBContext $scope))) false) false))
                     ($_other false))))
            (case $key (
               ((sk-key $type $kbctx)
                  (cons (sk-val (assemble-runtime-fact $type $kbctx (brand Proof (given $truth)) (STV (if $truth 1.0 0.0) 1.0))
                           (ev-set 0) (deps-key $hash))
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
               (if (sk-excludes? $exclude (sk-view-deps-step 0 $again)) sk-none $again)))
         (() $view)))
      $view))

;; A key's value under a condition: its value, unless that depends on a given
;; statement; then the merge of its leaves and its views read under it. A
;; compound And or Or with no value whose rows read a given statement directly
;; is the merge of those rows evaluated under the condition: a compound read
;; off its parts has no value while one part has none, and has one with the
;; part given. Evaluating every key so cost SupplyNet stage 3 a third more
;; time for no change. A compound reached again through its own rows while
;; they are evaluated so has no value there (row hash -2 in &sk_conditioning).
(= (sk-given-value $given $key $filter $exclude)
   (let $value (sk-value $key $filter $exclude)
      (if (sk-given-meets? $given $value) (sk-given-merge $given $key $filter $exclude)
         (if (if (== $value sk-none) (not (== $given ())) false)
            (case $key (
               ((sk-key $type $kbctx)
                  (let $hash (index-hash $key)
                     (if (if (not (head-is-member? $type (And Or Implication))) true (space-row-present? &ctx_sk_conditioning ($hash -2))) sk-none
                        (let* (($_entered (context-add! &sk_conditioning ($hash -2)))
                               ($views
                                  (fold-semidet (sk-given-row-step $given $exclude $hash $key) ()
                                     (collapse (match &sk_row ($hash $stored $rhash $row) (if (=alpha $stored $key) ($rhash $row) (empty))))))
                               ($_left (context-remove! &sk_conditioning ($hash -2))))
                           (if (== $views ()) sk-none (sk-merge-key $hash $key $filter $exclude $given $views))))))
               ($_fold sk-none)))
            $value))))

(: sk-given-row-step
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey (List SkeletonValue) (Number SkeletonRow)
       (List SkeletonValue)))
(= (sk-given-row-step $given $exclude $hash $key $views ($rhash (sk-row $ident $concl $premises $seq)))
   (if (fold-semidet (sk-reads-given-step (sk-given-hashes $given)) false $premises)
      (case (sk-row-view $given $exclude $hash $key $rhash (sk-row $ident $concl $premises $seq)) (
         (sk-none $views)
         ($view (cons $view $views))))
      $views))

(: sk-reads-given-step (-[det]-> (List Number) Bool SkPattern Bool))
(= (sk-reads-given-step $hashes $found $premise)
   (if $found true
      (case $premise (
         ((CPU $_fun $_args $_res) false)
         (($type $kbctx $_proof $_tv) (stored-list-member? (index-hash (sk-key $type $kbctx)) $hashes))
         ($_other false)))))

(: sk-given-merge (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-given-merge $given $key $filter $exclude)
   (let $hash (index-hash $key)
      (sk-merge-key $hash $key $filter $exclude $given
         (map-semidet (sk-given-view $given $exclude $hash $key) (sk-admitted-versions $hash $key $filter $exclude)))))

;; A premise value whose evidence overlaps what the row already uses is
;; replaced by the merge of the key's leaves and views that do not overlap it:
;; the consumer selects the proofs compatible with its other premises.
(: sk-compatible-step (-[semidet]-> EvidenceSet (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-compatible-step $ev $acc $view)
   (case $view (
      ((sk-val $_fact $view-ev $_deps)
         (if (premise-evidence-overlap? $ev $view-ev) $acc (cons $view $acc)))
      ($_other $acc))))

(: sk-compatible-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet Bool SkeletonValue))
(= (sk-compatible-value $given $key $filter $exclude $ev $views)
   (let* (($hash (index-hash $key))
          ($outside (hash-union $exclude (hash-set (sk-given-hashes $given))))
          ($leaves (sk-leaf-views $hash $key $filter $outside))
          ($ignore (hash-union (sk-unifier-hashes $hash $key) $outside))
          ($compatible
             (fold-semidet sk-cons-step ()
                (fold-semidet (sk-compatible-step $ev) ()
                (sk-own-values
                   (sk-judgment-values $key
                      (if $views
                         (append-flat $leaves
                            (map-semidet (sk-given-view $given $exclude $hash $key) (sk-admitted-versions $hash $key $filter $exclude)))
                         $leaves)))))))
      (let ($selected $_siblings) (sk-reference-values $ignore $compatible)
         (fold-semidet (sk-merge-step true $ignore) sk-none $selected))))

;; A fact premise takes a value unless its evidence overlaps the row's own,
;; except in joins the compiler marked as sharing their sources and for
;; projections joining a pool of the same source. A refined rule's truth is a
;; parameter of the row: the row depends on the truth's key, not on the
;; instances the truth was learned from, which the row does not observe.
(: sk-use-premise (-[semidet]-> Bool SkeletonRowState SkPattern SkeletonValue SkeletonRowState))
(= (sk-use-premise $shared (sk-acc $fold-proofs $ev $deps $parts) ($type $kbctx $proof $tv) $value)
   (case $value (
      ((sk-val $fact $premise-ev $premise-deps)
         (let $part (sk-premise-part $fact)
            (if (if $shared false
                   (if (premise-evidence-overlap? $ev $premise-ev) (not (sk-joins-pool? $parts $part)) false))
               sk-fail
               (if (= ($type $kbctx $proof $tv) (if (is-var $proof) $fact (sk-full-fact $fact)))
                  (sk-acc $fold-proofs (evidence-union $ev $premise-ev)
                     (cons
                        (if (if (is-expr $type) (== (car-atom $type) RuleTruth) false)
                           (deps-key (index-hash (sk-key $type $kbctx)))
                           $premise-deps)
                        $deps)
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
;; row, less those already given and those known, the most impact first. A
;; conditioned branch evaluates at most the value's dependencies. A premise that reads one of
;; those statements itself reads it as known under the condition, so a row
;; reading K and a value derived from K is exact: an And loop C <- (And A B),
;; B <- (Or A C) read by D <- (And C A) with A soft (fuzzer seed 12000289).
;; There is nothing to condition when the premise reads a projection:
;; projections of one source share it by construction and pool, and
;; projecting a conjunction known false has no conditional value.
(: sk-clash-on (-[semidet]-> (List SkeletonGiven) SkeletonRowState SkeletonValue SkeletonRowState))
(= (sk-clash-on $given $state $value)
   (case $state (
      ((sk-acc $_fold-proofs $ev $deps $_parts)
         (case $value (
            ((sk-val $fact $value-ev $value-deps)
               (if (sk-projection? $fact) (sk-clash () 0)
                  (let*
                     (($shared-facts (evidence-shared-facts $ev $value-ev))
                      ($keys (list_to_set (fold-semidet (sk-shared-key-step $given) () $shared-facts))))
                     (sk-clash
                        ;; A signed proof can name shared evidence without a
                        ;; scoped fact-ev entry. Its dependency keys retain the
                        ;; statement and context needed for conditioning.
                        (if (== $keys ())
                           (if (== $shared-facts ()) ()
                              (sk-shared-statements (sk-given-hashes $given)
                                 (deps-shared (deps-join $deps) $value-deps)))
                           (sk-ranked-statements (fold-semidet sk-shared-candidate () $keys)))
                        (+ 1 (deps-size $value-deps))))))
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
         (sk-val (assemble-runtime-fact $type $kbctx (brand Proof unfounded) (STV 0.0 1.0)) (ev-set 0) (deps-key $hash)))
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

;; This check also removes retired waiters encountered in the child index.
(: sk-application-waits? (-[semidet]-> SkPattern Bool SkeletonNodeAt Bool))
(= (sk-application-waits? $node $found (sk-node-at $hash $child))
   (if $found true
      (if (sk-delivered? $child) false
         (not (== (collapse (once (match &sk_wait ($hash $stored (sk-partial $owner $rule ($_t $_k $proof $_v) $_done $_rest $_keys))
                     (if (=alpha $stored $child)
                        (if (rule-live? $rule)
                           (if (=alpha $owner $node) (if (rule-application-proof? $proof) true (empty)) (empty))
                           (let $_removed (sk-retire-wait! $hash $stored (sk-partial $owner $rule ($_t $_k $proof $_v) $_done $_rest $_keys)) (empty)))
                        (empty)))))
                  ())))))

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
            (if (sk-expanded? $hash $node)
               (if (== (collapse (once (superpose (
                         (match &sk_deferred_joins ($hash $jhash (sk-join (sk-partial $join-owner $join-rule $jc $jd $jr $jk) $answer))
                            (if (rule-live? $join-rule) true
                               (let* (($_removed (remove-variant-row! &sk_deferred_joins (quote ($hash $jhash (sk-join (sk-partial $join-owner $join-rule $jc $jd $jr $jk) $answer)))))
                                      ($_work (sk-work! $hash $join-owner -1))) (empty))))
                         (match &sk_deferred ($hash $rhash (sk-deferred $row-owner $row-rule $rc $rp $rk))
                            (if (rule-live? $row-rule) true
                               (let* (($_removed (remove-variant-row! &sk_deferred (quote ($hash $rhash (sk-deferred $row-owner $row-rule $rc $rp $rk)))))
                                      ($_work (sk-work! $hash $row-owner -1))) (empty))))))))
                       ())
                  (if (fold-semidet (sk-application-waits? $node) false (sk-children $hash $node)) false true)
                  false)
               false)))
      ($_fold false))))

;; Whether a rule application is among a statement's rows. This check also
;; removes encountered retired rows and their optimization registrations.
(: sk-founded? (-[det]-> Number SkeletonKey Bool))
(= (sk-founded? $hash $key)
   (not (== (collapse (once (match &sk_row ($hash $stored $_rhash (sk-row (sk-ident $rule $_keys $_key) ($_t $_k $proof $_v) $_ps $_seq))
               (if (=alpha $stored $key)
                  (if (rule-live? $rule) (if (rule-application-proof? $proof) true (empty))
                     (let $_removed (sk-drop-row! $hash $stored $_rhash (sk-row (sk-ident $rule $_keys $_key) ($_t $_k $proof $_v) $_ps $_seq)) (empty)))
                  (empty)))))
            ())))

(: sk-closed-row-step
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey (List SkeletonValue) (Number SkeletonRow)
       (List SkeletonValue)))
(= (sk-closed-row-step $given $exclude $hash $key $kept ($rhash $row))
   (case (sk-row-view $given $exclude $hash $key $rhash $row) (
      (sk-none $kept)
      ($view (cons $view $kept)))))

;; What a row's closed reads take as unfounded: a complete statement, the
;; row's own conclusion when the row is a rule application of it (or a
;; completion's consequence, sk-completion-state); nothing otherwise, and the
;; row reads no premise closed.
(: sk-closed-pin (-[det]-> Number Atom Atom Bool (List SkeletonGiven)))
(= (sk-closed-pin $khash $type $kbctx $reads)
   (if (if $reads (complete-statement? $type $kbctx) false)
      (cons (sk-unfounded $khash (sk-key $type $kbctx)) ())
      ()))

;; A complete statement with no value the reader may read, once its search is
;; settled: unfounded when no rule application derives it, whoever reads it;
;; otherwise, for a reader with a pin, its rows evaluated again in creation
;; order with the pin joining the given list, merged with the leaves the
;; reader may read.
;; An excluded key cannot become admissible by closing it. Pins already in
;; the given list are read by sk-premise-step before reaching this operation.
(: sk-closed-read
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) SkeletonKey SkeletonFilter SkeletonValue))
(= (sk-closed-read $pin $given $exclude $key $filter)
   (case $key (
      ((sk-key $type $kbctx)
         (if (if (complete-statement? $type $kbctx) (== (sk-given-value $given $key $filter $exclude) sk-none) false)
            (let $hash (index-hash $key)
               (if (if (sk-context-excludes? (deps-key $hash)) false (sk-settled? $key))
                  (if (sk-founded? $hash $key)
                     (if (== $pin ()) sk-none
                        (sk-merge-key $hash $key $filter $exclude $given
                           (fold-semidet sk-cons-step ()
                              (fold-semidet (sk-closed-row-step (append-flat $pin $given) $exclude $hash $key) ()
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
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool Bool SkeletonRowState SkPattern
       SkeletonRowState))
(= (sk-premise-step $pin $given $exclude $shared $priors $facts-first $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-clash $clash-keys $clash-base) (sk-clash $clash-keys $clash-base))
      ((sk-acc $fold-proofs $ev $deps $parts)
         (case $premise (
            ((CPU ContextRule ($assumption $ctx) $_res)
               (if (context-rule-enabled? $ctx)
                  (sk-acc $fold-proofs $ev (cons (deps-key (index-hash $assumption)) $deps) $parts)
                  sk-fail))
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
                                 (sk-premise-value $priors
                                    (if $facts-first (sk-compatible-value $given $key $filter $exclude $ev false)
                                       (sk-given-value $given $key $filter $exclude)))
                                 (case (sk-use-premise $shared $state $premise $value) (
                                    (sk-fail
                                       (if $shared sk-fail
                                          (case (sk-use-premise $shared $state $premise
                                                   (sk-premise-value $priors (sk-compatible-value $given $key $filter $exclude $ev true))) (
                                             (sk-fail
                                                (sk-clash-on $given $state
                                                   (if $facts-first (sk-premise-value $priors (sk-given-value $given $key $filter $exclude)) $value)))
                                             ($compatible $compatible)))))
                                    ($taken $taken))))
                              (case (sk-use-premise $shared $state $premise $closed) (
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
(= (sk-row-view $given $exclude $khash $key $rhash $row)
   (if (let (sk-row (sk-ident $rule $_keys $_key) $_concl $_prems $_seq) $row
          (if (rule-live? $rule) (if (context-rule-visible? $rule) (sk-claim-charge! $given) false) false))
      (let* (((sk-row $_ident ($_type $_kbctx $proof $_tv) $_premises $_seq) $row)
             ($exclusions (hash-union (sk-row-exclusions $khash $key $proof) $exclude))
             ($target (sk-row-target $exclusions $khash $key $rhash $row))
             ($greedy (copy_term $row))
             ($state (sk-row-state $given $exclusions $khash false $greedy))
             ($value
                (if (case $state (((sk-clash $_k $_b) true) ((sk-entangled $_ek $_eb $_es) true) ($_read false)))
                   (let* (($retry (copy_term $row))
                          ($again (sk-row-state $given $exclusions $khash true $retry)))
                      (case $again (
                         ((sk-clash $keys $base) (sk-conditioned $given $target $khash $rhash $exclusions $keys $base sk-none sk-none))
                         ((sk-entangled $keys $base $independent)
                            (let $approx (sk-row-result $retry $independent)
                               (sk-conditioned $given $target $khash $rhash $exclusions $keys $base $approx
                                  $approx)))
                         ($_other (sk-row-result $retry $again)))))
                   (sk-row-result $greedy $state)))
)
         $value)
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
;; value, the merge's more confident view or the row's approximate value,
;; and the pass is cut; so it is when no shared statement's mix is possible
;; there and an approximate value stands in. A clash has no approximate
;; value, so it is conditioned at any depth the claim allows.
;;
;; Outside any condition a target is conditioned only once the evaluation paid
;; for it, and keeps its waiting value until then (see sk-pay-conditions!).
;; A payment at level l costs 2^l times the base, one more than the
;; dependency count of what the target conditions, and covers a claim of
;; twice that in conditioned evaluations. A target with an approximate value
;; conditions at depth 1, then, while its passes are cut, one statement
;; deeper, each pass on what the claim has left, and keeps the deepest pass
;; that finished: so the value only moves towards the conditioning on every
;; statement met, which is exact under the views' own formulas. A clash
;; conditions at any depth in one pass (sk-deepen). A claim that overdrew waits again at
;; the next level, twice the cost, and may be paid again once the allowance
;; covers it. A paid target read inside another claim, through a weight,
;; draws from that claim. Under a closed read's pins outside any claim, a
;; target with an approximate value is conditioned when what the evaluation
;; allowance has left pays its depth-1 cost, and takes its approximate value
;; otherwise; a clash opens a claim of its own, as before. A target read again inside its own conditioning,
;; through a shared statement's value, keeps its waiting value there.
(= (sk-conditioned $given $target $khash $rhash $wexclude $keys $base $approx $waiting)
   (let $owner (sk-condition-owner $khash)
   (case $keys (
      (() $approx)
      ((cons $_first $_more)
         (if (== $given ())
            (let* (($level (sk-condition-level $owner $rhash))
                   ($cost (* (pow-math 2 $level) $base)))
               (if (if (space-row-present? &ctx_sk_given_granted ($owner $rhash)) true
                      (if (not (== (search-id-value sk_claim_left) -1)) true
                         (if (== $owner $khash) (sk-take! sk_eval_budget $cost) false)))
                  (if (space-row-present? &ctx_sk_conditioning ($owner $rhash)) $waiting
                  (if (== (search-id-value sk_claim_left) -1)
                     (let* (($_grant (context-remove! &sk_given_granted ($owner $rhash)))
                            ($_entered (context-add! &sk_conditioning ($owner $rhash)))
                            ($_opened (sk-open-claim! $cost))
                            ($deepest (sk-deepen $given $target $wexclude $keys (== $approx sk-none) (if (== $approx sk-none) 64 1) ()))
                            ($overdrawn (sk-close-claim!))
                            ($_left (context-remove! &sk_conditioning ($owner $rhash))))
                        (if $overdrawn
                           (let* (($raised (+ $level 1))
                                  ($_was (remove-data-rows! &sk_cond_level (quote ($owner $rhash $_level))))
                                  ($_raised (context-add! &sk_cond_level ($owner $rhash $raised))))
                              (sk-wait! $owner $rhash (* 2 $cost) (sk-mixed $deepest $waiting)))
                           (sk-mixed $deepest $waiting)))
                     (sk-mixed (sk-mix-on $given $target $wexclude $keys) $waiting)))
                  (sk-wait! $owner $rhash $cost $waiting)))
            (if (if (== $approx sk-none) false (>= (fold-semidet sk-given-depth-step 0 $given) (search-id-value sk_claim_depth)))
               (progn (change-state! sk_claim_cut 1) $approx)
               (if (== (search-id-value sk_claim_left) -1)
                  (if (== $approx sk-none)
                  (let* (($_opened (sk-open-claim! (* (pow-math 2 (list-len $keys)) $base)))
                         ($mixed (sk-mix-on $given $target $wexclude $keys)))
                     (if (sk-close-claim!) $approx (sk-mixed $mixed $approx)))
                  (let $cost (* 2 $base)
                     (if (> $cost (search-id-value sk_eval_budget)) $approx
                        (let* (($_paid (change-state! sk_eval_budget (- (search-id-value sk_eval_budget) $cost)))
                               ($_opened (sk-open-claim! $cost))
                               ($deepest (sk-deepen $given $target $wexclude $keys false 1 ()))
                               ($_closed (sk-close-claim!)))
                           (sk-mixed $deepest $approx)))))
                  (case (sk-mix-on $given $target $wexclude $keys) (
                     (() (if (== $approx sk-none) sk-none (progn (change-state! sk_claim_cut 1) $approx)))
                     ((cons $value $_rest) $value)))))))))))

;; The claim's passes from a depth on: the deepest pass that finished before
;; the claim overdrew, () if none did. A target without an approximate value
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
      (if (== (search-id-value sk_claim_left) -2) $deepest
         (let $cut (== (search-id-value sk_claim_cut) 1)
            (let $found (if (== $mixed ()) $deepest (if (if $cut $uncut false) $deepest $mixed))
               (if (if $cut (< $depth 64) false) (sk-deepen $given $target $wexclude $keys $uncut (+ $depth 1) $found) $found))))))

(= (sk-mixed $mixed $otherwise) (case $mixed (((cons $value $_rest) $value) (() $otherwise))))

;; The level of a target's payment, its cost 2^level times its base: 1 until
;; a claim overdrew.
(: sk-condition-level (-[det]-> Number Number Number))
(= (sk-condition-level $khash $rhash)
   (case (collapse (once (match &ctx_sk_cond_level ($khash $rhash $level) $level))) (((cons $level $_rest) $level) (() 1))))

;; The statements a condition gives, closed reads' pins aside.
(: sk-given-depth-step (-[det]-> Number SkeletonGiven Number))
(= (sk-given-depth-step $depth $given) (case $given (((sk-given $_hash $_key $_truth) (+ $depth 1)) ($_pin $depth))))

;; The target evaluated with a statement known true and known false, mixed
;; by the statement's value read without the target: the first statement in
;; order whose mix is possible, its value's evidence outside the branches.
(: sk-mix-on (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) (List SkeletonValue)))
(= (sk-mix-on $given $target $wexclude $keys)
   (case $keys (
      (() ())
      ((cons $pin $more)
         (let $phash (index-hash $pin)
            (case (collapse (once
                     (sk-mix (sk-given-value $given $pin sk-any-filter $wexclude)
                        (sk-target-value (cons (sk-given $phash $pin true) $given) $target)
                        (sk-target-value (cons (sk-given $phash $pin false) $given) $target)))) (
               (() (sk-mix-on $given $target $wexclude $more))
               ($mixed $mixed))))))))

;; A claim is the conditioning one payment covers: a row or key conditioned
;; outside any condition, with everything its branches condition on in turn,
;; down to its passes' depths. Each row it evaluates again under a condition
;; takes one of twice its cost bound (sk-claim-charge!): the bound counts each
;; dependency once per branch, and a row read through two paths is evaluated
;; twice. Conditioning reached inside an open claim, a branch's or a paid
;; key's read through a weight, draws from that claim; a closed read outside
;; any claim that conditions opens one of its own, of unbounded depth. A claim
;; that would take more stops evaluating and overdraws, and its mix falls back
;; as an unpaid one does. So no claim grows past its bound, however deep its
;; branches condition.
(: sk-open-claim! (-[det]-> Number Atom))
(= (sk-open-claim! $cost)
   (progn (change-state! sk_claim_left (* 2 $cost)) (change-state! sk_claim_depth 64) (change-state! sk_claim_cut 0) ()))

;; Whether the open claim overdrew; it closes.
(: sk-close-claim! (-[det]-> Bool))
(= (sk-close-claim!)
   (let $overdrawn (== (search-id-value sk_claim_left) -2)
      (progn (change-state! sk_claim_left -1) (change-state! sk_claim_depth 64) (change-state! sk_claim_cut 0) $overdrawn)))

;; Whether a conditioned evaluation fits the open claim, which it then takes
;; one from; one that does not fit overdraws the claim.
(: sk-claim-charge! (-[det]-> (List SkeletonGiven) Bool))
(= (sk-claim-charge! $given)
   (if (== $given ()) true
      (let $left (search-id-value sk_claim_left)
         (if (> $left 0)
            (let $_counted (query_metric_increment conditioned-evaluations)
               (progn (change-state! sk_claim_left (- $left 1)) true))
            (if (== $left 0) (progn (change-state! sk_claim_left -2) false) (> $left -2))))))

;; The branches mix by modus ponens over the weight, when all three are simple
;; truth values and the weight's evidence is not in the branches.
(: sk-mix (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue SkeletonValue))
(= (sk-mix (sk-val ($_wtype $_wkbctx $wproof (STV $ws $wc)) $wev $wdeps)
      (sk-val ($type $kbctx $tproof (STV $ts $tc)) $tev $tdeps)
      (sk-val ($_ftype $_fkbctx $fproof (STV $fs $fc)) $fev $fdeps))
   (let $branch-ev (evidence-union $tev $fev)
      (if (premise-evidence-overlap? $wev $branch-ev) (empty)
         (sk-val
            (assemble-runtime-fact $type $kbctx (brand Proof (conditioned $wproof $tproof $fproof))
               (CTVModusPonensFormula (STV $ws $wc) (CTV (STV $ts $tc) (STV $fs $fc))))
            (evidence-union $wev $branch-ev) (deps-union $wdeps (deps-union $tdeps $fdeps))))))

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
;; An implication instance sample reads no value a refined rule's truth
;; estimates: what the other hypotheses predict is no observation, and taking
;; it as one would count their samples again and feed hypotheses into each
;; other (docs/metta/hypothesis_rules.md, "Cross-feeding"). Nor does it read a
;; value derived through the implication it samples, a derived implication
;; applied to its own instance: the fold carries no member dependencies, so
;; the sample is where that support is refused.
(: sk-row-exclusions (-[det]-> Number SkeletonKey Atom (List Number)))
(= (sk-row-exclusions $khash $key $proof)
   (let $own
      (case $key (
         ((sk-key $type ($kbid $ctx $_vars))
            (let $local (sk-unifier-hashes $khash $key)
               ;; Fixed MAIN adapter premises must not reintroduce the
               ;; world observation of the private row's own ground key.
               ;; An open hypothetical individual is not a world individual.
               (if (if (== $ctx MAIN) false (== (extract-vars $type) ()))
                  (let $main (sk-key $type (kbctx (brand KB $kbid)))
                     (hash-union $local (sk-unifier-hashes (index-hash $main) $main)))
                  $local)))
         ($_fold-key (sk-unifier-hashes $khash $key))))
      (case $key (
         ((sk-key $type $kbctx)
            (if (if (is-expr $proof)
                   (let $head (car-atom $proof)
                      (if (is-var $head) false
                         (case (copy_term $head) (((inverted $_rule with $_prior $_token) true) ($_other false)))))
                   false)
               (hash-set (foldr-flat (sk-part-exclusions $kbctx) $own (sk-statement-parts (cons $type ()))))
               (if (head-is? $type ImplicationInstanceSample)
                  (case $type (
                     ((ImplicationInstanceSample $a $b $_atv $_btv)
                        (let* (($kbid (car-atom $kbctx))
                               ($implication (sk-key (Implication $a $b) $kbctx)))
                           (hash-union (hash-union $own (sk-unifier-hashes (index-hash $implication) $implication))
                              (hash-set (collapse (match &sk_rule_truth ($_id $hash $_type ($kbid $_ctx $_vars)) $hash))))))
                     ($_statement $own)))
                  $own)))
         ($_fold $own)))))

;; A projection of a compound, its first premise, onto one part reads the other
;; parts as evidence apart from the compound: a part's view derived from the
;; compound would divide the compound by itself (P(A) = P(ABC) / P(BC) with
;; P(BC) read off ABC is 1). So the premises after the compound exclude views
;; depending on it.
(: sk-row-state (-[semidet]-> (List SkeletonGiven) (List Number) Number Bool SkeletonRow SkeletonRowState))
(= (sk-row-state $given $exclusions $khash $facts-first (sk-row $_ident ($type $kbctx $proof $_tv) $premises $_seq))
   (let* (($pin (sk-closed-pin $khash $type $kbctx (rule-application-proof? $proof)))
          ($shared (shared-evidence-frontier-proof? $proof))
          ($start (sk-acc () (evidence-set (sk-sample-exclusions $type $kbctx)) (cons (deps-key $khash) ()) ())))
      (if (if (is-expr $proof)
             (let $head (car-atom $proof)
                (if (is-var $head) false
                   (case (copy_term $head) (((proj $_idx $_source) true) ($_other false)))))
             false)
         (sk-projection-state $pin $given $exclusions $shared $facts-first $start $premises)
         (if (sk-completion-proof? $proof)
            (sk-completion-state $given $exclusions $khash (sk-key $type $kbctx) $shared $facts-first $start $premises)
            (let $state (fold-semidet (sk-premise-step $pin $given $exclusions $shared false $facts-first) $start $premises)
               (if (if $shared false (if (rule-application-proof? $proof) true (sk-compound-proof? $proof)))
                  (sk-entangle (hash-union $exclusions (hash-set (sk-given-hashes $given))) $state)
                  $state))))))

;; A completion marginalises the parts it does not complete over their values
;; before its consequence C is observed: the likelihood of C given M is
;; s_O u + (1 - s_O) v with s_O O's probability apart from C. So the siblings
;; read no view that depends on C: one derived from C counts C twice, through
;; s_O and through the likelihood ratio. In a loop through C a sibling's
;; support through C is circular, as for a closed read: a complete sibling
;; none of whose views it may read is read closed, with a complete C pinned
;; unfounded. In B <- (Or A D), D <- B with B observed true, D's value is
;; B's own; read without it D is false and the completion onto A finds A true,
;; exact (fuzzer seed 12000268). A consequence stored as known false is
;; what the pin would make it: the siblings read it as it is, through the rows
;; it settles (B <- (And A C) with C false is false, which a closed read
;; cannot settle while A has no value). The consequence is the completion's
;; last statement premise.
;;
;; The likelihood needs the siblings only where the completed part M leaves
;; the antecedent open: M true for And, M false for Or. A sibling with no
;; value of its own is read under that condition, M given, the rows it
;; depends on evaluated again with M known: a loop B <- (Or A D), D <- (Or A
;; B) over complete B and D, with A an unobserved root and D observed false,
;; gives B no value, since A has none; given A false the closed read finds B
;; unfounded, so D false says A false (fuzzer seed 12000044; before, A
;; answered its population prior). The sibling read under M may depend on
;; M's hypothesis, which is no support: M's own key is not excluded there.
(: sk-completion-state
   (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Bool Bool SkeletonRowState (List SkPattern)
       SkeletonRowState))
(= (sk-completion-state $given $exclusions $khash $key $shared $facts-first $start $premises)
   (case (fold-flat sk-last-statement-step () $premises) (
      ((sk-key $ctype $ckbctx)
         (let* (($consequence (sk-key $ctype $ckbctx))
                ($chash (index-hash $consequence))
                ($_subscribed (sk-subscribe-leaves! $consequence $exclusions))
                ($completed (fold-semidet (sk-completed-given-step $khash $key) () $premises)))
            (if (fold-semidet sk-known-false-step false (sk-key-leaves $consequence sk-any-filter))
               (fold-semidet
                  (sk-completion-premise-step () $given $exclusions $exclusions $consequence $completed $shared $facts-first)
                  $start $premises)
               (fold-semidet
                  (sk-completion-premise-step (sk-closed-pin $chash $ctype $ckbctx true) $given $exclusions
                     (hash-union (sk-unifier-hashes $chash $consequence) $exclusions) $consequence $completed $shared $facts-first)
                  $start $premises)))))))

;; The condition a completion reads an unvalued sibling under: the completed
;; statement true when its part (negated or not) opens a conjunction, false
;; when it opens a disjunction.
(: sk-completed-given-step (-[det]-> Number SkeletonKey (List SkeletonGiven) SkPattern (List SkeletonGiven)))
(= (sk-completed-given-step $khash $key $found $premise)
   (case $premise (
      ((CPU ConjunctLikelihoodFormula ($negated $_others $_rule) $_likelihood)
         (cons (sk-given $khash $key (if $negated false true)) ()))
      ((CPU DisjunctLikelihoodFormula ($negated $_others $_rule) $_likelihood)
         (cons (sk-given $khash $key (if $negated true false)) ()))
      ($_other $found))))

(: sk-without-hash-step (-[det]-> Number (List Number) Number (List Number)))
(= (sk-without-hash-step $drop $kept $hash) (if (== $hash $drop) $kept (cons $hash $kept)))

(: sk-known-false-step (-[det]-> Bool SkFact Bool))
(= (sk-known-false-step $found ($_type $_kbctx $_proof $tv))
   (if $found true (case $tv (((STV $s $c) (if (>= $c 1.0) (<= $s 0.0) false)) ($_other false)))))

(: sk-last-statement-step (-[det]-> Atom SkPattern Atom))
(= (sk-last-statement-step $last $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) $last)
      (($type $kbctx $_proof $_tv) (sk-key $type $kbctx)))))

(: sk-completion-premise-step
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) (List Number) SkeletonKey (List SkeletonGiven)
       Bool Bool SkeletonRowState SkPattern SkeletonRowState))
(= (sk-completion-premise-step $pin $given $exclusions $siblings $consequence $completed $shared $facts-first $state $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) (sk-premise-step () $given $exclusions $shared true $facts-first $state $premise))
      (($type $kbctx $_proof $_tv)
         (if (=alpha (sk-key $type $kbctx) $consequence)
            (sk-premise-step () $given $exclusions $shared true $facts-first $state $premise)
            (case (sk-premise-step $pin $given $siblings $shared true $facts-first $state $premise) (
               (sk-fail
                  (case $completed (
                     ((cons (sk-given $khash $_key $_truth) ())
                        (if (== $state sk-fail) sk-fail
                           (sk-premise-step $pin (append-flat $completed $given)
                              (hash-set (fold-flat (sk-without-hash-step $khash) () $siblings))
                              $shared true $facts-first $state $premise)))
                     ($_none sk-fail))))
               ($read $read))))))))

(: sk-projection-state
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonRowState (List SkPattern)
       SkeletonRowState))
(= (sk-projection-state $pin $given $exclusions $shared $facts-first $start (cons $premise $parts))
   (let* ((($type $kbctx $_proof $_tv) $premise)
          ($compound (sk-key $type $kbctx)))
      (fold-semidet
         (sk-premise-step $pin $given (hash-union (sk-unifier-hashes (index-hash $compound) $compound) $exclusions)
            $shared false $facts-first)
         (sk-premise-step $pin $given $exclusions $shared false $facts-first $start $premise)
         $parts)))

;; An implication instance sample must not restate the implication it
;; estimates: its row starts out excluding every rule whose premises and
;; conclusion match the sample's antecedent and consequent, so a premise value
;; using one of them clashes and the sample reads the key's other proofs. The
;; rules are found through the conclusion index, by the consequent.
(: sk-sample-exclusions (-[semidet]-> Atom KBContext (List Evidence)))
(= (sk-sample-exclusions $type $kbctx)
   (if (if (is-expr $type) (== (car-atom $type) ImplicationInstanceSample) false)
      (let* (((ImplicationInstanceSample $a $b $_atv $_btv) (copy_term $type))
             (($kbid $_ctx $_vars) $kbctx)
             ($conjuncts (implication-side-conjuncts (the Statement $a))))
         (collapse
            (match ccls_index (($b ($kbid $_rctx $_rvars) $prf $_tv) $_id $prems)
               (if (= (foldr-flat sk-fact-premise-type () $prems) $conjuncts)
                  (rule-excluded (brand KB $kbid) (rule-evidence-head $prf))
                  (empty)))))
      ()))

(: sk-fact-premise-type (-[det]-> Atom (List Atom) (List Atom)))
(= (sk-fact-premise-type $premise $types)
   (case $premise (
      ((CPU $_fun $_args $_res) $types)
      (($type $_kbctx $_prf $_tv)
         (if (if (head-is? $type RuleTruth) (= $type (RuleTruth $_implication)) false)
            $types (cons $type $types))))))

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

;; A false assumed antecedent cannot supply evidence through an STV's
;; population-inferred complement. Keep a zero-confidence value so internal
;; two-branch scaffolds can still read the unsupported side as unknown.
;; Explicit CTVs have no ImplicationCTVFormula and retain both stated branches.
(: sk-assumed-false-application? (-[det]-> (List SkPattern) Proof Bool))
(= (sk-assumed-false-application? $premises $proof)
   (if (not (== (collapse (once (let $stv-premise (superpose $premises)
          (case $stv-premise (((CPU ImplicationCTVFormula $_args $_out) true) ($_other (empty))))))) ()))
      (if (not (== (collapse (once (let $mp-premise (superpose $premises)
             (case $mp-premise (
                ((CPU $mp ((STV $s $c) $_ctv) $_result)
                   (if (if (if (== $mp CTVModusPonensFormula) true (== $mp ImplicationModusPonensFormula))
                           (if (<= (the Number $s) 0) (>= (the Number $c) 1) false) false) true (empty)))
                ($_other (empty))))))) ()))
         (== (collapse (once (proof-term-evidence proof-walk-in-kb $proof))) ((ev-set 0)))
         false)
      false))

;; Keep the TV union at a typed boundary: inlining these two constructors
;; into sk-row-result leaves a residual runtime TV check in strict mode.
(: sk-unsupported-tv (-[det]-> TV TV))
(= (sk-unsupported-tv $tv)
   (case $tv (
      ((CTV $_pos $_neg) (CTV (STV 0.0 0.0) (STV 0.0 0.0)))
      ($_other (STV 0.0 0.0)))))

(: sk-row-result (-[semidet]-> SkeletonRow SkeletonRowState SkeletonValue))
(= (sk-row-result (sk-row $_ident ($type $kbctx $proof $tv) $premises $_seq) $state)
   (case $state (
      ((sk-acc $fold-proofs $ev $deps $_parts)
         (let* (((token-state $full-proof $_unused)
                   (replace-token $proof (fold-semidet sk-cons-step () $fold-proofs)))
                ($unsupported (let ($_kb $ctx $_vars) $kbctx
                   (if (== $ctx MAIN) false
                      (sk-assumed-false-application? $premises (brand Proof $full-proof)))))
                ($value-tv (if $unsupported (sk-unsupported-tv $tv)
                   (sk-cover-tv (fold-semidet sk-fold-share-step 1 $fold-proofs) $tv)))
                ($fact (assemble-runtime-fact $type $kbctx
                   (sk-unwrap-proof $full-proof) $value-tv)))
            (sk-val $fact (if $unsupported (ev-set 0) (rule-result-evidence $fact $ev)) (deps-join $deps))))
      ($_failed sk-none))))

;; --- Context-node scheduling -----------------------------------------------
;; The native scheduler owns the one heap and producer-node subscriptions.
;; Row evaluation and PLN formulas remain here; no read computes a missing row.
(: sk-same-view? (-[det]-> SkeletonValue SkeletonValue Bool))
(= (sk-same-view? $new $old)
   (case $new (
      ((sk-val ($type $kbctx $_proof $tv) $ev $deps)
         (case $old (
            ((sk-val ($old-type $old-kbctx $_old-proof $old-tv) $old-ev $old-deps)
               (if (=alpha (data $type $kbctx $tv) (data $old-type $old-kbctx $old-tv))
                  (if (=alpha $ev $old-ev) (if (deps-within? $deps $old-deps) (deps-within? $old-deps $deps) false) false) false))
            ($_other false))))
      ((sk-goal-val $goal $_proof $ev $deps)
         (case $old (
            ((sk-goal-val $old-goal $_old-proof $old-ev $old-deps)
               (if (=alpha $goal $old-goal) (if (=alpha $ev $old-ev) (if (deps-within? $deps $old-deps) (deps-within? $old-deps $deps) false) false) false))
            ($_other false))))
      (sk-none (== $old sk-none)))))

(: sk-structural-readers (-[det]-> SkeletonKey (List SkeletonItem)))
(= (sk-structural-readers $key)
   (let $hash (index-hash $key)
      (collapse (match &ctx_sk_row_input ($hash $stored $khash $rhash)
         (if (=alpha $stored $key)
            (match &sk_row ($khash $rkey $rhash (sk-row $ident $concl $premises $seq))
               (sk-row-item $seq $khash $rkey $rhash (sk-row $ident $concl $premises $seq)))
            (empty))))))


(: sk-root-keys-step (-[semidet]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-root-keys-step $keys $goal) (append-flat $keys (sk-root-keys $goal)))

;; --- Base-rate API ----------------------------------------------------------

;; Setting or clearing a user base rate changes the folds over its pattern,
;; which recompute with their readers at the next evaluation.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($stored (copy_term $pattern))
          ($hash (base-rate-cache-hash $kbid $pattern))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_new (context-add! &base_rate_cache ($hash (base-rate $kbid $stored $tv user any)))))
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
          ($_rules (forget-stored-rules! materialized $hash (sk-key $type $kb)))
          ($_mark (remove-atom &materialized_facts (materialized-row $hash $type $kb ($type $kb $proof $tv) $ev))))
      ()))

;; A re-materialization of an output key replaces the key's earlier
;; materialized rows. Marked facts are never leaves of the backward search.
(: upsert-materialized! (-[semidet]-> SkFact EvidenceSet Proof Atom))
(= (upsert-materialized! ($type $kb $proof $tv) $ev $source)
   (let* (($fact (data $type $kb $proof $tv))
          ($hash (forward-output-index-hash (forward-output-key $kb $type)))
          ($row (materialized-row $hash $type $kb $fact $ev)))
      (if (space-row-present? &materialized_facts $row) ()
         (let* (($_remove (foreach-flat remove-materialized! (materialized-rows (forward-output-key $kb $type))))
                ($_add (chainer-add-atom &kb $fact))
                ($_index (kb-index-fact! live $fact))
                ($_rules (record-stored-rules! materialized $hash (sk-key $type $kb) $source))
                ($_mark (add-atom &materialized_facts $row))
                ($_journal (sk-note-fact! $type $kb)))
            (record-fact-inheritance-nodes! $fact false)))))

(: materializable-result? (-[det]-> SkFact Bool))
;; A positive implication judgment is a query result, never a world fact.
(= (materializable-result? ($type ($kbid $ctx $vars) $_prf $tv))
   (if (if (head-is? $kbid implication-query) false (== $ctx MAIN))
      (if (if (head-is-member? $type (ExistsJudgment ExistentialAlternatives)) false (== $vars Nil))
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
            (upsert-materialized! (sk-full-fact $fact) $ev (proof-atom-proof $fact))
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
   (expansions nodes-walked rows-created rows-deferred joins-deferred row-computes views-stored
    views-without-support merged-cache-hits merged-cache-misses conditioned-evaluations rows-unpaid
    conditions-unpaid context-nodes-created context-node-count context-classes-max context-classes-mean))

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
;; unfounded, as to any reader (sk-closed-read).
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
                        (case (sk-closed-read () () () $key $filter) (
                           (sk-none
                              (case (sk-materialized-views $type $kbctx $filter) (
                                 ((cons $incumbent $_rest) $incumbent)
                                 (() (if $ground (sk-population-prior $type $kbctx $filter) sk-none)))))
                           ($unfounded $unfounded))))
                     ($current $current))))
               sk-none))))))

(: sk-materialized-views (-[det]-> Statement KBContext SkeletonFilter (List SkeletonValue)))
(= (sk-materialized-views $type $kbctx $filter)
   (if (== (extract-vars $type) ())
      (let $hash (forward-output-index-hash (forward-output-key $kbctx $type))
         (collapse (match &materialized_facts (materialized-row $hash $type $kbctx $fact $ev)
            (if (sk-fact-matches? $filter $fact)
               (sk-val $fact $ev 0)
               (empty)))))
      ()))

;; A ground root the search left without a value answers with the base rate
;; of its population: a base rate one of its rules reads over a pattern its
;; statement belongs to, the prior its inversions update. It costs no
;; expansion, so a root the budget did not reach still has an estimate, with
;; the confidence of the members counted; any view the search finds replaces
;; it. It is the prior an inversion reads (population-prior-tv), and a
;; positive-only predicate has none. The prior is the population's value, not
;; the statement's, and is never materialized. A statement nothing derives
;; gets the same prior as a row once expanded (sk-start-prior!).
(: sk-population-prior (-[semidet]-> Statement KBContext SkeletonFilter SkeletonValue))
(= (sk-population-prior $type $kbctx $filter)
   (case (sk-prior-folds $type (collapse (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_proof $_tv)))) (
      ((cons (sk-prior-fold $_rule $args) $_more)
         (case (sk-value (sk-fold $args) sk-any-filter ()) (
            ((sk-goal-val (CPU $_fun $_args (STV $s $c)) $_fold-proof $_ev $deps)
               (let* (($prior (population-prior-tv (STV $s $c)))
                      ($fact (data $type $kbctx (brand Proof (population-prior (car-atom (cdr-atom $args)))) $prior)))
                  (if (sk-fact-matches? $filter $fact) (sk-val $fact (ev-set 0) $deps) sk-none)))
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
                     (sk-goal-val (CPU $fun $args $result) (brand Proof cpu) (ev-set 0) 0)
                     (empty)))))))
      ($_fact (map-semidet (sk-root-key-value $goal) (sk-root-keys $goal))))))

(: sk-result-step (-[semidet]-> (List RuntimeResult) SkeletonValue (List RuntimeResult)))
(= (sk-result-step $kept $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (cons (brand RuntimeResult $fact) $kept))
      ((sk-goal-val $goal $_proof $_ev $_deps) (cons (brand RuntimeResult $goal) $kept))
      (sk-none $kept))))

;; Proof-indexed subsumption preserves root order (runtime_helpers.pl).
(: prune_answer_instances (-[det]-> (List RuntimeResult) (List RuntimeResult)))

;; Proven answers in root order without redundant instances; a materializing
;; query writes back the first that is not a population prior. An answer's
;; proof is as its value holds it, references into &proof; only output
;; expands it.
(: sk-publish-results (-[semidet]-> Bool (List SkeletonValue) (List RuntimeResult)))
(= (sk-publish-results $materialize? $values)
   (let* (($_materialized
             (if $materialize?
                (case (collapse (once (let $value (superpose $values)
                         (case $value (
                            (sk-none (empty))
                            ($found (if (sk-population-prior? $found) (empty) $found))))))) (
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
      (sk-raise-score! $hash $goal 1.0)))

(: execute-backward
   (-[nondet]-> Number (List (| Goal (Statement KBContext Proof TV))) Bool (List (List RuntimeResult))))
(= (execute-backward $steps $requested $materialize?)
   (let* (($goals (map-flat context-search-goal $requested))
          ($_seen (remove-data-rows! &sk_seen (quote ($hash $node))))
          ($_fresh (remove-data-rows! &sk_fresh (quote ($fhash $node))))
          ($_parked (sk-park-deliveries!))
          ($_old-roots (remove-data-rows! &sk_roots (quote ($hash $root))))
          ;; What was stored since the last query is activated before the
          ;; walk: facts against the nodes that were there before (so a root
          ;; new to the skeleton still starts from its population prior),
          ;; rules once the roots are registered, since a query's own rules
          ;; build its roots' rows. Their answers are delivered at once, from
          ;; an allowance of their own, ten rows per new fact and per step:
          ;; reading new evidence is the deferred cost of storing it, so it
          ;; neither waits for a walk to come back to it nor takes the rows
          ;; the search needs, and the allowance bounds what new facts set off
          ;; through recursive rules. Deliveries beyond it are made from the
          ;; query's allowance (docs/metta/fact_absorption.md).
          ($started (inference-clock))
          ($_absorbing (change-state! sk_row_budget (* 10 (+ (length (collapse (match &sk_pending_facts $fact $fact))) $steps))))
          ($_facts (sk-activate-facts!))
          ($_scored (fold-semidet sk-root-score-step () $goals))
          ($_rules (sk-activate-rules!))
          ($_thawed (sk-activate-thawed!))
          ($_absorbed (sk-drain!))
          ($_budget (change-state! sk_budget $steps))
          ($_rows (change-state! sk_row_budget (* 10 $steps)))
          ($_evaluation (change-state! sk_eval_budget (* (sk-evaluation-per-step) $steps)))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) $steps)))
          ($_pushes (change-state! sk_push_seq 0))
          ($_context-start (context-start!))
          ($_search (sk-walk! $goals))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_reserve (change-state! sk_near_reserve 0))
          ($_needed (sk-need-roots! (fold-semidet sk-root-keys-step () $goals)))
          ($context-reserve (search-id-value sk_near_reserve))
          ($_evaluated (sk-evaluate!))
          ($_inferred (inference-add! $started))
          ($main-results (sk-answer-roots! $goals $materialize?))
          ($results (context-finish! (* (sk-evaluation-per-step) $steps) $context-reserve $requested $main-results))
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
