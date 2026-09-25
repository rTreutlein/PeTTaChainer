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
;; node, depth
(: SkeletonFrontier Type)
(: sk-frontier (-[det]-> SkPattern Number SkeletonFrontier))
(: sk-search! (-[semidet]-> (Heap SkeletonFrontier) Atom))

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

(: sk-node-score (-[det]-> SkPattern Number))
(= (sk-node-score $node)
   (let $hash (sk-node-hash $node)
      (case (collapse (once (match &sk_score ($hash $stored $score)
               (if (=alpha $stored $node) $score (empty))))) (
         ((cons $score $_rest) $score)
         (() 0.0)))))

(: sk-raise-score! (-[det]-> SkPattern Number Atom))
(= (sk-raise-score! $node $score)
   (let* (($hash (sk-node-hash $node))
          ($old (sk-node-score $node)))
      (if (> $score $old)
         (let* (($_removed
                   (collapse (match &sk_score ($hash $stored $old-score)
                      (if (=alpha $stored $node) (remove-atom &sk_score ($hash $stored $old-score)) (empty)))))
                ($_added (add-atom &sk_score ($hash $node $score))))
            ())
         ())))

;; A rule's expected confidence, computed when the rule was stored.
(: sk-rule-score (-[det]-> Number Number))
(= (sk-rule-score $rule)
   (case (collapse (once (match rule_expected ($rule $score) $score))) (
      ((cons $score $_rest) $score)
      (() 1.0))))

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
   (/ (* (sk-node-score $owner) (sk-rule-score $rule))
      (max 1 (fold-semidet sk-open-premise-step 0 $remaining))))

(: sk-add-child! (-[det]-> SkPattern SkPattern Number Atom))
(= (sk-add-child! $owner $child $score)
   (if (let $_scored (sk-raise-score! $child $score) (sk-link-new! (sk-child-link $owner $child)))
      (let* (($hash (sk-node-hash $owner))
             ($_row (add-atom &sk_child ($hash $owner $child)))
             ($_fresh (add-atom &sk_fresh (sk-fresh $child))))
         ())
      ()))

;; --- Base rates -------------------------------------------------------------

;; A base rate's estimate: a user base rate, or a cached one that an earlier
;; fold computed or forward chaining keeps. A base rate without one is seeded
;; from the facts already known when forward chaining can maintain it.
(: sk-rate-entries (-[semidet]-> $args (List BaseRateEntry)))
(= (sk-rate-entries $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
            (if (== $entries ())
               (if (forward-seed-fold! (CPU FoldAllCompiled $args $_result))
                  (base-rate-cache-entries-for-mode $kbid $pattern $mode)
                  ())
               $entries)))
      ($_none ()))))

;; What searching a fold's members is worth: a user base rate is never
;; refolded; an estimate by what one more member could add to its confidence,
;; since every member costs at least one expansion; a fold without an estimate
;; by its join.
(: sk-fold-child-score (-[semidet]-> $args Number (List BaseRateEntry) Number))
(= (sk-fold-child-score $args $join-score $entries)
   (case $entries (
      (() $join-score)
      ((cons $entry $_rest)
         (if (base-rate-entry-user? $entry) 0.0
            (let* (($confidence (tv-confidence (base-rate-entry-tv $entry)))
                   ($count (confidence-to-count $confidence)))
               (* $join-score (- (count-confidence (+ $count 1.0)) $confidence))))))))

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

(: SkeletonFilter Type)
;; the proof and truth-value pattern a consumer asks for
(: sk-filter (-[det]-> Proof TV SkeletonFilter))
(: sk-any-filter SkeletonFilter)

;; A view's proof is one rule application whose premise proofs are references
;; to stored proofs; the full proof expands every reference.
(: sk-proof-part (-[det]-> Atom Atom))
(: sk-proof-parts (-[det]-> Atom Atom))
(= (sk-proof-part $term)
   (if (is-expr $term)
      (case $term (
         ((proof-ref $pid)
            (case (collapse (once (match &proof ($pid $proof $_ev $_negated) $proof))) (
               ((cons $proof $_rest) (sk-proof-part $proof))
               (() $term))))
         ($_other (sk-proof-parts $term))))
      $term))
;; Atom parameters take their arguments unevaluated, so each part is bound first.
(= (sk-proof-parts $terms)
   (if (== $terms ()) ()
      (let* (($first (car-atom $terms))
             ($rest (cdr-atom $terms)))
         (cons-atom (sk-proof-part $first) (sk-proof-parts $rest)))))

(: sk-full-proof (-[det]-> Proof Proof))
(= (sk-full-proof $proof) (brand Proof (sk-proof-part $proof)))

(: sk-full-fact (-[det]-> SkFact SkFact))
(= (sk-full-fact ($type $kbctx $proof $tv)) (data $type $kbctx (sk-full-proof $proof) $tv))

;; Tries the pattern on fresh copies so neither side gets bound; a proof
;; pattern sees the full proof.
(: sk-fact-matches? (-[det]-> SkeletonFilter SkFact Bool))
(= (sk-fact-matches? $filter $fact)
   (case (copy_term $filter) (
      (sk-any-filter true)
      ((sk-filter $want-proof $want-tv) (sk-pattern-matches? $want-proof $want-tv (copy_term $fact))))))

(: sk-pattern-matches? (-[det]-> Proof TV SkFact Bool))
(= (sk-pattern-matches? $want-proof $want-tv ($_type $_kbctx $got-proof $got-tv))
   (if (if (is-var $want-proof) true (= (sk-full-proof $got-proof) $want-proof))
      (if (is-var $want-tv) true (= $got-tv $want-tv))
      false))

;; Every fact of a goal's statement and context that passes the filter. The
;; statement and context lead the match pattern, so the lookup uses the index
;; of &kb; the probe for materialized rows runs only when some materialization
;; happened.
(: sk-leaf-facts (-[det]-> Statement KBContext SkeletonFilter (List SkFact)))
(= (sk-leaf-facts $type $kbctx $filter)
   (let $plain (== (collapse (once (match &materialized_facts (materialized-row $_hash $_type $_kb $_fact $_ev) true))) ())
      (collapse (match &kb ($type $kbctx $proof $tv)
         (let $fact (data $type $kbctx $proof $tv)
            (if (sk-fact-matches? $filter $fact)
               (if (chainer-acyclic-term? $fact)
                  (if $plain $fact
                     (if (materialized-forward-fact? $fact) (empty) $fact))
                  (empty))
               (empty)))))))

(: sk-fact-key (-[det]-> SkFact SkeletonKey))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))

(: sk-leaf-answer-step (-[semidet]-> SkPattern Atom SkFact Atom))
(= (sk-leaf-answer-step $node $_acc $fact) (sk-add-answer! $node (sk-fact-key $fact)))

;; --- Keys ------------------------------------------------------------------

;; A value must not depend on its own key, nor on another key that unifies
;; with it: an open key such as ($p bob) may be answered by a derivation of
;; (Female bob) itself. The keys unifying with a reading key are found among
;; the answered keys once and cached. A ground key can unify only with open
;; keys, so its set is found among those. A new answered key joins the cached
;; sets it unifies with: a ground key is tried against the open readers of its
;; head, an open key against all readers of its head, and readers of any head
;; always; a key with an open head drops every cached set.
(: sk-key-open? (-[det]-> SkeletonKey Bool))
(= (sk-key-open? $key) (not (== (extract-vars $key) ())))

(: sk-unifier-add! (-[det]-> Number Number SkeletonKey Atom))
(= (sk-unifier-add! $khash $rhash $reader)
   (let $_updated
      (collapse (match &sk_unifiers ($rhash $open $stored $hashes)
         (if (=alpha $stored $reader)
            (let* (($_old (remove-variant-row! &sk_unifiers (quote ($rhash $open $stored $hashes))))
                   ($extended (cons $khash $hashes)))
               (add-atom &sk_unifiers ($rhash $open $stored $extended)))
            (empty))))
      ()))

(: sk-unifier-join! (-[det]-> Number SkeletonKey Number SkeletonKey Atom))
(= (sk-unifier-join! $khash $key $rhash $reader)
   (if (== $rhash $khash) ()
      (if (= (copy_term $reader) (copy_term $key)) (sk-unifier-add! $khash $rhash $reader) ())))

(: sk-register-key! (-[det]-> SkeletonKey Atom))
(= (sk-register-key! $key)
   (case $key (
      ((sk-key $type $_kbctx)
         (let* (($hash (index-hash $key))
                ($head (sk-type-head $type)))
            (if (== (collapse (once (match &sk_key_head ($head $_known-open $hash $stored)
                       (if (=alpha $stored $key) true (empty))))) ())
               (let* (($open (sk-key-open? $key))
                      ($_row (add-atom &sk_key_head ($head $open $hash $key)))
                      ($_open-row (if $open (add-atom &sk_open_key_head ($head $hash $key)) true)))
                  (if (== $head sk-any)
                     (let* (($_sets (remove-data-rows! &sk_unifiers (quote ($h $o $k $hs))))
                            ($_readers (remove-data-rows! &sk_reader_head (quote ($rh $rk $r))))
                            ($_open-readers (remove-data-rows! &sk_open_reader_head (quote ($oh $ok $or)))))
                        ())
                     (let* (($_same
                               (if $open
                                  (collapse (match &sk_reader_head ($head $rhash $reader) (sk-unifier-join! $hash $key $rhash $reader)))
                                  (collapse (match &sk_open_reader_head ($head $rhash $reader) (sk-unifier-join! $hash $key $rhash $reader)))))
                            ($_any
                               (collapse (match &sk_reader_head (sk-any $any-hash $any-reader) (sk-unifier-join! $hash $key $any-hash $any-reader)))))
                        ())))
               ())))
      ($_fold ()))))

;; Keys of one statement head, or of every head for a key whose head is open,
;; that unify with the key: all of them for an open key, the open ones for a
;; ground key.
(: sk-unifying-keys (-[det]-> Number SkeletonKey Bool Atom (List Number)))
(= (sk-unifying-keys $khash $key $open $head)
   (if $open
      (collapse (match &sk_key_head ($head $_other-open $hash $other)
         (if (== $hash $khash) (empty)
            (if (= (copy_term $key) (copy_term $other)) $hash (empty)))))
      (collapse (match &sk_open_key_head ($head $open-hash $open-other)
         (if (== $open-hash $khash) (empty)
            (if (= (copy_term $key) (copy_term $open-other)) $open-hash (empty)))))))

(: sk-unifier-hashes (-[det]-> Number SkeletonKey (List Number)))
(= (sk-unifier-hashes $khash $key)
   (case (collapse (once (match &sk_unifiers ($khash $_cached-open $stored $hashes)
            (if (=alpha $stored $key) $hashes (empty))))) (
      ((cons $hashes $_rest) $hashes)
      (()
         (case $key (
            ((sk-key $type $_kbctx)
               (let* (($open (sk-key-open? $key))
                      ($head (sk-type-head $type))
                      ($others
                         (if (== $head sk-any) (sk-unifying-keys $khash $key $open $_any-head)
                            (append-flat (sk-unifying-keys $khash $key $open $head)
                               (sk-unifying-keys $khash $key $open sk-any))))
                      ($hashes (cons $khash $others))
                      ($_cached (add-atom &sk_unifiers ($khash $open $key $hashes)))
                      ($_reader (add-atom &sk_reader_head ($head $khash $key)))
                      ($_open-reader (if $open (add-atom &sk_open_reader_head ($head $khash $key)) true)))
                  $hashes))
            ($_fold (cons $khash ()))))))))

;; --- Answers and delivery ---------------------------------------------------

(= (sk-add-answer! $node $key)
   (if (sk-link-new! (sk-answer-link $node $key))
      (let* (($_registered (sk-register-key! $key))
             ($hash (sk-node-hash $node))
             ($_row (add-atom &sk_answer ($hash $node $key)))
             ($folds
                (collapse (match &sk_member_of ($hash $stored $fold)
                   (if (=alpha $stored $node) $fold (empty)))))
             ($_members (fold-semidet (sk-member-step $key) () $folds))
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

(: sk-add-use! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-add-use! $key $parent)
   (if (sk-link-new! (sk-use-link $key $parent))
      (let* (($hash (index-hash $key))
             ($_row (add-atom &sk_use ($hash $key $parent))))
         ())
      ()))

(: sk-mark-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-mark-dirty! $key)
   (if (not (== (collapse (once (match &sk_latest ($_hash $_key $_version) true))) ()))
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
                  (let $_child
                     (let $score (sk-fold-child-score $args (sk-join-score $owner $rule $remaining) (sk-rate-entries $args))
                        (if (> $score 0.0) (sk-add-child! $owner (copy_term $premise) $score) ()))
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

;; A join waiting on a ground fact premise sees that premise's stored facts at
;; once: looking them up is one indexed read, so only expanding the premise's
;; rules costs a step. An open premise waits for its expansion, which bounds
;; recursion through its own answers.
(= (sk-wait-on! $owner $rule $premise $waiter)
   (let* (($hash (sk-node-hash $premise))
          ($_wait (add-atom &sk_wait ($hash $premise $waiter)))
          ($_leaves
             (if (sk-expanded? $premise) ()
                (case (copy_term $premise) (
                   ((CPU $_fun $_args $_res) ())
                   (($type $kbctx $proof $tv)
                      (if (== (extract-vars $type) ())
                         (fold-semidet (sk-leaf-answer-step $premise) () (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
                         ()))))))
          ($_temp
             (if (>= $rule 1000000000)
                (let $_t (add-atom &sk_temp_waits ($hash $premise $waiter)) ())
                ()))
          ($_child
             (case $waiter (
                ((sk-partial $_owner $_rule $_concl $_premises $remaining $_keys)
                   (sk-add-child! $owner (copy_term $premise) (sk-join-score $owner $rule $remaining)))))))
      (fold-semidet (sk-extend-waiter-step $waiter) () (sk-answers $premise))))

(: sk-extend-waiter-step (-[semidet]-> SkeletonWaiter Atom SkeletonKey Atom))
(= (sk-extend-waiter-step $waiter $_acc $key) (sk-extend! (copy_term $waiter) $key))

;; A join is extended by an answer once, however the answer reaches it (read
;; when the join starts waiting, or delivered later); a computation that
;; samples would otherwise draw again. Once the row allowance is spent, a join
;; an answer reaches stops there: the pair waits once with the join's owner, so
;; a recursive rule cannot keep extending joins whose rows could not be kept
;; anyway. Joins of the query's roots always proceed.
(= (sk-extend! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
   (if (if (sk-root? $owner) true (> (search-id-value sk_row_budget) 0))
      (if (sk-link-new! (sk-join-link (sk-partial $owner $rule $concl $premises $remaining $keys) $key))
         (sk-extend-now! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
         ())
      (let* (($hash (sk-node-hash $owner))
             ($join (sk-join (sk-partial $owner $rule $concl $premises $remaining $keys) $key))
             ($jhash (index-hash $join)))
         (if (== (collapse (once (match &sk_deferred_joins ($hash $jhash $_join) true))) ())
            (let* (($_deferred (add-atom &sk_deferred_joins ($hash $jhash $join)))
                   ($_counted (query_metric_increment joins-deferred)))
               ())
            ()))))

(: sk-extend-now! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(= (sk-extend-now! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
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

;; A computation whose arguments were ground when its join was built was
;; computed then and bound its result; recomputing a sampling formula would
;; draw again. The formulas over premise truth values run in evaluation.
(: sk-evaluated-premise-step (-[det]-> (List SkPattern) SkPattern (List SkPattern)))
(= (sk-evaluated-premise-step $kept $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (aggregate-fold-function? $fun) (cons $premise $kept)
            (if (== (extract-vars $args) ()) $kept (cons $premise $kept))))
      ($_fact (cons $premise $kept)))))

(= (sk-complete-row! $owner $rule $concl $premises $keys)
   (let* ((($type $kbctx $_proof $_tv) $concl)
          ($key (sk-key $type $kbctx))
          ($khash (index-hash $key))
          ($ident (sk-ident $rule $keys $key))
          ($rhash (index-hash $ident))
          ($local (>= $rule 1000000000)))
      (if (sk-row-present? $khash $key $rhash $ident)
         (sk-add-answer! $owner $key)
         ;; The rows of the query's roots are its compiled scaffold and always
         ;; fit; every other row spends the allowance.
         (if (if (sk-root? $owner) true (sk-take! sk_row_budget))
            (let* (($seq (next-search-id sk_row_seq))
                   ($row (sk-row $ident $concl
                            (fold-semidet sk-cons-step () (fold-semidet sk-evaluated-premise-step () $premises)) $seq))
                   ($_add
                      (if (chainer-acyclic-term? $row)
                         (let* (($_stored (add-atom &sk_row ($khash $key $rhash $row)))
                                ($_counted (query_metric_increment rows-created)))
                            (add-atom &sk_new (sk-row-item $seq $khash $key $rhash $row)))
                         false))
                   ($_temp
                      (if $local
                         (let $_t (add-atom &sk_temp_rows ($khash $key $rhash $row)) ())
                         ()))
                   ($_readers
                      (fold-semidet (sk-add-reader! $khash $rhash) ()
                         (fold-semidet sk-direct-key-step () $premises))))
               (sk-add-answer! $owner $key))
            ;; A row waits once, however often its join completes meanwhile.
            (let $hash (sk-node-hash $owner)
               (if (== (collapse (once (match &sk_deferred ($hash $rhash $_deferred) true))) ())
                  (let* (($_deferred
                            (add-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys))))
                         ($_counted (query_metric_increment rows-deferred)))
                     ())
                  ()))))))

;; The keys a row reads directly: its fact premises, folds and groups.
(: sk-direct-key-step (-[det]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-direct-key-step $keys $premise)
   (case $premise (
      ((CPU FoldAllCompiled $fold-args $_fold-res) (cons (sk-fold $fold-args) $keys))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res) (cons (sk-group $group-args) $keys))
      ((CPU $_fun $_args $_res) $keys)
      (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $keys)))))

(: sk-add-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-add-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_row (add-atom &sk_reader ($hash $key $khash $rhash))))
      ()))

(: sk-remove-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-remove-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_removed
             (collapse (match &sk_reader ($hash $stored $khash $rhash)
                (if (=alpha $stored $key) (remove-atom &sk_reader ($hash $stored $khash $rhash)) (empty))))))
      ()))

;; The budget counts expansions. New rows have their own allowance of ten per
;; step, so recursive rules cannot grow the skeleton without bound; a row found
;; after the allowance is spent waits in &sk_deferred for a later walk.
(: sk-root? (-[det]-> SkPattern Bool))
(= (sk-root? $node)
   (let $hash (sk-node-hash $node)
      (not (== (collapse (once (match &sk_roots ($hash $root) (if (=alpha $root $node) true (empty))))) ()))))

(: sk-take! (-[det]-> CounterKey Bool))
(= (sk-take! $counter)
   (let $left (search-id-value $counter)
      (if (<= $left 0) false
         (progn (change-state! $counter (- $left 1)) true))))

;; Work left over by an earlier query waits with its node and resumes when a
;; later walk reaches that node, so it never spends an unrelated query's
;; budget: parked deliveries are queued again, and while rows are allowed,
;; deferred joins are extended and deferred rows completed.
(: sk-deferred-step (-[semidet]-> Atom SkeletonDeferred Atom))
(= (sk-deferred-step $_acc (sk-deferred $owner $rule $concl $premises $keys))
   (sk-complete-row! $owner $rule $concl $premises $keys))

(: sk-resume! (-[semidet]-> SkPattern Atom))
(= (sk-resume! $node)
   (let* (($hash (sk-node-hash $node))
          ($_deliveries
             (collapse (match &sk_parked ($hash $seq (sk-delivery $owner $key))
                (if (=alpha $owner $node)
                   (let $_removed (remove-atom &sk_parked ($hash $seq (sk-delivery $_o $_k)))
                      (add-atom &sk_answer_queue ($seq (sk-delivery $owner $key))))
                   (empty))))))
      (if (<= (search-id-value sk_row_budget) 0) ()
         (let* (($joins
                   (collapse (match &sk_deferred_joins ($hash $jhash (sk-join $waiter $key))
                      (if (=alpha (sk-waiter-owner $waiter) $node)
                         (let $_removed (remove-atom &sk_deferred_joins ($hash $jhash (sk-join $waiter $key)))
                            (sk-join $waiter $key))
                         (empty)))))
                ($_joined (fold-semidet sk-deferred-join-step () $joins))
                ($deferred
                   (collapse (match &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys))
                      (if (=alpha $owner $node)
                         (let $_removed
                            (remove-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys)))
                            (sk-deferred $owner $rule $concl $premises $keys))
                         (empty))))))
            (fold-semidet sk-deferred-step () $deferred)))))

(: sk-waiter-owner (-[det]-> SkeletonWaiter SkPattern))
(= (sk-waiter-owner (sk-partial $owner $_rule $_concl $_premises $_remaining $_keys)) $owner)

(: sk-deferred-join-step (-[semidet]-> Atom SkeletonJoin Atom))
(= (sk-deferred-join-step $_acc (sk-join $waiter $key)) (sk-extend! (copy_term $waiter) $key))

(: sk-park-step (-[det]-> Atom SkeletonQueued Atom))
(= (sk-park-step $_acc (sk-queued $seq (sk-delivery $node $key)))
   (let* (($hash (sk-node-hash $node))
          ($_row (add-atom &sk_parked ($hash $seq (sk-delivery $node $key)))))
      ()))

(: sk-park-deliveries! (-[semidet]-> Atom))
(= (sk-park-deliveries!)
   (let $entries
      (collapse (match &sk_answer_queue ($seq (sk-delivery $node $key))
         (let $_removed (remove-atom &sk_answer_queue ($seq (sk-delivery $_n $_k)))
            (sk-queued $seq (sk-delivery $node $key)))))
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

;; A rule applies to a node when its conclusion fits the whole node pattern;
;; its row is built from the statement and context alone, since a row belongs
;; to its key and each reader applies its own proof and truth-value pattern.
(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (= (copy_term $goal) (copy_term $owner))
      (if (prefilter-prunes-walk (copy_term $premises)) ()
         (sk-advance! (sk-partial $owner $rule $goal $premises $premises ())))
      ()))

;; The compiled scaffold of a nested implication subgoal that is not itself a
;; compiled total-implication source; its assumption contexts are the query's.
(: inject-special-subgoal-query-adds (-[semidet]-> Statement KBContext Proof TV Atom))
(= (inject-special-subgoal-query-adds $type $kbctx $prf $tv)
   (case $kbctx (
      (($kbid MAIN Nil)
         (if (implication-type? $type)
            ;; A compiler-marked source already installed its scaffold. The
            ;; marker test compares without unifying, so an open proof head
            ;; stays an ordinary constraint.
            (if (if (is-expr $prf)
                   (if (== $prf ()) false
                      (if (== (car-atom $prf) total-implication-frontier)
                         (let $args (cdr-atom $prf) (if (== $args ()) false (== (cdr-atom $args) ())))
                         false))
                   false)
               ()
               (foreach-flat inject-compiled-query-adds
                  (collapse (mm2compileQuery (brand KB $kbid) (: $prf $type $tv)))))
            ()))
      ($_other ()))))

;; The empirical Member producer of a concrete Inheritance link depends only on
;; the link, so it is installed once as permanent backward rules: its rows
;; survive the query, and a later zero-budget read still has them. Forward
;; chaining keeps member inheritance through its own aggregate.
(: install-member-inheritance-rules! (-[semidet]-> Statement KBContext Atom))
(= (install-member-inheritance-rules! $type $kbctx)
   (case $kbctx (
      (($kbid MAIN Nil)
         (case $type (
            ((Inheritance $subj $concept)
               (if (concrete-inheritance-link? $subj $concept)
                  (let* (($link (quote ($kbid $subj $concept)))
                         ($hash (index-hash $link)))
                     (if (== (collapse (once (match &sk_member_rules ($hash $stored)
                                (if (=alpha $stored $link) true (empty))))) ())
                        (let* (($_row (add-atom &sk_member_rules ($hash $link)))
                               ($_rules
                                  (once (foreach-flat (kb-add-expr backward)
                                     (map-flat mm2stmt
                                        (compile-member-inheritance-query-adds
                                           (brand KB $kbid) (brand Term $subj) (brand Term $concept)))))))
                           ())
                        ()))
                  ()))
            ($_other ()))))
      ($_other ()))))

(: inject-compiled-query-adds (-[semidet]-> CompiledQuery Atom))
(= (inject-compiled-query-adds (compiled-query $_goal $adds))
   (if (is-var $adds) (empty) (once (inject-compiled-adds $adds))))

;; The fold's source goal is compiled as an ordinary query once per pattern.
;; Its additions depend only on the pattern, so they are installed as
;; permanent backward rules: the member rows outlive the query, and a later
;; fold over the same pattern reuses the goal.
(: sk-fold-member (-[semidet]-> $arguments (List SkPattern)))
(= (sk-fold-member $args)
   (let* (($kb (brand KB (car-atom $args)))
          ($pattern (brand Statement (car-atom (cdr-atom $args))))
          ($source (quote ($kb $pattern)))
          ($hash (index-hash $source)))
      (case (collapse (once (match &sk_fold_members ($hash $stored $member)
               (if (=alpha $stored $source) $member (empty))))) (
         ((cons $found $_rest) (cons $found ()))
         (()
            (case (collapse (once (mm2compileQuery $kb (: $_h $pattern $_i)))) (
               ((cons (compiled-query $goal $adds) $_rest)
                  (if (if (is-var $goal) true (is-var $adds)) ()
                     (let* (($_rules (once (foreach-flat (kb-add-expr backward) $adds)))
                            ($compiled (typed-runtime-premise $goal))
                            ($_row (add-atom &sk_fold_members ($hash $source $compiled))))
                        (cons $compiled ()))))
               ($_none ()))))))))

(= (sk-expand! $node $depth)
   (let $_counted (query_metric_increment expansions)
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
                         ($_child (sk-add-child! $node $member (sk-node-score $node))))
                     (fold-semidet (sk-fold-answer-step $node) () (sk-answers $member))))))))
      (($type $kbctx $proof $tv)
         (let* (($_special
                   (if (> $depth 0) (inject-special-subgoal-query-adds $type $kbctx $proof $tv) ()))
                ($_member (install-member-inheritance-rules! $type $kbctx))
                ($_activate (sk-activate-pending!))
                ($_mark (sk-mark-expanded! $node))
                ($_leaves
                   (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $type $kbctx (sk-filter $proof $tv))))
                ($owner (copy_term $node))
                (($rule-type $rule-kbctx $_node-proof $_node-tv) (copy_term $node))
                ($matches (collapse (sk-rule-match (assemble-stored-runtime-fact $rule-type $rule-kbctx $_rule-proof $_rule-tv)))))
            (fold-semidet (sk-start-rule-step $owner) () $matches)))))))

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
   (let* (((sk-rule-def $conclusion $premises) (copy_term (sk-rule-def $ccls $args))))
      (if (case (copy_term $node) (
             ((CPU $_fun $_args $_res) false)
             (($type $kbctx $_proof $_tv)
                (= $conclusion (assemble-stored-runtime-fact $type $kbctx $_rule-proof $_rule-tv)))))
         (if (chainer-acyclic-term? $conclusion)
            (sk-start-rule-step $node ()
               (sk-match $id (contextualize-rule-args $conclusion $premises) $conclusion))
            ())
         ())))

(: sk-activate-fact-on (-[semidet]-> SkeletonKey Atom SkPattern Atom))
(= (sk-activate-fact-on $key $_acc $node)
   (case (copy_term $node) (
      ((CPU $_fun $_args $_res) ())
      (($type $kbctx $proof $tv)
         (if (= (sk-key $type $kbctx) (copy_term $key))
            (fold-semidet (sk-leaf-answer-step $node) () (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
            ())))))

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

;; The walk is best-first by score. Walking an expanded node is free; an
;; unexpanded one costs a step, and the walk ends at the first one the budget
;; cannot pay for. Equal scores go shallowest first, then in insertion order.
(: sk-push (-[det]-> Number (Heap SkeletonFrontier) SkPattern (Heap SkeletonFrontier)))
(= (sk-push $depth $heap $node)
   (add_to_heap $heap
      (+ (- 0 (sk-node-score $node)) (+ (* $depth 0.000001) (* (next-search-id sk_push_seq) 0.000000000001)))
      (sk-frontier $node $depth)))

(: sk-push-children (-[semidet]-> Number SkPattern (Heap SkeletonFrontier) (Heap SkeletonFrontier)))
(= (sk-push-children $depth $node $heap)
   (fold-semidet (sk-push (+ $depth 1)) (fold-semidet (sk-push (+ $depth 1)) $heap (sk-children $node)) (sk-take-fresh!)))

(= (sk-search! $heap)
   (let $_drained (sk-drain!)
      (if (heap-empty? $heap)
         (case (sk-take-fresh!) (
            (() ())
            ($fresh (sk-search! (fold-semidet (sk-push 1) $heap $fresh)))))
         (sk-search-pop! (heap_pop $heap)))))

(: sk-search-pop! (-[semidet]-> (Number SkeletonFrontier (Heap SkeletonFrontier)) Atom))
(= (sk-search-pop! ($_priority (sk-frontier $node $depth) $rest))
   (if (sk-seen! $node)
      (sk-search! $rest)
      (if (sk-expanded? $node)
         (let $_resumed (sk-resume! $node) (sk-search! (sk-push-children $depth $node $rest)))
         (if (sk-take! sk_budget)
            (let $_expand (sk-expand! $node $depth) (sk-search! (sk-push-children $depth $node $rest)))
            (sk-drain!)))))

;; A row's latest view and the views it replaced.
(: sk-drop-row-views! (-[det]-> Number SkeletonKey Number Atom))
(= (sk-drop-row-views! $hash $key $rhash)
   (let* (($_latest
             (collapse (match &sk_latest ($hash $stored (sk-version $seq $rhash $view))
                (if (=alpha $stored $key)
                   (remove-atom &sk_latest ($hash $stored (sk-version $seq $rhash $view)))
                   (empty)))))
          ($_older
             (collapse (match &sk_view ($hash $stored $rhash $view)
                (if (=alpha $stored $key) (remove-atom &sk_view ($hash $stored $rhash $view)) (empty)))))
          ($_support (remove-data-rows! &sk_support (quote ($hash $rhash $_deps)))))
      ()))

;; Query-local rules leave with their query: their rows, waiters, deferred rows
;; and views are removed, and the keys of the removed rows changed.
(: sk-clear-temp! (-[semidet]-> Atom))
(= (sk-clear-temp!)
   (let* (($_deferred
             (collapse (match &sk_deferred ($h $rh (sk-deferred $o $rule $c $p $k))
                (if (>= $rule 1000000000)
                   (remove-atom &sk_deferred ($h $rh (sk-deferred $o $rule $c $p $k)))
                   (empty)))))
          ($_waits
             (collapse (match &sk_temp_waits ($hash $pattern $waiter)
                (let $_temp (remove-atom &sk_temp_waits ($hash $pattern $waiter))
                   (remove-atom &sk_wait ($hash $pattern $waiter))))))
          ($keys
             (collapse (match &sk_temp_rows ($khash $key $rhash $row)
                (let* (($_temp (remove-atom &sk_temp_rows ($khash $key $rhash $row)))
                       ($_row (remove-atom &sk_row ($khash $key $rhash $row)))
                       ((sk-row $_ident $_concl $premises $_seq) $row)
                       ($_readers
                          (fold-semidet (sk-remove-reader! $khash $rhash) ()
                             (fold-semidet sk-direct-key-step () $premises)))
                       ($_views (sk-drop-row-views! $khash $key $rhash)))
                   $key)))))
      (fold-semidet sk-dirty-step () $keys)))

(: sk-dirty-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-dirty-step $_acc $key) (sk-mark-dirty! $key))
