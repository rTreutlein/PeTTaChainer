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
(: sk-note-cuts! (-[det]-> (List Number) Atom))
(: sk-excludes? (-[det]-> (List Number) Number Bool))
(: sk-branch-excludes? (-[semidet]-> Number Bool))
(: sk-hold-branch-reader! (-[det]-> Number SkeletonKey Number (List Number) Atom))
(: sk-build-wanted! (-[semidet]-> Bool))
(: sk-branch-ready-step (-[semidet]-> Number (List Number) SkeletonKey Atom SkeletonItem Atom))
(: sk-finish-branches! (-[semidet]-> Number Atom))
(: sk-branch-values (-[semidet]-> Number SkeletonKey Number (List Number) Bool (List SkeletonValue)))
(: sk-reference-view (-[semidet]-> Number SkeletonValue SkeletonValue))
(: sk-cache-branch!
   (-[semidet]-> Number Number SkeletonKey Number (List SkeletonKey) (List Number) Bool SkeletonValue SkeletonValue))
(: sk-stale-reader-step (-[det]-> SkeletonKey Atom SkeletonItem Atom))
(: sk-value (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(: sk-row-view (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue))
(: sk-computed-fold-view (-[semidet]-> Number ScalarFoldSpec SkeletonValue))
(: sk-member-pending? (-[det]-> SkeletonKey Bool))
(: sk-dependent-merge (-[semidet]-> Bool SkeletonValue SkeletonValue SkeletonValue))
(: sk-given-value (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(: sk-given-depth-step (-[det]-> Number SkeletonGiven Number))
(: sk-conditioned
   (-[semidet]-> (List SkeletonGiven) SkeletonTarget Number Number (List Number) (List SkeletonKey) Number
       SkeletonValue SkeletonValue SkeletonValue))

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
;; value's evidence and the keys near it (forgetting.metta). Ordinary fact
;; leaves keep their exact source evidence beside the inline proof: a later
;; signed proof walk must never rebuild a scoped fact from its name alone.
(: sk-leaf-view (-[det]-> Number SkFact SkeletonValue))
(= (sk-leaf-view $hash ($type $scope $proof $tv))
   (let $fact (data $type $scope $proof $tv)
   (case (collapse (once (match &sk_forward_stored ($hash $_key $fact $ev $deps) (sk-val $fact $ev $deps)))) (
      ((cons $stored $_rest) $stored)
      (() (case (collapse (once (match &sk_summary ($hash $_skey $fact $sev $sdeps) (sk-val $fact $sev $sdeps)))) (
             ((cons $summary $_more) $summary)
             (() (let* (($ev (leaf-evidence-for-result $fact))
                         ($scoped (case (evidence-entries $ev) (
                            (((fact-ev $_source-scope $source-proof $_source-type))
                               (assemble-runtime-fact $type $scope
                                  (fact-source $ev $source-proof) $tv))
                            ($_other $fact)))))
                      (sk-val $scoped $ev (sk-leaf-deps $hash $fact)))))))))))

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
         (if (sk-branch-excludes? $deps) $kept (cons $view $kept))
         (if (if $computed (not (sk-summary-fact? $fact)) false) $kept
            (if (sk-excludes? $exclude $deps) $kept (cons $view $kept))))))

(: sk-leaf-views (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonValue)))
(= (sk-leaf-views $hash $key $filter $exclude)
   (let $computed (if (== (sk-latest-versions $hash $key) ()) false true)
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
          ;; Clip the log/variance calculation, not an exact posterior mean.
          ($s (if (== $link odds)
                 (if (or (certain-at? 0.0 $sa $ca) (certain-at? 0.0 $sb $cb)) 0.0
                    (if (or (certain-at? 1.0 $sa $ca) (certain-at? 1.0 $sb $cb)) 1.0
                       (/ 1.0 (+ 1.0 (pow-math 2.718281828459045 (- 0.0 $x))))))
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
      ($_other
         (let $read (population-prior-tv $tv)
            (sk-prior-update $proof (brand Proof (prior $read)) ()))))))

(: instance-prior-tv (-[det]-> Proof TV TV))
(= (instance-prior-tv $proof $tv)
   (case (sk-prior-update-of $proof $tv) (
      ((sk-prior-update $_source (prior $read) ()) (the TV $read))
      ($_updated $tv))))

;; An impossible likelihood rules the target out even if the remaining
;; estimate shares evidence. Keep its confidence; shared evidence buys none.
(: sk-zero-update? (-[det]-> SkFact SkFact Bool))
(= (sk-zero-update? ($_type $_scope $proof $_tv) ($_ot $_os $_op $other-tv))
   (if (proof-zero-likelihood? $proof)
      (case $other-tv (((STV $s $_c) (not (sk-contradict? 0 (the Number $s)))) ($_other false)))
      false))

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

;; Leave-one-out branch centres require actual source support. Unknown or
;; shared support gives the structural neutral centre, never a self-pool.
(: likelihood-centres (-[det]-> CTVType SupportCounts CTVType))
(= (likelihood-centres (CTV $positive $negative) (support-counts $_total $pos $neg $bad $overlap))
   (if (if (> $pos 0) (if (> $neg 0) (if (== $bad 0) (== $overlap 0) false) false) false)
      (CTV $negative $positive) (CTV (STV 0.5 1) (STV 0.5 1))))

;; Registered as truth rows are built, rather than walking all producer rows
;; at every sensor read. Ambiguous producer folds cannot certify independence.
(: RuleFold Type)
(: rule-fold (-[det]-> SkeletonKey RuleFold))
(: no-rule-fold RuleFold)
(: ambiguous-rule-fold RuleFold)
(: sk-rule-fold (-[det]-> KB Proof RuleFold))
(= (sk-rule-fold $kb $rule)
   (case (collapse (once (match rule_name_index ($rule $id)
             (match &sk_rule_truth ($id $truth $_statement ($kb $_ctx $_vars)) $truth)))) (
      ((cons $truth $_rest)
         (case (alpha_unique_keys (collapse (match &ctx_sk_truth_fold ($truth $_fold-hash $fold) $fold))) (
            ((cons $fold ()) (rule-fold $fold))
            (() no-rule-fold)
            ($_many ambiguous-rule-fold))))
      (() no-rule-fold))))

;; Indexed admissibility and subtraction inspect only the excluded sources.
;; Neither operation interns or walks a population-sized evidence set.
(: sk-computed-centre (-[semidet]-> KB Statement SourceList (List Number) OptionalSTV))
(= (sk-computed-centre $kb $pattern $sources $exclude)
   (let* (((cons (CPU FoldAllCompiled $args $_result) ()) (base-rate-premises $kb $pattern $_rate))
          ((cons (fa-subscription $identity $descriptor $_triggers) ())
             (fa-premise-subscriptions (CPU FoldAllCompiled $args $_out)))
          ($id (fa-id $identity))
          ($group (quote (aggregate-support $id))))
      (if (likelihood-support-admissible? $group $sources)
         (let* (($state (fold-flat fa-subtract-step (fa-state $id)
                            (fa-left-out $id (hash-union $exclude (hash-set (observation-keys $sources))))))
                ((forward-aggregate-state $_id $_sum $_mass $members) $state))
            (if (> $members 0)
               (let (STV $g $gc) (fa-result $descriptor $state) (STV $g $gc))
               (empty)))
         (empty))))

;; The watch already applied the row's cuts. Additional observation cuts
;; use the same cached fold evaluator, never a separate raw-tally snapshot.
(: sk-rate-read (-[semidet]-> KB Statement TV RatePlan (List Number) (List Number) TV))
(= (sk-rate-read $kb $pattern $raw (rate-plan $goals $result) $exclude $observations)
   (if (hash-subset? $observations $exclude) $raw
      (if (== $raw no-evidence) no-evidence
         (if (user-base-rate? $kb $pattern) $raw
            (case (fold-semidet
                      (sk-premise-step () () (hash-union $exclude $observations) false false false)
                      (sk-acc () (ev-set 0) () ()) $goals) (
               ((sk-acc $_proofs $_ev $_deps $_parts) (the TV $result))
               ($_missing (STV 0.5 0))))))))

(: LikelihoodContext Type)
(: likelihood-context (-[det]-> (List Number) EvidenceSet LikelihoodContext))
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
                         (let (likelihood-read (CTV $_reconciled $negative)
                                   (CTV $_read-positive $read-negative) $origin)
                               (ImplicationLikelihoodsFormula $atv $btv $itv)
                            (likelihood-read (CTV $itv $negative) (CTV $itv $read-negative) $origin)))
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

;; The observations of the updates a view merges, by hash: an inversion's
;; observation or a completion's consequence, its last witness.
;; Updates through one rule are independent given their prior
;; and the rule, whether its truth is given or an estimate (see
;; sk-merge-facts). A list of proofs is walked by recursion: the determinism
;; checker rejects a fold over Proof, a newtype of Atom.
(: sk-witness-hash (-[det]-> Atom Number))
(= (sk-witness-hash $proof)
   (index-hash (case $proof (((fact-source $_ev $source) $source) ($_other $proof)))))

(: sk-part-witnesses (-[det]-> (List Proof) (List Number)))
(= (sk-part-witnesses ()) ())
(= (sk-part-witnesses (cons $part $rest))
   (let* (($witness (car-atom (cdr-atom (sk-step-proof $part))))
          ($last-first (reverse (case $witness (((cons conjunction $proofs) $proofs) ($_one (cons $witness ()))))))
          ($read (the (List Atom) (cons (car-atom $last-first) ()))))
      (append-flat (map-flat sk-witness-hash $read) (sk-part-witnesses $rest))))

(: sk-sources-meet? (-[det]-> (List Proof) (List Proof) Bool))
(= (sk-sources-meet? $parts-a $parts-b)
   (not (== (/==\ (sk-part-witnesses $parts-a) (sk-part-witnesses $parts-b)) ())))

;; Context evidence is cached by immutable proof reference, including the given
;; siblings of nested completions. Certainty is checked against the live KB
;; below, rather than cached with the proof's structural context.
(: proof-given-evidence (-[det]-> Proof EvidenceSet))

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
      (((sk-prior-update $_prior $_own $_parts) (sk-prior-update $_oprior $_oown $oparts))
         (let $without-siblings
               (evidence-subtraction $ev
                  (evidence-set (fold-flat (evidence-certainty-step true) () (evidence-entries (proof-given-evidence $proof)))))
            (sk-without-given $without-siblings
               (sk-application-premises $type $kbctx $proof)
               (sk-part-witnesses $oparts)))))))

;; The premises a rule application of a complete statement reads directly, by
;; hash.
(: sk-application-premises (-[det]-> Atom Atom Proof (List Number)))
(= (sk-application-premises $type $kbctx $proof)
   (if (complete-statement? $type $kbctx)
      (case (sk-step-proof $proof) (
         ((by $_rule $premise)
            (map-flat sk-witness-hash (the (List Atom) (case $premise (
               ((cons conjunction $names) $names)
               ((settled $part) (cons $part ()))
               ($_one (cons $premise ())))))))
         ($_update ())))
      ()))

;; Evidence less the certain complete premises the other view observes.
(: sk-without-given (-[det]-> EvidenceSet (List Number) (List Number) EvidenceSet))
(= (sk-without-given $ev $premises $observed)
   (if (if (== $premises ()) true (== $observed ())) $ev
      (evidence-subtraction $ev
         (evidence-set (fold-flat (sk-given-entry-step $premises $observed) () (evidence-entries $ev))))))

(: sk-given-entry-step (-[det]-> (List Number) (List Number) (List Evidence) Evidence (List Evidence)))
(= (sk-given-entry-step $premises $observed $kept $entry)
   (case $entry (
      ((fact-ev $kbctx $proof $type)
         (let $hash (index-hash $proof)
            (if (if (stored-list-member? $hash $observed)
                   (if (stored-list-member? $hash $premises) (complete-statement? $type $kbctx) false)
                   false)
               (if (certain-fact-evidence? $entry) (cons $entry $kept) $kept)
               $kept)))
      ($_other $kept))))

;; Exclusion/subtraction may change only floating-point rounding of the
;; same prior. Compare its TV at arithmetic precision so independent updates
;; do not fall through into ordinary revision.
;; Two views updating the same prior with different rules and observations
;; merge by Bayes' rule; over a base rate, which carries no evidence, they
;; must also be independent, sharing no uncertain statement, since an
;; observation may be read below the witnesses the sources compare. A view
;; updating the population base rate (`cpu`) merges the same way into a
;; uncertain view over another prior, or updating nothing, that is independent
;; of it: that view, including a stored target belief, takes the base rate's
;; place as the instance's prior. The update contributes its likelihood ratio,
;; not another estimate to revise with the prior. A certain view stays as it
;; is. Anything else is left to the
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
               (if (if (if (if (>= $ca 1) (>= $cb 1) false)
                              (sk-contradict? (the Number $sa) (the Number $sb)) false) false
                      (if (same-proof? $base-a $base-b)
                         (if (< (abs-math (- (the Number $spa) (the Number $spb))) 0.000000000001) (if (< (abs-math (- (the Number $cpa) (the Number $cpb))) 0.000000000001) (if (== $parts-a ()) false (if (== $parts-b ()) false (if (if $population-a (if $independent false true) false) false (not (sk-sources-meet? $parts-a $parts-b))))) false) false)
                         (if $population-b
                            (if (< $ca 1.0) $independent false)
                            false)))
                  (let* (((STV $combined-s $combined-c)
                              (sk-factored-tv odds (the Number $spa) (the Number $cpa)
                                 (the Number $spb) (the Number $cpb)
                                 (if (== $parts-a ()) (the Number $spa) (the Number $sa)) (the Number $ca)
                                 (if (== $parts-b ()) (the Number $spb) (the Number $sb)) (the Number $cb)))
                         ($zero (if (proof-zero-likelihood? $proof-a) true (proof-zero-likelihood? $proof-b)))
                         ($merged (brand Proof (factored-revision $base-a (prior (STV $spa $cpa))
                                                   (append-flat $parts-a $parts-b))))
                         ($result-proof (if $zero (brand Proof (zero-likelihood $merged)) $merged)))
                     (sk-val ($type $kbctx $result-proof (STV (if $zero 0.0 $combined-s) $combined-c))
                        (evidence-union $ev-a $ev-b) (deps-union $deps-a $deps-b)))
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
          ($views (map-flat sk-version-view (sk-latest-versions $hash $key)))
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

;; After sk-update-evidence removes hard facts read as given, a remaining
;; concludable fact may be the same consequence observation in both updates.
;; Retain that protection even for hard reports: a likelihood counts once.
;; A fact no rule concludes is a premise either reads as given.
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
;; contains the other's is kept only if it also used every given the other
;; used; two that share an uncertain statement are an
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
               (let* (($touch (evidence-overlap? $ev-a $ev-b))
                      ($cmp-a (if $touch (sk-update-evidence $a $ev-a $b) $ev-a))
                      ($cmp-b (if $touch (sk-update-evidence $b $ev-b $a) $ev-b))
                      ($overlap (if $touch (evidence-overlap? $cmp-a $cmp-b) false))
                      ($a-in-b (if $overlap (if (evidence-subset? $cmp-a $cmp-b) (hash-subset? (deps-excluded $ignore $deps-a) (deps-excluded $ignore $deps-b)) false) false))
                      ($b-in-a (if $overlap (if (evidence-subset? $cmp-b $cmp-a) (hash-subset? (deps-excluded $ignore $deps-b) (deps-excluded $ignore $deps-a)) false) false))
                      ($apart (if $overlap (if $a-in-b false (if $b-in-a false true)) false))
                      ($shared (if $apart (sk-shared-statements $ignore (deps-shared $deps-a $deps-b)) ()))
                      ($independent
                         (if $overlap
                            (if $apart (if (== $shared ()) (if (fold-flat sk-observation-step false (evidence-shared-facts $cmp-a $cmp-b)) false true) false) false)
                            true))
                      ($twins
                         (if $independent
                            (if (sk-derivation-proof? $proof-a) (if (sk-derivation-proof? $proof-b) (sk-sample-twins? $va $vb) false) false)
                            false))
                      ($factored (if $twins sk-none
                                    (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b $independent)))
                      ($siblings (if (== $factored sk-none)
                                    (if $combine (if (== $shared ())
                                       (sk-siblings? true $va $vb) false) false)
                                    false)))
                  (if $twins (sk-paired (sk-dependent-merge false $va $vb))
                  (if (not (== $factored sk-none)) (sk-paired $factored)
                     (if $siblings (sk-paired (sk-sibling-merge true $va $vb))
                     (if (if $independent false (sk-zero-update? $a $b)) (sk-paired $va)
                     (if (if $independent false (sk-zero-update? $b $a)) (sk-paired $vb)
                     (if $independent
                        (let* (($pooled (evidence-union $ev-a $ev-b))
                               ($deps (deps-union $deps-a $deps-b))
                               ($combined (if $combine (sk-combined-merge $a $b $pooled $deps) sk-none)))
                           (sk-paired
                              (if (not (== $combined sk-none)) $combined
                                 (if (>= (term-confidence $a) (term-confidence $b))
                                    (sk-val (RevisionMergeProof $a $b) $pooled $deps)
                                    (sk-val (RevisionMergeProof $b $a) $pooled $deps)))))
                        (if (if $a-in-b (if $b-in-a false true) false) (sk-paired $vb)
                           (if (if $b-in-a (if $a-in-b false true) false) (sk-paired $va)
                              (sk-overlap $shared (deps-union $deps-a $deps-b)
                                 (sk-dependent-merge false $va $vb))))))))))))))))))))

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

;; A refined rule's truth with the digest of the instance folds its rows read.
(: sk-truth-digest (-[semidet]-> Number SkeletonDigest))
(= (sk-truth-digest $truth)
   (sk-digest $truth
      (fold-semidet sk-fold-digest-step 0
         (collapse (match &sk_row ($truth $_key $_rhash (sk-row $_ident $_concl $premises $_seq)) $premises)))))

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
               (match &sk_rule_truth ($id $truth $_statement $_truth-ctx) (sk-truth-digest $truth)))))))
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
      (if (deps-has? $deps $truth) (sk-truth-digest $truth) (empty))))))

(: sk-fold-digest-step (-[det]-> Number (List SkPattern) Number))
(= (sk-fold-digest-step $digest $premises) (fold-flat sk-premise-digest-step $digest $premises))

(: sk-premise-digest-step (-[det]-> Number SkPattern Number))
(= (sk-premise-digest-step $digest $premise)
   (case $premise (
      ((CPU FoldAllCompiled $args $_res)
         (if (sk-instance-fold? $args)
            (chainer-first-or $digest
               (collapse (once (match &ctx_sk_instance_digest ((index-hash (sk-fold $args)) $stored) $stored))))
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
;; strength under a prior at the general one (bayes-shrink). Its weight uses
;; the general estimate's confidence and the configured heterogeneity count
;; kappa, so an uncertain general rule supplies little or no pull.
(: sk-specialized (-[det]-> SkFact EvidenceSet Number SkFact EvidenceSet Number SkeletonValue))
(= (sk-specialized ($type $kbctx $proof $tv) $ev $deps ($_gtype $_gkbctx $general $gtv) $gev $gdeps)
   (case (sk-step-proof $proof) (
      ((specializes $original $previous $original-tv $previous-tv)
         (sk-specialized (assemble-runtime-fact $type $kbctx (brand Proof $original) (the TV $original-tv)) $ev $deps
            (assemble-runtime-fact $type $kbctx $general $gtv) $gev $gdeps))
      ($_other
         (case (data $tv $gtv) (
            (((STV $s $c) (STV $gs $gc))
               (sk-val ($type $kbctx (brand Proof (specializes $proof $general $tv $gtv)) (STV (bayes-shrink $s $c $gs $gc) $c))
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
      ((fact-source $source-ev $_source)
         (once (let* (($entries (evidence-entries $source-ev))
                      ((fact-ev $ctx $source $type) (superpose $entries)))
            (match &kb ($type $ctx $source (STV $s $_c))
               (data (implication-side-conjuncts $type) $s true)))))
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
   (case (sk-step-proof $proof) (
      ((by $rule $premise)
         (let* ((($parts $s $complete) (sk-antecedent (brand Proof $premise) $ev))
                ($source (sk-step-proof (brand Proof $rule))))
            (if (if (rule-application-proof? $source) true (head-is? $source merge/revision))
               (let ($parents $parent-s $parent-complete) (sk-application-antecedent (brand Proof $rule) $ev)
                  (data (append-flat $parents $parts) (* $parent-s $s) (if $complete $parent-complete false)))
               (data $parts $s $complete))))
      ;; A pooled implication still depends on its source conditions. When
      ;; all hold positively, its application specializes their shared general
      ;; class too. Mixed branches remain mixtures, never a false conjunction.
      ((merge/revision $left $right)
         (let* ((($left-parts $left-s $left-complete) (sk-application-antecedent (brand Proof $left) $ev))
                (($right-parts $right-s $right-complete) (sk-application-antecedent (brand Proof $right) $ev)))
            (data (list_to_set (append-flat $left-parts $right-parts))
               (if (>= $left-s 1.0) (if (>= $right-s 1.0) 1.0 0.5) 0.5)
               (if $left-complete $right-complete false)))))))

(: sk-class-sources (-[det]-> SkFact EvidenceSet SourceList))
(= (sk-class-sources ($type $ctx $proof $tv) $ev)
   (case (sk-step-proof $proof) (
      ((by $rule $_premise)
         (let $branch (case (collapse (once (sk-application-antecedent $proof $ev))) (
                         ((cons $found $_more)
                            (let ($_parts $s $_complete) (the ((List Atom) Number Bool) $found)
                               (if (>= $s 1) 1 (if (<= $s 0) -1 0))))
                         (() 0)))
            (case (sk-rule-fold (brand KB (car-atom $ctx)) (brand Proof $rule)) (
               ((rule-fold $fold) (likelihood-sources $fold $branch))
               (ambiguous-rule-fold (source-list (unverified-observation)))
               ($_unknown (source-list ()))))))
      ((specializes $original $_general $raw $_centre)
         (sk-class-sources (assemble-runtime-fact $type $ctx (brand Proof $original) (the TV $raw)) $ev))
      ((merge/revision $left $right)
         (source-list-union
            (sk-class-sources (assemble-runtime-fact $type $ctx (brand Proof $left) $tv) $ev)
            (sk-class-sources (assemble-runtime-fact $type $ctx (brand Proof $right) $tv) $ev)))
      ($_other (source-list ())))))

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

;; Only nearest strictly containing classes supply centres. Same-class
;; estimates have already been grouped; incomparable classes are a mixture.
(: sk-class-prior-step (-[semidet]-> SkeletonReference (List SkeletonReference) SkeletonReference (List SkeletonReference)))
(= (sk-class-prior-step $specific $prior $general)
   (if (sk-contained? $specific $general) (cons $general $prior) $prior))

(: sk-nearest-prior-step (-[semidet]-> (List SkeletonReference) SkFact EvidenceSet (List SkeletonValue) SkeletonReference (List SkeletonValue)))
(= (sk-nearest-prior-step $references $specific $specific-ev $kept (sk-reference $class $view))
   (if (fold-semidet (sk-outranked-step (sk-reference $class $view)) false $references)
      $kept
      (case (sk-class-without $specific $specific-ev $view) (
         (sk-none $kept)
         ($independent (cons $independent $kept))))))

(: ClassCentre Type)
(: class-centre (-[det]-> Number Number Number (List Proof) EvidenceSet Number ClassCentre))
(: sk-class-centre-step (-[det]-> EvidenceSet ClassCentre SkeletonValue ClassCentre))
(= (sk-class-centre-step $specific-ev (class-centre $n $sum $second $proofs $ev $deps) $view)
   (case $view (
      ((sk-val ($_type $_ctx $proof (STV $g $c)) $gev $gdeps)
         (if (premise-evidence-overlap? $specific-ev $gev)
            (class-centre $n $sum $second $proofs $ev (deps-union $deps $gdeps))
            (if (<= $c 0.0) (class-centre $n $sum $second $proofs $ev (deps-union $deps $gdeps))
               (class-centre (+ $n 1) (+ $sum $g) (+ $second (+ (ideal-var $g $c) (* $g $g)))
                  (cons $proof $proofs) (evidence-union $ev $gev) (deps-union $deps $gdeps)))))
      ($_none (class-centre $n $sum $second $proofs $ev $deps)))))

(: sk-class-centre (-[semidet]-> SkFact EvidenceSet (List SkeletonValue) SkeletonValue))
(= (sk-class-centre ($type $ctx $_proof $_tv) $specific-ev $views)
   (case $views (
      (() sk-none)
      ((cons $one ())
         (case $one (
            ((sk-val $_fact $ev $_deps) (if (premise-evidence-overlap? $specific-ev $ev) sk-none $one))
            ($_none sk-none))))
      ($_many
         (let* (((class-centre $n $sum $second $proofs $ev $deps)
                   (fold-flat (sk-class-centre-step $specific-ev) (class-centre 0 0 0 () (ev-set 0) 0) $views)))
            (if (<= $n 0) sk-none
               (let* (($g (/ $sum $n))
                      ($variance (max 0.0 (- (/ $second $n) (* $g $g))))
                      ($c (if (<= $variance 0) 1.0
                             (if (>= $variance (* $g (- 1 $g))) 0.0 (ideal-conf-from-var $g $variance)))))
                  (sk-val ($type $ctx (brand Proof (class-mixture (sort-atom $proofs))) (STV $g $c)) $ev $deps))))))))

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

(: sk-reference-values (-[semidet]-> (List Number) (List SkeletonValue) ((List SkeletonValue) Bool (List SkeletonReference))))
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
                           (fold-semidet (sk-sibling-values-step $references) false $references)) $references)))
               ($_few (data $values false ()))))))
      ($_single (data $values false ())))))

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

(= (sk-dependent-merge $product $a $b)
   (if (sk-siblings? false $a $b) (sk-sibling-merge $product $a $b)
      (case (data $a $b) (
         (((sk-val $fact-a $_ea $_da) (sk-val $fact-b $_eb $_db))
            (if (>= (term-confidence $fact-a) (term-confidence $fact-b)) $a $b))
         ($_other $a)))))

;; Deep shared history enters a prior update as fixed marginal inputs, with confidence discounted by the log-odds range between that
;; merge and the conservative representative (#49: c/(1+R^2), R >= 1).
(: sk-unpaid-pair (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-unpaid-pair $va $vb)
   (case (data $va $vb) (
      (((sk-val $a $ev-a $deps-a) (sk-val $b $ev-b $deps-b))
         (let* (($rep (sk-dependent-merge false $va $vb))
                ($factored (sk-factored-merge $a $ev-a $deps-a $b $ev-b $deps-b true)))
            (if (== $factored sk-none) $rep
               (sk-discounted $factored $rep (min (term-confidence $a) (term-confidence $b))))))
      ($_other (sk-dependent-merge false $va $vb)))))

(: sk-discounted (-[semidet]-> SkeletonValue SkeletonValue Number SkeletonValue))
(= (sk-discounted (sk-val ($type $kbctx $proof (STV $s $_c)) $ev $deps) (sk-val ($_rt $_rk $_rp (STV $r $_rc)) $_rev $_rdeps) $cmin)
   (let $range (max 1.0 (abs-math (- (sk-link odds $s) (sk-link odds $r))))
      (sk-val ($type $kbctx $proof (STV $s (/ $cmin (+ 1.0 (* $range $range))))) $ev $deps)))

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
(: sk-component (-[det]-> SkeletonValue Number EvidenceSet (List SkeletonValue) SkeletonComponent))
(: SkeletonConnecting Type)
(: sk-connecting (-[det]-> SkeletonComponent (List SkeletonComponent) SkeletonConnecting))

;; Connectivity needs existence, not a ranked conditioning cut. Stop at the
;; first uncertain shared statement instead of ranking every shared key.
(: sk-shared-statement-step (-[semidet]-> (List Number) Bool Number Bool))
(= (sk-shared-statement-step $ignore $found $hash)
   (if $found true (not (== (sk-shared-hash-step $ignore () $hash) ()))))

(: sk-component-step (-[semidet]-> (List Number) Number EvidenceSet SkeletonConnecting SkeletonComponent SkeletonConnecting))
(= (sk-component-step $ignore $view-deps $view-ev (sk-connecting (sk-component $best $deps $ev $members) $apart) (sk-component $other $other-deps $other-ev $other-members))
   (let* (($uncertain (fold-semidet (sk-shared-statement-step $ignore) false (deps-shared $view-deps $other-deps)))
          ($shared (if $uncertain true (fold-flat sk-observation-step false (evidence-shared-facts $view-ev $other-ev))))
          ($siblings (sk-siblings? true $best $other))
          ($filtered (if $uncertain
             (if $siblings false
                (== (sk-shared-statements $ignore (deps-near-shared (cons $view-deps (cons $other-deps ())))) ()))
             false)))
      (if (if $shared true $siblings)
         (sk-connecting
            (sk-component (if $filtered (sk-unpaid-pair $best $other)
                  (sk-dependent-merge (if $uncertain false
                  (if $siblings (if (sk-sample-twins? $best $other) false true) false)) $best $other))
               (deps-union $deps $other-deps) (evidence-union $ev $other-ev) (append-flat $members $other-members))
            $apart)
         (sk-connecting (sk-component $best $deps $ev $members) (cons (sk-component $other $other-deps $other-ev $other-members) $apart)))))

(: sk-key-merge-step (-[semidet]-> (List Number) (List SkeletonComponent) SkeletonReference (List SkeletonComponent)))
(= (sk-key-merge-step $ignore $components (sk-reference $_class $view))
   (case $view (
      ((sk-val $_fact $ev $deps)
         (let (sk-connecting $connected $apart)
               (fold-semidet (sk-component-step $ignore $deps $ev)
                  (sk-connecting (sk-component $view $deps $ev (cons $view ())) ()) $components)
            (cons $connected $apart)))
      ($_goal $components))))

;; Resolve overlap from the original sibling family, before an intermediate
;; combination can hide its classes. Pair intersections must all be the same
;; positive class; no confidence or condition-size ranking chooses a separator.
(: sk-separators-step (-[det]-> SkeletonReference (List ReferenceClass) SkeletonReference (List ReferenceClass)))
(= (sk-separators-step (sk-reference $a $_va) $found (sk-reference $b $_vb))
   (if (=alpha $a $b) $found
      (let $parts (sort-atom (/==\ (sk-class-parts $a) (sk-class-parts $b)))
         (cons (case (data $a $b) (
                  (((sk-class true $_pa) (sk-class true $_pb)) (sk-class true $parts))
                  ($_other (sk-mixture-class $parts)))) $found))))

(: sk-family-separators-step (-[det]-> (List SkeletonReference) (List ReferenceClass) SkeletonReference (List ReferenceClass)))
(= (sk-family-separators-step $family $found $one)
   (fold-flat (sk-separators-step $one) $found $family))

(: sk-separator-value (-[semidet]-> (List SkeletonReference) ReferenceClass SkeletonValue))
(= (sk-separator-value $references $separator)
   (once (let (sk-reference $class $value) (superpose $references)
      (if (=alpha $class $separator) $value (empty)))))

;; Each distinct syntactic separator contributes one candidate log odds.
;; Negative/mixture branches cannot use its positive TV as a denominator, but
;; it still measures disagreement of the unresolved population approximation.
(: sk-separator-link (-[semidet]-> (List SkeletonReference) ReferenceClass Number))
(= (sk-separator-link $references $separator)
   (let* (($parts (sk-class-parts $separator))
          ((sk-val ($_type $_ctx $_proof (STV $s $_c)) $_ev $_deps)
             (sk-separator-value $references (sk-class true $parts))))
      (sk-link odds $s)))

(: sk-sibling-tv-step (-[semidet]-> STVType STVType SkeletonValue STVType))
(= (sk-sibling-tv-step $prior $acc (sk-val $_fact $_ev $_deps))
   (let ($_type $_ctx $_proof (STV $s $c)) $_fact
      (sk-mode-step odds $prior $acc (STV $s $c))))

;; The envelope includes population, every homogeneous separator correction,
;; and inclusion-exclusion of the known distinct separators. It bounds all
;; choices of m-1 of those separators without enumerating merge trees. A unit
;; log-odds range is the minimum allowance for an unresolved/missing model.
(: sk-separator-range-step (-[det]-> Number (Number Number Number) Number (Number Number Number)))
(= (sk-separator-range-step $count ($sum $low $high) $link)
   (let $correction (* $count $link)
      (data (+ $sum $link) (min $low $correction) (max $high $correction))))

(: sk-overlap-range (-[semidet]-> Number Number (List Number) Number))
(= (sk-overlap-range $count $population $links)
   (let* (($base (* $count $population))
          (($sum $low $high) (the (Number Number Number) (fold-semidet (sk-separator-range-step $count) (data 0.0 $base $base) $links)))
          ($ie (- $sum (* (- (list-len $links) $count) $population))))
      (max 1.0 (- (max $high $ie) (min $low $ie)))))

(: sk-sibling-confidence-step (-[semidet]-> Number SkeletonValue Number))
(= (sk-sibling-confidence-step $confidence (sk-val $fact $_ev $_deps))
   (min $confidence (term-confidence $fact)))

(: sk-overlap-confidence (-[semidet]-> (List SkeletonReference) (List ReferenceClass) KB Statement Number Number Number))
(= (sk-overlap-confidence $references $separators $kb $type $count $confidence)
   (let* ((($_mode (STV $population $_pc)) (sk-combination-mode $kb $type))
          ($classes (list_to_set (map-semidet sk-class-parts $separators)))
          ($links (collapse (let $parts (superpose $classes)
                     (if (== $parts ()) (empty)
                        (sk-separator-link $references (sk-class true $parts))))))
          ($range (sk-overlap-range $count (sk-link odds (the Number $population)) $links)))
      (/ $confidence (+ 1.0 (* $range $range)))))

(: sk-sibling-product (-[semidet]-> SkeletonValue SkeletonValue (List SkeletonValue) SkeletonValue))
(= (sk-sibling-product (sk-val ($_gt $_gctx $_general (STV $gs $gc)) $_gev $gdeps)
                      (sk-val ($type $ctx $proof (STV $s $_c)) $ev $deps) $members)
   (let* (($prior (STV $gs $gc))
          ((STV $strength $confidence) (fold-semidet (sk-sibling-tv-step $prior) $prior $members))
          ((combination odds $_old-prior $proofs) (sk-step-proof $proof)))
      (sk-val ($type $ctx (brand Proof (combination odds (prior $prior) (proof-children $proofs)))
                  (STV $strength
                     (min (fold-semidet sk-sibling-confidence-step 1.0 $members) $confidence)))
         $ev (deps-union $deps $gdeps))))

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

(: sk-family-references (-[semidet]-> SkeletonValue (List SkeletonReference)))
(: sk-family-reference-step (-[semidet]-> SkeletonValue (List SkeletonReference) Proof (List SkeletonReference)))
(= (sk-family-reference-step (sk-val ($type $ctx $_proof $tv) $ev $deps) $family $part)
   (append-flat $family (sk-family-references (sk-val ($type $ctx $part $tv) $ev $deps))))

;; Sample twins are one estimate, but every condition they represent must
;; participate in separator recognition. Their probabilities stay pooled.
(= (sk-family-references $view)
   (case $view (
      ((sk-val ($_type $_ctx $proof $_tv) $_ev $_deps)
         (case (sk-step-proof $proof) (
            ((combination revision $_prior $parts)
               (fold-semidet (sk-family-reference-step $view) () (proof-children $parts)))
            ($_single (cons (sk-reference-of $view) ())))))
      ($_other (cons (sk-reference no-class $view) ())))))

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

(: SkeletonComponentOrder Type)
(: sk-component-order (-[det]-> Number SkeletonValue SkeletonComponentOrder))
(: sk-component-order-of (-[semidet]-> (List SkeletonReference) SkeletonComponent SkeletonComponentOrder))
(= (sk-component-order-of $references (sk-component $best $_deps $_ev $members))
   (let $view (sk-sibling-family $references $best $members)
      (case $view (
         ((sk-val ($_type $_ctx $proof $tv) $_ev2 $_deps2)
            (case (sk-prior-update-of $proof $tv) (
               ((sk-prior-update $_prior $_own ()) (sk-component-order 0 $view))
               ($_update (sk-component-order 1 $view)))))
         ($_goal (empty))))))

(: sk-component-merge-step (-[semidet]-> (List Number) SkeletonValue SkeletonComponentOrder SkeletonValue))
(= (sk-component-merge-step $ignore $acc (sk-component-order $_order $view)) (sk-merge-step true $ignore $acc $view))

(: sk-key-fallback (-[semidet]-> (List Number) (List SkeletonReference) (List SkeletonValue) SkeletonValue))
(= (sk-key-fallback $ignore $references $views)
   ;; Combine independent values before applying the updates they are priors
   ;; for. Canonical ordering also fixes confidence ties and floating-point
   ;; fold order, regardless of the order the original views were visited.
   (fold-semidet (sk-component-merge-step $ignore) sk-none
      (sort-atom (map-semidet (sk-component-order-of $references)
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
      ((fact-ev $_kbctx $fact-proof $_type) (if (== $fact-proof (sk-step-proof $proof)) (cons $entry $found) $found))
      ($_rule $found))))

;; The determinism checker proves a fold over a parameter list.
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

;; Each row keeps its latest view and the views it replaced, in the order
;; they were computed. A consumer takes, per row, the latest view that depends
;; on none of the excluded keys and matches its pattern; an older one stays
;; usable when a newer one came to depend on one of them. An older view whose
;; dependencies include all of a newer one's is admitted only where the newer
;; one is, so storing a view drops those.
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

(: sk-admit-older (-[det]-> SkeletonFilter (List Number) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-admit-older $filter $exclude $kept $view)
   (if (sk-admits? $filter $exclude $view) $view $kept))

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
                              (let* (($_unpaid
                                        (if $build
                                           (let $_counted (query_metric_increment rows-unpaid) (next-search-id sk_branch_unpaid))
                                           (if (== (collapse (once (match &ctx_sk_branch_wanted ($slot $hash $wanted $rhash $exclude)
                                                     (if (=alpha $wanted $key) true (empty))))) ())
                                              (context-add! &sk_branch_wanted ($slot $hash $key $rhash $exclude)) ())))
                                     ($_reader (sk-hold-branch-reader! $slot $key $rhash $exclude)))
                                 (chainer-first-or sk-none (sk-branch-values $slot $key $rhash $exclude false))))))))))))))))

(= (sk-hold-branch-reader! $slot $key $rhash $exclude)
   (let* (($_requested
             (if (== (search-id-value sk_holding) 1)
                (collapse (once (match &sk_reading ($held-hash $held-key $_held-row)
                   (if (sk-needed? $held-hash $held-key)
                      (if (space-row-present? &ctx_sk_branch_hold ($slot $_hash $key $rhash $exclude)) ()
                         (let $hash (index-hash $key)
                            (context-add! &sk_branch_hold ($slot $hash $key $rhash $exclude))))
                      (empty))))) ()))
          ($_held
             (collapse (match &sk_reading ($reader-hash $reader-key $reader-row)
                (match &sk_row ($reader-hash $stored-reader $reader-row (sk-row $ri $rc $rp $rs))
                   (if (=alpha $stored-reader $reader-key)
                      (if (if (== (search-id-value sk_holding) 1) (sk-needed? $reader-hash $reader-key) false)
                         (context-add! &sk_held ($reader-hash $reader-row (sk-branch-hold $slot $key $rhash $exclude)))
                         (sk-mark-stale! (sk-row-item $rs $reader-hash $reader-key $reader-row (sk-row $ri $rc $rp $rs))))
                      (empty)))))))
      ()))

(= (sk-excludes? $exclude $deps)
   (if (deps-meet? $exclude $deps)
      (let $_cut (if (== (search-id-value sk_branch_at) 0) ()
                    (sk-note-cuts! (deps-excluded $exclude $deps)))
         true)
      false))

;; Closed reads may use their own pins and direct observations, but cannot
;; cross the exclusions of the branch being rebuilt around them.
(= (sk-branch-excludes? $deps)
   (let $frame (search-id-value sk_branch_at)
      (if (== $frame 0) false
         (let (cons $exclude $_rest) (collapse (once
                 (match &sk_branch_cuts ($frame $exclude $_cuts) $exclude)))
            (sk-excludes? (the (List Number) $exclude) $deps)))))

(= (sk-note-cuts! $cuts)
   (let $frame (search-id-value sk_branch_at)
      (if (if (== $frame 0) true (== $cuts ())) ()
         (let $_noted (collapse (match &sk_branch_cuts ($frame $exclude $old)
                (let* (($both (hash-union $old $cuts))
                       ($_old (remove-variant-row! &sk_branch_cuts (quote ($frame $exclude $old)))))
                   (add-atom &sk_branch_cuts ($frame $exclude $both)))))
            ()))))

(= (sk-branch-values $slot $key $rhash $exclude $fresh)
   (case (fold-semidet sk-cons-step ()
      (collapse (match &ctx_sk_branch ($slot $stored $rhash $cuts $fresh $view)
         (if (=alpha $stored $key)
            (if (hash-subset? $cuts $exclude)
               (if (sk-excludes? $exclude (sk-view-deps-step 0 $view)) (empty)
                  (if (sk-live-view? $view)
                     (if (if $fresh true (not (== $view sk-none))) (sk-cut-view $cuts $view) (empty)) (empty)))
               (empty)) (empty))))) (
      (() ())
      ((cons (sk-cut-view $used $value) $_rest)
         (let $_cuts (sk-note-cuts! (the (List Number) $used)) (cons $value ()))))))

(= (sk-reference-view $rule $computed)
   (case $computed (
      ((sk-val ($type $kbctx $proof $tv) $ev $vdeps)
         (let* (($ref (sk-store-proof! $rule $proof $ev))
                ($_fact (case $ref (((proof-ref $pid) (add-atom &proof_fact ($pid $type $tv)))))))
            (sk-val (data $type $kbctx $ref $tv) $ev $vdeps)))
      ((sk-goal-val $goal $goal-proof $gev $gdeps)
         (sk-goal-val $goal (sk-store-proof! $rule $goal-proof $gev) $gev $gdeps))
      (sk-none sk-none))))

(= (sk-cache-branch! $slot $hash $key $rhash $inputs $cuts $fresh $view)
   (let* (($deps (sk-view-deps-step 0 $view))
          ($_dominated (if $fresh
             (collapse (match &ctx_sk_branch ($slot $stored $rhash $old-cuts $old-fresh $old)
                (if (=alpha $stored $key)
                   (if (if (hash-subset? $cuts $old-cuts) (deps-within? $deps (sk-view-deps-step 0 $old)) false)
                      (remove-variant-row! &sk_branch (quote ($slot $stored $rhash $old-cuts $old-fresh $old))) (empty))
                   (empty)))) ()))
          ($_owner
             (if (not (== (collapse (once (match &ctx_sk_branch_owner ($slot $hash $stored-owner $rhash $_inputs)
                              (if (=alpha $stored-owner $key) true (empty))))) ()))
                (if (space-row-present? &ctx_sk_branch_dirty ($slot))
                   (fold-semidet (sk-branch-link! $slot) () $inputs) ())
                (let* (($_registered (context-add! &sk_branch_owner ($slot $hash $key $rhash $inputs)))
                       ($_readers (fold-semidet (sk-branch-link! $slot) () $inputs))) ())))
          ($_clean (context-remove! &sk_branch_dirty ($slot)))
          ($_stored (context-add! &sk_branch ($slot $key $rhash $cuts $fresh $view)))
          ($kept (collapse (match &ctx_sk_branch ($slot $kept-key $rhash $kept-cuts $kept-fresh $kept-view)
                    (if (=alpha $kept-key $key) ($kept-key $kept-cuts $kept-fresh $kept-view) (empty)))))
          ($_bounded
             (collapse (let (cons ($oldest-key $oldest-cuts $oldest-fresh $oldest-view) $_rest)
                              (if (> (length $kept) 8) $kept (empty))
                (remove-variant-row! &sk_branch (quote ($slot $oldest-key $rhash $oldest-cuts $oldest-fresh $oldest-view)))))))
      $view))

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

;; A population tally is shared; exclusions subtract indexed contributions
;; for this read only, without mutating its authoritative aggregate or cache.
(: sk-rate-left-out (-[det]-> $spec (List Number) (List ForwardAggregateObservation)))
(= (sk-rate-left-out $args $exclude)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kb $pattern $_mode)
         (if (user-base-rate? $kb $pattern) ()
            (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)) (
               ((cons (fa-subscription $identity $_descriptor $_triggers) ())
                  (fold-flat append-flat () (collapse (let $id (fa-id $identity) (fa-left-out $id $exclude)))))
               ($_none ())))))
      ($_other ()))))

(: sk-rate-without (-[semidet]-> Number $spec (List Number) SkeletonValue))
(= (sk-rate-without $hash $args $exclude)
   (let $left (sk-rate-left-out $args $exclude)
      (if (== $left ()) sk-none
         (let* (((cons (fa-subscription $identity $descriptor $_triggers) ())
                   (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)))
                ($id (fa-id $identity))
                ($state (fold-flat fa-subtract-step (fa-state $id) $left))
                ($tv (fa-result $descriptor $state)))
            (sk-goal-val (CPU FoldAllCompiled $args $tv) (brand Proof cpu) (ev-set 0) (deps-key $hash))))))

;; Whether a row reads an instance fold that leaves out a member for the
;; excluded keys.
(: sk-leaves-out-step (-[det]-> (List Number) Bool SkPattern Bool))
(= (sk-leaves-out-step $exclude $found $premise)
   (if $found true
      (case $premise (
         ((CPU FoldAllCompiled $args $_res)
            (if (sk-instance-fold? $args) (not (== (sk-left-out (index-hash (sk-fold $args)) $exclude) ())) false))
         ($_other false)))))

(: sk-row-leaves-out-step (-[det]-> (List Number) Bool (List SkPattern) Bool))
(= (sk-row-leaves-out-step $exclude $found $premises)
   (if $found true (fold-flat (sk-leaves-out-step $exclude) false $premises)))

(: sk-rule-truth-key? (-[det]-> SkeletonKey Bool))
(= (sk-rule-truth-key? $key)
   (case $key (
      ((sk-key $type $_kbctx) (head-is? $type RuleTruth))
      ($_fold false))))

;; Whether a consumer excluding these keys reads the key with a sample left
;; out: an instance fold, or a refined rule's truth, which reads one.
(: sk-leaves-out? (-[det]-> Number SkeletonKey (List Number) Bool))
(= (sk-leaves-out? $hash $key $exclude)
   (if (== $exclude ()) false
      (case $key (
         ((sk-fold $args) (if (sk-instance-fold? $args) (not (== (sk-left-out $hash $exclude) ()))
                            (not (== (sk-rate-left-out $args $exclude) ()))))
         ($_statement
            (if (sk-rule-truth-key? $key)
               (fold-flat (sk-row-leaves-out-step $exclude) false
                  (collapse (match &sk_row ($hash $stored $_rhash (sk-row $_ident $_concl $premises $_seq))
                     (if (=alpha $stored $key) $premises (empty)))))
               false))))))

;; A tally less a sample, as if it had no value.
(: sk-leave-out-step (-[det]-> Number InstanceRegimeState InstanceSample InstanceRegimeState))
(= (sk-leave-out-step $hash (instance-regimes $hazard $next $pos $neg) (instance-sample $pos-seg $neg-seg (InstanceEvidence $old-pos $old-neg)))
   (let* ((($pos-segs $_pos-at) (regime-take! $hash $hazard 0 $pos $pos-seg $old-pos (BaseRateEvidence 0.0 0.0)))
          (($neg-segs $_neg-at) (regime-take! $hash $hazard 0 $neg $neg-seg $old-neg (BaseRateEvidence 0.0 0.0))))
      (instance-regimes $hazard $next (the (List RegimeSegment) $pos-segs) (the (List RegimeSegment) $neg-segs))))

;; The determinism checker proves a fold over a parameter list.
(: sk-tally-without (-[det]-> Number InstanceRegimeState (List InstanceSample) InstanceRegimeState))
(= (sk-tally-without $hash $tally $left) (fold-flat (sk-leave-out-step $hash) $tally $left))

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

(: sk-older-views (-[det]-> Number SkeletonKey Number (List SkeletonValue)))
(= (sk-older-views $hash $key $rhash)
   (collapse (match &ctx_sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))

;; The latest versions of a key's rows, in row creation order.
(: sk-latest-versions (-[det]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-latest-versions $hash $key)
   (sort-atom
      (collapse (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
         (if (=alpha $stored $key) (if (sk-live-view? $view) (sk-version $seq $rhash $view) (empty)) (empty))))))

(: sk-latest-view (-[det]-> Number SkeletonKey Number SkeletonValue))
(= (sk-latest-view $hash $key $rhash)
   (chainer-first-or sk-none
      (collapse (once (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
         (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))))

;; A stored view's proof moves to &proof under a fresh id and the view keeps a
;; reference to it, so a view stays the size of one rule application however
;; deep its derivation is. What the evidence of a proof needs from its whole
;; tree, its computed evidence and whether it negates anything, is stored with
;; it. Rewalking the printed proof loses rule evidence and fact identities.
(: sk-store-proof! (-[semidet]-> Number Proof EvidenceSet Proof))
(= (sk-store-proof! $rule $proof $ev)
   (let* (($pid (next-search-id proof_id))
          ($owner (record-view-rule! $pid $rule $proof))
          ($flags (+ (* 2 $owner) (if (proof-term-contains-negated? $proof) 1 0)))
          ($_row (add-atom &proof ($pid $proof $ev $flags))))
      (proof-ref $pid)))

;; A new view becomes the row's latest; the one it replaces is kept.
(: sk-store-view! (-[semidet]-> Number SkeletonKey Number Number SkeletonValue SkeletonValue))
(= (sk-store-view! $hash $key $seq $rhash $view)
   (let* (($deps (sk-view-deps-step 0 $view))
          ($previous
             (collapse (match &ctx_sk_latest ($hash $stored (sk-version $old-seq $rhash $old))
                (if (=alpha $stored $key)
                   (let* (($_invalidated (if (sk-same-view? $view (if (sk-live-view? $old) $old sk-none)) ()
                                            (sk-invalidate-branches! $key)))
                          ($_removed (context-remove! &sk_latest ($hash $stored (sk-version $old-seq $rhash $old)))))
                      (if (sk-dominated? $deps $old) () (context-add! &sk_view ($hash $stored $rhash $old))))
                   (empty)))))
          ($_first (if (== $previous ()) (sk-invalidate-branches! $key) ()))
          ($_pruned
             (collapse (match &ctx_sk_view ($hash $stored $rhash $older)
                (if (=alpha $stored $key)
                   (if (sk-dominated? $deps $older) (remove-variant-row! &sk_view (quote ($hash $stored $rhash $older))) (empty))
                   (empty)))))
          ($support (deps-union (sk-row-support $hash $rhash) $deps))
          ($_old-support (remove-data-rows! &sk_support (quote ($hash $rhash $_had))))
          ($_support (context-add! &sk_support ($hash $rhash $support)))
          ($_added (context-add! &sk_latest ($hash $key (sk-version $seq $rhash $view)))))
      $view))

(: sk-dominated? (-[semidet]-> Number SkeletonValue Bool))
(= (sk-dominated? $deps $older) (deps-mask-within? $deps (sk-view-deps-step 0 $older)))

(: sk-row-support (-[det]-> Number Number Number))
(= (sk-row-support $hash $rhash)
   (chainer-first-or 0 (collapse (once (match &ctx_sk_support ($hash $rhash $deps) $deps)))))

;; A population prior, `(population-prior pattern)` (sk-start-prior!), is the
;; population's value, not the statement's: a key reads it only while nothing
;; else gives it a value.
(: sk-population-prior? (-[det]-> SkeletonValue Bool))
(= (sk-population-prior? $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (let $step (sk-fact-step-proof $fact) (head-is? $step population-prior)))
      ($_other false))))

(: sk-own-value-step (-[det]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-own-value-step $kept $value) (if (sk-population-prior? $value) $kept (cons $value $kept)))

;; Zero-confidence STVs are unknown placeholders, not competing estimates.
;; Retain them only when nothing informative exists, so judgment scaffolds can
;; still read an unsupported branch. A CTV may have one informative branch.
(: sk-informed-step (-[det]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-informed-step $kept $value)
   (case $value (
      ((sk-val ($_type $_ctx $_proof (STV $_s $c)) $_ev $_deps)
         (if (> $c 0.0) (cons $value $kept) $kept))
      ($_other (cons $value $kept)))))

(: sk-own-values (-[semidet]-> (List SkeletonValue) (List SkeletonValue)))
(= (sk-own-values $values)
   (let* (($own (case (fold-semidet sk-own-value-step () $values) (
                   (() $values)
                   ($found (fold-semidet sk-cons-step () $found)))))
          ($informed (fold-flat sk-informed-step () $own)))
      (if (== $informed ()) $own (fold-semidet sk-cons-step () $informed))))

(: sk-premise-value (-[semidet]-> Bool SkeletonValue SkeletonValue))
(= (sk-premise-value $priors $value) (if $priors $value (if (sk-population-prior? $value) sk-none $value)))

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
                     (if $floor $tv
                        (if (== $proofs ()) (STV $s $c) (OrFormula $tv (STV $s $c))))
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
            (if (stored-list-member? $finish (uniform-prior uniform-prior-known)) (ev-set 0)
               (case $args (
                  (($_kb $_pattern (extract-with-truth $_p $_t $_v) $_init $_fn $_fin $_mode) (ev-set 0))
                  ($_other (evidence-join $ev))))))
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
                   (if (== (collapse (once (match &ctx_sk_rate_folds ($cache-hash $stored)
                              (if (=alpha $stored $key) true (empty))))) ())
                      (context-add! &sk_rate_folds ($cache-hash $key))
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
   (chainer-first-or 0.0001 (collapse (once (match &rule_change_hazard ($kb $hazard) $hazard)))))

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
          ($_digest (sk-instance-digest! $hash $mhash $fold $member $value $new)))
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
(: sk-instance-digest! (-[det]-> Number Number SkeletonKey SkeletonKey SkeletonValue InstanceEvidenceState Atom))
(= (sk-instance-digest! $hash $mhash $fold $member $value (InstanceEvidence (BaseRateEvidence $_pw $pm) (BaseRateEvidence $_nw $nm)))
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $_b $_atv $_btv) $kbctx)
         (let* (($sample-evidence
                  (case $value (
                     ((sk-val $_fact $ev $_deps)
                        (let $kept
                              (evidence-subtraction $ev
                                 (evidence-set (foldr-flat (sk-antecedent-fact-entries $kbctx) () (implication-side-conjuncts (the Statement $a)))))
                           (evidence-set (evidence-shared-facts $kept $kept))))
                     ($_none (ev-set 0)))))
                ($observed (fold-flat sk-entry-hash-step 0 (evidence-entries $sample-evidence)))
                ($_support (update-likelihood-support! $fold $member (observation-sources $sample-evidence)
                              (if (> $pm 0) 1 0) (if (> $nm 0) 1 0)))
                ($mass (+ $pm $nm))
                ($sig (if (> $mass 0.0) (index-hash (sk-sample-sig $observed (round-math (* 1000000 (/ $pm $mass))))) 0))
                ($was (chainer-first-or 0 (collapse (once (match &ctx_sk_instance_digest ($hash $stored) $stored)))))
                ($taken (chainer-first-or 0 (collapse (once (match &ctx_sk_instance_sig ($mhash $hash $stored-sig) $stored-sig)))))
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

;; The members of a tally fold that joined or changed since it last took them.
(: sk-rate-changed (-[det]-> Number SkeletonKey (List SkeletonKey)))
(= (sk-rate-changed $hash $fold)
   (collapse (match &ctx_sk_rate_dirty ($hash $_mhash $stored $member) (if (=alpha $stored $fold) $member (empty)))))

;; Takes the members of an instance fold that joined or changed since it last
;; took them, each at its current value: every take costs the members that
;; changed, never the instances.
(: sk-instance-take! (-[semidet]-> Number ScalarFoldSpec Atom))
(= (sk-instance-take! $hash $args)
   (let* (($fold (sk-fold $args))
          ($changed (sk-rate-changed $hash $fold)))
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
          ($_reading (add-atom &sk_reading ($hash $fold 0)))
          ($value (sk-premise-value false (sk-value $member sk-any-filter (cons $hash ()))))
          ($_read (remove-variant-row! &sk_reading (quote ($hash $fold 0)))))
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

;; --- Coverage of exact folds (docs/metta/partial_folds.md) -------------------

;; A member without a value is still to come while one of its key's rows is
;; stale, was never computed, or waits for conditioning; once every row is
;; computed and current and none derives anything, it is no member.
(: sk-row-current? (-[det]-> Number Number Bool))
(= (sk-row-current? $khash $rhash)
   (if (space-row-present? &ctx_sk_stale ($khash $rhash)) false
      (if (space-row-present? &ctx_sk_given_pending ($khash $rhash $_cost)) false
         (space-row-present? &ctx_sk_support ($khash $rhash $_deps)))))

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
   (case (let $hash (index-hash $key)
            (collapse (once (match &sk_group_of ($hash $stored $group-node) (if (=alpha $stored $key) $group-node (empty)))))) (
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
   (cons (sk-version 0 0 (sk-store-view! $hash $key 0 0 (sk-reference-view -1 $view))) ()))

;; The versions a consumer takes: per row, the latest one it admits.
(: sk-admitted-versions (-[semidet]-> Number SkeletonKey SkeletonFilter (List Number) (List SkeletonVersion)))
(= (sk-admitted-versions $hash $key $filter $exclude)
   (let* (($stored (sk-latest-versions $hash $key))
          ($versions (case $key (
             ((sk-key $_type $_kbctx) $stored)
             ($_fold (case $stored (
                ((cons (sk-version $_seq $_rhash $view) $_rest)
                   $stored)
                (() (sk-fold-views $hash $key)))))))))
      (fold-semidet sk-cons-step () (fold-semidet (sk-admit-step $hash $key $filter $exclude) () $versions))))

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
                            (if (head-is? $assumed JudgmentPrior)
                               (let $prior-type (car-atom (cdr-atom $assumed))
                                  (superpose (
                                     (index-hash (sk-key $assumed ($kbid $ctx $assumed-vars)))
                                     (index-hash (sk-key $prior-type ($kbid $ctx $assumed-vars))))))
                               (index-hash (sk-key $assumed ($kbid $ctx $assumed-vars))))))))
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
          ($unifiers (sk-unifier-hashes $hash $key))
          ($ignore (hash-union $unifiers $outside))
          (($values $siblings $references) (sk-reference-values $ignore $standing)))
      (case (sk-lift $siblings $values) (
         ((cons $lifted $_rest) $lifted)
         (()
            (case (fold-semidet (sk-pair-merge-step true $ignore) (sk-merging sk-none () 0) $values) (
               ;; Every fact view depends on its own key. A nonempty
               ;; overlap dependency set also marks an unconditionable
               ;; overlap (shared observations, with no cut statements).
               ((sk-merging $merged () $deps)
                  (if (if (== $deps 0) (if $siblings false true) false) $merged (sk-key-fallback $ignore $references $values)))
               ((sk-merging $_provisional $keys $deps)
                  (let* (($merged (sk-key-fallback $ignore $references $values))
                         ($near (sk-shared-statements $ignore (deps-near-shared (map-semidet (sk-view-deps-step 0) $values))))
                         ($cut (fold-semidet (sk-near-key-step $near) () $keys)))
                     (if (== $cut ()) $merged
                        (sk-conditioned $given (sk-key-target $hash $key $filter $exclude) $hash -1
                           (hash-union $exclude $unifiers) $cut (+ 1 (deps-size $deps)) $merged $merged)))))))))))

;; Preserve the cut candidate order when restricting it to near statements.
(: sk-near-key-step (-[det]-> (List SkeletonKey) (List SkeletonKey) SkeletonKey (List SkeletonKey)))
(= (sk-near-key-step $near $kept $k) (if (stored-list-member? $k $near) (append-flat $kept (cons $k ())) $kept))

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
   (case (collapse (once (match &ctx_sk_merged ($hash $stored $deps $value)
            (if (=alpha $stored $key) (if (sk-live-view? $value) (sk-merged $hash $stored $deps $value) (empty)) (empty))))) (
      ((cons $merged $_rest) (let $_counted (query_metric_increment merged-cache-hits) $merged))
      (() (context-cold-merged $hash $key $filter)))))

;; The owner of a cold merge controls all maintenance performed by the read.
;; Independent reads in C execute this operation in MAIN; dependent reads keep
;; the overlay active, including conditioning and aggregate maintenance.
(: sk-merge-open! (-[semidet]-> Number SkeletonKey SkeletonFilter SkeletonMerged))
(= (sk-merge-open! $hash $key $filter)
   (let* (($_counted (query_metric_increment merged-cache-misses))
          ($views (sk-admitted $hash $key $filter ()))
          ($leaves (sk-leaf-views $hash $key $filter ()))
          ($deps (fold-semidet sk-view-deps-step 0 (append-flat $leaves $views)))
          ($value (sk-merge-key $hash $key $filter () () $views))
          ($_inner (sk-uncache! $hash $key))
          ($_cached (context-add! &sk_merged ($hash $key $deps $value)))
          ($_factor (sk-note-truth-factor! $hash $key $value)))
      (sk-merged $hash $key $deps $value)))

;; A rule truth's new value rescores the rules that read it.
(: sk-note-truth-factor! (-[det]-> Number SkeletonKey SkeletonValue Atom))
(= (sk-note-truth-factor! $hash $key $value)
   (if (sk-rule-truth-key? $key)
      (case $value (
         ((sk-val ($_type $_kbctx $_proof $tv) $_ev $_deps) (sk-set-truth-factor! $hash (rule-truth-factor $tv)))
         ($_none ())))
      ()))

;; The merged value of a key on behalf of a consumer. A proof or truth-value
;; pattern takes the whole merged value when it admits it, and otherwise the
;; merge of the views it admits. A consumer that leaves one of its own samples
;; out of an instance fold reads the views it admits, never the cached value.
(= (sk-value $key $filter $exclude)
   (let $derived (case $filter (
           ((sk-filter $proof $_tv) (head-is? $proof derived-implication))
           ($_any false)))
      (if $derived
         (let $hash (index-hash $key)
            (sk-merge-key $hash $key $filter $exclude () (sk-admitted $hash $key $filter $exclude)))
         (let* (($hash (index-hash $key))
                ($merged
                   (if (sk-leaves-out? $hash $key $exclude)
                      (sk-merge-key $hash $key sk-any-filter $exclude () (sk-admitted $hash $key sk-any-filter $exclude))
                      (case (sk-open-value $hash $key sk-any-filter) (
                         ((sk-merged $_hash $_key $deps $value)
                            (if (sk-excludes? $exclude $deps)
                               (sk-merge-key $hash $key sk-any-filter $exclude () (sk-admitted $hash $key sk-any-filter $exclude))
                               $value)))))))
            (if (sk-open-filter? $filter) $merged
               (if (sk-admits? $filter () $merged) $merged
                  (sk-merge-key $hash $key $filter $exclude () (sk-admitted $hash $key $filter $exclude))))))))

(: sk-drop-merged! (-[det]-> SkeletonKey Atom))
(= (sk-drop-merged! $key)
   (let* (($hash (index-hash $key))
          ($_unpaid (remove-data-rows! &sk_given_pending (quote ($hash -1 $_cost)))))
      (sk-uncache! $hash $key)))

;; A merge conditioning a key may read the key again through a shared
;; statement's value, which caches the key's fallback first; the conditioned
;; value replaces it.
(: sk-uncache! (-[det]-> Number SkeletonKey Atom))
(= (sk-uncache! $hash $key)
   (let $_dropped
         (collapse (match &ctx_sk_merged ($hash $stored $deps $value)
            (if (=alpha $stored $key)
               (context-remove! &sk_merged ($hash $stored $deps $value))
               (empty))))
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
            (sk-acc (cons $proof $fold-proofs) (evidence-union $ev $fold-ev) (cons $fold-deps $deps) $parts)
            sk-fail))
      ($_none sk-fail))))

;; --- Conjunction pooling ----------------------------------------------------

;; Projections of one stored (And ...) source are not independent: they share
;; the source's evidence. A conjunction pools them back into the source, whose
;; truth value it takes once every member is projected, and the first
;; projection's marginal truth value before.
(: sk-proof-source (-[det]-> KBContext Proof (List SkeletonSource)))
(= (sk-proof-source $scope $base)
   (case $base (
      ((fact-source $source-ev $_source-proof)
         (collapse (once (let* (($entries (evidence-entries $source-ev))
                               ((fact-ev $source-scope $source $source-type) (superpose $entries)))
            (match &kb ($source-type $source-scope $source $source-tv) (sk-source $source-type $source-tv))))))
      ((proof-ref $pid) (collapse (once (match &proof_fact ($pid $statement $tv) (sk-source $statement $tv)))))
      ($_leaf (collapse (once (match &kb ($statement $scope $base $tv) (sk-source $statement $tv))))))))

(: sk-premise-part (-[det]-> SkFact SkeletonPart))
(= (sk-premise-part ($_type $kbctx $proof $tv))
   (case (sk-step-proof $proof) (
      ((marginal-proj $idx $base)
         (case (sk-proof-source $kbctx (brand Proof $base)) (
            ((cons (sk-source $statement $source-tv) $_rest)
               (if (head-is? $statement And)
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
               (same-proof? $base $other-base))
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
               (if (same-proof? $base $part-base)
                  (cons (sk-pool-part $base $tv $arity (list_to_set (append-flat $idxs $new-idxs)) $marginal) $rest)
                  (cons $head (sk-add-part $rest $part))))
            ($_indep-part (cons $head (sk-add-part $rest $part))))))
      ($_indep-head (cons $head (sk-add-part $rest $part))))))

;; Keep parts in read order until their source computations have run. In
;; particular, NotFormula transforms the last read before conjunction pooling.
(: sk-pool-parts (-[det]-> (List SkeletonPart) (List SkeletonPart)))
(= (sk-pool-parts $parts)
   (let $ordered (reverse $parts)
      (fold-flat sk-add-part () (the (List SkeletonPart) $ordered))))

(: sk-pooled? (-[det]-> (List SkeletonPart) Bool))
(= (sk-pooled? $parts) (sk-has-pool? (sk-pool-parts $parts)))

(: sk-has-pool? (-[det]-> (List SkeletonPart) Bool))
(= (sk-has-pool? ()) false)
(= (sk-has-pool? (cons $head $rest))
   (case $head (
      ((sk-pool-part $_base $_tv $_arity $idxs $_marginal)
         (if (> (list-len $idxs) 1) true (sk-has-pool? $rest)))
      ($_indep (sk-has-pool? $rest)))))

(: sk-part-tv (-[det]-> SkeletonPart TV))
(= (sk-part-tv $part)
   (case $part (
      ((sk-indep-part $tv) $tv)
      ((sk-pool-part $_base $tv $arity $idxs $marginal)
         (if (== (list-len $idxs) $arity) $tv $marginal)))))

(: sk-parts-tv-step (-[semidet]-> TV SkeletonPart TV))
(= (sk-parts-tv-step $acc $part) (AndFormula $acc (sk-part-tv $part)))

(: sk-parts-tv (-[semidet]-> (List SkeletonPart) TV))
(= (sk-parts-tv $parts)
   (let (cons $first $rest) (sk-pool-parts $parts)
      (fold-semidet sk-parts-tv-step (sk-part-tv $first) $rest)))

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
;; it had none in MAIN; row hash -2 prevents re-entry through those rows.
(= (sk-given-value $given $key $filter $exclude)
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
                     (if (if (not (head-is-member? $type (And Or Implication))) true (space-row-present? &ctx_sk_conditioning ($hash -2))) sk-none
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

(: sk-reads-given-step (-[det]-> (List Number) Bool SkPattern Bool))
(= (sk-reads-given-step $hashes $found $premise)
   (if $found true
      (case $premise (
         ((CPU $_fun $_args $_res) false)
         (($type $kbctx $_proof $_tv) (stored-list-member? (index-hash (sk-key $type $kbctx)) $hashes))
         ($_other false)))))

;; Actual pins can make a latest MAIN view admissible; apply exclusions only
;; after rebuilding it. Closed unfounded reads are not cutset branches.
(: sk-admission-exclusions (-[det]-> (List SkeletonGiven) (List Number) (List Number)))
(= (sk-admission-exclusions $given $exclude)
   (if (if (>= (search-id-value sk_claim_state) 0) (> (fold-flat sk-given-depth-step 0 $given) 0) false) () $exclude))

(: sk-given-merge (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) SkeletonValue))
(= (sk-given-merge $given $key $filter $exclude)
   (let $hash (index-hash $key)
      (sk-merge-key $hash $key $filter $exclude $given
         (map-semidet (sk-given-view $given $exclude $hash $key)
            (sk-admitted-versions $hash $key $filter (sk-admission-exclusions $given $exclude))))))

;; A premise value whose evidence overlaps what the row already uses is
;; replaced by the merge of the key's leaves and views that do not overlap it:
;; the consumer selects the proofs compatible with its other premises.
(: sk-compatible-step (-[semidet]-> EvidenceSet (List SkeletonPart) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-compatible-step $ev $parts $acc $view)
   (case $view (
      ((sk-val $fact $view-ev $_deps)
         (if (if (premise-evidence-overlap? $ev $view-ev)
                 (not (sk-joins-pool? $parts (sk-premise-part $fact))) false)
            $acc (cons $view $acc)))
      ($_other $acc))))

(: sk-compatible-value
   (-[semidet]-> (List SkeletonGiven) SkeletonKey SkeletonFilter (List Number) EvidenceSet (List SkeletonPart) Bool SkeletonValue))
(= (sk-compatible-value $given $key $filter $exclude $ev $parts $views)
   (let* (($hash (index-hash $key))
          ($outside (hash-union $exclude (hash-set (sk-given-hashes $given))))
          ($leaves (sk-leaf-views $hash $key $filter $outside))
          ($ignore (hash-union (sk-unifier-hashes $hash $key) $outside))
          ($compatible
             (fold-semidet sk-cons-step ()
                (fold-semidet (sk-compatible-step $ev $parts) ()
                (sk-own-values
                   (sk-judgment-values $key
                      (if $views
                         (append-flat $leaves
                            (map-semidet (sk-given-view $given $exclude $hash $key)
                               (sk-admitted-versions $hash $key $filter (sk-admission-exclusions $given $exclude))))
                         $leaves))))))
          (($selected $siblings $references) (sk-reference-values $ignore $compatible)))
      (if $siblings (sk-key-fallback $ignore $references $selected)
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
               (if (if (head-is? $proof derived-implication)
                      (let (derived-implication $value-proof) $proof
                         (= ($type $kbctx $value-proof $tv) $fact))
                      (= ($type $kbctx $proof $tv) (if (is-var $proof) $fact (sk-full-fact $fact))))
                  (sk-acc $fold-proofs (evidence-union $ev $premise-ev)
                     (cons
                        (if (head-is? $type RuleTruth)
                           (deps-key (index-hash (sk-key $type $kbctx)))
                           $premise-deps)
                        $deps)
                     (cons $part $parts))
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
      ((not-fact-ev $nkbctx $nproof $ntype)
         (sk-shared-key-step $given $keys (fact-ev $nkbctx $nproof $ntype)))
      ($_other $keys))))

;; Whether a fact is a projection of a stored or derived conjunction.
(: sk-projection? (-[det]-> SkFact Bool))
(= (sk-projection? $fact)
   (let $step (sk-fact-step-proof $fact)
      (if (head-is? $step marginal-proj) true
         (if (is-expr $step) (let $head (car-atom $step) (head-is? $head proj)) false))))

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
                     (($shared-facts (fold-flat (evidence-certainty-step false) () (evidence-shared-facts $ev $value-ev)))
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
               (if (if (sk-branch-excludes? (deps-key $hash)) false (sk-settled? $key))
                  (if (sk-founded? $hash $key)
                     (if (== $pin ()) sk-none
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
   (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool Bool SkeletonRowState SkPattern
       SkeletonRowState))
(= (sk-premise-step $pin $given $exclude $shared $priors $facts-first $state $premise)
   (case $state (
      (sk-fail sk-fail)
      ((sk-clash $clash-keys $clash-base) (sk-clash $clash-keys $clash-base))
      ((sk-acc $fold-proofs $ev $deps $parts)
         (case $premise (
            ;; This context primitive binds the row's cuts before a likelihood
            ;; is resolved; expected-TV scoring leaves the open read optimistic.
            ((CPU ReadLikelihoodContext () $res)
               (if (= $res (likelihood-context $exclude $ev)) $state sk-fail))
            ((CPU ContextRule ($assumption $ctx) $_res)
               (if (context-rule-enabled? $ctx)
                  (sk-acc $fold-proofs $ev (cons (deps-key (index-hash $assumption)) $deps) $parts)
                  sk-fail))
            ((CPU ReadRate ($kb $pattern $raw (rate-plan $goals $rate) $prior) $result)
               (let $observations (hash-set (observation-keys (observation-sources $ev)))
                  (case (collapse (once (sk-rate-read (brand KB $kb) (brand Statement $pattern) (the TV $raw)
                           (rate-plan (the (List Goal) $goals) $rate) $exclude $observations))) (
                     ((cons $admissible ())
                        (case (collapse (once (if (the Bool $prior)
                                  (configured-population-prior-tv (brand KB $kb) (brand Statement $pattern) (the TV $admissible))
                                  (the TV $admissible)))) (
                           ((cons $read ()) (if (= $result (rate-read (the TV $admissible) (the TV $read))) $state sk-fail))
                           (() sk-fail))))
                     (() sk-fail)))))
            ((CPU FoldAllCompiled $fold-args $fold-res)
               (sk-consume-fold $state $fold-res (sk-value (sk-fold $fold-args) sk-any-filter $exclude)))
            ((CPU GroupedFoldAllCompiled $group-args $group-res)
               (sk-consume-fold $state $group-res (sk-value (sk-group $group-args) sk-any-filter $exclude)))
            ;; Not is lowered to a fact read followed by its complement. The
            ;; conjunction must pool the source-level value, not the raw fact's
            ;; TV. A complemented projection is no longer a positive projection
            ;; of its source. Output-only NotFormula calls have no later join.
            ((CPU NotFormula ($input) $res)
               (case (collapse (once (cpu-call 0 NotFormula (quote ($input))))) (
                  ((cons $result $_rest)
                     (if (= $res $result)
                        (if (head-is? $result STV)
                           (case $parts (
                              ((cons $part $rest)
                                 (if (=alpha (sk-part-tv $part) $input)
                                    (sk-acc $fold-proofs $ev $deps
                                       (cons (sk-indep-part (the STVType $result)) $rest))
                                    $state))
                              (() $state)))
                           $state)
                        sk-fail))
                  (() sk-fail))))
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
                                    (if $facts-first (sk-compatible-value $given $key $filter $exclude $ev $parts false)
                                       (sk-given-value $given $key $filter $exclude)))
                                 (case (sk-use-premise $shared $state $premise $value) (
                                    (sk-fail
                                       (if $shared sk-fail
                                          (case (sk-use-premise $shared $state $premise
                                                   (sk-premise-value $priors (sk-compatible-value $given $key $filter $exclude $ev $parts true))) (
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
          (if (rule-live? $rule) (context-rule-visible? $rule) false))
      (if (sk-claim-charge! $given)
         (let* (((sk-row (sk-ident $owner $_owner-keys $_owner-key) ($_type $_kbctx $proof $_tv) $_premises $_seq) $row)
                ($_reader (if (== $exclude ()) (add-atom &sk_reading ($khash $key $rhash)) ()))
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
                            ;; While its conditioning waits, a row keeps the views
                            ;; it had; one that has none takes its approximate value.
                            ((sk-entangled $keys $base $independent)
                               (let $approx (sk-row-result $retry $independent)
                                  (sk-conditioned $given $target $khash $rhash $exclusions $keys $base $approx
                                     (if (== (sk-latest-view $khash $key $rhash) sk-none) $approx sk-none))))
                            ($_other (sk-row-result $retry $again)))))
                      (sk-row-result $greedy $state)))
                ($_reader-left (if (== $exclude ())
                                  (remove-variant-row! &sk_reading (quote ($khash $key $rhash))) ())))
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
;; value, the merge's more confident view or the row's approximate value,
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
(= (sk-conditioned $given $target $khash $rhash $wexclude $keys $base $approx $waiting)
   (case $keys (
      (() $approx)
      ((cons $_first $_more)
         (if (== $given ())
            (let $cost (* 2 $base)
               ;; Deferred rebuilds may lie outside the ordinary need closure;
               ;; their conditioning uses the same bounded tier slice.
               (if (if (space-row-present? &ctx_sk_given_granted ($khash $rhash)) true
                      (if (== (search-id-value sk_branch_at) 0) false
                         (if (== (search-id-value sk_claim_state) -1)
                            (>= (search-id-value sk_eval_budget) 1) true)))
                  (if (space-row-present? &ctx_sk_conditioning ($khash $rhash)) $waiting
                     (if (== (search-id-value sk_claim_state) -1)
                        (let* (($_entered (context-add! &sk_conditioning ($khash $rhash)))
                               ($_opened (sk-open-claim!))
                               ($deepest (sk-deepen $given $target $wexclude $keys (== $approx sk-none) (if (== $approx sk-none) 64 1) ()))
                               ($exhausted (sk-close-claim!))
                               ($_left (context-remove! &sk_conditioning ($khash $rhash))))
                           (if $exhausted
                              (sk-wait! $khash $rhash $cost (chainer-first-or $waiting $deepest))
                              (chainer-first-or $waiting $deepest)))
                        (chainer-first-or $waiting (sk-mix-on $given $target $wexclude $keys))))
                  (sk-wait! $khash $rhash $cost $waiting)))
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

;; A target waits for a turn, with its estimated cost and waiting value.
(: sk-wait! (-[det]-> Number Number Number SkeletonValue SkeletonValue))
(= (sk-wait! $khash $rhash $cost $waiting)
   (let* (($_unfinished (next-search-id sk_branch_unpaid))
          ($_was (remove-data-rows! &sk_given_pending (quote ($khash $rhash $_cost))))
          ($_pending (context-add! &sk_given_pending ($khash $rhash $cost))))
      $waiting))

;; The statements a condition gives, closed reads' pins aside.
(= (sk-given-depth-step $depth $given) (case $given (((sk-given $_hash $_key $_truth) (+ $depth 1)) ($_pin $depth))))

;; The target evaluated with a statement known true and known false, mixed
;; by the statement's value read without the target: the first statement in
;; order whose mix is possible, its value's evidence outside the branches.
(: sk-mix-on (-[semidet]-> (List SkeletonGiven) SkeletonTarget (List Number) (List SkeletonKey) (List SkeletonValue)))
(= (sk-mix-on $given $target $wexclude $keys)
   (case $keys (
      (() ())
      ((cons $pin $more)
         (let* (($phash (index-hash $pin))
                ($before (search-id-value sk_claim_cut)))
            (case (collapse (once
                     (sk-mix (sk-given-value $given $pin sk-any-filter $wexclude)
                        (sk-target-value (cons (sk-given $phash $pin true) $given) $target)
                        (sk-target-value (cons (sk-given $phash $pin false) $given) $target)))) (
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

;; A claim buys conditioned rows in pairs: one evaluation unit pays for
;; the next row and leaves one credit for a later row in this claim. This
;; preserves the existing two-rows-per-unit bound and integer allowances.
;; Nested conditioning shares the credit; unused credit expires at close.
(: sk-open-claim! (-[det]-> Atom))
(= (sk-open-claim!)
   (progn (change-state! sk_claim_state 0)
          (change-state! sk_claim_depth 64) (change-state! sk_claim_cut 0) ()))

(: sk-close-claim! (-[det]-> Bool))
(= (sk-close-claim!)
   (let $exhausted (== (search-id-value sk_claim_state) -2)
      (progn (change-state! sk_claim_state -1) (change-state! sk_claim_depth 64) (change-state! sk_claim_cut 0) $exhausted)))

(: sk-claim-charge! (-[det]-> (List SkeletonGiven) Bool))
(= (sk-claim-charge! $given)
   (if (if (== $given ()) true (== (search-id-value sk_claim_state) -1)) true
      (if (== (search-id-value sk_claim_state) -2) false
         (let $paid
               (if (== (search-id-value sk_claim_state) 1)
                  (progn (change-state! sk_claim_state 0) true)
                  (if (>= (search-id-value sk_eval_budget) 1)
                     (progn (change-state! sk_eval_budget (- (search-id-value sk_eval_budget) 1))
                            (change-state! sk_claim_state 1) true)
                     false))
            (if $paid
               (let $_counted (query_metric_increment conditioned-evaluations) true)
               (progn (change-state! sk_claim_state -2) false))))))

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
               (if (if $shared false (if (rule-application-proof? $proof) true (head-is? $proof conjunction)))
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
      ((CPU CompletionLikelihoodsFormula (And $negated $_others $_rule) $_likelihood)
         (cons (sk-given $khash $key (if (== $negated true) false true)) ()))
      ((CPU CompletionLikelihoodsFormula (Or $negated $_others $_rule) $_likelihood)
         (cons (sk-given $khash $key (if (== $negated true) true false)) ()))
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
   (if (head-is? $type ImplicationInstanceSample)
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

;; A ground false assumed antecedent cannot supply evidence through an STV's
;; population-inferred complement. Open antecedents retain that population
;; evidence: an assumed individual does not exhaust their population.
;; Keep a zero-confidence value so internal
;; two-branch scaffolds can still read the unsupported side as unknown.
;; Explicit CTVs have no ImplicationLikelihoodsFormula and retain both stated branches.
(: sk-assumed-false-application? (-[det]-> (List SkPattern) Proof Bool))
(= (sk-assumed-false-application? $premises $proof)
   (if (not (== (collapse (once (let $stv-premise (superpose $premises)
          (case $stv-premise (((CPU ImplicationLikelihoodsFormula $_args $_out) true) ($_other (empty))))))) ()))
      (if (not (== (collapse (once (let $mp-premise (superpose $premises)
             (case $mp-premise (
                ((CPU $mp ((STV $s $c) $_ctv) $_result)
                   (if (if (if (== $mp CTVModusPonensFormula) true (== $mp ImplicationModusPonensFormula))
                           (if (<= (the Number $s) 0) (>= (the Number $c) 1) false) false) true (empty)))
                ($_other (empty))))))) ()))
         (if (== (collapse (once (let $input (superpose $premises)
                (case $input (
                   ((CPU $_input-fun $_input-args $_input-result) (empty))
                   (($antecedent $_scope $_input-proof $_input-tv)
                      (if (head-is? $antecedent RuleTruth) (empty)
                         (if (== (extract-vars $antecedent) ()) (empty) true)))))))) ())
            (== (collapse (once (proof-term-evidence proof-walk-in-kb $proof))) ((ev-set 0)))
            false)
         false)
      false))

;; Keep the TV union at a typed boundary: inlining these two constructors
;; into sk-row-result leaves a residual runtime TV check in strict mode.
(: sk-unsupported-tv (-[det]-> TV TV))
(= (sk-unsupported-tv $tv)
   (case $tv (
      ((CTV $_pos $_neg) (CTV (STV 0.0 0.0) (STV 0.0 0.0)))
      ($_other (STV 0.0 0.0)))))

;; Only a likelihood with a certain zero branch can certify impossibility.
;; The opposite branch must allow the observation; a zero prior, a rounded
;; posterior endpoint, and an ordinary zero-strength fact certify nothing.
(: sk-zero-likelihood-step (-[det]-> Bool SkPattern Bool))
(= (sk-zero-likelihood-step $found $premise)
   (if $found true
      (case $premise (
         ((CPU CTVBayesFormula ((STV $p $_pc)
                  (likelihood-read (CTV (STV $s $c) (STV $n $nc)) $_read $_support)) $_out)
            (if (if (> (the Number $p) 0) (< (the Number $p) 1) false)
               (if (>= (the Number $c) 1)
                  (if (<= (the Number $s) 0) (> (the Number $n) 0)
                     (if (>= (the Number $s) 1) (< (the Number $n) 1) false))
                  (if (>= (the Number $nc) 1)
                     (if (<= (the Number $n) 0) (> (the Number $s) 0)
                        (if (>= (the Number $n) 1) (< (the Number $s) 1) false)) false)) false))
         ($_other false)))))

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
                ($applied (sk-unwrap-proof $full-proof))
                ($zero (if $unsupported false
                   (case $value-tv (
                      ((STV $s $_c)
                         (if (<= $s 0)
                            (case (sk-prior-update-of $applied $value-tv) (
                               ((sk-prior-update $_base $_prior ()) false)
                               ($_update (fold-semidet sk-zero-likelihood-step false $premises)))) false))
                      ($_other false)))))
                ($fact (assemble-runtime-fact $type $kbctx
                   (if $zero (zero-likelihood $applied) $applied) $value-tv)))
            ;; The unknown bridge permits an evidence-backed inversion; it
            ;; is not a standalone guess about an unobserved root.
            (if (if (head-is? $applied population-prior)
                    (case $value-tv (((STV $_s $c) (<= $c 0)) ($_other false))) false)
               sk-none
               (sk-val $fact (if $unsupported (ev-set 0) (rule-result-evidence $fact $ev)) (deps-join $deps)))))
      ($_failed sk-none))))

;; --- Evaluation -------------------------------------------------------------

;; Evaluation starts from what changed since the last one: rows never
;; evaluated, and the readers of keys whose value changed outside evaluation
;; (added facts, removed query-local rows, new fold members). Rows are computed
;; in creation order, so a first computation reads only what was derived
;; earlier, as a proof is built from proofs that already exist. A query
;; computes the rows it pays for from its allowance after the others, nearest
;; a root first (see sk-item-order). When a row's view changes, the rows
;; reading its key are scheduled: later rows in the same pass, earlier rows in
;; the next one. Nothing whose inputs did not change is visited.
;;
;; Inverted rules make most of a real skeleton cyclic, so values need not
;; settle. A recomputed view is kept only when it brings support: a dependency
;; the row never had. The keys a row can depend on are finite, so evaluation
;; ends. A truth value that changes without new support, when a reader switches
;; to an older admissible version or a merge's dominance flips, keeps the view
;; it had. A change from outside the rows (a fact, a removed query-local row, a
;; fold member) makes each reader recompute without that test, once per
;; evaluation for each cause, and a reader whose value changes passes the
;; same cause on through rows and folds. A newly supported member change
;; starts a distinct cause, so later refinements can reach the same readers.

;; The row stored under a key hash and a row hash, as an item of the work.
(: sk-row-item-at (-[nondet]-> Number Number SkeletonItem))
(= (sk-row-item-at $khash $rhash)
   (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
      (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq))))

;; The rows that read a key directly, as fact premise, fold or group.
(: sk-readers (-[det]-> SkeletonKey (List SkeletonItem)))
(= (sk-readers $key)
   (let $hash (index-hash $key)
      (collapse (match &ctx_sk_reader ($hash $stored $khash $rhash)
         (if (=alpha $stored $key) (sk-row-item-at $khash $rhash) (empty))))))

;; An item's place in its pass. A query computes the rows within the free
;; depth first, by creation; then the rows that spend its allowance, nearest a
;; root first and by creation within a depth; then the fold checks. So within
;; a pass the allowance goes to the rows nearest a root, whatever order the
;; search created them in. A forward run, whose rows all spend its units,
;; computes them by creation. Creation numbers stay below 10^12, and the fold
;; checks come after every row.
(: sk-item-order (-[det]-> SkeletonItem Number))
(= (sk-item-order (sk-row-item $seq $khash $key $_rhash $_row))
   (let $depth (sk-need-depth $khash $key)
      (if (if (== (search-id-value sk_forward_run) 1) true (<= $depth (sk-evaluation-free-depth))) $seq
         (+ (* $depth 1000000000000) $seq))))
(= (sk-item-order (sk-fold-check $_hash $_fold)) (sk-check-seq))

;; this pass's remaining items and the next pass's, by their order
(: SkeletonWork Type)
(: sk-work (-[det]-> (Heap SkeletonItem) (Heap SkeletonItem) SkeletonWork))

(: sk-queued-new? (-[det]-> Number Number Number Bool))
(= (sk-queued-new? $pass $khash $rhash)
   (if (space-row-present? &ctx_sk_queued ($pass $khash $rhash)) false
      (let $_queued (context-add! &sk_queued ($pass $khash $rhash)) true)))

;; A row is queued by its key and row hashes, a fold check by its fold's hash.
(: sk-queue-new? (-[det]-> Number SkeletonItem Bool))
(= (sk-queue-new? $pass (sk-row-item $_seq $khash $_key $rhash $_row)) (sk-queued-new? $pass $khash $rhash))
(= (sk-queue-new? $pass (sk-fold-check $hash $_fold)) (sk-queued-new? $pass $hash -1))

;; What changed for a key's readers: a new row view with its dependencies,
;; the same with the key's open merged value unchanged and the dependencies of
;; that value before and after, or a change from outside the rows (a fact, a
;; removed query-local row, fold members), with the dependencies of the new
;; view. View-only notifications retain incoming causes too: a proof-only
;; refresh does not force ordinary readers, but must not start a fresh cause
;; if it reaches a fold. Empty causes identify an unforced supported change.
(: SkeletonChange Type)
(: sk-view-change (-[det]-> Number (List Number) SkeletonChange))
(: sk-value-same (-[det]-> Number Number (List Number) SkeletonChange))
(: sk-outside-change (-[det]-> (List Number) Number SkeletonChange))

(: sk-change-deps (-[det]-> SkeletonChange Number))
(= (sk-change-deps (sk-view-change $deps $_causes)) $deps)
(= (sk-change-deps (sk-value-same $deps $_merged-deps $_causes)) $deps)
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
      ((sk-view-change $deps $_causes)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s)) true))
      ((sk-value-same $deps $merged-deps $_causes)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s))
            (if (deps-has? $merged-deps $khash) true
               (if (fold-semidet (sk-reads-open? $key) true $premises) false true)))))))

;; A reader after the item that changed its input, in the pass's order, is
;; still ahead in this pass; an earlier one waits for the next.
(: sk-schedule-reader
   (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonItem SkeletonWork))
(= (sk-schedule-reader $pass $order $key $change (sk-work $todo $next) $item)
   (if (if (sk-item-needed? $item) false (if (sk-determined-row? $item) false (let $_stale (sk-mark-stale! $item) true)))
      (sk-work $todo $next)
   (if (let $_forced
          (case $change (
             ((sk-outside-change $causes $_deps) (sk-force! $causes $item))
             ($_view ())))
          (sk-reader-affected? $key $change $item))
      (let $at (sk-item-order $item)
         (if (> $at $order)
            (if (sk-queue-new? $pass $item)
               (sk-work (add_to_heap $todo $at $item) $next)
               (sk-work $todo $next))
            (if (sk-queue-new? (+ $pass 1) $item)
               (sk-work $todo (add_to_heap $next $at $item))
               (sk-work $todo $next))))
      (sk-work $todo $next))))

(: sk-drop-fold-view! (-[det]-> SkeletonKey Atom))
(= (sk-drop-fold-view! $key) (sk-drop-row-views! (index-hash $key) $key 0))

;; A changed key schedules the rows it affects. A fold or group over it is
;; recomputed when next read, and all of its readers are scheduled.
(: sk-key-changed
   (-[semidet]-> Number Number SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-key-changed $pass $order $change $work $key)
   (if (context-propagate? $key)
   (let* (($hash (index-hash $key))
          ($_mining (case $change (
             ((sk-value-same $_deps $_merged-deps $_causes) ())
             ($_changed (hm-screen-changed! $hash $key)))))
          ($folds
             (collapse (match &sk_use ($hash $stored $fold)
                (if (=alpha $stored $key) $fold (empty)))))
          ($scheduled (fold-semidet (sk-schedule-reader $pass $order $key $change) $work (sk-readers $key))))
      (fold-semidet (sk-fold-changed $pass $order $key $change) $scheduled $folds)) $work))

;; A member change of a fold that was read queues the fold's check at the end
;; of the pass, unless the member's new view depends on the fold, which the fold
;; does not admit; so the members changed in one pass recompute it once; until
;; then its readers read the value it had. A fold nobody read since it last
;; changed is computed when next read. A base-rate fold also records the
;; member to take, unless the change came through the rate itself: a past
;; belief that reads the rate as its prior changes whenever the rate moves, and
;; would otherwise be needed and taken again each time. Nor does a base-rate
;; fold see a member whose open merged value stayed the same outside the
;; fold's dependencies: it takes that value, so there is nothing new to take
;; (a labelled past member gaining a derived view under its fact). An implication
;; instance fold no query needs keeps its view and readers: the evaluation
;; brings it current at its end (sk-instance-checks!). A check queued for this
;; pass is also queued for the next, in case this pass's check already ran.
;; Supported changes start fresh causes; forced changes retain their incoming
;; causes across the fold. Retagging a forced change by the immediate member
;; would either suppress a later refinement or renew feedback around a cycle.
(: sk-check-seq (-[det]-> Number))
(= (sk-check-seq) 1000000000000000000000000)

;; An empty existential fold has been read but has no value. Its members
;; must still wake its readers when they obtain evidence.
(: sk-fold-read? (-[det]-> Number SkeletonKey Bool))
(= (sk-fold-read? $hash $fold)
   (if (sk-existential-fold? $fold)
      (not (== (collapse (once (match &ctx_sk_latest ($hash $stored (sk-version $_seq 0 $_value))
         (if (=alpha $stored $fold) true (empty))))) ()))
      (not (== (sk-latest-view $hash $fold 0) sk-none))))

(: sk-fold-changed (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-fold-changed $pass $_seq $member $change (sk-work $todo $next) $fold)
   (let $hash (index-hash $fold)
      (if (if (deps-has? (sk-change-deps $change) $hash) true
             (case $change (
                ((sk-value-same $_deps $merged-deps $_causes)
                   (if (deps-has? $merged-deps $hash) false
                      (if (sk-instance-fold-key? $fold) false (sk-rate-fold? $fold))))
                ($_other false))))
         (sk-work $todo $next)
      (let $_rate (sk-rate-dirty! $fold $member)
      (if (not (sk-fold-read? $hash $fold)) (sk-work $todo $next)
      (if (if (sk-needed? $hash $fold) false
             (let $_stale (if (sk-instance-fold-key? $fold) () (sk-stale-fold! $fold)) true))
         (sk-work $todo $next)
         (let* (($incoming (case $change (
                   ((sk-outside-change $propagated $_deps) $propagated)
                   ((sk-view-change $_deps $propagated) $propagated)
                   ((sk-value-same $_deps $_merged $propagated) $propagated))))
                ($causes (if (== $incoming ())
                   (cons (- 0 (+ 2 (next-search-id sk_change_cause))) ()) $incoming))
                ($_pending (foreach-flat (sk-fold-pending! $hash) $causes))
                ($check (sk-fold-check $hash $fold)))
            (if (sk-queue-new? $pass $check) (sk-work (add_to_heap $todo (sk-check-seq) $check) $next)
               (if (sk-queue-new? (+ $pass 1) $check) (sk-work $todo (add_to_heap $next (sk-check-seq) $check))
                  (sk-work $todo $next))))))))))

;; A row is forced once per evaluation by each cause. Supported changes are
;; finite, and forced propagation never creates a new cause, even through a
;; fold, so feedback still ends. A row never computed is not forced: its first
;; view changes its key whatever caused it.
(: sk-force-causes! (-[det]-> Number Number (List Number) Atom))
(: sk-force-reset! (-[det]-> Atom))

(: sk-force! (-[det]-> (List Number) SkeletonItem Atom))
(= (sk-force! $causes (sk-row-item $_seq $khash $_key $rhash $_row))
   (if (space-row-present? &ctx_sk_support ($khash $rhash $_deps))
      (sk-force-causes! $khash $rhash $causes)
      ()))
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
      ((sk-val ($type $kbctx $_proof $tv) $ev $deps)
         (case $old (
            ((sk-val ($old-type $old-kbctx $_old-proof $old-tv) $old-ev $old-deps)
               (if (=alpha (data $type $kbctx $tv) (data $old-type $old-kbctx $old-tv))
                  (if (=alpha $ev $old-ev) (=alpha $deps $old-deps) false) false))
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
   (let* (($causes (list_to_set (collapse (match &ctx_sk_fold_pending ($hash $member) $member))))
          ($_taken (remove-data-rows! &sk_fold_pending (quote ($hash $member))))
          ($old (sk-latest-view $hash $fold 0)))
      (if (if (== $causes ()) true
             (if (sk-existential-fold? $fold) false (== $old sk-none))) $work
         (let* (($_merged (sk-drop-merged! $fold)))
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
;; The row's order in the pass places the readers it schedules.
(: sk-compute (-[semidet]-> Number Number SkeletonWork SkeletonItem SkeletonWork))
(= (sk-compute $pass $_order $work (sk-fold-check $hash $fold)) (sk-check-fold $pass $work $hash $fold))
(= (sk-compute $pass $order $work (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_computed (query_metric_increment row-computes))
          ($causes (collapse (match &ctx_sk_forced ($hash $rhash $cause) $cause)))
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
                      (not (space-row-present? &ctx_sk_given_pending ($hash $rhash $_waits))))
                   false)
               (let* (($_views (sk-drop-row-views! $hash $key $rhash))
                      ($_merged (sk-drop-merged! $key))
                      ($_derived-nothing (context-add! &sk_support ($hash $rhash 0))))
                  (sk-key-changed $pass $order (sk-outside-change $causes 0) $work $key))
               ;; A closed reader of a complete key evaluates its rows again,
               ;; so a new row that derives nothing, or a forced one, still
               ;; changes the key for it.
               (let* (($first (not (space-row-present? &ctx_sk_support ($hash $rhash $_had))))
                      ($_nothing (if $first (context-add! &sk_support ($hash $rhash 0)) true)))
                  (if (if (if $first true $forced)
                         (case $key (((sk-key $type $kbctx) (complete-statement? $type $kbctx)) ($_fold false)))
                         false)
                     (sk-key-changed $pass $order (if $forced (sk-outside-change $causes 0) (sk-view-change 0 ())) $work $key)
                     $work))))
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
                         (collapse (once (match &ctx_sk_merged ($hash $stored $deps $value)
                            (if (=alpha $stored $key) (if (sk-live-view? $value) (sk-merged $hash $stored $deps $value) (empty)) (empty))))))
                      ($_stored (sk-store-view! $hash $key $seq $rhash $new))
                      ($_stored-count (query_metric_increment views-stored))
                      ($_merged (sk-drop-merged! $key))
                      ($deps (sk-view-deps-step 0 $new)))
                  (sk-key-changed $pass $order
                     (if (if $forced (not (sk-same-view? $new $latest)) false)
                        (sk-outside-change $causes $deps)
                        (sk-value-change $hash $key $deps $causes $before))
                     $work $key)))))))))

;; An unchanged open merged value is known only when it was cached before.
;; Keep a provenance-only refresh's causes without forcing its row readers.
(: sk-value-change (-[semidet]-> Number SkeletonKey Number (List Number) (List SkeletonMerged) SkeletonChange))
(= (sk-value-change $hash $key $deps $causes $before)
   (case $before (
      (() (sk-view-change $deps $causes))
      ((cons (sk-merged $_h $_k $old-deps $old-value) $_rest)
         (case (sk-open-value $hash $key sk-any-filter) (
            ((sk-merged $_h2 $_k2 $new-deps $new-value)
               (if (=alpha $old-value $new-value)
                  (sk-value-same $deps (deps-union $old-deps $new-deps) $causes)
                  (sk-view-change $deps $causes)))))))))

;; Works off the queued rows and returns the last pass. A row a query needs
;; that reads a fold the stale cascade reached meanwhile (the fold went stale
;; over a member left stale and dropped its view) is computed again in a
;; further pass, forced by its own key, whenever that happens: the query reads
;; no value from before what it needs. One left stale for want of allowance
;; meanwhile stays stale. A forward run leaves such rows stale for the
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
         (let* (($restale (collapse (match &ctx_sk_restale ($khash $rhash) ($khash $rhash))))
                ($_taken (remove-data-rows! &sk_restale (quote ($khash $rhash))))
                ($again (fold-semidet sk-restale-step (empty_heap) $restale)))
            (if (heap-empty? $again)
               (if (sk-build-wanted!) (sk-work-off! (+ $pass 1) (sk-work (empty_heap) (empty_heap))) $pass)
               (sk-work-off! (+ $pass 1) (sk-work $again (empty_heap)))))
         (sk-work-off! (+ $pass 1) (sk-work $next (empty_heap))))
      (sk-work-pop! $pass $next (heap_pop $todo))))

;; Ordinary reads keep their incumbent. Only this last tier rebuilds a miss;
;; nested reads may rebuild inline inside its bounded evaluation slice.
;; Leave a request in place until the build returns, including on exceptions.
(= (sk-build-wanted!)
   (let $room (min (search-id-value sk_eval_budget) (search-id-value sk_branch_budget))
      (if (< $room 1) false
         (case (collapse (once (match &ctx_sk_branch_wanted ($slot $hash $key $rhash $exclude)
                  (sk-wanted $slot $hash $key $rhash $exclude)))) (
            (() false)
            ((cons (sk-wanted $slot $hash $key $rhash $exclude) $_rest)
               (let* (($request (data $slot $hash $key $rhash $exclude))
                      ($before (search-id-value sk_eval_budget))
                      ($incumbent (chainer-first-or
                                    (chainer-first-or sk-none (sk-branch-values $slot $key $rhash $exclude false))
                                    (sk-branch-values $slot $key $rhash $exclude true)))
                      ($_slice (change-state! sk_eval_budget $room))
                      ($built (sk-rebuild-view true $hash $key $rhash $exclude))
                      ($spent (- $room (search-id-value sk_eval_budget)))
                      ($_restore (change-state! sk_eval_budget (- $before $spent)))
                      ;; Even a cache hit or a structurally impossible read
                      ;; consumes one tier unit, bounding queue bookkeeping.
                      ($_share (change-state! sk_branch_budget (- (search-id-value sk_branch_budget) (max 1 $spent))))
                      ($_taken (remove-variant-row! &sk_branch_wanted (quote ($slot $hash $key $rhash $exclude))))
                      ($settled (not (== (sk-branch-values $slot $key $rhash $exclude true) ())))
                      ($_retry (if $settled true (context-add! &sk_branch_wanted $request)))
                      ($_ready
                         (if (not (sk-same-view? $built $incumbent))
                            (let* (($cause (- 0 (+ 2 (next-search-id sk_change_cause))))
                                   ($_readers (collapse (fold-semidet (sk-branch-ready-step $cause $exclude $key) ()
                               (append-flat (append-flat (sk-readers $key)
                                  (collapse (match &sk_use ($hash $member $fold)
                                     (if (=alpha $member $key)
                                        (if (sk-instance-fold-key? $fold) (empty)
                                           (if (sk-rate-fold? $fold) (sk-fold-check (index-hash $fold) $fold) (empty)))
                                        (empty)))))
                                  (collapse (match &ctx_sk_stale_reader ($hash $stored $reader-hash $reader-row)
                                     (if (=alpha $stored $key) (sk-row-item-at $reader-hash $reader-row) (empty))))))))) ())
                            ())))
                  true)))))))

(= (sk-branch-ready-step $cause $exclude $_member $_acc (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $created)))
   ;; A row always excludes its own key. Readers in other exclusion contexts
   ;; keep their own requests; this arrival must not force them as well.
   (if (stored-list-member? $hash $exclude)
      (let $_requested
         (if (== (search-id-value sk_forward_run) 1)
            (if (sk-needed? $hash $key) () (let $_needed (add-atom &sk_needed ($hash $key 0)) ())) ())
         (if (sk-needed? $hash $key)
            (let* (($_forced (sk-force! (cons $cause ()) (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $created))))
                   ($_linked (if (space-row-present? &ctx_sk_stale ($hash $rhash))
                                (sk-relink-row! $hash $rhash $premises) ()))
                   ($_ready (if (space-row-present? &ctx_sk_restale ($hash $rhash)) ()
                                (let $_row (context-add! &sk_restale ($hash $rhash)) ()))))
               ())
            ()))
      ()))
;; A member's fold-excluded branch can arrive after its initial take failed.
;; Retake it through the ordinary fold read and wake that fold's consumers.
(= (sk-branch-ready-step $_cause $exclude $member $_acc (sk-fold-check $hash $fold))
   (if (stored-list-member? $hash $exclude)
      (let $_dirty (sk-rate-dirty! $fold $member)
         (sk-stale-fold! $fold)) ()))

(: sk-restale-step (-[semidet]-> (Heap SkeletonItem) (Number Number) (Heap SkeletonItem)))
(= (sk-restale-step $todo ($khash $rhash))
   (if (space-row-present? &ctx_sk_stale ($khash $rhash)) $todo
      (case (collapse (once (sk-row-item-at $khash $rhash))) (
         ((cons $item $_rest) (let $_forced (sk-force! (cons $khash ()) $item) (add_to_heap $todo (sk-item-order $item) $item)))
         (() $todo)))))

(: sk-work-pop!
   (-[semidet]-> Number (Heap SkeletonItem) (Number SkeletonItem (Heap SkeletonItem)) Number))
;; Each row commits to its one result, so the loop leaves no choice points and
;; runs in constant stack however many rows it computes. An item no query needs
;; is in the work only as a determined row (sk-seed-new, sk-schedule-reader),
;; which costs nothing; a determined row a query needs is computed even when
;; the allowance cannot pay for it.
(= (sk-work-pop! $pass $next ($order $item $rest))
   (if (if (sk-item-needed? $item)
          (if (sk-near-root-reserve-take! $item) true
             (if (sk-take! sk_eval_budget
                    (case $item (((sk-row-item $_seq $_khash (sk-key $type $_kbctx) $_rhash $_row) (term-cost $type)) ($_fold-check 1))))
                true
                (sk-determined-row? $item)))
          true)
      (sk-work-off! $pass (once (sk-compute $pass $order (sk-work $rest $next) $item)))
      (let* (($_unpaid (query_metric_increment rows-unpaid))
             ($_stale (sk-mark-stale! $item)))
         (sk-work-off! $pass (sk-work $rest $next)))))

;; A query computes the rows and folds within two steps of a root from a
;; reserve that its need fills with a fixed number of computations for each
;; one it reaches there, shared among them: rows read one another through
;; inverted rules, each change schedules its readers again, and a fold is
;; checked again when more members change, so near a root an evaluation is
;; bounded by the size of what its roots read, not by the passes its cycles
;; take. What the reserve cannot pay for, and every deeper row, spends the
;; allowance; what neither can pay for is left stale, as if no query needed
;; it, and a later query that reads it recomputes it from its inputs then. A
;; row of a large key spends more of the allowance (term-cost); a fold, whose
;; arguments do not grow with recursion, one.
;; Creation order is kept, so an allowance that covers everything computes
;; what a query without one would. A forward run has no reserve.
(: sk-near-root-reserve-take! (-[det]-> SkeletonItem Bool))
(= (sk-near-root-reserve-take! (sk-row-item $_seq $khash $key $_rhash $_row))
   (if (<= (sk-need-depth $khash $key) (sk-evaluation-free-depth)) (sk-take! sk_near_reserve 1) false))
(= (sk-near-root-reserve-take! (sk-fold-check $hash $fold))
   (if (<= (sk-need-depth $hash $fold) (sk-evaluation-free-depth)) (sk-take! sk_near_reserve 1) false))

;; How near a root a key must be for its rows to draw on the reserve and its
;; stale rows to be brought current. A forward run's need stops at the readers
;; of the keys it takes, and every row it computes costs one of its units.
(: sk-evaluation-free-depth (-[det]-> Number))
(= (sk-evaluation-free-depth) (if (== (search-id-value sk_forward_run) 1) 0 2))

;; Computations each row or fold within two steps of a root adds to a query's
;; reserve: SupplyNet's evaluations take up to about four, cycles through
;; inverted rules (ONA relationalnetwork) about two.
(: sk-evaluation-near-root-reserve (-[det]-> Number))
(= (sk-evaluation-near-root-reserve) 8)

;; Row computations a query may spend per step of its budget beyond the reserve.
(: sk-evaluation-per-step (-[det]-> Number))
(= (sk-evaluation-per-step) 2)

;; A request cannot crowd out ordinary evaluation, restales or conditioning.
;; This is a ceiling within the existing allowance, not an extra allowance.
(: sk-branch-share (-[det]-> Number))
(= (sk-branch-share) 0.125)

;; Expanded nodes a query's walk may pass through per step of its budget.
(: sk-walk-per-step (-[det]-> Number))
(= (sk-walk-per-step) 1)

;; Keys changed outside evaluation: a fold or group key recomputes when next
;; read, and every changed key's readers are scheduled. A stored fact may make
;; a stale reader determined: it rejoins the key's readers, so it is computed.
(: sk-dirty-seed (-[semidet]-> Number SkeletonWork SkeletonKey SkeletonWork))
(= (sk-dirty-seed $pass $work $key)
   (let* (($hash (index-hash $key))
          ($_branches (sk-invalidate-branches! $key))
          ($_view
             (case $key (
                ((sk-key $_type $_kbctx)
                   (fold-semidet sk-relink-determined-step ()
                      (collapse (match &ctx_sk_stale_reader ($hash $stored $khash $rhash)
                         (if (=alpha $stored $key) (sk-row-item-at $khash $rhash) (empty))))))
                ($_fold (sk-drop-fold-view! $key)))))
          ($_merged (sk-drop-merged! $key)))
      (sk-key-changed $pass -1 (sk-outside-change (cons $hash ()) 0) $work $key)))

(: sk-relink-determined-step (-[semidet]-> Atom SkeletonItem Atom))
(= (sk-relink-determined-step $_acc (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $s)))
   (if (sk-determined-row? (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $s)))
      (sk-relink-row! $khash $rhash $premises)
      ()))

;; --- Demand -----------------------------------------------------------------
;; A query brings current only what its roots read: their keys, the premise
;; keys of those keys' rows, and the members of the folds and groups among
;; them. A row outside that set whose input changes is marked stale instead of
;; computed, and so is everything reading it, once (what the query needs once
;; it has read its answers); a later query that reads it again recomputes it. A stale row leaves
;; the reader lists of the keys it reads until then, so a change walks only
;; readers that are current, and earlier queries' rows cost nothing per query
;; or per change.

;; Signatures of the mutually recursive functions below.
(: sk-need! (-[semidet]-> Number SkeletonNeed SkeletonKey SkeletonNeed))
(: sk-stale-key! (-[det]-> SkeletonKey Atom))

(: sk-needed? (-[det]-> Number SkeletonKey Bool))
(= (sk-needed? $hash $key)
   (not (== (collapse (once (match &sk_needed ($hash $stored $_depth) (if (=alpha $stored $key) true (empty))))) ())))

;; How many rows or folds lie between a needed key and the nearest root.
(: sk-need-depth (-[det]-> Number SkeletonKey Number))
(= (sk-need-depth $hash $key)
   (chainer-first-or 1000000
      (collapse (once (match &sk_needed ($hash $stored $depth) (if (=alpha $stored $key) $depth (empty)))))))

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
;; current, so there is nothing under either to recompute. Rows never computed
;; are taken nearest a root first, as the evaluation computes them; those of
;; large statements spend what their size costs beyond a row's (term-cost)
;; from as much as the allowance can compute (sk_need_budget). A recursive rule
;; that builds ever larger rows faster than they are computed, such as a base
;; rate's members through (Num $x) → (Num (succ $x)), would otherwise make
;; every need walk the whole backlog; a need through rows of ordinary size,
;; whose walk also takes base rates' changed members, is not cut.
;;
;; A stale row brought current leaves the stale set and rejoins its keys'
;; readers.
(: sk-relink-row! (-[semidet]-> Number Number (List SkPattern) Atom))
(= (sk-relink-row! $khash $rhash $premises)
   (let* (($_fresh (context-remove! &sk_stale ($khash $rhash)))
          ($keys (fold-semidet sk-direct-key-step () $premises))
          ($_unmarked (fold-semidet (sk-drop-stale-reader! $khash $rhash) () $keys))
          ($_linked (fold-semidet (sk-add-reader! $khash $rhash) () $keys)))
      ()))

;; A row cannot contribute when every structural reader excludes one of its
;; mandatory statement inputs. Keep the pending claim: a new reader or root
;; revokes this proof of unreadability on the next need/payment round.
(: sk-readable-row? (-[semidet]-> Number SkeletonKey (List SkPattern) Bool))
;; A forward run exposes taken values too, beyond its depth-zero reader keys.
;; Conservatively keep all its claims live instead of pruning a public value.
(= (sk-readable-row? $hash $key $premises)
   (if (if (== (search-id-value sk_forward_run) 1) true (== (sk-need-depth $hash $key) 0)) true
      (if (not (== (collapse (once (match &sk_use ($hash $member $_fold)
                    (if (=alpha $member $key) true (empty))))) ())) true
         (let* (($inputs (fold-semidet sk-direct-key-step (cons $key ()) $premises))
                ($mandatory (deps-join (collapse
                   (let (sk-key $type $scope) (superpose $inputs)
                      (deps-key (index-hash (sk-key $type $scope)))))))
                ($readers (append-flat
                   (collapse (match &ctx_sk_reader ($hash $read $kh $rh)
                      (if (=alpha $read $key) ($kh $rh) (empty))))
                   (collapse (match &ctx_sk_stale_reader ($hash $stale $sh $sr)
                      (if (=alpha $stale $key) ($sh $sr) (empty)))))))
            (not (== (collapse (once
               (let ($reader-hash $reader-row) (superpose $readers)
                  (match &sk_row ($reader-hash $reader-key $reader-row
                           (sk-row $_ident ($_type $_ctx $proof $_tv) $_premises $_seq))
                     (if (deps-meet? (sk-row-exclusions $reader-hash $reader-key $proof) $mandatory)
                        (empty) true))))) ()))))))

(: sk-need-row! (-[semidet]-> Number SkeletonNeed SkeletonItem SkeletonNeed))
(= (sk-need-row! $depth (sk-need-next $next $members) (sk-row-item $_seq $khash $key $rhash (sk-row (sk-ident $rule $_keys $_key) $_concl $premises $_s)))
   (if (rule-live? $rule)
   (let* (($_reserve (sk-reserve-near! (- $depth 1)))
          ($near (<= $depth (+ (sk-evaluation-free-depth) 1)))
          ($world (space-row-present? &sk_world_stale ($khash $rhash)))
          ($_world-needed (if $world
             (if (space-row-present? &sk_world_done ($khash $rhash)) ()
                (let $_needed (add-atom &sk_world_done ($khash $rhash)) ())) ()))
          (($latest $invalid)
             (case (collapse (once (match &ctx_sk_latest ($khash $stored (sk-version $_old-seq $rhash $view))
                       (if (=alpha $stored $key) (if (sk-live-view? $view) ($view false) (sk-none true)) (empty))))) (
                ((cons $state $_rest) $state)
                (() (sk-none false)))))
          ($unseen
             (if (== $latest sk-none)
                (if $near true
                   (case $key (((sk-key $type $_kbctx)
                      (let $extra (- (term-cost $type) 1)
                         (if (== $extra 0) true (sk-take! sk_need_budget $extra)))))))
                false))
          ($refresh
             (if (if $unseen true (if $near true $world))
                (if $invalid true (space-row-present? &ctx_sk_stale ($khash $rhash)))
                false))
          ($_forced (if (if $refresh $invalid false) (context-add! &sk_forced ($khash $rhash -1)) true))
          ($_refreshed
             (if $refresh
                (let $_relinked (sk-relink-row! $khash $rhash $premises) (context-add! &sk_refresh ($khash $rhash)))
                ())))
      (if (if (space-row-present? &ctx_sk_given_pending ($khash $rhash $_cost))
                (sk-readable-row? $khash $key $premises)
                (if $world true (if $refresh true
                   (if (<= $depth (sk-evaluation-free-depth)) true $unseen))))
         (sk-need-next (fold-semidet sk-direct-key-step $next $premises) $members)
         (sk-need-next $next $members)))
   (let $_removed (sk-drop-row! $khash $key $rhash (sk-row (sk-ident $rule $_keys $_key) $_concl $premises $_s))
      (sk-need-next $next $members))))

;; The need from a query's roots, or from the keys a forward wave takes.
(: sk-need-roots! (-[semidet]-> (List SkeletonKey) Atom))
(= (sk-need-roots! $keys)
   (let $_budget (change-state! sk_need_budget (search-id-value sk_eval_budget)) (sk-need-keys! 0 $keys)))

;; A key is needed at the fewest steps from a root it is reached by. The keys
;; are visited breadth first, a level of keys one step further than the last
;; at a time, so each is reached first at that depth and visited once: a
;; deeper visit first, then a closer one passing the smaller depth on, walked
;; a chain of inverted rules once per key below it (ChainerGame
;; benchmarks/ona/repros/term_growing_rule.metta: 90% of the query).
;;
;; The members a base-rate or instance fold has yet to take are visited after
;; every key reached otherwise, one level past the deepest. Such a fold
;; estimates a population, so a member moves what its readers read by one
;; member's share, and a member reached otherwise keeps the depth of that
;; path: a fold one step from a root otherwise puts its whole population,
;; every past observation of the pattern, two steps from it, where its rows
;; take the allowance before the rows of the paths the roots read through
;; (SupplyNet stage 2 b100 s2: the history rows reading the base rate took the
;; allowance from the periods nearest the present, error 0 to 0.0004).
;; keys one level further, members of statistical folds
(: SkeletonNeed Type)
(: sk-need-next (-[det]-> (List SkeletonKey) (List SkeletonKey) SkeletonNeed))

(: sk-need-keys! (-[semidet]-> Number (List SkeletonKey) Atom))
(= (sk-need-keys! $depth $keys) (sk-need-level! $depth $keys ()))

(: sk-need-level! (-[semidet]-> Number (List SkeletonKey) (List SkeletonKey) Atom))
(= (sk-need-level! $depth $keys $members)
   (if (== $keys ())
      (if (== $members ()) () (sk-need-level! $depth $members ()))
      (case (fold-semidet (sk-need! $depth) (sk-need-next () $members) $keys) (
         ((sk-need-next $next $later) (sk-need-level! (+ $depth 1) (fold-semidet sk-cons-step () $next) $later))))))

(= (sk-need! $depth $need $key)
   (let $hash (index-hash $key)
      (if (sk-needed? $hash $key) $need
         (let* (($_new (add-atom &sk_needed ($hash $key $depth)))
                ($_touched (sk-touch-key! $hash $key)))
            (sk-need-below! $depth $hash $key $need)))))

;; What a needed key reads: its rows' premise keys, or the members of a fold
;; or group; a base-rate fold takes its changed members.
(: sk-need-below! (-[semidet]-> Number Number SkeletonKey SkeletonNeed SkeletonNeed))
(= (sk-need-below! $depth $hash $key (sk-need-next $next $members))
   (case $key (
      ((sk-key $_type $_kbctx)
         (fold-semidet (sk-need-row! (+ $depth 1)) (sk-need-next $next $members)
            (collapse (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
               (if (=alpha $stored $key)
                  (sk-row-item $seq $hash $stored $rhash (sk-row $ident $concl $premises $seq))
                  (empty))))))
      ((sk-fold $args)
         (let $_reserve (sk-reserve-near! $depth)
         (if (sk-rate-fold? $key)
            (let $changed (sk-rate-changed $hash $key)
               (if (== $changed ()) (sk-need-next $next $members)
                  (let* (($_taken (sk-rate-take! $hash (the ScalarFoldSpec $args)))
                         ($_dirty (sk-mark-dirty! $key)))
                     (sk-need-next $next (fold-semidet sk-cons-step $members $changed)))))
            (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
               ((cons $member $_rest) (sk-need-next (fold-semidet sk-cons-step $next (sk-answers $member)) $members))
               (() (sk-need-next $next $members)))))))
      ((sk-group $group-args)
         (let $_reserve (sk-reserve-near! $depth)
            (case (sk-group-members $key $group-args) (
               ((sk-group-found $_member $found) (sk-need-next (fold-semidet sk-cons-step $next $found) $members))
               (sk-group-missing (sk-need-next $next $members)))))))))

;; A row or fold within two steps of a root adds to a query's reserve (see
;; sk-work-pop!); a forward run has none.
(: sk-reserve-near! (-[det]-> Number Atom))
(= (sk-reserve-near! $depth)
   (if (if (== (search-id-value sk_forward_run) 1) false (<= $depth (sk-evaluation-free-depth)))
      (let $_added (change-state! sk_near_reserve (+ (search-id-value sk_near_reserve) (sk-evaluation-near-root-reserve))) ())
      ()))

(: sk-root-keys-step (-[semidet]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-root-keys-step $keys $goal) (append-flat $keys (sk-root-keys $goal)))

;; A stale row leaves the reader lists of the keys it reads, so a change walks
;; only current readers; it is kept as a stale reader of those keys, which a
;; forward run taking one of them brings back.
(: sk-unlink-reader! (-[det]-> Number Number (List SkPattern) Atom))
(= (sk-unlink-reader! $khash $rhash $premises)
   (fold-flat (sk-stale-reader! $khash $rhash) () (fold-flat sk-direct-key-step () $premises)))

(: sk-mark-stale! (-[det]-> SkeletonItem Atom))
(= (sk-mark-stale! (sk-row-item $_seq $khash $key $rhash (sk-row $_ident $_concl $premises $_s)))
   (if (space-row-present? &ctx_sk_stale ($khash $rhash)) ()
      (let* (($_stale (context-add! &sk_stale ($khash $rhash)))
             ($_unlinked (sk-unlink-reader! $khash $rhash $premises)))
         (sk-stale-key! $key))))
(= (sk-mark-stale! (sk-fold-check $_hash $fold)) (sk-stale-fold! $fold))

;; A fold over a stale key drops its view, so it is recomputed when read.
(: sk-stale-fold! (-[det]-> SkeletonKey Atom))
(= (sk-stale-fold! $fold)
   (if (not (sk-fold-read? (index-hash $fold) $fold)) ()
      (let* (($_view (sk-drop-fold-view! $fold))
             ($_merged (sk-drop-merged! $fold)))
         (sk-stale-key! $fold))))

;; While a query's evaluation runs, the stale cascade does not stale a row the
;; query needs: the row stays linked and follows the changes the evaluation
;; still makes. A row goes stale keeping its view, so a needed reader of its
;; key is held and staled once the query has read its answers (sk-stale-held!),
;; which keeps a current row's inputs current between queries; a fold that
;; goes stale drops its view, so a needed reader of it is computed again in a
;; further pass. Staling needed readers at once unlinked them mid-evaluation,
;; after one refresh, so the rows nearest the roots kept views of inputs that
;; moved after them (SupplyNet scale m spq4 s2: the allowance ran out on a row
;; of (Front z1 t5), the cascade went up the front's chain, and (Blocked k1 t8)
;; ended at 0.46 under a storm of 0.31).
(= (sk-stale-reader-step $stale $_acc (sk-row-item $seq $khash $key $rhash $row))
   (if (if (== (search-id-value sk_holding) 1) (sk-needed? $khash $key) false)
      (case $stale (
         ((sk-key $_type $_kbctx)
            (if (space-row-present? &ctx_sk_held ($khash $rhash sk-stale-input)) ()
               (let $_row (context-add! &sk_held ($khash $rhash sk-stale-input)) ())))
         ($_fold (if (space-row-present? &ctx_sk_restale ($khash $rhash)) () (let $_row (context-add! &sk_restale ($khash $rhash)) ())))))
      (sk-mark-stale! (sk-row-item $seq $khash $key $rhash $row))))
(= (sk-stale-reader-step $_stale $_acc (sk-fold-check $hash $fold)) (sk-mark-stale! (sk-fold-check $hash $fold)))

;; Release branch-only holds whose exact exclusion read settled. An empty
;; branch settles too; an invalidated or unfinished branch still holds its
;; consumer. Ordinary stale-input debt always survives branch settlement.
;; Decide before the stale cascade invalidates other settled branches.
(: sk-stale-held! (-[semidet]-> Atom))
(= (sk-stale-held!)
   (let* (($_released (change-state! sk_holding 0))
          ($held
             (collapse (match &ctx_sk_held ($khash $rhash $reason)
                (if (case $reason (
                       (sk-stale-input true)
                       ((sk-branch-hold $slot $key $row $exclude)
                          (== (sk-branch-values $slot $key $row $exclude true) ()))))
                   (sk-row-item-at $khash $rhash) (empty)))))
          ($_taken (remove-data-rows! &sk_held (quote ($hkhash $hrhash $_reason))))
          ($_branches (remove-data-rows! &sk_branch_hold (quote ($_slot $_hash $_key $_row $_exclude)))))
      (foreach-flat sk-mark-stale! $held)))

(= (sk-stale-key! $key)
   (let* (($hash (index-hash $key))
          ($_readers (fold-flat (sk-stale-reader-step $key) () (sk-readers $key))))
      (foreach-flat sk-stale-fold!
         (collapse (match &sk_use ($hash $stored $fold)
            (if (=alpha $stored $key)
               (if (sk-rate-fold? $fold)
                  (let $_take (if (sk-instance-fold-key? $fold) (sk-rate-dirty! $fold $key) ()) (empty))
                  $fold)
               (empty)))))))

(: sk-stale-world-row-step (-[det]-> (List SkeletonKey) SkeletonItem (List SkeletonKey)))
(= (sk-stale-world-row-step $keys (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_marked (if (space-row-present? &sk_world_stale ($hash $rhash)) ()
                      (let $_mark (add-atom &sk_world_stale ($hash $rhash)) ())))
          ($_stale (sk-mark-stale! (sk-row-item $seq $hash $key $rhash $row))))
      (cons $key $keys)))
(= (sk-stale-world-row-step $keys (sk-fold-check $_hash $_fold)) $keys)

;; Follow both current and released reader links. The key set bounds cycles;
;; the work list avoids retaining a recursive frame per downstream row.
(: sk-stale-world-keys! (-[semidet]-> (List SkeletonKey) Atom))
(= (sk-stale-world-keys! ()) ())
(= (sk-stale-world-keys! (cons $key $rest))
   (let $hash (index-hash $key)
      (if (not (== (collapse (once (match &sk_world_seen ($hash $stored)
                  (if (=alpha $stored $key) true (empty))))) ()))
         (sk-stale-world-keys! $rest)
         (let* (($_seen (add-atom &sk_world_seen ($hash $key)))
                ($readers (append-flat (sk-readers $key)
                   (collapse (match &ctx_sk_stale_reader ($hash $input $khash $rhash)
                      (if (=alpha $input $key) (sk-row-item-at $khash $rhash) (empty))))))
                ($owners (fold-semidet sk-stale-world-row-step () $readers))
                ($folds (collapse (match &sk_use ($hash $member $fold)
                   (if (=alpha $member $key) (if (sk-rate-fold? $fold) (empty) $fold) (empty)))))
                ($_folds (foreach-flat sk-stale-fold! $folds)))
            (sk-stale-world-keys! (append-flat $owners (append-flat $folds $rest)))))))

(: sk-invalidate-world! (-[semidet]-> Atom))
(= (sk-invalidate-world!)
   (let* (($changed (collapse (match &sk_world_changed ($hash $key) $key)))
          ($_taken (remove-data-rows! &sk_world_changed (quote ($_hash $_key))))
          ($_stale (sk-stale-world-keys! $changed))
          ($_seen (remove-data-rows! &sk_world_seen (quote ($_shash $_skey)))))
      ()))

(: sk-item-needed? (-[det]-> SkeletonItem Bool))
(= (sk-item-needed? (sk-row-item $_seq $hash $key $_rhash $_row)) (sk-needed? $hash $key))
(= (sk-item-needed? (sk-fold-check $hash $fold)) (sk-needed? $hash $fold))

;; A new row no query needs is left stale, unless it is determined
;; (sk-determined-row?).
(: sk-seed-new (-[det]-> Number (Heap SkeletonItem) SkeletonItem (Heap SkeletonItem)))
(= (sk-seed-new $pass $todo $item)
   (if (if (sk-item-needed? $item) true (sk-determined-row? $item))
      (if (sk-queue-new? $pass $item) (add_to_heap $todo (sk-item-order $item) $item) $todo)
      (let $_stale (sk-mark-stale! $item) $todo)))

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

;; MAIN can release held rows before an Assuming world starts. That world
;; borrows the same need depths, but must relink its stale rows near the roots
;; locally before seed changes can reach them. Deeper stale history stays put.
(: sk-refresh-near! (-[det]-> Atom))
(= (sk-refresh-near!)
   (let $_refreshed (collapse (match &sk_needed ($hash $key $depth)
      (if (<= $depth (sk-evaluation-free-depth))
         (match &ctx_sk_stale ($hash $rhash)
            (match &sk_row ($hash $stored $rhash (sk-row $_ident $_concl $premises $_seq))
               (if (=alpha $stored $key)
                  (let $_linked (sk-relink-row! $hash $rhash $premises)
                     (context-add! &sk_refresh ($hash $rhash)))
                  (empty))))
         (empty))))
      ()))

(: sk-evaluate! (-[semidet]-> Atom))
(= (sk-evaluate!)
   (let* (($_queued (remove-data-rows! &sk_queued (quote ($qpass $qkhash $qrhash))))
          ($_cleared-forced (remove-data-rows! &sk_forced (quote ($khash $rhash $cause))))
          ($_used (sk-force-reset!))
          ($_pending (remove-data-rows! &sk_fold_pending (quote ($fhash $member))))
          ;; an incomplete fold the query needs is checked again: its members
          ;; may have been searched, or found to derive nothing, since
          ($partial
             (collapse (match &ctx_sk_partial ($phash $pfold)
                (if (sk-needed? $phash $pfold)
                   (let $_cause (context-add! &sk_fold_pending ($phash $phash)) (sk-fold-check $phash $pfold))
                   (empty)))))
          ($_granted (remove-data-rows! &sk_given_granted (quote ($khash $rhash))))
          ($_conditioning (remove-data-rows! &sk_conditioning (quote ($chash $crhash))))
          ($_restale (remove-data-rows! &sk_restale (quote ($skhash $srhash))))
          ($_checked (remove-data-rows! &sk_instance_checked (quote ($ihash))))
          ($last (sk-evaluate-pass! 0 $partial))
          ($_roots (sk-read-roots!)))
      (let $_paid (sk-pay-conditions! (+ $last 1))
         (query_metric_set conditions-unpaid
            (length (collapse (match &ctx_sk_given_pending ($ph $pr $_cost)
               (if (== $pr -1)
                  (match &sk_keys ($ph $pk) (if (sk-needed? $ph $pk) true (empty)))
                  (match &sk_row ($ph $pk $pr (sk-row $_pi $_pc $pp $_ps))
                     (if (sk-needed? $ph $pk) (if (sk-readable-row? $ph $pk $pp) true (empty)) (empty)))))))))))

;; A pass works off the rows never evaluated, the readers of the keys changed
;; outside evaluation, the stale rows a need brought current (forced by their
;; own keys) and the items given. Then the implication instance folds whose
;; members changed are brought current, in further passes, and the last pass
;; is returned.
(: sk-evaluate-pass! (-[semidet]-> Number (List SkeletonItem) Number))
(= (sk-evaluate-pass! $pass $items)
   (let* (($new (collapse (match &ctx_sk_new (sk-row-item $seq $hash $key $rhash $row)
             (sk-row-item $seq $hash $key $rhash $row))))
          ($_new (remove-data-rows! &sk_new (quote (sk-row-item $nseq $nhash $nkey $nrhash $nrow))))
          ($dirty (collapse (match &ctx_sk_dirty ($dhash $dkey) $dkey)))
          ($_dirty (remove-data-rows! &sk_dirty (quote ($ddhash $ddkey))))
          ($refresh
             (collapse (match &ctx_sk_refresh ($khash $rhash)
                (let $_taken (context-remove! &sk_refresh ($khash $rhash))
                   (let* (($item (sk-row-item-at $khash $rhash))
                          ($_forced (sk-force! (cons $khash ()) $item)))
                      $item)))))
          ($seeded
             (fold-semidet (sk-dirty-seed $pass)
                (sk-work (fold-semidet (sk-seed-new $pass) (empty_heap) (append-flat $new (append-flat $refresh $items)))
                   (empty_heap))
                $dirty))
          ($last (sk-work-off! $pass $seeded)))
      (case (sk-instance-checks!) (
         (() $last)
         ($checks (sk-evaluate-pass! (+ $last 1) $checks))))))

;; An evaluation brings current every implication instance fold that rows read,
;; has a view and has members still to take, with the keys reading it, a refined rule's
;; truth above all, whoever needs them: those keys are needed as roots are, the
;; members to take beside them, and the fold is checked once the members are
;; computed. So a new instance moves its rule's truth, and the search score
;; read from it, at the evaluation after it is stored, without a query asking
;; for the truth, at the cost of the members that changed. A fold nobody read
;; takes all its members when first read. Each fold is brought current once
;; per evaluation; what changes after that, the fold now needed, is checked as
;; any needed fold is, and a member whose rows the evaluation could not compute
;; waits for the next one.
(: sk-instance-checks! (-[semidet]-> (List SkeletonItem)))
(= (sk-instance-checks!)
   (fold-semidet sk-instance-check-step ()
      (collapse (match &ctx_sk_instance_changed ($hash $fold)
         (if (space-row-present? &ctx_sk_instance_checked ($hash)) (empty)
            (let* (($_taken (context-remove! &sk_instance_changed ($hash $fold)))
                   ($_checked (context-add! &sk_instance_checked ($hash))))
               ($hash $fold)))))))

(: sk-fold-reader-key-step (-[det]-> (List SkeletonKey) (Number Number) (List SkeletonKey)))
(= (sk-fold-reader-key-step $keys ($khash $rhash))
   (append-flat (collapse (match &sk_row ($khash $key $rhash $_row) $key)) $keys))

(: sk-instance-check-step (-[semidet]-> (List SkeletonItem) (Number SkeletonKey) (List SkeletonItem)))
(= (sk-instance-check-step $checks ($hash $fold))
   (let* (($members (sk-rate-changed $hash $fold))
          ($readers
             (collapse (superpose (
                (match &ctx_sk_reader ($hash $stored-r $khash $rhash) (if (=alpha $stored-r $fold) ($khash $rhash) (empty)))
                (match &ctx_sk_stale_reader ($hash $stored-s $skhash $srhash) (if (=alpha $stored-s $fold) ($skhash $srhash) (empty))))))))
      (if (if (== $members ()) true (if (== $readers ()) true (== (sk-latest-view $hash $fold 0) sk-none))) $checks
         (let* (($_readers (sk-need-closer! 0 (alpha_unique_keys (fold-flat sk-fold-reader-key-step () $readers))))
                ($_fold (sk-need-closer! 1 (cons $fold ())))
                ($_members (sk-need-closer! 2 $members))
                ($_causes (foreach-flat (sk-fold-pending! $hash) (map-flat index-hash $members))))
            (cons (sk-fold-check $hash $fold) $checks)))))

;; Keys needed again at a depth closer to a root than they were, so their
;; rows are computed in full and their stale rows brought current.
(: sk-unneed-deeper! (-[det]-> Number Atom SkeletonKey Atom))
(= (sk-unneed-deeper! $depth $_acc $key)
   (let* (($hash (index-hash $key))
          ($_dropped
             (collapse (match &sk_needed ($hash $stored $was)
                (if (=alpha $stored $key) (if (> $was $depth) (remove-atom &sk_needed ($hash $stored $was)) (empty)) (empty))))))
      ()))

(: sk-need-closer! (-[semidet]-> Number (List SkeletonKey) Atom))
(= (sk-need-closer! $depth $keys)
   (let $_unneeded (fold-flat (sk-unneed-deeper! $depth) () $keys) (sk-need-keys! $depth $keys)))

(: sk-fold-pending! (-[det]-> Number Number Atom))
(= (sk-fold-pending! $hash $cause) (context-add! &sk_fold_pending ($hash $cause)))

;; Waiting targets get turns nearest a root first, then by estimated cost,
;; then oldest. Actual conditioned rows spend the remaining allowance as
;; they run; no estimate gates admission. Each target gets at most one
;; ordinary turn per evaluation, and an exhausted target stays pending.
(: SkeletonWaiting Type)
(: sk-row-waiting (-[det]-> SkeletonItem SkeletonWaiting))
(: sk-key-waiting (-[det]-> Number SkeletonKey SkeletonWaiting))
(: SkeletonClaim Type)
(: sk-claim (-[det]-> Number Number Number SkeletonWaiting SkeletonClaim))

(: sk-order-claims (-[det]-> (List SkeletonClaim) (List SkeletonClaim)))

(: sk-pay-conditions! (-[semidet]-> Number Atom))
(= (sk-pay-conditions! $pass)
   (case (sk-order-claims
            (append-flat
               (collapse (match &ctx_sk_given_pending ($khash $rhash $cost)
                  (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
                     (if (if (sk-needed? $khash $key)
                              (if (sk-readable-row? $khash $key $premises)
                                 (not (space-row-present? &ctx_sk_given_granted ($khash $rhash))) false) false)
                        (sk-claim (sk-need-depth $khash $key) $cost $seq
                           (sk-row-waiting (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq))))
                        (empty)))))
               (collapse (match &ctx_sk_given_pending ($khash -1 $cost)
                  (match &sk_keys ($khash $key)
                     (if (if (sk-needed? $khash $key) (not (space-row-present? &ctx_sk_given_granted ($khash -1))) false)
                        (sk-claim (sk-need-depth $khash $key) $cost -1 (sk-key-waiting $khash $key))
                        (empty))))))) (
      (() (sk-finish-branches! $pass))
      ((cons (sk-claim $_depth $_claim-cost $_seq $waiting) $_rest)
         (let $left (search-id-value sk_eval_budget)
            (if (< $left 1)
               (sk-finish-branches! $pass)
               (let $last (sk-pay! $pass $waiting)
                  (sk-pay-conditions! (+ $last 1)))))))))

;; Root merges and conditioning can discover misses after the row heap ends.
;; Give those requests the same last tier, within its remaining fixed share.
(= (sk-finish-branches! $pass)
   (if (sk-build-wanted!)
      (let* (($last (sk-work-off! $pass (sk-work (empty_heap) (empty_heap))))
             ($_roots (sk-read-roots!)))
         (sk-pay-conditions! (+ $last 1)))
      ()))

(: sk-pay! (-[semidet]-> Number SkeletonWaiting Number))
(= (sk-pay! $pass (sk-row-waiting (sk-row-item $seq $hash $key $rhash $row)))
   (let* (($item (sk-row-item $seq $hash $key $rhash $row))
          ($_taken (remove-data-rows! &sk_given_pending (quote ($hash $rhash $_was))))
          ($_granted (context-add! &sk_given_granted ($hash $rhash)))
          ($_forced (sk-force! (cons $hash ()) $item)))
      (sk-work-off! $pass (sk-work (add_to_heap (empty_heap) (sk-item-order $item) $item) (empty_heap)))))
;; A paid key drops its merged value, which its readers then read conditioned.
;; Branches pay their own conditioning; this grant changes no branch input.
(= (sk-pay! $pass (sk-key-waiting $hash $key))
   (let* (($_granted (context-add! &sk_given_granted ($hash -1)))
          ($_merged (sk-drop-merged! $key)))
      (sk-work-off! $pass
         (sk-key-changed $pass -1 (sk-outside-change (cons $hash ()) 0) (sk-work (empty_heap) (empty_heap)) $key))))

;; The roots' merged values are read before conditions are paid, so a root
;; whose views overlap is conditioned in its own query.
(: sk-read-roots! (-[semidet]-> Atom))
(= (sk-read-roots!)
   (let $_read
         (collapse (match &sk_needed ($hash $key 0)
            (case $key (
               ((sk-key $_type $_kbctx) (sk-open-value $hash $key sk-any-filter))
               ($_fold (empty))))))
      ()))

;; --- Base-rate API ----------------------------------------------------------

;; Setting or clearing a user base rate changes the folds over its pattern,
;; which recompute with their readers at the next evaluation.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $pattern $tv)
   (let* (($_valid (validate-base-rate! $pattern (conjunct-parts (implication-side-conjuncts $pattern))))
          ($stored (copy_term $pattern))
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
    conditions-unpaid branch-cache-hits branch-cache-misses branch-builds branch-cache-refreshes))

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
               (let* (($prior (configured-population-prior-tv (brand KB (car-atom $args)) (brand Statement (car-atom (cdr-atom $args))) (STV $s $c)))
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
(: sk-root-results (-[semidet]-> Bool SkPattern (List RuntimeResult)))
(= (sk-root-results $materialize? $goal)
   (let* (($values (sk-root-values $goal))
          ($_materialized
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
   (let* (($_branch-frame (change-state! sk_branch_at 0))
          ($_branch-cuts (remove-data-rows! &sk_branch_cuts (quote ($_frame $_exclude $_cuts))))
          ($_branch-reader (remove-data-rows! &sk_reading (quote ($_hash $_key $_row))))
          ($goals (map-flat context-search-goal $requested))
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
          ($_branches (change-state! sk_branch_budget (* (* (sk-evaluation-per-step) $steps) (sk-branch-share))))
          ($_walk (change-state! sk_walk_budget (* (sk-walk-per-step) $steps)))
          ($_pushes (change-state! sk_push_seq 0))
          ($_context-start (context-start!))
          ($_search (sk-walk! $goals))
          ($_world-invalidated (sk-invalidate-world!))
          ($_unneeded (remove-data-rows! &sk_needed (quote ($hash $key $depth))))
          ($_reserve (change-state! sk_near_reserve 0))
          ($_needed (sk-need-roots! (fold-semidet sk-root-keys-step () $goals)))
          ($context-reserve (search-id-value sk_near_reserve))
          ($_holding (change-state! sk_holding 1))
          ($_evaluated (sk-evaluate!))
          ($_inferred (inference-add! $started))
          ($main-results (map-semidet (sk-root-results $materialize?) $goals))
          ($_held (sk-stale-held!))
          ;; Keep the entire visited path while any of its world refreshes
          ;; remains unpaid. Current ancestors must still lead the next need
          ;; to deeper debt; they do not need another computation themselves.
          ($world-unpaid (not (== (collapse (once (match &sk_world_done ($wh $wr)
             (if (if (space-row-present? &ctx_sk_stale ($wh $wr)) true
                     (space-row-present? &ctx_sk_given_pending ($wh $wr $_cost))) true (empty))))) ())))
          ($_world-done (collapse (match &sk_world_done ($wkhash $wrhash)
             (let $_taken (remove-atom &sk_world_done ($wkhash $wrhash))
                (if $world-unpaid () (remove-atom &sk_world_stale ($wkhash $wrhash)))))))
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
