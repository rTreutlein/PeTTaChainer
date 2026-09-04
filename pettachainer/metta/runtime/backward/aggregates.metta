;; Backward fold goals: spawn, refresh, and commit (docs/metta/fold_node_contract.md).
;; A fold goal folds the representatives of its source goal; snapshots go through
;; the shared proof store with the replace policy, so this module owns only the
;; source link, the scheduling of refreshes, and the fold-specific policies
;; (cache seeding, evidence transparency, base-rate degrade guard).
;; Cycles are rejected before a snapshot is stored; commits with unchanged
;; results only wake the existing representative.
(: ba-child (-[nondet]-> Goal (| Goal (Statement KBContext Proof TV))))
(= (ba-child (CPU $a $b $c))(let* (($d (car-atom $b))($e (car-atom (cdr-atom $b)))((compiled-query $f $g)(the CompiledQuery (eval (mm2compileQuery $d (: $h $e $i))))))(if (or (is-var $f)(is-var $g))(empty)(let $_ (once (inject-compiled-adds $g))(typed-runtime-premise $f)))))
(: ba-step-acc (-[semidet]-> $x (-[semidet]-> $a Atom $a) $a $b (| TV NoTV) $a))
(= (ba-step-acc $a $b $c $d $e)(case $a ( ((extract-value $f $g)(let ($f ($h $i $j) $k $l)(copy_term $d)($b $c $g)))((extract-inheritance-tv $m $n)(let ((Inheritance $o $p)($h $i $j) $k $l)(copy_term $d)($b $c (WeightedTv (inheritance-subject-prior-tv $m (brand Statement $o)) $e))))(extract-tv ($b $c $e)))))
;; The empty-lineage probe must stay in front: without it every harvest and
;; unchanged-snapshot commit folds goal-proof-ids against an empty space.
(: ba-materialized-step (-[det]-> Bool Number Bool))
(= (ba-materialized-step $a $b)(if $a true (materialized-aggregate-proof? $b)))
(: materialized-lineage-present? (-[det]-> Bool))
(= (materialized-lineage-present?)(not (== (collapse (once (match &materialized_aggregate_lineage (materialized-aggregate-lineage-row $h $t $k $f $e $d) true)))())))
(: ba-materialized? (-[semidet]-> Number Bool))
(= (ba-materialized? $a)(if (materialized-lineage-present?)(proof-fold-flat-semidet ba-materialized-step false (goal-proof-ids $a)) false))
;; One commit path for scalar, grouped, cached and user snapshots. An unchanged
;; result (alpha-equal term, equal evidence) is a no-op: the current snapshot is
;; already visible to every waiter through the result index. The exception is a
;; childless cached snapshot that must be re-snapshotted with its sources so
;; materialized lineage can attach.
(: current-fold-snapshot (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))(List Number)))
(= (current-fold-snapshot $a $b)(collapse (once (current-proof-result-id-for-output-key (proof-goal-key-by-goal-id $a)(candidate-output-key $b)))))
(: store-fold-snapshot-heap (-[semidet]-> (Heap AgendaEntry) Number (| Goal (Statement KBContext Proof TV))(List Evidence)(List Number)(List Number)(Heap AgendaEntry)))
(= (store-fold-snapshot-heap $a $b $c $d $e $f)(if (candidate-is-cyclic? $b (aggregate $c) $e) $a (let* (($g (once (store-proof-candidate $b (aggregate-result-candidate $c $d $e))))($h (case $f ( (() ())((cons $old $_rest)(refine-dependent-demand! $old))))))(wake-proof-commit-heap $a $b $g))))
(: commit-fold-snapshot-heap (-[semidet]-> (Heap AgendaEntry) Number (| Goal (Statement KBContext Proof TV))(List Evidence)(List Number)(Heap AgendaEntry)))
(= (commit-fold-snapshot-heap $a $b $c $d $e)(case (current-fold-snapshot $b $c) ( (()(store-fold-snapshot-heap $a $b $c $d $e ()))((cons $f $g)(if (=alpha (proof-output-atom-by-id $f) $c)(let ($h $i)(proof-stats-by-id $f)(if (== $i $d)(if (== (proof-children-by-id $f)())(if (== $e ()) $a (if (ba-materialized? $b)(store-fold-snapshot-heap $a $b $c $d $e (cons $f ())) $a)) $a)(store-fold-snapshot-heap $a $b $c $d $e (cons $f ()))))(store-fold-snapshot-heap $a $b $c $d $e (cons $f ())))))))
(: ba-ensure-child (-[nondet]-> Number Goal $a Number Number Bool Number))
(= (ba-ensure-child $a $b $c $d $e $f)(let* (($g (ba-child $b))((stored-goal-row $h $i $j $k $l)(goal-by-id $a))($m (ensure-goal-at-depth $g (+ 1 $i)))($n (collapse (once (match &fold_source (fold-source-row $a $o $p $q $r $s) true))))($t (if (== $n ())(let* (($u (once (chainer-add-atom &fold_source (fold-source-row $a $m $c $d $e $f))))($v (case (base-rate-aggregate-key $c) ( ((base-rate-aggregate-key-value $w $x $y)(register-base-rate-fold! (base-rate-aggregate-key-value $w $x $y)(proof-goal-key-by-goal-id $a)))(no-base-rate-aggregate-key ())))))())()))) $m))
(: ba-refine (-[nondet]-> (Heap AgendaEntry) Number Number Number Goal $a TV BaseRateSource (Heap AgendaEntry)))
(= (ba-refine $a $b $u $c $d $e $f $g)(let* (($h (ba-ensure-child $c $d $e $b $u (== $g forward-approx)))($q (register-goal-waiter! $h $c (aggregate-waiter $c (cached-aggregate-demand $f))))($s (commit-fold-snapshot-heap $a $c (CPU FoldAllCompiled $e $f) ()())))(wake-goal-demand-heap $s $h)))
(: spawn-aggregate-goal-heap (-[nondet]-> (Heap AgendaEntry) Number Number Number Goal (Heap AgendaEntry)))
(= (spawn-aggregate-goal-heap $a $b $c $d $e)(let* (($f (copy_term (let (CPU $g $h $i) $e $h)))($k (base-rate-aggregate-key $f)))(case $k ( ((base-rate-aggregate-key-value $m $n $o)(case (base-rate-cache-entries-for-mode $m $n $o) ( (()(if (case $f ( (($p (MemberInheritanceSample $q $r $s $t $u) $v $w $x (member-inheritance $p) $y)(forward-member-inheritance-empty-cache-hit? (brand KB $p)(brand Term $r)(brand Term $s) $b))($z false))) $a (ba-spawn-live $a $c $b $d $e $f)))((cons $s2 $t2)(let* (($u2 (base-rate-entry-tv $s2))($v2 (base-rate-entry-source $s2)))(if (== $v2 user)(commit-fold-snapshot-heap $a $d (CPU FoldAllCompiled $f $u2)()())(ba-refine $a $c $b $d $e $f $u2 $v2)))))))(no-base-rate-aggregate-key (ba-spawn-live $a $c $b $d $e $f))))))
(: ba-spawn-live (-[nondet]-> (Heap AgendaEntry) Number Number Number Goal $a (Heap AgendaEntry)))
(= (ba-spawn-live $a $b $u $c $d $e)(let* (($f (ba-ensure-child $c $d $e $b $u false))($g (register-goal-waiter! $f $c (aggregate-waiter $c live-aggregate-demand))))(schedule-aggregate-heap (wake-goal-demand-heap $a $f) $c)))
(: ba-source-step (-[semidet]-> (List Number) Number (List Number)))
(= (ba-source-step $a $b)(case (proof-kind-by-id $b)( ((leaf ($c $d $e $f))(if (materialized-aggregate-forward-fact? (assemble-stored-runtime-fact $c $d $e $f)) $a (cons $b $a)))($g (cons $b $a)))))
(: ba-source-pids (-[semidet]-> Number Number (List Number)))
(= (ba-source-pids $a $b)(let $c (reverse-number-list (proof-fold-flat-semidet ba-source-step ()(noncyclic-proof-source-ids $a closed-goal $b)))(proof-output-group-representative-pids $b (proof-output-groups $c))))
(: ba-child-tv (-[det]-> (| Goal (Statement KBContext Proof TV))(| TV NoTV)))
(= (ba-child-tv $a)(case $a ( ((CPU $b $c $d) no-tv)(($e $f $g $h) $h))))
(: ba-group-add (-[semidet]-> $x (-[semidet]-> $a $b $a) $a $c $d (| TV NoTV)(List Evidence) Number (List AggregateGroupState)(List AggregateGroupState)))
(= (ba-group-add $a $b $c $d $e $f $g $h ())(let* (($i (ba-step-acc $a $b $c $e $f))($j (list_to_set $g)))(cons (aggregate-group-state $d $i $j ($h))())))
(= (ba-group-add $a $b $c $d $e $f $g $h (cons (aggregate-group-state $i $j $k $l) $m))(if (== $d $i)(let* (($n (ba-step-acc $a $b $j $e $f))($o (list_to_set (append-flat $k $g)))($p (append-flat $l ($h))))(cons (aggregate-group-state $i $n $o $p) $m))(cons (aggregate-group-state $i $j $k $l)(ba-group-add $a $b $c $d $e $f $g $h $m))))
;; One accumulation state per group; a scalar fold is the single group `scalar`
;; seeded with the accumulator's initial value so an empty source still commits.
;; Each step copies the pattern, group variable and extractor so unification
;; with one child output does not bind them for the next.
(: ScalarFoldSpec (Alias (KB Statement (| ExtractValue ExtractInheritanceTV ExtractTV) $a (-[semidet]-> $b $c $b) AggregateFinish AggregateTVMode)))
(: GroupedFoldSpec (Alias (KB Statement $a (| ExtractValue ExtractInheritanceTV ExtractTV) $b (-[semidet]-> $c $d $c) AggregateFinish AggregateTVMode)))
(: fold-step-scalar (-[semidet]-> ScalarFoldSpec (List AggregateGroupState) Number (List AggregateGroupState)))
(= (fold-step-scalar $a $b $c)(let* ((($d $e $g $h $i $j $k) $a)(($l $m (proof-support $n $o $p) $q)(proof-row-by-id $c))($g2 (copy_term $g)))(ba-group-add $g2 $i $h scalar $l (ba-child-tv $l) $o $c $b)))
(: fold-step-grouped (-[semidet]-> GroupedFoldSpec (List AggregateGroupState) Number (List AggregateGroupState)))
(= (fold-step-grouped $a $b $c)(let* ((($d $e $f $g $h $i $j $k) $a)(($l $m (proof-support $n $o $p) $q)(proof-row-by-id $c))(($e2 $f2 $g2)(copy_term (quote ($e $f $g))))($r (let ($e2 ($s $t $u) $v $w)(copy_term $l) $f2)))(ba-group-add $g2 $i $h $r $l (ba-child-tv $l) $o $c $b)))
(: fold-commit-state (-[semidet]-> Number $spec Bool (Heap AgendaEntry) AggregateGroupState (Heap AgendaEntry)))
(= (fold-commit-state $a $b $c $d (aggregate-group-state $e $f $g $h))(let* (($i (case $b ( (($k $l $m $n $o $p $q $r) $q)(($k $l $n $o $p $q $r) $q))))($j (case $b ( (($k $l $m $n $o $p $q $r)(CPU GroupedFoldAllCompiled (quote ($k $l $e $n $o $p $q $r))(finish-aggregate $q $f)))(($k $l $n $o $p $q $r)(CPU FoldAllCompiled $b (finish-aggregate $q $f)))))))(if (ba-degrades? $c $i $a $j) $d (commit-fold-snapshot-heap $d $a $j (ba-commit-ev $i $g) $h))))
(: ba-commit-ev (-[det]-> $a (List Evidence)(List Evidence)))
(= (ba-commit-ev $a $b)(if (base-rate-finish? $a)()(if (== $a uniform-prior)()(if (== $a uniform-prior-known)() $b))))
(: refresh-fold-heap (-[nondet]-> (Heap AgendaEntry) Number (Heap AgendaEntry)))
(= (refresh-fold-heap $a $b)(let* (((fold-source-row $d $e $f $g $h $i)(fold-source-by-id $b))($p (ba-source-pids $b $e))($j (case $f ( (($k $l $m $n $o $q $r $s)(proof-fold-flat-semidet (fold-step-grouped (the GroupedFoldSpec (copy_term $f)))() $p))(($k $l $n $o $q $r $s)(proof-fold-flat-semidet (fold-step-scalar (the ScalarFoldSpec (copy_term $f)))(cons (aggregate-group-state scalar $o ()()) ()) $p))))))(proof-fold-flat-semidet (fold-commit-state $b $f $i) $a $j)))
;; A complete base-rate refold may not lower the confidence of the current
;; snapshot; a forward-approx seed is partial work and is always replaced.
(: ba-degrades? (-[semidet]-> Bool $a Number $b Bool))
(= (ba-degrades? $a $b $c $d)(if $a false (if (base-rate-finish? $b)(case (current-fold-snapshot $c $d) ( (() false)((cons $e $f)(let* (($g (let (CPU $h $i $j) $d $j))($k (let (CPU $l $m $n)(proof-output-atom-by-id $e) $n)))(if (= $k (STV $o $p))(if (= $g (STV $q $r))(< (tv-confidence $g)(tv-confidence $k)) true) false))))) false)))
(: direct-goal-results-view (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))(| Goal (Statement KBContext Proof TV))))
(= (direct-goal-results-view $a (CPU $b $c $d))(let $e (reduce (cpu-call $a $b $c))(if (= $d $e)(CPU $b $c $e)(empty))))
(= (direct-goal-results-view $a ($b $c $d $e))(let $f (== (collapse (once (match &materialized_aggregate_lineage $g true)))())(match &kb (@ $h ($b $c $d $e))(if (chainer-acyclic-term? $h)(if $f $h (if (materialized-forward-fact-stale? $h)(empty) $h))(empty)))))
(: ba-direct-step (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))(Heap AgendaEntry)(| Goal (Statement KBContext Proof TV))(Heap AgendaEntry)))
(= (ba-direct-step $a $b $c $d)(let* (($e (leaf-evidence-for-result $d))($f (leaf-result-candidate $d $e))($g (classify-goal-proof-candidate $a $f))($h (commit-proof-candidate-heap $c $a $g $f))) $h))
(: expand-direct-goal-heap (-[semidet]-> (Heap AgendaEntry) Number Number (| Goal (Statement KBContext Proof TV))(Heap AgendaEntry)))
(= (expand-direct-goal-heap $a $b $c $d)(let* (($e (collapse (direct-goal-results-view $b $d)))($f (proof-fold-flat-semidet (ba-direct-step $c $d) $a $e)))(expand-rule-goal-heap $f $c $d)))
(: inject-compiled-query-adds (-[semidet]-> CompiledQuery (List $a)))
(= (inject-compiled-query-adds (compiled-query $a $b))(if (is-var $b)(empty)(once (inject-compiled-adds $b))))
