;; Leaf values, proof metadata, merge formulas and reference classes.
;; These helpers never invoke the recursive value reader.
;; Evaluation over the skeleton and the public backward entry points.
;;
;; Every row keeps the versions of its view: its conclusion computed by the
;; rule's formulas from its premises' values, with the evidence behind it and
;; the hashes of the keys it depends on. A key's value merges its leaf facts
;; and one version per row; overlapping evidence resolves by dominance and
;; disjoint evidence revises.
;;
;; A premise reads, per row of its key, the latest version that depends
;; neither on the reading row's own conclusion key nor on a key unifying with
;; it. Dependency sets are transitive, so no value supports itself, through
;; inverted rules, longer cycles, or a more general or more specific key.
;; Views are computed in the order rows were created and refreshed while
;; support grows; they persist until something below them changes.

;; --- Leaves -----------------------------------------------------------------

;; A borrowed observation retains its MAIN evidence and dependency identity.
(: sk-leaf-source (-[det]-> SkFact SkFact))
(= (sk-leaf-source ($type ($kbid $ctx $vars) $proof $tv))
   (let* (($kb (make-kb-context (brand KB $kbid) $ctx $vars))
          ($main (kbctx (brand KB $kbid)))
          ($source (if (if (== $ctx MAIN) true (assumption-proof? $proof)) $kb
                      (if (kb-fact-present? (data $type $main $proof $tv)) $main $kb))))
      (data $type $source $proof $tv)))

;; A hypothetical context's assumptions carry no empirical evidence. An Assuming
;; fact, the value of a MAIN key in the query's world `(ctx proof C ...)`, is
;; the fact the overlay stores in C: evidence with an identity of its own, as
;; the same fact stored in the knowledge base would be, so views reading it
;; are not independent (#143).
(: leaf-evidence-for-result (-[det]-> SkFact EvidenceSet))
(= (leaf-evidence-for-result ($type ($kbid $ctx $vars) $proof $tv))
   (if (assumption-proof? $proof)
      (if (== $ctx MAIN)
         (evidence-set (cons (fact-evidence-entry
            (make-kb-context (brand KB $kbid) (car-atom (cdr-atom (cdr-atom $proof))) $vars) $proof $type) ()))
         (ev-set 0))
      (let ($source-type $source-kb $source-proof $_source-tv)
         (sk-leaf-source (data $type (make-kb-context (brand KB $kbid) $ctx $vars) $proof $tv))
         (evidence-set (cons (fact-evidence-entry $source-kb $source-proof $source-type) ())))))

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

(: sk-read-value (-[det]-> SkeletonFilter SkeletonValue SkeletonValue))
(= (sk-read-value $filter $value)
   (case $value (
      ((sk-val $fact $ev $deps) (sk-val (sk-read-fact $filter $fact) $ev $deps))
      ($_other $value))))

;; A stored fact is its own evidence and depends on its own key. The fact a
;; forward run stored for a key carries its value's evidence and what that value
;; was derived through (see sk-forward-store!), and a frozen key's summary its
;; value's evidence and the keys near it (forgetting.metta). Ordinary fact
;; leaves keep their exact source evidence beside the inline proof: a later
;; signed proof walk must never rebuild a scoped fact from its name alone.
(: sk-leaf-view (-[det]-> Number SkFact SkeletonValue))
(= (sk-leaf-view $hash ($type $scope $proof $tv))
   (let $fact (data $type $scope $proof $tv)
   (case (collapse (once (match &sk_forward_stored ($hash $_key $source $ev $deps)
      (let $read (sk-read-value (sk-filter $proof $tv) (sk-val $source $ev $deps))
         (if (== $read (sk-val $fact $ev $deps)) $read (empty)))))) (
      ((cons $stored $_rest) $stored)
      (() (case (collapse (once (match &sk_summary ($hash $_skey $summary-source $sev $sdeps)
         (let $read-summary (sk-read-value (sk-filter $proof $tv) (sk-val $summary-source $sev $sdeps))
            (if (== $read-summary (sk-val $fact $sev $sdeps)) $read-summary (empty)))))) (
             ((cons $summary $_more) $summary)
             (() (let* (($ev (leaf-evidence-for-result $fact))
                         ($scoped (case (evidence-entries $ev) (
                            (((fact-ev $_source-scope $source-proof $_source-type))
                               (assemble-runtime-fact $type $scope
                                  (fact-source $ev $source-proof) $tv))
                            (((not-fact-ev $_negative-scope $negative-source $_negative-type))
                               (assemble-runtime-fact $type $scope
                                  (fact-source $ev (negated $negative-source)) $tv))
                            ($_other $fact)))))
                      (sk-val $scoped $ev (sk-leaf-deps $hash $fact)))))))))))

;; A frozen key's summary stands for its past, so it counts as a fact: kept
;; beside the rows the key gets later.
(: sk-summary-fact? (-[det]-> SkFact Bool))
(= (sk-summary-fact? ($_type $_kbctx $proof $_tv))
   (case $proof (((forgotten $_hash $_epoch) true) ($_other false))))

;; The fact a forward run stored for a key is a copy of the key's own value: it
;; lets a reader reach the key without searching for it, and stands for the
;; value only while the key has no computed versions; a frozen key's summary
;; stands beside them. A reader that must not depend on what either was
;; derived through leaves it out.
;; Direct facts depend on their key too: a closed re-read may reach a fact
;; whose key an outer reader excluded, even though no ordinary row can use it.
(: sk-leaf-step (-[semidet]-> Number Bool (List Number) (List SkeletonValue) SkFact (List SkeletonValue)))
(= (sk-leaf-step $hash $computed $exclude $kept $fact)
   (let* (($view (sk-leaf-view $hash $fact)) ($deps (sk-view-deps-step 0 $view)))
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
(= (sk-link-var $link $s $c) (let $q (sk-link-slope $link $s) (/ (ideal-var $s $c) (* $q $q))))

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

(: sk-own-prior-update (-[det]-> Proof TV SkeletonPriorUpdate))
(= (sk-own-prior-update $proof $tv)
   (let $read (population-prior-tv $tv) (sk-prior-update $proof (brand Proof (prior $read)) ())))

(: sk-prior-update-of (-[det]-> KB Proof TV SkeletonPriorUpdate))
(= (sk-prior-update-of $kb $proof $tv)
   (case (sk-step-proof $proof) (
      (((inverted $_rule with $prior (prior $prior-tv)) $_observation)
         (sk-prior-update $prior (brand Proof (prior $prior-tv)) (cons $proof ())))
      (((antecedent-completion $_completed $_idx with $completion-prior (prior $completion-prior-tv)) $_known)
         (sk-prior-update $completion-prior (brand Proof (prior $completion-prior-tv)) (cons $proof ())))
      (((reported with $prior (prior $prior-tv)) $_report)
         (sk-prior-update $prior (brand Proof (prior $prior-tv)) (cons $proof ())))
      ((factored-revision $prior $prior-tv $parts) (sk-prior-update $prior $prior-tv $parts))
      ((by $rule $premise)
         (if (if (head-is? $premise conjunction) false (equivalence-rule? $kb (brand Proof $rule)))
            (case (sk-prior-update-of $kb (brand Proof $premise) $tv) (
               ((sk-prior-update $_own-source $_own-read ()) (sk-own-prior-update $proof $tv))
               ((sk-prior-update $moved $moved-tv $_moved) (sk-prior-update $moved $moved-tv (cons $proof ())))))
            (sk-own-prior-update $proof $tv)))
      ($_other (sk-own-prior-update $proof $tv)))))

;; An impossible likelihood rules the target out even if the remaining
;; estimate shares evidence. Keep its confidence; shared evidence buys none.
(: sk-zero-update? (-[det]-> SkFact SkFact Bool))
(= (sk-zero-update? ($_type $_scope $proof $_tv) ($_ot $_os $_op $other-tv))
   (if (proof-zero-likelihood? $proof)
      (case $other-tv (((STV $s $_c) (not (sk-contradict? 0 (the Number $s)))) ($_other false)))
      false))

;; The prior an observation's value was formed under, for an inversion or a
;; completion that reads the value as a likelihood ratio over it
;; (ObservationRatioFormula): the prior a view updates, so only its updates
;; count. A view updating nothing is a value of its own, read under the prior
;; the inversion implies, as modus ponens reads it, except:
;; - an unfounded value is a closed read's pin, the reading conclusion taken
;;   false to cut its circular support (docs/metta/complete_predicates.md): a
;;   hypothesis, not an observation, so nothing is inferred from it;
;; - a stage (stage-statement?, prolog/sorts.pl) gets evidence from below
;;   only (#122): its consequence's reports and assumptions count, a forward
;;   prediction does not. An aggregate keeps PLN induction and abduction.
(: sk-observation-prior (-[semidet]-> KB Proof TV Bool TV))
(= (sk-observation-prior $kb $proof $tv $stage)
   (if (== (sk-step-proof $proof) unfounded) (empty)
      (case (sk-prior-update-of $kb $proof $tv) (
         ((sk-prior-update $_prior $_own ())
            (if $stage (if (sk-observed? $proof) no-evidence (empty)) no-evidence))
         ((sk-prior-update $_prior (prior $prior-tv) $_parts) (the TV $prior-tv))))))

;; Leave-one-out branch centres require actual source support. Unknown or
;; shared support gives the structural neutral centre, never a self-pool.
(: likelihood-centres (-[det]-> CTVType SupportCounts CTVType))
(= (likelihood-centres (CTV $positive $negative) (support-counts $_total $pos $neg $bad $overlap))
   (if (if (> $pos 0) (if (> $neg 0) (if (== $bad 0) (== $overlap 0) false) false) false)
      (CTV $negative $positive) (CTV (STV 0.5 1) (STV 0.5 1))))
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
;; Neither operation interns or walks a population-sized evidence set. A
;; compound's centre is admissible when the folds deciding it are: those its
;; search reads (compound-rate-goals).
(: sk-admissible-step (-[semidet]-> SourceList Bool SkPattern Bool))
(= (sk-admissible-step $sources $admissible $goal)
   (if $admissible
      (case $goal (
         ((CPU FoldAllCompiled $args $_res)
            (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_out)) (
               ((cons (fa-subscription $identity $_descriptor $_triggers) ())
                  (case (collapse (fa-id $identity)) (
                     ((cons $id $_more) (likelihood-support-admissible? (quote (aggregate-support $id)) $sources))
                     (() false))))
               ($_none false))))
         ((CPU CompoundRate $inner $_rate) (fold-semidet (sk-admissible-step $sources) true (compound-rate-goals $inner true $_inner)))
         ($_formula true)))
      false))

;; A connective's own evidence for the completions of its parts (#142): its
;; key K's value without the views that depend on K's parts or on the
;; consequence C (the rule's inversion onto K reads C), and no value when K has
;; no such view, which is a value too: K uses the key (&sk_use), so each change
;; of K checks it again, and its readers change only with it (a change of K's
;; producer, whose views it excludes, wakes no completion). The value carries
;; K's evidence and dependencies, and the prior it was formed under
;; (sk-observation-prior). A reader excluding keys it depends on gets it
;; computed again without them.
;;
;; K's producer, settling and inversion rows read a part or C. K has a view
;; apart from them only by a stored fact or one of the rows reading neither,
;; which the key needs (sk-need-below!) and is read only then, since every
;; change of a part changes K.
;; The evidence read excludes K's parts and C, besides what its reader excludes.
;; A node row's sibling read (cavity K target) excludes K itself, not its
;; parts (the sibling is one), and the target with its parts.
(: sk-evidence-apart (-[det]-> $spec (List Number) (List Number)))
(= (sk-evidence-apart ($_kb $ktype $ctype $kbctx) $exclude)
   (hash-set (foldr-flat (sk-part-exclusions (the KBContext $kbctx)) $exclude
      (case $ctype (
         ((cavity $compound $target) (cons $compound (sk-statement-parts (the (List Atom) (cons $target ())))))
         ($_consequence (sk-statement-parts (cons $ctype (the (List Atom) (cdr-atom $ktype))))))))))

(: sk-evidence-rows (-[semidet]-> $spec (List SkeletonItem)))
(= (sk-evidence-rows $args)
   (let* ((($_kb $ktype $_ctype $kbctx) $args)
          ($compound (sk-key $ktype $kbctx))
          ($khash (index-hash $compound))
          ($apart (sk-evidence-apart $args ())))
      (collapse (match &sk_row ($khash $stored $rhash (sk-row $ident $concl $premises $seq))
         (if (=alpha $stored $compound)
            (if (sk-excludes? $apart
                   (deps-join (map-flat deps-key (map-semidet index-hash (fold-semidet sk-direct-key-step () $premises)))))
               (empty)
               (sk-row-item $seq $khash $stored $rhash (sk-row $ident $concl $premises $seq)))
            (empty))))))

;; The forward conclusions a view combines: a rule application is one, a
;; combination of forward views (docs/metta/combination_modes.md) its parts.
(: sk-forward-parts (-[det]-> Proof (List Proof)))
(= (sk-forward-parts $proof)
   (let $step (sk-step-proof $proof)
      (if (rule-application-proof? $step) (cons $proof ())
         (case $step (
            ((combination $mode $_combination-prior $parts)
               (if (== $mode revision) (cons $proof ()) (proof-children $parts)))
            ((merge/revision $left $right) (sk-pair-parts $proof $left $right))
            ((conditioned $_weight $yes $no) (sk-pair-parts $proof $yes $no))
            ((specializes $_specific $_general $_raw $_prior-tv) (cons $proof ()))
            ($_other ()))))))
(: sk-pair-parts (-[det]-> Proof Atom Atom (List Proof)))

;; A revision or a conditioning of two views combines forward views when both do.
(= (sk-pair-parts $proof $left $right)
   (let* (($left-parts (sk-forward-parts (brand Proof $left)))
          ($right-parts (sk-forward-parts (brand Proof $right))))
      (if (if (== $left-parts ()) true (== $right-parts ())) () (cons $proof ()))))

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
;; Stored reports describe the instance's evidence, while an independent
;; forward view predicts it. Revise reports first, then apply their
;; likelihood once (sk-report-merge).
(: sk-report-proof? (-[det]-> Proof Bool))
(= (sk-report-proof? $proof)
   (case $proof (
      ((fact-source $_ev $_source) true)
      ($_other (case (sk-step-proof $proof) (
         ((merge/revision $left $right)
            (if (sk-report-proof? (brand Proof $left)) (sk-report-proof? (brand Proof $right)) false))
         ($_derived false)))))))

;; An observation of a consequent: its stored reports, an assumption, or for a
;; compound consequent, an observation of every part.
(: sk-observed? (-[det]-> Proof Bool))
(= (sk-observed? $proof)
   (case (sk-step-proof $proof) (
      ((cons conjunction $parts) (fold-flat sk-observed-step true (proof-children $parts)))
      ($step (if (assumption-proof? $step) true (sk-report-proof? $proof))))))
(: sk-observed-step (-[det]-> Bool Proof Bool))
(= (sk-observed-step $seen $part) (if $seen (sk-observed? $part) false))

(: sk-report-prior? (-[det]-> Proof Bool))
(= (sk-report-prior? $proof)
   (if (== (sk-forward-parts $proof) ())
      (case (sk-step-proof $proof) (
         ((factored-revision $prior $_tv $_parts) (sk-report-prior? (brand Proof $prior)))
         ((merge/revision $left $right)
            (if (sk-report-prior? (brand Proof $left)) true (sk-report-prior? (brand Proof $right))))
         ($step (head-is? $step forgotten))))
      true))

;; A stored report below confidence 1 is a likelihood over the instance's
;; independent prediction (B2, Pearl), not a posterior calibrated against a
;; population: O(post) = O(prediction) O(s), no base rate entering. A report
;; of strength 0 or 1 is an observation: the prediction's value does not move
;; it, and it keeps the revised reports' confidence.
(: sk-report-merge (-[det]-> SkFact EvidenceSet Number SkFact EvidenceSet Number SkeletonValue))
(= (sk-report-merge $fact $ev $deps $prior $pev $pdeps)
   (case (collapse (once
         (let* ((($type ($kb $ctx $vars) $report (STV $s $c)) $fact)
                (($_type $_scope $prediction (STV $sp $cp)) $prior)
                ($endpoint (if (<= $s 0.0) true (>= $s 1.0)))
                ;; An endpoint report is the lambda = (1, 0) case: conditioning,
                ;; whatever the prior's value (#115). Retain the prior's
                ;; support below: conditioning still needs it. The update's
                ;; neutral prior is the base an inversion reads the report
                ;; under (sk-prior-update-of).
                ($tv (if $endpoint (STV $s $c)
                        (let (STV $posterior $confidence) (sk-factored-tv odds $sp $cp 0.5 1 $sp $cp $s $c)
                           (STV (if (<= $sp 0.0) 0.0 (if (>= $sp 1.0) 1.0 $posterior)) $confidence))))
                ($update (brand Proof ((reported with cpu (prior (STV 0.5 0.0))) $report))))
            (sk-val ($type ($kb $ctx $vars)
                        (brand Proof (factored-revision $prediction (prior (STV $sp $cp)) ($update)))
                        $tv)
               (evidence-union $ev $pev) (deps-union $deps $pdeps))))) (
      ((cons $merged ()) $merged)
      (() sk-none))))

;; A compound's message or update to a part that an antecedent completion of
;; the part already counts (#142): the completion's prior was formed under the
;; compound's evidence, its proof or the base its value revised, and the
;; message would count it again. A revision or a factored update counts what
;; any of its views counts.
(: sk-message-counted? (-[det]-> Proof Proof Bool))
(= (sk-message-counted? $message $view)
   (case (sk-step-proof $view) (
      (((antecedent-completion $_rule $_idx with $formed $_prior) $_parts)
         (case (sk-step-proof $message) (
            ((node-message $_m-idx $source $_tokens $_likelihood) (sk-source-from? $source (brand Proof $formed)))
            (((node-jeffrey $_j-idx $j-source $_prediction $_conditionals) $_j-parts) (sk-source-from? $j-source (brand Proof $formed)))
            ($_other false))))
      ((merge/revision $left $right)
         (if (sk-message-counted? $message (brand Proof $left)) true (sk-message-counted? $message (brand Proof $right))))
      ((factored-revision $base $_prior $parts)
         (if (sk-message-counted? $message (brand Proof $base)) true
            (fold-flat (sk-counted-step $message) false (the (List Atom) $parts))))
      ($_view false))))

(: sk-counted-step (-[det]-> Proof Bool Atom Bool))
(= (sk-counted-step $message $found $view) (if $found true (sk-message-counted? $message (brand Proof $view))))

(: sk-source-from? (-[det]-> Atom Proof Bool))
(= (sk-source-from? $source $base)
   (if (same-proof? (brand Proof $source) $base) true
      (case (sk-step-proof (brand Proof $source)) (
         ((factored-revision $revised $_prior $_parts) (same-proof? (brand Proof $revised) $base))
         ($_other false)))))

(: sk-factored-merge
   (-[det]-> SkFact EvidenceSet Number SkFact EvidenceSet Number Bool SkeletonValue))
(= (sk-factored-merge ($type $kbctx $proof-a $tv-a) $ev-a $deps-a ($btype $bkbctx $proof-b $tv-b) $ev-b $deps-b $independent)
   (if (if $independent (if (sk-report-proof? $proof-a) (sk-report-prior? $proof-b) false) false)
      (sk-report-merge (data $type $kbctx $proof-a $tv-a) $ev-a $deps-a
         (data $btype $bkbctx $proof-b $tv-b) $ev-b $deps-b)
      (if (if $independent (if (sk-report-proof? $proof-b) (sk-report-prior? $proof-a) false) false)
         (sk-report-merge (data $btype $bkbctx $proof-b $tv-b) $ev-b $deps-b
            (data $type $kbctx $proof-a $tv-a) $ev-a $deps-a)
         (case (let $kb (brand KB (car-atom $kbctx)) (data (sk-prior-update-of $kb $proof-a $tv-a) (sk-prior-update-of $kb $proof-b $tv-b) $tv-a $tv-b)) (
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
            ($_other sk-none))))))

(: sk-disjoint-view-step (-[semidet]-> Atom SkeletonValue Atom))
(= (sk-disjoint-view-step ($tvs $seen) (sk-val ($_type $_ctx $_proof $tv) $ev $_deps))
   (if (evidence-overlap? (the EvidenceSet $ev) (the EvidenceSet $seen)) (empty) (data (cons $tv $tvs) (evidence-union $ev $seen))))

(: sk-mode-step (-[semidet]-> Atom STVType STVType STVType STVType))
(= (sk-mode-step $mode (STV $sp $cp) (STV $sa $ca) (STV $sb $cb)) (sk-factored-tv $mode $sp $cp $sp $cp $sa $ca $sb $cb))

;; The log probability a prediction gave an outcome.
(: sk-log-score (-[det]-> Number STVType Number))
(= (sk-log-score $outcome (STV $s $_c))
   (let $q (ideal-clip $s)
      (+ (* $outcome (log-math 2.718281828459045 $q)) (* (- 1.0 $outcome) (log-math 2.718281828459045 (- 1.0 $q))))))

;; A statement is known when a stored fact gives it strength 0 or 1 at
;; confidence 1, or when every view its rows have does. A shared statement is
;; read off its stored facts and its rows' latest views, never by merging it:
;; its merge may read the very key being merged. Stored facts supply their
;; statement's probability: it ranks by their spread, depending on its own
;; key, as its rules' views are updates its weight keeps only apart from the
;; branches (sk-mix-on). A rule's truth is no
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
         (if (== $leaves ())
            (let $deps (fold-semidet sk-view-deps-step (deps-key $hash) $views)
               (cons (sk-shared-key (- 0 (deps-size $deps)) $key $deps (fold-semidet sk-view-spread-step 0 $views) false)
                  $found))
            (cons (sk-shared-key -1 $key (deps-key $hash) (fold-semidet sk-leaf-spread-step 0 $leaves) true) $found))))))

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
(= (sk-shared-rank (sk-shared-key $size $key $_deps $spread $_source)) (sk-ranked (* $spread (- $size 1)) $key))

(: sk-ranked-key (-[det]-> SkeletonRanked SkeletonKey))
(= (sk-ranked-key (sk-ranked $_impact $key)) $key)

(: sk-shared-hash-step (-[semidet]-> (List Number) (List SkeletonShared) Number (List SkeletonShared)))
(= (sk-shared-hash-step $ignore $found $hash)
   (if (stored-list-member? $hash $ignore) $found
      (fold-semidet sk-shared-candidate $found (collapse (match &sk_keys ($hash $key) $key)))))

(: sk-below-step (-[det]-> Number Bool SkeletonShared Bool))
(= (sk-below-step $hash $found (sk-shared-key $_size $_key $deps $_spread $_source)) (if $found true (deps-has? $deps $hash)))

(: sk-frontier-step (-[semidet]-> Bool (List SkeletonShared) SkeletonShared (List SkeletonShared)))
(= (sk-frontier-step $group $kept $shared)
   (case $shared (
      ((sk-shared-key $_size $key $_deps $_spread $source)
         (if (== $source $group)
            (if (fold-flat (sk-below-step (index-hash $key)) false $kept) $kept (cons $shared $kept))
            $kept)))))

;; The shared statements, among the keys of the hashes less the ignored ones,
;; whose value is uncertain: first the ones no other one depends on (the
;; largest dependency set decides first), those stored facts supply before
;; derived ones, then the others, each group the most impact first. A stored
;; fact depends on its own key, and a fold is no statement. A stored
;; statement's weight leaves out the views that share the branches' evidence,
;; so its mix is not refused after both branches were paid; a derived one's
;; can be (#94).
(: sk-shared-statements (-[semidet]-> (List Number) (List Number) (List SkeletonKey)))
(= (sk-shared-statements $ignore $hashes)
   (let* (($candidates (sort-atom (fold-semidet (sk-shared-hash-step $ignore) () $hashes)))
          ($sources (fold-semidet (sk-frontier-step true) () $candidates))
          ($frontier (fold-semidet (sk-frontier-step false) () $candidates))
          ($below (fold-semidet (sk-below-frontier-step (append-flat $sources $frontier)) () $candidates)))
      (append-flat (sk-ranked-statements $sources)
         (append-flat (sk-ranked-statements $frontier) (sk-ranked-statements $below)))))

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
;; members as data, and compiler-marked joins share their sources by design.
(: sk-entangle (-[semidet]-> (List Number) SkeletonRowState SkeletonRowState))
(= (sk-entangle $ignore $state)
   (case $state (
      ((sk-acc () $_ev $deps)
         (case (sk-shared-statements $ignore (deps-entangled $deps)) (
            (() $state)
            ($keys (sk-entangled $keys (+ 1 (deps-size (deps-join $deps))) $state)))))
      ($_other $state))))

;; A compound among a cut's statements is followed by its parts: what reads
;; several parts of one compound reads them jointly, each given the compound and
;; the parts before it (event-moment-node.md), so a branch never builds a joint
;; state the compound excludes.
;; A node row's sibling the condition gives is read at its given value.
(: sk-pinned-evidence (-[semidet]-> (List SkeletonGiven) $spec SkeletonValue))
(= (sk-pinned-evidence $given $args)
   (case $args (
      (($_kb $statement (cavity $_compound $_target) $kbctx)
         (case (fold-semidet (sk-pinned-step (sk-key $statement $kbctx)) () $given) (
            ((cons $pinned $_more) (sk-pinned-goal $args $pinned))
            ($_none sk-none))))
      ($_completion sk-none))))

(: sk-pinned-goal (-[semidet]-> $spec SkeletonValue SkeletonValue))
(= (sk-pinned-goal $args (sk-val ($_type $_kbctx $proof $tv) $ev $deps))
   (sk-goal-val (CPU CompoundEvidence $args (key-evidence $tv $tv $proof)) $proof $ev $deps))

;; A compound pin's parts, its children's keys; a pin that is no compound has
;; none. Parts are read under their pin only: a pin that cannot mix does not
;; make its parts pins of their own.
(: sk-pin-parts (-[semidet]-> SkeletonKey (List SkeletonKey)))
(= (sk-pin-parts $pin)
   (case $pin (
      ((sk-key $type $kbctx)
         (if (head-is-member? $type (And Or)) (map-semidet (sk-part-key $kbctx) (statement-children (cdr-atom $type))) ()))
      ($_fold ()))))

(: sk-part-key (-[semidet]-> KBContext Atom SkeletonKey))
(= (sk-part-key $kbctx $child) (let ($key $_odd) (canon (brand Statement $child)) (sk-key $key $kbctx)))

;; A certain fact both views observed, or a forward view's condition the other
;; observed (a cause that is also an effect, which only a loop allows, as a
;; symmetric relation's rule and its completion): given it they are
;; independent and revise, but a product would apply what it tells twice. In a
;; loop of complete predicates a cause read as given adds nothing the
;; observation does not (fuzzer seed 14000138), so there they stay independent.
;; A completion's sibling is a condition of its likelihood, not a cause, and
;; two views that both read the fact as a condition are independent
;; (evidence-observed-roles).

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
         (case (sk-truth-digests $deps) (((cons $one ()) (cons $one ())) ($_many ())))
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
         (once (let (fact-ev $ctx $proof $type) (evidence-proof-fact $ev $proof)
            (match &kb ($type $ctx $proof (STV $s $_c)) (data (implication-side-conjuncts (brand Statement $type)) $s true))))))))
(: sk-antecedent-step (-[semidet]-> EvidenceSet ((List Atom) Number Bool) Proof ((List Atom) Number Bool)))

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
                ;; An assumed rule is declared in its context's scope, its
                ;; applications in MAIN's; a rule name is unique in its KB.
                (() (let* (($kb (car-atom $ctx)) ($ctv (sk-rule-ctv (brand KB $kb) $rule)))
                       (once (match &kb ((Implication $declared $type) ($kb $_scope $_vars) $rule $ctv) $declared))))))))
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
            ((merge/revision $left $right) (sk-pair-reference $view $left $right))
            ((conditioned $_weight $yes $no) (sk-pair-reference $view $yes $no))
            ((combination $_mode $_combination-prior $parts)
               (sk-reference (sk-combined-class
                  (list_to_set (fold-semidet (sk-combined-condition-step $view) () (proof-children $parts)))) $view))
            ($_other (sk-reference no-class $view)))))
      ($_goal (sk-reference no-class $view)))))
(: sk-pair-reference (-[semidet]-> SkeletonValue Atom Atom SkeletonReference))

;; A revision or a conditioning of two views has their class when they agree.
(= (sk-pair-reference (sk-val ($type $ctx $proof $tv) $ev $deps) $left $right)
   (let* (((sk-reference $class-left $_left)
             (sk-reference-of (sk-val (assemble-runtime-fact $type $ctx (brand Proof $left) $tv) $ev $deps)))
          ((sk-reference $class-right $_right)
             (sk-reference-of (sk-val (assemble-runtime-fact $type $ctx (brand Proof $right) $tv) $ev $deps))))
      (sk-reference (if (=alpha $class-left $class-right) $class-left no-class) (sk-val ($type $ctx $proof $tv) $ev $deps))))

(: sk-contained? (-[det]-> SkeletonReference SkeletonReference Bool))
(= (sk-contained? $specific $general)
   (case (data $specific $general) (
      (((sk-reference (sk-class true $parts-a) $_a) (sk-reference (sk-class true $parts-b) $_b))
         (if (< (list-len $parts-b) (list-len $parts-a)) (all-members? $parts-a $parts-b) false))
      (((sk-reference (sk-class false $parts-a) $_a) (sk-reference (sk-class false $parts-b) $_b))
         (if (< (list-len $parts-a) (list-len $parts-b)) (all-members? $parts-b $parts-a) false))
      ($_other false))))

(: sk-outranked-step (-[semidet]-> SkeletonReference Bool SkeletonReference Bool))
(= (sk-outranked-step $view $found $other) (if $found true (sk-contained? $other $view)))

;; Only nearest strictly containing classes supply centres. Same-class
;; estimates have already been grouped; incomparable classes are a mixture.
(: sk-class-prior-step (-[semidet]-> SkeletonReference (List SkeletonReference) SkeletonReference (List SkeletonReference)))
(= (sk-class-prior-step $specific $prior $general)
   (if (sk-contained? $specific $general) (cons $general $prior) $prior))
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
(: sk-same-class-step (-[det]-> (List SkeletonClassGroup) SkeletonReference (List SkeletonClassGroup)))
(= (sk-same-class-step $groups (sk-reference $class $view))
   (case $groups (
      ((cons (sk-class-group $previous $views) $rest)
         (if (if (== $class no-class) false (=alpha $class $previous))
            (cons (sk-class-group $class (cons $view $views)) $rest)
            (cons (sk-class-group $class (cons $view ())) $groups)))
      (() (cons (sk-class-group $class (cons $view ())) ())))))

;; Views of one class revise into one, unless they share an uncertain
;; statement: then each stays a reference of its own, and the key's merge
;; conditions on what they share.
(: sk-class-view-step (-[det]-> ReferenceClass (List SkeletonReference) SkeletonValue (List SkeletonReference)))
(= (sk-class-view-step $class $kept $view) (append-flat $kept (cons (sk-reference $class $view) ())))

(: sk-report-prior-step (-[det]-> Bool SkeletonValue Bool))
(= (sk-report-prior-step $found $value)
   (if $found true
      (case $value (
         ((sk-val ($_type $_ctx $proof $_tv) $_ev $_deps) (sk-report-prior? $proof))
         ($_other false)))))

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
   (let* (((sk-reference $class-a $_a) $a) ((sk-reference $class-b $_b) $b))
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

;; Two estimates of one quantity, twins from the same samples or views with
;; equal recorded evidence: the larger count holds all of it. Also the
;; reference a discounted combination measures its range from.
(: sk-larger-count (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-larger-count $a $b)
   (case (data $a $b) (
      (((sk-val $fact-a $_ea $_da) (sk-val $fact-b $_eb $_db))
         (if (>= (term-confidence $fact-a) (term-confidence $fact-b)) $a $b))
      ($_other $a))))

(: sk-discounted (-[semidet]-> SkeletonValue SkeletonValue Number SkeletonValue))
(= (sk-discounted (sk-val ($type $kbctx $proof (STV $s $_c)) $ev $deps) (sk-val ($_rt $_rk $_rp (STV $r $_rc)) $_rev $_rdeps) $cmin)
   (let $range (max 1.0 (abs-math (- (sk-link odds $s) (sk-link odds $r))))
      (sk-val ($type $kbctx $proof (STV $s (/ $cmin (+ 1.0 (* $range $range))))) $ev $deps)))

;; Premises read as independent although they share an uncertain statement:
;; the dependence is unresolved, with no second estimate to bound it, so the
;; minimum log-odds range R = 1 discounts its confidence, c/(1+R^2).
(: sk-unresolved (-[det]-> SkeletonValue SkeletonValue))
(= (sk-unresolved $value)
   (case $value (
      ((sk-val ($type $kbctx $proof (STV $s $c)) $ev $deps)
         (sk-val (assemble-runtime-fact $type $kbctx $proof (STV $s (/ $c 2.0))) $ev $deps))
      ($_other $value))))

;; Connectivity needs existence, not a ranked conditioning cut. Stop at the
;; first uncertain shared statement instead of ranking every shared key.
(: sk-shared-statement-step (-[semidet]-> (List Number) Bool Number Bool))
(= (sk-shared-statement-step $ignore $found $hash)
   (if $found true (not (== (sk-shared-hash-step $ignore () $hash) ()))))

(: sk-updates? (-[semidet]-> SkeletonValue Bool))
(= (sk-updates? (sk-val ($_type $ctx $proof $tv) $_ev $_deps))
   (case (sk-prior-update-of (brand KB (car-atom $ctx)) $proof $tv) (((sk-prior-update $_prior $_own ()) false) ($_update true))))

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
   (let ($_type $_ctx $_proof (STV $s $c)) $_fact (sk-mode-step odds $prior $acc (STV $s $c))))

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
(: sk-family-reference-step (-[semidet]-> SkeletonValue (List SkeletonReference) Proof (List SkeletonReference)))
(= (sk-family-reference-step (sk-val ($type $ctx $_proof $tv) $ev $deps) $family $part)
   (append-flat $family (sk-family-references (sk-val ($type $ctx $part $tv) $ev $deps))))

(: sk-family-references (-[semidet]-> SkeletonValue (List SkeletonReference)))

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

;; The rule's CTV, when its conclusion is modus ponens over a conjunction (of
;; a statement, or of an implication, docs/metta/derived_implications.md).
;; An assumed rule's ContextRule premise only confines it to its context.
(: sk-rule-formula-step (-[semidet]-> (List CTVType) Atom (List CTVType)))
(= (sk-rule-formula-step $found $premise)
   (case $premise (
      ((CPU AndFormula $_and-args $_and-out) $found)
      ((CPU ContextRule $_rule-args $_rule-out) $found)
      ((CPU $mp ($_premise-tv $ctv) $_mp-out)
         (if (if (if (== $mp CTVModusPonensFormula) true (== $mp ImplicationModusPonensFormula)) (is-var $ctv) true) (empty)
            (case $ctv (((CTV $pos $neg) (cons (CTV $pos $neg) $found))))))
      ((CPU $_formula $_formula-args $_formula-out) (empty))
      ($_goal $found))))

(: sk-rule-ctv (-[semidet]-> KB Atom CTVType))
(= (sk-rule-ctv $kb $rule)
   (case (collapse (once (match rule_name_index ($rule $id)
            (match rules (runtime-rule-row $id ($_type ($kb $_ctx $_vars) (by $rule $_premise) $_tv) $premises)
               (fold-semidet sk-rule-formula-step () $premises))))) (
      ((cons (cons $ctv ()) $_rest) $ctv))))

(: sk-sibling-pair-step (-[semidet]-> SkeletonReference Bool SkeletonReference Bool))
(= (sk-sibling-pair-step $first $found $other)
   (if $found true (sk-reference-siblings? true $first $other)))

(: sk-sibling-values-step (-[semidet]-> (List SkeletonReference) Bool SkeletonReference Bool))
(= (sk-sibling-values-step $values $found $reference)
   (if $found true
      (let (sk-reference $class $_original) $reference
         (if (== $class no-class) false (fold-semidet (sk-sibling-pair-step $reference) false $values)))))

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

(: sk-excludes? (-[det]-> (List Number) Number Bool))
(= (sk-excludes? $exclude $deps)
   (if (deps-meet? $exclude $deps)
      (let $_cut (if (== (search-id-value sk_branch_at) 0) ()
                    (sk-note-cuts! (deps-excluded $exclude $deps)))
         true)
      false))

;; Closed reads may use their own pins and direct observations, but cannot
;; cross the exclusions of the branch being rebuilt around them.
(: sk-branch-excludes? (-[semidet]-> Number Bool))
(= (sk-branch-excludes? $deps)
   (let $frame (search-id-value sk_branch_at)
      (if (== $frame 0) false
         (let (cons $exclude $_rest) (collapse (once
                 (match &sk_branch_cuts ($frame $exclude $_cuts) $exclude)))
            (sk-excludes? (the (List Number) $exclude) $deps)))))

(: sk-note-cuts! (-[det]-> (List Number) Atom))
(= (sk-note-cuts! $cuts)
   (let $frame (search-id-value sk_branch_at)
      (if (if (== $frame 0) true (== $cuts ())) ()
         (let $_noted (collapse (match &sk_branch_cuts ($frame $exclude $old)
                (let* (($both (hash-union $old $cuts))
                       ($_old (remove-variant-row! &sk_branch_cuts (quote ($frame $exclude $old)))))
                   (add-atom &sk_branch_cuts ($frame $exclude $both)))))
            ()))))

;; The latest versions of a key's rows, in row creation order.
(: sk-latest-versions (-[det]-> Number SkeletonKey (List SkeletonVersion)))
(= (sk-latest-versions $hash $key)
   (sort-atom
      (collapse (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
         (if (=alpha $stored $key) (if (sk-live-view? $view) (sk-version $seq $rhash $view) (empty)) (empty))))))

(: sk-version-view (-[det]-> SkeletonVersion SkeletonValue))
(= (sk-version-view (sk-version $_seq $_rhash $view)) $view)

(: sk-view-deps-step (-[semidet]-> Number SkeletonValue Number))
(= (sk-view-deps-step $deps $view)
   (case $view (
      ((sk-val $_fact $_ev $view-deps) (deps-union $deps $view-deps))
      ((sk-goal-val $_goal $_proof $_ev $view-deps) (deps-union $deps $view-deps))
      (sk-none $deps))))

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
   (let* ((($statement $_odd) (canon (brand Statement $part))) ($key (sk-key $statement $kbctx)))
      (append-flat (sk-unifier-hashes (index-hash $key) $key) $hashes)))
