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

(: SkeletonWaiter Type)
;; owner-pattern rule-id conclusion premises remaining-premises premise-keys
(: sk-partial (-[det]-> Atom Atom Atom Atom Atom Atom SkeletonWaiter))
(: SkeletonTemp Type)
(: sk-temp-row (-[det]-> Atom SkeletonTemp))
(: sk-temp-wait (-[det]-> Atom SkeletonTemp))
(: sk-any Atom)

;; The loader rejects the effect-polymorphic library folds inside semidet
;; bodies, so the skeleton keeps its own semidet fold and map.
(: fold-semidet
   (-[semidet]-> (-[semidet]-> $acc $item $acc) $acc %Undefined% $acc))
(= (fold-semidet $_fun $acc ()) $acc)
(= (fold-semidet $fun $acc (cons $item $rest))
   (fold-semidet $fun ($fun $acc $item) $rest))

(: map-semidet
   (-[semidet]-> (-[semidet]-> $input $output) %Undefined% Atom))
(= (map-semidet $_fun ()) ())
(= (map-semidet $fun (cons $item $rest))
   (cons ($fun $item) (map-semidet $fun $rest)))

(: sk-cons-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-cons-step $acc $item) (cons $item $acc))

(: stored-list-member? (-[det]-> Atom Atom Bool))
(= (stored-list-member? $needle $values)
   (case $values (
      (() false)
      ((cons $first $rest)
         (if (== $needle $first) true (stored-list-member? $needle $rest)))
      ($_other false))))

(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (or (== $function FoldAllCompiled) (== $function GroupedFoldAllCompiled)))

;; Signatures of the mutually recursive functions below.
(: sk-add-answer! (-[semidet]-> %Undefined% %Undefined% Atom))
(: sk-drain! (-[semidet]-> Atom))
(: sk-extend-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-member-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-add-group-of! (-[det]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-advance! (-[semidet]-> %Undefined% Atom))
(: sk-cpu-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-wait-on! (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(: sk-extend-step-waiter (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-extend! (-[semidet]-> %Undefined% %Undefined% Atom))
(: sk-complete-row! (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(: sk-use-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-start-rule-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-activate-pending! (-[semidet]-> Atom))
(: sk-activate-step (-[semidet]-> %Undefined% %Undefined% Atom))
(: sk-activate-rule-row (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-activate-rule-on (-[semidet]-> %Undefined% %Undefined% %Undefined% %Undefined% %Undefined% Atom))
(: sk-activate-fact-on (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-leaf-answer-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-fold-answer-step (-[semidet]-> %Undefined% %Undefined% %Undefined% Atom))
(: sk-expand! (-[semidet]-> %Undefined% Number Atom))
(: sk-search! (-[semidet]-> Number %Undefined% %Undefined% Atom))
(: sk-clear-temp-step (-[semidet]-> %Undefined% %Undefined% Atom))

;; --- Node identity ----------------------------------------------------------

(: sk-node-hash (-[det]-> %Undefined% Number))
(= (sk-node-hash $pattern)
   (case $pattern (
      ((CPU $_fun $args $_res) (index-hash $args))
      (($type $kbctx $_proof $_tv) (index-hash (sk-key $type $kbctx))))))

(: sk-type-head (-[det]-> %Undefined% Atom))
(= (sk-type-head $type)
   (if (is-var $type) sk-any
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) sk-any $head))
         $type)))

(: sk-expanded? (-[det]-> %Undefined% Bool))
(= (sk-expanded? $pattern)
   (let $hash (sk-node-hash $pattern)
      (not (== (collapse (once (match &sk_expanded ($hash $stored)
                  (if (=alpha $stored $pattern) true (empty)))))
               ()))))

(: sk-mark-expanded! (-[det]-> %Undefined% Atom))
(= (sk-mark-expanded! $pattern)
   (let* (($hash (sk-node-hash $pattern))
          ($_row (add-space-atom! &sk_expanded (make-space-pair $hash $pattern))))
      (case $pattern (
         ((CPU $_fun $_args $_res) ())
         (($type $_kbctx $_proof $_tv)
            (let $head (sk-type-head $type)
               (let $_head (add-space-atom! &sk_node_head (make-space-pair $head $pattern))
                  ())))))))

(: sk-answers (-[det]-> %Undefined% Atom))
(= (sk-answers $pattern)
   (let $hash (sk-node-hash $pattern)
      (collapse (match &sk_answer ($hash $stored $key)
         (if (=alpha $stored $pattern) $key (empty))))))

(: sk-add-child! (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-add-child! $owner $child)
   (if (sk-link-new! child $owner $child)
      (let* (($_row (add-space-atom! &sk_child (make-space-row3 (sk-node-hash $owner) $owner $child)))
             ($_fresh (add-atom &sk_fresh (sk-fresh $child))))
         ())
      ()))

;; Child links, answers and use edges are each recorded once. A hash of the
;; whole link makes that check one lookup instead of a scan over every link of
;; the same source.
(: sk-link-new! (-[det]-> %Undefined% %Undefined% %Undefined% Bool))
(= (sk-link-new! $kind $from $to)
   (let* (($link (quote ($kind $from $to)))
          ($hash (index-hash $link)))
      (if (== (collapse (once (match &sk_link ($hash $stored)
                 (if (=alpha $stored $link) true (empty)))))
              ())
         (let $_row (add-space-atom! &sk_link (make-space-pair $hash $link)) true)
         false)))

;; --- Leaves -----------------------------------------------------------------

;; Materialized facts are forward rows marked in &materialized_facts. They are
;; never leaves: the backward chainer re-derives them.
(: MaterializedRow Type)
(: materialized-row
   (-[det]-> Number Statement KBContext (Statement KBContext Proof TV)
       (List Evidence) MaterializedRow))
(: materialized-forward-fact? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (materialized-forward-fact? ($type $kb $proof $tv))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (space-row-present? &materialized_facts
         (materialized-row $hash $type $kb ($type $kb $proof $tv) $_ev))))

;; Every fact matching the goal pattern; the probe for materialized rows runs
;; only when some materialization happened.
(: sk-leaf-facts (-[semidet]-> %Undefined% Atom))
(= (sk-leaf-facts $goal)
   (let* ((($type $kbctx $proof $tv) (copy_term $goal))
          ($plain (not (sk-space-nonempty? &materialized_facts))))
      (collapse (match &kb (@ $fact ($type $kbctx $proof $tv))
         (if (chainer-acyclic-term? $fact)
            (if $plain $fact
               (if (materialized-forward-fact? $fact) (empty) $fact))
            (empty))))))

(: sk-fact-key (-[det]-> %Undefined% Atom))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))

;; --- Answers and delivery ---------------------------------------------------

(= (sk-add-answer! $node $key)
   (let $hash (sk-node-hash $node)
      (if (not (sk-link-new! answer $node $key)) ()
         (let* (($_row (add-space-atom! &sk_answer (make-space-row3 $hash $node $key)))
                ($folds
                   (collapse (match &sk_member_of ($hash $stored $fold)
                      (if (=alpha $stored $node) $fold (empty)))))
                ($_members (fold-semidet (sk-member-step $key) () $folds))
                ($_queued (add-atom &sk_answer_queue (sk-delivery $node $key))))
            ()))))

;; Deliveries run in the order answers were found, so derivations grow level
;; by level and a budget cut keeps the shallow ones.
(= (sk-drain!)
   (case (collapse (once (match &sk_answer_queue $entry $entry))) (
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

(: sk-add-use! (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-add-use! $key $parent)
   (if (sk-link-new! use $key $parent)
      (let $_row (add-space-atom! &sk_use (make-space-row3 (index-hash $key) $key $parent)) ())
      ()))

(: sk-mark-dirty! (-[det]-> %Undefined% Atom))
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
      ((CPU GroupedFoldAllCompiled $args $_res)
         (let* (($unbound (copy_term $args))
                (($kbctx $pattern $group $_extractor $_init $_fun $_finish $_mode)
                   (copy_term $args))
                ($grouped
                   (if (= (sk-key $pattern $kbctx) $key)
                      (let* ((($_c $_p $unbound-group $_e $_i $_f $_fi $_m) $unbound)) (if (= $unbound-group $group) true false))
                      false)))
            (if $grouped
               (let* (($group-key (sk-group $unbound))
                      ($group-hash (index-hash $group-key))
                      ($_group-of (sk-add-group-of! $group-hash $group-key $fold))
                      ($_use (sk-add-use! $key $group-key))
                      ($_dirty (sk-mark-dirty! $group-key)))
                  (sk-add-answer! $fold $group-key))
               ())))
      ($_other ()))))

(= (sk-add-group-of! $hash $group-key $fold)
   (if (== (collapse (once (match &sk_group_of ($hash $stored $_fold)
              (if (=alpha $stored $group-key) true (empty)))))
           ())
      (let $_row (add-space-atom! &sk_group_of (make-space-row3 $hash $group-key $fold)) ())
      ()))

;; --- Partial joins and rows -------------------------------------------------

(= (sk-advance! (sk-partial $owner $rule $concl $premises $remaining $keys))
   (case $remaining (
      (() (sk-complete-row! $owner $rule $concl $premises $keys))
      ((cons $premise $rest)
         (case $premise (
            ((CPU $fun $args $res)
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
   (let* (((sk-partial $owner $rule $concl $premises (cons (CPU $_fun $_args $res) $rest) $keys) (copy_term $partial)))
      (if (= $res $result)
         (sk-advance! (sk-partial $owner $rule $concl $premises $rest $keys))
         ())))

(= (sk-wait-on! $owner $rule $premise $waiter)
   (let* (($hash (sk-node-hash $premise))
          ($row (make-space-row3 $hash $premise $waiter))
          ($_wait (add-atom &sk_wait $row))
          ($_temp
             (if (>= (the Number $rule) 1000000000)
                (let $_t (add-atom &sk_temp (sk-temp-wait $row)) ())
                ()))
          ($_child (sk-add-child! $owner (copy_term $premise))))
      (fold-semidet (sk-extend-step-waiter $waiter) () (sk-answers $premise))))

(= (sk-extend-step-waiter $waiter $_acc $key) (sk-extend! (copy_term $waiter) $key))

(= (sk-extend! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
   (case $remaining (
      ((cons $premise $rest)
         (if (case $premise (
                ((CPU $_fun $args $_res) (= (sk-group $args) $key))
                (($type $kbctx $_proof $_tv)
                   (if (= (sk-key $type $kbctx) $key) (chainer-acyclic-term? $concl) false))))
            (sk-advance!
               (sk-partial $owner $rule $concl $premises $rest
                  (cons $key $keys)))
            ()))
      ($_other ()))))

(: sk-row-present? (-[det]-> %Undefined% %Undefined% %Undefined% %Undefined% Bool))
(= (sk-row-present? $khash $key $rhash $ident)
   (not (== (collapse (once (match &sk_row ($khash $stored $rhash ($stored-ident $_c $_p $_seq))
               (if (=alpha $stored $key)
                  (if (=alpha $stored-ident $ident) true (empty))
                  (empty)))))
            ())))

(= (sk-complete-row! $owner $rule $concl $premises $keys)
   (let* ((($type $kbctx $_proof $_tv) $concl)
          ($key (sk-key $type $kbctx))
          ($khash (index-hash $key))
          ($ident (quote ($rule $keys $key)))
          ($rhash (index-hash $ident)))
      (if (sk-row-present? $khash $key $rhash $ident)
         (sk-add-answer! $owner $key)
         (if (if (>= (the Number $rule) 1000000000) true (sk-take-row!))
            (let* (($seq (next-search-id sk_row_seq))
                   ($body (quote ($ident $concl $premises $seq)))
                   ($row (make-space-row4 $khash $key $rhash $body))
                   ($_add (collapse (once (chainer-add-atom &sk_row $row))))
                   ($_temp
                      (if (>= (the Number $rule) 1000000000)
                         (let $_t (add-atom &sk_temp (sk-temp-row $row)) ())
                         ()))
                   ($_uses (fold-semidet (sk-use-step $key) () $keys))
                   ($_dirty (sk-mark-dirty! $key)))
               (sk-add-answer! $owner $key))
            (let $_deferred
               (add-space-atom! &sk_deferred
                  (make-space-pair (sk-node-hash $owner) (sk-deferred $owner $rule $concl $premises $keys)))
               ())))))

;; The budget counts expansions. New rows have their own allowance of ten per
;; step, so recursive rules cannot grow the skeleton without bound; a row found
;; after the allowance is spent waits in &sk_deferred for a later walk. Rows of
;; query-local rules are the query's own compiled scaffold and always fit.
(: sk-take-step! (-[det]-> Bool))
(= (sk-take-step!) (sk-take! sk_budget))

(: sk-take-row! (-[det]-> Bool))
(= (sk-take-row!) (sk-take! sk_row_budget))

(: sk-take! (-[det]-> CounterKey Bool))
(= (sk-take! $counter)
   (let $left (search-id-value $counter)
      (if (<= $left 0) false
         (progn (change-state! $counter (- $left 1)) true))))

(: sk-complete-deferred! (-[semidet]-> %Undefined% Atom))
(= (sk-complete-deferred! $node)
   (let* (($hash (sk-node-hash $node))
          ($entries
             (collapse (match &sk_deferred ($hash (sk-deferred $owner $rule $concl $premises $keys))
                (if (=alpha $owner $node)
                   (let $entry (make-space-pair $hash (sk-deferred $owner $rule $concl $premises $keys))
                      (let $_removed (remove-atom &sk_deferred $entry)
                         (sk-deferred $owner $rule $concl $premises $keys)))
                   (empty))))))
      (fold-semidet sk-deferred-step () $entries)))

(: sk-deferred-step (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-deferred-step $_acc (sk-deferred $owner $rule $concl $premises $keys))
   (sk-complete-row! $owner $rule $concl $premises $keys))

;; Work left over by an earlier query waits with its node and resumes when a
;; later walk reaches that node, so it never spends an unrelated query's
;; budget: deferred rows are completed and parked deliveries are queued again.
(: sk-park-deliveries! (-[semidet]-> Atom))
(= (sk-park-deliveries!)
   (let $entries
      (collapse (match &sk_answer_queue (sk-delivery $node $key)
         (let $_removed (remove-atom &sk_answer_queue (sk-delivery $node $key))
            (sk-delivery $node $key))))
      (fold-semidet sk-park-step () $entries)))

(: sk-park-step (-[det]-> %Undefined% %Undefined% Atom))
(= (sk-park-step $_acc (sk-delivery $node $key))
   (let $_row (add-space-atom! &sk_parked (make-space-pair (sk-node-hash $node) (sk-delivery $node $key))) ()))

(: sk-resume! (-[semidet]-> %Undefined% Atom))
(= (sk-resume! $node)
   (let* (($hash (sk-node-hash $node))
          ($_deliveries
             (collapse (match &sk_parked ($hash (sk-delivery $owner $key))
                (if (=alpha $owner $node)
                   (let* (($entry (make-space-pair $hash (sk-delivery $owner $key)))
                          ($_removed (remove-atom &sk_parked $entry)))
                      (add-atom &sk_answer_queue (sk-delivery $owner $key)))
                   (empty))))))
      (sk-complete-deferred! $node)))

(= (sk-use-step $parent $_acc $key) (sk-add-use! $key $parent))

;; --- Expansion --------------------------------------------------------------

(: rule-lookup-needs-occurs-check (-[det]-> Atom Bool))
(: ccls-index-occurs-matches (-[det]-> Atom (List Atom)))

;; Preserve the complete conclusion shape during lookup so SWI's deep index can
;; discriminate arguments. A goal that repeats a variable unifies under an
;; occurs check: an exists witness term embeds the variable it witnesses for.
(: sk-rule-match (-[nondet]-> %Undefined% Atom))
(= (sk-rule-match $goal)
   (let $lookup-goal (copy_term $goal)
      (if (rule-lookup-needs-occurs-check $lookup-goal)
         (let $matches (ccls-index-occurs-matches $lookup-goal)
            (let* ((($matched-goal $rule-id $args) (superpose $matches)))
               (if (= $matched-goal $goal)
                  (data $rule-id (contextualize-rule-args $goal $args) $goal)
                  (empty))))
         (match ccls_index ($lookup-goal $rule-id $args)
            (if (= $lookup-goal $goal)
               (data $rule-id (contextualize-rule-args $goal $args) $goal)
               (empty))))))

(: context-vars-in-type? (-[det]-> %Undefined% %Undefined% Bool))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false
      (let $type-vars (extract-vars $type)
         (sk-any-member? $type-vars $vars))))

(: sk-any-member? (-[det]-> %Undefined% %Undefined% Bool))
(= (sk-any-member? $_type-vars ()) false)
(= (sk-any-member? $type-vars (cons $var $rest))
   (if (stored-list-member? $var $type-vars) true (sk-any-member? $type-vars $rest)))

;; A MAIN premise that mentions the goal's context variables is read in the
;; goal's hypothetical context.
(: contextualize-rule-premise (-[det]-> %Undefined% %Undefined% Atom))
(= (contextualize-rule-premise ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv) $premise)
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (if (if (== $prem-ctx MAIN)
                   (if (== $ctx MAIN) false (context-vars-in-type? $type $vars))
                   false)
               (let $fact-kb (make-kb-context (brand KB $kbid) $ctx $vars)
                  (assemble-stored-runtime-fact $type $fact-kb $prf $tv))
               (let $fact-kb (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars)
                  (assemble-stored-runtime-fact $type $fact-kb $prf $tv))))
         ((CPU $fun $args $res) (CPU $fun $args $res))))))

(: contextualize-rule-args (-[semidet]-> %Undefined% %Undefined% Atom))
(= (contextualize-rule-args $goal $args)
   (map-semidet (contextualize-rule-premise $goal) $args))

;; Walk a copy of a candidate rule's premises before any skeleton state is
;; created: a ground fact premise with no matching fact that no rule concludes
;; prunes the rule; ground deterministic computations run so later premises
;; become checkable.
(: prefilter-head-concludable? (-[det]-> %Undefined% Bool))
(= (prefilter-head-concludable? $prem)
   (case $prem (
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (let $lookup-type (copy_term $type)
            (not (== (collapse (once (match ccls_index
                        (($lookup-type ($kbid $_stored-ctx $_stored-vars) $_stored-proof $_stored-tv)
                         $_rule-id $_stored-args)
                        true)))
                     ()))))
      ($_other true))))

(: prefilter-premise-blocks? (-[det]-> %Undefined% Bool))
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (aggregate-fold-function? $fun) false
               (if (if (is-var $fun) false (== (extract-vars $args) ()))
                  (let $hits (collapse (cpu-call 0 $fun $args))
                     (if (== $hits ()) true
                        (if (= $res (car-atom $hits)) false true)))
                  false)))
         (($type ($kbid $ctx $vars) $prf $tv)
            (if (== (extract-vars $type) ())
               (if (== (collapse (once (match &kb ($type ($kbid $_c2 $_v2) $_p2 $_t2) true))) ())
                  (let* (($fact-kb (make-kb-context $kbid $ctx $vars))
                         ($fact (assemble-stored-runtime-fact $type $fact-kb $prf $tv)))
                     (not (prefilter-head-concludable? $fact)))
                  false)
               false))))))

(: prefilter-prunes-walk (-[det]-> %Undefined% Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

(: rule-premise-prefilter-prunes? (-[det]-> %Undefined% Bool))
(= (rule-premise-prefilter-prunes? $args)
   (let $hits (collapse (prefilter-prunes-walk (copy_term $args)))
      (if (== $hits ()) false (car-atom $hits))))

(= (sk-start-rule-step $owner $_acc $match)
   (let* ((($rule $premises $goal) $match))
      (if (rule-premise-prefilter-prunes? $premises) ()
         (sk-advance! (sk-partial $owner $rule $goal $premises $premises ())))))

(= (sk-leaf-answer-step $node $_acc $fact) (sk-add-answer! $node (sk-fact-key $fact)))

;; Install only the empirical Member producer for a concrete Inheritance
;; subgoal, and the compiled scaffold of a nested implication subgoal.
(: inject-special-subgoal-query-adds (-[semidet]-> %Undefined% Atom))
(= (inject-special-subgoal-query-adds $goal)
   (case $goal (
      (($type ($kbid MAIN Nil) $prf $tv)
         (if (implication-type? (brand Statement $type))
            (if (if (is-expr $prf)
                   (if (== (list-len (the (List Atom) $prf)) 2)
                      (== (car-atom $prf) total-implication-frontier)
                      false)
                   false)
               ()
               (let $compiled-queries
                  (collapse (mm2compileQuery (brand KB $kbid) (: $prf $type $tv)))
                  (foreach-flat inject-compiled-query-adds $compiled-queries)))
            (if (= $type (Inheritance $subj $concept))
               (if (concrete-inheritance-link? (brand Term $subj) (brand Term $concept))
                  (once
                     (inject-compiled-adds
                        (map-flat mm2stmt
                           (compile-member-inheritance-query-adds
                              (brand KB $kbid) (brand Term $subj) (brand Term $concept)))))
                  ())
               ())))
      ($_other ()))))

(: inject-compiled-query-adds (-[semidet]-> CompiledQuery Atom))
(= (inject-compiled-query-adds (compiled-query $_goal $adds))
   (if (is-var $adds) (empty) (once (inject-compiled-adds $adds))))

;; The fold's source goal is compiled as an ordinary query; its additions are
;; query-local rules.
(: sk-fold-member (-[nondet]-> %Undefined% Atom))
(= (sk-fold-member (CPU $_fun $args $_res))
   (let* (($kb (car-atom $args))
          ($pattern (car-atom (cdr-atom $args)))
          ((compiled-query $goal $adds)
             (the CompiledQuery (eval (mm2compileQuery (brand KB $kb) (: $_h $pattern $_i))))))
      (if (or (is-var $goal) (is-var $adds)) (empty)
         (let $_ (once (inject-compiled-adds $adds))
            (typed-runtime-premise $goal)))))

(= (sk-expand! $node $depth)
   (case $node (
      ((CPU $_fun $_args $_res)
         (let* (($_mark (sk-mark-expanded! $node))
                ($members (collapse (once (sk-fold-member $node))))
                ($_activate (sk-activate-pending!)))
            (case $members (
               (() ())
               ((cons $member $_rest)
                  (let* (($member-hash (sk-node-hash $member))
                         ($_fold (add-space-atom! &sk_fold
                                    (make-space-row3 (sk-node-hash $node) $node $member)))
                         ($_member-of (add-space-atom! &sk_member_of
                                         (make-space-row3 $member-hash $member $node)))
                         ($_child (sk-add-child! $node $member))
                         ($answers (sk-answers $member)))
                     (fold-semidet (sk-fold-answer-step $node) () $answers)))))))
      (($_type $_kbctx $_proof $_tv)
         (let* (($_special (if (> $depth 0) (inject-special-subgoal-query-adds $node) ()))
                ($_activate (sk-activate-pending!))
                ($_mark (sk-mark-expanded! $node))
                ($_leaves (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $node)))
                ($owner (copy_term $node))
                ($matches (collapse (sk-rule-match (copy_term $node)))))
            (fold-semidet (sk-start-rule-step $owner) () $matches))))))

(= (sk-fold-answer-step $fold $acc $key) (sk-member-step $key $acc $fold))

;; --- Activation of facts and rules added after expansion --------------------

(: sk-nodes-with-head (-[semidet]-> %Undefined% Atom))
(= (sk-nodes-with-head $head)
   (if (== $head sk-any)
      (collapse (match &sk_node_head ($_head $pattern) $pattern))
      (let* (($exact (collapse (match &sk_node_head ($head $pattern) $pattern)))
             ($open (collapse (match &sk_node_head (sk-any $pattern) $pattern))))
         (fold-semidet sk-cons-step $open $exact))))

(= (sk-activate-pending!)
   (let $pending
      (collapse (match &sk_pending $entry
         (let $_removed (remove-atom &sk_pending $entry) $entry)))
      (fold-semidet sk-activate-step () $pending)))

(= (sk-activate-step $_acc $entry)
   (case $entry (
      ((sk-pending-rule $id)
         (let $rows (collapse (match rules (runtime-rule-row $id $ccls $args) (quote ($ccls $args))))
            (fold-semidet (sk-activate-rule-row $id) () $rows)))
      ((sk-pending-fact (sk-key $type $kbctx))
         (fold-semidet (sk-activate-fact-on (sk-key $type $kbctx)) ()
            (sk-nodes-with-head (sk-type-head $type))))
      ($_other ()))))

(= (sk-activate-rule-row $id $_acc $row)
   (let* ((($conclusion $args) $row)
          (($type $_kbctx $_proof $_tv) $conclusion))
      (fold-semidet (sk-activate-rule-on $id $conclusion $args) ()
         (sk-nodes-with-head (sk-type-head $type)))))

(= (sk-activate-rule-on $id $ccls $args $_acc $node)
   (let* (($goal (copy_term $node))
          (($conclusion $premises) (copy_term (quote ($ccls $args)))))
      (if (= $conclusion $goal)
         (if (chainer-acyclic-term? $goal)
            (sk-start-rule-step $node ()
               (data $id (contextualize-rule-args $goal $premises) $goal))
            ())
         ())))

(= (sk-activate-fact-on $key $_acc $node)
   (let* (($goal (copy_term $node))
          (($type $kbctx $_proof $_tv) $goal))
      (if (= (sk-key $type $kbctx) (copy_term $key))
         (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $goal))
         ())))

;; --- Budgeted search walk ---------------------------------------------------

;; Breadth-first from the roots over child links. Walking an expanded node is
;; free; expanding a new node costs one step. Increasing the budget extends
;; the same deterministic order.
(: sk-children (-[det]-> %Undefined% Atom))
(= (sk-children $node)
   (let $hash (sk-node-hash $node)
      (collapse (match &sk_child ($hash $stored $child)
         (if (=alpha $stored $node) $child (empty))))))

(: sk-seen! (-[det]-> %Undefined% Bool))
(= (sk-seen! $node)
   (let $hash (sk-node-hash $node)
      (if (== (collapse (once (match &sk_seen ($hash $stored)
                 (if (=alpha $stored $node) true (empty)))))
              ())
         (let $_row (add-space-atom! &sk_seen (make-space-pair $hash $node)) false)
         true)))

;; Joins extended after their owner was walked link new children to it; the
;; walk picks those up from &sk_fresh at the next level.
(: sk-take-fresh! (-[det]-> Atom))
(= (sk-take-fresh!)
   (collapse (match &sk_fresh (sk-fresh $node)
      (let $_removed (remove-atom &sk_fresh (sk-fresh $node)) $node))))

;; The current level is walked in order; children are collected, newest
;; first, into the next level, which is reversed when the level is done.
;; Roots are depth 0: their compiled scaffolding was installed by the query.
(: sk-enqueue (-[semidet]-> %Undefined% %Undefined% Atom))
(= (sk-enqueue $next $child) (cons $child $next))

(= (sk-search! $depth $level $next)
   (case $level (
      (()
         (let* (($_drained (sk-drain!))
                ($level-next (fold-semidet sk-enqueue $next (sk-take-fresh!))))
            (if (== $level-next ()) ()
               (sk-search! (+ $depth 1) (fold-semidet sk-enqueue () $level-next) ()))))
      ((cons $node $rest)
         (let $_drained (sk-drain!)
         (if (sk-seen! $node)
            (sk-search! $depth $rest $next)
            (if (sk-expanded? $node)
               (let $_resumed (sk-resume! $node)
                  (sk-search! $depth $rest (fold-semidet sk-enqueue $next (sk-children $node))))
               (if (sk-take-step!)
                  (let $_expand (sk-expand! $node $depth)
                     (sk-search! $depth $rest
                        (fold-semidet sk-enqueue $next (sk-children $node))))
                  (sk-drain!)))))))))

;; Query-local rules leave with their query: their rows and waiters are
;; removed and every value that read one of those rows goes stale.
(: sk-clear-temp! (-[semidet]-> Atom))
(= (sk-clear-temp!)
   (let* (($_deferred
             (collapse (match &sk_deferred ($h (sk-deferred $o $rule $c $p $k))
                (if (>= (the Number $rule) 1000000000)
                   (let $entry (make-space-pair $h (sk-deferred $o $rule $c $p $k))
                      (remove-atom &sk_deferred $entry))
                   (empty)))))
          ($entries
             (collapse (match &sk_temp $entry
                (let $_removed (remove-atom &sk_temp $entry) $entry)))))
      (fold-semidet sk-clear-temp-step () $entries)))

(= (sk-clear-temp-step $_acc $entry)
   (case $entry (
      ((sk-temp-row $row)
         (let* (($_removed (remove-atom &sk_row $row))
                (($_khash $key $_rhash $_body) $row))
            (sk-mark-dirty! $key)))
      ((sk-temp-wait $row)
         (let $_removed (remove-atom &sk_wait $row) ()))
      ($_other ()))))
