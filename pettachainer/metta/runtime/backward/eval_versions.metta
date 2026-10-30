;; Version selection, branch storage, fold tallies and row input support.
;; Depends on eval_values; recursive reads live in eval_core.


(: sk-admits? (-[det]-> SkeletonFilter (List Number) SkeletonValue Bool))
(= (sk-admits? $filter $exclude $view)
   (case $view (
      ((sk-val $fact $_ev $deps)
         (if (sk-excludes? $exclude $deps) false (sk-fact-matches? $filter $fact)))
      ((sk-goal-val $_goal $_proof $_ev $deps) (if (sk-excludes? $exclude $deps) false true))
      (sk-none false))))

(: sk-admit-older (-[det]-> SkeletonFilter (List Number) SkeletonValue SkeletonValue SkeletonValue))
(= (sk-admit-older $filter $exclude $kept $view)
   (if (sk-admits? $filter $exclude $view) $view $kept))

(: sk-hold-branch-reader! (-[det]-> Number SkeletonKey Number (List Number) Atom))
(= (sk-hold-branch-reader! $slot $key $rhash $exclude)
   (let* (($_requested
             (if (== (search-id-value sk_holding) 1)
                (collapse (once (let ($held-hash $held-key $_held-row) (sk-active-reader)
                   (if (sk-needed? $held-hash $held-key)
                      (if (space-row-present? &ctx_sk_branch_hold ($slot $_hash $key $rhash $exclude)) ()
                         (let $hash (index-hash $key)
                            (context-add! &sk_branch_hold ($slot $hash $key $rhash $exclude))))
                      (empty))))) ()))
          ($_held
             (collapse (let ($reader-hash $reader-key $reader-row) (sk-active-reader)
                (match &sk_row ($reader-hash $stored-reader $reader-row (sk-row $ri $rc $rp $rs))
                   (if (=alpha $stored-reader $reader-key)
                      (if (if (== (search-id-value sk_holding) 1) (sk-needed? $reader-hash $reader-key) false)
                         (context-add! &sk_held ($reader-hash $reader-row (sk-branch-hold $slot $key $rhash $exclude)))
                         (sk-mark-stale! (sk-row-item $rs $reader-hash $reader-key $reader-row (sk-row $ri $rc $rp $rs))))
                      (empty)))))))
      ()))

(: sk-branch-values (-[semidet]-> Number SkeletonKey Number (List Number) Bool (List SkeletonValue)))
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

(: sk-reference-view (-[semidet]-> Number SkeletonValue SkeletonValue))
(= (sk-reference-view $rule $computed)
   (case $computed (
      ((sk-val ($type $kbctx $proof $tv) $ev $vdeps)
         (let* (($fact (data $type $kbctx $tv))
                ($ref (record-proof! (next-search-id proof_id) $rule $proof $ev $vdeps $fact)))
            (sk-val (data $type $kbctx $ref $tv) $ev $vdeps)))
      ((sk-goal-val $goal $goal-proof $gev $gdeps)
         (sk-goal-val $goal (record-proof! (next-search-id proof_id) $rule $goal-proof $gev $gdeps ()) $gev $gdeps))
      (sk-none sk-none))))

(: sk-cache-branch!
   (-[semidet]-> Number Number SkeletonKey Number (List SkeletonKey) (List Number) Bool SkeletonValue SkeletonValue))
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

(: sk-member-sample-step (-[det]-> Number (List InstanceSample) Number (List InstanceSample)))
(= (sk-member-sample-step $hash $found $mhash)
   (append-flat
      (collapse (match &ctx_sk_instance_member ($mhash $hash $_member $pos-seg $neg-seg $contribution)
         (case $contribution (
            ((InstanceEvidence (BaseRateEvidence $_pw 0.0) (BaseRateEvidence $_nw 0.0)) (empty))
            ($sample (instance-sample $pos-seg $neg-seg $sample))))))
      $found))

;; The samples an instance fold read without the excluded keys leaves out; a
;; member that is no sample leaves nothing out. Sorted, as member hashes carry
;; the process's KB id and subtraction order shows in the tally.
(: sk-left-out (-[det]-> Number (List Number) (List InstanceSample)))
(= (sk-left-out $hash $exclude)
   (if (== $exclude ()) ()
      (sort-atom (fold-flat (sk-member-sample-step $hash) ()
         (list_to_set (fold-flat (sk-read-members-step $hash) () $exclude))))))

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
   (case $key (((sk-key $type $_kbctx) (head-is? $type RuleTruth)) ($_fold false))))
(: sk-input-leaves-out-step (-[det]-> (List Number) Bool SkeletonKey Bool))
(= (sk-input-leaves-out-step $exclude $found $input)
   (if $found true (sk-leaves-out? (index-hash $input) $input $exclude)))

;; Whether a consumer excluding these keys reads the key with a sample left
;; out: an instance fold, or a refined rule's truth, which reads one.
(: sk-leaves-out? (-[det]-> Number SkeletonKey (List Number) Bool))
(= (sk-leaves-out? $hash $key $exclude)
   (if (== $exclude ()) false
      (case $key (
         ((sk-fold $args) (if (sk-instance-fold? $args) (not (== (sk-left-out $hash $exclude) ()))
                            (not (== (sk-rate-left-out $args $exclude) ()))))
         ((sk-prior $rate-args)
            (fold-flat (sk-input-leaves-out-step $exclude) false (sk-prior-inputs (compound-rate-goals $rate-args false $_rate))))
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

(: sk-older-views (-[det]-> Number SkeletonKey Number (List SkeletonValue)))
(= (sk-older-views $hash $key $rhash)
   (collapse (match &ctx_sk_view ($hash $stored $rhash $view)
      (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))

(: sk-latest-view (-[det]-> Number SkeletonKey Number SkeletonValue))
(= (sk-latest-view $hash $key $rhash)
   (chainer-first-or sk-none
      (collapse (once (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
         (if (=alpha $stored $key) (if (sk-live-view? $view) $view (empty)) (empty)))))))

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

;; Observed compounds' messages and predicted compounds' updates are split from
;; a key's other views, which merge first.
(: sk-node-message? (-[det]-> SkeletonValue Bool))
(= (sk-node-message? $value)
   (case $value (
      ((sk-val $fact $_ev $_deps) (not (== (sk-message-likelihood (proof-atom-proof $fact)) ())))
      ($_none false))))

;; A message's likelihood; () for any other proof.
(: sk-message-likelihood (-[det]-> Proof Atom))
(= (sk-message-likelihood $step)
   (case (proof-semantic $step) (
      ((message $_source $likelihood $_idx $_tokens) $likelihood)
      ($_other ()))))

;; Zero-confidence STVs are unknown placeholders, not competing estimates.
;; Retain them only when nothing informative exists, so judgment scaffolds can
;; still read an unsupported branch. A CTV may have one informative branch. A
;; compound's message is a likelihood, whatever its own value claims.
(: sk-informed-step (-[det]-> (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-informed-step $kept $value)
   (case $value (
      ((sk-val ($_type $_ctx $_proof (STV $_s $c)) $_ev $_deps)
         (if (if (> $c 0.0) true (sk-node-message? $value)) (cons $value $kept) $kept))
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
      (extract-tv (let* ((($_type $_kbctx $_proof $tv) $fact)) ($fun $acc $tv))))))

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

;; A fold with members proves by its members, in the order they were found.
(: sk-fold-proof (-[semidet]-> Atom (List Proof) Proof))
(= (sk-fold-proof $function $proofs)
   (if (== $proofs ()) (brand Proof cpu)
      (brand Proof
         (cons (if (== $function OrFormula) disjunction foldall-proof)
            (fold-semidet sk-cons-step () $proofs)))))

(: sk-instance-tally (-[det]-> Number SkeletonKey Atom InstanceRegimeState))
(= (sk-instance-tally $hash $fold $kb)
   (case (collapse (once (match &ctx_sk_instance_tally ($hash $stored $acc) (if (=alpha $stored $fold) $acc (empty))))) (
      ((cons $found $_rest) $found)
      (() (instance-regimes (instance-hazard (brand KB $kb) $fold) 1 () ())))))

;; A stationary rule, one no variable of which can bind a stage
;; (stationary-rule?, prolog/sorts.pl), keeps one regime: its estimate is the
;; plain frequency of its samples, whatever order they arrive in. A rule one
;; of whose variables can bind a stage has the KB's hazard.
(: instance-hazard (-[det]-> KB SkeletonKey Number))
(= (instance-hazard $kb $fold)
   (case $fold (
      ((sk-fold ($_kb (ImplicationInstanceSample $a $b $_atv $_btv) $_extract $_init $_function $_finish $_mode))
         (if (stationary-rule? $kb $a $b) 0.0 (rule-change-hazard $kb)))
      ($_other (rule-change-hazard $kb)))))

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

;; A class-link sample of its two sides' stored values, when both have one: a
;; side's stored facts, merged, or a forward run's copy of its value. A copy
;; derived through a rule the sample leaves out (sk-sample-exclusions) holds
;; more than the facts, so the sample is still to be computed.
(: sk-stored-sample (-[semidet]-> SkeletonKey (| SkeletonValue SkeletonWaitingAnswer)))
(= (sk-stored-sample $member)
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $b $_atv $_btv) $kbctx)
         (if (class-link-instance? $a $b)
         (let $excluded (evidence-set (sk-sample-exclusions (ImplicationInstanceSample $a $b $_atv $_btv) $kbctx))
            (case (data (sk-stored-side $a $kbctx $excluded) (sk-stored-side $b $kbctx $excluded)) (
               (((forward-derived ($_at $_ac $aprf $atv) $aev) (forward-derived ($_bt $_bc $bprf $btv) $bev))
                  (sk-val
                     (assemble-runtime-fact (ImplicationInstanceSample $a $b $atv $btv) $kbctx
                        (implication-instance-sample (fact-source $aev $aprf) (fact-source $bev $bprf)) (STV 1.0 1.0))
                     (evidence-join (cons $aev (cons $bev ()))) 0))
               (((sk-waiting $_wa) $_b) (sk-waiting sk-none))
               (($_a (sk-waiting $_wb)) (sk-waiting sk-none))
               ($_missing sk-none))))
            sk-none))
      ($_other sk-none))))

;; A side's stored value: a forward run's copy of the key's value, which
;; holds its stored facts as well, else the stored facts merged; a copy left
;; out is waiting.
(: sk-stored-side (-[det]-> Atom KBContext EvidenceSet (| ForwardDerived NoForwardOutputCandidate SkeletonWaitingAnswer)))
(= (sk-stored-side $side $kbctx $excluded)
   (let $hash (index-hash (sk-key $side $kbctx))
      (case (collapse (once (match &sk_forward_stored ($hash $_key $fact $ev $_deps)
               (if (evidence-excludes? $excluded $ev) (sk-waiting sk-none) (forward-derived $fact $ev))))) (
         ((cons $copy $_rest) $copy)
         (() (stored-statement-candidate (brand Statement $side) $kbctx false))))))

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
(: sk-instance-digest! (-[det]-> Number Number SkeletonKey SkeletonKey SkeletonValue InstanceEvidenceState Atom))
(= (sk-instance-digest! $hash $mhash $fold $member $value (InstanceEvidence (BaseRateEvidence $_pw $pm) (BaseRateEvidence $_nw $nm)))
   (case $member (
      ((sk-key (ImplicationInstanceSample $a $_b $_atv $_btv) $kbctx)
         (let* (($sample-evidence
                  (case $value (
                     ;; A sample's signature is what it observes, whatever role a
                     ;; derived premise read a fact in.
                     ((sk-val $_fact $ev $_deps)
                        (let $kept
                              (evidence-subtraction (evidence-inherited $ev)
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

;; --- Coverage of exact folds (docs/metta/partial_folds.md) -------------------

;; A member without a value is still to come while one of its key's rows is
;; stale, was never computed, or waits for conditioning; once every row is
;; computed and current and none derives anything, it is no member.
(: sk-row-current? (-[det]-> Number Number Bool))
(= (sk-row-current? $khash $rhash)
   (if (space-row-present? &ctx_sk_stale ($khash $rhash)) false
      (if (space-row-present? &ctx_sk_given_pending ($khash $rhash $_cost)) false
         (space-row-present? &ctx_sk_support ($khash $rhash $_deps)))))

(: sk-member-pending? (-[det]-> SkeletonKey Bool))
(= (sk-member-pending? $key)
   (let $khash (index-hash $key)
      (not (== (collapse (once (match &sk_row ($khash $stored $rhash $_row)
                  (if (=alpha $stored $key) (if (sk-row-current? $khash $rhash) (empty) true) (empty)))))
               ()))))

;; The premises of the member node's joins that have no answer yet.
(: sk-unanswered-step (-[det]-> (List SkeletonNodeAt) SkeletonNodeAt (List SkeletonNodeAt)))
(= (sk-unanswered-step $kept (sk-node-at $hash $premise))
   (if (== (sk-answers $premise) ()) (cons (sk-node-at $hash $premise) $kept) $kept))

;; Takes fresh copies of the group's arguments and of the key.
(: sk-group-member? (-[det]-> $spec SkeletonKey Bool))
(= (sk-group-member? ($kbctx $pattern $_group $_e $_i $_f $_fi $_m) $key)
   (= (sk-key $pattern $kbctx) $key))

(: sk-keep-group-member (-[semidet]-> $spec (List SkeletonKey) SkeletonKey (List SkeletonKey)))
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

(: sk-keep-view (-[semidet]-> Number SkeletonKey SkeletonValue (List SkeletonVersion)))
(= (sk-keep-view $hash $key $view)
   (cons (sk-version 0 0 (sk-store-view! $hash $key 0 0 (sk-reference-view -1 $view))) ()))

(: sk-certain-leaf-step (-[det]-> (List SkeletonValue) (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-certain-leaf-step $sources $kept $leaf)
   (case $leaf (
      ((sk-val $fact $_ev $_deps)
         (if (sk-certain? (brand Statement (car-atom $fact)) (cons $fact ()))
            (if (stored-list-member? $leaf $sources) (cons $leaf $kept) $kept) $kept))
      ($_other $kept))))

;; A ground statement stored with confidence 1 is its own value, as expansion
;; applies no rule to it: no other proof could change it, so its rows' views
;; add neither evidence nor dependencies. At a strength between 0 and 1 the
;; fact is the statement's current belief (Jeffrey), so every reader of the
;; key, a conditioning weight included, takes the fact and not its views. A
;; derived view of confidence 1 is a probability known exactly, not the
;; statement's truth, and merges as usual.
(: sk-certain-or (-[semidet]-> (List SkeletonValue) (List SkeletonValue) (List SkeletonValue)))
(= (sk-certain-or $leaves $values)
   (let $certain (fold-semidet (sk-certain-leaf-step $values) () $leaves)
      (if (== $certain ()) $values $certain)))

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

;; Predicted compounds' updates of a key (event-moment-node.md, Jeffrey) apply
;; after its other views have merged, observations included: each moves the
;; merged value, in the order of what they carry (jeffrey-order), so the
;; result does not depend on the order they arrived in. An update's own
;; evidence is its compound's (not what it read of the part's siblings, which
;; are parameters of the update), expanded to its raw sources: what of it the
;; value already holds counts once, so the prediction's count is at most the
;; count of its uncertain sources that are new (evidence-unique-count), and one
;; with none new is dropped; one with no value to move applies to the key's
;; prior (its own value).
(: sk-jeffrey-update? (-[det]-> SkeletonValue Bool))
(= (sk-jeffrey-update? $value)
   (case $value (
      ((sk-val $fact $_ev $_deps)
         (case (proof-semantic (proof-atom-proof $fact)) (
            ((kinematic-update $_source $_prediction $_conditionals $_idx $_parts) true)
            ($_view false))))
      ($_none false))))

(: sk-node-split-step (-[det]-> Atom SkeletonValue Atom))
(= (sk-node-split-step ($messages $updates $others) $value)
   (if (sk-node-message? $value) (data (cons $value $messages) $updates $others)
      (if (sk-jeffrey-update? $value) (data $messages (cons $value $updates) $others)
         (data $messages $updates (cons $value $others)))))

;; A stored fact that is no forward run's copy of a derived value.
(: sk-source-fact-step (-[det]-> (List SkFact) SkFact (List SkFact)))
(= (sk-source-fact-step $kept $fact)
   (if (space-row-present? &sk_forward_stored ((index-hash (sk-fact-key $fact)) $_key $fact $_ev $_deps)) $kept
      (cons $fact $kept)))

(: sk-value-ev-step (-[det]-> EvidenceSet SkeletonValue EvidenceSet))
(= (sk-value-ev-step $ev $value) (case $value (((sk-val $_fact $vev $_deps) (evidence-union $ev $vev)) ($_none $ev))))

(: sk-fresh-variable (-[det]-> Atom Atom))
(= (sk-fresh-variable $_argument) $fresh)

;; A message is applied once: not when the value it acts on already counts it
;; (an antecedent completion formed under its compound's evidence), and once for
;; one source, whatever position or row it came by.
(: sk-message-kept-step (-[det]-> Proof (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-message-kept-step $base-proof $kept $message)
   (case $message (
      ((sk-val ($_type $_kbctx $proof $_tv) $ev $_deps)
         (if (sk-message-counted? $proof $base-proof) $kept
            (if (fold-flat (sk-same-evidence-step $ev) false $kept) $kept (cons $message $kept))))
      ($_none $kept))))

(: sk-same-evidence-step (-[det]-> EvidenceSet Bool SkeletonValue Bool))
(= (sk-same-evidence-step $ev $found $other)
   (if $found true (case $other (((sk-val $_fact $other-ev $_deps) (== $ev $other-ev)) ($_none false)))))

(: sk-message-acc-step (-[det]-> Atom SkeletonValue Atom))
(= (sk-message-acc-step ($likelihoods $proofs $ev $deps) $message)
   (case $message (
      ((sk-val ($_type $_kbctx $proof $_tv) $mev $mdeps)
         (data (cons (sk-message-likelihood $proof) $likelihoods) (cons $proof $proofs)
            (evidence-union (the EvidenceSet $ev) $mev) (deps-union (the Number $deps) $mdeps)))
      ($_none (data $likelihoods $proofs $ev $deps)))))

(: sk-jeffrey-step (-[semidet]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-jeffrey-step $value $update)
   (case $value (
      (sk-none $update)
      ((sk-val ($type $kbctx $proof (STV $s $c)) $ev $deps)
         (case $update (
            ((sk-val ($_utype $_ukbctx $uproof $_utv) $uev $udeps)
               (case (proof-semantic $uproof) (
                  ((kinematic-update $source (prediction (STV $ps $pc)) $conditionals $_idx $_parts)
                     (let $new (evidence-unique-count (evidence-confidence-k) $ev (proof-term-evidence proof-walk-in-kb $source))
                        (if (if (== $new 0.0) true (sk-message-counted? $uproof $proof)) $value
                           (sk-val (assemble-runtime-fact $type $kbctx (brand Proof (jeffrey-update $proof $uproof))
                                       (jeffrey-posterior (evidence-confidence-k) (the Number $s) (the Number $c)
                                          (STV $ps (if (< $new 0.0) (the Number $pc)
                                                      (min (the Number $pc) (/ $new (+ $new (evidence-confidence-k))))))
                                          (the Expression $conditionals)))
                              (evidence-union $ev $uev) (deps-union $deps $udeps)))))
                  ($_other $value))))
            ($_none $value))))
      ($_other $value))))

(: sk-root-claim? (-[det]-> (List SkeletonGiven) Number SkeletonKey Bool))
(= (sk-root-claim? $given $hash $key)
   (if (== $given ())
      (if (== (search-id-value sk_forward_run) 0) (== (sk-need-depth $hash $key) 0) false)
      false))

;; Preserve the cut candidate order when restricting it to near statements.
(: sk-near-key-step (-[det]-> (List SkeletonKey) (List SkeletonKey) SkeletonKey (List SkeletonKey)))
(= (sk-near-key-step $near $kept $k) (if (stored-list-member? $k $near) (append-flat $kept (cons $k ())) $kept))

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
   (case (collapse (once (match &ctx_sk_merged ($hash $stored $deps $value $cached-root)
            (if (=alpha $stored $key)
               (if (== $cached-root (sk-root-claim? () $hash $key))
                  (if (sk-live-view? $value) (sk-merged $hash $stored $deps $value) (empty))
                  (empty)) (empty))))) (
      ((cons $merged $_rest) (let $_counted (query_metric_increment merged-cache-hits) $merged))
      (() (context-cold-merged $hash $key $filter)))))

(: sk-unsettled-value (-[det]-> Number SkeletonValue SkeletonValue SkeletonValue))
(= (sk-unsettled-value $stamp $value $full)
   (case $value (
      ((sk-val ($type $ctx $proof (STV $s $c)) $ev $deps)
         (case $full (
            ((sk-val ($_type $_ctx $_proof (STV $r $_c)) $_full-ev $_full-deps)
               (let* (($range (abs-math (- (sk-link odds (max 0.001 (min 0.999 $s)))
                                      (sk-link odds (max 0.001 (min 0.999 $r))))))
                      ($sources (proof-unsettled-sources $proof)))
                  (if (if (<= $range 0.0) true (hash-subset? (cons $stamp ()) $sources)) $value
                     (sk-val (assemble-runtime-fact $type $ctx (unsettled-summary $stamp $proof)
                        (STV $s (/ $c (+ 1.0 (* $range $range))))) $ev $deps))))
            ($_other-full $value))))
      ($_other-value $value))))

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
         (collapse (match &ctx_sk_merged ($hash $stored $deps $value $cached-root)
            (if (=alpha $stored $key)
               (context-remove! &sk_merged ($hash $stored $deps $value $cached-root))
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
               (== $head total-implication-frontier)))
         false)))
(: replace-token-list (-[det]-> Atom (List Proof) TokenReplacement))
(= (replace-token-list () $proofs) (token-state () $proofs))
(= (replace-token-list (cons $head $tail) $proofs)
   (let* (((token-state $new-head $proofs1) (replace-token $head $proofs))
          ((token-state $new-tail $proofs2) (replace-token-list $tail $proofs1)))
      (token-state (cons $new-head $new-tail) $proofs2)))

;; A rule proof marks each fold premise with a `cpu` token; the tokens are
;; replaced, in premise order, by the folds' proofs.
(: replace-token (-[det]-> Atom (List Proof) TokenReplacement))
(= (replace-token $term $proofs)
   (if (is-var $term) (token-state $term $proofs)
      (if (== $term cpu)
         (case $proofs (((cons $proof $rest) (token-state $proof $rest)) (() (token-state cpu ()))))
         (if (is-expr $term) (replace-token-list $term $proofs) (token-state $term $proofs)))))

;; A compiled query adapter proves (_ inner) with an open head; its proof is
;; the inner proof.
(: sk-unwrap-proof (-[det]-> Atom Proof))
(= (sk-unwrap-proof $proof)
   (brand Proof
      (if (is-expr $proof)
         (if (== $proof ()) $proof
            (if (is-var (car-atom $proof))
               (case (cdr-atom $proof) (((cons $inner ()) $inner) ($_other $proof)))
               $proof))
         $proof)))

(: sk-consume-fold (-[semidet]-> SkeletonRowState $result SkeletonValue SkeletonRowState))
(= (sk-consume-fold (sk-acc $fold-proofs $ev $deps) $res $value)
   (case $value (
      ((sk-goal-val (CPU $_fun $_args $result) $proof $fold-ev $fold-deps)
         (if (= $res $result)
            (sk-acc (cons $proof $fold-proofs) (evidence-union $ev $fold-ev) (cons $fold-deps $deps))
            sk-fail))
      ($_none sk-fail))))

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
   (if (== $given ()) false (deps-meet? (sk-given-hashes $given) (sk-view-deps-step 0 $value))))

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

;; A premise value whose evidence overlaps what the row already uses is
;; replaced by the merge of the key's leaves and views that do not overlap it:
;; the consumer selects the proofs compatible with its other premises.
(: sk-compatible-step (-[semidet]-> EvidenceSet (List SkeletonValue) SkeletonValue (List SkeletonValue)))
(= (sk-compatible-step $ev $acc $view)
   (case $view (
      ((sk-val $_fact $view-ev $_deps)
         (if (premise-evidence-overlap? $ev $view-ev) $acc (cons $view $acc)))
      ($_other $acc))))

(: sk-representative-best (-[det]-> SkeletonValue SkeletonValue SkeletonValue))
(= (sk-representative-best $kept $view)
   (case $view (
      ((sk-val $fact $_ev $_deps)
         (case $kept (
            ((sk-val $old $_old-ev $_old-deps)
               (if (>= (term-confidence $old) (term-confidence $fact)) $kept $view))
            ($_missing $view))))
      ($_other $kept))))

;; A fact premise takes a value unless its evidence overlaps the row's own,
;; except in joins the compiler marked as sharing their sources. A refined rule's truth is a
;; parameter of the row: the row depends on the truth's key, not on the
;; instances the truth was learned from, which the row does not observe.
(: sk-use-premise (-[semidet]-> Bool SkeletonRowState SkPattern SkeletonValue SkeletonRowState))
(= (sk-use-premise $shared (sk-acc $fold-proofs $ev $deps) ($type $kbctx $proof $tv) $value)
   (case (sk-read-value (sk-filter $proof $tv) $value) (
      ((sk-val $fact $premise-ev $premise-deps)
         (let $overlap (if $shared false (premise-evidence-overlap? $ev $premise-ev))
            (if $overlap
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
                        $deps))
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

;; A clash names the statements of the fact evidence the value shares with the
;; row, less those already given and those known, the most impact first. A
;; conditioned branch evaluates at most the value's dependencies. A premise that reads one of
;; those statements itself reads it as known under the condition, so a row
;; reading K and a value derived from K is exact: an And loop C <- (And A B),
;; B <- (Or A C) read by D <- (And C A) with A soft (fuzzer seed 12000289).
;; Premises sharing a compound's node views condition on the compound's event:
;; given it true or false, its parts' messages are that observation's
;; (event-moment-node.md); a connective over the node's own parts is its joint
;; row, which supersedes the conditioned one (proof-dominates?).
(: sk-clash-on (-[semidet]-> (List SkeletonGiven) SkeletonRowState SkeletonValue SkeletonRowState))
(= (sk-clash-on $given $state $value)
   (case $state (
      ((sk-acc $_fold-proofs $ev $deps)
         (case $value (
            ((sk-val $fact $value-ev $value-deps)
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
                     (+ 1 (deps-size $value-deps)))))
            ($_none sk-fail))))
      ($_failed sk-fail))))

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
         (not (== (collapse (once (match &sk_wait ($hash $stored (sk-partial $owner $rule ($type $_k $proof $_v) $_done $_rest $_keys))
                     (if (=alpha $stored $child)
                        (if (rule-live? $rule)
                           (if (=alpha $owner $node) (if (derivation-proof? $type $proof) true (empty)) (empty))
                           (let $_removed (sk-retire-wait! $hash $stored (sk-partial $owner $rule ($type $_k $proof $_v) $_done $_rest $_keys)) (empty)))
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

;; Whether a derivation (`derivation-proof?`) is among a statement's rows. This check also
;; removes encountered retired rows and their optimization registrations.
(: sk-founded? (-[det]-> Number SkeletonKey Bool))
(= (sk-founded? $hash $key)
   (not (== (collapse (once (match &sk_row ($hash $stored $_rhash (sk-row (sk-ident $rule $_keys $_key) ($type $_k $proof $_v) $_ps $_seq))
               (if (=alpha $stored $key)
                  (if (rule-live? $rule) (if (derivation-proof? $type $proof) true (empty))
                     (let $_removed (sk-drop-row! $hash $stored $_rhash (sk-row (sk-ident $rule $_keys $_key) ($type $_k $proof $_v) $_ps $_seq)) (empty)))
                  (empty)))))
            ())))

;; What a row's closed reads take as unfounded: a complete statement, the
;; row's own conclusion when the row is a rule application of it (or a
;; completion's consequence, sk-read-completion); nothing otherwise, and the
;; row reads no premise closed.
(: sk-closed-pin (-[det]-> Number Atom Atom Bool (List SkeletonGiven)))
(= (sk-closed-pin $khash $type $kbctx $reads)
   (if (if $reads (complete-statement? $type $kbctx) false)
      (cons (sk-unfounded $khash (sk-key $type $kbctx)) ())
      ()))

;; A target waits for a turn, with its estimated cost and waiting value.
(: sk-wait! (-[det]-> Number Number Number SkeletonValue SkeletonValue))
(= (sk-wait! $khash $rhash $cost $waiting)
   (let* (($_unfinished (next-search-id sk_branch_unpaid))
          ($_was (remove-data-rows! &sk_given_pending (quote ($khash $rhash $_cost))))
          ($_pending (context-add! &sk_given_pending ($khash $rhash $cost))))
      $waiting))

;; The statements a condition gives, closed reads' pins aside.
(: sk-given-depth-step (-[det]-> Number SkeletonGiven Number))
(= (sk-given-depth-step $depth $given) (case $given (((sk-given $_hash $_key $_truth) (+ $depth 1)) ($_pin $depth))))

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

;; A compound antecedent is read through its key, whose producers read its
;; parts. Inverting the rule concludes the compound again, so its row also
;; excludes views depending on any part: the premise it inverts was derived
;; from them.
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
            (if (sk-inverted-proof? $proof)
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

;; A completion's recipe fixes its target, compound, observation position and
;; opening polarity; statement inputs before the observation are siblings.
;; Siblings exclude the consequence and compound to avoid feedback. A known
;; false consequence needs no closed pin; otherwise complete siblings may close
;; with C unfounded. An unanswered sibling may be read with the target given
;; at its opening value (true for And, false for Or, complemented for Not).
;; That hypothesis supplies no support and is removed from the exclusions.
;; The compound's independent evidence conditions the prior and siblings;
;; the observation excludes other inversions' observations but may read a
;; prediction through the compound's own evidence. See runtime_design_assumptions
;; and prior_factored_merge for the policy and its known approximation limits.
;; Folded over what the compound's inversion rows read: the hashes of each
;; such observation, the completion's own consequence aside.
(: sk-observed-exclusion-step (-[det]-> SkeletonKey (List Number) SkeletonKey (List Number)))
(= (sk-observed-exclusion-step $consequence $hashes $input)
   (if (=alpha $input $consequence) $hashes (append-flat (sk-unifier-hashes (index-hash $input) $input) $hashes)))

(: sk-without-hash-step (-[det]-> Number (List Number) Number (List Number)))
(= (sk-without-hash-step $drop $kept $hash) (if (== $hash $drop) $kept (cons $hash $kept)))

(: sk-known-false-step (-[det]-> Bool SkFact Bool))
(= (sk-known-false-step $found ($_type $_kbctx $_proof $tv))
   (if $found true (case $tv (((STV $s $c) (if (>= $c 1.0) (<= $s 0.0) false)) ($_other false)))))

;; An implication instance sample must not restate the implication it
;; estimates: its row starts out excluding every rule whose premises and
;; conclusion match the sample's antecedent and consequent, so a premise value
;; using one of them clashes and the sample reads the key's other proofs. The
;; rules are found through the conclusion index, by the consequent.
(: sk-sample-exclusions (-[semidet]-> Atom KBContext (List Evidence)))
(= (sk-sample-exclusions $type $kbctx)
   (if (head-is? $type ImplicationInstanceSample)
      (let* (((ImplicationInstanceSample $sa $sb $_atv $_btv) $type)
             (($kbid $_ctx $_vars) $kbctx)
             ($sides (quote ($sa $sb)))
             (($a $b) (generalize-constants $sides))
             ($link (quote ($kbid $a $b)))
             ($hash (index-hash $link))
             ($epoch (data (search-id-value ruleid) (search-id-value bwd_tmp_ruleid))))
         ;; The rules restating one sample restate every sample of the link,
         ;; so they are found once per link and rule set, over the sample's
         ;; sides with their constants generalized.
         (case (collapse (once (match &sk_sample_exclusions ($hash $stored $stored-epoch $excluded)
                  (if (=alpha $stored $link) (if (== $stored-epoch $epoch) $excluded (empty)) (empty))))) (
            ((cons $excluded $_rest) $excluded)
            (()
               (let* (($conjuncts (implication-side-conjuncts (the Statement $a)))
                      ($excluded
                         (collapse
                            (match ccls_index (($b ($kbid $_rctx $_rvars) $prf $_tv) $_id $prems)
                               (if (= (foldr-flat sk-fact-premise-type () $prems) $conjuncts)
                                  (rule-excluded (brand KB $kbid) (rule-evidence-head $prf))
                                  (empty)))))
                      ($_old (remove-data-rows! &sk_sample_exclusions (quote ($hash $_old-link $_old-epoch $_old-excluded))))
                      ($_new (add-atom &sk_sample_exclusions ($hash $link $epoch $excluded))))
                  $excluded)))))
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
   (case $tv (((CTV $_pos $_neg) (CTV (STV 0.0 0.0) (STV 0.0 0.0))) ($_other (STV 0.0 0.0)))))

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
(= (sk-row-result (sk-row (sk-ident $rule $_keys $_key) ($type $kbctx $proof $tv) $premises $_seq) $state)
   (case $state (
      ((sk-acc $fold-proofs $ev $deps)
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
                            (case (sk-prior-update-of (brand KB (car-atom $kbctx)) $applied $value-tv) (
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
               (sk-val $fact (if $unsupported (ev-set 0)
                     (let $result-ev (rule-result-evidence $fact $ev)
                        (if (not (== (rule-completion-inputs $rule $premises) no-completion-inputs))
                           (evidence-subtraction-certain $result-ev (proof-given-evidence $proof))
                           (if (if (sk-inverted-proof? $proof) true (head-is? $type ImplicationInstanceSample)) $result-ev
                              (evidence-condition $result-ev (fold-semidet sk-leaf-premise-step () $premises))))))
                  (deps-join $deps)))))
      ($_failed sk-none))))

(: sk-leaf-premise-step (-[det]-> (List Number) SkPattern (List Number)))
(= (sk-leaf-premise-step $leaves $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) $leaves)
      (($_type $_kbctx $leaf $_tv) (sk-leaf-proof-step $leaves $leaf)))))

(: sk-leaf-proof-step (-[det]-> (List Number) Atom (List Number)))
(= (sk-leaf-proof-step $leaves $leaf)
   (if (is-var $leaf) (cons 0 $leaves)
      (case $leaf (
         ((fact-source $_source-ev $name) (cons (index-hash $name) $leaves))
         ((cons conjunction $parts) (fold-flat sk-leaf-proof-step $leaves (the (List Atom) $parts)))
         ((negated $inner) (sk-leaf-proof-step $leaves $inner))
         ($other (if (is-expr $other) (cons 0 $leaves) (cons (index-hash $other) $leaves)))))))

(: sk-inverted-proof? (-[det]-> Atom Bool))
(= (sk-inverted-proof? $proof)
   (case (proof-semantic (brand Proof $proof)) (
      ((prior-update inversion $_rule $_base $_read $_witness) true)
      ($_other false))))

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

(: sk-drop-fold-view! (-[det]-> SkeletonKey Atom))
(= (sk-drop-fold-view! $key) (sk-drop-row-views! (index-hash $key) $key 0))

;; An empty existential fold, or a connective's evidence with no view, has
;; been read but has no value. Its inputs must still wake its readers when
;; they obtain evidence.
(: sk-empty-read? (-[det]-> SkeletonKey Bool))
(= (sk-empty-read? $fold) (if (sk-existential-fold? $fold) true (head-is? $fold sk-evidence)))
(: sk-fold-read? (-[det]-> Number SkeletonKey Bool))
(= (sk-fold-read? $hash $fold)
   (if (sk-empty-read? $fold)
      (not (== (collapse (once (match &ctx_sk_latest ($hash $stored (sk-version $_seq 0 $_value))
         (if (=alpha $stored $fold) true (empty))))) ()))
      (not (== (sk-latest-view $hash $fold 0) sk-none))))

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

(: sk-needed? (-[det]-> Number SkeletonKey Bool))
(= (sk-needed? $hash $key)
   (not (== (collapse (once (match &sk_needed ($hash $stored $_depth) (if (=alpha $stored $key) true (empty))))) ())))

;; How many rows or folds lie between a needed key and the nearest root.
(: sk-need-depth (-[det]-> Number SkeletonKey Number))
(= (sk-need-depth $hash $key)
   (chainer-first-or 1000000
      (collapse (once (match &sk_needed ($hash $stored $depth) (if (=alpha $stored $key) $depth (empty)))))))

;; A stale row leaves the reader lists of the keys it reads, so a change walks
;; only current readers; it is kept as a stale reader of those keys, which a
;; forward run taking one of them brings back. The determinism checker proves
;; the fold over a parameter list.
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
      (let* (($_view (sk-drop-fold-view! $fold)) ($_merged (sk-drop-merged! $fold)))
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
(: sk-stale-reader-step (-[det]-> SkeletonKey Atom SkeletonItem Atom))
(= (sk-stale-reader-step $stale $_acc (sk-row-item $seq $khash $key $rhash $row))
   (if (if (== (search-id-value sk_holding) 1) (sk-needed? $khash $key) false)
      (case $stale (
         ((sk-key $_type $_kbctx)
            (if (space-row-present? &ctx_sk_held ($khash $rhash sk-stale-input)) ()
               (let $_row (context-add! &sk_held ($khash $rhash sk-stale-input)) ())))
         ($_fold (if (space-row-present? &ctx_sk_restale ($khash $rhash)) () (let $_row (context-add! &sk_restale ($khash $rhash)) ())))))
      (sk-mark-stale! (sk-row-item $seq $khash $key $rhash $row))))
(= (sk-stale-reader-step $_stale $_acc (sk-fold-check $hash $fold)) (sk-mark-stale! (sk-fold-check $hash $fold)))
(: sk-stale-key! (-[det]-> SkeletonKey Atom))

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
