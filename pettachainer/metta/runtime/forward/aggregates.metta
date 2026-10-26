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
(: fa-id (-[semidet]-> ForwardAggregateIdentityKey Number))
(= (fa-id $a)(let $b (index-hash $a)(once (match &ctx_forward_aggregate_identity ($b (forward-aggregate-identity-row $c $d))(if (=alpha $c $a) $d (empty))))))
;; A typed callback keeps interest insertion from changing the sharing of
;; the descriptor copied by fa-register! during fold specialization.
(: fa-add-interest! (-[det]-> Number ForwardAggregateDescriptor Atom ForwardTriggerKey Atom))
(= (fa-add-interest! $id $descriptor $_acc $trigger)
   (let* (($hash (term_hash $trigger))
          ($_interest (once (context-add! &forward_aggregate_interest_by_trigger
             ($hash (forward-aggregate-interest $trigger $id $descriptor))))))
      (if (space-row-present? &ctx_forward_aggregate_triggers ($hash $trigger)) ()
         (let $_added (once (context-add! &forward_aggregate_triggers ($hash $trigger))) ()))))
;; Identity and descriptor are copied together, so they keep sharing variables.
(: fa-register! (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor (List ForwardTriggerKey) (List $a)))
(= (fa-register! $identity $descriptor $triggers)
   (if (== (collapse (once (fa-id $identity))) ())
      (let* (($hash (index-hash $identity))
             ($id (next-search-id fwd_aggregate_id))
             (($i $d) (copy_term (quote ($identity $descriptor))))
             ($stored-identity (the ForwardAggregateIdentityKey $i))
             ($stored-descriptor (the ForwardAggregateDescriptor $d))
             ($_identity (once (context-add! &forward_aggregate_identity
                ($hash (forward-aggregate-identity-row $stored-identity $id)))))
             ($_state (once (context-add! &forward_aggregate_state ($id 0.0 0.0 0))))
             ($_interests (fold-flat (fa-add-interest! $id $stored-descriptor) () (the (List ForwardTriggerKey) $triggers))))
         ())
      ()))

;; What a fold premise asks the forward chainer to maintain: its aggregate
;; identity and descriptor, and the trigger keys whose facts update it, in
;; order (two only for a class link between two distinct classes).
(: ForwardAggregateSubscription Type)
(: fa-subscription
   (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor (List ForwardTriggerKey)
       ForwardAggregateSubscription))

(: fa-rate-subscription
   (-[det]-> KB Statement ExtractTV BaseRateEvidenceState (-[semidet]-> $a $b $a) BaseRateFinish
       ForwardAggregateSubscription))
(= (fa-rate-subscription $kb $pattern $extractor $init $step $finish)
   (fa-subscription
      (forward-base-rate-identity $kb $pattern $extractor $init $step $finish result-tv)
      (forward-base-rate-descriptor $kb $pattern $extractor $init $step $finish)
      (cons (forward-type-trigger-key $kb $pattern) ())))

;; The fold premises the forward chainer can maintain: plain base rates, and
;; the instance fold of a class link (A $x) -> (B $x) between two classes.
(: fa-premise-subscriptions
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (List ForwardAggregateSubscription)))
(= (fa-premise-subscriptions $premise)
   (case $premise (
      ((CPU FoldAllCompiled ($kb $pattern extract-tv (BaseRateEvidence $e $f) BaseRateAcc base-rate result-tv) $_r)
         (cons (fa-rate-subscription (brand KB $kb) (brand Statement $pattern) extract-tv
                  (BaseRateEvidence $e $f) BaseRateAcc base-rate)
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
(: fa-acc (-[det]-> KB ExtractTV BaseRateEvidenceState (-[semidet]-> $a $b $a) Number Number BaseRateEvidenceState))
(= (fa-acc $a $b (BaseRateEvidence $c $d) BaseRateAcc $e $f)(BaseRateEvidence $e $f))
(: fa-state (-[semidet]-> Number ForwardAggregateState))
(= (fa-state $id)
   (once (match &ctx_forward_aggregate_state ($id $sum $mass $members)
      (forward-aggregate-state $id $sum $mass $members))))
(: fa-obs (-[det]-> ForwardAggregateObservationKey (List ForwardAggregateObservation)))
(= (fa-obs $a)(let $h (index-hash $a)(collapse (match &ctx_forward_aggregate_observation ($h $a $b $c $d $_sources)(forward-aggregate-observation $a $b $c $d)))))
(: fa-physical-sources (-[semidet]-> SkFact SourceList))
(= (fa-physical-sources ($type $ctx $proof $_tv))
   (if (is-expr $proof)
      (observation-sources (proof-term-evidence proof-walk-in-kb $proof))
      (observation-sources (fact-evidence-entry $ctx $proof $type))))

(: fa-read-step (-[det]-> Number (List ForwardAggregateObservationKey) Number (List ForwardAggregateObservationKey)))
(= (fa-read-step $id $keys $read) (append-flat (aggregate-readers $id $read) $keys))

;; In the standard order of their keys, never the exclusion's hash order: the
;; hashes include the process's KB id, and subtraction order shows in the sum.
(: fa-left-out (-[det]-> Number (List Number) (List ForwardAggregateObservation)))
(= (fa-left-out $id $exclude)
   (fold-flat append-flat () (map-flat fa-obs
      (sort-atom (list_to_set (fold-flat (fa-read-step $id) () $exclude))))))

(: fa-result (-[semidet]-> ForwardAggregateDescriptor ForwardAggregateState TV))
(= (fa-result (forward-base-rate-descriptor $kb $_pattern $extractor $init $step $finish)
      (forward-aggregate-state $_id $sum $mass $_members))
   (the TV (finish-aggregate $kb $finish (fa-acc $kb $extractor $init $step $sum $mass))))

(: fa-subtract-step (-[det]-> ForwardAggregateState ForwardAggregateObservation ForwardAggregateState))
(= (fa-subtract-step (forward-aggregate-state $id $sum $mass $members)
      (forward-aggregate-observation $_key $_value $s $m))
   (let $remaining (- $members (if (> $m 0) 1 0))
      (if (<= $remaining 0) (forward-aggregate-state $id 0.0 0.0 0)
         (forward-aggregate-state $id (- $sum $s) (max 0.0 (- $mass $m)) $remaining))))

(: fa-swap! (-[semidet]-> Number (List ForwardAggregateObservation) ForwardAggregateObservation Bool SourceList ForwardAggregateState))
(= (fa-swap! $id $previous (forward-aggregate-observation $key $value $sum $mass) $keep $sources)
   (let* ((($old-sum $old-mass)
             (case $previous (
                (() (data 0.0 0.0))
                ((cons (forward-aggregate-observation $_key $_value $s $m) $_rest) (data $s $m)))))
          ((forward-aggregate-state $_id $total $weight $members) (fa-state $id))
          ($new-count (+ $members (- (if (if $keep (> $mass 0) false) 1 0) (if (> $old-mass 0) 1 0))))
          ($new-sum (if (<= $new-count 0) 0.0 (+ $total (- $sum $old-sum))))
          ($new-mass (if (<= $new-count 0) 0.0 (+ $weight (- $mass $old-mass))))
          ($_old-state (once (context-remove! &forward_aggregate_state ($id $total $weight $members))))
          ($_new-state (once (context-add! &forward_aggregate_state ($id $new-sum $new-mass $new-count))))
          ($hash (index-hash $key))
          ($old-sources (chainer-first-or (source-list ()) (collapse (once
             (match &ctx_forward_aggregate_observation ($hash $key $_old-v $_old-s $_old-m $reads) $reads)))))
          ($_sources (update-aggregate-sources! $id $key $old-sources (if (> $old-mass 0) 1 0)
                         $sources (if (if $keep (> $mass 0) false) 1 0)))
          ($_old (context-remove! &forward_aggregate_observation ($hash $key $_value $_sum $_mass $_reads)))
          ($_new (if $keep
                    (once (context-add! &forward_aggregate_observation ($hash $key $value $sum $mass $sources))) ())))
      (forward-aggregate-state $id $new-sum $new-mass $new-count)))

(: fa-dist-acc (-[det]-> $a DistributionSumCount))
(= (fa-dist-acc $a)(the DistributionSumCount $a))
(: fa-ev-acc (-[det]-> $a BaseRateEvidenceState))
(= (fa-ev-acc $a)(the BaseRateEvidenceState $a))
(: fa-instance-acc (-[det]-> $a InstanceEvidenceState))
(= (fa-instance-acc $a)(the InstanceEvidenceState $a))
;; A base-rate finish is read as the KB reads base rates (see
;; `smoothed-base-rate-tv`).
(: finish-aggregate (-[semidet]-> KB Expression Expression Atom))
(= (finish-aggregate $kb $a $b)(let $tv (case $a ( (identity $b)(dist-average (the Distribution (once (reduce (reduce (DistAverageFromSumCount (fa-dist-acc $b)))))))(base-rate (BaseRateTv (fa-ev-acc $b)))(implication-instance (case (fa-instance-acc $b) (((InstanceEvidence $pos $_neg) (WeightedCountBaseRateTv $pos)))))(implication-instance-ctv (ImplicationInstanceTv (fa-instance-acc $b))))) (if (base-rate-finish? $a)(smoothed-base-rate-tv $kb $tv) $tv)))
(: fa-publish-cache! (-[det]-> KB Statement TV $a (List $b)))
(= (fa-publish-cache! $a $b $c $d)
   (case (base-rate-cache-entries-for-mode $a $b $d) (
      ((cons $entry $_rest) (if (== (base-rate-entry-tv $entry) $c) () (store-produced-base-rate! $a $b $c $d)))
      (() (store-produced-base-rate! $a $b $c $d)))))
(: FAggSample Type)
(: fa-sample (-[det]-> Atom ForwardAggregateObservationValue Number Number Bool FAggSample))
(: fa-sample-for (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-sample-for $a (forward-base-rate-descriptor $b $c $d $e $f $g))(let* ((($h ($i $j $k) $l $m)(copy_term $a))($n (let $c $h ok))((BaseRateEvidence $o $p)(fa-positive-ev $m)))(fa-sample (forward-fact-key $a)(forward-base-rate-observation-value $a) $o $p true)))
(: fa-store-cache! (-[semidet]-> ForwardAggregateMaintenance Number ForwardAggregateDescriptor Number Number (List $a)))
(= (fa-store-cache! $a $b (forward-base-rate-descriptor $c $d $e $f $g $h) $i $j)(if (and (== $a aggregate-remove)(<= $j 0.0))(remove-produced-base-rate! $c $d $h)(let* (($k (fa-acc $c $e $f $g $i $j))($l (the TV (finish-aggregate $c $h $k))))(fa-publish-cache! $c $d $l $h))))
(: fa-update! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-update! $fact $id $descriptor)
   (let* (($publish-descriptor (copy_term $descriptor))
          ((fa-sample $member $value $sum $mass $keep) (fa-sample-for $fact $descriptor))
          ($key (brand ForwardAggregateObservationKey (quote ($id $member))))
          ($sources (if (if $keep (> $mass 0) false) (fa-physical-sources $fact) (source-list ())))
          ((forward-aggregate-state $_id $total $weight $_members)
             (fa-swap! $id (fa-obs $key) (forward-aggregate-observation $key $value $sum $mass) $keep $sources))
          ($_published (fa-store-cache! aggregate-update $id $publish-descriptor $total $weight))) ()))

(: fa-item (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-item $a (forward-base-rate-descriptor $b $c $d $e $f $g))(forward-fact-key $a))
(: fa-remove! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-remove! $a $b $c)(let* (($d (copy_term $c))($e (fa-item $a $c))($f (brand ForwardAggregateObservationKey (quote ($b $e))))($g (fa-obs $f)))(if (== $g ()) () (let (forward-aggregate-state $l $m $n $_members)(fa-swap! $b $g (forward-aggregate-observation $f no-forward-aggregate-observation-value 0.0 0.0) false (source-list ()))(fa-store-cache! aggregate-remove $b $d $m $n)))))

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

;; Base rates and implication instance folds follow their members
;; incrementally, as a tally of each member's contribution (see sk-fold-view).
(: sk-instance-fold? (-[det]-> Atom Bool))
(= (sk-instance-fold? ($_kb $_pattern $_extractor $_init $_function $finish $_mode))
   (stored-list-member? $finish (implication-instance implication-instance-ctv)))

(: sk-instance-fold-key? (-[det]-> SkeletonKey Bool))
(= (sk-instance-fold-key? $key)
   (case $key (((sk-fold $args) (sk-instance-fold? $args)) ($_other false))))

(: sk-rate-fold? (-[det]-> SkeletonKey Bool))
(= (sk-rate-fold? $key)
   (if (sk-instance-fold-key? $key) true
      (case $key (
         ((sk-fold ($_kb $_pattern $_extractor $_init $_function $finish $_mode)) (base-rate-finish? $finish))
         ($_other false)))))

;; A member that joined a tally fold, or whose value changed, is taken into it
;; when a query next needs the fold or it is next read; an implication
;; instance fold is also brought current by the evaluation (see
;; sk-instance-checks!).
(: sk-rate-dirty! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-rate-dirty! $fold $member)
   (if (sk-rate-fold? $fold)
      (let* (($hash (index-hash $fold)) ($mhash (index-hash $member)))
         (if (== (collapse (once (match &ctx_sk_rate_dirty ($hash $mhash $stored-fold $stored)
                    (if (=alpha $stored $member) (if (=alpha $stored-fold $fold) true (empty)) (empty)))))
                 ())
            (let* (($_row (context-add! &sk_rate_dirty ($hash $mhash $fold $member)))
                   ($_changed
                      (if (if (sk-instance-fold-key? $fold) (not (space-row-present? &ctx_sk_instance_changed ($hash $_stored))) false)
                         (context-add! &sk_instance_changed ($hash $fold))
                         ())))
               ())
            ()))
      ()))

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
;; own update tests (fa-sample-for), and that a skeleton fold has read (see
;; sk-rate-take!). An ordered set, since an exclusion is tested by ordered-set
;; intersection.
(: fa-trigger-folds (-[det]-> Statement ForwardTriggerKey (List Number)))
(= (fa-trigger-folds $statement $trigger)
   (let $hash (term_hash $trigger)
      (collapse (match &ctx_forward_aggregate_interest_by_trigger ($hash (forward-aggregate-interest $stored $id $descriptor))
         (if (== $stored $trigger)
            (case (copy_term $descriptor) (
               ((forward-base-rate-descriptor $_kb $pattern $_extractor $_init $_function $_finish)
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
      ((cons (fa-subscription $identity (forward-base-rate-descriptor $kb $pattern $extractor $init $step $finish) $triggers) $_none)
         (let* (($descriptor (forward-base-rate-descriptor $kb $pattern $extractor $init $step $finish))
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
