(: QueueGoal Type)
(: qgoal (-> Number Number QueueGoal))
(: QueueAggregate Type)
(: qagg (-> Number Number QueueAggregate))
;; SWI heap primitives imported by PeTTa.
(: reverse-number-list
   (-[det]-> (List Number) (List Number)))
(: reverse-number-list-into
   (-[det]-> (List Number) (List Number) (List Number)))
(= (reverse-number-list $items)
   (reverse-number-list-into $items ()))
(= (reverse-number-list-into () $acc) $acc)
(= (reverse-number-list-into (cons $item $rest) $acc)
   (reverse-number-list-into $rest (cons $item $acc)))
(: backward-runtime-fact
   (-[det]-> Atom Atom Atom Atom
       (Statement KBContext Proof TV)))
(= (backward-runtime-fact $statement $kb $proof $tv)
   (quote ($statement $kb $proof $tv)))
(: backward-acyclic-term? (-[det]-> Atom Bool))
(= (backward-acyclic-term? $term)
   (== (collapse
          (callPredicate (Predicate (cyclic_term $term))))
       ()))
(: SearchState Type)
(: search-state (-> Number $heap SearchState))
(: ChainerRunResult Type)
(: chainer-run-result
   (-> Number
       (List RuntimeResult)
       ChainerRunResult))
(: AndBundle Type)
(: and-bundle
   (-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       AndBundle))
(= (get-type (and-bundle $goal $premises)) AndBundle)

(: ensure-goal-at-depth
   (-[semidet]-> (| Goal
          (Statement KBContext Proof TV))
       Number Number))
(= (ensure-goal-at-depth $goal $depth)
   (let*
      (($stored-goal (copy_term $goal))
       ($goal-key (goal-key $stored-goal))
       ($lookup-key (copy_term $goal-key))
       ($hits
          (collapse
             (once
                (match &goal_lookup ($lookup-key $stored-key $gid)
                   (if (=alpha $stored-key $goal-key)
                      (stored-number $gid)
                      (empty)))))))
      (if (== $hits ())
         (let*
            (($gid (next-gid))
             ($index-key (copy_term $goal-key))
             ($_1
                (once
                   (chainer-add-atom &goal
                      (stored-goal-row
                         $gid $depth $stored-goal false 0.0))))
             ($_2
                (once
                   (chainer-add-atom &goal_lookup
                      ($index-key $goal-key $gid)))))
            $gid)
         (first-number $hits))))

(: schedule-goal-heap
   (-[semidet]-> $heap Number Number $heap))
(= (schedule-goal-heap $agenda $score $gid)
   (schedule-goal-row
      $agenda $score $gid (goal-by-id $gid)))

(: schedule-goal-row
   (-[semidet]-> $heap Number Number StoredGoalRow $heap))
(= (schedule-goal-row
      $agenda $score $gid
      (stored-goal-row
         $_stored-gid $depth $goal $expanded $current))
   (if (== $expanded true) $agenda
      (if (>= $current $score) $agenda
         (let*
            (($closed-proof-bonus
                (if (goal-has-type-vars? $goal) 0.0 1.0))
             ($bonus
                (case $goal (
                   (($_type ($_kbid $_ctx $_vars) $_prf $_tv)
                      $closed-proof-bonus)
                   ($_other 2.0))))
             ($priority
                (+ (* 1000000000.0 $depth)
                   (- 0 (+ (* 1000000.0 $score) $bonus))))
             ($nagenda
                (add_to_heap
                   $agenda $priority (qgoal $score $gid)))
             ($_set
                (progn
                   (remove-atom &goal
                      (stored-goal-row
                         $gid $depth $goal $expanded $current))
                   (once
                      (chainer-add-atom &goal
                         (stored-goal-row
                            $gid $depth $goal $expanded $score))))))
            $nagenda))))

(: schedule-aggregate-heap
   (-[semidet]-> $heap Number $heap))
(= (schedule-aggregate-heap $agenda $agg-gid)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $current $current-pid)
          (aggregate-by-id $agg-gid))
       ((stored-goal-row
           $_stored-gid $depth $_goal $_expanded $_goal-pending)
          (goal-by-id $agg-gid)))
      (if (>= $current $base-score) $agenda
         (let*
            (($priority (+ (+ (* 1000000000.0 (+ 1 $depth)) (- 0 (* 1000000.0 $base-score))) 0.1))
             ($nagenda (add_to_heap $agenda $priority (qagg $base-score $agg-gid)))
             ($_set
                (progn
                   (remove-atom &aggregate
                      (stored-aggregate-row
                         $agg-gid $child-gid $args $base-score
                         $current $current-pid))
                   (once
                      (chainer-add-atom &aggregate
                         (stored-aggregate-row
                            $agg-gid $child-gid $args $base-score
                            $base-score $current-pid))))))
            $nagenda))))

;; FoldAllCompiled and GroupedFoldAllCompiled both carry the kb and pattern as
;; the first two args; the child goal is the compiled query for that pattern.
(: activate-compiled-query
   (-[nondet]-> CompiledQuery
       (| Goal (Statement KBContext Proof TV))))
(= (activate-compiled-query
      (compiled-query $child-goal $adds))
   (if (or (is-var $child-goal) (is-var $adds))
      (empty)
      (let $_
         (once
            (inject-compiled-adds $adds))
         $child-goal)))

(: aggregate-child-goal
   (-[nondet]-> Goal
       (| Goal (Statement KBContext Proof TV))))
(= (aggregate-child-goal (CPU $_fun $args $_goalres))
   (let*
      (($kb (car-atom $args))
       ($pattern (car-atom (cdr-atom $args)))
       ($raw-compiled-query
          (eval
             (mm2compileQuery
                $kb
                (: $prf $pattern $tvin))))
       ($compiled-query
          (the CompiledQuery $raw-compiled-query)))
      (activate-compiled-query $compiled-query)))

(: aggregate-step-value
   (-> ExtractValue
       $child-atom (| TV NoTV) $value))
(: aggregate-step-value
   (-> ExtractInheritanceTV
       $child-atom TV WeightedTV))
(: aggregate-step-value
   (-> ExtractTV $child-atom TV TV))
(= (aggregate-step-value (extract-value $pattern $value) $child-atom $_child-tv)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $value))
(= (aggregate-step-value (extract-inheritance-tv $kbid $_pattern) $child-atom $child-tv)
   (let ((Inheritance $subj $_concept) ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom)
      (WeightedTv
         (inheritance-subject-prior-tv
            (brand KB $kbid)
            (brand Statement $subj))
         $child-tv)))
(= (aggregate-step-value extract-tv $_child-atom $child-tv) $child-tv)
(: aggregate-step-group-value
   (-> Statement $group-template $child-atom $group))
(= (aggregate-step-group-value $pattern $group $child-atom)
   (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv) (copy_term $child-atom) $group))

(: aggregate-foldall-step-acc
   (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)
       (-[semidet]-> $accumulator Atom $accumulator)
       $accumulator $child-atom (| TV NoTV) $accumulator))
(= (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv)
   (case $extractor (
      ((extract-value $pattern $value-template)
         (let ($pattern ($_ckbid $_cctx $_cvars) $_cprf $_ctv)
            (copy_term $child-atom)
            ($fun $acc $value-template)))
      ((extract-inheritance-tv $kbid $_pattern)
         (let ((Inheritance $subj $_concept)
                ($_ckbid $_cctx $_cvars) $_cprf $_ctv)
            (copy_term $child-atom)
            ($fun $acc
               (WeightedTv
                  (inheritance-subject-prior-tv
                     (brand KB $kbid)
                     (brand Statement $subj))
                  (the TV $child-tv)))))
      (extract-tv
         ($fun $acc (the TV $child-tv))))))

(: aggregate-finish (-> IdentityFinish $acc $acc))
(: aggregate-finish
   (-> DistAverageFinish DistributionSumCount Distribution))
(: aggregate-finish (-> BaseRateFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-> WeightedBaseRateFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-[semidet]-> WeightedBaseRateWithPriorFinish
       BaseRateEvidenceWithPriorState TV))
(: aggregate-finish
   (-> MemberInheritanceFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-> WeightedBaseRateInUniverseFinish BaseRateEvidenceState TV))
(: aggregate-finish
   (-> WeightedBaseRateWithPriorInUniverseFinish BaseRateEvidenceWithPriorState TV))
(: aggregate-finish
   (-> UniformPriorFinish (List $subject) TV))
(: aggregate-finish
   (-> UniformPriorKnownFinish (List $subject) TV))
(= (aggregate-finish identity $acc) $acc)
(= (aggregate-finish dist-average $acc)
   (the Distribution
      (once
         (reduce (reduce (DistAverageFromSumCount $acc))))))
(= (aggregate-finish base-rate $acc)
   (BaseRateTv (the BaseRateEvidenceState $acc)))
(= (aggregate-finish weighted-base-rate $acc) (WeightedBaseRateTv $acc))
(= (aggregate-finish weighted-base-rate-with-prior $acc)
   (WeightedBaseRateWithPriorTv $acc))
(= (aggregate-finish (member-inheritance $kbid) $acc)
   (member-inheritance-tv $kbid $acc))
(= (aggregate-finish (weighted-base-rate-in-universe $kbid) $acc)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedBaseRateTv $acc)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $acc))))
(= (aggregate-finish
      (weighted-base-rate-with-prior-in-universe $kbid)
      (BaseRateEvidenceWithPrior $prior $ev))
   (let $universe-size (kb-universe-size $kbid)
      (BaseRateWithPriorFormula
         (resolve-base-rate-prior $prior)
         (if (== $universe-size no-universe-size)
            (WeightedBaseRateTv $ev)
            (WeightedUniverseBaseRateTv
               (the Number $universe-size) $ev)))))
(= (aggregate-finish uniform-prior $acc) (UniformPriorTv $acc))
(= (aggregate-finish uniform-prior-known $acc) (UniformPriorKnownTv $acc))

;; Compiled aggregate arguments are a dynamic wire format.  Dispatching on the
;; finish token is the point where its corresponding accumulator type is known.
(: distribution-sum-count-acc
   (-> $value DistributionSumCount))
(= (distribution-sum-count-acc $acc)
   (the DistributionSumCount $acc))
(: base-rate-evidence-acc
   (-> $value BaseRateEvidenceState))
(= (base-rate-evidence-acc $acc)
   (the BaseRateEvidenceState $acc))
(: base-rate-evidence-with-prior-acc
   (-> $value BaseRateEvidenceWithPriorState))
(= (base-rate-evidence-with-prior-acc $acc)
   (the BaseRateEvidenceWithPriorState $acc))
(: list-aggregate-acc
   (-> $value (List Atom)))
(= (list-aggregate-acc $acc)
   (the (List Atom) $acc))
(: available-universe-size
   (-> (| Number UniverseSizeUnavailable) Number))
(= (available-universe-size $size)
   (the Number $size))

;; Aggregate CPU arguments are stored as an open, user-extensible wire format:
;; the finish token determines both the accumulator and result types.  Keep the
;; dispatcher itself dynamic and validate only at the selected typed boundary;
;; `aggregate-finish` above remains the fully typed API for direct callers.
(: finish-aggregate
   (-[semidet]-> Atom Atom Atom))

(= (finish-aggregate $finish $acc)
   (case $finish (
      (identity $acc)
      (dist-average
         (the Distribution
            (once
               (reduce
                  (reduce
                     (DistAverageFromSumCount
                        (distribution-sum-count-acc $acc)))))))
      (base-rate
         (BaseRateTv (base-rate-evidence-acc $acc)))
      (weighted-base-rate
         (WeightedBaseRateTv (base-rate-evidence-acc $acc)))
      (weighted-base-rate-with-prior
         (WeightedBaseRateWithPriorTv
            (base-rate-evidence-with-prior-acc $acc)))
      ((member-inheritance $kbid)
         (member-inheritance-tv (brand KB $kbid)
            (base-rate-evidence-acc $acc)))
      ((weighted-base-rate-in-universe $kbid)
         (let $ev (base-rate-evidence-acc $acc)
            (let $universe-size
               (kb-universe-size (brand KB $kbid))
               (if (== $universe-size no-universe-size)
                  (WeightedBaseRateTv $ev)
                  (WeightedUniverseBaseRateTv
                     (available-universe-size $universe-size) $ev)))))
      ((weighted-base-rate-with-prior-in-universe $kbid)
         (let (BaseRateEvidenceWithPrior $prior $ev)
            (base-rate-evidence-with-prior-acc $acc)
            (let $universe-size
               (kb-universe-size (brand KB $kbid))
               (BaseRateWithPriorFormula
                  (resolve-base-rate-prior $prior)
                  (if (== $universe-size no-universe-size)
                     (WeightedBaseRateTv $ev)
                     (WeightedUniverseBaseRateTv
                        (available-universe-size $universe-size) $ev))))))
      (uniform-prior
         (UniformPriorTv (list-aggregate-acc $acc)))
      (uniform-prior-known
         (UniformPriorKnownTv (list-aggregate-acc $acc))))))

;; Stored aggregate arguments cross an untyped space boundary. Reconstruct the
;; declared finish variant by its constructor instead of rechecking the whole
;; nested value at runtime (which would also try to recover erased KB brands).
(: finish-stored-aggregate
   (-[semidet]-> Atom Atom Atom))
(= (finish-stored-aggregate $finish $acc)
   (case $finish (
      (identity (finish-aggregate identity $acc))
      (dist-average
         (finish-aggregate dist-average
            (distribution-sum-count-acc $acc)))
      (base-rate
         (finish-aggregate base-rate
            (base-rate-evidence-acc $acc)))
      (weighted-base-rate
         (finish-aggregate weighted-base-rate
            (base-rate-evidence-acc $acc)))
      (weighted-base-rate-with-prior
         (finish-aggregate weighted-base-rate-with-prior
            (base-rate-evidence-with-prior-acc $acc)))
      ((member-inheritance $kbid)
         (finish-aggregate
            (member-inheritance (brand KB $kbid))
            (base-rate-evidence-acc $acc)))
      ((weighted-base-rate-in-universe $kbid)
         (finish-aggregate
            (weighted-base-rate-in-universe (brand KB $kbid))
            (base-rate-evidence-acc $acc)))
      ((weighted-base-rate-with-prior-in-universe $kbid)
         (finish-aggregate
            (weighted-base-rate-with-prior-in-universe
               (brand KB $kbid))
            (base-rate-evidence-with-prior-acc $acc)))
      (uniform-prior
         (finish-aggregate uniform-prior
            (list-aggregate-acc $acc)))
      (uniform-prior-known
         (finish-aggregate uniform-prior-known
            (list-aggregate-acc $acc))))))
;; --- Frontier pooling of same-source projections -----------------------------
;; A conjunction frontier rejects a premise proof whose fact evidence overlaps
;; evidence already consumed (AndFormula would double count it). When the
;; overlapping proofs are marginal projections of the *same* stored or derived
;; (And ...) source, the sharing is exactly accountable: the group of premises
;; is one joint projection of that source. Such premises are pooled into a
;; single part whose TV is the marginal projection while the pool is partial
;; and the source's own TV once every conjunct of the source is in the pool.
;; Parts are folded with AndFormula across parts only, so frontiers whose parts
;; are all independent reproduce the unpooled TVs exactly; pooling only adds
;; results that were previously dropped. Overlap that is not fully explained by
;; a same-source pool keeps today's rejection.

(: expr-arity (-> $expression Number))
(= (expr-arity $e) (if (== $e ()) 0 (+ 1 (expr-arity (cdr-atom $e)))))

;; Parts, one per consumed premise, in premise order:
;;   (indep-part $tv)                                -- ordinary premise
;;   (pool-part $base $base-tv $arity $idxs $ev $marginal-tv)
;;                                                   -- projections of one source
;;   skip-part                                       -- AndFormula chain steps
;;   unpoolable-part                                 -- unclassifiable premise;
;;                                                      poisons folds so joins
;;                                                      fall back to rejection
(: FrontierPart Type)
(: indep-part (-> TV FrontierPart))
(: pool-part
   (-> ProofOutputKey TV Number (List Number)
       (List Evidence) TV FrontierPart))
(: SkipPart Type)
(: skip-part SkipPart)
(: UnpoolablePart Type)
(: unpoolable-part UnpoolablePart)
(: NoPool Type)
(: no-pool NoPool)
(: SourceInfo Type)
(: source-info (-> TV Number SourceInfo))
(: NoSourceInfo Type)
(: no-source-info NoSourceInfo)
(: SourceEntry Type)
(: source-entry (-> ProofOutputKey SourceInfo SourceEntry))
(: NoSourceEntry Type)
(: no-source-entry NoSourceEntry)
(: FrontierProjection Type)
(: projection
   (-> Number (| Proof ProofRef) FrontierProjection))
;; Keep the absence sentinel distinct from the public logic-config
;; `NoProjection` output mode.
(: NoFrontierProjection Type)
(: no-projection NoFrontierProjection)
(: NoTerm Type)
(: no-term NoTerm)
(: NoPoolKey Type)
(: no-pool-key NoPoolKey)
(: FrontierWaiter Type)
(: frontier-waiter
   (-> Number AndBundle Number (List Evidence) (List (| FrontierPart UnpoolablePart)) (List Number) FrontierWaiter))
(: AggregateWaiter Type)
(: aggregate-waiter (-> Number AggregateWaiter))
(: AggregateState Type)
(: aggregate-state
   (-> $accumulator (List Evidence) (List Number) AggregateState))
(: AggregateGroupState Type)
(: aggregate-group-state
   (-> $group $accumulator (List Evidence) (List Number) AggregateGroupState))

(: frontier-part-tv (-> FrontierPart TV))
(= (frontier-part-tv $part)
   (case $part (
      ((indep-part $tv) $tv)
      ((pool-part $_base $btv $n $idxs $_ev $mtv)
         (if (== (expr-arity $idxs) $n) $btv $mtv)))))

(: frontier-parts-fold-acc
   (-[semidet]-> TV (List FrontierPart) TV))
(= (frontier-parts-fold-acc $acc ()) $acc)
(= (frontier-parts-fold-acc $acc (cons $part $rest))
   (frontier-parts-fold-acc (AndFormula $acc (frontier-part-tv $part)) $rest))

(: frontier-parts-fold
   (-[semidet]-> (List FrontierPart) TV))
(= (frontier-parts-fold (cons $first $rest))
   (frontier-parts-fold-acc (frontier-part-tv $first) $rest))

(: frontier-parts-checked
   (-[nondet]-> (List (| FrontierPart UnpoolablePart))
       (List FrontierPart)))
(= (frontier-parts-checked ()) ())
(= (frontier-parts-checked (cons $part $rest))
   (case $part
      (((indep-part $tv)
          (cons (indep-part $tv) (frontier-parts-checked $rest)))
       ((pool-part $base $btv $n $idxs $ev $mtv)
          (cons
             (pool-part $base $btv $n $idxs $ev $mtv)
             (frontier-parts-checked $rest)))
       (unpoolable-part (empty)))))

;; TV and conjunct count of a projection's source conjunction. Stored proof
;; outputs carry (proof-ref $pid) handles instead of proof terms, so the real
;; projection term lives in the proof node's kind; its base is a (proof-ref
;; $bpid) for chained sources (facts and derived conjunctions alike) or a
;; statement name for kb-materialized projection facts.
(: frontier-and-source-info
   (-> (| Goal (Statement KBContext Proof TV))
       (| SourceInfo NoSourceInfo)))
(= (frontier-and-source-info ($type $_kb $_prf $tv))
   (if (is-expr $type)
      (if (== (car-atom $type) And)
         (source-info $tv (expr-arity (cdr-atom $type)))
         no-source-info)
      no-source-info))

;; Pools are keyed by the source's output key (type + kb), not by its proof
;; node: different conjuncts can instantiate a projection rule's source premise
;; differently (open vs ground goals), producing distinct proof nodes for the
;; same source proposition.
(: frontier-source-entry-from-atom
   (-> (| Goal (Statement KBContext Proof TV))
       (| SourceEntry NoSourceEntry)))
(= (frontier-source-entry-from-atom $atom)
   (let $i (frontier-and-source-info $atom)
      (case $i (
         (no-source-info no-source-entry)
         ((source-info $tv $n)
            (source-entry (candidate-output-key $atom)
               (source-info $tv $n)))))))

(: frontier-source-entry
   (-[semidet]-> (| Proof ProofRef)
       (| SourceEntry NoSourceEntry)))
(= (frontier-source-entry $base)
   (if (= $base (proof-ref $bpid))
      (frontier-source-entry-from-atom
         (proof-output-atom-by-id (the Number $bpid)))
      (let $hits
         (collapse
            (match &kb ($type $kb $base $tv)
               (let $e
                  (frontier-source-entry-from-atom
                     (backward-runtime-fact
                        $type $kb $base $tv))
                  (if (== $e no-source-entry) (empty) $e))))
         (if (== $hits ()) no-source-entry (car-atom $hits)))))

(: frontier-proof-term (-> ProofKind (| $term NoTerm)))
(= (frontier-proof-term $kind)
   (case $kind (
      ((rule $term) $term)
      ((leaf $term) $term)
      ($_ no-term))))

(: frontier-proof-projection
   (-> ProofKind (| FrontierProjection NoFrontierProjection)))
(= (frontier-proof-projection $kind)
   (let $term (frontier-proof-term $kind)
      (case $term (
         (($_t $_kb $prf $_tv)
            (case $prf (
               ((marginal-proj $idx $base)
                  (projection $idx $base))
               ($_other no-projection))))
         ($_other no-projection)))))

(: frontier-atom-part
   (-[semidet]-> Number ($type $kb $proof TV)
       FrontierPart))
(= (frontier-atom-part $pid ($_type $_kb $_prf $tv))
   (let $atom-tv $tv
      (let $proj (frontier-proof-projection (proof-kind-by-id $pid))
         (case $proj (
            ((projection $idx $base)
               (let $entry (frontier-source-entry $base)
                  (if (= $entry (source-entry $key (source-info $btv $n)))
                     (let ($_score $ev) (proof-stats-by-id $pid)
                        (pool-part $key
                           $btv
                           $n
                           ($idx)
                           $ev
                           $atom-tv))
                     (indep-part $atom-tv))))
            (no-projection
               (indep-part $atom-tv)))))))

(: frontier-premise-part
   (-[semidet]-> Number (| FrontierPart SkipPart)))
(= (frontier-premise-part $pid)
   (once
      (let $out (proof-output-atom-by-id $pid)
         (if (= $out (CPU $f $args $res))
            (if (== $f AndFormula) skip-part
               (indep-part (cpu-premise-tv $f $args $res)))
            (case $out
               ((($type ($kbid $ctx $vars) $prf $tv)
                  (let $fact-kb
                     (make-kb-context
                        (brand KB $kbid) $ctx $vars)
                     (frontier-atom-part
                        $pid
                        (backward-runtime-fact
                           $type $fact-kb $prf $tv))))))))))

(: frontier-part-or-unpoolable
   (-[det]-> (List (| FrontierPart SkipPart))
       (| FrontierPart SkipPart UnpoolablePart)))
(= (frontier-part-or-unpoolable ()) unpoolable-part)
(= (frontier-part-or-unpoolable
      (cons $part $_rest))
   $part)

(: frontier-parts-idx-union
   (-[det]-> (List Number) (List Number) (List Number)))
(: frontier-append-index
   (-[det]-> (List Number) Number (List Number)))
(: frontier-index-member?
   (-[det]-> Number (List Number) Bool))
(= (frontier-index-member? $_index ()) false)
(= (frontier-index-member? $index (cons $head $rest))
   (if (== $index $head)
      true
      (frontier-index-member? $index $rest)))
(= (frontier-append-index () $index)
   (cons $index ()))
(= (frontier-append-index (cons $head $rest) $index)
   (cons $head (frontier-append-index $rest $index)))
(= (frontier-parts-idx-union $a ()) $a)
(= (frontier-parts-idx-union $a (cons $i $rest))
   (frontier-parts-idx-union
      (if (frontier-index-member? $i $a)
         $a
         (frontier-append-index $a $i))
      $rest))

(: frontier-pool-key
   (-> (| FrontierPart UnpoolablePart)
       (| ProofOutputKey NoPoolKey)))
(= (frontier-pool-key $part)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv) $key)
      ($_ no-pool-key))))

(: frontier-parts-same-pool
   (-> (List (| FrontierPart UnpoolablePart))
       ProofOutputKey (| FrontierPart NoPool)))
(= (frontier-parts-same-pool () $_key) no-pool)
(= (frontier-parts-same-pool (cons $head $rest) $key)
   (case $head (
      ((pool-part $head-key $btv $n $idxs $ev $mtv)
         (if (=alpha $head-key $key)
            (pool-part $head-key $btv $n $idxs $ev $mtv)
            (frontier-parts-same-pool $rest $key)))
      ($_other (frontier-parts-same-pool $rest $key)))))

(: frontier-parts-join-pool
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       FrontierPart
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-join-pool () $pool) (cons $pool ()))
(= (frontier-parts-join-pool (cons $head $rest) (pool-part $key $btv $n $idxs $ev $mtv))
   (if (=alpha (frontier-pool-key $head) $key)
      (let (pool-part $okey $obtv $on $oidxs $oev $omtv) $head
         (cons
            (pool-part $okey $obtv $on
               (frontier-parts-idx-union $oidxs $idxs)
               (list_to_set (append-evidence $oev $ev))
               $omtv)
            $rest))
      (cons $head (frontier-parts-join-pool $rest (pool-part $key $btv $n $idxs $ev $mtv)))))

(: frontier-parts-add
   (-[semidet]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart SkipPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(: frontier-parts-append-one
   (-[det]-> (List (| FrontierPart UnpoolablePart))
       (| FrontierPart UnpoolablePart)
       (List (| FrontierPart UnpoolablePart))))
(= (frontier-parts-append-one () $part)
   (cons $part ()))
(= (frontier-parts-append-one
      (cons $head $rest) $part)
   (cons $head
      (frontier-parts-append-one $rest $part)))
(= (frontier-parts-add $parts $part)
   (case $part (
      (skip-part $parts)
      ((pool-part $base $btv $n $idxs $ev $mtv)
         (frontier-parts-join-pool $parts (pool-part $base $btv $n $idxs $ev $mtv)))
      ((indep-part $tv)
         (frontier-parts-append-one
            $parts (indep-part $tv)))
      (unpoolable-part
         (frontier-parts-append-one
            $parts unpoolable-part)))))

;; Projections score with their source's confidence: a partial pool's marginal
;; confidence (0 for a strength-0 source) says nothing about the completed
;; pool's, and would starve the frontier before the join that completes it.
(: frontier-part-score
   (-> (| FrontierPart SkipPart UnpoolablePart) Number Number))
(= (frontier-part-score $part $pscore)
   (case $part (
      ((pool-part $_base $btv $_n $_idxs $_ev $_mtv) (max $pscore (tv-confidence $btv)))
      ($_ $pscore))))

;; A partial pool's marginal TV can have zero confidence (strength-0 source),
;; which zeroes the remaining chain's expected confidence and would starve the
;; frontier before the join that completes the pool. The pool's source
;; confidence is the frontier's real potential.
(: frontier-pool-potential
   (-> (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-pool-potential ()) 0.0)
(= (frontier-pool-potential (cons $part $rest))
   (case $part (
      ((pool-part $_k $btv $n $idxs $_ev $_mtv)
         (if (< (expr-arity $idxs) $n)
            (max (tv-confidence $btv) (frontier-pool-potential $rest))
            (frontier-pool-potential $rest)))
      ($_ (frontier-pool-potential $rest)))))

(: frontier-remaining-score
   (-> AndBundle (List (| FrontierPart UnpoolablePart)) Number))
(= (frontier-remaining-score $bundle $parts)
   (max
      (premises-expected-confidence
         (copy_term (and-bundle-premises $bundle)))
      (frontier-pool-potential $parts)))

(: frontier-and-step-premise? (-[det]-> $premise Bool))
(= (frontier-and-step-premise? $prem)
   (if (is-expr $prem)
      (if (== (car-atom $prem) CPU)
         (== (car-atom (cdr-atom $prem)) AndFormula)
         false)
      false))

;; Pop the consumed premise AND its AndFormula step, binding the step's output
;; to the parts fold (the chain's pairwise application would double count the
;; pooled source). Yields () when the premise is not directly followed by its
;; AndFormula step; the caller then drops the proof as before.
(: frontier-pooled-bundle
   (-[semidet]-> AndBundle Number TV
       (| AndBundle (List $none))))
(= (frontier-pooled-bundle $bundle $pid $folded)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
         ((cons $prem (cons $step $rest))
            (if (frontier-and-step-premise? $step)
               (if (= $prem (proof-output-atom-by-id $pid))
                  (if (= (CPU AndFormula $_fargs $folded) $step)
                     (make-and-bundle $goal $rest)
                     ())
                  ())
               ()))
         ($_ ())))))

(: make-and-bundle
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       AndBundle))
(= (make-and-bundle $goal $args) (and-bundle $goal $args))
(: present-and-bundle
   (-> (| AndBundle (List $none)) AndBundle))
(= (present-and-bundle (and-bundle $goal $premises))
   (make-and-bundle $goal $premises))
(: and-bundle-goal
   (-[det]-> AndBundle
       (| Goal (Statement KBContext Proof TV))))
(= (and-bundle-goal (and-bundle $goal $_premises)) $goal)
(: and-bundle-premises
   (-[det]-> AndBundle
       (List (| Goal (Statement KBContext Proof TV)))))
(= (and-bundle-premises (and-bundle $_goal $premises)) $premises)

(: advance-frontier-bundle
   (-[semidet]-> AndBundle Number
       (| AndBundle (List $none))))
(= (advance-frontier-bundle $bundle $pid)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (() ())
           ((cons $prem $rest)
              (if (= $prem (proof-output-atom-by-id $pid))
                 (make-and-bundle $goal $rest) ()))))))

(: waiter-live? (-[semidet]-> FrontierWaiter Bool))
(= (waiter-live? (frontier-waiter $_parent-gid $_bundle $_score $_seen $_parts $rev-pids))
   (proof-list-live? $rev-pids))

;; These compiler-generated joins keep their premise TVs separate instead of
;; combining them through AndFormula. Their premises may therefore share
;; evidence: total implication compares positive/refuting contexts, while a
;; member-inheritance sample pairs an antecedent membership with a consequent
;; that may itself have been derived from that antecedent. The resulting proof
;; still carries the union of both evidence sets, and normal cycle checks apply.
(: shared-evidence-frontier-proof? (-> $proof Bool))
(= (shared-evidence-frontier-proof? $proof)
   (case $proof (
      ((total-implication-frontier $_inner) true)
      ((inheritance-query-result $inner)
         (shared-evidence-frontier-proof? $inner))
      ((member-inheritance-sample $_antecedent $_consequent) true)
      ($_other false))))

(: frontier-allows-shared-evidence? (-> AndBundle Bool))
(= (frontier-allows-shared-evidence? $bundle)
   (let $goal (and-bundle-goal $bundle)
      (case $goal (
         (($_type $_kb $proof $_tv)
            (shared-evidence-frontier-proof? $proof))
         ($_other false)))))

(: advance-frontier-waiter-heap
   (-[semidet]-> $heap FrontierWaiter Number $heap))
(= (advance-frontier-waiter-heap $agenda (frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids) $pid)
   (if (waiter-live? (frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids))
      (let*
         ((($pscore $pev) (proof-stats-by-id $pid))
          ($proof-output (proof-output-atom-by-id $pid))
          ($frontier-pscore (frontier-proof-score $proof-output $pscore))
          ($part-hits (collapse (frontier-premise-part $pid)))
          ($part (frontier-part-or-unpoolable $part-hits))
          ($overlap
             (if (frontier-allows-shared-evidence? $bundle)
                false
                (premise-evidence-overlap? $seen $pev))))
         (if (frontier-pool-join? $part $parts $seen $pev)
            (frontier-advance-pooled-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids
               $pid $pev $part)
            (if $overlap $agenda
               (let $next-bundle (advance-frontier-bundle (copy_term $bundle) $pid)
                  (if (== $next-bundle ()) $agenda
                     (let*
                        (($typed-next-bundle
                            (present-and-bundle $next-bundle))
                         ($nparts (frontier-parts-add $parts $part))
                         ($next-score
                            (min-atom ($score
                                       (if (== $part skip-part)
                                          (max $frontier-pscore
                                             (frontier-pool-potential $nparts))
                                          (frontier-part-score $part $frontier-pscore))
                                       (frontier-remaining-score
                                          $typed-next-bundle $nparts)))))
                        (spawn-frontier-heap $agenda
                           $parent-gid
                           $typed-next-bundle
                           $next-score
                           (list_to_set
                              (append-evidence $seen $pev))
                           $nparts
                           (cons $pid $rev-pids))))))))
      $agenda))

;; A premise proof joins the frontier's pool for its projection source when a
;; pool for that source already exists and any evidence overlap is fully
;; explained by it. The join applies with or without overlap: projections of
;; one source are never independent, and forward-chained materialization can
;; hide their shared provenance behind distinct fact atoms. Overlap not
;; explained by a pool keeps the double-counting rejection.
(: frontier-pool-join?
   (-> (| FrontierPart SkipPart UnpoolablePart) (List (| FrontierPart UnpoolablePart)) (List Evidence) (List Evidence) Bool))
(= (frontier-pool-join? $part $parts $seen $pev)
   (case $part (
      ((pool-part $key $_btv $_n $_idxs $_ev $_mtv)
         (let $existing (frontier-parts-same-pool $parts $key)
            (if (== $existing no-pool) false
               (let (pool-part $_k $_btv2 $_n2 $_idxs2 $oev $_mtv2) $existing
                  (evidence-subset?
                     (evidence-intersection
                        (fact-evidence-only $seen)
                        (fact-evidence-only $pev))
                     (fact-evidence-only $oev))))))
      ($_ false))))

(: frontier-advance-pooled-heap
   (-[semidet]-> $heap Number AndBundle Number
       (List Evidence)
       (List (| FrontierPart UnpoolablePart))
       (List Number) Number (List Evidence)
       (| FrontierPart SkipPart UnpoolablePart)
       $heap))
(= (frontier-advance-pooled-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids $pid $pev $part)
   (let*
      (($nparts (frontier-parts-add $parts $part))
       ($folded-hits
          (collapse
             (frontier-parts-fold
                (frontier-parts-checked $nparts)))))
      (if (== $folded-hits ()) $agenda
         (let $next-bundle
            (frontier-pooled-bundle
               (copy_term $bundle) $pid
               (the TV (car-atom $folded-hits)))
            (if (== $next-bundle ()) $agenda
               (let*
                  (($typed-next-bundle
                      (present-and-bundle $next-bundle))
                   ($next-score
                      (min-atom ($score
                                 (frontier-part-score $part 0.000001)
                                 (frontier-remaining-score
                                    $typed-next-bundle $nparts)))))
                  (spawn-frontier-heap $agenda
                     $parent-gid
                     $typed-next-bundle
                     $next-score
                     (list_to_set
                        (append-evidence $seen $pev))
                     $nparts
                     (cons $pid $rev-pids))))))))

(: frontier-waiter-step
   (-[det]-> $waiter (List (| FrontierWaiter AggregateWaiter Atom))  (List (| FrontierWaiter AggregateWaiter Atom))))
(= (frontier-waiter-step $waiter $rest)
   (case $waiter
      (((frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids)
          (cons
             (frontier-waiter
                $parent-gid $bundle $score $seen $parts $rev-pids)
             $rest))
       ($_other $rest))))

(: aggregate-waiter-step
   (-[det]-> $waiter (List (| Number FrontierWaiter AggregateWaiter Atom))  (List (| Number FrontierWaiter AggregateWaiter Atom))))
(= (aggregate-waiter-step $waiter $rest)
   (case $waiter (((aggregate-waiter $agg-gid) (cons $agg-gid $rest)) ($_other $rest))))

(: stored-atom-list
   (-[det]-> Atom (List Atom)))
(= (stored-atom-list ())
   ())
(= (stored-atom-list (cons $head $rest))
   (cons $head (stored-atom-list $rest)))

(: advance-frontier-waiters-heap
   (-[semidet]-> $heap Number (List Atom) $heap))
(= (advance-frontier-waiters-heap $agenda $_pid ()) $agenda)
(= (advance-frontier-waiters-heap $agenda $pid (cons $waiter $rest))
   (case $waiter
      (((frontier-waiter $parent-gid $bundle $score $seen $parts $rev-pids)
          (advance-frontier-waiters-heap
             (advance-frontier-waiter-heap
                $agenda
                (frontier-waiter
                   $parent-gid $bundle $score $seen $parts $rev-pids)
                $pid)
             $pid
             $rest))
       ($_other
          (advance-frontier-waiters-heap $agenda $pid $rest)))))

(: schedule-aggregate-waiters-heap
   (-[semidet]-> $heap (List Atom) $heap))
(= (schedule-aggregate-waiters-heap $agenda ()) $agenda)
(= (schedule-aggregate-waiters-heap $agenda (cons $waiter $rest))
   (case $waiter
      (((aggregate-waiter $agg-gid)
          (schedule-aggregate-waiters-heap
             (schedule-aggregate-heap $agenda (the Number $agg-gid))
             $rest))
       ($_other
          (schedule-aggregate-waiters-heap $agenda $rest)))))

(: wake-proof-commit-heap
   (-[semidet]-> $heap Number Number $heap))
(= (wake-proof-commit-heap $agenda $gid $pid)
   (let*
      (($waiters
          (stored-atom-list
             (collapse
                (match &goal_waiter
                   ($gid $waiter) $waiter))))
       ($representative-pid (goal-merged-proof-id-for-pid $gid $pid))
       ($agenda1
          (advance-frontier-waiters-heap
             $agenda $representative-pid $waiters))
       ($agenda2
          (schedule-aggregate-waiters-heap $agenda1 $waiters)))
      $agenda2))

(: commit-proof-candidate-heap
   (-[semidet]-> $heap Number Bool ProofCandidate $heap))
(= (commit-proof-candidate-heap $agenda $gid $accepted
      (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $kind $children) $agenda
         (let $pid
            (once
               (store-proof-candidate $gid
                  (proof-candidate $kind $score $ev $children)))
            (wake-proof-commit-heap $agenda $gid $pid)))))

(: commit-aggregate-snapshot-heap
   (-[semidet]-> $heap Number
       (| Goal (Statement KBContext Proof TV))
       (List Evidence) (List Number) $heap))
(= (commit-aggregate-snapshot-heap $agenda $agg-gid $result $ev $children)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $pending $current-pid)
          (aggregate-by-id $agg-gid))
       ($pid
          (once
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate $result $ev $children))))
       ($_set
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $base-score
                   $pending $current-pid))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $base-score
                      $pending $pid)))))
       ($_cache-invalidate
          (if (== $current-pid ()) () (invalidate-proof-live-caches)))
       ($nagenda (wake-proof-commit-heap $agenda $agg-gid $pid)))
      $nagenda))

(: spawn-frontier-goal-heap
   (-[semidet]-> $heap Number Number FrontierWaiter $heap))

(: advance-frontier-waiter-fold-step
   (-[semidet]-> FrontierWaiter $heap Number $heap))
(= (advance-frontier-waiter-fold-step $waiter $agenda $pid)
   (advance-frontier-waiter-heap $agenda $waiter $pid))

(= (spawn-frontier-goal-heap $agenda $score $gid $waiter)
   (let*
      (($_1
          (once
             (chainer-add-atom &goal_waiter
                ($gid $waiter))))
       ($agenda1
          (proof-fold-flat-semidet (advance-frontier-waiter-fold-step $waiter)
             $agenda
             (goal-merged-proof-ids $gid)))
       ($nagenda (schedule-goal-heap $agenda1 $score $gid)))
      $nagenda))

(: base-rate-finish? (-[det]-> $finish Bool))
(= (base-rate-finish? $finish)
   (case $finish (
      (base-rate true)
      (weighted-base-rate true)
      (weighted-base-rate-with-prior true)
      ((weighted-base-rate-in-universe $_kbid) true)
      ((weighted-base-rate-with-prior-in-universe $_kbid) true)
      ((member-inheritance $_kbid) true)
      ($_other false))))

(: BaseRateAggregateKey Type)
(: base-rate-aggregate-key-value
   (-> KB Statement $mode BaseRateAggregateKey))
(: NoBaseRateAggregateKey Type)
(: no-base-rate-aggregate-key NoBaseRateAggregateKey)

(: base-rate-aggregate-key
   (-> $arguments
       (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value
               (brand KB $kbid)
               (brand Statement $pattern)
               $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))

(: commit-cached-aggregate-heap
   (-[semidet]-> $heap Number $arguments TV $heap))
(= (commit-cached-aggregate-heap $agenda $agg-gid $args $tv)
   (let*
      (($result (CPU FoldAllCompiled $args $tv))
       ($pid
          (once
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate $result () ())))))
      (wake-proof-commit-heap $agenda $agg-gid $pid)))

(: base-rate-refine-score (-> Number Number))
(= (base-rate-refine-score $score) (* 0.25 $score))

(: ensure-aggregate-child-goal
   (-[nondet]-> Number Goal $arguments Number Number))
(= (ensure-aggregate-child-goal $agg-gid $goal-view $args $score)
   (let*
      (($child-goal (aggregate-child-goal $goal-view))
       ((stored-goal-row
           $_stored-gid $depth $_goal $_expanded $_pending)
          (goal-by-id $agg-gid))
       ($child-gid (ensure-goal-at-depth $child-goal (+ 1 $depth)))
       ($hits
          (collapse
             (once
                (match &aggregate
                   (stored-aggregate-row
                      $agg-gid $_child $_args
                      $_base $_pending1 $_current)
                   true))))
       ($_agg
          (if (== $hits ())
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $score 0.0 ())))
             ())))
      $child-gid))

(: spawn-refining-aggregate-heap
   (-[nondet]-> $heap Number Number Goal $arguments TV BaseRateSource $heap))
(= (spawn-refining-aggregate-heap $agenda $score $agg-gid $goal-view $args $tv $source)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($pid
          (once
             (store-proof-candidate $agg-gid
                (aggregate-result-candidate
                   (CPU FoldAllCompiled $args $tv) () ()))))
       ($_source
          (if (== $source forward-approx)
             (add-atom &aggregate_forward_approx ($agg-gid))
             ()))
       ($_set
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $score 0.0 ()))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $score 0.0 $pid)))))
       ($_wait
          (once
             (chainer-add-atom &goal_waiter
                ($child-gid (aggregate-waiter $agg-gid)))))
       ($agenda1 (wake-proof-commit-heap $agenda $agg-gid $pid))
       ($nagenda (schedule-goal-heap $agenda1 (base-rate-refine-score $score) $child-gid)))
      $nagenda))

(: spawn-aggregate-goal-heap
   (-[nondet]-> $heap Number Number Goal $heap))
(= (spawn-aggregate-goal-heap $agenda $score $agg-gid $goal-view)
   (let*
      (($args (copy_term (let (CPU $_agg-fun $view-args $_goalres) $goal-view $view-args)))
       ($cache-key (base-rate-aggregate-key $args))
       ($entries
          (case $cache-key (
             ((base-rate-aggregate-key-value $kbid $pattern $mode)
                (base-rate-cache-entries-for-mode
                   (brand KB $kbid)
                   (brand Statement $pattern)
                   $mode))
             (no-base-rate-aggregate-key ())))))
      (if (== $entries ())
         (spawn-aggregate-goal-live-heap $agenda $score $agg-gid $goal-view $args)
         (let (base-rate $_kbid $_stored $stored-tv $source $_mode)
            (car-atom $entries)
            (let $tv (the TV $stored-tv)
               (if (== $source user)
                  (commit-cached-aggregate-heap
                     $agenda $agg-gid $args $tv)
                  (spawn-refining-aggregate-heap
                     $agenda $score $agg-gid $goal-view
                     $args $tv (the BaseRateSource $source))))))))

(: spawn-aggregate-goal-live-heap
   (-[nondet]-> $heap Number Number Goal $arguments $heap))
(= (spawn-aggregate-goal-live-heap $agenda $score $agg-gid $goal-view $args)
   (let*
      (($child-gid (ensure-aggregate-child-goal $agg-gid $goal-view $args $score))
       ($_wait
          (once
             (chainer-add-atom &goal_waiter
                ($child-gid (aggregate-waiter $agg-gid)))))
       ($agenda1 (schedule-goal-heap $agenda $score $child-gid))
       ($nagenda (schedule-aggregate-heap $agenda1 $agg-gid)))
      $nagenda))

(: aggregate-args-grouped? (-> $arguments Bool))
(= (aggregate-args-grouped? $args)
   (case $args (
      (($_kb $_pattern $_group $_extractor $_init $_fun $_finish $_tv-mode)
         true)
      ($_other false))))

(: aggregate-proof-fold-step
   (-[semidet]-> (KB Statement
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       AggregateState Number AggregateState))
(: aggregate-child-tv
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (| TV NoTV)))
(= (aggregate-child-tv $child)
   (case $child (
      ((CPU $_formula $_arguments $_result) no-tv)
      (($_type $_kb $_proof $tv) $tv))))

(= (aggregate-proof-fold-step $args (aggregate-state $acc $ev $children) $pid)
   (let*
      ((($_agg-kb $_agg-pattern $extractor $_agg-init $fun $_agg-finish $_agg-tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom-by-id $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($child-tv (aggregate-child-tv $child-atom))
       ($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
       ($nev
          (list_to_set (append-evidence $ev $pev)))
       ($nchildren
          (frontier-append-index $children $pid)))
      (aggregate-state $nacc $nev $nchildren)))

(: aggregate-noncyclic-source-step
   (-[semidet]-> Number (List Number) Number (List Number)))
(= (aggregate-noncyclic-source-step $agg-gid $acc $pid)
   (if (proof-depends-on-goal-seen?
         $pid $agg-gid closed-goal ())
      $acc
      (frontier-append-index $acc $pid)))

;; Cycle rejection must happen before equivalent outputs are merged.  Otherwise
;; one recursive proof can make a merged representative look cyclic and hide an
;; independent direct proof of the same grounded atom from the aggregate.
(: aggregate-fold-source-ids
   (-[semidet]-> Number Number (List Number)))
(= (aggregate-fold-source-ids $agg-gid $child-gid)
   (proof-output-group-representative-pids $child-gid
      (proof-output-groups
         (proof-fold-flat-semidet (aggregate-noncyclic-source-step $agg-gid)
            ()
            (goal-live-proof-ids $child-gid)))))

(: aggregate-final-state
   (-[semidet]-> Number Number
       (KB Statement
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       AggregateState))
(= (aggregate-final-state $agg-gid $child-gid $args)
   (let*
      ((($_kb $_pattern $_extractor $init-acc $_fun $_finish $_tv-mode) (copy_term $args)))
      (proof-fold-flat-semidet (aggregate-proof-fold-step $args)
         (aggregate-state $init-acc () ())
         (aggregate-fold-source-ids $agg-gid $child-gid))))

(: aggregate-group-update
   (-[semidet]-> (| ExtractValue ExtractInheritanceTV ExtractTV)
       (-[semidet]-> $accumulator $value $accumulator)
       $accumulator $group $child-atom (| TV NoTV)
       (List Evidence) Number
       (List AggregateGroupState) (List AggregateGroupState)))
(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid ())
   (let*
      (($nacc (aggregate-foldall-step-acc $extractor $fun $init $child-atom $child-tv))
       ($nev (list_to_set $pev)))
      (cons (aggregate-group-state $group $nacc $nev ($pid)) ())))
(= (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid (cons (aggregate-group-state $old-group $acc $ev $children) $rest))
   (if (== $group $old-group)
      (let*
         (($nacc (aggregate-foldall-step-acc $extractor $fun $acc $child-atom $child-tv))
          ($nev
             (list_to_set (append-evidence $ev $pev)))
          ($nchildren
             (frontier-append-index $children $pid)))
         (cons (aggregate-group-state $old-group $nacc $nev $nchildren) $rest))
      (cons (aggregate-group-state $old-group $acc $ev $children)
         (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $rest))))

(: grouped-aggregate-proof-fold-step
   (-[semidet]-> (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       (List AggregateGroupState) Number (List AggregateGroupState)))
(= (grouped-aggregate-proof-fold-step $args $states $pid)
   (let*
      ((($_agg-kb $pattern $group-template $extractor $init $fun $_finish $_tv-mode) (copy_term $args))
       ($child-atom (proof-output-atom-by-id $pid))
       (($_pscore $pev) (proof-stats-by-id $pid))
       ($group (aggregate-step-group-value $pattern $group-template $child-atom))
       ($child-tv (aggregate-child-tv $child-atom)))
      (aggregate-group-update $extractor $fun $init $group $child-atom $child-tv $pev $pid $states)))

(: grouped-aggregate-final-states
   (-[semidet]-> Number Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          $finish AggregateTVMode)
       (List AggregateGroupState)))
(= (grouped-aggregate-final-states $agg-gid $child-gid $args)
   (proof-fold-flat-semidet (grouped-aggregate-proof-fold-step $args)
      ()
      (aggregate-fold-source-ids $agg-gid $child-gid)))

(: grouped-aggregate-result
   (-[semidet]-> (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          (| IdentityFinish
             DistAverageFinish
             BaseRateFinish
             WeightedBaseRateFinish
             WeightedBaseRateWithPriorFinish
             MemberInheritanceFinish
             WeightedBaseRateInUniverseFinish
             WeightedBaseRateWithPriorInUniverseFinish
             UniformPriorFinish
             UniformPriorKnownFinish)
          AggregateTVMode)
       AggregateGroupState Goal))
(= (grouped-aggregate-result $args (aggregate-group-state $group $acc $_ev $_children))
   (let*
      ((($kb $pattern $_group-template $extractor $init $fun $finish $tv-mode)
          $args)
       ($grouped-args
          (quote
             ($kb $pattern $group $extractor $init $fun $finish $tv-mode)))
       ($result (finish-aggregate $finish $acc)))
      (CPU GroupedFoldAllCompiled $grouped-args $result)))

(: commit-grouped-aggregate-state-heap
   (-[semidet]-> Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          (| IdentityFinish
             DistAverageFinish
             BaseRateFinish
             WeightedBaseRateFinish
             WeightedBaseRateWithPriorFinish
             MemberInheritanceFinish
             WeightedBaseRateInUniverseFinish
             WeightedBaseRateWithPriorInUniverseFinish
             UniformPriorFinish
             UniformPriorKnownFinish)
          AggregateTVMode)
       $heap AggregateGroupState $heap))
(= (commit-grouped-aggregate-state-heap $agg-gid $args $agenda (aggregate-group-state $group $acc $ev $children))
   (let*
      (($result (grouped-aggregate-result $args (aggregate-group-state $group $acc $ev $children)))
       ($score (term-confidence $result))
       ($accepted (classify-goal-proof-candidate $agg-gid $result $ev $score)))
      (commit-grouped-aggregate-candidate-heap $agenda
         $agg-gid
         $accepted
         (aggregate-result-candidate $result $ev $children))))

(: append-grouped-aggregate-current-pid!
   (-[semidet]-> Number Number (| Bool (List $none))))
(= (append-grouped-aggregate-current-pid! $agg-gid $pid)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $pending $stored-current-pids)
          (aggregate-by-id $agg-gid))
       ($current-pids $stored-current-pids)
      ($next-pids (cons $pid $current-pids)))
      (progn
         (remove-atom &aggregate
            (stored-aggregate-row
               $agg-gid $child-gid $args $base-score
               $pending $current-pids))
         (once
            (chainer-add-atom &aggregate
               (stored-aggregate-row
                  $agg-gid $child-gid $args $base-score
                  $pending $next-pids))))))

(: commit-grouped-aggregate-candidate-heap
   (-[semidet]-> $heap Number Bool ProofCandidate $heap))
(= (commit-grouped-aggregate-candidate-heap $agenda $agg-gid $accepted (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $agg-gid $kind $children) $agenda
         (let*
            (($pid
                (once
                   (store-proof-candidate $agg-gid
                      (proof-candidate $kind $score $ev $children))))
             ($_set (append-grouped-aggregate-current-pid! $agg-gid $pid))
             ($_cache-invalidate (invalidate-proof-live-caches)))
            (wake-proof-commit-heap $agenda $agg-gid $pid)))))

(: run-grouped-aggregate-heap
   (-[semidet]-> $heap Number Number
       (KB Statement $group-template
          (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
          (-[semidet]-> $accumulator $value $accumulator)
          (| IdentityFinish
             DistAverageFinish
             BaseRateFinish
             WeightedBaseRateFinish
             WeightedBaseRateWithPriorFinish
             MemberInheritanceFinish
             WeightedBaseRateInUniverseFinish
             WeightedBaseRateWithPriorInUniverseFinish
             UniformPriorFinish
             UniformPriorKnownFinish)
          AggregateTVMode)
       $heap))
(= (run-grouped-aggregate-heap $agenda $agg-gid $child-gid $args)
   (proof-fold-flat-semidet (commit-grouped-aggregate-state-heap $agg-gid $args)
      $agenda
      (grouped-aggregate-final-states $agg-gid $child-gid $args)))

(: aggregate-commit-evidence
   (-> $finish (List Evidence) (List Evidence)))
(= (aggregate-commit-evidence $finish $ev)
   (if (background-aggregate-finish? $finish) () $ev))

(: run-aggregate-heap (-[nondet]-> $heap Number $heap))
(= (run-aggregate-heap $agenda $agg-gid)
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $child-gid $args
            $base-score $pending $current-pid)
          (aggregate-by-id $agg-gid))
       ($grouped? (aggregate-args-grouped? $args))
       ($next-current-pid (if $grouped? () $current-pid))
       ($_clear
          (progn
             (remove-atom &aggregate
                (stored-aggregate-row
                   $agg-gid $child-gid $args $base-score
                   $pending $current-pid))
             (once
                (chainer-add-atom &aggregate
                   (stored-aggregate-row
                      $agg-gid $child-gid $args $base-score
                      0.0 $next-current-pid))))))
      (if $grouped?
         (run-grouped-aggregate-heap
            $agenda $agg-gid $child-gid
            (the
               (KB Statement $group-template
                  (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
                  (-[semidet]-> $accumulator $value $accumulator)
                  (| IdentityFinish
                     DistAverageFinish
                     BaseRateFinish
                     WeightedBaseRateFinish
                     WeightedBaseRateWithPriorFinish
                     MemberInheritanceFinish
                     WeightedBaseRateInUniverseFinish
                     WeightedBaseRateWithPriorInUniverseFinish
                     UniformPriorFinish
                     UniformPriorKnownFinish)
                  AggregateTVMode)
               (copy_term $args)))
         (let*
            (((aggregate-state $acc $ev $children)
                (aggregate-final-state
                   $agg-gid $child-gid
                   (the
                      (KB Statement
                         (| ExtractValue ExtractInheritanceTV ExtractTV) $initial
                         (-[semidet]-> $accumulator $value $accumulator)
                         (| IdentityFinish
                            DistAverageFinish
                            BaseRateFinish
                            WeightedBaseRateFinish
                            WeightedBaseRateWithPriorFinish
                            MemberInheritanceFinish
                            WeightedBaseRateInUniverseFinish
                            WeightedBaseRateWithPriorInUniverseFinish
                            UniformPriorFinish
                            UniformPriorKnownFinish)
                         AggregateTVMode)
                      (copy_term $args))))
             (($_kb $_pattern $_extractor $_init $_fun $finish $_tv-mode)
                $args)
             ($result
                (CPU FoldAllCompiled $args
                   (finish-stored-aggregate $finish $acc)))
             ($commit-ev (aggregate-commit-evidence $finish $ev)))
            (if
               (base-rate-refinement-degrades?
                  $agg-gid $finish $current-pid $result)
               $agenda
               (if
                  (aggregate-snapshot-changed?
                     $current-pid $result $commit-ev)
                  (commit-aggregate-snapshot-heap
                     $agenda $agg-gid $result $commit-ev $children)
                  $agenda))))))

; Background aggregates (node priors / base rates) summarise the whole store
; rather than chaining specific evidence, so their committed proof carries no
; evidence dependency -- this keeps them from forming evidence cycles with the
; very premises they are computed alongside.
(: background-aggregate-finish? (-> $finish Bool))
(= (background-aggregate-finish? $finish)
   (if (base-rate-finish? $finish) true
      (if (== $finish uniform-prior) true (== $finish uniform-prior-known))))

(: base-rate-refinement-degrades?
   (-[semidet]-> Number $finish (| Number (List Number)) $result Bool))
(= (base-rate-refinement-degrades? $agg-gid $finish $current-pid $result)
   (if (not (==
         (collapse (once (match &aggregate_forward_approx ($agg-gid) true)))
         ()))
      false
      (if (base-rate-finish? $finish)
      (if (== $current-pid ()) false
         (let*
            (($new-tv (let (CPU $_fun $_args $ntv) $result $ntv))
             ($current-tv
                (let (CPU $_cfun $_cargs $ctv)
                   (proof-output-atom-by-id (the Number $current-pid))
                   $ctv)))
            (if (= $current-tv (STV $_cs $_cc))
               (if (= $new-tv (STV $_ns $_nc))
                  (< (tv-confidence $new-tv) (tv-confidence $current-tv))
                  true)
               false)))
      false)))

(: direct-goal-results-view
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))))
(= (direct-goal-results-view $steps (CPU $fun $args $_res))
   (CPU $fun $args (reduce (cpu-call $steps $fun $args))))
(= (direct-goal-results-view $steps ($type $kb $prf $tv))
   (match &kb ($type $kb $prf $tv)
      (let $raw (quote ($type $kb $prf $tv))
         (if (backward-acyclic-term? $raw)
            (backward-runtime-fact
               $type $kb $prf $tv)
            (empty)))))

(: expand-direct-goal-step
   (-[semidet]-> Number (| Goal (Statement KBContext Proof TV))
       $heap
       (| Goal (Statement KBContext Proof TV))
       $heap))
(= (expand-direct-goal-step $gid $_goal $agenda $result)
   (let*
      (($score (term-confidence $result))
       ($ev (leaf-evidence-for-result $result))
       ($accepted (classify-goal-proof-candidate $gid $result $ev $score))
       ($nagenda (commit-proof-candidate-heap $agenda $gid $accepted (leaf-result-candidate $result $ev))))
      $nagenda))

(: expand-direct-goal-heap
   (-[semidet]-> $heap Number Number
       (| Goal (Statement KBContext Proof TV))
       $heap))
(= (expand-direct-goal-heap $agenda $steps $gid $goal)
   (let*
      (($results (collapse (direct-goal-results-view $steps $goal)))
       ($agenda1
          (proof-fold-flat-semidet
             (expand-direct-goal-step $gid $goal) $agenda $results)))
      (expand-rule-goal-heap $agenda1 $gid $goal)))

(: inject-compiled-query-adds
   (-[semidet]-> CompiledQuery (List $none)))
(= (inject-compiled-query-adds (compiled-query $_goal $adds))
   (if (is-var $adds)
      (empty)
      (once
         (inject-compiled-adds $adds))))

(: inject-implication-subgoal-query-adds
   (-[semidet]-> (| Goal (Statement KBContext Proof TV))
       (List $none)))
(= (inject-implication-subgoal-query-adds $goal)
   (case $goal (
      (($type ($kbid MAIN Nil) $prf $tv)
         (case $type (
            ((Implication
                  (cons Premises $_premises)
                  (cons Conclusions $_conclusions))
               (let $compiled-queries
                  (collapse
                     (mm2compileQuery
                        (brand KB $kbid)
                        (:
                           (brand Proof $prf)
                           (brand Statement $type)
                           (the TV $tv))))
                  (foreach-flat-semidet
                     inject-compiled-query-adds
                     (the
                        (List CompiledQuery)
                        $compiled-queries))))
            ($_other ()))))
      ($_other ()))))

(: open-rule-goal?
   (-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (open-rule-goal? $goal)
   (case $goal (
      (($type $_kb $_prf $_tv)
         (not (== (extract-vars $type) ())))
      ($_other false))))

(: RuleGoalMatch Type)
(: rule-goal-match
   (-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (| Goal (Statement KBContext Proof TV))
       Number RuleGoalMatch))

(: rule-goal-head-view-for-key
   (-[nondet]-> (| Goal (Statement KBContext Proof TV))
      Number ForwardTriggerKey  RuleGoalMatch))
(= (rule-goal-head-view-for-key $goal $parent-gid $key)
   (match ccls_head_index ($key $rule-id)
      (match rules
         (runtime-rule-row $rule-id $goal $args)
         (rule-goal-match $rule-id
            $args $goal $parent-gid))))

;; Look up rules by the goal's concrete head *and* the `any` wildcard bucket, so
;; an open goal still reaches variable-headed conclusions (which only live under
;; `any`). This mirrors the forward chainer's direct+wildcard union and removes
;; the behavioural gap between open and closed goals.
(: rule-goal-head-view
   (-[nondet]-> (| Goal (Statement KBContext Proof TV))
      Number  RuleGoalMatch))
(= (rule-goal-head-view $goal $parent-gid)
   (if (= $goal ($_type ($kbid $_ctx $_vars) $_prf $_tv))
      (let*
          (($key
             (forward-type-trigger-key
                (brand KB $kbid)
                (brand Statement $_type)))
          ($wildcard-key
             (forward-premise-wildcard-key $goal)))
         (superpose (
            (rule-goal-head-view-for-key $goal $parent-gid $key)
            (if (== $key $wildcard-key) (empty)
               (rule-goal-head-view-for-key
                  $goal $parent-gid $wildcard-key)))))
      (empty)))

(: rule-goal-contextual?
   (-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (rule-goal-contextual? $goal)
   (case $goal (
      (($_type ($_kbid $ctx $_vars) $_prf $_tv)
         (not (== $ctx MAIN)))
      ($_other false))))

(: rule-goal-full-view
   (-[nondet]-> (| Goal (Statement KBContext Proof TV))
      Number  RuleGoalMatch))
(= (rule-goal-full-view $goal $parent-gid)
   (let $lookup-goal (copy_term $goal)
      (match ccls_index ($lookup-goal $rule-id)
         (match rules
            (runtime-rule-row $rule-id $stored-goal $args)
            (if (= $stored-goal $goal)
               (rule-goal-match $rule-id
                  (contextualize-rule-args
                     $goal $args)
                  $goal
                  $parent-gid)
               (empty))))))

(: same-var-in-list? (-> $variable (List $variable) Bool))
(= (same-var-in-list? $_var ()) false)
(= (same-var-in-list? $var (cons $head $tail))
   (or (== $var $head) (same-var-in-list? $var $tail)))

(: any-same-var? (-> (List $variable) (List $variable) Bool))
(= (any-same-var? () $_vars) false)
(= (any-same-var? (cons $var $rest) $vars)
   (or (same-var-in-list? $var $vars) (any-same-var? $rest $vars)))

(: context-vars-in-type?
   ;; KBContext is an erased newtype, so its destructured variables field is a
   ;; raw wire value here: Nil or a variable list.
   (-> Expression Atom Bool))
(: any-context-var-in?
   (-> (List Variable) (List Variable) Bool))
(= (any-context-var-in? $_type-vars ()) false)
(= (any-context-var-in? $type-vars (cons $var $rest))
   (or (same-var-in-list? $var $type-vars)
      (any-context-var-in? $type-vars $rest)))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false
      (let $type-vars
         (extract-vars $type)
         (any-context-var-in?
            (the (List Variable) $type-vars)
            (the (List Variable) $vars)))))

(: contextualize-rule-premise
   (-> (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))))
(= (contextualize-rule-premise $premise
      ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv))
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (if
               (and (== $prem-ctx MAIN)
                  (and (not (== $ctx MAIN))
                     (context-vars-in-type? $type $vars)))
               (let $fact-kb
                  (make-kb-context
                     (brand KB $kbid) $ctx $vars)
                  (backward-runtime-fact
                     $type $fact-kb $prf $tv))
               (let $fact-kb
                  (make-kb-context
                     (brand KB $kbid) $prem-ctx $prem-vars)
                  (backward-runtime-fact
                     $type $fact-kb $prf $tv))))
         ((CPU $fun $args $res) (CPU $fun $args $res))))))

(: contextualize-rule-args
   (-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       (List (| Goal (Statement KBContext Proof TV)))))
(= (contextualize-rule-args $_goal ()) ())
(= (contextualize-rule-args $goal (cons $premise $rest))
   (cons (contextualize-rule-premise $premise $goal)
      (contextualize-rule-args $goal $rest)))

(: rule-goal-view
   (-[nondet]-> (| Goal (Statement KBContext Proof TV))
      Number  RuleGoalMatch))
(= (rule-goal-view $goal $parent-gid)
   (if (open-rule-goal? $goal)
      (if (rule-goal-contextual? $goal)
         (rule-goal-full-view $goal $parent-gid)
         (rule-goal-head-view $goal $parent-gid))
      (rule-goal-full-view $goal $parent-gid)))

(: spawn-frontier-heap
   (-[semidet]-> $heap Number AndBundle Number (List Evidence) (List (| FrontierPart UnpoolablePart)) (List Number) $heap))
(= (spawn-frontier-heap $agenda $parent-gid $bundle $score $seen $parts $rev-pids)
   (let*
      (($goal (and-bundle-goal $bundle))
       ($premises (and-bundle-premises $bundle)))
      (case $premises (
           (()
              (let*
                 (($pid-list (reverse-number-list $rev-pids))
                  ($candidate
                     (normalize-proof-candidate-evidence
                        (proof-candidate (rule $goal) $score $seen $pid-list)))
                  ((proof-candidate $_kind $_candidate-score $candidate-ev $_children) $candidate))
                 (commit-proof-candidate-heap $agenda
                    $parent-gid
                    (classify-goal-proof-candidate $parent-gid $goal $candidate-ev $score)
                    $candidate)))
           ((cons $prem $_rest)
              (let*
                 (((stored-goal-row
                       $_stored-gid $parent-depth
                       $_goal1 $_expanded $_pending)
                    (goal-by-id $parent-gid))
                  ($gid (ensure-goal-at-depth $prem (+ 1 $parent-depth)))
                  ($stored-bundle (copy_term $bundle)))
                 (spawn-frontier-goal-heap $agenda
                    $score
                    $gid
                    (frontier-waiter $parent-gid
                       $stored-bundle
                       $score
                       $seen
                       $parts
                       $rev-pids))))))))

(: expand-rule-goal-heap
   (-[semidet]-> $heap Number
       (| Goal (Statement KBContext Proof TV))
       $heap))
(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (proof-fold-flat-semidet expand-rule-goal-fold
      $agenda
      (collapse (rule-goal-view $goal $parent-gid))))

;; Cached expected score, computed at rule-add time (store-rule-expected-score!).
;; The cache assumes the goal's TV slot is unbound (the value depends only on
;; premise structure and stored TVs then); a goal queried with a known TV falls
;; back to computing against the bound bundle, as before.
(: inheritance-lift-rule-goal?
   (-> (| Goal
          (Statement KBContext Proof TV))
       Bool))
(= (inheritance-lift-rule-goal? $goal)
   (case $goal (
      (($_type $_kb ((inheritance-rule-lift $_rule) $_source $_instance) $_tv)
         true)
      ($_other false))))

(: rule-expected-score
   (-> Number
       (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       Number))
(= (rule-expected-score $rule-id $goal $args)
   ;; A specialized lift is a completeness bridge for evidence that cannot
   ;; execute directly in the hypothetical context. Native implication views
   ;; must be allowed to finish before that bridge closes the parent goal.
   (if (inheritance-lift-rule-goal? $goal) 0.000001
      (if
         (case $goal (
            (($_gtype $_gkb $_gprf $gtv) (is-var $gtv))
            ($_other false)))
         (let $hits (collapse (match rule_expected ($rule-id $score) $score))
            (if (== $hits ())
               (premises-expected-confidence (copy_term $args))
               (the Number (car-atom $hits))))
         (premises-expected-confidence (copy_term $args)))))

;; --- Premise pre-filter (opt-in via set-backward-premise-prefilter) ---------
;; Walks a copy of a candidate rule's premise list before any frontier state is
;; created: ground deterministic CPU premises are evaluated eagerly (binding
;; e.g. computed step variables for later premises), and a fully ground atom
;; premise prunes the rule when no fact matches it AND no rule can conclude its
;; head. In KBs where every premise head is also some rule's conclusion the
;; filter never prunes, so behavior degrades to the unfiltered search.

(: set-backward-premise-prefilter (-> Bool Bool))
(= (set-backward-premise-prefilter $enabled) (change-state! bwd_premise_prefilter $enabled))
(: backward-premise-prefilter? (-> Bool))
(= (backward-premise-prefilter?)
   (let $values
      (collapse (catch (get-state bwd_premise_prefilter)))
      (if (== $values ())
         false
         (if-error-bool (car-atom $values) false))))

(: prefilter-head-concludable?
   (-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (prefilter-head-concludable? $prem)
   (let $key (forward-indexable-premise-key $prem)
      (if (== $key ()) true
         (let $wildcard (forward-premise-wildcard-key $prem)
            (if
               (not
                  (==
                     (collapse
                        (once
                           (match ccls_head_index
                              ($key $_id) true)))
                     ()))
               true
               (if (== $key $wildcard)
                  false
                  (not
                     (==
                        (collapse
                           (once
                              (match ccls_head_index
                                 ($wildcard $_wid) true)))
                        ()))))))))

(: prefilter-fact-missing?
   (-> (Statement KBContext Proof TV) Bool))
(= (prefilter-fact-missing? ($type ($kbid $_ctx $_vars) $_prf $_tv))
   (== (collapse (once (match &kb ($type ($kbid $_c2 $_v2) $_p2 $_t2) true))) ()))

;; CPU functions the filter must not run eagerly: aggregate folds have their own
;; search machinery and store-scanning formulas are too costly for a filter.
(: prefilter-cpu-opaque? (-> $function Bool))
(= (prefilter-cpu-opaque? $fun)
   (same-var-in-list?
      $fun
      (FoldAllCompiled GroupedFoldAllCompiled ConceptNodePriorFormula)))

(: prefilter-premise-blocks?
   (-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (prefilter-cpu-opaque? $fun) false
               ;; Only run a CPU premise eagerly when its argument list is fully
               ;; ground. Building an ($fun ...) expression here would apply it
               ;; to unevaluated arguments.
               (if
                  (and (not (is-var $fun))
                     (== (extract-vars $args) ()))
                  (let $hits (collapse (cpu-call 0 $fun $args))
                     (if (== $hits ()) true
                        (if (= $res (car-atom $hits)) false true)))
                  false)))
         (($type ($kbid $ctx $vars) $prf $tv)
            (let*
               (($fact-kb
                   (make-kb-context
                      (brand KB $kbid) $ctx $vars))
                ($fact
                   (backward-runtime-fact
                      $type $fact-kb $prf $tv)))
               (if (== (extract-vars $type) ())
                  (if (prefilter-fact-missing? $fact)
                     (not (prefilter-head-concludable? $fact))
                     false)
                  false)))))))

(: prefilter-prunes-walk
   (-> (List (| Goal (Statement KBContext Proof TV))) Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

;; The walk runs on a copy (eager CPU evaluation binds variables) inside a
;; collapse so a premise shape neither clause covers makes the walk yield
;; nothing and the rule is kept, never dropped.
(: rule-premise-prefilter-prunes?
   (-> (List (| Goal (Statement KBContext Proof TV))) Bool))
(= (rule-premise-prefilter-prunes? $args)
   (if (backward-premise-prefilter?)
      (let $hits (collapse (prefilter-prunes-walk (copy_term $args)))
         (if (== $hits ()) false (car-atom $hits)))
      false))

(: expand-rule-goal-fold
   (-[semidet]-> $heap RuleGoalMatch $heap))
(= (expand-rule-goal-fold $agenda (rule-goal-match $rule-id $args $goal $parent-gid))
   (if (rule-premise-prefilter-prunes? $args) $agenda
      (let*
         (($expected-score
             (rule-expected-score $rule-id $goal $args))
          ($bound
             (rule-marginal-score
                (goal-current-confidence $parent-gid)
                $expected-score))
          ($bundle (copy_term (make-and-bundle $goal $args))))
         (spawn-frontier-heap $agenda
            $parent-gid
            $bundle
            $bound
            ()
            ()
            ()))))

(: expand-goal-heap
   (-[semidet]-> $heap Number Number Number $heap))
(= (expand-goal-heap $agenda $steps $score $gid)
   (let*
      (((stored-goal-row
            $_stored-gid $depth $goal $expanded $pending)
          (goal-by-id $gid))
       ($_expand
          (progn
             (remove-atom &goal
                (stored-goal-row
                   $gid $depth $goal $expanded $pending))
             (once
                (chainer-add-atom &goal
                   (stored-goal-row
                      $gid $depth $goal true $pending)))))
       ($_query-adds (if (> $depth 0) (inject-implication-subgoal-query-adds $goal) ()))
       ($nagenda0
          (if (= $goal (CPU $fun $_args $_res))
             (if (== $fun FoldAllCompiled)
                (once
                   (spawn-aggregate-goal-heap
                      $agenda $score $gid (the Goal $goal)))
                (if (== $fun GroupedFoldAllCompiled)
                   (once
                      (spawn-aggregate-goal-heap
                         $agenda $score $gid (the Goal $goal)))
                   (expand-direct-goal-heap
                      $agenda $steps $gid $goal)))
             (expand-direct-goal-heap $agenda $steps $gid $goal)))
       ($nagenda (if (== $nagenda0 ()) (empty_heap) $nagenda0)))
      $nagenda))

(: search-agenda-step
   (-[nondet]-> Number $heap (| QueueGoal QueueAggregate) SearchState))
(= (search-agenda-step $steps $agenda (qgoal $score $gid))
   (let*
      (((stored-goal-row
            $_stored-gid $depth $goal $expanded $pending)
          (goal-by-id $gid)))
      (if $expanded
         (search-agenda-heap $steps $agenda)
         (if (== $pending $score)
            (let*
               (($_clear
                    (progn
                       (remove-atom &goal
                          (stored-goal-row
                             $gid $depth $goal $expanded $pending))
                       (once
                          (chainer-add-atom &goal
                             (stored-goal-row
                                $gid $depth $goal $expanded 0.0)))))
                ($next-steps (- $steps 1))
                ($nagenda
                   (once
                      (bounded-agenda-prune $next-steps
                         (expand-goal-heap $agenda $steps $score $gid)))))
               (search-agenda-heap $next-steps $nagenda))
            (search-agenda-heap $steps $agenda)))))

(= (search-agenda-step $steps $agenda (qagg $score $agg-gid))
   (let*
      (((stored-aggregate-row
            $_stored-agg-gid $_child-gid $_args
            $_base-score $pending $_current-pid)
          (aggregate-by-id $agg-gid)))
      (if (== $pending $score)
         (let*
            (($next-steps (- $steps 1))
             ($nagenda
                (once
                   (bounded-agenda-prune $next-steps
                      (once (run-aggregate-heap $agenda $agg-gid))))))
            (search-agenda-heap $next-steps $nagenda))
         (search-agenda-heap $steps $agenda))))

(: search-agenda-heap (-[nondet]-> Number $heap SearchState))
(= (search-agenda-heap $steps $agenda)
   (if (<= $steps 0)
      (search-state $steps $agenda)
      (if (== (the Number (heap_size $agenda)) 0)
         (search-state $steps $agenda)
         (let*
            (($rest (get_from_heap $agenda $_priority $item)))
            (search-agenda-step $steps $rest
               (the (| QueueGoal QueueAggregate) $item))))))

(: harvest-base-rate-entry
   (-[semidet]-> $arguments (| Number (List Number)) (List $none)))
(= (harvest-base-rate-entry $args $current-pid)
   (let $key (base-rate-aggregate-key $args)
      (case $key (
         (no-base-rate-aggregate-key ())
         ((base-rate-aggregate-key-value $kbid $pattern $mode)
            (if (== $current-pid ()) ()
               (let $output
                  (proof-output-atom-by-id (the Number $current-pid))
                  (if (= $output (CPU $_fun $_out-args (STV $s $c)))
                     (store-computed-base-rate!
                        (brand KB $kbid)
                        (brand Statement $pattern)
                        (STV $s $c)
                        $mode)
                     ()))))))))

(: harvest-base-rates (-> (List $none)))
(= (harvest-base-rates)
   (let $_
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $_agg-gid $_child $args
               $_base $_pending $current-pid)
            (harvest-base-rate-entry $args $current-pid)))
      ()))

;; Internal queue operations are semidet because an arbitrary numeric ID may
;; be absent.  The public runner creates its root ID immediately above, so turn
;; an impossible missing-root result into an empty, deterministic search
;; rather than letting the whole query vanish.
(: chainer-first-or (-[det]-> $value (List $value) $value))
(= (chainer-first-or $fallback ()) $fallback)
(= (chainer-first-or $_fallback (cons $value $_rest)) $value)

(: chainer-run
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       ChainerRunResult))
(= (chainer-run $steps $goal)
   (let*
      (($_clear (foreach-flat remove-all-atoms (&goal &goal_lookup &goal_waiter &aggregate &aggregate_forward_approx &proof &proof_parent &proof_invalidated_epoch &proof_live_cache &goal_live_cache &proof_static_live &proof_superseded)))
       ($_reset (foreach-flat (|-> ($key) (change-state! $key 0)) (bwd_gid bwd_pid bwd_live_epoch)))
       ($root-gid (ensure-goal-at-depth $goal 0))
       ($agenda0
          (chainer-first-or (empty_heap)
             (the (List Atom)
                (collapse
                   (once
                      (schedule-goal-heap
                         (empty_heap) 1.0 $root-gid))))))
       ($search-result
          (chainer-first-or
             (search-state 0 $agenda0)
             (the (List SearchState)
                (collapse
                   (once
                      (if (<= $steps 0)
                         (search-state 0 $agenda0)
                         (search-agenda-heap (+ $steps 1) $agenda0)))))))
       ((search-state $_steps-left $_agenda1)
          $search-result)
       ($_harvest (harvest-base-rates)))
      (chainer-run-result
         $root-gid
         (chainer-first-or ()
            (the (List (List RuntimeResult))
               (collapse (once (goal-results $root-gid))))))))

(: chainer
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer $steps $goal)
   (let (chainer-run-result $_root-gid $results) (chainer-run $steps $goal)
      $results))

(: chainer-materialize
   (-[nondet]-> Number (| Goal (Statement KBContext Proof TV))
       (List RuntimeResult)))
(= (chainer-materialize $steps $goal)
   (let (chainer-run-result $root-gid $results) (chainer-run $steps $goal)
      (let $_materialized (materialize-goal-proofs-to-kb $root-gid)
         $results)))
