;; A rule's expected confidence, computed when the rule was stored; a refined
;; rule's is scaled by what its current truth can add, read from the truth
;; goal's value, or from its axiom until the goal has one.

(: sk-rule-score (-[det]-> Number Number))
(= (sk-rule-score $rule)
   (* (chainer-first-or 1.0 (collapse (once (match rule_expected ($rule $score) $score))))
      (chainer-first-or 1.0 (collapse (once (match &sk_rule_truth ($rule $hash $type $kbctx) (sk-truth-factor $hash $type $kbctx)))))))

(: sk-truth-factor (-[det]-> Number Statement KBContext Number))
(= (sk-truth-factor $hash $type $kbctx)
   (case (collapse (once (match &ctx_sk_truth_factor ($hash $factor) $factor))) (
      ((cons $factor $_rest) $factor)
      (()
         (let* (($factor
                   (case (collapse (once (match &kb ($type $kbctx (rule-axiom $_name) $tv) $tv))) (
                      ((cons $tv $_rest) (rule-truth-factor $tv))
                      (() 1.0))))
                ($_set (sk-set-truth-factor! $hash $factor)))
            $factor)))))

(: discover-application (-[semidet]-> Number SkFact (List SkPattern) SkPattern SkeletonMatch))
(= (discover-application $id $ccls $args $node)
   (let (sk-rule-def $conclusion $premises) (copy_term (sk-rule-def $ccls $args))
      (if (case (copy_term $node) (
             ((CPU $_fun $_args $_res) false)
             (($type $kbctx $_proof $_tv)
                (= $conclusion (assemble-stored-runtime-fact $type $kbctx $_rule-proof $_rule-tv)))))
         (if (chainer-acyclic-term? $conclusion)
            (sk-match $id (contextualize-rule-args $conclusion $premises) $conclusion)
            (empty))
         (empty))))

(: sk-premise-rules-step (-[det]-> Statement KBContext Number (List SkeletonMatch) (List SkeletonMatch)))
(= (sk-premise-rules-step $type $kbctx $prefix $found)
   (append-flat
      (collapse
         (let* ((($_pattern $id $idx) (match &prem_prefix ($prefix $pattern $id $idx) ($pattern $id $idx)))
                (($ccls $prems) (match ccls_index ($ccls $id $prems) ($ccls $prems)))
                ($_rest (nth0 $idx $prems (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))))
            (sk-match $id $prems $ccls)))
      $found))

(: prefilter-premise-blocks? (-[det]-> SkPattern Bool))
;; Binding guards inspect the variables still open after application matching;
;; they must run now, rather than leave a rejected settling row for evaluation.
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (sk-computes-now? $premise)
               (case (collapse (cpu-call 0 $fun $args)) (
                  (() true)
                  ((cons $result $_rest) (if (= $res $result) false true))))
               false))
         ;; Missing facts can arrive after this node has been expanded. Keep
         ;; their ordinary join subscriptions instead of caching an empty search.
         ($_fact false)))))

;; Whether starting an application runs a premise's computation at once: a
;; user computation over bound arguments (or a binding guard).
(: sk-computes-now? (-[det]-> SkPattern Bool))
(= (sk-computes-now? $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (if (contextual-cpu? $fun) true (aggregate-fold-function? $fun)) false
            (if (is-var $fun) false (if (== $fun vars-covered?) true (== (extract-vars $args) ())))))
      ($_fact false))))

;; Durable skeleton construction: goal expansion, partial joins, rows, answers,
;; activation of later facts and rules, and the budgeted search walk.
;;
;; A node is a goal pattern: a fact goal (statement context proof tv) or a fold
;; goal (CPU FoldAllCompiled args result). Expanding a node records its leaf
;; answers and starts one partial join per matching rule. A partial join waits
;; on its next premise node; every answer of that node extends it. A complete
;; join is a row: a rule instance with bound premise keys whose truth value is
;; computed only by evaluation. Rows, answers and waiters are append-only, so a
;; later query continues from the skeleton earlier queries built.

;; Signatures of the mutually recursive functions below.
(: sk-add-answer! (-[semidet]-> SkPattern SkeletonKey Atom))
(: sk-drain! (-[semidet]-> Atom))
(: sk-extend-step (-[semidet]-> SkeletonKey Atom SkeletonWaiter Atom))
(: sk-member-step (-[semidet]-> SkeletonKey Atom SkPattern Atom))
(: sk-advance! (-[semidet]-> SkeletonWaiter Atom))
(: sk-cpu-step (-[semidet]-> SkeletonWaiter Atom $result Atom))
(: sk-wait-on! (-[semidet]-> SkPattern Number SkPattern SkeletonWaiter Atom))
(: sk-extend! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(: sk-complete-row! (-[semidet]-> SkPattern Number SkFact (List SkPattern) (List SkeletonKey) Atom))
(: sk-start-rule-step (-[semidet]-> SkPattern Atom SkeletonMatch Atom))
(: sk-activate-pending! (-[semidet]-> Atom))
(: sk-activate-rules! (-[semidet]-> Atom))
(: sk-activate-facts! (-[semidet]-> Atom))
(: sk-expand! (-[semidet]-> SkPattern Number Number Atom))

;; node, depth, node hash
(datatype SkeletonFrontier (sk-frontier SkPattern Number Number))
;; a node with its hash

(: sk-search! (-[semidet]-> (Heap SkeletonFrontier) Atom))

;; Premises a join still has to prove: facts and folds; formulas are computed.
(: sk-open-premise-step (-[det]-> Number SkPattern Number))
(= (sk-open-premise-step $count $premise)
   (case $premise (
      ((CPU $fun $_args $_res) (if (aggregate-fold-function? $fun) (+ $count 1) $count))
      ($_fact (+ $count 1)))))

;; The value of a join's next premise: what its owner is worth, times the
;; rule's expected confidence, shared among the premises still open.
(: sk-join-score (-[semidet]-> SkPattern Number (List SkPattern) Number))
(= (sk-join-score $owner $rule $remaining)
   (/ (* (sk-node-score (sk-node-hash $owner) $owner) (sk-rule-score $rule))
      (max 1 (fold-semidet sk-open-premise-step 0 $remaining))))

;; A ground node reading any proof and value, or a fold's member node, is
;; indexed once and takes the ground keys already registered that unify with
;; it (see sk-register-key!). Any other open node is answered by its own
;; search, which bounds recursion through its own conclusions.
(: sk-index-key-step (-[semidet]-> SkPattern Atom Number Atom))
(= (sk-index-key-step $node $_acc $khash)
   (let $_answered
      (collapse (match &sk_keys ($khash $key)
         (if (== (extract-vars $key) ()) (sk-add-answer! $node $key) (empty))))
      ()))

(: sk-index-node! (-[semidet]-> SkPattern Atom))
(= (sk-index-node! $node)
   (case $node (
      (($type $kbctx $proof $tv)
         (if (if (is-var $proof)
                (if (is-var $tv)
                   (if (== (extract-vars $type) ()) true
                      (space-row-present? &sk_member_of ((sk-node-hash $node) $_member $_fold)))
                   false)
                false)
            (let* (($hash (sk-node-hash $node))
                   ($prefix
                      (case (statement-prefix-hashes $type) (
                         (() (index-hash (car-atom $type)))
                         ((cons $longest $_shorter) $longest)))))
               (if (space-row-present? &sk_node_prefix ($prefix $_t $_c $hash $_n)) ()
                  (let $_row
                     (case (copy_term $node) (
                        ;; Branded so the row's columns are proven when compiled,
                        ;; not checked on every add.
                        (($lookup-type $lookup-kbctx $_p $_v)
                           (let* (($row-type (brand Statement $lookup-type))
                                  ($row-kbctx (brand KBContext $lookup-kbctx)))
                              (add-atom &sk_node_prefix ($prefix $row-type $row-kbctx $hash $node))))))
                     (fold-semidet (sk-index-key-step $node) ()
                        (sk-unifying-key-hashes (brand Statement $type) (brand KBContext $kbctx))))))
            ()))
      ($_cpu ()))))

(: sk-add-child! (-[semidet]-> SkPattern SkPattern Number Number Atom))
(= (sk-add-child! $owner $child $score $digest)
   (let $child-hash (sk-node-hash $child)
      (if (let $_scored (sk-raise-score! $child-hash $child $score) (sk-link-new! $digest))
         (let* (($hash (sk-node-hash $owner))
                ($_row (sk-store-child! $digest $hash $owner $child $child-hash))
                ($_pending (sk-link-pending! $hash $owner $child-hash $child))
                ($_fresh (add-atom &sk_fresh ($child-hash $child))))
            (sk-index-node! $child))
         ())))

;; What searching a fold's members is worth: a user base rate is never
;; refolded; an estimate by what one more member could add to its confidence,
;; since every member costs at least one expansion (nothing to a point); a fold
;; without an estimate by its join.
(: sk-fold-child-score (-[semidet]-> $args Number (List BaseRateEntry) Number))
(= (sk-fold-child-score $args $join-score $entries)
   (case $entries (
      (() $join-score)
      ((cons $entry $_rest)
         (if (base-rate-entry-user? $entry) 0.0
            (let $confidence (tv-confidence (base-rate-entry-tv $entry))
               (if (>= $confidence 1.0) 0.0
                  (* $join-score (- (count-confidence (+ (confidence-to-count $confidence) 1.0)) $confidence)))))))))

(: sk-leaf-answer-step (-[semidet]-> SkPattern Atom SkFact Atom))
(= (sk-leaf-answer-step $node $_acc $fact) (sk-add-answer! $node (sk-fact-key $fact)))

;; A ground node is answered by its key, and a fold's member node by every
;; ground key unifying with it, whichever search registered the key
;; (docs/metta/answers_by_index.md): a new key answers the indexed nodes it
;; unifies with, found through its statement's prefixes, and a node indexed
;; later takes the keys already registered (sk-index-node!).
(: sk-member-join-step (-[semidet]-> Statement KBContext SkeletonKey Atom Number Atom))
(= (sk-member-join-step $type $kbctx $key $_acc $prefix)
   (let $_answered
      (collapse (match &sk_node_prefix ($prefix $type $kbctx $_nhash $node) (sk-add-answer! $node $key)))
      ()))

(: sk-register-key! (-[semidet]-> SkeletonKey Atom))
(= (sk-register-key! $key)
   (case $key (
      ((sk-key $type $kbctx)
         (let $hash (index-hash $key)
            (if (== (collapse (once (match &sk_keys ($hash $stored) (if (=alpha $stored $key) true (empty))))) ())
               (let* (($_key (add-atom &sk_keys ($hash $key)))
                      ($_terms (add-atom &sk_key_terms ($type $kbctx $hash)))
                      ($ground (== (extract-vars $type) ()))
                      ($prefixes (statement-prefix-hashes $type))
                      ($_prefixes
                         (collapse (let $prefix (superpose $prefixes) (add-atom &sk_key_prefix ($prefix $type $kbctx $hash)))))
                      ($_open
                         (if $ground ()
                            (let $open (statement-open-hash $type) (add-atom &sk_key_open ($open $type $kbctx $hash)))))
                      ($readers (sk-unifying-readers $type $kbctx))
                      ($_joined
                         (collapse (let ($rhash $reader) (superpose $readers)
                            (if (== $rhash $hash) (empty) (sk-unifier-add! $hash (the Number $rhash) (the SkeletonKey $reader)))))))
                  (if $ground
                     (fold-semidet (sk-member-join-step $type $kbctx $key) () (cons (index-hash (car-atom $type)) $prefixes))
                     ()))
               ())))
      ($_fold ()))))

;; --- Answers and delivery ---------------------------------------------------

(= (sk-add-answer! $node $key)
   (if (let $link (sk-answer-link $node $key) (sk-link-new! (link-digest $link)))
      (let* (($_registered (sk-register-key! $key))
             ($hash (sk-node-hash $node))
             ($_row (add-atom &sk_answer ($hash $node $key)))
             ($_indexed
                (if (<= (search-id-value forgetting_horizon) 0) ()
                   (let* (($khash (index-hash $key))
                          ($_answered (add-atom &sk_answered ($khash $key $hash $node))))
                      ())))
             ($folds
                (collapse (match &sk_member_of ($hash $stored $fold)
                   (if (=alpha $stored $node) $fold (empty)))))
             ($_members (fold-semidet (sk-member-step $key) () $folds))
             ($_subsumed
                (collapse (match &sk_subsumed ($hash $stored $specific)
                   (if (=alpha $stored $node) (sk-unifying-answer! $specific () $key) (empty)))))
             ($seq (next-search-id sk_delivery_seq))
             ($_queued (add-atom &sk_answer_queue ($seq (sk-delivery $node $key)))))
         ())
      ()))

;; Deliveries run in the order answers were found, so derivations grow level
;; by level and a budget cut keeps the shallow ones.
(= (sk-drain!)
   (case (collapse (once (match &sk_answer_queue ($s (sk-delivery $n $k)) (sk-queued $s (sk-delivery $n $k))))) (
      (() ())
      ((cons (sk-queued $seq (sk-delivery $node $key)) $_rest)
         (if (<= (search-id-value sk_row_budget) 0) ()
            (let* (($_removed (remove-atom &sk_answer_queue ($seq (sk-delivery $_n $_k))))
                   ($hash (sk-node-hash $node))
                   ($waiters
                      (collapse (match &sk_wait ($hash $stored $waiter)
                         (if (=alpha $stored $node) $waiter (empty)))))
                   ($_delivered (fold-semidet (sk-extend-step $key) () $waiters)))
               (sk-drain!)))))))

(= (sk-extend-step $key $_acc $waiter) (sk-extend! (copy_term $waiter) $key))

;; A new member answer changes the value of every fold over its node; a group
;; fold additionally gains the answer's group as one of its own answers. An
;; implication instance fold takes the member when the evaluation brings it
;; current, so its readers are not changed before.
(= (sk-member-step $key $_acc $fold)
   (case $fold (
      ((CPU FoldAllCompiled $args $_res)
         (let* (($fold-key (sk-fold $args))
                ($_use (sk-add-use! $key $fold-key))
                ($_rate (sk-rate-dirty! $fold-key $key)))
            (if (sk-instance-fold-key? $fold-key) () (sk-mark-dirty! $fold-key))))
      ((CPU GroupedFoldAllCompiled $grouped-args $_res)
         (case (let $unbound (copy_term $grouped-args)
                  (sk-member-group (copy_term $grouped-args) $unbound $unbound $key)) (
            (() ())
            ((cons $group-args $_rest)
               (let* (($group-key (sk-group $group-args))
                      ($ghash (index-hash $group-key))
                      ($_group-of (if (== (collapse (once (match &sk_group_of ($ghash $stored $_gfold)
                                          (if (=alpha $stored $group-key) true (empty))))) ())
                                     (add-atom &sk_group_of ($ghash $group-key $fold)) ()))
                      ($_use (sk-add-use! $key $group-key))
                      ($_dirty (sk-mark-dirty! $group-key)))
                  (sk-add-answer! $fold $group-key))))))
      ($_other ()))))

;; The grouped fold's arguments with only the group variables bound, from one
;; member key; nothing when the key is not a member. Takes a fresh copy of the
;; arguments to match the key and another, passed twice, to receive the group
;; binding and be returned whole.
(: sk-member-group (-[det]-> $spec $spec $spec SkeletonKey (List $spec)))
(= (sk-member-group ($kbctx $pattern $group $_e $_i $_f $_fi $_m)
                    ($_c $_p $unbound-group $_e2 $_i2 $_f2 $_fi2 $_m2) $unbound $key)
   (if (= (sk-key $pattern $kbctx) $key) (if (= $unbound-group $group) (cons $unbound ()) ()) ()))

(: sk-completion-waiter? (-[det]-> SkeletonWaiter Bool))
(= (sk-completion-waiter? $waiter)
   (case $waiter (
      ((sk-partial $_owner $rule $_concl $_done $_remaining $_keys)
         (not (== (collapse (match &completion_recipe ($rule $_recipe) true)) ())))
      ($_other false))))

;; --- Partial joins and rows -------------------------------------------------

(: sk-forward-note-fold! (-[det]-> SkPattern Atom))
(= (sk-forward-note-fold! $premise)
   (case (copy_term $premise) (
      ((CPU $fun $args $res)
         (let $hash (sk-node-hash (CPU $fun $args $res))
            (if (if (sk-expanded? $hash (CPU $fun $args $res)) true
                   (case (base-rate-aggregate-key $args) (
                      ((base-rate-aggregate-key-value $_kbid $_pattern $_mode) true)
                      (no-base-rate-aggregate-key false))))
               ()
               (let $_noted (add-atom &sk_forward_folds ($hash (CPU $fun $args $res))) ()))))
      ($_fact ()))))

;; The keys a forward join's premise can take: the statements with stored
;; facts, and the keys the skeleton already has.
(: sk-forward-keys (-[det]-> SkPattern (List SkeletonKey)))
(= (sk-forward-keys $premise)
   (case $premise (
      (($type $kbctx $proof $tv)
         (list_to_set
            (append-flat
               (map-flat sk-fact-key
                  (sk-leaf-facts (brand Statement $type) (brand KBContext $kbctx) (sk-filter $proof $tv)))
               (foldr-flat sk-hash-keys-step ()
                  (sk-unifying-key-hashes (brand Statement $type) (brand KBContext $kbctx))))))
      ($_cpu ()))))

(: sk-hash-keys-step (-[det]-> Number (List SkeletonKey) (List SkeletonKey)))
(= (sk-hash-keys-step $hash $keys) (append-flat (collapse (match &sk_keys ($hash $key) $key)) $keys))

;; A row's premises, from the premises its join took (most recent first) and
;; the keys that extended it (in the same order): a statement premise reads
;; its key as registered. An open key, a statement that holds for every value
;; of its variables (an implication's own variables, a fact stored with
;; variables), stays open where later premises bound the variables it shares
;; with them: that instance is no key of its own and has no rows to read. The
;; variables the join left open stay linked, so evaluation binds them through
;; the key's value, as a fold's result binds the conclusion.
(datatype SkeletonReading (sk-reading (List SkeletonKey) (List SkPattern)))
(: sk-read-step (-[semidet]-> SkeletonReading SkPattern SkeletonReading))
(= (sk-read-step (sk-reading $keys $read) $premise)
   (case $premise (
      ((CPU $fun $_args $_res)
         (if (aggregate-fold-function? $fun)
            (sk-reading (cdr-atom $keys) (cons $premise $read))
            (sk-reading $keys (cons $premise $read))))
      (($type $kbctx $proof $tv)
         (let* (((cons (sk-key $read-type $read-kbctx) $rest) $keys)
                ($_linked (link-open-variables (sk-key $read-type $read-kbctx) (sk-key $type $kbctx))))
            (sk-reading $rest (cons (assemble-stored-runtime-fact $read-type $read-kbctx $proof $tv) $read)))))))

;; A fold premise of a join is searched as a child of the join's owner, scored
;; by what the join is worth, and a compound's prior through the folds it
;; reads (#142); a forward run notes them instead. So is the statement a node
;; row's sibling read takes, at a small share of the join's worth: the row
;; does not wait for it, and its search takes what budget the direct work
;; leaves, so the sibling's value improves with budget instead of costing
;; every query.
(: sk-evidence-statement (-[det]-> $spec SkPattern))
(= (sk-evidence-statement ($_kb $statement $_target $kbctx)) (assemble-stored-runtime-fact $statement $kbctx $_proof $_tv))

(: sk-cavity-read? (-[det]-> $spec Bool))
(= (sk-cavity-read? $args)
   (case $args ((($_kb $_statement (cavity $_compound $_target) $_kbctx) true) ($_completion false))))

(: sk-fold-child! (-[semidet]-> SkPattern Number SkFact (List SkPattern) Atom SkPattern Atom))
(= (sk-fold-child! $owner $rule $concl $remaining $_acc $premise)
   (case $premise (
      ((CPU CompoundRate $rate-args $_rate)
         (fold-semidet (sk-fold-child! $owner $rule $concl $remaining) () (compound-rate-goals $rate-args true $_inner)))
      ((CPU CompoundEvidence $evidence-args $_res)
         (if (if (== (search-id-value sk_forward_run) 1) true (not (sk-cavity-read? $evidence-args))) ()
            (let* (($child (sk-evidence-statement $evidence-args))
                   ($digest (link-digest (sk-child-link $owner $child)))
                   ($_kept (sk-keep-child! $digest $concl)))
               (sk-add-child! $owner $child (* 0.01 (sk-join-score $owner $rule $remaining)) $digest))))
      ((CPU FoldAllCompiled $args $_res)
         (if (== (search-id-value sk_forward_run) 1) (sk-forward-note-fold! $premise)
            (let $score (sk-fold-child-score $args (sk-join-score $owner $rule $remaining) (sk-rate-entries $args))
               (if (> $score 0.0)
                  (let* (($child (copy_term $premise))
                         ($digest (link-digest (sk-child-link $owner $child)))
                         ($_kept (sk-keep-child! $digest $concl)))
                     (sk-add-child! $owner $child $score $digest)) ()))))
      ($_formula ()))))

(= (sk-advance! (sk-partial $owner $rule $concl $done $remaining $keys))
   (if (rule-live? $rule)
   (case $remaining (
      (()
         (let (sk-reading $_none $premises) (fold-semidet sk-read-step (sk-reading $keys ()) $done)
            (sk-complete-row! $owner $rule $concl $premises $keys)))
      ((cons $premise $rest)
         (case $premise (
            ((CPU $fun $args $_res)
               (if (stored-list-member? $fun (FoldAllCompiled CompoundRate))
                  (let $_child (sk-fold-child! $owner $rule $concl $remaining () $premise)
                     (sk-advance!
                        (sk-partial $owner $rule $concl (cons $premise $done) $rest
                           (sk-direct-key-step $keys $premise))))
                  (if (== $fun GroupedFoldAllCompiled)
                     (let $_fold (if (== (search-id-value sk_forward_run) 1) (sk-forward-note-fold! $premise) ())
                        (sk-wait-on! $owner $rule $premise
                           (sk-partial $owner $rule $concl $done $remaining $keys)))
                     (if (if (contextual-cpu? $fun) false (if (== $fun vars-covered?) true (== (extract-vars $args) ())))
                        ;; Once the row allowance is closed, an application
                        ;; computes nothing more: a row it completes would only
                        ;; be refused (sk-refuse!).
                        (if (if (sk-scaffold? $owner $rule) false (<= (search-id-value sk_row_budget) 0))
                           (sk-refuse!)
                           (fold-semidet
                              (sk-cpu-step (sk-partial $owner $rule $concl $done $remaining $keys))
                              ()
                              (collapse (cpu-call 0 $fun $args))))
                        ;; Truth-value formulas run during evaluation.
                        (let $_child (if (== $fun CompoundEvidence) (sk-fold-child! $owner $rule $concl $remaining () $premise) ())
                           (sk-advance!
                              (sk-partial $owner $rule $concl (cons $premise $done) $rest $keys)))))))
            ;; A forward run reads a premise from what exists, never waiting.
            ($_fact
               (if (== (search-id-value sk_forward_run) 1)
                  (fold-semidet (sk-extend-waiter-step (sk-partial $owner $rule $concl $done $remaining $keys)) ()
                     (sk-forward-keys (copy_term $premise)))
                  (sk-wait-on! $owner $rule $premise
                     (sk-partial $owner $rule $concl $done $remaining $keys)))))))))
      ()))

;; A ground computation (for example arithmetic on bound statement terms)
;; binds its result before later premises are looked up.
(= (sk-cpu-step $partial $_acc $result)
   (let* (((sk-partial $owner $rule $concl $done $remaining $keys) (copy_term $partial)))
      (case $remaining (
         ((cons $premise $rest)
            (case $premise (
               ((CPU $_fun $_args $res)
                  (if (= $res $result)
                     (sk-advance! (sk-partial $owner $rule $concl (cons $premise $done) $rest $keys))
                     ()))
               ($_fact ()))))
         ($_other ())))))

;; A join waiting on a ground fact premise sees that premise's stored facts at
;; once: looking them up is one indexed read, so only expanding the premise's
;; rules costs a step. An open premise waits for its expansion, which bounds
;; recursion through its own answers.

(= (sk-wait-on! $owner $rule $premise $waiter)
   (if (sk-functional-conflict? $premise) ()
   (if (sk-functional-exhausted? $premise)
      (fold-semidet (sk-extend-waiter-step $waiter) () (sk-answers $premise))
   (let* (((sk-partial $_owner $_rule $concl $_done $remaining $_keys) $waiter)
          ($known (sk-known-conclusion? $concl))
          ($hash (sk-node-hash $premise))
          ($child (copy_term $premise))
          ($digest (link-digest (sk-child-link $owner $child)))
          ($_wait (if $known () (sk-store-wait! $digest $hash $premise $waiter)))
          ($_inversions (sk-start-deferred! $hash $premise $rule))
          ($subscription (sk-functional-subscription $waiter))
          ;; A durable join cannot depend on a query-local judgment producer.
          ;; Install its exact scaffold with the join's lifetime, even if a
          ;; prior query already expanded this premise using temporary rules.
          ;; A query-local join reading an implication's judgment, as a
          ;; compound key's producer does, gets the query's own scaffold too:
          ;; an earlier query's left with it.
          ($_scaffold
             (case $premise (
                ((CPU $_fun $_args $_res) ())
                (($type $scope $proof $tv)
                   (if (< $rule 1000000000)
                      (inject-special-subgoal-query-adds backward $type $scope $proof $tv)
                      (if (if (head-is? $tv STV) (implication-type? $type) false)
                         (let $_installed (inject-special-subgoal-query-adds temp $type $scope $proof $tv)
                            (sk-activate-pending!))
                         ()))))))
          ;; A compound premise read in a hypothetical context gets its
          ;; producers with the join's lifetime too. A MAIN compound premise
          ;; gets none here: an open variable-headed node matches each new
          ;; producer's conclusion, and installing for those instances would
          ;; nest compound keys without bound. A root's producers come with
          ;; the root, a rule's own compound premises with the rule.
          ($_producers
             (case $premise (
                ((CPU $_pfun $_pargs $_pres) ())
                (($ptype $pscope $_pproof $_ptv)
                   (if (compound-source? $ptype)
                      (let $pctx (car-atom (cdr-atom $pscope))
                         (if (== $pctx MAIN) ()
                            (let $_installed (install-producers! (if (< $rule 1000000000) backward temp) $ptype $pscope)
                               (sk-activate-pending!))))
                      ())))))
          ($_leaves
             (if (sk-expanded? $hash $premise) ()
                (case (copy_term $premise) (
                   ((CPU $_fun $_args $_res) ())
                   (($type $kbctx $proof $tv)
                      (if (== (extract-vars $type) ())
                         (fold-semidet (sk-leaf-answer-step $premise) () (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
                         ()))))))
          ($_temp
             (if $known ()
                (if (>= $rule 1000000000)
                   (let $_t (add-atom &sk_temp_waits ($hash $premise $waiter)) ())
                   ())))
          ($_child
             (let $_kept (if $known (sk-keep-child! $digest $concl) true)
                (sk-add-child! $owner $child (sk-join-score $owner $rule $remaining) $digest))))
      ;; Read existing keys, including aggregate registrations before the
      ;; completed-row check. A known conclusion leaves no future subscriber.
      (let* (($_read (sk-read-answers! $waiter $premise))
             ($_retired (sk-functional-delivered! $subscription)))
         ())))))

;; A waiting join reads the keys its premise has: its answers, and a
;; completion's population priors too.
(: sk-read-answers! (-[semidet]-> SkeletonWaiter SkPattern Atom))
(= (sk-read-answers! $waiter $premise)
   (let $hash (sk-node-hash $premise)
      (fold-semidet (sk-extend-waiter-step $waiter) ()
         (if (sk-completion-waiter? $waiter) (append-flat (sk-answers $premise)
            (collapse (match &sk_prior_answer ($hash $pstored $pkey) (if (=alpha $pstored $premise) $pkey (empty))))) (sk-answers $premise)))))

(: sk-extend-waiter-step (-[semidet]-> SkeletonWaiter Atom SkeletonKey Atom))
(= (sk-extend-waiter-step $waiter $_acc $key) (sk-extend-current! (copy_term $waiter) $key))

;; A join is extended by an answer once, however the answer reaches it (read
;; when the join starts waiting, or delivered later); a computation that
;; samples would otherwise draw again. Once the row allowance is spent, a join
;; an answer reaches stops there: the pair waits once with the join's owner, so
;; a recursive rule cannot keep extending joins whose rows could not be kept
;; anyway. Joins of the query's scaffold always proceed (sk-scaffold?).
(= (sk-extend! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
   (if (rule-live? $rule)
      (if (sk-known-conclusion? $concl) ()
         (let* (($subscription (sk-functional-subscription (sk-partial $owner $rule $concl $done $remaining $keys)))
                ($_extended (sk-extend-current! (sk-partial $owner $rule $concl $done $remaining $keys) $key))
                ($_retired (sk-functional-delivered! $subscription)))
            ()))
      (case $remaining (
         ((cons $premise $_rest)
            (let $hash (sk-node-hash $premise)
               (sk-retire-wait! $hash $premise (sk-partial $owner $rule $concl $done $remaining $keys))))
         (() ())))))

(: sk-extend-current! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(= (sk-extend-current! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
   (if (rule-live? $rule)
   (if (if (sk-scaffold? $owner $rule) true (> (search-id-value sk_row_budget) 0))
      (sk-extend-now! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
      (sk-defer-join! (sk-partial $owner $rule $concl $done $remaining $keys)))
      ()))

;; A join the allowance cannot extend keeps the identity of itself as it
;; waits in &sk_wait (sk-wait-handle), neither the key that reached it nor the terms
;; its earlier premises bound: a later walk with allowance reads its
;; premise's keys again (sk-resume!), and the join extends by those it has not
;; taken. A join with no stored waiter, as a forward run's are, has no handle,
;; and the application that started it owns the refusal (sk-refuse!).
(: sk-defer-join! (-[det]-> SkeletonWaiter Atom))
(= (sk-defer-join! (sk-partial $owner $rule $concl $done $remaining $keys))
   (let $handle (sk-wait-handle (sk-partial $owner $rule $concl $done $remaining $keys))
      (if (< $handle 0) (sk-refuse!)
         (let* (($hash (sk-node-hash $owner))
                ($join (sk-join $owner $rule $handle))
                ($jhash (index-hash $join)))
            ;; The hashes find candidates; only the record itself is a duplicate.
            (if (not (== (collapse (match &sk_deferred_joins ($hash $jhash $stored) (if (=alpha $stored $join) true (empty)))) ())) ()
               (let* (($_deferred (add-atom &sk_deferred_joins ($hash $jhash $join)))
                      ($_pending (sk-work! $hash $owner 1))
                      ($_counted (query_metric_increment joins-deferred)))
                  ()))))))

;; A settled join (its rule reads one part of a compound, settling it; see
;; connective_settling.md) reads a part only when a certain stored fact fixes
;; its value, as it does for a ground key, and binds that value: the part's
;; formulas then run when the join is built, and a part that does not settle
;; builds no row. A derived value never settles (modus ponens leaves its
;; confidence below 1), so a settled join builds no row it does not need.
(: sk-settles? (-[det]-> (List SkPattern) Bool))
(= (sk-settles? ()) false)
(= (sk-settles? (cons $premise $rest))
   (if (case $premise (((CPU $fun $_args $_res) (== $fun SettlesFormula)) ($_fact false))) true (sk-settles? $rest)))

(: sk-certain-tv-step (-[det]-> (List TV) SkFact (List TV)))
(= (sk-certain-tv-step $tvs ($_type $_kbctx $_proof $tv))
   (case $tv (((STV $_s $c) (if (>= $c 1.0) (cons $tv $tvs) $tvs)) ($_other $tvs))))

(: sk-settled-read? (-[det]-> (List SkPattern) (List SkPattern) Statement KBContext TV Bool))
(= (sk-settled-read? $done $remaining $type $kbctx $tv)
   (if (if (sk-settles? $done) true (sk-settles? $remaining))
      (if (== (extract-vars $type) ())
         (case (fold-flat sk-certain-tv-step () (sk-leaf-facts $type $kbctx sk-any-filter)) (
            ((cons $certain $_more) (= $tv $certain))
            (() (context-seeded? $type $kbctx))))
         false)
      true))

(: sk-extend-now! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(= (sk-extend-now! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
   (case $remaining (
      ((cons $premise $rest)
         ;; The key as registered, before later premises bind it (sk-read-step).
         (let* (($registered (copy_term $key))
                ($waiter (copy_term (sk-partial $owner $rule $concl $done $remaining $keys))))
         (if (case $premise (
                ((CPU $_fun $args $_res) (= (sk-group $args) $key))
                (($type $kbctx $_proof $tv)
                   (if (= (sk-key $type $kbctx) $key)
                      (if (chainer-acyclic-term? $concl) (sk-settled-read? $done $remaining $type $kbctx $tv) false)
                      false))))
            ;; Record after this answer binds the conclusion. A thawed ground
            ;; key can then remove the digest even for an originally open join.
            ;; A forward run's join is not recorded: it never waits, so one
            ;; that stops at a premise no key answers yet would keep the same
            ;; join, started later from that premise's key, from extending,
            ;; and its row would never be built (sk-complete-row! keeps a row
            ;; once).
            (let $digest (link-digest (sk-join-link (sk-partial $owner $rule $concl $done $remaining $keys) $registered))
               (if (if (== (search-id-value sk_forward_run) 1) true (sk-store-join! $digest $waiter $concl))
                  ;; A row this extension led to that could not be paid
                  ;; for leaves the join to extend again (sk-refuse!).
                  (let* (($refused (search-id-value sk_refused))
                         ($_advanced (sk-advance!
                            (sk-partial $owner $rule $concl (cons $premise $done) $rest (cons $registered $keys)))))
                     (if (if (== $refused (search-id-value sk_refused)) true (== (search-id-value sk_forward_run) 1)) ()
                        (let* (($_owned (change-state! sk_refused $refused))
                               ($_forgot (sk-unstore-join! $digest $concl)))
                           (sk-defer-join! $waiter))))
                  ()))
            ())))
      ($_other ()))))

(: sk-row-present? (-[det]-> Number SkeletonKey Number SkeletonIdent Bool))
(= (sk-row-present? $khash $key $rhash $ident)
   (not (== (collapse (once (match &sk_row ($khash $stored $rhash (sk-row $stored-ident $_c $_p $_seq))
               (if (=alpha $stored $key) (if (=alpha $stored-ident $ident) true (empty)) (empty)))))
            ())))

;; A computation whose arguments were ground when its join was built was
;; computed then and bound its result; recomputing a sampling formula would
;; draw again. The formulas over premise truth values run in evaluation.
;; The truth's instance producer is registered once as its row is built.
(: sk-truth-fold-step! (-[semidet]-> Number Atom SkPattern Atom))
(= (sk-truth-fold-step! $truth $_acc $premise)
   (case $premise (
      ((CPU FoldAllCompiled $args $_res)
         (case $args (
            (($_kb (ImplicationInstanceSample $_a $_b $_atv $_btv) $_extract $_zero $_accumulator $_finish $_result)
               (let* (($fold (sk-fold $args)) ($hash (index-hash $fold)))
                  (if (space-row-present? &ctx_sk_truth_fold ($truth $hash $fold)) ()
                     (context-add! &sk_truth_fold ($truth $hash $fold)))))
            ($_other ()))))
      ($_other ()))))

(: sk-evaluated-premise-step (-[det]-> (List SkPattern) SkPattern (List SkPattern)))
(= (sk-evaluated-premise-step $kept $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (if (contextual-cpu? $fun) true (aggregate-fold-function? $fun)) (cons $premise $kept)
            (if (== (extract-vars $args) ()) $kept (cons $premise $kept))))
      ($_fact (cons $premise $kept)))))

(: sk-same-key-step (-[det]-> SkeletonKey Bool SkeletonKey Bool))
(= (sk-same-key-step $key $found $other) (if $found true (=alpha $other $key)))

;; A row answers its owner node with its key, except a root's population
;; prior, which answers only the antecedent completions waiting on the node:
;; to any other row the population's value is no value of the statement
;; (sk-premise-step), and a join it completed would build a row deriving
;; nothing. Answering them at once and as a completion starts waiting keeps
;; the node's answers for the rows that do.
(: sk-row-answer! (-[semidet]-> SkPattern SkeletonKey Atom Atom))
(= (sk-row-answer! $owner $key $proof)
   (if (head-is? $proof population-prior) (sk-prior-answer! (sk-node-hash $owner) $owner $key) (sk-add-answer! $owner $key)))

(: sk-prior-answer! (-[semidet]-> Number SkPattern SkeletonKey Atom))
(= (sk-prior-answer! $hash $owner $key)
   (if (space-row-present? &sk_prior_answer ($hash $owner $key)) ()
      (let* (($_row (add-atom &sk_prior_answer ($hash $owner $key)))
             ($waiters
                (collapse (match &sk_wait ($hash $stored $waiter)
                   (if (=alpha $stored $owner) (if (sk-completion-waiter? $waiter) $waiter (empty)) (empty))))))
         (fold-semidet (sk-extend-step $key) () $waiters))))

;; Register direct fold/group readers with their rows. Idle eviction can
;; reopen their search rather than freeze an aggregate snapshot.
(: sk-aggregate-reader-step (-[det]-> Bool SkPattern Bool))
(= (sk-aggregate-reader-step $found $premise)
   (if $found true
      (case $premise (((CPU $fun $_args $_res) (aggregate-fold-function? $fun)) ($_fact false)))))

(= (sk-complete-row! $owner $rule $concl $premises $keys)
   (if (rule-live? $rule)
   (let* ((($type $kbctx $proof $_tv) $concl)
          ($key (sk-key $type $kbctx))
          ($khash (index-hash $key))
          ($ident (sk-ident $rule $keys $key))
          ($rhash (index-hash $ident))
          ($local (>= $rule 1000000000)))
      ;; Expansion applies no rule to a certain statement; a forward run's
      ;; upward joins skip it here, where their conclusion is first bound,
      ;; and so does a query's join of an open node for a known statement: its
      ;; value is its stored fact to every reader, so the row would only
      ;; spend the evaluation's allowance, and the need would walk on below
      ;; it (a history of known periods under an open node, all of it rows
      ;; of an Assuming context). An instance that reads its own conclusion,
      ;; (HasLeg Dog 4) from (Dog Dog) and (HasLeg Dog 4) itself, is no
      ;; derivation of it. An open key stands for several statements, and a
      ;; query adapter, whose open proof head passes its premise's proof
      ;; through, derives nothing.
      (if (if (== (extract-vars $type) ())
             (if (if (if (is-expr $proof) (is-var (car-atom $proof)) false) false
                    (fold-semidet (sk-same-key-step $key) false $keys))
                true
                (let $facts (sk-leaf-facts $type $kbctx sk-any-filter)
                   (if (== (search-id-value sk_forward_run) 1) (sk-certain? $type $facts)
                      (fold-semidet sk-known-leaf-step false $facts))))
             false)
         ()
      (if (sk-row-present? $khash $key $rhash $ident)
         (sk-row-answer! $owner $key $proof)
         ;; The query's scaffold always fits; every other row spends the
         ;; allowance at what storing it costs, paid before it is stored. A
         ;; row the allowance left cannot pay closes it and is refused
         ;; (sk-refuse!).
         (let $evaluated (fold-semidet sk-cons-step () (fold-semidet sk-evaluated-premise-step () $premises))
         (if (if (sk-scaffold? $owner $rule) true
                (if (sk-pay-cost! sk_row_budget (row-cost (sk-row $ident $concl $evaluated 0) (search-id-value sk_row_budget))) true
                   (let $_closed (change-state! sk_row_budget (min 0 (search-id-value sk_row_budget))) false)))
            (let* (($seq (next-search-id sk_row_seq))
                   ($row (sk-row $ident $concl $evaluated $seq))
                   ($_add
                      (if (chainer-acyclic-term? $row)
                         (let* (($_stored (add-atom &sk_row ($khash $key $rhash $row)))
                                ($_truth-folds (case $key (
                                   ((sk-key (RuleTruth $_truth) $_ctx)
                                      (fold-semidet (sk-truth-fold-step! $khash) () $premises))
                                   ($_other ()))))
                                ($_aggregate (if (fold-semidet sk-aggregate-reader-step false $premises)
                                           (add-atom &sk_aggregate_row ($khash $key $rhash)) ()))
                                ($_touched (sk-touch-key! $khash $key))
                                ($_counted (query_metric_increment rows-created)))
                            (context-add! &sk_new (sk-row-item $seq $khash $key $rhash $row)))
                         false))
                   ($_temp
                      (if $local
                         (let $_t (add-atom &sk_temp_rows ($khash $key $rhash $row)) ())
                         ()))
                   ($_readers
                      (fold-semidet (sk-add-reader! $khash $rhash) ()
                         (fold-semidet sk-direct-key-step () $premises))))
               (sk-row-answer! $owner $key $proof))
            (sk-refuse!))))))
      ()))

;; A row the allowance cannot pay leaves no payload behind (sk-refuse!). The
;; innermost application in progress owns the refusal and keeps only how to
;; rebuild the row: a join extension forgets it extended and waits to read its
;; premise's keys again (sk-defer-join!), and a rule started at a node waits
;; to start again there (sk-defer-rule!). Keeping the row itself let refused
;; rows keep 90,000 words each, and 2.4 million words for 32 rules completing
;; without a join at one step, none of it paid.
(: sk-refuse! (-[det]-> Atom))
(= (sk-refuse!) (let $_refused (next-search-id sk_refused) ()))

;; A rule waits to start again at its owner once, however often it is refused.
(: sk-defer-rule! (-[det]-> SkPattern Number Atom))
(= (sk-defer-rule! $owner $rule)
   (let* (($hash (sk-node-hash $owner))
          ($dhash (index-hash (sk-deferred $owner $rule))))
      (if (not (== (collapse (match &sk_deferred ($hash $dhash $stored) (if (=alpha $stored (sk-deferred $owner $rule)) true (empty)))) ())) ()
         (let* (($_deferred (add-atom &sk_deferred ($hash $dhash (sk-deferred $owner $rule))))
                ($_pending (sk-work! $hash $owner 1))
                ($_counted (query_metric_increment rows-deferred)))
            ()))))

;; The budget counts expansions. New rows have their own allowance of ten per
;; step, so recursive rules cannot grow the skeleton without bound; a row found
;; after the allowance is spent waits in &sk_deferred for a later walk. A row
;; costs more the larger it is as stored, every shared subterm counted again,
;; as expanding a fact node costs more the larger its statement (row-cost and
;; term-cost, runtime_state.pl), so a step costs the same however large the
;; terms a recursive rule builds, such as (Num (succ (succ ...))) from
;; (Num $x) → (Num (succ $x)). A fold's arguments do not grow that way.
(: sk-root? (-[det]-> SkPattern Bool))
(= (sk-root? $node)
   (let $hash (sk-node-hash $node)
      (not (== (collapse (once (match &sk_roots ($hash $root) (if (=alpha $root $node) true (empty))))) ()))))

;; A query's scaffold, the joins and rows its roots own that cost no
;; allowance: the applications of its own rules, which the query compiled
;; and which apply a bounded number of times. A root's applications of the
;; KB's rules are as many as their premises have bindings, whether the root
;; is open or ground, and spend the allowance as any other row does (#176: an
;; inverted rule and the projections of a conjunction rebuilt each other's
;; answers at an open root, 1,222 rows and 518 MB of stored rows in 400 steps;
;; one rule over 1,000 facts gave a ground root 1,000 free rows at one step).
(: sk-scaffold? (-[det]-> SkPattern Number Bool))
(= (sk-scaffold? $owner $rule)
   (if (>= $rule 1000000000) (sk-root? $owner) false))

;; Whether the search still has work at or below a node: it is unexpanded, or
;; the pending-work index holds work below it. A root never reached has no
;; entry in the index yet.
(: diagnostic-work? (-[det]-> Number SkPattern Bool))
(= (diagnostic-work? $hash $node)
   (if (sk-pending? $hash $node) true (if (sk-expanded? $hash $node) false (sk-root? $node))))

;; Work left over by an earlier query waits with its node and resumes when a
;; later walk reaches that node, so it never spends an unrelated query's
;; budget: parked deliveries are queued again, and while rows are allowed,
;; deferred joins are extended and deferred rules started again.
;; A deferred rule starts again at its owner, as expansion started it.
(: sk-deferred-step (-[semidet]-> Atom SkeletonDeferred Atom))
(= (sk-deferred-step $_acc (sk-deferred $owner $rule))
   (let ($type $kbctx $_proof $_tv) $owner
      (fold-semidet (sk-start-rule-step $owner) ()
         (collapse (let (sk-match $id $premises $goal) (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_p $_t))
            (if (== $id $rule) (sk-match $id $premises $goal) (empty)))))))

(: sk-resume! (-[semidet]-> Number SkPattern Atom))
(= (sk-resume! $hash $node)
   (let* (($deliveries
             (collapse (match &sk_parked ($hash $seq (sk-delivery $owner $key))
                (if (=alpha $owner $node)
                   (let $_removed (remove-atom &sk_parked ($hash $seq (sk-delivery $_o $_k)))
                      (add-atom &sk_answer_queue ($seq (sk-delivery $owner $key))))
                   (empty)))))
          ($_delivered (sk-work! $hash $node (- 0 (length $deliveries)))))
      (if (<= (search-id-value sk_row_budget) 0) ()
         (let* (($joins
                   (collapse (match &sk_deferred_joins ($hash $jhash (sk-join $jowner $jrule $handle))
                      (if (=alpha $jowner $node)
                         (let $_removed (remove-atom &sk_deferred_joins ($hash $jhash (sk-join $jowner $jrule $handle)))
                            (sk-join $jowner $jrule $handle))
                         (empty)))))
                ($_taken (sk-work! $hash $node (- 0 (length $joins))))
                ($_joined (fold-semidet sk-deferred-join-step () $joins))
                ($deferred
                   (collapse (match &sk_deferred ($hash $rhash (sk-deferred $owner $rule))
                      (if (=alpha $owner $node)
                         (let $_removed (remove-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule)))
                            (sk-deferred $owner $rule))
                         (empty)))))
                ($_completed (sk-work! $hash $node (- 0 (length $deferred)))))
            (fold-semidet sk-deferred-step () $deferred)))))

(: sk-waiter-owner (-[det]-> SkeletonWaiter SkPattern))
(= (sk-waiter-owner (sk-partial $owner $_rule $_concl $_done $_remaining $_keys)) $owner)

(: sk-deferred-join-step (-[semidet]-> Atom SkeletonJoin Atom))
(= (sk-deferred-join-step $_acc (sk-join $_owner $rule $handle))
   (if (rule-live? $rule)
      (fold-semidet sk-waiter-read-step () (sk-waiter-at $handle))
      ()))

(: sk-waiter-read-step (-[semidet]-> Atom SkeletonWaiter Atom))
(= (sk-waiter-read-step $_acc (sk-partial $owner $rule $concl $done (cons $premise $rest) $keys))
   (let* (($subscription (sk-functional-subscription (sk-partial $owner $rule $concl $done (cons $premise $rest) $keys)))
          ($_read (sk-read-answers! (sk-partial $owner $rule $concl $done (cons $premise $rest) $keys) $premise)))
      (sk-functional-delivered! $subscription)))

(: sk-park-step (-[det]-> Atom SkeletonQueued Atom))
(= (sk-park-step $_acc (sk-queued $seq (sk-delivery $node $key)))
   (let* (($hash (sk-node-hash $node))
          ($_row (add-atom &sk_parked ($hash $seq (sk-delivery $node $key)))))
      (sk-work! $hash $node 1)))

(: sk-park-deliveries! (-[semidet]-> Atom))
(= (sk-park-deliveries!)
   (let $entries
      (collapse (match &sk_answer_queue ($seq (sk-delivery $node $key))
         (let $_removed (remove-atom &sk_answer_queue ($seq (sk-delivery $_n $_k)))
            (sk-queued $seq (sk-delivery $node $key)))))
      (fold-semidet sk-park-step () $entries)))

;; --- Expansion --------------------------------------------------------------

;; runtime/application_discovery/plans supplies the application plans used here,
;; by forward triggers and by late-rule activation.

;; A rule applies to a node when its conclusion fits the whole node pattern;
;; its row is built from the statement and context alone, since a row belongs
;; to its key and each reader applies its own proof and truth-value pattern.
;; A dormant rule is not started (docs/metta/dormant_rules.md).
;; Assumptions can enable producers MAIN skipped as dormant. Assuming shares
;; structural rows without supplying assumed values; private implication
;; judgments start their own contextual rows, regardless of MAIN's verdict.
;; Missing fact premises keep their join subscriptions. Failing ground CPU
;; premises and structural binding guards trigger the prefilter.
(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (if (if (sk-context-search? $goal) false (rule-dormant? $rule)) false (= (copy_term $goal) (sk-rule-goal (copy_term $owner))))
      (if (if (case $goal (
                (($type $kbctx $proof $_tv)
                   (if (derivation-proof? $type $proof) (complete-statement? $type $kbctx) false))))
             false
             ;; Once the row allowance is closed, starting an application
             ;; that computes at once is refused before it computes: its rule
             ;; starts again later, prefilter and all.
             (if (if (sk-scaffold? $owner $rule) false (<= (search-id-value sk_row_budget) 0))
                (if (any-flat? sk-computes-now? $premises) (let $_deferred (sk-defer-rule! $owner $rule) true) false)
                (any-flat? prefilter-premise-blocks? (copy_term $premises))))
         ()
         (let* (($refused (search-id-value sk_refused))
                ($_advanced (sk-advance! (sk-partial $owner $rule $goal () $premises ()))))
            (if (== $refused (search-id-value sk_refused)) ()
               (let $_owned (change-state! sk_refused $refused) (sk-defer-rule! $owner $rule)))))
      ()))

;; The compiled scaffold of an implication subgoal that is not itself a
;; compiled total-implication source. Durable consumers need durable private
;; contexts; a temporary query scaffold cannot satisfy that ownership.
;; A subgoal asking for a rule application's proof, as a statement rule's
;; premise does (docs/metta/derived_implications.md), reads only rules
;; concluding the implication, and gets no scaffold.
(: inject-special-subgoal-query-adds (-[semidet]-> KbBackend Statement KBContext Proof TV Atom))
(= (inject-special-subgoal-query-adds $backend $type $kbctx $prf $tv)
   (case $kbctx (
      (($kbid MAIN Nil)
         (if (implication-type? $type)
            ;; A compiler-marked source already installed its scaffold. The
            ;; marker test compares without unifying, so an open proof head
            ;; stays an ordinary constraint.
            (if (if (is-expr $prf)
                   (if (== $prf ()) false
                      (let $head (car-atom $prf)
                         (if (if (== $head by) true (== $head derived-implication)) true
                            (if (== $head total-implication-frontier)
                               (let $args (cdr-atom $prf) (if (== $args ()) false (== (cdr-atom $args) ())))
                               false))))
                   false)
               ()
               ;; A compound root may already have prepared this leaf's
               ;; scaffold. Require alpha identity before checking constraints:
               ;; a bound instance needs its own assumption contexts. Copy
               ;; the lookup so checking constraints cannot bind the caller.
               (let ($lookup-type $lookup-ctx $lookup-proof $lookup-tv)
                  (copy_term (data $type $kbctx $prf
                     (if (head-is? $tv STV)
                        (statement-query-tv $tv)
                        (if (is-var $tv) (CTV $positive $negative) $tv))))
                  (if (== (collapse (once (match ccls_index
                        (($lookup-type $lookup-ctx
                           (cons $scaffold-head (cons $inner ())) $scaffold-tv)
                         $scaffold-id $_args)
                        (if (if (== $scaffold-head total-implication-frontier) true
                               (== $scaffold-head conditional-implication))
                           ;; Indexed lookup unifies its copied pattern. Read
                           ;; the original shape by id before checking alpha
                           ;; identity, so a general scaffold stays general.
                           (match ccls_index (($scaffold-type $_ctx $_proof $_tv)
                                 $scaffold-id $_premises)
                              (if (if (== $backend backward) (< $scaffold-id 1000000000) true)
                                 (if (=alpha $scaffold-type $type)
                                    (if (= $lookup-tv $scaffold-tv)
                                       (if (= $lookup-proof (cons $scaffold-head (cons $inner ())))
                                          true (empty))
                                       (empty))
                                    (empty))
                                 (empty)))
                           (empty))))) ())
                     (foreach-flat (inject-compiled-query-adds $backend)
                        (collapse
                           (if (if (is-var $tv) true (head-is? $tv CTV))
                              (let (compilation-plan $goal $adds)
                                 (compile-implication-subgoal-query (brand KB $kbid)
                                    (: $prf $type (if (is-var $tv) (CTV $positive-tv $negative-tv) $tv)))
                                 (compiled-query (brand CompiledQueryGoal (internalize-proof-structure $goal))
                                    (map-flat mm2stmt $adds)))
                              (mm2compileQuery (brand KB $kbid) (: $prf $type $tv)))))
                     ())))
            ()))
      ($_other ()))))

;; The producers of a compound key a reader reads get the reader's lifetime,
;; as its scaffolds do (#142): a query root's and a query-local join's leave
;; with the query's temporary rules, a durable join's stay. So a query's cost
;; does not grow with the compounds earlier queries read. Each producer is
;; installed once per lifetime, up to variable renaming (&installed_producers);
;; a durable one also serves a query. A MAIN read gets MAIN's rules, any other
;; read rules for every context.
(: fresh-producer-step
   (-[det]-> KbBackend (List CompiledAddition) CompiledAddition (List CompiledAddition)))
(= (fresh-producer-step $backend $fresh $add)
   (let $hash (index-hash $add)
      (if (== (collapse (once (match &installed_producers ($hash $lifetime $stored)
                (if (if (== $lifetime backward) true (== $backend temp)) (if (=alpha $stored $add) true (empty)) (empty)))))
             ())
         (let* (($copy (copy_term $add)) ($_row (add-atom &installed_producers ($hash $backend $copy)))) (cons $add $fresh))
         $fresh)))

(: install-producers! (-[semidet]-> KbBackend Statement KBContext Atom))
(= (install-producers! $backend $type ($kbid $ctx $vars))
   (let $adds (producers
                 (if (if (== $ctx MAIN) (== $vars Nil) false)
                    (make-kb-context (brand KB $kbid) MAIN Nil)
                    (make-kb-context (brand KB $kbid) $any-ctx $any-vars))
                 $type)
      (let $_rules (once (foreach-flat (kb-add-expr $backend)
                     (map-flat mm2stmt (fold-flat (fresh-producer-step $backend) () $adds))))
         ())))

;; A class link's sample and fold rules are permanent
;; backward rules, installed once per link up to renaming, when a root or an
;; expanded node of the link or of an instance of it needs them, as a
;; compound's part does: their rows survive the query, so a later query reads
;; the link's tally at the cost of the samples that changed.
(: install-class-link-rules! (-[semidet]-> Statement KBContext Atom))
(= (install-class-link-rules! $type ($kbid $ctx $vars))
   (if (if (== $ctx MAIN) (if (== $vars Nil) (head-is? $type Implication) false) false)
      (let (Implication $a $b) $type
         (if (class-link-instance? $a $b)
            (let* (($kb (brand KB $kbid))
                   ($link (brand Statement (Implication (cons (car-atom $a) (cons $x ())) (cons (car-atom $b) (cons $x ())))))
                   ($adds (if (rule-truth-installed? $kb $link) (the (List CompiledAddition) ())
                             (let (Implication $antecedent $consequent) $link
                                (compile-implication-instance-adds false $kb $link
                                   (brand Statement $antecedent) (brand Statement $consequent)))))
                   ($_rules (once (foreach-flat (kb-add-expr backward)
                               (map-flat mm2stmt (fold-flat (fresh-producer-step backward) () $adds))))))
               ())
            ()))
      ()))

(: inject-compiled-query-adds (-[semidet]-> KbBackend CompiledQuery Atom))
(= (inject-compiled-query-adds $backend (compiled-query $_goal $adds))
   (if (is-var $adds) (empty)
      (let $_added (once (foreach-flat (kb-add-expr $backend) $adds))
         (if (== $backend backward) (sk-activate-pending!) ()))))

;; The fold's source goal is compiled as an ordinary query once per pattern
;; shape and KB (`pattern-shape`: constants of a user predicate, alone or
;; under a connective, do not change what it compiles to). Its additions are
;; installed as permanent backward rules: the member rows outlive the query,
;; and a later fold over the same shape reuses the goal. The member is the compiled goal
;; for the fold's own pattern; a fold scoped to a context reads it there.
(: sk-fold-member (-[semidet]-> $arguments (List SkPattern)))
(= (sk-fold-member $args)
   (let* (($scope (car-atom $args))
          ($kbid (if (is-expr $scope) (car-atom $scope) $scope))
          ($pattern (car-atom (cdr-atom $args)))
          ($existential (sk-existential-fold? (CPU fold $args unused)))
          ($shape (pattern-shape $pattern))
          ($compiled (sk-shape-members $kbid $shape))
          ;; Existential shapes retain free variables. Relink the cached
          ;; member to this pattern, including its private context variables;
          ;; alpha equality alone would leave those variables disconnected.
          ($members (if (if $existential false (== $shape $pattern))
                        $compiled (map-semidet (sk-narrow-member $pattern) $compiled))))
      (if (is-expr $scope) (map-semidet (sk-scoped-member $scope) $members) $members)))

;; A member compiled for an abstracted shape is narrowed to the fold's pattern.
(: sk-narrow-member (-[semidet]-> Atom SkPattern SkPattern))
(= (sk-narrow-member $pattern ($type $kbctx $proof $tv))
   (once (let $pattern $type (the SkPattern ($type $kbctx $proof $tv)))))

(: sk-scoped-member (-[semidet]-> Atom SkPattern SkPattern))
(= (sk-scoped-member $scope ($type $_kbctx $proof $tv))
   (assemble-stored-runtime-fact $type (brand KBContext $scope) $proof $tv))

(: sk-shape-members (-[semidet]-> Atom Atom (List SkPattern)))
(= (sk-shape-members $kbid $shape)
   (let* (($source (quote ($kbid $shape))) ($hash (index-hash $source)))
      (case (collapse (once (match &sk_fold_members ($hash $stored $member)
               (if (=alpha $stored $source) $member (empty))))) (
         ((cons $found $_rest) (cons $found ()))
         (()
            (case (collapse (once (mm2compileQuery (brand KB $kbid) (: $_h (brand Statement $shape) $_i)))) (
               ((cons (compiled-query $goal $adds) $_rest)
                  (if (if (is-var $goal) true (is-var $adds)) ()
                     ;; A compound shape's producers come with its member,
                     ;; once per shape: compileQuery leaves them to the reader.
                     (let* (($_rules (once (foreach-flat (kb-add-expr backward) $adds)))
                            ($_producers (once (foreach-flat (kb-add-expr backward)
                               (map-flat mm2stmt (producers (make-kb-context (brand KB $kbid) $ctx $vars) (brand Statement $shape))))))
                            ($compiled (typed-runtime-premise $goal))
                            ($_row (add-space-atom! &sk_fold_members (make-space-row3 $hash $source $compiled))))
                        (cons $compiled ()))))
               ($_none ()))))))))

(= (sk-expand! $node $depth $hash)
   (let $_counted (query_metric_increment expansions)
   (case $node (
      ((CPU $_fun $args $_res)
         (let* (($_mark (sk-mark-expanded! $hash $node))
                ($members (sk-fold-member $args))
                ($_activate (sk-activate-pending!)))
            (case $members (
               (() ())
               ((cons $member $_rest)
                  (let* (($member-hash (sk-node-hash $member))
                         ($_fold (add-atom &sk_fold ($hash $node $member)))
                         ($_member-of (add-atom &sk_member_of ($member-hash $member $node)))
                         ($digest (link-digest (sk-child-link $node $member)))
                         ($_kept (sk-keep-child! $digest $node))
                         ($_child (sk-add-child! $node $member (sk-node-score $hash $node) $digest)))
                     (fold-semidet (sk-fold-answer-step $node) () (sk-answers $member))))))))
      (($type $kbctx $proof $tv)
         (let* (($_special
                   (if (> $depth 0) (inject-special-subgoal-query-adds temp $type $kbctx $proof $tv) ()))
                ($_links (install-class-link-rules! $type $kbctx))
                ($_activate (sk-activate-pending!))
                ($_mark (sk-mark-expanded! $hash $node))
                ($_seeds (context-answer-seeds! $node))
                ($leaf-facts (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
                ($_leaves (fold-semidet (sk-leaf-answer-step $node) () $leaf-facts))
                ;; A complete statement answers by its own key: the joins
                ;; reading it build their rows, and a closed read decides its
                ;; value (docs/metta/complete_predicates.md).
                ($_complete (if (complete-statement? $type $kbctx) (sk-add-answer! $node (sk-key $type $kbctx)) ()))
                ($owner (copy_term $node))
                (($rule-type $rule-kbctx $_node-proof $_node-tv) (copy_term $node)))
            ;; No rule is applied to a certain statement.
            (if (sk-certain? $type $leaf-facts) ()
               (case (sk-subsumers $depth $node) (
                  ((cons $general $_more)
                     (let* (($ghash (sk-node-hash $general))
                            ($_row (add-atom &sk_subsumed ($ghash $general $owner)))
                            ($digest (link-digest (sk-child-link $owner $general)))
                            ($_kept (sk-keep-child! $digest $owner))
                            ($_child (sk-add-child! $owner $general (sk-node-score $hash $owner) $digest)))
                        (fold-semidet (sk-unifying-answer! $owner) () (sk-answers $general))))
                  (()
                     (let* (($goal (assemble-stored-runtime-fact $rule-type $rule-kbctx $_rule-proof $_rule-tv))
                            ($matches (collapse (sk-rule-match $goal)))
                            ($started
                               (if (if (> $depth 0) (compound-source? (brand Statement $type)) false)
                                  (fold-semidet (sk-start-now-step $hash $owner (sk-reader-names $hash)) () $matches)
                                  $matches))
                            ($_rules (fold-semidet (sk-start-rule-step $owner) () $started))
                            ($_open
                               (if (== (extract-vars $type) ()) ()
                                  (let $prefix (sk-node-prefix $type) (add-atom &sk_open_node ($prefix $hash $owner))))))
                        (if (== $leaf-facts ()) (sk-start-prior! $owner $type $kbctx $matches) ()))))))))))))

;; The rule an inversion match inverts, or none.
(: sk-inverted-rule (-[det]-> SkeletonMatch Atom))
(= (sk-inverted-rule (sk-match $id $_premises $_conclusion)) (proof-inversion-name $id))

;; The name of the rule a join applies, none for a producer or an adapter.
(: sk-rule-name (-[det]-> Number Atom))
(= (sk-rule-name $id) (proof-application-name $id))

;; The rules whose joins wait on a node.
(: sk-reader-names (-[det]-> Number (List Atom)))
(= (sk-reader-names $hash)
   (let $rules (collapse (match &sk_wait ($hash $_premise (sk-partial $_owner $rule $_c $_d $_r $_k)) $rule))
      (map-flat sk-rule-name $rules)))

;; Folded over readers: whether each is `$rule`.
(: sk-only-reader-step (-[det]-> Atom Bool Atom Bool))
(= (sk-only-reader-step $rule $only $reader) (if $only (== $reader $rule) false))

;; A compound node's matches in source order, an inversion left waiting while
;; the inverted rule's joins alone read the node (&sk_deferred_inversion).
(: sk-start-now-step
   (-[semidet]-> Number SkPattern (List Atom) (List SkeletonMatch) SkeletonMatch (List SkeletonMatch)))
(= (sk-start-now-step $hash $owner $readers $kept $match)
   (let $rule (sk-inverted-rule $match)
      (if (if (== $rule none) false
             (if (== $readers ()) false (fold-semidet (sk-only-reader-step $rule) true $readers)))
         (let $_deferred (add-atom &sk_deferred_inversion ($hash $rule $owner $match)) $kept)
         (append-flat $kept (cons $match ())))))

;; A reader of a node, a join of rule `$reader` or a query root (-1), starts
;; the inversions waiting there of every other rule; the node hash only finds
;; the node's entries.
(: sk-start-deferred! (-[semidet]-> Number SkPattern Number Atom))
(= (sk-start-deferred! $hash $node $reader-id)
   (if (not (space-row-present? &sk_deferred_inversion (quote ($hash $_r $_o $_m)))) ()
      (let* (($reader (if (< $reader-id 0) none (sk-rule-name $reader-id)))
             ($_started (collapse (match &sk_deferred_inversion ($hash $rule $owner $match)
                (if (if (== $rule $reader) true (not (sk-same-node? $owner $node))) (empty)
                   (let $_taken (remove-variant-row! &sk_deferred_inversion (quote ($hash $rule $owner $match)))
                      (sk-start-rule-step $owner () $match)))))))
         ())))

(: sk-root-reader-step (-[semidet]-> Atom SkPattern Atom))
(= (sk-root-reader-step $_acc $root) (sk-start-deferred! (sk-node-hash $root) $root -1))

;; Subsumption: an open node below a root whose statement grows a term of an
;; open node whose rules were already started (grows-from?, as (Num (succ $x))
;; does (Num $x)) reads that node's answers instead of starting rules of its
;; own. A mere specialization, such as (Reward op1 $t) of (Reward $op $t),
;; keeps its own search, which a budget spends on that case first. Every rule concluding the instance concludes the
;; general node, whose joins wait on premises at least as general, so the
;; general search finds every key the instance's would; the instance takes
;; those that unify with it, and a child link to the general node lets walks
;; through the instance resume the general search. Otherwise a recursive rule
;; read through an open node (a base rate's members over (Num $x) → (Num (succ
;; $x))) unrolls one new open node per step, each answered by every key below
;; it. A candidate's index column is a prefix of the instance's statement, so
;; one lookup per prefix finds it. Implications are expanded on their own,
;; since their expansion installs rules. A root of the
;; current query subsumes nothing: its rows always fit the allowance, so a
;; recursive rule answering it through an instance would never stop.
(: sk-subsumers (-[det]-> Number SkPattern (List SkPattern)))
(= (sk-subsumers $depth $node)
   (case $node (
      ((CPU $_fun $_args $_res) ())
      (($type $_kbctx $_proof $_tv)
         (if (if (== $depth 0) true
                (if (== (extract-vars $type) ()) true
                   (implication-type? $type)))
            ()
            (let $prefixes (append-flat (statement-prefix-hashes $type) (cons (index-hash (car-atom $type)) ()))
               (collapse (once (let $prefix (superpose $prefixes)
                  (match &sk_open_node ($prefix $_ghash $general)
                     (if (grows-from? $general $node) (if (sk-root? $general) (empty) $general) (empty))))))))))))

;; A key reaching a subsumed node through its general node answers it when it
;; unifies with it.
(: sk-unifying-answer! (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-unifying-answer! $node $_acc $key)
   (case (copy_term $node) (
      (($type $kbctx $_proof $_tv)
         (if (= (sk-key $type $kbctx) (copy_term $key)) (sk-add-answer! $node $key) ()))
      ($_cpu ()))))

;; The base-rate folds that rules concluding a statement read over a pattern
;; the statement belongs to, the priors their inversions and completions
;; update, with the rules reading them.

(: sk-application-match? (-[det]-> Bool SkeletonMatch Bool))
(= (sk-application-match? $found (sk-match $_rule $_premises ($_type $_kbctx $proof $_tv)))
   (if $found true (rule-application-proof? $proof)))

;; A ground statement that no rule application concludes and that is not
;; complete is a root of the model: inversions and completions conclude it
;; from evidence, but nothing derives it. Without evidence its value is the
;; prior of one more member of its population, the base rate its inversions
;; update (population-prior-tv). A row of its key reads it, so the rules
;; reading the statement apply to it, and the prior follows the base rate;
;; the key reads the prior only while nothing else gives it a value
;; (sk-own-values). A positive-only predicate has no prior, and a complete
;; statement no rule application derives is unfounded instead
;; (docs/metta/complete_predicates.md).
(: sk-start-prior! (-[semidet]-> SkPattern Statement KBContext (List SkeletonMatch) Atom))
(= (sk-start-prior! $owner $type $kbctx $matches)
   (if (if (if (== (extract-vars $type) ()) (== (key-context (sk-key $type $kbctx)) MAIN) false)
          (if (complete-statement? $type $kbctx) false (if (fold-semidet sk-application-match? false $matches) false true))
          false)
      (case (sk-prior-folds $type $matches) (
         ((cons (sk-prior-fold $rule $args) $_more)
            (let* (($pattern (copy_term (car-atom (cdr-atom $args)))) ($kbid (car-atom $args)))
               (sk-advance!
                  (sk-partial $owner $rule
                     (assemble-stored-runtime-fact $type $kbctx (brand Proof (population-prior $pattern)) $tv)
                     ()
                     (quote ((CPU FoldAllCompiled $args $rate) (CPU configured-population-prior-tv ($kbid $pattern $rate) $tv)))
                     ()))))
         (() ())))
      ()))

(: sk-fold-answer-step (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-fold-answer-step $fold $acc $key) (sk-member-step $key $acc $fold))

;; --- Activation of facts and rules added after expansion --------------------

(: sk-activate-thawed! (-[semidet]-> Atom))
(= (sk-activate-thawed!)
   (let $_thawed (collapse (match &sk_thawed ($hash (sk-key $type $kbctx))
      (let* (($_taken (remove-atom &sk_thawed ($hash (sk-key $type $kbctx))))
             ($_registered (sk-register-key! (sk-key $type $kbctx)))
             ($goal (assemble-stored-runtime-fact $type $kbctx $_proof $_tv)))
         (fold-semidet (sk-start-rule-step $goal) () (collapse (sk-rule-match $goal))))))
      ()))

(= (sk-activate-pending!)
   (let* (($_retired (sk-retire-searches!))
          ($_rules (sk-activate-rules!))
          ($_thawed (sk-activate-thawed!)))
      (sk-activate-facts!)))

(= (sk-activate-rules!)
   (fold-semidet sk-activate-rule-step ()
      (collapse (match &sk_pending_rules (sk-pending-rule $id)
         (let $_removed (remove-atom &sk_pending_rules (sk-pending-rule $id)) $id)))))

(= (sk-activate-facts!)
   (fold-semidet sk-activate-fact-step ()
      (collapse (match &sk_pending_facts (sk-pending-fact $key)
         (let $_removed (remove-atom &sk_pending_facts (sk-pending-fact $key)) $key)))))

(: sk-activate-rule-step (-[semidet]-> Atom Number Atom))
(= (sk-activate-rule-step $_acc $id)
   (fold-semidet (sk-activate-rule-row $id) ()
      (collapse (match ccls_index ($ccls $id $args) (sk-rule-def $ccls $args)))))

(: sk-absorb-step (-[semidet]-> Atom SkeletonMatch Atom))
(= (sk-absorb-step $_acc (sk-match $id $prems $ccls))
   (let* ((($type $kbctx $_proof $_tv) $ccls) ($key (sk-key $type $kbctx)))
      (if (== (extract-vars $key) ())
         (let $hash (index-hash $key)
            (fold-semidet (sk-activate-rule-on $id $ccls $prems) ()
               (collapse (match &sk_score ($hash $node $_score) (if (sk-expanded? $hash $node) (empty) $node)))))
         ())))

;; A fact added after expansion is read at once by every node reading its key:
;; the expanded nodes it matches and the ground premises joins wait on, expanded
;; or not. A ground fact is also read by each node the skeleton holds, still
;; unexpanded, for the conclusion of a rule it is a premise of: that rule alone
;; is started there, as expanding the node would start it. Stored facts cost no
;; expansion however late they arrive, so new evidence reaches the keys a search
;; built without the search returning to them.
(: sk-activate-world-reader (-[semidet]-> Statement Atom SkeletonKey Atom))
(: sk-activate-fact-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-activate-fact-step $_acc $key)
   (case $key (
      ((sk-key $type $kbctx)
         (let* ((($kbid $ctx $_vars) $kbctx)
                ($hash (index-hash $key))
                ($_read
                   (fold-semidet (sk-activate-fact-on $key) ()
                      (alpha_unique_keys
                         (append-flat (collapse (match &sk_node_terms ($type $kbctx $node) $node))
                            (append-flat (sk-fact-watches $hash)
                               (collapse (match &sk_wait ($hash $premise $_waiter) $premise)))))))
                ($_absorbed
                   (if (== (extract-vars $type) ())
                      (fold-semidet sk-absorb-step () (foldr-flat (sk-premise-rules-step $type $kbctx) () (map-flat (prefix-key $kbid)
                         (cons (index-hash (if (is-expr $type) (car-atom $type) $type)) (statement-prefix-hashes $type)))))
                      ())))
            (if (== $ctx MAIN)
               (fold-semidet (sk-activate-world-reader $type) () (sk-world-readers $type (brand KB $kbid)))
               ())))
      ($_fold ()))))

(= (sk-activate-world-reader $type $_acc (sk-key $reader $scope))
   (let* (($key (sk-key $reader $scope))
          ($hash (index-hash $key))
          ($_root (sk-clear-root-cap! $hash $key))
          ($_dirty (sk-dirty! $key))
          ($_changed
             (if (not (== (collapse (once (match &sk_world_changed ($hash $stored)
                        (if (=alpha $stored $key) true (empty))))) ())) ()
                (let $_pending (add-atom &sk_world_changed ($hash $key)) ()))))
      (sk-activate-fact-step () (sk-key $type $scope))))

(: sk-activate-world-rule-on (-[semidet]-> Number Atom SkPattern Atom))
(: sk-activate-world-rule (-[semidet]-> Number Atom SkeletonKey Atom))
(= (sk-activate-world-rule $id $_acc (sk-key $type $scope))
   (let* (($hash (index-hash (sk-key $type $scope)))
          ($nodes (alpha_unique_keys
             (append-flat (collapse (match &sk_node_terms ($type $scope $node) $node))
                (append-flat (sk-fact-watches $hash)
                   (collapse (match &sk_wait ($hash $premise $_waiter) $premise)))))))
      (fold-semidet (sk-activate-world-rule-on $id) () $nodes)))

(= (sk-activate-world-rule-on $id $_acc $node)
   (case (copy_term $node) (
      ((CPU $_fun $_args $_res) ())
      (($type $scope $proof $tv)
         (let $matches (collapse (let $matched
            (sk-judgment-main-rule-match (data $type $scope $proof $tv))
            (case $matched (((sk-match $id $args $conclusion) (sk-match $id $args $conclusion))
                            ($_other (empty))))))
            (if (== $matches ()) ()
               (let $_changed (sk-activate-world-reader $type () (sk-key $type $scope))
                  (fold-semidet (sk-start-rule-step $node) () $matches))))))))

(: sk-activate-rule-row (-[semidet]-> Number Atom SkeletonRuleDef Atom))
(= (sk-activate-rule-row $id $_acc (sk-rule-def $conclusion $args))
   (let* ((($type $kbctx $_proof $_tv) $conclusion)
          ($_ordinary
             (fold-semidet (sk-activate-rule-on $id $conclusion $args) ()
                (collapse (match &sk_node_terms ($type $kbctx $node)
                   (let ($node-type $_c $_p $_t) $node
                      ;; A subsumed node reads the general node's conclusions.
                      (if (== (extract-vars $node-type) ()) $node
                         (if (let $prefix (sk-node-prefix $node-type)
                                (== (collapse (once (match &sk_open_node ($prefix $_h $stored)
                                       (if (=alpha $stored $node) true (empty))))) ()))
                            (empty) $node))))))))
      ;; A late compound fact brings new MAIN projection rules. They must
      ;; reach existing private readers just as they do on cold expansion.
      (case $kbctx (
         (($kbid $ctx $_vars)
            (if (== $ctx MAIN)
               (fold-semidet (sk-activate-world-rule $id) () (sk-world-readers $type (brand KB $kbid)))
               ()))))))

(: sk-activate-rule-on (-[semidet]-> Number SkFact (List SkPattern) Atom SkPattern Atom))
(= (sk-activate-rule-on $id $ccls $args $_acc $node)
   (let $matches (collapse (discover-application $id $ccls $args $node))
      (fold-semidet (sk-start-rule-step $node) () $matches)))

(: sk-activate-fact-on (-[semidet]-> SkeletonKey Atom SkPattern Atom))
(= (sk-activate-fact-on $key $_acc $node)
   (case (copy_term $node) (
      ((CPU $_fun $_args $_res) ())
      (($type $kbctx $proof $tv)
         (if (= (sk-key $type $kbctx) (copy_term $key))
            (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
            ())))))

;; Whether a node's search can still give it answers: it, or a node below it,
;; is unexpanded or has work waiting at it (parked deliveries, deferred joins
;; or rows). A node whose search is exhausted never answers without new
;; knowledge. Each node is visited once; the walk stops at the first such node.

(: sk-seen! (-[det]-> Number SkPattern Bool))
(= (sk-seen! $hash $node)
   (if (== (collapse (once (match &sk_seen ($hash $stored) (if (=alpha $stored $node) true (empty))))) ())
      (let $_row (add-atom &sk_seen ($hash $node)) false) true))

;; Joins extended after their owner was walked link new children to it; the
;; walk picks those up from &sk_fresh at the next level.
(: sk-take-fresh! (-[det]-> (List SkeletonNodeAt)))
(= (sk-take-fresh!)
   (let* (($fresh (collapse (match &sk_fresh ($hash $node) (sk-node-at $hash $node))))
          ($_taken (remove-data-rows! &sk_fresh (quote ($fresh-hash $fresh-node)))))
      $fresh))

;; The walk is best-first by score. Expanding a node costs a step. Passing
;; through an expanded node spends a separate walk allowance, so revisiting what
;; is already built never takes a step from new expansions. The walk enters
;; only nodes whose search may still have work (sk-pending?): below any other
;; node everything is expanded and nothing waits, so walking it would change
;; nothing, and it costs neither time nor allowance. Once the budget is
;; spent, unexpanded nodes are passed over, as expanded nodes are once the
;; allowance is spent, and the walk goes on to what is left: expansions that
;; cost no step still complete the joins the paid ones started. Equal scores go
;; first to the work of roots already started, shallowest first, and then to
;; the roots not started yet, in insertion order: the budget completes the
;; answers it started before it starts new ones. A frontier entry carries its
;; node's hash, so neither its push nor its pop hashes the node again.
(: sk-push (-[det]-> Number (Heap SkeletonFrontier) SkeletonNodeAt (Heap SkeletonFrontier)))
(= (sk-push $depth $heap (sk-node-at $hash $node))
   (add_to_heap $heap
      (+ (- 0 (sk-node-score $hash $node)) (+ (* (if (== $depth 0) 1000 $depth) 0.000001) (* (next-search-id sk_push_seq) 0.000000000001)))
      (sk-frontier $node $depth $hash)))

(: sk-push-children (-[semidet]-> Number Number SkPattern (Heap SkeletonFrontier) (Heap SkeletonFrontier)))
(= (sk-push-children $depth $hash $node $heap)
   (fold-semidet (sk-push (+ $depth 1))
      (fold-semidet (sk-push (+ $depth 1)) $heap (sk-pending-children $hash $node))
      (sk-take-fresh!)))

(= (sk-search! $heap)
   (let $_drained (sk-drain!)
      (if (heap-empty? $heap)
         (case (sk-take-fresh!) (
            (() ())
            ($fresh (sk-search! (fold-semidet (sk-push 1) $heap $fresh)))))
         (sk-search-pop! (heap_pop $heap)))))

;; A node expanded without a step when the walk reaches it: one no rule can
;; conclude, whose expansion only reads its stored facts, and a compound key a
;; rule application reads as its premise, whose producers are how that rule
;; reads the compound's parts, so reading it through its key costs the search
;; what reading the parts did (#142). Any other compound node, such as a rule's
;; whole conjunctive antecedent, which no rule reads, costs a step.
;; Implications are not free, since expanding them installs rules.
(: sk-free-expansion? (-[semidet]-> Number SkPattern Bool))
(= (sk-free-expansion? $hash $node)
   (case $node (
      ((CPU $_fun $_args $_res) false)
      (($type $kbctx $_proof $_tv)
         (if (compound-source? (brand Statement $type)) (if (fold-semidet (sk-only-reader-step none) true (sk-reader-names $hash)) false true)
            (if (implication-type? $type) false
               (== (collapse (once (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_rp $_rt)))) ())))))))

(: sk-search-pop! (-[semidet]-> (Number SkeletonFrontier (Heap SkeletonFrontier)) Atom))
(= (sk-search-pop! ($_priority (sk-frontier $node $depth $hash) $rest))
   (if (sk-expanded? $hash $node)
      (if (if (sk-pending? $hash $node) (not (sk-seen! $hash $node)) false)
         (if (sk-take! sk_walk_budget 1)
            (let* (($_counted (query_metric_increment nodes-walked))
                   ($_resumed (sk-resume! $hash $node)))
               (sk-search! (sk-push-children $depth $hash $node $rest)))
            (sk-search! $rest))
         (sk-search! $rest))
      (if (sk-seen! $hash $node)
         (sk-search! $rest)
         (if (if (sk-free-expansion? $hash $node) true (sk-pay-cost! sk_budget (case $node (((CPU $_f $_a $_r) 1) (($type $_c $_p $_t) (term-cost $type (search-id-value sk_budget)))))))
            (let $_expand (sk-expand! $node $depth $hash) (sk-search! (sk-push-children $depth $hash $node $rest)))
            (sk-search! $rest)))))

;; A walk from its roots.
(: sk-walk! (-[semidet]-> (List SkPattern) Atom))
(= (sk-walk! $roots) (sk-search! (fold-semidet sk-push-root (empty_heap) $roots)))

(: sk-push-root (-[det]-> (Heap SkeletonFrontier) SkPattern (Heap SkeletonFrontier)))
(= (sk-push-root $heap $root) (sk-push 0 $heap (sk-node-at (sk-node-hash $root) $root)))

;; Query-local rules leave with their query: their rows, waiters, deferred joins
;; and rows and views are removed, and the keys of the removed rows changed. A
;; later query's rule may take a removed rule's id, so a deferred join left
;; behind would extend the wrong rule.
(: sk-clear-temp! (-[semidet]-> Atom))
(= (sk-clear-temp!)
   (let* (($_deferred
             (collapse (match &sk_deferred ($h $rh (sk-deferred $o $rule))
                (if (>= $rule 1000000000)
                   (let $_taken (sk-work! (sk-node-hash $o) $o -1)
                      (remove-atom &sk_deferred ($h $rh (sk-deferred $o $rule))))
                   (empty)))))
          ($_joins
             (collapse (match &sk_deferred_joins ($jh $jj (sk-join $jo $jrule $jw))
                (if (>= $jrule 1000000000)
                   (let $_taken (sk-work! (sk-node-hash $jo) $jo -1)
                      (remove-atom &sk_deferred_joins ($jh $jj (sk-join $jo $jrule $jw))))
                   (empty)))))
          ($_waits
             (collapse (match &sk_temp_waits ($hash $pattern $waiter)
                (let* (($_temp (remove-atom &sk_temp_waits ($hash $pattern $waiter)))
                       ($_removed (remove-variant-row! &sk_wait (quote ($hash $pattern $waiter)))))
                   ()))))
          ($keys
             (collapse (match &sk_temp_rows ($khash $key $rhash $row)
                (let* (($_temp (remove-atom &sk_temp_rows ($khash $key $rhash $row)))
                       ($_row (sk-drop-row! $khash $key $rhash $row)))
                   $key)))))
      (foreach-flat sk-mark-dirty! $keys)))

(: context-answer-seeds! (-[semidet]-> SkPattern Atom))
(= (context-answer-seeds! $node) (let $_added (map-semidet (sk-add-answer! $node) (context-answer-keys $node)) true))

;; A root's producers are part of its scaffold and installed even when the
;; budget expands nothing.
(: sk-root-score-step (-[semidet]-> Atom SkPattern Atom))
(= (sk-root-score-step $_acc $goal)
   (let* (($hash (sk-node-hash $goal))
          ($_root (add-atom &sk_roots ($hash $goal)))
          ($_indexed (sk-index-node! $goal))
          ($_member
             (case (copy_term $goal) (
                ((CPU $_fun $_args $_res) ())
                (($type $kbctx $_proof $_tv)
                   (let $_producers (install-producers! temp $type $kbctx) (install-class-link-rules! $type $kbctx)))))))
      (sk-raise-score! $hash $goal 1.0)))
