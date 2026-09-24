;; Forward subscriptions maintain additive canonical state with fixed rows and copy points.
;; Alpha-ground identity hashes always verify full keys; query-local registration tests only MemberInheritance.
;; Shared finish dispatch preserves wire tokens, universe fallback and prior order; ordinary base rates stay lazy at add time.
;; Empty Member cache keeps the largest settled budget and only matching additions refine it.
;; Computed rows keep that source while forward deltas patch sufficient statistics.
;; Computed merges retain subset or no-heavier incomparable incumbents; double removal republishes and rejoins surviving Member state.
;; Unqueued additions touch only that Member join.
(: fa-id (-[semidet]-> ForwardAggregateIdentityKey Number))
(= (fa-id $a)(let $b (index-hash $a)(once (match &forward_aggregate_identity ($b (forward-aggregate-identity-row $c $d))(if (=alpha $c $a) $d (empty))))))
(: fa-ordinary-row (-[semidet]-> KB Statement Atom))
(= (fa-ordinary-row $a $b)(let* (($c (forward-type-trigger-key $a $b))($d (term_hash $c)))(once (match &forward_aggregate_interest_by_trigger ($d (forward-aggregate-interest $e $f $g))(if (== $e $c)(case $g ( ((forward-base-rate-descriptor $h $i $j $k $l $m)(if (and (== $h $a)(=alpha $i $b))(data $f (the ForwardAggregateDescriptor $g))(empty)))($n (empty))))(empty))))))
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
(: finish-aggregate (-[semidet]-> Expression Expression Atom))
(= (finish-aggregate $a $b)(case $a ( (identity $b)(dist-average (the Distribution (once (reduce (reduce (DistAverageFromSumCount (fa-dist-acc $b)))))))(base-rate (BaseRateTv (fa-ev-acc $b)))(weighted-base-rate (WeightedCountBaseRateTv (fa-ev-acc $b)))(weighted-base-rate-with-prior (let (BaseRateEvidenceWithPrior $f $d)(fa-prior-acc $b)(BaseRateWithPriorFormula (resolve-base-rate-prior $f)(WeightedCountBaseRateTv $d))))((member-inheritance $c)(member-inheritance-tv $c (fa-ev-acc $b)))((weighted-base-rate-in-universe $c)(member-inheritance-tv $c (fa-ev-acc $b)))((weighted-base-rate-with-prior-in-universe $c)(let (BaseRateEvidenceWithPrior $f $d)(fa-prior-acc $b)(BaseRateWithPriorFormula (resolve-base-rate-prior $f)(member-inheritance-tv $c $d))))(uniform-prior (UniformPriorTv (fa-list-acc $b)))(uniform-prior-known (UniformPriorKnownTv (fa-list-acc $b))))))
(: fa-member (-[det]-> KB Term Term (| ForwardDerived NoForwardOutputCandidate)))
(= (fa-member $a $b $c)(let* (($d (brand Statement (Member $b $c)))($e (make-kb-context $a MAIN Nil))($g (collapse (once (match &forward_canonical_evidence (forward-canonical-evidence-row (term_hash (quote ($e $d))) $d $e $h $i)(forward-derived $h (stored-evidence-list $i))))))($j (if (== $g ())(collapse (once (match &kb ($d $e $l $m)(forward-derived (data $d $e $l $m)(forward-fact-evidence $d $e $l $m))))) $g)))(case $j ((() no-forward-output-candidate)((cons $candidate $_rest) $candidate)))))
(: forward-member-inheritance-id (-[semidet]-> KB Term Term Number))
(= (forward-member-inheritance-id $a $b $c)(fa-id (forward-member-inheritance-identity $a $b $c)))
(: fa-publish-cache! (-[det]-> KB Statement TV $a (List $b)))
(= (fa-publish-cache! $a $b $c $d)(case (base-rate-cache-entries-for-mode $a $b $d) ((()(store-produced-base-rate! $a $b $c forward-approx $d))((cons $e $f)(if (== (base-rate-entry-source $e) computed)(store-produced-base-rate! $a $b $c computed $d)(store-produced-base-rate! $a $b $c forward-approx $d))))))
(: fa-member-ev (-[semidet]-> ForwardAggregateObservationValue (List Evidence)))
(= (fa-member-ev (forward-member-inheritance-observation-value (forward-derived $a $b)(forward-derived $c $d)))(list_to_set (append-flat $b $d)))
(: forward-merge-computed-member-observation! (-[semidet]-> Number ForwardAggregateObservation (List $a)))
(= (forward-merge-computed-member-observation! $a (forward-aggregate-observation $b $c $d $e))(let* (($f (fa-obs $b))($g (forward-aggregate-observation $b $c $d $e)))(if (== $f ())(let $h (fa-swap! $a $f $g true)())(let (forward-aggregate-observation $i $j $k $l)(car-atom $f)(let* (($m (fa-member-ev $j))($n (fa-member-ev $c)))(if (evidence-subset? $n $m)()(if (and (not (evidence-subset? $m $n))(<= $e $l))()(let $h (fa-swap! $a $f $g true)()))))))))
(: FAggSample Type)
(: fa-sample (-[det]-> Atom ForwardAggregateObservationValue Number Number Bool FAggSample))
(: fa-sample-for (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-sample-for $a (forward-base-rate-descriptor $b $c $d $e $f $g))(let* ((($h ($i $j $k) $l $m)(copy_term $a))($n (let $c $h ok))((BaseRateEvidence $o $p)(fa-positive-ev $m)))(fa-sample (forward-fact-key $a)(forward-base-rate-observation-value $a) $o $p true)))
(= (fa-sample-for $a (forward-member-inheritance-descriptor $b $c $d $e))(let* ((((Member $f $g)($h MAIN Nil) $i $j)(copy_term $a))($k (brand Term $f))($l (fa-member $b $k $c))($m (fa-member $b $k $d)))(case $l ( ((forward-derived $n $o)(case $m ( ((forward-derived $p $q)(let* ((($r $s $t $u) $n)(($v $w $x $y) $p)((BaseRateEvidence $z $v26)(forward-weighted-base-rate-contribution $u $y)))(fa-sample $k (forward-member-inheritance-observation-value $l $m) $z $v26 true)))(no-forward-output-candidate (fa-sample $k no-forward-aggregate-observation-value 0.0 0.0 false)))))(no-forward-output-candidate (fa-sample $k no-forward-aggregate-observation-value 0.0 0.0 false))))))
(: fa-store-cache! (-[semidet]-> ForwardAggregateMaintenance Number ForwardAggregateDescriptor Number Number (List $a)))
(= (fa-store-cache! $a $b (forward-base-rate-descriptor $c $d $e $f $g $h) $i $j)(if (and (== $a aggregate-remove)(<= $j 0.0))(remove-produced-base-rate! $c $d $h)(let* (($k (fa-acc $c $e $f $g $i $j))($l (the TV (finish-aggregate $h $k))))(fa-publish-cache! $c $d $l $h))))
(= (fa-store-cache! $a $b (forward-member-inheritance-descriptor $c $d $e $f) $g $h)(if (<= $h 0.0)(remove-produced-base-rate! $c $f (member-inheritance $c))(fa-publish-cache! $c $f (member-inheritance-tv $c (BaseRateEvidence $g $h)) (member-inheritance $c))))
(: fa-update! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-update! $a $b $c)(let* (($d (copy_term $c))((fa-sample $e $f $g $h $i)(fa-sample-for $a $c))($j (brand ForwardAggregateObservationKey (quote ($b $e))))((forward-aggregate-state $k $l $m)(fa-swap! $b (fa-obs $j)(forward-aggregate-observation $j $f $g $h) $i))($n (fa-store-cache! aggregate-update $b $d $l $m)))()))
(: fa-item (-[semidet]-> (Statement KBContext Proof TV) ForwardAggregateDescriptor Atom))
(= (fa-item $a (forward-base-rate-descriptor $b $c $d $e $f $g))(forward-fact-key $a))
(= (fa-item $a (forward-member-inheritance-descriptor $b $c $d $e))(let ((Member $f $g)($h MAIN Nil) $i $j)(copy_term $a)(brand Term $f)))
(: fa-remove! (-[semidet]-> (Statement KBContext Proof TV) Number ForwardAggregateDescriptor (List $a)))
(= (fa-remove! $a $b $c)(let* (($d (copy_term $c))($e (fa-item $a $c))($f (brand ForwardAggregateObservationKey (quote ($b $e))))($g (fa-obs $f)))(if (== $g ())(case $d ( ((forward-member-inheritance-descriptor $h $i $j $k)(let (forward-aggregate-state $l $m $n)(fa-state $b)(if (<= $n 0.0)()(fa-store-cache! aggregate-update $b $d $m $n))))($o ())))(let* (((forward-aggregate-state $l $m $n)(fa-swap! $b $g (forward-aggregate-observation $f no-forward-aggregate-observation-value 0.0 0.0) false))($p (fa-store-cache! aggregate-remove $b $d $m $n)))(case $d ( ((forward-member-inheritance-descriptor $h $i $j $k)(progn (fa-update! $a $b $d)()))($o ())))))))
(: fa-maintain-key! (-[nondet]-> ForwardAggregateMaintenance (Statement KBContext Proof TV) ForwardTriggerKey (List $a)))
(= (fa-maintain-key! $a $b $c)(let $d (term_hash $c)(match &forward_aggregate_interest_by_trigger ($d (forward-aggregate-interest $e $f $g))(if (== $e $c)(case $a ( (aggregate-update (fa-update! $b $f (copy_term $g)))(aggregate-remove (fa-remove! $b $f (copy_term $g)))))(empty)))))
;; A base rate a reader finds without an estimate is seeded: its aggregate
;; registers if it is new, and the facts already in the KB are counted as the
;; forward chainer counts them. Counting is per fact, so seeding an aggregate
;; the forward chainer already fed counts nothing twice. From then on forward
;; chaining keeps the estimate current as it processes facts. Only fold
;; premises with a forward subscription (at most one each) can be seeded.
(: fa-seed-facts
   (-[det]-> ForwardAggregateDescriptor ForwardTriggerKey (List (Statement KBContext Proof TV))))
(= (fa-seed-facts (forward-base-rate-descriptor $kb $pattern $_extractor $_init $_step $_finish) $_trigger)
   (let* (($kbctx (make-kb-context $kb MAIN Nil))
          ($type (copy_term $pattern)))
      (collapse (match &kb ($type $kbctx $proof $tv) (data $type $kbctx $proof $tv)))))
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
(: forward-apply-unqueued-member-change! (-[det]-> ForwardOutputChange (List $a)))
(= (forward-apply-unqueued-member-change! $a)(case $a ( (no-forward-change ())((forward-output-added $b)(forward-maintain-member-aggregates! aggregate-update $b))((forward-output-replaced $c $b)(forward-maintain-member-aggregates! aggregate-update $b))((forward-output-removed $c)()))))
