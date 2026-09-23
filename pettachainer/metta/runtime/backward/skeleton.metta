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

(: SkeletonMatch Type)
;; rule-id contextualized-premises conclusion
(: sk-match (-[det]-> Number (List SkPattern) SkFact SkeletonMatch))
(: SkeletonRuleDef Type)
(: sk-rule-def (-[det]-> SkFact (List SkPattern) SkeletonRuleDef))
(: sk-any Atom)

(: fold-semidet
   (-[semidet]-> (-[semidet]-> $acc $item $acc) $acc (List $item) $acc))
(= (fold-semidet $_fun $acc ()) $acc)
(= (fold-semidet $fun $acc (cons $item $rest))
   (fold-semidet $fun ($fun $acc $item) $rest))

(: map-semidet
   (-[semidet]-> (-[semidet]-> $input $output) (List $input) (List $output)))
(= (map-semidet $_fun ()) ())
(= (map-semidet $fun (cons $item $rest))
   (cons ($fun $item) (map-semidet $fun $rest)))

(: sk-cons-step (-[semidet]-> (List $item) $item (List $item)))
(= (sk-cons-step $items $item) (cons $item $items))

(: stored-list-member? (-[det]-> $item (List $item) Bool))
(= (stored-list-member? $_needle ()) false)
(= (stored-list-member? $needle (cons $first $rest))
   (if (== $needle $first) true (stored-list-member? $needle $rest)))

(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (or (== $function FoldAllCompiled) (== $function GroupedFoldAllCompiled)))

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
(: sk-expand! (-[semidet]-> SkPattern Number Atom))
(: sk-search! (-[semidet]-> Number (List SkPattern) (List SkPattern) Atom))

;; --- Node identity ----------------------------------------------------------

(: sk-node-hash (-[det]-> SkPattern Number))
(= (sk-node-hash $pattern)
   (case $pattern (
      ((CPU $_fun $args $_res) (index-hash $args))
      (($type $kbctx $_proof $_tv) (index-hash (sk-key $type $kbctx))))))

(: sk-type-head (-[det]-> Statement Atom))
(= (sk-type-head $type)
   (if (is-var $type) sk-any
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) sk-any $head))
         $type)))

(: sk-expanded? (-[det]-> SkPattern Bool))
(= (sk-expanded? $pattern)
   (let $hash (sk-node-hash $pattern)
      (not (== (collapse (once (match &sk_expanded ($hash $stored)
                  (if (=alpha $stored $pattern) true (empty)))))
               ()))))

(: sk-mark-expanded! (-[det]-> SkPattern Atom))
(= (sk-mark-expanded! $pattern)
   (let* (($hash (sk-node-hash $pattern))
          ($_row (add-atom &sk_expanded ($hash $pattern))))
      (case $pattern (
         ((CPU $_fun $_args $_res) ())
         (($type $_kbctx $_proof $_tv)
            (let* (($head (sk-type-head $type))
                   ($_head (add-atom &sk_node_head ($head $pattern))))
               ()))))))

(: sk-answers (-[det]-> SkPattern (List SkeletonKey)))
(= (sk-answers $pattern)
   (let $hash (sk-node-hash $pattern)
      (collapse (match &sk_answer ($hash $stored $key)
         (if (=alpha $stored $pattern) $key (empty))))))

;; Child links, answers and use edges are each recorded once. A hash of the
;; whole link makes that check one lookup instead of a scan over every link of
;; the same source.
(: sk-link-new! (-[det]-> SkeletonLink Bool))
(= (sk-link-new! $link)
   (let $hash (index-hash $link)
      (if (== (collapse (once (match &sk_link ($hash $stored)
                 (if (=alpha $stored $link) true (empty)))))
              ())
         (add-atom &sk_link ($hash $link))
         false)))

(: sk-add-child! (-[det]-> SkPattern SkPattern Atom))
(= (sk-add-child! $owner $child)
   (if (sk-link-new! (sk-child-link $owner $child))
      (let* (($hash (sk-node-hash $owner))
             ($_row (add-atom &sk_child ($hash $owner $child)))
             ($_fresh (add-atom &sk_fresh (sk-fresh $child))))
         ())
      ()))

;; --- Leaves -----------------------------------------------------------------

;; Materialized facts are forward rows marked in &materialized_facts. They are
;; never leaves: the backward chainer re-derives them.
(: MaterializedRow Type)
(: materialized-row
   (-[det]-> Number Statement KBContext (Statement KBContext Proof TV)
       (List Evidence) MaterializedRow))
(: materialized-forward-fact? (-[det]-> SkFact Bool))
(= (materialized-forward-fact? ($type $kb $proof $tv))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (space-row-present? &materialized_facts
         (materialized-row $hash $type $kb ($type $kb $proof $tv) $_ev))))

;; Every fact matching a goal; the probe for materialized rows runs only when
;; some materialization happened.
;; The pieces of a node pattern destructured from SkPattern arrive as raw terms.
(: sk-leaf-facts (-[det]-> Atom Atom Atom Atom (List SkFact)))
(= (sk-leaf-facts $type $kbctx $proof $tv)
   (let $plain (not (sk-space-nonempty? &materialized_facts))
      (collapse (match &kb (@ $fact ($type $kbctx $proof $tv))
         (if (chainer-acyclic-term? $fact)
            (if $plain $fact
               (if (materialized-forward-fact? $fact) (empty) $fact))
            (empty))))))

(: sk-fact-key (-[det]-> SkFact SkeletonKey))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))

;; --- Answers and delivery ---------------------------------------------------

(= (sk-add-answer! $node $key)
   (if (sk-link-new! (sk-answer-link $node $key))
      (let* (($hash (sk-node-hash $node))
             ($_row (add-atom &sk_answer ($hash $node $key)))
             ($folds
                (collapse (match &sk_member_of ($hash $stored $fold)
                   (if (=alpha $stored $node) $fold (empty)))))
             ($_members (fold-semidet (sk-member-step $key) () $folds))
             ($_queued (add-atom &sk_answer_queue (sk-delivery $node $key))))
         ())
      ()))

;; Deliveries run in the order answers were found, so derivations grow level
;; by level and a budget cut keeps the shallow ones.
(= (sk-drain!)
   (case (collapse (once (match &sk_answer_queue (sk-delivery $n $k) (sk-delivery $n $k)))) (
      (() ())
      ((cons (sk-delivery $node $key) $_rest)
         (if (<= (search-id-value sk_row_budget) 0) ()
            (let* (($_removed (remove-atom &sk_answer_queue (sk-delivery $node $key)))
                   ($hash (sk-node-hash $node))
                   ($waiters
                      (collapse (match &sk_wait ($hash $stored $waiter)
                         (if (=alpha $stored $node) $waiter (empty)))))
                   ($_delivered (fold-semidet (sk-extend-step $key) () $waiters)))
               (sk-drain!)))))))

(= (sk-extend-step $key $_acc $waiter) (sk-extend! (copy_term $waiter) $key))

(: sk-add-use! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-add-use! $key $parent)
   (if (sk-link-new! (sk-use-link $key $parent))
      (let* (($hash (index-hash $key))
             ($_row (add-atom &sk_use ($hash $key $parent))))
         ())
      ()))

(: sk-mark-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-mark-dirty! $key)
   (if (sk-space-nonempty? &sk_view)
      (let $_row (add-atom &sk_dirty (sk-dirty $key)) ())
      ()))

;; A new member answer changes the value of every fold over its node; a group
;; fold additionally gains the answer's group as one of its own answers.
(= (sk-member-step $key $_acc $fold)
   (case $fold (
      ((CPU FoldAllCompiled $args $_res)
         (let* (($fold-key (sk-fold $args))
                ($_use (sk-add-use! $key $fold-key)))
            (sk-mark-dirty! $fold-key)))
      ((CPU GroupedFoldAllCompiled $grouped-args $_res)
         (case (let $unbound (copy_term $grouped-args)
                  (sk-member-group (copy_term $grouped-args) $unbound $unbound $key)) (
            (() ())
            ((cons $group-args $_rest)
               (let* (($group-key (sk-group $group-args))
                      ($_group-of (sk-add-group-of! $group-key $fold))
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
   (if (= (sk-key $pattern $kbctx) $key)
      (if (= $unbound-group $group) (cons $unbound ()) ())
      ()))

(: sk-add-group-of! (-[det]-> SkeletonKey SkPattern Atom))
(= (sk-add-group-of! $group-key $fold)
   (let $hash (index-hash $group-key)
      (if (== (collapse (once (match &sk_group_of ($hash $stored $_fold)
                 (if (=alpha $stored $group-key) true (empty)))))
              ())
         (let $_row (add-atom &sk_group_of ($hash $group-key $fold)) ())
         ())))

;; --- Partial joins and rows -------------------------------------------------

(= (sk-advance! (sk-partial $owner $rule $concl $premises $remaining $keys))
   (case $remaining (
      (() (sk-complete-row! $owner $rule $concl $premises $keys))
      ((cons $premise $rest)
         (case $premise (
            ((CPU $fun $args $_res)
               (if (== $fun FoldAllCompiled)
                  (let $_child (sk-add-child! $owner (copy_term $premise))
                     (sk-advance!
                        (sk-partial $owner $rule $concl $premises $rest
                           (cons (sk-fold $args) $keys))))
                  (if (== $fun GroupedFoldAllCompiled)
                     (sk-wait-on! $owner $rule $premise
                        (sk-partial $owner $rule $concl $premises $remaining $keys))
                     (if (== (extract-vars $args) ())
                        (fold-semidet
                           (sk-cpu-step
                              (sk-partial $owner $rule $concl $premises $remaining $keys))
                           ()
                           (collapse (cpu-call 0 $fun $args)))
                        ;; Truth-value formulas run during evaluation.
                        (sk-advance!
                           (sk-partial $owner $rule $concl $premises $rest $keys))))))
            ($_fact
               (sk-wait-on! $owner $rule $premise
                  (sk-partial $owner $rule $concl $premises $remaining $keys)))))))))

;; A ground computation (for example arithmetic on bound statement terms)
;; binds its result before later premises are looked up.
(= (sk-cpu-step $partial $_acc $result)
   (let* (((sk-partial $owner $rule $concl $premises $remaining $keys) (copy_term $partial)))
      (case $remaining (
         ((cons (CPU $_fun $_args $res) $rest)
            (if (= $res $result)
               (sk-advance! (sk-partial $owner $rule $concl $premises $rest $keys))
               ()))
         ($_other ())))))

(= (sk-wait-on! $owner $rule $premise $waiter)
   (let* (($hash (sk-node-hash $premise))
          ($_wait (add-atom &sk_wait ($hash $premise $waiter)))
          ($_temp
             (if (>= $rule 1000000000)
                (let $_t (add-atom &sk_temp_waits ($hash $premise $waiter)) ())
                ()))
          ($_child (sk-add-child! $owner (copy_term $premise))))
      (fold-semidet (sk-extend-waiter-step $waiter) () (sk-answers $premise))))

(: sk-extend-waiter-step (-[semidet]-> SkeletonWaiter Atom SkeletonKey Atom))
(= (sk-extend-waiter-step $waiter $_acc $key) (sk-extend! (copy_term $waiter) $key))

(= (sk-extend! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
   (case $remaining (
      ((cons $premise $rest)
         (if (case $premise (
                ((CPU $_fun $args $_res) (= (sk-group $args) $key))
                (($type $kbctx $_proof $_tv)
                   (if (= (sk-key $type $kbctx) $key) (chainer-acyclic-term? $concl) false))))
            (sk-advance!
               (sk-partial $owner $rule $concl $premises $rest (cons $key $keys)))
            ()))
      ($_other ()))))

(: sk-row-present? (-[det]-> Number SkeletonKey Number SkeletonIdent Bool))
(= (sk-row-present? $khash $key $rhash $ident)
   (not (== (collapse (once (match &sk_row ($khash $stored $rhash (sk-row $stored-ident $_c $_p $_seq))
               (if (=alpha $stored $key)
                  (if (=alpha $stored-ident $ident) true (empty))
                  (empty)))))
            ())))

(= (sk-complete-row! $owner $rule $concl $premises $keys)
   (let* ((($type $kbctx $_proof $_tv) $concl)
          ($key (sk-key $type $kbctx))
          ($khash (index-hash $key))
          ($ident (sk-ident $rule $keys $key))
          ($rhash (index-hash $ident))
          ($local (>= $rule 1000000000)))
      (if (sk-row-present? $khash $key $rhash $ident)
         (sk-add-answer! $owner $key)
         (if (if $local true (sk-take-row!))
            (let* (($row (sk-row $ident $concl $premises (next-search-id sk_row_seq)))
                   ($_add (if (chainer-acyclic-term? $row) (add-atom &sk_row ($khash $key $rhash $row)) false))
                   ($_temp
                      (if $local
                         (let $_t (add-atom &sk_temp_rows ($khash $key $rhash $row)) ())
                         ()))
                   ($_uses (fold-semidet (sk-use-step $key) () $keys))
                   ($_dirty (sk-mark-dirty! $key)))
               (sk-add-answer! $owner $key))
            (let* (($hash (sk-node-hash $owner))
                   ($_deferred
                      (add-atom &sk_deferred ($hash (sk-deferred $owner $rule $concl $premises $keys)))))
               ())))))

(: sk-use-step (-[semidet]-> SkeletonKey Atom SkeletonKey Atom))
(= (sk-use-step $parent $_acc $key) (sk-add-use! $key $parent))

;; The budget counts expansions. New rows have their own allowance of ten per
;; step, so recursive rules cannot grow the skeleton without bound; a row found
;; after the allowance is spent waits in &sk_deferred for a later walk. Rows of
;; query-local rules are the query's own compiled scaffold and always fit.
(: sk-take! (-[det]-> CounterKey Bool))
(= (sk-take! $counter)
   (let $left (search-id-value $counter)
      (if (<= $left 0) false
         (progn (change-state! $counter (- $left 1)) true))))

(: sk-take-step! (-[det]-> Bool))
(= (sk-take-step!) (sk-take! sk_budget))

(: sk-take-row! (-[det]-> Bool))
(= (sk-take-row!) (sk-take! sk_row_budget))

;; Work left over by an earlier query waits with its node and resumes when a
;; later walk reaches that node, so it never spends an unrelated query's
;; budget: deferred rows are completed and parked deliveries are queued again.
(: sk-deferred-step (-[semidet]-> Atom SkeletonDeferred Atom))
(= (sk-deferred-step $_acc (sk-deferred $owner $rule $concl $premises $keys))
   (sk-complete-row! $owner $rule $concl $premises $keys))

(: sk-resume! (-[semidet]-> SkPattern Atom))
(= (sk-resume! $node)
   (let* (($hash (sk-node-hash $node))
          ($_deliveries
             (collapse (match &sk_parked ($hash (sk-delivery $owner $key))
                (if (=alpha $owner $node)
                   (let $_removed (remove-atom &sk_parked ($hash (sk-delivery $owner $key)))
                      (add-atom &sk_answer_queue (sk-delivery $owner $key)))
                   (empty)))))
          ($deferred
             (collapse (match &sk_deferred ($hash (sk-deferred $owner $rule $concl $premises $keys))
                (if (=alpha $owner $node)
                   (let $_removed
                      (remove-atom &sk_deferred ($hash (sk-deferred $owner $rule $concl $premises $keys)))
                      (sk-deferred $owner $rule $concl $premises $keys))
                   (empty))))))
      (fold-semidet sk-deferred-step () $deferred)))

(: sk-park-step (-[det]-> Atom SkeletonDelivery Atom))
(= (sk-park-step $_acc (sk-delivery $node $key))
   (let* (($hash (sk-node-hash $node))
          ($_row (add-atom &sk_parked ($hash (sk-delivery $node $key)))))
      ()))

(: sk-park-deliveries! (-[semidet]-> Atom))
(= (sk-park-deliveries!)
   (let $entries
      (collapse (match &sk_answer_queue (sk-delivery $node $key)
         (let $_removed (remove-atom &sk_answer_queue (sk-delivery $node $key))
            (sk-delivery $node $key))))
      (fold-semidet sk-park-step () $entries)))

;; --- Expansion --------------------------------------------------------------

(: rule-lookup-needs-occurs-check (-[det]-> Atom Bool))
(: ccls-index-occurs-matches
   (-[det]-> Atom (List (SkFact Number (List SkPattern)))))

;; Preserve the complete conclusion shape during lookup so SWI's deep index can
;; discriminate arguments. A goal that repeats a variable unifies under an
;; occurs check: an exists witness term embeds the variable it witnesses for.
(: sk-rule-match (-[nondet]-> SkFact SkeletonMatch))
(= (sk-rule-match $goal)
   (let $lookup-goal (copy_term $goal)
      (if (rule-lookup-needs-occurs-check $lookup-goal)
         (let* (($matches (ccls-index-occurs-matches $lookup-goal))
                (($matched-goal $rule-id $args) (superpose $matches)))
            (if (= $matched-goal $goal)
               (sk-match $rule-id (contextualize-rule-args $goal $args) $goal)
               (empty)))
         (match ccls_index ($lookup-goal $rule-id $args)
            (if (= $lookup-goal $goal)
               (sk-match $rule-id (contextualize-rule-args $goal $args) $goal)
               (empty))))))

;; Both arguments come from destructuring a premise and its erased KBContext,
;; so they arrive as raw terms: a statement and Nil or a variable list.
(: context-vars-in-type? (-[det]-> Atom Atom Bool))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false (sk-any-member? (extract-vars $type) $vars)))

(: sk-any-member? (-[det]-> (List Variable) Atom Bool))
(= (sk-any-member? $_type-vars ()) false)
(= (sk-any-member? $type-vars (cons $var $rest))
   (if (stored-list-member? $var $type-vars) true (sk-any-member? $type-vars $rest)))

;; A MAIN premise that mentions the goal's context variables is read in the
;; goal's hypothetical context.
(: contextualize-rule-premise (-[det]-> SkFact SkPattern SkPattern))
(= (contextualize-rule-premise ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv) $premise)
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (let $fact-kb
               (if (if (== $prem-ctx MAIN)
                      (if (== $ctx MAIN) false (context-vars-in-type? $type $vars))
                      false)
                  (make-kb-context (brand KB $kbid) $ctx $vars)
                  (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars))
               (assemble-stored-runtime-fact $type $fact-kb $prf $tv)))
         ((CPU $fun $args $res) (CPU $fun $args $res))))))

(: contextualize-rule-args (-[semidet]-> SkFact (List SkPattern) (List SkPattern)))
(= (contextualize-rule-args $goal $args)
   (map-semidet (contextualize-rule-premise $goal) $args))

;; Walk a copy of a candidate rule's premises before any skeleton state is
;; created: a ground fact premise with no matching fact that no rule concludes
;; prunes the rule; ground deterministic computations run so later premises
;; become checkable.
(: prefilter-head-concludable? (-[det]-> Statement Atom Bool))
(= (prefilter-head-concludable? $type $kbid)
   (let $lookup-type (copy_term $type)
      (not (== (collapse (once (match ccls_index
                  (($lookup-type ($kbid $_stored-ctx $_stored-vars) $_stored-proof $_stored-tv)
                   $_rule-id $_stored-args)
                  true)))
               ()))))

(: prefilter-premise-blocks? (-[det]-> SkPattern Bool))
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (aggregate-fold-function? $fun) false
               (if (if (is-var $fun) false (== (extract-vars $args) ()))
                  (case (collapse (cpu-call 0 $fun $args)) (
                     (() true)
                     ((cons $result $_rest) (if (= $res $result) false true))))
                  false)))
         (($type ($kbid $_ctx $_vars) $_prf $_tv)
            (if (== (extract-vars $type) ())
               (if (== (collapse (once (match &kb ($type ($kbid $_c2 $_v2) $_p2 $_t2) true))) ())
                  (not (prefilter-head-concludable? $type $kbid))
                  false)
               false))))))

(: prefilter-prunes-walk (-[det]-> (List SkPattern) Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (prefilter-prunes-walk (copy_term $premises)) ()
      (sk-advance! (sk-partial $owner $rule $goal $premises $premises ()))))

(: sk-leaf-answer-step (-[semidet]-> SkPattern Atom SkFact Atom))
(= (sk-leaf-answer-step $node $_acc $fact) (sk-add-answer! $node (sk-fact-key $fact)))

;; Install only the empirical Member producer for a concrete Inheritance
;; subgoal, and the compiled scaffold of a nested implication subgoal that is
;; not itself a compiled total-implication source.
(: inject-special-subgoal-query-adds (-[semidet]-> Statement KBContext Proof TV Atom))
(= (inject-special-subgoal-query-adds $type $kbctx $prf $tv)
   (case $kbctx (
      (($kbid MAIN Nil)
         (if (implication-type? $type)
            (case $prf (
               ((total-implication-frontier $_inner) ())
               ($_other
                  (foreach-flat inject-compiled-query-adds
                     (collapse (mm2compileQuery (brand KB $kbid) (: $prf $type $tv)))))))
            (case $type (
               ((Inheritance $subj $concept)
                  (if (concrete-inheritance-link? $subj $concept)
                     (once
                        (inject-compiled-adds
                           (map-flat mm2stmt
                              (compile-member-inheritance-query-adds
                                 (brand KB $kbid) (brand Term $subj) (brand Term $concept)))))
                     ()))
               ($_other ())))))
      ($_other ()))))

(: inject-compiled-query-adds (-[semidet]-> CompiledQuery Atom))
(= (inject-compiled-query-adds (compiled-query $_goal $adds))
   (if (is-var $adds) (empty) (once (inject-compiled-adds $adds))))

;; The fold's source goal is compiled as an ordinary query; its additions are
;; query-local rules.
(: sk-fold-member (-[semidet]-> $arguments (List SkPattern)))
(= (sk-fold-member $args)
   (let* (($kb (brand KB (car-atom $args)))
          ($pattern (brand Statement (car-atom (cdr-atom $args)))))
      (case (collapse (once (mm2compileQuery $kb (: $_h $pattern $_i)))) (
         ((cons (compiled-query $goal $adds) $_rest)
            (if (if (is-var $goal) true (is-var $adds)) ()
               (let $_ (once (inject-compiled-adds $adds))
                  (cons (typed-runtime-premise $goal) ()))))
         ($_none ())))))

(= (sk-expand! $node $depth)
   (case $node (
      ((CPU $_fun $args $_res)
         (let* (($_mark (sk-mark-expanded! $node))
                ($members (sk-fold-member $args))
                ($_activate (sk-activate-pending!)))
            (case $members (
               (() ())
               ((cons $member $_rest)
                  (let* (($node-hash (sk-node-hash $node))
                         ($member-hash (sk-node-hash $member))
                         ($_fold (add-atom &sk_fold ($node-hash $node $member)))
                         ($_member-of (add-atom &sk_member_of ($member-hash $member $node)))
                         ($_child (sk-add-child! $node $member)))
                     (fold-semidet (sk-fold-answer-step $node) () (sk-answers $member))))))))
      (($type $kbctx $proof $tv)
         (let* (($_special
                   (if (> $depth 0) (inject-special-subgoal-query-adds $type $kbctx $proof $tv) ()))
                ($_activate (sk-activate-pending!))
                ($_mark (sk-mark-expanded! $node))
                ($_leaves
                   (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $type $kbctx $proof $tv)))
                ($owner (copy_term $node))
                ($matches (collapse (sk-rule-match (copy_term (assemble-stored-runtime-fact $type $kbctx $proof $tv))))))
            (fold-semidet (sk-start-rule-step $owner) () $matches))))))

(: sk-fold-answer-step (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-fold-answer-step $fold $acc $key) (sk-member-step $key $acc $fold))

;; --- Activation of facts and rules added after expansion --------------------

;; The expanded fact patterns a statement could match: those with its head
;; and those with an open head.
(: sk-nodes-with-head (-[semidet]-> Statement (List SkPattern)))
(= (sk-nodes-with-head $type)
   (let $head (sk-type-head $type)
      (if (== $head sk-any)
         (collapse (match &sk_node_head ($_head $pattern) $pattern))
         (fold-semidet sk-cons-step
            (collapse (match &sk_node_head (sk-any $pattern) $pattern))
            (collapse (match &sk_node_head ($head $pattern) $pattern))))))

(= (sk-activate-pending!)
   (let* (($rules
             (collapse (match &sk_pending_rules (sk-pending-rule $id)
                (let $_removed (remove-atom &sk_pending_rules (sk-pending-rule $id)) $id))))
          ($facts
             (collapse (match &sk_pending_facts (sk-pending-fact $key)
                (let $_removed (remove-atom &sk_pending_facts (sk-pending-fact $key)) $key))))
          ($_rules (fold-semidet sk-activate-rule-step () $rules)))
      (fold-semidet sk-activate-fact-step () $facts)))

(: sk-activate-rule-step (-[semidet]-> Atom Number Atom))
(= (sk-activate-rule-step $_acc $id)
   (fold-semidet (sk-activate-rule-row $id) ()
      (collapse (match rules (runtime-rule-row $id $ccls $args) (sk-rule-def $ccls $args)))))

(: sk-activate-fact-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-activate-fact-step $_acc $key)
   (case $key (
      ((sk-key $type $_kbctx)
         (fold-semidet (sk-activate-fact-on $key) () (sk-nodes-with-head $type)))
      ($_fold ()))))

(: sk-activate-rule-row (-[semidet]-> Number Atom SkeletonRuleDef Atom))
(= (sk-activate-rule-row $id $_acc (sk-rule-def $conclusion $args))
   (let* ((($type $_kbctx $_proof $_tv) $conclusion))
      (fold-semidet (sk-activate-rule-on $id $conclusion $args) ()
         (sk-nodes-with-head $type))))

(: sk-activate-rule-on (-[semidet]-> Number SkFact (List SkPattern) Atom SkPattern Atom))
(= (sk-activate-rule-on $id $ccls $args $_acc $node)
   (let* (($goal (copy_term $node))
          ((sk-rule-def $conclusion $premises) (copy_term (sk-rule-def $ccls $args))))
      (if (= $conclusion $goal)
         (if (chainer-acyclic-term? $conclusion)
            (sk-start-rule-step $node ()
               (sk-match $id (contextualize-rule-args $conclusion $premises) $conclusion))
            ())
         ())))

(: sk-activate-fact-on (-[semidet]-> SkeletonKey Atom SkPattern Atom))
(= (sk-activate-fact-on $key $_acc $node)
   (case (copy_term $node) (
      (($type $kbctx $proof $tv)
         (if (= (sk-key $type $kbctx) (copy_term $key))
            (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $type $kbctx $proof $tv))
            ()))
      ($_cpu ()))))

;; --- Budgeted search walk ---------------------------------------------------

;; Breadth-first from the roots over child links. Walking an expanded node is
;; free; expanding a new node costs one step. Increasing the budget extends
;; the same deterministic order.
(: sk-children (-[det]-> SkPattern (List SkPattern)))
(= (sk-children $node)
   (let $hash (sk-node-hash $node)
      (collapse (match &sk_child ($hash $stored $child)
         (if (=alpha $stored $node) $child (empty))))))

(: sk-seen! (-[det]-> SkPattern Bool))
(= (sk-seen! $node)
   (let $hash (sk-node-hash $node)
      (if (== (collapse (once (match &sk_seen ($hash $stored)
                 (if (=alpha $stored $node) true (empty)))))
              ())
         (let $_row (add-atom &sk_seen ($hash $node)) false)
         true)))

;; Joins extended after their owner was walked link new children to it; the
;; walk picks those up from &sk_fresh at the next level.
(: sk-take-fresh! (-[det]-> (List SkPattern)))
(= (sk-take-fresh!)
   (collapse (match &sk_fresh (sk-fresh $node)
      (let $_removed (remove-atom &sk_fresh (sk-fresh $node)) $node))))

;; The current level is walked in order; children are collected, newest
;; first, into the next level, which is reversed when the level is done.
;; Roots are depth 0: their compiled scaffolding was installed by the query.
(= (sk-search! $depth $level $next)
   (case $level (
      (()
         (let* (($_drained (sk-drain!))
                ($level-next (fold-semidet sk-cons-step $next (sk-take-fresh!))))
            (if (== $level-next ()) ()
               (sk-search! (+ $depth 1) (fold-semidet sk-cons-step () $level-next) ()))))
      ((cons $node $rest)
         (let $_drained (sk-drain!)
            (if (sk-seen! $node)
               (sk-search! $depth $rest $next)
               (if (sk-expanded? $node)
                  (let $_resumed (sk-resume! $node)
                     (sk-search! $depth $rest (fold-semidet sk-cons-step $next (sk-children $node))))
                  (if (sk-take-step!)
                     (let $_expand (sk-expand! $node $depth)
                        (sk-search! $depth $rest
                           (fold-semidet sk-cons-step $next (sk-children $node))))
                     (sk-drain!)))))))))

;; Query-local rules leave with their query: their rows, waiters and deferred
;; rows are removed and every value that read one of those rows goes stale.
(: sk-clear-temp! (-[semidet]-> Atom))
(= (sk-clear-temp!)
   (let* (($_deferred
             (collapse (match &sk_deferred ($h (sk-deferred $o $rule $c $p $k))
                (if (>= $rule 1000000000)
                   (remove-atom &sk_deferred ($h (sk-deferred $o $rule $c $p $k)))
                   (empty)))))
          ($_waits
             (collapse (match &sk_temp_waits ($hash $pattern $waiter)
                (let $_temp (remove-atom &sk_temp_waits ($hash $pattern $waiter))
                   (remove-atom &sk_wait ($hash $pattern $waiter))))))
          ($keys
             (collapse (match &sk_temp_rows ($khash $key $rhash $row)
                (let* (($_temp (remove-atom &sk_temp_rows ($khash $key $rhash $row)))
                       ($_row (remove-atom &sk_row ($khash $key $rhash $row))))
                   $key)))))
      (fold-semidet sk-dirty-step () $keys)))

(: sk-dirty-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-dirty-step $_acc $key) (sk-mark-dirty! $key))
