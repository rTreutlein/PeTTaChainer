;; Demand, change propagation, evaluation scheduling and budget payment.
;; Depends on eval_core; query lifecycle and public entry points follow.


;; A rule's hazard can change while its tally stands: a head of the rule gains
;; or loses a stage position after its samples were taken (a sort declared, or
;; a Stage constant first stated there), or the KB's rule-change hazard is
;; set. The evaluation that follows brings every standing tally to its rule's
;; hazard now (instance-hazard): a tally whose hazard differs is dropped and
;; every member it held is marked to be taken again, in the order it was first
;; taken, which its read rows keep (sk-instance-reads!), before the members
;; still waiting to join it.
(: sk-rehazard-tallies! (-[det]-> Atom))
(= (sk-rehazard-tallies!)
   (fold-flat sk-rehazard-step () (collapse (match &ctx_sk_instance_tally ($hash $fold $_acc) ($hash $fold)))))

(: sk-rehazard-step (-[det]-> Atom (Number SkeletonKey) Atom))
(= (sk-rehazard-step $_acc ($hash $fold))
   (case $fold (
      ((sk-fold $args) (let $kb (car-atom $args) (sk-instance-rehazard! $hash $fold $kb)))
      ($_other ()))))

(: sk-instance-rehazard! (-[det]-> Number SkeletonKey Atom Atom))
(= (sk-instance-rehazard! $hash $fold $kb)
   (case (collapse (once (match &ctx_sk_instance_tally ($hash $stored (instance-regimes $hazard $_next $_pos $_neg))
            (if (=alpha $stored $fold) $hazard (empty))))) (
      ((cons $hazard $_rest)
         (if (== $hazard (instance-hazard (brand KB $kb) $fold)) ()
            (ledger-reset-regime! $hash $fold)))
      (() ()))))

;; An item's place in its pass. A query computes the rows within the free
;; depth first, by creation; then the rows that spend its allowance, nearest a
;; root first and by creation within a depth; then the fold checks. So within
;; a pass the allowance goes to the rows nearest a root, whatever order the
;; search created them in. A forward run, whose rows all spend its units,
;; computes them by creation. Creation numbers stay below 10^12, and the fold
;; checks come after every row.
(: sk-item-order (-[det]-> SkeletonItem Number))
(= (sk-item-order (sk-row-item $seq $khash $key $_rhash $_row))
   (let $depth (sk-need-depth $khash $key)
      (if (if (== (search-id-value sk_forward_run) 1) true (<= $depth (sk-evaluation-free-depth))) $seq
         (+ (* $depth 1000000000000) $seq))))
(= (sk-item-order (sk-fold-check $_hash $_fold)) (sk-check-seq))

(: sk-queued-new? (-[det]-> Number Number Number Bool))
(= (sk-queued-new? $pass $khash $rhash)
   (if (space-row-present? &ctx_sk_queued ($pass $khash $rhash)) false
      (let $_queued (context-add! &sk_queued ($pass $khash $rhash)) true)))

;; A row is queued by its key and row hashes, a fold check by its fold's hash.
(: sk-queue-new? (-[det]-> Number SkeletonItem Bool))
(= (sk-queue-new? $pass (sk-row-item $_seq $khash $_key $rhash $_row)) (sk-queued-new? $pass $khash $rhash))
(= (sk-queue-new? $pass (sk-fold-check $hash $_fold)) (sk-queued-new? $pass $hash -1))

;; Every fact premise on the key asks for an open pattern.
(: sk-reads-open? (-[det]-> SkeletonKey Atom SkPattern Bool))
(= (sk-reads-open? $key $open $premise)
   (if $open
      (case $premise (
         (($type $kbctx $proof $tv)
            (if (=alpha (sk-key $type $kbctx) $key) (if (is-var $proof) (is-var $tv) false) true))
         ($_cpu true)))
      false))

;; A reader whose own key the new view depends on does not admit it, unless it
;; reads the key closed: a rule application of a complete statement reading a
;; complete one evaluates the key's rows again, whatever their views depend
;; on. When the key's open merged value did not change, a reader outside its
;; dependencies that reads it openly gets that same value.
(: sk-reads-closed? (-[det]-> SkeletonKey SkeletonRow Bool))
(= (sk-reads-closed? $key (sk-row $_ident ($rtype $rkbctx $rproof $_rtv) $_premises $_seq))
   (case $key (
      ((sk-key $type $kbctx)
         (if (complete-statement? $type $kbctx)
            (if (derivation-proof? $rtype $rproof) (complete-statement? $rtype $rkbctx) false)
            false))
      ($_fold false))))

(: sk-reader-affected? (-[semidet]-> SkeletonKey SkeletonChange SkeletonItem Bool))
(= (sk-reader-affected? $key $change (sk-row-item $_seq $khash $_rkey $_rhash (sk-row $ident $concl $premises $s)))
   (case $change (
      ((sk-outside-change $_causes $_deps) true)
      ((sk-view-change $deps $_causes)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s)) true))
      ((sk-value-same $deps $merged-deps $_causes)
         (if (deps-has? $deps $khash) (sk-reads-closed? $key (sk-row $ident $concl $premises $s))
            (if (deps-has? $merged-deps $khash) true
               (if (fold-semidet (sk-reads-open? $key) true $premises) false true)))))))

;; A reader after the item that changed its input, in the pass's order, is
;; still ahead in this pass; an earlier one waits for the next.
(: sk-schedule-reader
   (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonItem SkeletonWork))
(= (sk-schedule-reader $pass $order $key $change (sk-work $todo $next) $item)
   (if (if (sk-item-needed? $item) false (if (sk-determined-row? $item) false (let $_stale (sk-mark-stale! $item) true)))
      (sk-work $todo $next)
   (if (let $_forced
          (case $change (
             ((sk-outside-change $causes $_deps) (sk-force! $causes $item))
             ($_view ())))
          (sk-reader-affected? $key $change $item))
      (let* (($at (sk-item-order $item)) ($later (> $at $order)))
         (if (sk-queue-new? (if $later $pass (+ $pass 1)) $item)
            (if $later (sk-work (add_to_heap $todo $at $item) $next) (sk-work $todo (add_to_heap $next $at $item)))
            (sk-work $todo $next)))
      (sk-work $todo $next))))

;; A changed key schedules the rows it affects. A fold or group over it is
;; recomputed when next read, and all of its readers are scheduled.
(: sk-key-changed (-[semidet]-> Number Number SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-key-changed $pass $order $change $work $key)
   (if (context-propagate? $key)
   (let* (($hash (index-hash $key))
          ($_mining (case $change (
             ((sk-value-same $_deps $_merged-deps $_causes) ())
             ($_changed (hm-screen-changed! $hash $key)))))
          ($folds
             (collapse (match &sk_use ($hash $stored $fold)
                (if (=alpha $stored $key) $fold (empty)))))
          ($scheduled (fold-semidet (sk-schedule-reader $pass $order $key $change) $work (sk-readers $key))))
      (fold-semidet (sk-fold-changed $pass $order $key $change) $scheduled $folds)) $work))

;; A member change of a fold that was read queues the fold's check at the end
;; of the pass, unless the member's new view depends on the fold, which the fold
;; does not admit; so the members changed in one pass recompute it once; until
;; then its readers read the value it had. A fold nobody read since it last
;; changed is computed when next read. A base-rate fold also records the
;; member to take, unless the change came through the rate itself: a past
;; belief that reads the rate as its prior changes whenever the rate moves, and
;; would otherwise be needed and taken again each time. Nor does a base-rate
;; fold see a member whose open merged value stayed the same outside the
;; fold's dependencies: it takes that value, so there is nothing new to take
;; (a labelled past member gaining a derived view under its fact). An implication
;; instance fold no query needs keeps its view and readers: the evaluation
;; brings it current at its end (sk-instance-checks!). A check queued for this
;; pass is also queued for the next, in case this pass's check already ran.
;; Supported changes start fresh causes; forced changes retain their incoming
;; causes across the fold. Retagging a forced change by the immediate member
;; would either suppress a later refinement or renew feedback around a cycle.
(: sk-check-seq (-[det]-> Number))
(= (sk-check-seq) 1000000000000000000000000)

(: sk-fold-changed (-[semidet]-> Number Number SkeletonKey SkeletonChange SkeletonWork SkeletonKey SkeletonWork))
(= (sk-fold-changed $pass $_seq $member $change (sk-work $todo $next) $fold)
   (let $hash (index-hash $fold)
      (if (case $change (
             ((sk-view-change $deps $_causes) (deps-has? $deps $hash))
             ((sk-value-same $deps $merged-deps $_causes)
                (if (deps-has? $deps $hash) true
                   (if (deps-has? $merged-deps $hash) false
                      (if (sk-instance-fold-key? $fold) false (sk-rate-fold? $fold)))))
             ((sk-outside-change $_causes $deps) (deps-has? $deps $hash))))
         (sk-work $todo $next)
      (let $_rate (sk-rate-dirty! $fold $member)
      (if (not (sk-fold-read? $hash $fold)) (sk-work $todo $next)
      (if (if (sk-needed? $hash $fold) false
             (let $_stale (if (sk-instance-fold-key? $fold) () (sk-stale-fold! $fold)) true))
         (sk-work $todo $next)
         (let* (($incoming (case $change (
                   ((sk-outside-change $propagated $_deps) $propagated)
                   ((sk-view-change $_deps $propagated) $propagated)
                   ((sk-value-same $_deps $_merged $propagated) $propagated))))
                ($causes (if (== $incoming ())
                   (cons (- 0 (+ 2 (next-search-id sk_change_cause))) ()) $incoming))
                ($_pending (foreach-flat (sk-fold-pending! $hash) $causes))
                ($check (sk-fold-check $hash $fold)))
            (if (sk-queue-new? $pass $check) (sk-work (add_to_heap $todo (sk-check-seq) $check) $next)
               (if (sk-queue-new? (+ $pass 1) $check) (sk-work $todo (add_to_heap $next (sk-check-seq) $check))
                  (sk-work $todo $next))))))))))

(: sk-force! (-[det]-> (List Number) SkeletonItem Atom))
(= (sk-force! $causes (sk-row-item $_seq $khash $_key $rhash $_row))
   (if (space-row-present? &ctx_sk_support ($khash $rhash $_deps))
      (sk-force-causes! $khash $rhash $causes)
      ()))
(= (sk-force! $_causes (sk-fold-check $_hash $_fold)) ())

;; A fold check recomputes the fold once for the members that changed since
;; the last one; when its value changed, every reader is forced by those
;; members, in the next pass. A row whose view differs from its latest version stores a new version and
;; changes its key, when it is the row's first view, it was forced, or it
;; brings new support. A forced row also stores a view that differs only in
;; its proof: an outside change such as a completed fold improves provenance.
;; The row's order in the pass places the readers it schedules.
(: sk-compute (-[semidet]-> Number Number SkeletonWork SkeletonItem SkeletonWork))
(= (sk-compute $pass $_order $work (sk-fold-check $hash $fold))
   (let* (($causes (list_to_set (collapse (match &ctx_sk_fold_pending ($hash $member) $member))))
          ($_taken (remove-data-rows! &sk_fold_pending (quote ($hash $member))))
          ($old (sk-latest-view $hash $fold 0)))
      (if (if (== $causes ()) true (if (sk-empty-read? $fold) false (== $old sk-none))) $work
         (let* (($_merged (sk-drop-merged! $fold)))
            (case (sk-fold-views $hash $fold) (
               ((cons (sk-version $_seq $_rhash $new) $_rest)
                  (if (if (sk-same-view? $new $old) (== (sk-view-step-proof $new) (sk-view-step-proof $old)) false)
                     $work
                     (sk-key-changed $pass (sk-check-seq)
                        (sk-outside-change $causes (sk-view-deps-step 0 $new)) $work $fold)))
               (() (sk-key-changed $pass (sk-check-seq) (sk-outside-change $causes 0) $work $fold))))))))
(= (sk-compute $pass $order $work (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_computed (query_metric_increment row-computes))
          ($causes (collapse (match &ctx_sk_forced ($hash $rhash $cause) $cause)))
          ($_taken (remove-data-rows! &sk_forced (quote ($hash $rhash $cause))))
          ($_unpaid (remove-data-rows! &sk_given_pending (quote ($hash $rhash $_cost))))
          ($new (sk-row-view () () $hash $key $rhash $row)))
      (case (sk-commit-result! $hash $key $seq $rhash $causes $new) (
         (sk-uncommitted $work)
         ((sk-committed $change) (sk-key-changed $pass $order $change $work $key))
         ((sk-merge-refresh $deps $incoming $before)
            (sk-key-changed $pass $order (sk-value-change $hash $key $deps $incoming $before) $work $key))))))

;; An unchanged open merged value is known only when it was cached before.
;; Keep a provenance-only refresh's causes without forcing its row readers.
(: sk-value-change (-[semidet]-> Number SkeletonKey Number (List Number) (List SkeletonMerged) SkeletonChange))
(= (sk-value-change $hash $key $deps $causes $before)
   (case $before (
      (() (sk-view-change $deps $causes))
      ((cons (sk-merged $_h $_k $old-deps $old-value) $_rest)
         (case (sk-open-value $hash $key sk-any-filter) (
            ((sk-merged $_h2 $_k2 $new-deps $new-value)
               (if (=alpha $old-value $new-value)
                  (sk-value-same $deps (deps-union $old-deps $new-deps) $causes)
                  (sk-view-change $deps $causes)))))))))

;; Works off the queued rows and returns the last pass. A row a query needs
;; that reads a fold the stale cascade reached meanwhile (the fold went stale
;; over a member left stale and dropped its view) is computed again in a
;; further pass, forced by its own key, whenever that happens: the query reads
;; no value from before what it needs. One left stale for want of allowance
;; meanwhile stays stale. A forward run leaves such rows stale for the
;; query that next needs them, so its cost does not grow with every reader of
;; a fold its new facts change. That includes readers of the keys the run
;; takes: a reader computed early in a wave that a later change in the wave
;; reaches stays stale, so the run can return and store its value from before
;; that change. A query that needs it within the free depth refreshes it
;; first; deeper, it is read like any other stale row.
;; Refreshing those readers in the run (tried Oct 2) changed no StationOps
;; answer and cost forward time growing with the KB (+1% at 10 modules, +9%
;; at 20).
(: sk-work-off! (-[semidet]-> Number SkeletonWork Number))
(= (sk-work-off! $pass (sk-work $todo $next))
   (if (heap-empty? $todo)
      (if (heap-empty? $next)
         (let* (($restale (collapse (match &ctx_sk_restale ($khash $rhash) ($khash $rhash))))
                ($_taken (remove-data-rows! &sk_restale (quote ($khash $rhash))))
                ($again (fold-semidet sk-restale-step (empty_heap) $restale)))
            (if (heap-empty? $again)
               (if (sk-build-wanted!) (sk-work-off! (+ $pass 1) (sk-work (empty_heap) (empty_heap))) $pass)
               (sk-work-off! (+ $pass 1) (sk-work $again (empty_heap)))))
         (sk-work-off! (+ $pass 1) (sk-work $next (empty_heap))))
      (sk-work-pop! $pass $next (heap_pop $todo))))

;; Ordinary reads keep their incumbent. Only this last tier rebuilds a miss;
;; nested reads may rebuild inline inside its bounded evaluation slice.
;; Leave a request in place until the build returns, including on exceptions.
(: sk-build-wanted! (-[semidet]-> Bool))
(= (sk-build-wanted!)
   (let $room (min (search-id-value sk_eval_budget) (search-id-value sk_branch_budget))
      (if (< $room 1) false
         (case (collapse (once (match &ctx_sk_branch_wanted ($slot $hash $key $rhash $exclude)
                  (sk-wanted $slot $hash $key $rhash $exclude)))) (
            (() false)
            ((cons (sk-wanted $slot $hash $key $rhash $exclude) $_rest)
               (let* (($incumbent (chainer-first-or
                                    (chainer-first-or sk-none (sk-branch-values $slot $key $rhash $exclude false))
                                    (sk-branch-values $slot $key $rhash $exclude true)))
                      ($slice (execution-open-slice! $room))
                      ($built (sk-rebuild-view true $hash $key $rhash $exclude))
                      ($_spent (execution-close-slice! $slice branch-slice))
                      ;; Even a cache hit or a structurally impossible read
                      ;; consumes one tier unit, bounding queue bookkeeping.
                      ($_request (sk-finish-branch-request! $slot $hash $key $rhash $exclude))
                      ($_ready
                         (if (not (sk-same-view? $built $incumbent))
                            (let* (($cause (- 0 (+ 2 (next-search-id sk_change_cause))))
                                   ($_readers (collapse (fold-semidet (sk-branch-ready-step $cause $exclude $key) ()
                               (append-flat (append-flat (sk-readers $key)
                                  (collapse (match &sk_use ($hash $member $fold)
                                     (if (=alpha $member $key)
                                        (if (sk-instance-fold-key? $fold) (empty)
                                           (if (sk-rate-fold? $fold) (sk-fold-check (index-hash $fold) $fold) (empty)))
                                        (empty)))))
                                  (collapse (match &ctx_sk_stale_reader ($hash $stored $reader-hash $reader-row)
                                     (if (=alpha $stored $key) (sk-row-item-at $reader-hash $reader-row) (empty))))))))) ())
                            ())))
                  true)))))))

(: sk-branch-ready-step (-[semidet]-> Number (List Number) SkeletonKey Atom SkeletonItem Atom))
(= (sk-branch-ready-step $cause $exclude $_member $_acc (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $created)))
   ;; A row always excludes its own key. Readers in other exclusion contexts
   ;; keep their own requests; this arrival must not force them as well.
   (if (stored-list-member? $hash $exclude)
      (let $_requested
         (if (== (search-id-value sk_forward_run) 1)
            (if (sk-needed? $hash $key) () (let $_needed (add-atom &sk_needed ($hash $key 0)) ())) ())
         (if (sk-needed? $hash $key)
            (let* (($_forced (sk-force! (cons $cause ()) (sk-row-item $seq $hash $key $rhash (sk-row $ident $concl $premises $created))))
                   ($_linked (if (space-row-present? &ctx_sk_stale ($hash $rhash))
                                (sk-relink-row! $hash $rhash $premises) ()))
                   ($_ready (if (space-row-present? &ctx_sk_restale ($hash $rhash)) ()
                                (let $_row (context-add! &sk_restale ($hash $rhash)) ()))))
               ())
            ()))
      ()))
;; A member's fold-excluded branch can arrive after its initial take failed.
;; Retake it through the ordinary fold read and wake that fold's consumers.
(= (sk-branch-ready-step $_cause $exclude $member $_acc (sk-fold-check $hash $fold))
   (if (stored-list-member? $hash $exclude)
      (let $_dirty (sk-rate-dirty! $fold $member) (sk-stale-fold! $fold)) ()))

(: sk-restale-step (-[semidet]-> (Heap SkeletonItem) (Number Number) (Heap SkeletonItem)))
(= (sk-restale-step $todo ($khash $rhash))
   (if (space-row-present? &ctx_sk_stale ($khash $rhash)) $todo
      (case (collapse (once (sk-row-item-at $khash $rhash))) (
         ((cons $item $_rest) (let $_forced (sk-force! (cons $khash ()) $item) (add_to_heap $todo (sk-item-order $item) $item)))
         (() $todo)))))

(: sk-work-pop!
   (-[semidet]-> Number (Heap SkeletonItem) (Number SkeletonItem (Heap SkeletonItem)) Number))
;; Each row commits to its one result, so the loop leaves no choice points and
;; runs in constant stack however many rows it computes. An item no query needs
;; is in the work only as a determined row (sk-seed-new, sk-schedule-reader),
;; which costs nothing; a determined row a query needs is computed even when
;; the allowance cannot pay for it.
(= (sk-work-pop! $pass $next ($order $item $rest))
   (if (if (sk-item-needed? $item)
          (if (sk-near-root-reserve-take! $item) true
             (if (sk-take! sk_eval_budget
                    (case $item (((sk-row-item $_seq $_khash (sk-key $type $_kbctx) $_rhash $_row) (term-cost $type)) ($_fold-check 1))))
                true
                (sk-determined-row? $item)))
          true)
      (sk-work-off! $pass (once (sk-compute $pass $order (sk-work $rest $next) $item)))
      (let* (($_unpaid (query_metric_increment rows-unpaid)) ($_stale (sk-mark-stale! $item)))
         (sk-work-off! $pass (sk-work $rest $next)))))

;; A query computes the rows and folds within two steps of a root from a
;; reserve that its need fills with a fixed number of computations for each
;; one it reaches there, shared among them: rows read one another through
;; inverted rules, each change schedules its readers again, and a fold is
;; checked again when more members change, so near a root an evaluation is
;; bounded by the size of what its roots read, not by the passes its cycles
;; take. What the reserve cannot pay for, and every deeper row, spends the
;; allowance; what neither can pay for is left stale, as if no query needed
;; it, and a later query that reads it recomputes it from its inputs then. A
;; row of a large key spends more of the allowance (term-cost); a fold, whose
;; arguments do not grow with recursion, one.
;; Creation order is kept, so an allowance that covers everything computes
;; what a query without one would. A forward run has no reserve.
(: sk-near-root-reserve-take! (-[det]-> SkeletonItem Bool))
(= (sk-near-root-reserve-take! (sk-row-item $_seq $khash $key $_rhash $_row))
   (if (<= (sk-need-depth $khash $key) (sk-evaluation-free-depth)) (sk-take! sk_near_reserve 1) false))
(= (sk-near-root-reserve-take! (sk-fold-check $hash $fold))
   (if (<= (sk-need-depth $hash $fold) (sk-evaluation-free-depth)) (sk-take! sk_near_reserve 1) false))

;; Keys changed outside evaluation: a fold or group key recomputes when next
;; read, and every changed key's readers are scheduled. A stored fact may make
;; a stale reader determined: it rejoins the key's readers, so it is computed.
(: sk-dirty-seed (-[semidet]-> Number SkeletonWork SkeletonKey SkeletonWork))
(= (sk-dirty-seed $pass $work $key)
   (let* (($hash (index-hash $key))
          ($_branches (sk-invalidate-branches! $key))
          ($_view
             (case $key (
                ((sk-key $_type $_kbctx)
                   (fold-semidet sk-relink-determined-step ()
                      (collapse (match &ctx_sk_stale_reader ($hash $stored $khash $rhash)
                         (if (=alpha $stored $key) (sk-row-item-at $khash $rhash) (empty))))))
                ($_fold (sk-drop-fold-view! $key)))))
          ($_merged (sk-drop-merged! $key)))
      (sk-key-changed $pass -1 (sk-outside-change (cons $hash ()) 0) $work $key)))

(: sk-relink-determined-step (-[semidet]-> Atom SkeletonItem Atom))
(= (sk-relink-determined-step $_acc (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $s)))
   (if (sk-determined-row? (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $s)))
      (sk-relink-row! $khash $rhash $premises)
      ()))

;; A stale row within the depth computed in full rejoins its keys' readers and
;; is recomputed by the evaluation, and so does a stale row at any depth that
;; has no value yet: a row a forward run created but could not pay for. A
;; deeper stale row keeps its value and stays
;; out of the change path: only a need that reaches it that closely, such as a
;; query asking for it, brings it current. So a change below a long chain, such
;; as a base rate every past belief read, costs once per stale row and never
;; recomputes the history no one asked for.
;;
;; Below that depth the need goes on only through rows never computed or
;; waiting to be conditioned. A current row's inputs are current, since every
;; change reaches the readers of what changed, and a stale one is not brought
;; current, so there is nothing under either to recompute. Rows never computed
;; are taken nearest a root first, as the evaluation computes them; those of
;; large statements spend what their size costs beyond a row's (term-cost)
;; from as much as the allowance can compute (sk_need_budget). A recursive rule
;; that builds ever larger rows faster than they are computed, such as a base
;; rate's members through (Num $x) → (Num (succ $x)), would otherwise make
;; every need walk the whole backlog; a need through rows of ordinary size,
;; whose walk also takes base rates' changed members, is not cut.
;;
;; A stale row brought current leaves the stale set and rejoins its keys'
;; readers.
(: sk-relink-row! (-[semidet]-> Number Number (List SkPattern) Atom))
(= (sk-relink-row! $khash $rhash $premises)
   (let* (($_fresh (context-remove! &sk_stale ($khash $rhash)))
          ($keys (fold-semidet sk-direct-key-step () $premises))
          ($_unmarked (fold-semidet (sk-drop-stale-reader! $khash $rhash) () $keys))
          ($_linked (fold-semidet (sk-add-reader! $khash $rhash) () $keys)))
      ()))

;; A row cannot contribute when every structural reader excludes one of its
;; mandatory statement inputs, or a key the view it keeps depends on: its
;; conditioned view reads the same views of its inputs, and each reader reads
;; the row again under its own exclusions. A fold or group using the key reads
;; it; a connective's evidence read (sk-evidence-view) excludes the parts and
;; the consequence. So a compound's producer row whose part has a completion
;; from what the rule reading the compound concludes does not condition around
;; that loop for its reader, which refuses that view (#142; fuzz s22000086:
;; 7,966 conditioned evaluations otherwise, none on master, whose rule read the
;; parts itself). Keep the pending claim: a new reader or root revokes this
;; proof of unreadability on the next need/payment round.
(: sk-readable-row? (-[semidet]-> Number SkeletonKey Number (List SkPattern) Bool))
;; A forward run exposes taken values too, beyond its depth-zero reader keys.
;; Conservatively keep all its claims live instead of pruning a public value.
(= (sk-readable-row? $hash $key $rhash $premises)
   (if (if (== (search-id-value sk_forward_run) 1) true (== (sk-need-depth $hash $key) 0)) true
         (let* (($inputs (fold-semidet sk-direct-key-step (cons $key ()) $premises))
                ($input-deps (deps-join (collapse
                   (let (sk-key $type $scope) (superpose $inputs)
                      (deps-key (index-hash (sk-key $type $scope)))))))
                ($mandatory (case (sk-latest-view $hash $key $rhash) (
                   ((sk-val $_fact $_ev $view-deps) (deps-union $input-deps $view-deps))
                   ($_none $input-deps))))
                ($used (not (== (collapse (once (match &sk_use ($hash $member $use)
                   (if (=alpha $member $key)
                      (case $use (
                         ((sk-evidence $args) (if (deps-meet? (sk-evidence-apart $args ()) $mandatory) (empty) true))
                         ($_fold true)))
                      (empty))))) ())))
                ($readers (append-flat
                   (collapse (match &ctx_sk_reader ($hash $read $kh $rh)
                      (if (=alpha $read $key) ($kh $rh) (empty))))
                   (collapse (match &ctx_sk_stale_reader ($hash $stale $sh $sr)
                      (if (=alpha $stale $key) ($sh $sr) (empty)))))))
            (if $used true
               (not (== (collapse (once
                  (let ($reader-hash $reader-row) (superpose $readers)
                     (match &sk_row ($reader-hash $reader-key $reader-row
                              (sk-row $_ident ($_type $_ctx $proof $_tv) $_premises $_seq))
                        (if (deps-meet? (sk-row-exclusions $reader-hash $reader-key $proof) $mandatory)
                           (empty) true))))) ()))))))

(: sk-need-row! (-[semidet]-> Number SkeletonNeed SkeletonItem SkeletonNeed))
(= (sk-need-row! $depth (sk-need-next $next $members) (sk-row-item $_seq $khash $key $rhash (sk-row (sk-ident $rule $_keys $_key) $_concl $premises $_s)))
   (if (rule-live? $rule)
   (let* (($_reserve (sk-reserve-near! (- $depth 1)))
          ($near (<= $depth (+ (sk-evaluation-free-depth) 1)))
          ($world (space-row-present? &sk_world_stale ($khash $rhash)))
          ($_world-needed (if $world
             (if (space-row-present? &sk_world_done ($khash $rhash)) ()
                (let $_needed (add-atom &sk_world_done ($khash $rhash)) ())) ()))
          (($latest $invalid)
             (case (collapse (once (match &ctx_sk_latest ($khash $stored (sk-version $_old-seq $rhash $view))
                       (if (=alpha $stored $key) (if (sk-live-view? $view) ($view false) (sk-none true)) (empty))))) (
                ((cons $state $_rest) $state)
                (() (sk-none false)))))
          ($unseen
             (if (== $latest sk-none)
                (if $near true
                   (case $key (((sk-key $type $_kbctx)
                      (let $extra (- (term-cost $type) 1)
                         (if (== $extra 0) true (sk-take! sk_need_budget $extra)))))))
                false))
          ($refresh
             (if (if $unseen true (if $near true $world))
                (if $invalid true (space-row-present? &ctx_sk_stale ($khash $rhash)))
                false))
          ($_forced (if (if $refresh $invalid false) (context-add! &sk_forced ($khash $rhash -1)) true))
          ($_refreshed
             (if $refresh
                (let $_relinked (sk-relink-row! $khash $rhash $premises) (context-add! &sk_refresh ($khash $rhash)))
                ())))
      (if (if (space-row-present? &ctx_sk_given_pending ($khash $rhash $_cost))
                (sk-readable-row? $khash $key $rhash $premises)
                (if $world true (if $refresh true
                   (if (<= $depth (sk-evaluation-free-depth)) true $unseen))))
         (fold-semidet (sk-need-premise-step true $depth) (sk-need-next $next $members) $premises)
         (fold-semidet (sk-need-premise-step false $depth) (sk-need-next $next $members) $premises)))
   (let $_removed (sk-drop-row! $khash $key $rhash (sk-row (sk-ident $rule $_keys $_key) $_concl $premises $_s))
      (sk-need-next $next $members))))

;; A row's premise keys are needed one level further, at `$depth`, when the
;; row passes its need on (`$all`). A compound key is the row's own reading of
;; the compound's parts (#142), so a needed row always needs it, at the row's
;; key's depth, and its producer rows with the row: they are as near a root as
;; the reading row, the parts as near as when the rule read them, and a change
;; of a part reaches the reading row through them. A stale producer row one
;; level further was not brought current, and its reader kept the view of an
;; earlier value of the part, in MAIN (a late fact of a part: Q at 0.6306 for
;; 0.6524) and in an Assuming world, which relinks only the rows of keys near
;; a root (SupplyNet stage 4: an assumed stock read as unfounded). The key of
;; a root's row is needed at depth 1, which is as near: depth 0 makes a root,
;; whose merge a query reads and conditions as its answer.
(: sk-need-premise-step (-[semidet]-> Bool Number SkeletonNeed SkPattern SkeletonNeed))
(= (sk-need-premise-step $all $depth (sk-need-next $next $members) $premise)
   (case (sk-direct-key-step () $premise) (
      ((cons (sk-key $type $kbctx) ())
         (let* (($key (sk-key $type $kbctx)) ($hash (index-hash $key)))
            (if (compound-source? (brand Statement $type))
               (if (sk-needed? $hash $key) (sk-need-next $next $members)
                  (let* (($at (max (- $depth 1) 1))
                         ($_new (add-atom &sk_needed ($hash $key $at)))
                         ($_touched (sk-touch-key! $hash $key)))
                     (sk-need-below! (- $depth 1) $hash $key (sk-need-next $next $members))))
               (if $all (sk-need-next (cons $key $next) $members) (sk-need-next $next $members)))))
      ($keys (if $all (sk-need-next (append-flat $keys $next) $members) (sk-need-next $next $members))))))

;; The need from a query's roots, or from the keys a forward wave takes.
(: sk-need-roots! (-[semidet]-> (List SkeletonKey) Atom))
(= (sk-need-roots! $keys)
   (let $_budget (change-state! sk_need_budget (search-id-value sk_eval_budget)) (sk-need-level! 0 $keys ())))

(: sk-need-level! (-[semidet]-> Number (List SkeletonKey) (List SkeletonKey) Atom))
(= (sk-need-level! $depth $keys $members)
   (if (== $keys ())
      (if (== $members ()) () (sk-need-level! $depth $members ()))
      (case (fold-semidet (sk-need! $depth) (sk-need-next () $members) $keys) (
         ((sk-need-next $next $later) (sk-need-level! (+ $depth 1) (fold-semidet sk-cons-step () $next) $later))))))

;; --- Demand -----------------------------------------------------------------
;; A query brings current only what its roots read: their keys, the premise
;; keys of those keys' rows, and the members of the folds and groups among
;; them. A row outside that set whose input changes is marked stale instead of
;; computed, and so is everything reading it, once (what the query needs once
;; it has read its answers); a later query that reads it again recomputes it. A stale row leaves
;; the reader lists of the keys it reads until then, so a change walks only
;; readers that are current, and earlier queries' rows cost nothing per query
;; or per change.

;; Signatures of the mutually recursive functions below.
(: sk-need! (-[semidet]-> Number SkeletonNeed SkeletonKey SkeletonNeed))

(= (sk-need! $depth $need $key)
   (let $hash (index-hash $key)
      (if (sk-needed? $hash $key) $need
         (let* (($_new (add-atom &sk_needed ($hash $key $depth)))
                ($_touched (sk-touch-key! $hash $key)))
            (sk-need-below! $depth $hash $key $need)))))

;; What a needed key reads: its rows' premise keys, or the members of a fold
;; or group; a base-rate fold takes its changed members.
(: sk-need-below! (-[semidet]-> Number Number SkeletonKey SkeletonNeed SkeletonNeed))
(= (sk-need-below! $depth $hash $key (sk-need-next $next $members))
   (case $key (
      ((sk-key $_type $_kbctx)
         (fold-semidet (sk-need-row! (+ $depth 1)) (sk-need-next $next $members)
            (collapse (match &sk_row ($hash $stored $rhash (sk-row $ident $concl $premises $seq))
               (if (=alpha $stored $key)
                  (sk-row-item $seq $hash $stored $rhash (sk-row $ident $concl $premises $seq))
                  (empty))))))
      ((sk-fold $args)
         (let $_reserve (sk-reserve-near! $depth)
         (if (sk-rate-fold? $key)
            (let $changed (sk-rate-changed $hash $key)
               (if (== $changed ()) (sk-need-next $next $members)
                  (let* (($_taken (sk-rate-take! $hash (the ScalarFoldSpec $args)))
                         ($_dirty (sk-mark-dirty! $key)))
                     (sk-need-next $next (fold-semidet sk-cons-step $members $changed)))))
            (case (sk-fold-node-member (CPU FoldAllCompiled $args $_result)) (
               ((cons $member $_rest) (sk-need-next (fold-semidet sk-cons-step $next (sk-answers $member)) $members))
               (() (sk-need-next $next $members)))))))
      ;; A compound's prior reads its inputs as its reader would read them.
      ((sk-prior $rate-args)
         (fold-semidet (sk-need! $depth) (sk-need-next $next $members) (sk-prior-inputs (compound-rate-goals $rate-args false $_rate))))
      ;; Not K's producer's rows, whose views it excludes.
      ;; A node row's sibling key is needed one level further, its rows apart from
      ;; the target as these: its value changes reach the read.
      ((sk-evidence $evidence-args)
         (let $_sibling (case $evidence-args (
                           (($_ekb $etype (cavity $_compound $_target) $ekbctx)
                              (let* (($ekey (sk-key $etype $ekbctx)) ($ehash (index-hash $ekey)) ($at (+ $depth 1)))
                                 (if (sk-needed? $ehash $ekey) () (add-atom &sk_needed ($ehash $ekey $at)))))
                           ($_completion ())))
            (fold-semidet (sk-need-row! (+ $depth 1)) (sk-need-next $next $members) (sk-evidence-rows $evidence-args))))
      ((sk-group $group-args)
         (let $_reserve (sk-reserve-near! $depth)
            (case (sk-group-members $key $group-args) (
               ((sk-group-found $_member $found) (sk-need-next (fold-semidet sk-cons-step $next $found) $members))
               (sk-group-missing (sk-need-next $next $members)))))))))

(: sk-root-keys-step (-[semidet]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-root-keys-step $keys $goal) (append-flat $keys (sk-root-keys $goal)))

;; Release branch-only holds whose exact exclusion read settled. An empty
;; branch settles too; an invalidated or unfinished branch still holds its
;; consumer. Ordinary stale-input debt always survives branch settlement.
;; Decide before the stale cascade invalidates other settled branches.
(: sk-stale-held! (-[semidet]-> Atom))
(= (sk-stale-held!)
   (let* (($_released (change-state! sk_holding 0))
          ($held
             (collapse (match &ctx_sk_held ($khash $rhash $reason)
                (if (case $reason (
                       (sk-stale-input true)
                       ((sk-branch-hold $slot $key $row $exclude)
                          (== (sk-branch-values $slot $key $row $exclude true) ()))))
                   (sk-row-item-at $khash $rhash) (empty)))))
          ($_taken (remove-data-rows! &sk_held (quote ($hkhash $hrhash $_reason))))
          ($_branches (remove-data-rows! &sk_branch_hold (quote ($_slot $_hash $_key $_row $_exclude)))))
      (foreach-flat sk-mark-stale! $held)))

(: sk-stale-world-row-step (-[det]-> (List SkeletonKey) SkeletonItem (List SkeletonKey)))
(= (sk-stale-world-row-step $keys (sk-row-item $seq $hash $key $rhash $row))
   (let* (($_marked (if (space-row-present? &sk_world_stale ($hash $rhash)) ()
                      (let $_mark (add-atom &sk_world_stale ($hash $rhash)) ())))
          ($_stale (sk-mark-stale! (sk-row-item $seq $hash $key $rhash $row))))
      (cons $key $keys)))
(= (sk-stale-world-row-step $keys (sk-fold-check $_hash $_fold)) $keys)

;; Follow both current and released reader links. The key set bounds cycles;
;; the work list avoids retaining a recursive frame per downstream row.
(: sk-stale-world-keys! (-[semidet]-> (List SkeletonKey) Atom))
(= (sk-stale-world-keys! ()) ())
(= (sk-stale-world-keys! (cons $key $rest))
   (let $hash (index-hash $key)
      (if (not (== (collapse (once (match &sk_world_seen ($hash $stored)
                  (if (=alpha $stored $key) true (empty))))) ()))
         (sk-stale-world-keys! $rest)
         (let* (($_seen (add-atom &sk_world_seen ($hash $key)))
                ($readers (append-flat (sk-readers $key)
                   (collapse (match &ctx_sk_stale_reader ($hash $input $khash $rhash)
                      (if (=alpha $input $key) (sk-row-item-at $khash $rhash) (empty))))))
                ($owners (fold-semidet sk-stale-world-row-step () $readers))
                ($folds (collapse (match &sk_use ($hash $member $fold)
                   (if (=alpha $member $key) (if (sk-rate-fold? $fold) (empty) $fold) (empty)))))
                ($_folds (foreach-flat sk-stale-fold! $folds)))
            (sk-stale-world-keys! (append-flat $owners (append-flat $folds $rest)))))))

(: sk-invalidate-world! (-[semidet]-> Atom))
(= (sk-invalidate-world!)
   (let* (($changed (collapse (match &sk_world_changed ($hash $key) $key)))
          ($_taken (remove-data-rows! &sk_world_changed (quote ($_hash $_key))))
          ($_stale (sk-stale-world-keys! $changed))
          ($_seen (remove-data-rows! &sk_world_seen (quote ($_shash $_skey)))))
      ()))

(: sk-item-needed? (-[det]-> SkeletonItem Bool))
(= (sk-item-needed? (sk-row-item $_seq $hash $key $_rhash $_row)) (sk-needed? $hash $key))
(= (sk-item-needed? (sk-fold-check $hash $fold)) (sk-needed? $hash $fold))

;; A new row no query needs is left stale, unless it is determined
;; (sk-determined-row?).
(: sk-seed-new (-[det]-> Number (Heap SkeletonItem) SkeletonItem (Heap SkeletonItem)))
(= (sk-seed-new $pass $todo $item)
   (if (if (sk-item-needed? $item) true (sk-determined-row? $item))
      (if (sk-queue-new? $pass $item) (add_to_heap $todo (sk-item-order $item) $item) $todo)
      (let $_stale (sk-mark-stale! $item) $todo)))

;; A row is determined when its rule is deterministic (stated with strength 0
;; or 1 and confidence 1 in every branch: register-rule-evidence!) and its
;; premises are all certain statements, reading no fold or group: its
;; conclusion is certain, as a stored fact is. So it is computed when it is
;; built or its premises change, whoever needs it, at the cost of reading a
;; fact: its key then changes as a stored fact's would, and the tallies and
;; base rates over the key take it (docs/metta/runtime_design_assumptions.md,
;; "Determined rows").
(: sk-determined-row? (-[det]-> SkeletonItem Bool))
(= (sk-determined-row? (sk-row-item $_seq $_khash $_key $_rhash (sk-row $_ident ($_type ($kbid $_ctx $_vars) $proof $_tv) $premises $_s)))
   (if (deterministic-rule? (brand KB $kbid) (rule-evidence-head $proof))
      (fold-flat sk-certain-premise-step true (the (List SkPattern) $premises))
      false))
(= (sk-determined-row? (sk-fold-check $_hash $_fold)) false)

(: sk-certain-premise-step (-[det]-> Bool SkPattern Bool))
(= (sk-certain-premise-step $certain $premise)
   (if $certain
      (case $premise (
         ((CPU $fun $_args $_res) (not (if (== $fun FoldAllCompiled) true (== $fun GroupedFoldAllCompiled))))
         (($type $kbctx $_proof $_tv) (sk-certain? $type (sk-leaf-facts $type $kbctx sk-any-filter)))
         ($_other false)))
      false))

;; MAIN can release held rows before an Assuming world starts. That world
;; borrows the same need depths, but must relink its stale rows near the roots
;; locally before seed changes can reach them. Deeper stale history stays put.
(: sk-refresh-near! (-[det]-> Atom))
(= (sk-refresh-near!)
   (let $_refreshed (collapse (match &sk_needed ($hash $key $depth)
      (if (<= $depth (sk-evaluation-free-depth))
         (match &ctx_sk_stale ($hash $rhash)
            (match &sk_row ($hash $stored $rhash (sk-row $_ident $_concl $premises $_seq))
               (if (=alpha $stored $key)
                  (let $_linked (sk-relink-row! $hash $rhash $premises)
                     (context-add! &sk_refresh ($hash $rhash)))
                  (empty))))
         (empty))))
      ()))

(: sk-evaluate! (-[semidet]-> Atom))
(= (sk-evaluate!)
   (let* (($_hazards (if (take-hazards-changed) (sk-rehazard-tallies!) ()))
          ($_queued (remove-data-rows! &sk_queued (quote ($qpass $qkhash $qrhash))))
          ($_cleared-forced (remove-data-rows! &sk_forced (quote ($khash $rhash $cause))))
          ($_used (sk-force-reset!))
          ($_pending (remove-data-rows! &sk_fold_pending (quote ($fhash $member))))
          ;; an incomplete fold the query needs is checked again: its members
          ;; may have been searched, or found to derive nothing, since
          ($partial
             (collapse (match &ctx_sk_partial ($phash $pfold)
                (if (sk-needed? $phash $pfold)
                   (let $_cause (context-add! &sk_fold_pending ($phash $phash)) (sk-fold-check $phash $pfold))
                   (empty)))))
          ($_granted (remove-data-rows! &sk_given_granted (quote ($khash $rhash))))
          ($_conditioning (remove-data-rows! &sk_conditioning (quote ($chash $crhash))))
          ($_restale (remove-data-rows! &sk_restale (quote ($skhash $srhash))))
          ($_checked (remove-data-rows! &sk_instance_checked (quote ($ihash))))
          ($_root-spent (remove-data-rows! &sk_root_spent (quote ($_hash $_key $_units))))
          ($root-room (search-id-value sk_root_claim_cap))
          ($_wake (collapse (match &sk_needed ($root-hash $root-key 0)
             (match &ctx_sk_root_exhausted ($root-hash $stored-root (sk-root-limit $tried $epoch))
                (if (=alpha $stored-root $root-key)
                   (if (if (< $tried $root-room) true (not (== $epoch (sk-input-epoch $root-key))))
                      (if (sk-root-claim? () $root-hash $root-key) (sk-uncache! $root-hash $root-key) (empty)) (empty))
                   (empty))))))
          ($last (sk-evaluate-pass! 0 $partial))
          ($_roots (sk-read-roots!)))
      (let $_paid (sk-pay-conditions! (+ $last 1))
         (query_metric_set conditions-unpaid
            (+ (length (collapse (match &sk_needed ($dh $dk 0)
                  (match &ctx_sk_root_exhausted ($dh $stored-debt $_cap)
                     (if (=alpha $stored-debt $dk)
                        (if (sk-root-claim? () $dh $dk)
                           (if (space-row-present? &ctx_sk_given_pending ($dh -1 $_pending-cost)) (empty) true)
                           (empty)) (empty))))))
               (length (collapse (match &ctx_sk_given_pending ($ph $pr $_cost)
               (if (== $pr -1)
                  (match &sk_keys ($ph $pk) (if (sk-needed? $ph $pk) true (empty)))
                  (match &sk_row ($ph $pk $pr (sk-row $_pi $_pc $pp $_ps))
                     (if (sk-needed? $ph $pk) (if (sk-readable-row? $ph $pk $pr $pp) true (empty)) (empty))))))))))))

;; A pass works off the rows never evaluated, the readers of the keys changed
;; outside evaluation, the stale rows a need brought current (forced by their
;; own keys) and the items given. Then the implication instance folds whose
;; members changed are brought current, in further passes, and the last pass
;; is returned.
(: sk-evaluate-pass! (-[semidet]-> Number (List SkeletonItem) Number))
(= (sk-evaluate-pass! $pass $items)
   (let* (($new (collapse (match &ctx_sk_new (sk-row-item $seq $hash $key $rhash $row)
             (sk-row-item $seq $hash $key $rhash $row))))
          ($_new (remove-data-rows! &sk_new (quote (sk-row-item $nseq $nhash $nkey $nrhash $nrow))))
          ($dirty (collapse (match &ctx_sk_dirty ($dhash $dkey) $dkey)))
          ($_dirty (remove-data-rows! &sk_dirty (quote ($ddhash $ddkey))))
          ($refresh
             (collapse (match &ctx_sk_refresh ($khash $rhash)
                (let* (($_taken (context-remove! &sk_refresh ($khash $rhash)))
                       ($item (sk-row-item-at $khash $rhash))
                       ($_forced (sk-force! (cons $khash ()) $item)))
                   $item))))
          ($seeded
             (fold-semidet (sk-dirty-seed $pass)
                (sk-work (fold-semidet (sk-seed-new $pass) (empty_heap) (append-flat $new (append-flat $refresh $items)))
                   (empty_heap))
                $dirty))
          ($last (sk-work-off! $pass $seeded)))
      (case (sk-instance-checks!) ((() $last) ($checks (sk-evaluate-pass! (+ $last 1) $checks))))))

;; An evaluation brings current every implication instance fold that rows read,
;; has a view and has members still to take, with the keys reading it, a refined rule's
;; truth above all, whoever needs them: those keys are needed as roots are, the
;; members to take beside them, and the fold is checked once the members are
;; computed. So a new instance moves its rule's truth, and the search score
;; read from it, at the evaluation after it is stored, without a query asking
;; for the truth, at the cost of the members that changed. A fold nobody read
;; takes all its members when first read. Each fold is brought current once
;; per evaluation; what changes after that, the fold now needed, is checked as
;; any needed fold is, and a member whose rows the evaluation could not compute
;; waits for the next one.
(: sk-instance-checks! (-[semidet]-> (List SkeletonItem)))
(= (sk-instance-checks!)
   (fold-semidet sk-instance-check-step ()
      (collapse (match &ctx_sk_instance_changed ($hash $fold)
         (if (space-row-present? &ctx_sk_instance_checked ($hash)) (empty)
            (let* (($_taken (ledger-take-change! $hash $fold))
                   ($_checked (context-add! &sk_instance_checked ($hash))))
               ($hash $fold)))))))

(: sk-fold-reader-key-step (-[det]-> (List SkeletonKey) (Number Number) (List SkeletonKey)))
(= (sk-fold-reader-key-step $keys ($khash $rhash))
   (append-flat (collapse (match &sk_row ($khash $key $rhash $_row) $key)) $keys))

(: sk-instance-check-step (-[semidet]-> (List SkeletonItem) (Number SkeletonKey) (List SkeletonItem)))
(= (sk-instance-check-step $checks ($hash $fold))
   (let* (($members (sk-rate-changed $hash $fold))
          ($readers
             (collapse (superpose (
                (match &ctx_sk_reader ($hash $stored-r $khash $rhash) (if (=alpha $stored-r $fold) ($khash $rhash) (empty)))
                (match &ctx_sk_stale_reader ($hash $stored-s $skhash $srhash) (if (=alpha $stored-s $fold) ($skhash $srhash) (empty))))))))
      (if (if (== $members ()) true (if (== $readers ()) true (== (sk-latest-view $hash $fold 0) sk-none))) $checks
         (let* (($_readers (sk-need-closer! 0 (alpha_unique_keys (fold-flat sk-fold-reader-key-step () $readers))))
                ($_fold (sk-need-closer! 1 (cons $fold ())))
                ($_members (sk-need-closer! 2 $members))
                ($_causes (foreach-flat (sk-fold-pending! $hash) (map-flat index-hash $members))))
            (cons (sk-fold-check $hash $fold) $checks)))))

;; Keys needed again at a depth closer to a root than they were, so their
;; rows are computed in full and their stale rows brought current.
(: sk-unneed-deeper! (-[det]-> Number Atom SkeletonKey Atom))
(= (sk-unneed-deeper! $depth $_acc $key)
   (let* (($hash (index-hash $key))
          ($_dropped
             (collapse (match &sk_needed ($hash $stored $was)
                (if (=alpha $stored $key) (if (> $was $depth) (remove-atom &sk_needed ($hash $stored $was)) (empty)) (empty))))))
      ()))

(: sk-need-closer! (-[semidet]-> Number (List SkeletonKey) Atom))
(= (sk-need-closer! $depth $keys)
   (let $_unneeded (fold-flat (sk-unneed-deeper! $depth) () $keys) (sk-need-level! $depth $keys ())))

(: sk-fold-pending! (-[det]-> Number Number Atom))
(= (sk-fold-pending! $hash $cause) (context-add! &sk_fold_pending ($hash $cause)))

(: sk-pay-conditions! (-[semidet]-> Number Atom))
(= (sk-pay-conditions! $pass)
   (case (sk-order-claims
            (append-flat
               (collapse (match &ctx_sk_given_pending ($khash $rhash $cost)
                  (match &sk_row ($khash $key $rhash (sk-row $ident $concl $premises $seq))
                     (if (if (sk-needed? $khash $key)
                              (if (sk-readable-row? $khash $key $rhash $premises)
                                 (not (space-row-present? &ctx_sk_given_granted ($khash $rhash))) false) false)
                        (sk-claim (sk-need-depth $khash $key) $cost $seq
                           (sk-row-waiting (sk-row-item $seq $khash $key $rhash (sk-row $ident $concl $premises $seq))))
                        (empty)))))
               (collapse (match &ctx_sk_given_pending ($khash -1 $cost)
                  (match &sk_keys ($khash $key)
                     (if (if (sk-needed? $khash $key) (not (space-row-present? &ctx_sk_given_granted ($khash -1))) false)
                        (sk-claim (sk-need-depth $khash $key) $cost -1 (sk-key-waiting $khash $key))
                        (empty))))))) (
      (() (sk-finish-branches! $pass))
      ((cons (sk-claim $_depth $_claim-cost $_seq $waiting) $_rest)
         (if (< (search-id-value sk_eval_budget) 1) (sk-finish-branches! $pass)
            (let $last (sk-pay! $pass $waiting) (sk-pay-conditions! (+ $last 1))))))))

;; Root merges and conditioning can discover misses after the row heap ends.
;; Give those requests the same last tier, within its remaining fixed share.
(: sk-finish-branches! (-[semidet]-> Number Atom))
(= (sk-finish-branches! $pass)
   (if (sk-build-wanted!)
      (let* (($last (sk-work-off! $pass (sk-work (empty_heap) (empty_heap))))
             ($_roots (sk-read-roots!)))
         (sk-pay-conditions! (+ $last 1)))
      ()))

(: sk-pay! (-[semidet]-> Number SkeletonWaiting Number))
(= (sk-pay! $pass (sk-row-waiting (sk-row-item $seq $hash $key $rhash $row)))
   (let* (($item (sk-row-item $seq $hash $key $rhash $row))
          ($_taken (remove-data-rows! &sk_given_pending (quote ($hash $rhash $_was))))
          ($_granted (context-add! &sk_given_granted ($hash $rhash)))
          ($_forced (sk-force! (cons $hash ()) $item)))
      (sk-work-off! $pass (sk-work (add_to_heap (empty_heap) (sk-item-order $item) $item) (empty_heap)))))
;; A paid key drops its merged value, which its readers then read conditioned.
;; Branches pay their own conditioning; this grant changes no branch input.
(= (sk-pay! $pass (sk-key-waiting $hash $key))
   (let* (($_granted (context-add! &sk_given_granted ($hash -1)))
          ($_merged (sk-drop-merged! $key)))
      (sk-work-off! $pass
         (sk-key-changed $pass -1 (sk-outside-change (cons $hash ()) 0) (sk-work (empty_heap) (empty_heap)) $key))))

;; The roots' merged values are read before conditions are paid, so a root
;; whose views overlap is conditioned in its own query.
(: sk-read-roots! (-[semidet]-> Atom))
(= (sk-read-roots!)
   (let $_read
         (collapse (match &sk_needed ($hash $key 0)
            (case $key (
               ((sk-key $_type $_kbctx) (sk-open-value $hash $key sk-any-filter))
               ($_fold (empty))))))
      ()))

;; The keys a root reads, in first-answer order; a ground root reads its own
;; key, answered or not. A root reads the answers of every node of its
;; statement and context, whatever their proof and truth-value patterns: a root
;; whose pattern is new has no answers of its own before it is searched. Its
;; stored facts cost no expansion, as for any premise.
(: sk-root-keys (-[semidet]-> SkPattern (List SkeletonKey)))
(= (sk-root-keys $goal)
   (case $goal (
      ((CPU $fun $args $_res)
         (if (== $fun FoldAllCompiled) (cons (sk-fold $args) ())
            (if (== $fun GroupedFoldAllCompiled) (sk-answers $goal) ())))
      (($type $kbctx $_proof $_tv)
         (let* (($key (sk-key $type $kbctx)) ($hash (index-hash $key)))
         (alpha_unique_keys
            (append-flat
               (collapse (match &sk_answer ($hash ($node-type $node-kbctx $_n-proof $_n-tv) $answer)
                  (if (=alpha (sk-key $node-type $node-kbctx) $key) $answer (empty))))
               (if (== (extract-vars $type) ()) (cons $key ())
                  (collapse (match &kb ($type $kbctx $_stored-proof $_stored-tv) (sk-key $type $kbctx)))))))))))
