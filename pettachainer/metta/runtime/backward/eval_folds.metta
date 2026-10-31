;; Lazy member folds and population reads. The caller owns value and premise reads.

(: sk-computed-centre (-[semidet]-> SkeletonValueReader KB Statement SourceList (List Number) OptionalSTV))
(= (sk-computed-centre $reader $kb $pattern $sources $exclude)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn))
          ($left-out (hash-union $exclude (hash-set (observation-keys $sources)))))
      (case (base-rate-premises $kb $pattern $_rate) (
         ((cons (CPU FoldAllCompiled $args $_result) ())
            (let* (((cons (fa-subscription $identity $descriptor $_triggers) ())
                      (fa-premise-subscriptions (CPU FoldAllCompiled $args $_out)))
                   ($id (fa-id $identity))
                   ($group (quote (aggregate-support $id))))
               (if (likelihood-support-admissible? $group $sources)
                  (let* (($state (ledger-read-excluding $id (fa-left-out $id $left-out)))
                         ((forward-aggregate-state $_id $_sum $_mass $members) $state))
                     (if (> $members 0)
                        (let (STV $g $gc) (fa-result $descriptor $state) (STV $g $gc))
                        (empty)))
                  (empty))))
         ;; A compound's centre is the prior every other reader reads.
         ((cons (CPU CompoundRate $rate-args $rate-res) ())
            (if (sk-admissible-step $sources true (CPU CompoundRate $rate-args $rate-res))
               (case ($read (sk-prior $rate-args) sk-any-filter $left-out) (
                  ((sk-goal-val (CPU $_fun $_args (STV $s $c)) $_proof $_ev $_deps) (STV $s $c))
                  ($_none (empty))))
               (empty)))))))

;; The watch already applied the row's cuts. Additional observation cuts
;; use the same cached fold evaluator, never a separate raw-tally snapshot.
(: sk-rate-read (-[semidet]-> SkeletonPremiseReader KB Statement TV RatePlan (List Number) (List Number) TV))
(= (sk-rate-read $premises-reader $kb $pattern $raw (rate-plan $goals $result) $exclude $observations)
   (let* (((sk-premise-reader $premise-read-fn) $premises-reader)
          ($premise-read (the (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonReadPolicy SkeletonRowState SkPattern SkeletonRowState) $premise-read-fn)))
      (if (hash-subset? $observations $exclude) $raw
         (if (== $raw no-evidence) no-evidence
            (if (user-base-rate? $kb $pattern) $raw
               (case (fold-semidet
                         ($premise-read () () (hash-union $exclude $observations) false false sk-greedy-read)
                         (sk-acc () (ev-set 0) ()) $goals) (
                  ((sk-acc $_proofs $_ev $_deps) (the TV $result))
                  ($_missing (STV 0.5 0)))))))))

(: sk-evidence-view (-[semidet]-> SkeletonValueReader Number $spec (List Number) SkeletonValue))
(= (sk-evidence-view $reader $hash $args $exclude)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn))
          (($kb $ktype $_ctype $kbctx) $args)
          ($compound (sk-key $ktype $kbctx))
          ($_use (sk-add-use! $compound (sk-evidence $args)))
          ($apart (sk-evidence-apart $args $exclude)))
      (if (if (== (sk-key-leaves $compound sk-any-filter) ()) (== (sk-evidence-rows $args) ()) false)
         sk-none
         (case (sk-premise-value false ($read $compound sk-any-filter $apart)) (
            ((sk-val ($_type $_kbctx $proof $tv) $ev $deps)
               (case (collapse (once (sk-observation-prior (brand KB $kb) (the Proof $proof) (the TV $tv) false))) (
                  ((cons $formed ())
                     (sk-goal-val (CPU CompoundEvidence $args (key-evidence $tv $formed $proof))
                        $proof $ev (deps-join (cons (deps-key $hash) (cons (deps-key (index-hash $compound)) (cons $deps ()))))))
                  (() sk-none))))
            ($_none sk-none))))))
;; Cache a compound prior per pattern, watching its input keys. Excluded reads
;; recompute it with the same cuts; only input dependencies, not evidence, propagate.
(: sk-prior-view (-[semidet]-> SkeletonPremiseReader Number $spec (List Number) SkeletonValue))
(= (sk-prior-view $premises-reader $hash $args $exclude)
   (let* (((sk-premise-reader $premise-read-fn) $premises-reader)
          ($premise-read (the (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonReadPolicy SkeletonRowState SkPattern SkeletonRowState) $premise-read-fn))
          ($goals (compound-rate-goals $args false $rate))
          ($_uses (fold-flat (sk-use-step! (sk-prior $args)) () (sk-prior-inputs $goals))))
      (case (fold-semidet ($premise-read () () $exclude false false sk-greedy-read) (sk-acc () (ev-set 0) ()) $goals) (
         ((sk-acc $_proofs $_ev $deps)
            (sk-goal-val (CPU CompoundRate $args (the TV $rate)) (brand Proof cpu) (ev-set 0) (deps-join (cons (deps-key $hash) $deps))))
         ($_missing sk-none)))))
;; Read members without the fold's own output. Collect evidence/dependencies per
;; member and join them once after selection.
(: sk-fold-step
   (-[semidet]-> SkeletonValueReader (-[semidet]-> $acc SkFact $acc) SkeletonFilter (List Number) SkeletonFold SkeletonKey
       SkeletonFold))
(= (sk-fold-step $reader $step $filter $exclude (sk-fold-state $acc $proofs $ev $deps) $key)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn)))
      (case (sk-premise-value false ($read $key $filter $exclude)) (
         ((sk-val $fact $member-ev $member-deps)
            (let* ((($_type $_kbctx $proof $_tv) $fact))
               (sk-fold-state ($step $acc $fact) (cons $proof $proofs)
                  (cons $member-ev $ev) (cons $member-deps $deps))))
         ($_none (sk-fold-state $acc $proofs $ev $deps))))))
;; Witnesses sharing uncertain evidence or derived statements are correlated.
;; Keep one witness's bound and evidence, but every member's dependencies, so a
;; later bridge or stronger witness refreshes it (docs/metta/explicit_exists.md).
(: sk-existential-step
   (-[semidet]-> SkeletonValueReader Bool SkeletonFilter (List Number) SkeletonExistentialFold SkeletonKey SkeletonExistentialFold))
(= (sk-existential-step $reader $floor $filter $exclude
      (sk-exists-state $tv $best $overlap $proofs $ev $deps) $key)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn)))
      (case (sk-premise-value false ($read $key $filter $exclude)) (
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
         ($_none (sk-exists-state $tv $best $overlap $proofs $ev $deps))))))
;; Finish a fold over its members. Empty existential folds have no value except
;; the residual's requested identity; population folds carry no member evidence.
(: sk-folded-view
   (-[semidet]-> SkeletonValueReader Number Atom $args (-[semidet]-> $acc SkFact $acc) Atom $acc AggregateFinish
       (List SkeletonKey) SkeletonFilter SkeletonValue))
(= (sk-folded-view $reader $hash $kind $args $step $function $init $finish $members $filter)
   (if (if (== $function OrFormula) true (== $function ExistentialFloor))
      (let* (($floor (== $function ExistentialFloor))
             ((sk-exists-state $exists-tv $exists-best $exists-overlap $exists-proofs $exists-ev $exists-deps)
                (fold-semidet (sk-existential-step $reader $floor $filter (cons $hash ()))
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
             (fold-semidet (sk-fold-step $reader $step $filter (cons $hash ()))
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
;; Base-rate and instance folds maintain their existing per-member tallies;
;; other folds compute from members. User base rates remain authoritative.
;; See docs/metta/base_rate_refresh.md and hypothesis_rules.md.
(: sk-fold-view (-[semidet]-> SkeletonValueReader Number ScalarFoldSpec SkeletonValue))
(= (sk-fold-view $reader $hash $args)
   (if (sk-instance-fold? $args)
      (let* (($_taken (sk-instance-take! $reader $hash $args))
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
                ($_taken (sk-take-rate $reader $hash $args))
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
      (no-base-rate-aggregate-key (sk-computed-fold-view $reader $hash $args))))))
;; Pending members remain to be taken. A sample without search rows may use its
;; sides' stored values; a pending or excluded side must wait.
(: sk-instance-take-step (-[semidet]-> SkeletonValueReader Number SkeletonKey ScalarFoldSpec SkeletonFilter Atom SkeletonKey Atom))
(= (sk-instance-take-step $reader $hash $fold $args $filter $_acc $member)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn))
          ($value ($read $member $filter (cons $hash ()))))
      (if (== $value sk-none)
         (case (if (sk-member-pending? $member) (sk-waiting sk-none) (sk-stored-sample $member)) (
            ((sk-waiting $_none)
               (ledger-instance-changed! $hash $fold))
            ($stored (sk-instance-take-value! $hash $fold $args $member (the SkeletonValue $stored)))))
         (sk-instance-take-value! $hash $fold $args $member $value))))
;; Take only members that joined or changed, preserving their arrival order.
(: sk-instance-take! (-[semidet]-> SkeletonValueReader Number ScalarFoldSpec Atom))
(= (sk-instance-take! $reader $hash $args)
   (let* (($fold (sk-fold $args)) ($changed (sk-rate-changed $hash $fold)))
      (if (== $changed ()) ()
         (let $filter
               (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
                  ((cons $node $_more) (sk-member-filter $node))
                  (() sk-any-filter)))
            (fold-semidet (sk-instance-take-step $reader (the Number $hash) $fold $args $filter) () $changed)))))
;; Replace changed members' aggregate contributions using fold-excluded reads;
;; a member without an admissible value leaves the tally.
(: sk-rate-take-step (-[semidet]-> SkeletonValueReader Number SkeletonKey Number ForwardAggregateDescriptor Atom SkeletonKey Atom))
(= (sk-rate-take-step $reader $hash $fold $id $descriptor $_acc $member)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn))
          ($mhash (index-hash $member))
          ($_clean (ledger-member-current! $hash $mhash $fold $member))
          ($readers (sk-push-reader! ($hash $fold 0)))
          ($value (sk-premise-value false ($read $member sk-any-filter (cons $hash ()))))
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

(: sk-cover-member-step (-[semidet]-> SkeletonValueReader Number SkeletonFilter SkeletonCover SkeletonKey SkeletonCover))
(= (sk-cover-member-step $reader $hash $filter (sk-cover $covered $missing) $key)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn)))
      (if (== ($read $key $filter (cons $hash ())) sk-none)
         (if (sk-member-pending? $key) (sk-cover $covered (+ $missing 1)) (sk-cover $covered $missing))
         (sk-cover (+ $covered 1) $missing))))
;; Exact folds are partial while members or their search are pending. Count
;; covered members and pending members, plus one for unfinished joins; -1 means
;; search has not started. Record partial-fold provenance in &sk_partial.
;; Statistical and existential folds do not require this coverage certificate.
(: sk-cover-fold! (-[semidet]-> SkeletonValueReader Number SkeletonKey SkPattern (List SkPattern) SkeletonValue SkeletonValue))
(= (sk-cover-fold! $reader $hash $key $node $members $view)
   (let* (($cover
             (case $members (
                (() (if (sk-expanded? (sk-node-hash $node) $node) (sk-cover 0 0) (sk-cover 0 -1)))
                ((cons $member $_more)
                   (if (sk-expanded? (sk-node-hash $member) $member)
                      (let* (((sk-cover $found $pending)
                                (fold-semidet (sk-cover-member-step $reader $hash (sk-member-filter $member)) (sk-cover 0 0)
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

(: sk-computed-fold-view (-[semidet]-> SkeletonValueReader Number ScalarFoldSpec SkeletonValue))
(= (sk-computed-fold-view $reader $hash $args)
   (let* ((($_kb $_pattern $extractor $init $function $finish $_mode) $args)
          ($node (CPU FoldAllCompiled $args $_result))
          ($members (sk-fold-node-member $node))
          (($keys $filter)
             (case $members (
                (() (data () sk-any-filter))
                ((cons $member $_rest) (data (sk-answers $member) (sk-member-filter $member))))))
          ($view
             (sk-folded-view $reader $hash FoldAllCompiled $args (sk-accumulate $extractor $function) $function $init
                $finish (the (List SkeletonKey) $keys) (the SkeletonFilter $filter))))
      (if (if (== $finish identity) (if (== $function OrFormula) false (if (== $function ExistentialFloor) false true)) false)
         (sk-cover-fold! $reader $hash (sk-fold $args) $node $members $view)
         $view)))

(: sk-group-view (-[semidet]-> SkeletonValueReader Number SkeletonKey GroupedFoldSpec SkeletonValue))
(= (sk-group-view $reader $hash $key $args)
   (let* ((($_kbctx $_pattern $_group $extractor $init $function $finish $_mode) $args))
      (case (sk-group-members $key $args) (
         ((sk-group-found $member $members)
            (sk-folded-view $reader $hash GroupedFoldAllCompiled $args (sk-accumulate $extractor $function) $function
               $init $finish $members (sk-member-filter $member)))
         (sk-group-missing sk-none)))))

(: sk-node-apply (-[semidet]-> SkeletonValueReader SkeletonKey (List Number) (List SkeletonValue) (List SkeletonValue) SkeletonValue SkeletonValue))
(= (sk-node-apply $reader $key $exclude $messages $updates $value)
   (let $observed (if (== $messages ()) $value (sk-messages-on $reader $key $exclude $messages $value))
      (if (== $updates ()) $observed
         (fold-semidet sk-jeffrey-step
            (if (== $observed sk-none) (sk-cavity-prior $reader $key (fold-semidet sk-value-ev-step (ev-set 0) $updates) $exclude) $observed)
            (the (List SkeletonValue) (jeffrey-order $updates))))))
;; Read the cavity population rate without sources held by the messages/updates
;; or excluded by the reader. Only source facts count; an explicit rate overrides
;; the tally. Positive-only predicates have no prior without an explicit rate.
(: sk-cavity-prior (-[semidet]-> SkeletonValueReader SkeletonKey EvidenceSet (List Number) SkeletonValue))
(= (sk-cavity-prior $reader $key $ev $exclude)
   (let* (((sk-value-reader $read-fn) $reader)
          ($read (the (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue) $read-fn)))
      (case $key (
         ((sk-key $type $kbctx)
            (if (head-is-member? $type (And Or Not)) sk-none
               (let* (($pattern
                         (case (source-catalog-priors $type $kbctx) (
                            ((cons (sk-prior-fold $_rule $args) $_more) (car-atom (cdr-atom $args)))
                            (() (if (is-expr $type) (cons-atom (car-atom $type) (map-flat sk-fresh-variable (cdr-atom $type))) $type)))))
                      ($kbid (car-atom $kbctx))
                      ($kb (brand KB $kbid)))
                  (if (if (positive-only-pattern? $kb (the Statement $pattern)) (user-base-rate? $kb (the Statement $pattern)) true)
                     (case ($read (car-atom (sk-direct-key-step () (base-rate-fold $kb (the Statement $pattern) $_rate))) sk-any-filter ()) (
                        ((sk-goal-val (CPU $_fun $_args $fold-tv) $_proof $_ev $deps)
                           (case (if (user-base-rate? $kb (the Statement $pattern)) $fold-tv
                                    (let* (($facts (fold-semidet sk-source-fact-step ()
                                                      (sk-leaf-facts (the Statement $pattern) (kbctx $kb) sk-any-filter)))
                                           ($observed (BaseRateTv (observed-rate-evidence $facts $exclude $ev))))
                                       (smoothed-base-rate-tv $kb $observed))) (
                              ((STV $s $c)
                                 (if (> (the Number $c) 0.0)
                                    (sk-val (assemble-runtime-fact $type $kbctx (brand Proof (population-prior $pattern)) (STV $s $c))
                                       (ev-set 0) $deps)
                                    sk-none))
                              ($_unknown sk-none))))
                        ($_none sk-none)))
                     sk-none))))
         ($_fold sk-none)))))

(: sk-messages-on (-[semidet]-> SkeletonValueReader SkeletonKey (List Number) (List SkeletonValue) SkeletonValue SkeletonValue))
(= (sk-messages-on $reader $key $exclude $messages $value)
   (let* (($base (if (== $value sk-none) (sk-cavity-prior $reader $key (fold-semidet sk-value-ev-step (ev-set 0) $messages) $exclude) $value))
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

(: sk-take-rate (-[semidet]-> SkeletonValueReader Number ScalarFoldSpec Atom))
(= (sk-take-rate $reader $hash $args)
   (if (sk-instance-fold? $args) (sk-instance-take! $reader $hash $args)
   (let $key (sk-fold $args)
      (case (fa-premise-subscriptions (CPU FoldAllCompiled $args $_result)) (
         ((cons (fa-subscription $identity $descriptor $triggers) $_none)
            (let* (($_registered (fa-register! $identity $descriptor $triggers))
                   ($changed (sk-rate-changed $hash $key)))
               (case (collapse (fa-id $identity)) (
                  ((cons $id $_more)
                     (let $_linked (link-aggregate-fold! $id $hash)
                        (fold-semidet (sk-rate-take-step $reader (the Number $hash) $key (the Number $id) $descriptor) () $changed)))
                  (() ())))))
         ($_other ()))))))

;; A fold or group gets its view when first read, from its members' views at
;; that point; it is recomputed once one of them changes.
