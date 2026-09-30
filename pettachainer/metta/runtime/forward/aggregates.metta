;; Forward subscriptions maintain additive state from per-key observations.
;; Identity hashes select candidates; full alpha comparison decides identity.
;; Fold descriptors share registration, observation replacement and cache publication.
;; The aggregate is a base rate's one estimate: backward folds update it too (sk-fold-view).
;; Publishing a value the cache already holds is skipped, since every store wakes the folds.
;; Ordinary base rates are seeded lazily when a fold first reads them.
;; Computed cache entries keep that source while forward deltas update statistics.
;; Removal rejoins the surviving Member facts before publishing the cache.
;; An added Member fact updates only its subscribed joins.
(: fa-id (-[semidet]-> ForwardAggregateIdentityKey Number))
(= (fa-id $a)(let $b (index-hash $a)(once (match &forward_aggregate_identity ($b (forward-aggregate-identity-row $c $d))(if (=alpha $c $a) $d (empty))))))
(: fa-register! (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor ForwardTriggerKey Bool ForwardTriggerKey (List $a)))
(= (fa-register! $a $b $c $d $e)(let $h (collapse (once (fa-id $a)))(if (== $h ())(let* (($f (index-hash $a))($g (term_hash $c))($k (next-search-id fwd_aggregate_id))(($i $l)(copy_term (quote ($a $b))))($m (the ForwardAggregateIdentityKey $i))($n (the ForwardAggregateDescriptor $l))($o (once (add-atom &forward_aggregate_identity ($f (forward-aggregate-identity-row $m $k)))))($p (once (add-atom &forward_aggregate_interest_by_trigger ($g (forward-aggregate-interest $c $k $n)))))($q (if $d (let* (($r (term_hash $e))($s (once (add-atom &forward_aggregate_interest_by_trigger ($r (forward-aggregate-interest $e $k $n))))))())()))($t (once (add-atom &forward_aggregate_state (forward-aggregate-state $k 0.0 0.0)))))())())))
;; What a fold premise asks the forward chainer to maintain: its aggregate
;; identity and descriptor, and the trigger keys whose facts update it (a
;; second trigger only for member inheritance between two concepts).
(: ForwardAggregateSubscription Type)
(: fa-subscription
   (-[det]-> ForwardAggregateIdentityKey ForwardAggregateDescriptor ForwardTriggerKey Bool
       ForwardTriggerKey ForwardAggregateSubscription))

(: fa-rate-subscription
   (-[det]-> KB Statement (| ExtractTV ExtractInheritanceTV)
       (| BaseRateEvidenceState BaseRateEvidenceWithPriorState) (-[semidet]-> $a $b $a)
       (| BaseRateFinish WeightedBaseRateInUniverseFinish WeightedBaseRateWithPriorInUniverseFinish)
       ForwardAggregateSubscription))
(= (fa-rate-subscription $kb $pattern $extractor $init $step $finish)
   (fa-subscription
      (forward-base-rate-identity $kb $pattern $extractor $init $step $finish result-tv)
      (forward-base-rate-descriptor $kb $pattern $extractor $init $step $finish)
      (forward-type-trigger-key $kb $pattern) false fwd_trigger_any))

;; The fold premises the forward chainer can maintain: plain and inheritance
;; base rates, and member inheritance between two ground concepts.
(: fa-premise-subscriptions
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (List ForwardAggregateSubscription)))
(= (fa-premise-subscriptions $premise)
   (case $premise (
      ((CPU FoldAllCompiled ($kb $pattern extract-tv (BaseRateEvidence $e $f) BaseRateAcc base-rate result-tv) $_r)
         (cons (fa-rate-subscription (brand KB $kb) (brand Statement $pattern) extract-tv
                  (BaseRateEvidence $e $f) BaseRateAcc base-rate)
            ()))
      ((CPU FoldAllCompiled
          ($kb $pattern (extract-inheritance-tv $ekb $estmt) (BaseRateEvidence $e $f) WeightedBaseRateAcc
             (weighted-base-rate-in-universe $ukb) result-tv) $_r)
         (cons (fa-rate-subscription (brand KB $kb) (brand Statement $pattern)
                  (extract-inheritance-tv (brand KB $ekb) (brand Statement $estmt))
                  (BaseRateEvidence $e $f) WeightedBaseRateAcc (weighted-base-rate-in-universe (brand KB $ukb)))
            ()))
      ((CPU FoldAllCompiled
          ($kb $pattern (extract-inheritance-tv $ekb $estmt) (BaseRateEvidenceWithPrior $prior (BaseRateEvidence $e $f))
             WeightedBaseRateWithPriorAcc (weighted-base-rate-with-prior-in-universe $ukb) result-tv) $_r)
         (cons (fa-rate-subscription (brand KB $kb) (brand Statement $pattern)
                  (extract-inheritance-tv (brand KB $ekb) (brand Statement $estmt))
                  (BaseRateEvidenceWithPrior (brand BaseRatePrior $prior) (BaseRateEvidence $e $f))
                  WeightedBaseRateWithPriorAcc (weighted-base-rate-with-prior-in-universe (brand KB $ukb)))
            ()))
      ((CPU FoldAllCompiled
          ($kb (MemberInheritanceSample $x $sub $super $s $c)
             (extract-value (MemberInheritanceSample $x $sub $super $s $c) (WeightedTv $s $c))
             (BaseRateEvidence 0.0 0.0) WeightedBaseRateAcc (member-inheritance $kb) result-tv) $_r)
         (if (== (extract-vars $sub) ())
            (if (== (extract-vars $super) ())
               (let* (($k (brand KB $kb))
                      ($j (brand Term $sub))
                      ($i (brand Term $super)))
                  (cons (fa-subscription (forward-member-inheritance-identity $k $j $i)
                           (forward-member-inheritance-descriptor $k $j $i
                              (brand Statement (MemberInheritanceSample $x $sub $super $s $c)))
                           (fwd_member $k $j) (not (== $j $i)) (fwd_member $k $i))
                     ()))
               ())
            ()))
      ($_other ()))))

;; A rule's fold premises register when the rule is stored. Query-local rules
;; register only member inheritance; their base rates wait for a reader.
(: fa-register-subscription! (-[det]-> Bool (List $a) ForwardAggregateSubscription (List $a)))
(= (fa-register-subscription! $live $acc (fa-subscription $identity $descriptor $trigger $both $second))
   (if (if $live true
          (case $descriptor (
             ((forward-member-inheritance-descriptor $_kb $_sub $_super $_stmt) true)
             ($_rate false))))
      (fa-register! $identity $descriptor $trigger $both $second)
      $acc))

(: fa-register-premise-step! (-[det]-> Bool (List $a) (| Goal (Statement KBContext Proof TV)) (List $a)))
(= (fa-register-premise-step! $live $acc $premise)
   (fold-flat (fa-register-subscription! $live) $acc (fa-premise-subscriptions $premise)))

(: register-forward-aggregate-premises! (-[det]-> Bool (List (| Goal (Statement KBContext Proof TV))) (List $a)))
(= (register-forward-aggregate-premises! $live $premises)
   (fold-flat (fa-register-premise-step! $live) () $premises))

(: fa-positive-ev (-[det]-> TV BaseRateEvidenceState))
(= (fa-positive-ev $a)(case $a ( ((STV $b $c)(BaseRateEvidence (* $b $c) $c))((CTV $d $e)(fa-positive-ev $d))($f (BaseRateEvidence 0.0 0.0)))))
(: forward-weighted-base-rate-contribution (-[det]-> TV TV BaseRateEvidenceState))
(= (forward-weighted-base-rate-contribution $a $b)(case $a ( ((STV $c $d)(case $b ( ((STV $e $f)(let $g (* (* $c $d) $f)(BaseRateEvidence (* $e $g) $g)))((CTV $h $i)(forward-weighted-base-rate-contribution $a $h))($j (BaseRateEvidence 0.0 0.0)))))($k (BaseRateEvidence 0.0 0.0)))))
(: fa-mass-scale (-[det]-> KB Number))
(= (fa-mass-scale $a)(let $c (kb-node-count $a subject-node)(if (<= $c 0) 0.0 (/ 1.0 $c))))
(: fa-acc (-[det]-> KB (| ExtractTV ExtractInheritanceTV)(| BaseRateEvidenceState BaseRateEvidenceWithPriorState)(-[semidet]-> $a $b $a) Number Number (| BaseRateEvidenceState BaseRateEvidenceWithPriorState)))
(= (fa-acc $a $b (BaseRateEvidence $c $d) BaseRateAcc $e $f)(BaseRateEvidence $e $f))
(= (fa-acc $a (extract-inheritance-tv $b $c)(BaseRateEvidence $d $e) WeightedBaseRateAcc $f $g)(let $h (fa-mass-scale $a)(BaseRateEvidence (* $h $f)(* $h $g))))
(= (fa-acc $a (extract-inheritance-tv $b $c)(BaseRateEvidenceWithPrior $d (BaseRateEvidence $e $f)) WeightedBaseRateWithPriorAcc $g $h)(let $i (fa-mass-scale $a)(BaseRateEvidenceWithPrior $d (BaseRateEvidence (* $i $g)(* $i $h)))))
(: fa-state (-[semidet]-> Number ForwardAggregateState))
(= (fa-state $a)(once (match &forward_aggregate_state (forward-aggregate-state $a $b $c)(forward-aggregate-state $a $b $c))))
(: fa-obs (-[det]-> ForwardAggregateObservationKey (List ForwardAggregateObservation)))
(= (fa-obs $a)(collapse (match &forward_aggregate_observation (forward-aggregate-observation $a $b $c $d)(forward-aggregate-observation $a $b $c $d))))
(: fa-swap! (-[semidet]-> Number (List ForwardAggregateObservation) ForwardAggregateObservation Bool ForwardAggregateState))
(= (fa-swap! $a $b (forward-aggregate-observation $c $d $e $f) $g)(let* ((($h $i)(case $b ( (()(data 0.0 0.0))((cons (forward-aggregate-observation $j $k $l $m) $n)(data $l $m)))))((forward-aggregate-state $o $p $q)(fa-state $a))($r (+ (- $p $h) $e))($s (+ (- $q $i) $f))($t (once (remove-atom &forward_aggregate_state (forward-aggregate-state $a $p $q))))($t2 (once (add-atom &forward_aggregate_state (forward-aggregate-state $a $r $s))))($u (remove-atom &forward_aggregate_observation (forward-aggregate-observation $c $_v $_w $_m)))($v (if $g (once (add-atom &forward_aggregate_observation (forward-aggregate-observation $c $d $e $f)))())))(forward-aggregate-state $a $r $s)))
(: fa-dist-acc (-[det]-> $a DistributionSumCount))
(= (fa-dist-acc $a)(the DistributionSumCount $a))
(: fa-ev-acc (-[det]-> $a BaseRateEvidenceState))
(= (fa-ev-acc $a)(the BaseRateEvidenceState $a))
(: fa-prior-acc (-[det]-> $a BaseRateEvidenceWithPriorState))
(= (fa-prior-acc $a)(the BaseRateEvidenceWithPriorState $a))
(: fa-list-acc (-[det]-> $a (List Atom)))
(= (fa-list-acc $a)(the (List Atom) $a))
;; A base-rate finish is read as the KB reads base rates (see
;; `smoothed-base-rate-tv`).
(: finish-aggregate (-[semidet]-> KB Expression Expression Atom))
(= (finish-aggregate $kb $a $b)(let $tv (case $a ( (identity $b)(dist-average (the Distribution (once (reduce (reduce (DistAverageFromSumCount (fa-dist-acc $b)))))))(base-rate (BaseRateTv (fa-ev-acc $b)))(weighted-base-rate (WeightedCountBaseRateTv (fa-ev-acc $b)))(weighted-base-rate-with-prior (let (BaseRateEvidenceWithPrior $f $d)(fa-prior-acc $b)(BaseRateWithPriorFormula (resolve-base-rate-prior $f)(WeightedCountBaseRateTv $d))))((member-inheritance $c)(member-inheritance-tv $c (fa-ev-acc $b)))(implication-instance (WeightedCountBaseRateTv (fa-ev-acc $b)))((weighted-base-rate-in-universe $c)(member-inheritance-tv $c (fa-ev-acc $b)))((weighted-base-rate-with-prior-in-universe $c)(let (BaseRateEvidenceWithPrior $f $d)(fa-prior-acc $b)(BaseRateWithPriorFormula (resolve-base-rate-prior $f)(member-inheritance-tv $c $d))))(uniform-prior (UniformPriorTv (fa-list-acc $b)))(uniform-prior-known (UniformPriorKnownTv (fa-list-acc $b))))) (if (base-rate-finish? $a)(smoothed-base-rate-tv $kb $tv) $tv)))
(: fa-member (-[det]-> KB Term Term (| ForwardDerived NoForwardOutputCandidate)))
(= (fa-member $a $b $c)(stored-statement-candidate (brand Statement (Member $b $c)) (make-kb-context $a MAIN Nil)))
(: fa-publish-cache! (-[det]-> KB Statement TV $a (List $b)))
(= (fa-publish-cache! $a $b $c $d)
   (case (base-rate-cache-entries-for-mode $a $b $d) (
      ((cons $entry $_rest) (if (== (base-rate-entry-tv $entry) $c) () (store-produced-base-rate! $a $b $c $d)))
      (() (store-produced-base-rate! $a $b $c $d)))))
(: FAggSample Type)
(: fa-sample (-[det]-> Atom ForwardAggregateObservationValue Number Number Bool FAggSample))
(: fa-sample-for (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-sample-for $a (forward-base-rate-descriptor $b $c $d $e $f $g))(let* ((($h ($i $j $k) $l $m)(copy_term $a))($n (let $c $h ok))((BaseRateEvidence $o $p)(fa-positive-ev $m)))(fa-sample (forward-fact-key $a)(forward-base-rate-observation-value $a) $o $p true)))
;; A Member fact counts for its subject with its membership in both concepts;
;; a member-inheritance fold sample counts for its subject too, so the two
;; replace each other.
(= (fa-sample-for $a (forward-member-inheritance-descriptor $b $c $d $e))
   (case (copy_term $a) (
      (((MemberInheritanceSample $sx $_ssub $_ssuper $smass $struth) $_skbctx $_sproof $_stv)
         (case (WeightedBaseRateAcc (BaseRateEvidence 0.0 0.0) (WeightedTv $smass $struth)) (
            ((BaseRateEvidence $sw $sm) (fa-sample (brand Term $sx) no-forward-aggregate-observation-value $sw $sm true)))))
      ($_member_fact(let* ((((Member $f $g)($h MAIN Nil) $i $j)(copy_term $a))($k (brand Term $f))($l (fa-member $b $k $c))($m (fa-member $b $k $d)))(case $l ( ((forward-derived $n $o)(case $m ( ((forward-derived $p $q)(let* ((($r $s $t $u) $n)(($v $w $x $y) $p)((BaseRateEvidence $z $v26)(forward-weighted-base-rate-contribution $u $y)))(fa-sample $k (forward-member-inheritance-observation-value $l $m) $z $v26 true)))(no-forward-output-candidate (fa-sample $k no-forward-aggregate-observation-value 0.0 0.0 false)))))(no-forward-output-candidate (fa-sample $k no-forward-aggregate-observation-value 0.0 0.0 false)))))))))
(: fa-store-cache! (-[semidet]-> ForwardAggregateMaintenance Number ForwardAggregateDescriptor Number Number (List $a)))
(= (fa-store-cache! $a $b (forward-base-rate-descriptor $c $d $e $f $g $h) $i $j)(if (and (== $a aggregate-remove)(<= $j 0.0))(remove-produced-base-rate! $c $d $h)(let* (($k (fa-acc $c $e $f $g $i $j))($l (the TV (finish-aggregate $c $h $k))))(fa-publish-cache! $c $d $l $h))))
(= (fa-store-cache! $a $b (forward-member-inheritance-descriptor $c $d $e $f) $g $h)(if (<= $h 0.0)(remove-produced-base-rate! $c $f (member-inheritance $c))(fa-publish-cache! $c $f (the TV (finish-aggregate $c (member-inheritance $c) (BaseRateEvidence $g $h))) (member-inheritance $c))))
(: fa-update! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-update! $a $b $c)(let* (($d (copy_term $c))((fa-sample $e $f $g $h $i)(fa-sample-for $a $c))($j (brand ForwardAggregateObservationKey (quote ($b $e))))((forward-aggregate-state $k $l $m)(fa-swap! $b (fa-obs $j)(forward-aggregate-observation $j $f $g $h) $i))($n (fa-store-cache! aggregate-update $b $d $l $m)))()))
(: fa-item (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-item $a (forward-base-rate-descriptor $b $c $d $e $f $g))(forward-fact-key $a))
(= (fa-item $a (forward-member-inheritance-descriptor $b $c $d $e))(let ((Member $f $g)($h MAIN Nil) $i $j)(copy_term $a)(brand Term $f)))
(: fa-remove! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-remove! $a $b $c)(let* (($d (copy_term $c))($e (fa-item $a $c))($f (brand ForwardAggregateObservationKey (quote ($b $e))))($g (fa-obs $f)))(if (== $g ())(case $d ( ((forward-member-inheritance-descriptor $h $i $j $k)(let (forward-aggregate-state $l $m $n)(fa-state $b)(if (<= $n 0.0)()(fa-store-cache! aggregate-update $b $d $m $n))))($o ())))(let* (((forward-aggregate-state $l $m $n)(fa-swap! $b $g (forward-aggregate-observation $f no-forward-aggregate-observation-value 0.0 0.0) false))($p (fa-store-cache! aggregate-remove $b $d $m $n)))(case $d ( ((forward-member-inheritance-descriptor $h $i $j $k)(progn (fa-update! $a $b $d)()))($o ())))))))
(: fa-maintain-key! (-[nondet]-> ForwardAggregateMaintenance (Statement KBContext Proof TV) ForwardTriggerKey (List $a)))
(= (fa-maintain-key! $a $b $c)(let $d (term_hash $c)(match &forward_aggregate_interest_by_trigger ($d (forward-aggregate-interest $e $f $g))(if (== $e $c)(case $a ( (aggregate-update (fa-update! $b $f (copy_term $g)))(aggregate-remove (fa-remove! $b $f (copy_term $g)))))(empty)))))
;; A statement counts once, with its stored facts merged.
(: fa-seed-statement
   (-[det]-> KBContext (List (Statement KBContext Proof TV)) Statement (List (Statement KBContext Proof TV))))
(= (fa-seed-statement $kbctx $acc $statement)
   (case (stored-statement-candidate $statement $kbctx) (
      ((forward-derived $fact $_ev) (cons $fact $acc))
      (no-forward-output-candidate $acc))))

;; A base rate a reader finds without an estimate is seeded: its aggregate
;; registers if it is new, and the facts already in the KB are counted as the
;; forward chainer counts them. Counting is per statement, so seeding an aggregate
;; the forward chainer already fed counts nothing twice. From then on forward
;; chaining keeps the estimate current as it processes facts. Only fold
;; premises with a forward subscription (at most one each) can be seeded.
(: fa-seed-facts
   (-[det]-> ForwardAggregateDescriptor ForwardTriggerKey (List (Statement KBContext Proof TV))))
(= (fa-seed-facts (forward-base-rate-descriptor $kb $pattern $_extractor $_init $_step $_finish) $_trigger)
   (let* (($kbctx (make-kb-context $kb MAIN Nil))
          ($type (copy_term $pattern)))
      (fold-flat (fa-seed-statement $kbctx) ()
         (list_to_set (collapse (match &kb ($type $kbctx $_proof $_tv) (brand Statement $type)))))))
(= (fa-seed-facts (forward-member-inheritance-descriptor $kb $_sub $_super $_stmt) $trigger)
   (case $trigger (
      ((fwd_member $_kb $concept)
         (let* (($kbctx (make-kb-context $kb MAIN Nil))
                ($member (brand Statement (Member $_x $concept))))
            (collapse (match &kb ($member $kbctx $proof $tv) (data $member $kbctx $proof $tv)))))
      ($_other ()))))

(: fa-seed-step (-[det]-> Number ForwardAggregateDescriptor Atom (Statement KBContext Proof TV) Atom))
(= (fa-seed-step $id $descriptor $_acc $fact)
   (let $_counted (collapse (fa-update! $fact $id (copy_term $descriptor))) ()))

(: fa-seed! (-[det]-> ForwardAggregateSubscription Atom))
(= (fa-seed! (fa-subscription $identity $descriptor $trigger $both $second))
   (let $_registered (fa-register! $identity $descriptor $trigger $both $second)
      (case (collapse (fa-id $identity)) (
         ((cons $id $_rest)
            (let $_first (fold-flat (fa-seed-step $id $descriptor) () (fa-seed-facts $descriptor $trigger))
               (if $both (fold-flat (fa-seed-step $id $descriptor) () (fa-seed-facts $descriptor $second)) ())))
         (() ())))))

(: forward-seed-fold! (-[semidet]-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (forward-seed-fold! $premise)
   (case (fa-premise-subscriptions $premise) (
      (() false)
      ((cons $subscription $_none) (let $_seeded (fa-seed! $subscription) true)))))

(: forward-maintain-member-aggregates! (-[det]-> ForwardAggregateMaintenance (Statement KBContext Proof TV)(List $a)))
(= (forward-maintain-member-aggregates! $a $b)(case $b ( (((Member $c $d)($e MAIN Nil) $f $g)(collapse (fa-maintain-key! $a $b (fwd_member (brand KB $e)(brand Term $d)))))($h ()))))
(: forward-maintain-aggregates! (-[det]-> ForwardAggregateMaintenance (Statement KBContext Proof TV)(List $a)))
(= (forward-maintain-aggregates! $a $b)(let* ((($c $d)(forward-premise-keys $b))($e (collapse (fa-maintain-key! $a $b $c)))($f (if (== $c $d)()(collapse (fa-maintain-key! $a $b $d))))($g (forward-maintain-member-aggregates! $a $b)))()))
