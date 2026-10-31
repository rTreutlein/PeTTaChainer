;; Forward subscriptions maintain additive state from per-key observations.
;; Identity hashes select candidates; full alpha comparison decides identity.
;; Fold descriptors share registration, observation replacement and cache publication.
;; The aggregate is a base rate's one estimate: backward folds update it too (sk-fold-view).
;; A member counts without its values derived through the estimate itself.
;; Publishing a value the cache already holds is skipped, since every store wakes the folds.
;; Ordinary base rates are seeded lazily when a fold first reads them.
;; Computed cache entries keep that source while forward deltas update statistics.
;; Removal rejoins the surviving class facts before publishing the cache.
;; An added class fact updates only its subscribed joins.

;; What a fold premise asks the forward chainer to maintain: its aggregate
;; identity and descriptor, and the trigger keys whose facts update it, in
;; order (two only for a class link between two distinct classes).
(datatype ForwardAggregateSubscription
   (fa-subscription ForwardAggregateIdentityKey ForwardAggregateDescriptor (List ForwardTriggerKey)))

;; The fold premises the forward chainer can maintain: plain base rates, and
;; the instance fold of a class link (A $x) -> (B $x) between two classes.
(: fa-premise-subscriptions
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (List ForwardAggregateSubscription)))
(= (fa-premise-subscriptions $premise)
   (case $premise (
      ((CPU FoldAllCompiled ($kb $pattern extract-tv (BaseRateEvidence $_e $_f) BaseRateAcc base-rate result-tv) $_r)
         (cons (fa-subscription
                  (forward-base-rate-identity (brand KB $kb) (brand Statement $pattern))
                  (forward-base-rate-descriptor (brand KB $kb) (brand Statement $pattern))
                  (cons (forward-type-trigger-key (brand KB $kb) (brand Statement $pattern)) ()))
            ()))
      ((CPU FoldAllCompiled ($kb (ImplicationInstanceSample $a $b $atv $btv) $extract $init $step $finish $mode) $_r)
         (if (class-link? $a $b)
            (let* (($k (brand KB $kb)) ($j (brand Term (car-atom $a))) ($i (brand Term (car-atom $b))))
               (cons (fa-subscription (forward-class-link-identity $k $j $i)
                        (forward-class-link-descriptor $k $j $i
                           (sk-fold (quote ($kb (ImplicationInstanceSample $a $b $atv $btv) $extract $init $step $finish $mode))))
                        (cons (fwd_member $k $j) (if (== $j $i) () (cons (fwd_member $k $i) ()))))
                  ()))
            ()))
      ($_other ()))))

;; A rule's fold premises register when the rule is stored. Query-local rules
;; register only class links, whose subjects are seeded from the stored facts
;; when they first register; their base rates wait for a reader.
(: fa-register-subscription! (-[det]-> Bool (List $a) ForwardAggregateSubscription (List $a)))
(= (fa-register-subscription! $live $acc (fa-subscription $identity $descriptor $triggers))
   (case $descriptor (
      ((forward-class-link-descriptor $kb $sub $super $fold)
         (if (== (collapse (once (fa-id $identity))) ())
            (let* (($_registered (fa-register! $identity $descriptor $triggers))
                   ($_seeded (fold-flat (fa-seed-class-link! $kb $sub $super $fold) () (the (List ForwardTriggerKey) $triggers))))
               $acc)
            $acc))
      ($_rate (if $live (fa-register! $identity $descriptor $triggers) $acc)))))

(: fa-register-premise-step! (-[det]-> Bool (List $a) (| Goal (Statement KBContext Proof TV)) (List $a)))
(= (fa-register-premise-step! $live $acc $premise)
   (fold-flat (fa-register-subscription! $live) $acc (fa-premise-subscriptions $premise)))

(: register-forward-aggregate-premises! (-[det]-> Bool (List (| Goal (Statement KBContext Proof TV))) (List $a)))
(= (register-forward-aggregate-premises! $live $premises)
   (fold-flat (fa-register-premise-step! $live) () $premises))

(: fa-positive-ev (-[det]-> TV BaseRateEvidenceState))
(= (fa-positive-ev $a)(case $a ( ((STV $b $c)(BaseRateEvidence (* $b $c) $c))((CTV $d $e)(fa-positive-ev $d))($f (BaseRateEvidence 0.0 0.0)))))

(: fa-physical-sources (-[semidet]-> SkFact SourceList))
(= (fa-physical-sources ($type $ctx $proof $_tv))
   (if (is-expr $proof)
      (observation-sources (proof-term-evidence proof-walk-in-kb $proof))
      (observation-sources (fact-evidence-entry $ctx $proof $type))))

(: fa-result (-[semidet]-> ForwardAggregateDescriptor ForwardAggregateState TV))
(= (fa-result (forward-base-rate-descriptor $kb $_pattern)
      (forward-aggregate-state $_id $sum $mass $_members))
   (let $tv (BaseRateTv (BaseRateEvidence $sum $mass))
      (the TV (smoothed-base-rate-tv $kb $tv))))

(: fa-dist-acc (-[det]-> $a DistributionSumCount))
(= (fa-dist-acc $a)(the DistributionSumCount $a))
(: fa-ev-acc (-[det]-> $a BaseRateEvidenceState))
(= (fa-ev-acc $a)(the BaseRateEvidenceState $a))
(: fa-instance-acc (-[det]-> $a InstanceEvidenceState))
(= (fa-instance-acc $a)(the InstanceEvidenceState $a))
;; A base-rate finish is read as the KB reads base rates (see
;; `smoothed-base-rate-tv`).
(: finish-aggregate (-[semidet]-> KB Expression Expression Atom))
(= (finish-aggregate $kb $a $b)(let $tv (case $a ( (identity $b)(dist-average (the Distribution (once (reduce (reduce (DistAverageFromSumCount (fa-dist-acc $b)))))))(base-rate (BaseRateTv (fa-ev-acc $b)))(implication-instance-ctv (ImplicationInstanceTv (fa-instance-acc $b))))) (if (base-rate-finish? $a)(smoothed-base-rate-tv $kb $tv) $tv)))
(: fa-publish-cache! (-[det]-> KB Statement TV $a (List $b)))
(= (fa-publish-cache! $a $b $c $d)
   (case (base-rate-cache-entries-for-mode $a $b $d) (
      ((cons $entry $_rest) (if (== (base-rate-entry-tv $entry) $c) () (store-produced-base-rate! $a $b $c $d)))
      (() (store-produced-base-rate! $a $b $c $d)))))
(: fa-update! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-update! $fact $id (forward-base-rate-descriptor $kb $pattern))
   (let* ((($type $_ctx $_proof $tv) (copy_term $fact))
          ;; Matching must not specialize the population subsequently published.
          ($_matched (if (= (copy_term $pattern) $type) ok (empty)))
          ((BaseRateEvidence $sum $mass) (fa-positive-ev $tv))
          ($member (forward-fact-key $fact))
          ($key (brand ForwardAggregateObservationKey (quote ($id $member))))
          ($sources (if (> $mass 0) (fa-physical-sources $fact) (source-list ())))
          ($state (ledger-replace-member! $id (fa-obs $key)
             (forward-aggregate-observation $key (forward-base-rate-observation-value $fact) $sum $mass) true $sources)))
      (fa-publish-cache! $kb $pattern (fa-result (forward-base-rate-descriptor $kb $pattern) $state) base-rate)))

(: fa-remove! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-remove! $fact $id (forward-base-rate-descriptor $kb $pattern))
   (let* (($member (forward-fact-key $fact))
          ($key (brand ForwardAggregateObservationKey (quote ($id $member))))
          ($previous (fa-obs $key)))
      (if (== $previous ()) ()
         (let* (($state (ledger-remove-member! $id $key $previous))
                ((forward-aggregate-state $_id $_sum $mass $_members) $state))
            (if (<= $mass 0.0) (remove-produced-base-rate! $kb $pattern base-rate)
               (fa-publish-cache! $kb $pattern (fa-result (forward-base-rate-descriptor $kb $pattern) $state) base-rate))))))

;; The trigger directory answers a miss in one row. Reading the interests
;; directly is a scan once most of them share one trigger, as every rule's
;; antecedent base rate under one head does: bulk rule import then slows as
;; it grows (scripts/check_import_scaling.py ratio 1.9-2.1 against 1.0).
(: fa-maintain-key! (-[nondet]-> ForwardAggregateMaintenance (Statement KBContext Proof TV) ForwardTriggerKey (List $a)))
(= (fa-maintain-key! $action $fact $trigger)
   (let $hash (term_hash $trigger)
      (if (space-row-present? &ctx_forward_aggregate_triggers ($hash $trigger))
         (match &ctx_forward_aggregate_interest_by_trigger ($hash (forward-aggregate-interest $stored $id $descriptor))
         (if (== $stored $trigger)
            (case (copy_term $descriptor) (
               ((forward-class-link-descriptor $kb $sub $super $fold)
                  (let $_marked (fa-class-link-dirty! $kb $sub $super $fold () (the Statement (car-atom $fact))) ()))
               ($rate
                  (case $action (
                     (aggregate-update (fa-update! $fact $id $rate))
                     (aggregate-remove (fa-remove! $fact $id $rate)))))))
            (empty)))
         (empty))))

;; A class fact (C x) changes the sample of x in each class link over C: it
;; marks that sample changed, and the link's instance fold takes it when next
;; read (sk-instance-take-step), so a fact costs one mark per link.
(: fa-class-link-dirty! (-[det]-> KB Term Term SkeletonKey Atom Statement Atom))
(= (fa-class-link-dirty! $kb $sub $super $fold $_acc $type)
   (let $obj (car-atom (cdr-atom $type))
      (sk-rate-dirty! $fold
         (sk-key (ImplicationInstanceSample (cons $sub (cons $obj ())) (cons $super (cons $obj ())) $atv $btv)
            (make-kb-context $kb MAIN Nil)))))

;; A class link that registers marks the samples of the subjects its classes'
;; stored facts name, as a base rate counts the facts already stored.
(: fa-seed-class-link! (-[det]-> KB Term Term SkeletonKey Atom ForwardTriggerKey Atom))
(= (fa-seed-class-link! $kb $sub $super $fold $acc $trigger)
   (case $trigger (
      ((fwd_member $_kb $class)
         (fold-flat (fa-class-link-dirty! $kb $sub $super $fold) $acc
            (let $member (brand Statement (cons $class (cons $_obj ())))
               (list_to_set (collapse (match &kb ($member ($kb MAIN Nil) $_proof $_tv) (brand Statement $member)))))))
      ($_other $acc))))

;; The base-rate folds a fact counts in: those of the aggregates interested in
;; its triggers whose pattern the fact's statement matches, as the aggregate's
;; own update tests (fa-update!), and that a skeleton fold has read (see
;; sk-rate-take!). An ordered set, since an exclusion is tested by ordered-set
;; intersection.
(: fa-trigger-folds (-[det]-> Statement ForwardTriggerKey (List Number)))
(= (fa-trigger-folds $statement $trigger)
   (let $hash (term_hash $trigger)
      (collapse (match &ctx_forward_aggregate_interest_by_trigger ($hash (forward-aggregate-interest $stored $id $descriptor))
         (if (== $stored $trigger)
            (case (copy_term $descriptor) (
               ((forward-base-rate-descriptor $_kb $pattern)
                  (if (= $pattern (copy_term $statement)) (match &ctx_forward_aggregate_fold ($id $fold) $fold) (empty)))
               ($_other (match &ctx_forward_aggregate_fold ($id $fold) $fold))))
            (empty))))))

(: forward-rate-folds (-[det]-> (Statement KBContext Proof TV) (List Number)))
(= (forward-rate-folds $fact)
   (let* ((($head $wildcard) (forward-premise-keys $fact)) ($type (the Statement (car-atom $fact))))
      (hash-set
         (if (== $head $wildcard) (fa-trigger-folds $type $head)
            (append-flat (fa-trigger-folds $type $head) (fa-trigger-folds $type $wildcard))))))

;; A statement counts once, with its stored facts merged.
(: fa-seed-statement
   (-[det]-> KBContext (List (Statement KBContext Proof TV)) Statement (List (Statement KBContext Proof TV))))
(= (fa-seed-statement $kbctx $acc $statement)
   (case (stored-statement-candidate $statement $kbctx false) (
      ((forward-derived ($type $ctx $proof $tv) $ev)
         (cons (assemble-runtime-fact $type $ctx (fact-source $ev $proof) $tv) $acc))
      (no-forward-output-candidate $acc))))

;; A base rate a reader finds without an estimate is seeded: its aggregate
;; registers if it is new, and the facts already in the KB are counted as the
;; forward chainer counts them. Counting is per statement, so seeding an aggregate
;; the forward chainer already fed counts nothing twice. From then on forward
;; chaining keeps the estimate current as it processes facts. Only fold
;; premises with a forward subscription (at most one each) can be seeded.
(: forward-seed-fold! (-[semidet]-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (forward-seed-fold! $premise)
   (case (fa-premise-subscriptions $premise) (
      ((cons (fa-subscription $identity (forward-base-rate-descriptor $kb $pattern) $triggers) $_none)
         (let* (($descriptor (forward-base-rate-descriptor $kb $pattern))
                ($_registered (fa-register! $identity $descriptor $triggers))
                ($kbctx (make-kb-context $kb MAIN Nil))
                ($type (copy_term $pattern))
                ($facts (fold-flat (fa-seed-statement $kbctx) ()
                   (list_to_set (collapse (match &kb ($type $kbctx $_proof $_tv) (brand Statement $type))))))
                ($_counted
                   (case (collapse (fa-id $identity)) (
                      ((cons $id $_rest) (collapse (let $fact (superpose $facts) (fa-update! $fact $id (copy_term $descriptor)))))
                      (() ())))))
            true))
      ($_other false))))

(: forward-maintain-member-aggregates! (-[det]-> ForwardAggregateMaintenance (Statement KBContext Proof TV)(List $a)))
(= (forward-maintain-member-aggregates! $maintenance $fact)
   (case $fact (
      (($type ($kb MAIN Nil) $_proof $_tv)
         (case $type (
            (($concept $_obj) (collapse (fa-maintain-key! $maintenance $fact (fwd_member (brand KB $kb) (brand Term $concept)))))
            ($_other ()))))
      ($_other ()))))
(: forward-maintain-aggregates! (-[det]-> ForwardAggregateMaintenance (Statement KBContext Proof TV)(List $a)))
(= (forward-maintain-aggregates! $a $b)(let* ((($c $d)(forward-premise-keys $b))($e (collapse (fa-maintain-key! $a $b $c)))($f (if (== $c $d)()(collapse (fa-maintain-key! $a $b $d))))($g (forward-maintain-member-aggregates! $a $b)))()))


;; A statement's stored facts merged into one candidate: what the facts say
;; about the statement together. Materialized facts are not stored facts: the
;; skeleton derived them. A forward run's copy of a key's value is counted only
;; when asked for: a base rate counts stored facts and hears of copies from the
;; run that made them, while a membership read wants the latest value a run
;; reported. A copy is looked up under the key of the row matched, which an open
;; statement only finds once the match binds it.
(: stored-candidate-step
   (-[det]-> (| ForwardDerived NoForwardOutputCandidate) (Statement KBContext Proof TV) ForwardDerived))
(= (stored-candidate-step $acc ($type $kb $proof $tv))
   (let* (($fact (data $type $kb $proof $tv))
          ($ev (evidence-set (cons (fact-evidence-entry $kb $proof $type) ()))))
      (case $acc (
         (no-forward-output-candidate (forward-derived $fact $ev))
         ((forward-derived $current $current-ev)
            (case (collapse (once (sk-merge-facts false () $current $current-ev 0 $fact $ev 0))) (
               ((cons (sk-paired (sk-val $merged $merged-ev $_deps)) ()) (forward-derived $merged $merged-ev))
               ((cons (sk-overlap $_shared $_deps (sk-val $merged $merged-ev $_fdeps)) ()) (forward-derived $merged $merged-ev))
               ($_none (forward-derived $current $current-ev)))))))))
(: stored-statement-candidate
   (-[det]-> Statement KBContext Bool (| ForwardDerived NoForwardOutputCandidate)))
(= (stored-statement-candidate $type $kb $copies)
   (fold-flat stored-candidate-step no-forward-output-candidate
      (let $facts (kb-facts $type $kb)
         (collapse (let ($ftype $fkb $_proof $_tv) (superpose $facts)
            (let $fact (data $ftype $fkb $_proof $_tv)
               (if (materialized-forward-fact? $fact) (empty)
                  (if $copies $fact
                     (if (space-row-present? &sk_forward_stored ((index-hash (sk-key $ftype $fkb)) $_key $fact $_ev $_deps)) (empty) $fact)))))))))
