;; Backward aggregates spawn, fold, restore and commit; forward owns subscriptions.
;; Wire args start with kb/pattern and share forward finish dispatch at typed boundaries.
;; Scalar keeps one pid; grouped keeps the latest per snapshot key; base-rate restore requires a nonempty proof.
;; Refinement publishes a changed cached snapshot before scheduling its live refold; cycles are rejected before child merging.
;; Background commits use empty evidence; degrading base rates drop unless forward-approx.
;; Replaced incumbents deactivate, and proof history stays durable.
(: ba-child (-[nondet]-> Goal (| Goal (Statement KBContext Proof TV))))
(= (ba-child (CPU $a $b $c))(let* (($d (car-atom $b))($e (car-atom (cdr-atom $b)))((compiled-query $f $g)(the CompiledQuery (eval (mm2compileQuery $d (: $h $e $i))))))(if (or (is-var $f)(is-var $g))(empty)(let $_ (once (inject-compiled-adds $g))(typed-runtime-premise $f)))))
(: ba-step-acc (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)(-[semidet]-> $a Atom $a) $a $b (| TV NoTV) $a))
(= (ba-step-acc $a $b $c $d $e)(case $a ( ((extract-value $f $g)(let ($f ($h $i $j) $k $l)(copy_term $d)($b $c $g)))((extract-inheritance-tv $m $n)(let ((Inheritance $o $p)($h $i $j) $k $l)(copy_term $d)($b $c (WeightedTv (inheritance-subject-prior-tv $m (brand Statement $o)) $e))))(extract-tv ($b $c $e)))))
(: ba-durable (-[semidet]-> Number $a (List Number)))
(: ba-restorable (-[semidet]-> (List Number)(List Number)))
(= (ba-restorable ())())
(= (ba-restorable (cons $a $b))(let $c (ba-restorable $b)(if (== (proof-children-by-id $a)()) $c (if (proof-current-representative? $a)(cons $a $c) $c))))
(: ba-wake (-[semidet]-> (Heap AgendaEntry) Number (List Number)(Heap AgendaEntry)))
(= (ba-wake $a $b ()) $a)
(= (ba-wake $a $b (cons $c $d))(ba-wake (wake-proof-commit-heap $a $b $c) $b $d))
(= (ba-durable $a $b)(let* (($c (case (base-rate-aggregate-key $b)( ((base-rate-aggregate-key-value $d $e $g)(ba-restorable (goal-proof-ids $a)))(no-base-rate-aggregate-key (goal-proof-ids $a)))))($f (latest-proof-output-group-ids (aggregate-snapshot-groups $c))))(if (ba-grouped? $b) $f (case $f ( (()())((cons $g $h)(cons $g ())))))))
(: ba-ensure-child (-[nondet]-> Number Goal $a Number Number))
(= (ba-ensure-child $a $b $c $d)(let* (($e (ba-child $b))((stored-goal-row $f $g $h $i $j)(goal-by-id $a))($k (ensure-goal-at-depth $e (+ 1 $g)))($l (collapse (once (match &aggregate (stored-aggregate-row $a $m $n $o $p $q) true))))($r (if (== $l ())(let $s (ba-durable $a $c)(progn (once (chainer-add-atom &aggregate (stored-aggregate-row $a $k $c $d 0.0 $s)))()))()))) $k))
(: ba-refine (-[nondet]-> (Heap AgendaEntry) Number Number Goal $a TV BaseRateSource (Heap AgendaEntry)))
(= (ba-refine $a $b $c $d $e $f $g)(let* (($h (ba-ensure-child $c $d $e $b))((stored-aggregate-row $j $k $l $m $n $o)(aggregate-by-id $c))($p (if (== $g forward-approx)(add-atom &aggregate_forward_approx ($c))()))($q (register-goal-waiter! $h $c (aggregate-waiter $c (cached-aggregate-demand $f))))($r (CPU FoldAllCompiled $e $f))($s (if (aggregate-snapshot-changed? $o $r ())(commit-aggregate-snapshot-heap $a $c $r ()())(ba-wake $a $c $o))))(wake-goal-demand-heap $s $h)))
(: spawn-aggregate-goal-heap (-[nondet]-> (Heap AgendaEntry) Number Number Number Goal (Heap AgendaEntry)))
(= (spawn-aggregate-goal-heap $a $b $c $d $e)(let* (($f (copy_term (let (CPU $g $h $i) $e $h)))($j (once (chainer-add-atom &aggregate_search_budget (aggregate-search-budget-row $d $b))))($k (base-rate-aggregate-key $f))($l (if (pending-base-rate-retires?)(case $k ( ((base-rate-aggregate-key-value $_kbid $_pattern $_mode)(consume-pending-base-rate-retire-key! (the BaseRateAggregateKey $k)))(no-base-rate-aggregate-key false)))false)))(case $k ( ((base-rate-aggregate-key-value $m $n $o)(if (and $l (case $o ( ((member-inheritance $_member-kbid) false)($_other true))))(ba-spawn-live $a $c $d $e $f)(ba-spawn-cached $a $b $c $d $e $f (base-rate-cache-entries-for-mode $m $n $o))))(no-base-rate-aggregate-key (ba-spawn-live $a $c $d $e $f))))))
(: ba-spawn-cached (-[nondet]-> (Heap AgendaEntry) Number Number Number Goal $a (List BaseRateEntry)(Heap AgendaEntry)))
(= (ba-spawn-cached $a $b $c $d $e $f $g)(case $g ( (()(if (case $f ( (($h (MemberInheritanceSample $i $j $k $l $m) $n $o $p (member-inheritance $h) $q)(forward-member-inheritance-empty-cache-hit? (brand KB $h)(brand Term $j)(brand Term $k) $b))($r false))) $a (ba-spawn-live $a $c $d $e $f)))((cons $s $t)(let* (($u (base-rate-entry-tv $s))($v (base-rate-entry-source $s)))(if (== $v user)(let $w (once (store-proof-candidate $d (aggregate-result-candidate (CPU FoldAllCompiled $f $u)()())))(wake-proof-commit-heap $a $d $w))(ba-refine $a $c $d $e $f $u $v)))))))
(: AggregateSearchBudgetRow Type)
(: aggregate-search-budget-row (-[det]-> Number Number AggregateSearchBudgetRow))
(: ba-spawn-live (-[nondet]-> (Heap AgendaEntry) Number Number Goal $a (Heap AgendaEntry)))
(= (ba-spawn-live $a $b $c $d $e)(let* (($f (ba-ensure-child $c $d $e $b))($g (register-goal-waiter! $f $c (aggregate-waiter $c live-aggregate-demand))))(schedule-aggregate-heap (wake-goal-demand-heap $a $f) $c)))
(: ba-grouped? (-[det]-> $a Bool))
(= (ba-grouped? $a)(case $a ( (($b $c $d $e $f $g $h $i) true)($j false))))
(: ba-source-step (-[semidet]-> (List Number) Number (List Number)))
(= (ba-source-step $a $b)(case (proof-kind-by-id $b)( ((leaf ($c $d $e $f))(if (materialized-aggregate-forward-fact? (assemble-stored-runtime-fact $c $d $e $f)) $a (cons $b $a)))($g (cons $b $a)))))
(: ba-source-pids (-[semidet]-> Number Number (List Number)))
(= (ba-source-pids $a $b)(let $c (reverse-number-list (proof-fold-flat-semidet ba-source-step ()(noncyclic-proof-source-ids $a closed-goal $b)))(proof-output-group-representative-pids $b (proof-output-groups $c))))
(: ba-child-tv (-[det]-> (| Goal (Statement KBContext Proof TV))(| TV NoTV)))
(= (ba-child-tv $a)(case $a ( ((CPU $b $c $d) no-tv)(($e $f $g $h) $h))))
(: ba-scalar-step (-[semidet]-> (KB Statement (| ExtractValue ExtractInheritanceTV ExtractTV) $a (-[semidet]-> $b $c $b) $d AggregateTVMode) AggregateState Number AggregateState))
(= (ba-scalar-step $a (aggregate-state $b $c $d) $e)(let* ((($f $g $h $i $j $k $l)(copy_term $a))(($m $n (proof-support $o $p $q) $r)(proof-row-by-id $e))($s (ba-step-acc $h $j $b $m (ba-child-tv $m))))(aggregate-state $s (list_to_set (append-flat $c $p))(append-flat $d ($e)))))
(: ba-scalar-state (-[semidet]-> Number Number (KB Statement (| ExtractValue ExtractInheritanceTV ExtractTV) $a (-[semidet]-> $b $c $b) $d AggregateTVMode) AggregateState))
(= (ba-scalar-state $a $b $c)(let ($d $e $f $g $h $i $j)(copy_term $c)(proof-fold-flat-semidet (ba-scalar-step $c)(aggregate-state $g ()())(ba-source-pids $a $b))))
(: ba-group-add (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)(-[semidet]-> $a $b $a) $a $c $d (| TV NoTV)(List Evidence) Number (List AggregateGroupState)(List AggregateGroupState)))
(= (ba-group-add $a $b $c $d $e $f $g $h ())(let* (($i (ba-step-acc $a $b $c $e $f))($j (list_to_set $g)))(cons (aggregate-group-state $d $i $j ($h))())))
(= (ba-group-add $a $b $c $d $e $f $g $h (cons (aggregate-group-state $i $j $k $l) $m))(if (== $d $i)(let* (($n (ba-step-acc $a $b $j $e $f))($o (list_to_set (append-flat $k $g)))($p (append-flat $l ($h))))(cons (aggregate-group-state $i $n $o $p) $m))(cons (aggregate-group-state $i $j $k $l)(ba-group-add $a $b $c $d $e $f $g $h $m))))
(: ba-group-step (-[semidet]-> (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b (-[semidet]-> $c $d $c) $e AggregateTVMode)(List AggregateGroupState) Number (List AggregateGroupState)))
(= (ba-group-step $a $b $c)(let* ((($d $e $f $g $h $i $j $k)(copy_term $a))(($l $m (proof-support $n $o $p) $q)(proof-row-by-id $c))($r (let ($e ($s $t $u) $v $w)(copy_term $l) $f)))(ba-group-add $g $i $h $r $l (ba-child-tv $l) $o $c $b)))
(: ba-group-states (-[semidet]-> Number Number (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b (-[semidet]-> $c $d $c) $e AggregateTVMode)(List AggregateGroupState)))
(= (ba-group-states $a $b $c)(proof-fold-flat-semidet (ba-group-step $c)()(ba-source-pids $a $b)))
(: ba-commit-state (-[semidet]-> Number (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b (-[semidet]-> $c $d $c) AggregateFinish AggregateTVMode)(Heap AgendaEntry) AggregateGroupState (Heap AgendaEntry)))
(: ba-current? (-[semidet]-> ProofCandidate (List Number) Bool))
(= (ba-current? $a ()) false)
(= (ba-current? (proof-candidate $a $b $c $d)(cons $e $f))(let* (($g (candidate-kind-term $a))(($h $i (proof-support $j $k $l) $m)(proof-row-by-id $e)))(if (and (=alpha $h $g)(and (== $j $b)(== $k $c))) true (ba-current? (proof-candidate $a $b $c $d) $f))))
(= (ba-commit-state $a $b $c (aggregate-group-state $d $e $f $g))(let* ((($h $i $j $k $l $m $n $o) $b)($p (CPU GroupedFoldAllCompiled (quote ($h $i $d $k $l $m $n $o))(finish-aggregate $n $e)))($q (aggregate-result-candidate $p $f $g))((stored-aggregate-row $r $s $t $u $v $w)(aggregate-by-id $a))($x (if (ba-current? $q $w) false (classify-goal-proof-candidate $a $q))))(ba-commit-group $c $a $x $q)))
(: append-grouped-aggregate-current-pid! (-[semidet]-> Number Number (List $none)))
(: BaggPidSplit Type)
(: ba-pid-split (-[det]-> (List Number)(List Number) BaggPidSplit))
(: ba-split-step (-[semidet]-> ProofOutputKey BaggPidSplit Number BaggPidSplit))
(= (ba-split-step $a (ba-pid-split $b $c) $d)(if (=alpha (aggregate-snapshot-key-by-id $d) $a)(ba-pid-split (cons $d $b) $c)(ba-pid-split $b (cons $d $c))))
(= (append-grouped-aggregate-current-pid! $a $b)(let* (($c (aggregate-by-id $a))((stored-aggregate-row $d $e $f $g $h $i) $c)($j (aggregate-snapshot-key-by-id $b))((ba-pid-split $k $l)(proof-fold-flat-semidet (ba-split-step $j)(ba-pid-split ()()) $i))($m (reverse-number-list $k))($n (reverse-number-list $l))($o (cons $b $n))($p (set-aggregate-current-pid! $c $o)))(deactivate-current-proofs! $m)))
(: ba-commit-group (-[semidet]-> (Heap AgendaEntry) Number Bool ProofCandidate (Heap AgendaEntry)))
(= (ba-commit-group $a $b $c (proof-candidate $d $e $f $g))(if (== $c false) $a (if (candidate-is-cyclic? $b $d $g) $a (let* (($h (once (store-proof-candidate $b (proof-candidate $d $e $f $g))))($i (append-grouped-aggregate-current-pid! $b $h)))(wake-proof-commit-heap $a $b $h)))))
(: ba-commit-ev (-[det]-> $a (List Evidence)(List Evidence)))
(= (ba-commit-ev $a $b)(if (base-rate-finish? $a)()(if (== $a uniform-prior)()(if (== $a uniform-prior-known)() $b))))
(: ba-materialized-step (-[det]-> Bool Number Bool))
(= (ba-materialized-step $a $b)(if $a true (materialized-aggregate-proof? $b)))
(: materialized-lineage-present? (-[det]-> Bool))
(= (materialized-lineage-present?)(space-row-present? &materialized_aggregate_lineage (materialized-aggregate-lineage-row $h $t $k $f $e $d)))
;; The empty-lineage probe must stay in front: without it every harvest and
;; unchanged-snapshot commit folds goal-proof-ids against an empty space.
(: ba-materialized? (-[semidet]-> Number Bool))
(= (ba-materialized? $a)(if (materialized-lineage-present?)(proof-fold-flat-semidet ba-materialized-step false (goal-proof-ids $a)) false))
(: run-aggregate-heap (-[nondet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (run-aggregate-heap $a $b)
   (let* (($c (aggregate-by-id $b))
          ((stored-aggregate-row $d $e $f $g $h $i) $c)
          ($j (ba-grouped? $f))
          ($k (set-aggregate-pending! $c 0.0)))
      (if $j
         (let $l
            (the
               (KB Statement $m
                  (| ExtractValue ExtractInheritanceTV ExtractTV) $n
                  (-[semidet]-> $o $p $o) AggregateFinish AggregateTVMode)
               (copy_term $f))
            (proof-fold-flat-semidet
               (ba-commit-state $b $l) $a
               (ba-group-states $b $e $l)))
         (let* (((aggregate-state $q $r $s)
                    (ba-scalar-state $b $e
                       (the
                          (KB Statement
                             (| ExtractValue ExtractInheritanceTV ExtractTV)
                             $n (-[semidet]-> $o $p $o)
                             AggregateFinish AggregateTVMode)
                          (copy_term $f))))
                (($t $u $v $w $x $y $z) $f)
                ($v26 (CPU FoldAllCompiled $f (finish-aggregate $y $q)))
                ($v27 (ba-commit-ev $y $r)))
            (if (ba-degrades? $b $y $i $v26) $a
               (if (if (aggregate-snapshot-changed? $i $v26 $v27) true
                      (case $i (
                         (() false)
                         ((cons $v28 $_v29)
                            (and
                               (== (proof-children-by-id $v28) ())
                               (and
                                  (not (== $s ()))
                                  (ba-materialized? $b)))))))
                  (commit-aggregate-snapshot-heap
                     $a $b $v26 $v27 $s)
                  $a))))))
(: ba-degrades? (-[semidet]-> Number $a (List Number) $b Bool))
(= (ba-degrades? $a $b $c $d)(if (space-row-present? &aggregate_forward_approx ($a)) false (if (base-rate-finish? $b)(if (== $c ()) false (let* (((cons $e $f) $c)($g (let (CPU $h $i $j) $d $j))($k (let (CPU $l $m $n)(proof-output-atom-by-id $e) $n)))(if (= $k (STV $o $p))(if (= $g (STV $q $r))(< (tv-confidence $g)(tv-confidence $k)) true) false))) false)))
(: direct-goal-results-view (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))(| Goal (Statement KBContext Proof TV))))
(= (direct-goal-results-view $a (CPU $b $c $d))(let $e (reduce (cpu-call $a $b $c))(if (= $d $e)(CPU $b $c $e)(empty))))
(= (direct-goal-results-view $a ($b $c $d $e))(let $f (not (materialized-lineage-present?))(match &kb (@ $h ($b $c $d $e))(if (chainer-acyclic-term? $h)(if $f $h (if (materialized-forward-fact-stale? $h)(empty) $h))(empty)))))
(: ba-direct-step (-[semidet]-> Number (Heap AgendaEntry)(| Goal (Statement KBContext Proof TV))(Heap AgendaEntry)))
(= (ba-direct-step $a $c $d)(let* (($e (leaf-evidence-for-result $d))($f (leaf-result-candidate $d $e))($g (classify-goal-proof-candidate $a $f)))(commit-proof-candidate-heap $c $a $g $f)))
(: expand-direct-goal-heap (-[semidet]-> (Heap AgendaEntry) Number Number (| Goal (Statement KBContext Proof TV))(Heap AgendaEntry)))
(= (expand-direct-goal-heap $a $b $c $d)(expand-rule-goal-heap (proof-fold-flat-semidet (ba-direct-step $c) $a (collapse (direct-goal-results-view $b $d))) $c $d))
(: inject-compiled-query-adds (-[semidet]-> CompiledQuery (List $a)))
(= (inject-compiled-query-adds (compiled-query $a $b))(if (is-var $b)(empty)(once (inject-compiled-adds $b))))
