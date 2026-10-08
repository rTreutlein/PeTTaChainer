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
(: sk-rule-match (-[nondet]-> SkFact SkeletonMatch))
(: sk-world-rule-match (-[nondet]-> SkFact SkeletonMatch))
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
      (case (copy_term $pattern) (
         ((CPU $_fun $_args $_res) ())
         (($type $kbctx $_proof $_tv)
            (let $_terms (add-atom &sk_node_terms ($type $kbctx $pattern)) ()))))))

(: sk-answers (-[det]-> SkPattern (List SkeletonKey)))
(= (sk-answers $pattern)
   (let $hash (sk-node-hash $pattern)
      (collapse (match &sk_answer ($hash $stored $key)
         (if (=alpha $stored $pattern) $key (empty))))))

;; With forgetting on, a key records the last epoch it got a row or was
;; needed; a key idle for the horizon is frozen (forgetting.metta).
(: sk-touch-key! (-[det]-> Number SkeletonKey Atom))
(= (sk-touch-key! $hash $key)
   (if (<= (search-id-value forgetting_horizon) 0) ()
      (case $key (
         ((sk-key $_type $_kbctx)
            (let $epoch (search-id-value sk_epoch)
               (if (space-row-present? &sk_key_epoch ($hash $key $epoch)) ()
                  (let $_old
                     (collapse (match &sk_key_epoch ($hash $stored $was)
                        (if (=alpha $stored $key) (remove-atom &sk_key_epoch ($hash $stored $was)) (empty))))
                     (let $_new (add-atom &sk_key_epoch ($hash $key $epoch)) ())))))
         ($_fold ())))))

;; Child links, answers, use edges and join extensions are each recorded
;; once, by a digest of the link: one lookup, and a record of one integer
;; however large the join it names. A link with an end in an Assuming query's
;; context leaves with that context.
(: sk-link-new! (-[det]-> SkeletonLink Bool))
(= (sk-link-new! $link)
   (let $digest (link-digest $link)
      (if (space-row-present? &sk_link ($digest)) false
         (let* (($_row (add-atom &sk_link ($digest)))
                ($ctx
                   (case $link (
                      ((sk-child-link $owner $child)
                         (let $owner-ctx (node-context $owner)
                            (if (context-world? $owner-ctx) $owner-ctx (node-context $child))))
                      ((sk-answer-link $node $key)
                         (let $node-ctx (node-context $node)
                            (if (context-world? $node-ctx) $node-ctx (key-context $key))))
                      ((sk-use-link $key $parent)
                         (let $key-ctx (key-context $key)
                            (if (context-world? $key-ctx) $key-ctx (key-context $parent))))
                      ((sk-join-link (sk-partial $join-owner $_rule $_concl $_premises $_remaining $_keys) $answer)
                         (let $join-ctx (node-context $join-owner)
                            (if (context-world? $join-ctx) $join-ctx (key-context $answer)))))))
                ($_noted (sk-note-context! $ctx (ctx-link $digest))))
            true))))

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
         (let* (($removed
                   (collapse (match &sk_score ($hash $stored $old-score)
                      (if (=alpha $stored $node) (remove-atom &sk_score ($hash $stored $old-score)) (empty)))))
                ($_added (add-atom &sk_score ($hash $node $score))))
            (if (== $removed ())
               (let $ctx (node-context $node) (sk-note-context! $ctx (ctx-node $hash $node)))
               ()))
         ())))

;; A rule's expected confidence, computed when the rule was stored; a refined
;; rule's is scaled by what its current truth can add, read from the truth
;; goal's value, or from its axiom until the goal has one.
(: sk-rule-score (-[det]-> Number Number))
(= (sk-rule-score $rule)
   (* (case (collapse (once (match rule_expected ($rule $score) $score))) (
         ((cons $score $_rest) $score)
         (() 1.0)))
      (case (collapse (once (match &sk_rule_truth ($rule $hash $type $kbctx) (sk-truth-factor $hash $type $kbctx)))) (
         ((cons $factor $_more) $factor)
         (() 1.0)))))

(: sk-truth-factor (-[det]-> Number Statement KBContext Number))
(= (sk-truth-factor $hash $type $kbctx)
   (case (collapse (once (match &sk_truth_factor ($hash $factor) $factor))) (
      ((cons $factor $_rest) $factor)
      (()
         (let $factor
            (case (collapse (once (match &kb ($type $kbctx (rule-axiom $_name) $tv) $tv))) (
               ((cons $tv $_rest) (rule-truth-factor $tv))
               (() 1.0)))
            (let $_set (sk-set-truth-factor! $hash $factor) $factor))))))

(: sk-set-truth-factor! (-[det]-> Number Number Atom))
(= (sk-set-truth-factor! $hash $factor)
   (let* (($_old (remove-data-rows! &sk_truth_factor (quote ($hash $_was))))
          ($_new (add-atom &sk_truth_factor ($hash $factor))))
      ()))

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

(: sk-note-context! (-[det]-> Atom SkeletonContextItem Atom))
(= (sk-note-context! $ctx $item)
   (if (context-world? $ctx) (let $_row (add-atom &sk_ctx_items ($ctx $item)) ()) ()))

(: sk-add-child! (-[semidet]-> SkPattern SkPattern Number Atom))
(= (sk-add-child! $owner $child $score)
   (if (let $_scored (sk-raise-score! $child $score) (sk-link-new! (sk-child-link $owner $child)))
      (let* (($hash (sk-node-hash $owner))
             ($_row (add-atom &sk_child ($hash $owner $child)))
             ($child-ctx (node-context $child))
             ($_node (sk-note-context! $child-ctx (ctx-node (sk-node-hash $child) $child)))
             ($_link
                (if (== $child-ctx (node-context $owner)) ()
                   (sk-note-context! $child-ctx (ctx-child $hash $owner $child))))
             ($_fresh (add-atom &sk_fresh (sk-fresh $child))))
         (sk-index-node! $child))
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

(: SkeletonFilter Type)
;; the proof and truth-value pattern a consumer asks for
(: sk-filter (-[det]-> Proof TV SkeletonFilter))
(: sk-any-filter SkeletonFilter)

;; A view's proof is one rule application whose premise proofs are references
;; to stored proofs; the full proof expands them, printing each shared
;; subproof once (proof_dag_expand in runtime_helpers.pl).
(: sk-full-proof (-[det]-> Proof Proof))
(= (sk-full-proof $proof) (brand Proof (proof_dag_expand $proof)))

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

;; Every fact of a goal's statement and context that passes the filter, read
;; through the statement's prefix index (kb-facts); the probe for materialized
;; rows runs only when some materialization happened.
(: sk-leaf-facts (-[det]-> Statement KBContext SkeletonFilter (List SkFact)))
(= (sk-leaf-facts $type $kbctx $filter)
   (let $plain (== (collapse (once (match &materialized_facts (materialized-row $_hash $_type $_kb $_fact $_ev) true))) ())
      (foldr-flat (sk-leaf-fact-step $plain $filter) ()
         (append-flat (kb-facts $type $kbctx) (sk-world-facts $type $kbctx)))))

;; A context that sees the world reads the main context's stored facts as its
;; own: an assumption adds to what is known and hides nothing. Forward copies
;; of derived values are not read; the context derives those itself.
(: sk-world-facts (-[det]-> Statement KBContext (List SkFact)))
(= (sk-world-facts $type $kbctx)
   (case (sk-key $type $kbctx) (
      ((sk-key $_type ($kbid $ctx $_vars))
         (if (context-world? $ctx)
            (foldr-flat (sk-world-fact-step $kbctx) ()
               (kb-facts $type (make-kb-context (brand KB $kbid) MAIN Nil)))
            ()))
      ($_fold ()))))

(: sk-world-fact-step (-[det]-> KBContext SkFact (List SkFact) (List SkFact)))
(= (sk-world-fact-step $kbctx ($type $main $proof $tv) $facts)
   (let $hash (index-hash (sk-key $type $main))
      (if (== (collapse (once (match &sk_forward_stored ($hash $_key $copy $_ev $_deps)
                 (if (=alpha $copy ($type $main $proof $tv)) true (empty))))) ())
         (cons (data $type $kbctx $proof $tv) $facts)
         $facts)))

(: sk-leaf-fact-step (-[det]-> Bool SkeletonFilter SkFact (List SkFact) (List SkFact)))
(= (sk-leaf-fact-step $plain $filter $fact $facts)
   (if (sk-fact-matches? $filter $fact)
      (if (chainer-acyclic-term? $fact)
         (if $plain (cons $fact $facts)
            (if (materialized-forward-fact? $fact) $facts (cons $fact $facts)))
         $facts)
      $facts))

(: sk-fact-key (-[det]-> SkFact SkeletonKey))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))

;; A ground statement stored with confidence 1 is certain: no other proof
;; could change its value.
(: sk-certain-step (-[det]-> Bool SkFact Bool))
(= (sk-certain-step $seen ($_type $_kbctx $_proof $tv))
   (if $seen true (case $tv (((STV $_s $c) (>= $c 1.0)) ($_other false)))))
(: sk-certain? (-[det]-> Statement (List SkFact) Bool))
(= (sk-certain? $type $facts)
   (if (== (extract-vars $type) ()) (fold-flat sk-certain-step false $facts) false))

(: sk-leaf-answer-step (-[semidet]-> SkPattern Atom SkFact Atom))
(= (sk-leaf-answer-step $node $_acc $fact) (sk-add-answer! $node (sk-fact-key $fact)))

;; --- Keys ------------------------------------------------------------------

;; A value must not depend on its own key, nor on another key that unifies
;; with it: an open key such as ($p bob) may be answered by a derivation of
;; (Female bob) itself. The keys unifying with a reading key are found once and
;; cached, and a new answered key joins the cached sets of the readers it
;; unifies with. Keys and readers are stored by statement and context, so
;; finding the ones that unify with a key is one structural match; a reader's
;; lookup columns are a copy, so a match leaves the returned reader open.
(: sk-unifier-add! (-[det]-> Number Number SkeletonKey Atom))
(= (sk-unifier-add! $khash $rhash $reader)
   (let $_updated
      (collapse (match &sk_unifiers ($rhash $stored $hashes)
         (if (=alpha $stored $reader)
            (let* (($_old (remove-variant-row! &sk_unifiers (quote ($rhash $stored $hashes))))
                   ($extended (hash-union (cons $khash ()) $hashes)))
               (add-atom &sk_unifiers ($rhash $stored $extended)))
            (empty))))
      ()))

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
                      ($ctx (key-context $key))
                      ($_noted (sk-note-context! $ctx (ctx-key $hash $key)))
                      ($_terms (add-atom &sk_key_terms ($type $kbctx $hash)))
                      ($ground (== (extract-vars $type) ()))
                      ($_prefixes
                         (if $ground
                            (map-flat (sk-key-prefix-row! $type $kbctx $hash) (statement-prefix-hashes $type))
                            (add-atom &sk_key_open ($type $kbctx $hash))))
                      ($_joined
                         (collapse (match &sk_reader_terms ($type $kbctx $rhash $reader)
                            (if (== $rhash $hash) (empty) (sk-unifier-add! $hash $rhash $reader))))))
                  (if $ground
                     (fold-semidet (sk-member-join-step $type $kbctx $key) () (cons (index-hash (car-atom $type)) (statement-prefix-hashes $type)))
                     ()))
               ())))
      ($_fold ()))))

(: sk-key-prefix-row! (-[det]-> Statement KBContext Number Number Bool))
(= (sk-key-prefix-row! $type $kbctx $hash $prefix) (add-atom &sk_key_prefix ($prefix $type $kbctx $hash)))

;; The hashes of the registered keys whose term unifies with a pattern: through
;; the longest ground prefix of the pattern when it has one (see kb-facts).
(: sk-unifying-key-hashes (-[det]-> Statement KBContext (List Number)))
(= (sk-unifying-key-hashes $type $kbctx)
   (case (statement-prefix-hashes $type) (
      (() (collapse (match &sk_key_terms ($type $kbctx $hash) $hash)))
      ((cons $prefix $_shorter)
         (append-flat
            (collapse (match &sk_key_prefix ($prefix $type $kbctx $hash) $hash))
            (collapse (match &sk_key_open ($type $kbctx $hash) $hash)))))))

;; the key itself and every registered key whose term unifies with it
(: sk-key-term-hashes (-[det]-> Number Statement KBContext (List Number)))
(= (sk-key-term-hashes $khash $type $kbctx)
   (hash-set (cons $khash (sk-unifying-key-hashes $type $kbctx))))

(: sk-unifier-hashes (-[det]-> Number SkeletonKey (List Number)))
(= (sk-unifier-hashes $khash $key)
   (case (collapse (once (match &sk_unifiers ($khash $stored $hashes)
            (if (=alpha $stored $key) $hashes (empty))))) (
      ((cons $hashes $_rest) $hashes)
      (()
         (case (copy_term $key) (
            ((sk-key $type $kbctx)
               ;; Named apart from the match's $hashes: the translator loses
               ;; a reused name's type and would check the row at run time.
               (let* (($computed (sk-key-term-hashes $khash $type $kbctx))
                      ($_cached (add-atom &sk_unifiers ($khash $key $computed)))
                      ;; A ground reader unifies with no other key, so only
                      ;; an open one waits for the keys registered later.
                      ($_reader (if (== (extract-vars $key) ()) ()
                                   (add-atom &sk_reader_terms ($type $kbctx $khash $key)))))
                  $computed))
            ($_fold (cons $khash ()))))))))

;; --- Answers and delivery ---------------------------------------------------

(= (sk-add-answer! $node $key)
   (if (sk-link-new! (sk-answer-link $node $key))
      (let* (($_registered (sk-register-key! $key))
             ($hash (sk-node-hash $node))
             ($_row (add-atom &sk_answer ($hash $node $key)))
             ($_noted
                (let $key-ctx (key-context $key)
                   (if (== $key-ctx (node-context $node)) ()
                      (sk-note-context! $key-ctx (ctx-answer $hash $node $key)))))
             ($_indexed
                (if (<= (search-id-value forgetting_horizon) 0) ()
                   (let* (($khash (index-hash $key))
                          ($_answered (add-atom &sk_answered ($khash $key $hash $node))))
                      ())))
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
             ($_row (add-atom &sk_use ($hash $key $parent)))
             ($_noted
                (let $parent-ctx (key-context $parent)
                   (if (== $parent-ctx (key-context $key)) ()
                      (sk-note-context! $parent-ctx (ctx-use $hash $key $parent))))))
         ())
      ()))

;; Before anything was evaluated (no latest version of any key) there is no
;; reader to schedule.
(: sk-mark-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-mark-dirty! $key)
   (if (not (== (collapse (once (match &sk_latest ($_hash $_key $_version) true))) ()))
      (sk-dirty! $key)
      ()))

;; Base rates follow their members incrementally, see sk-fold-view.
(: sk-rate-fold? (-[det]-> SkeletonKey Bool))
(= (sk-rate-fold? $key)
   (case $key (
      ((sk-fold ($_kb $_pattern $_extractor $_init $_function $finish $_mode)) (base-rate-finish? $finish))
      ($_other false))))

;; A member that joined a base-rate fold, or whose value changed, is taken into
;; it when a query next needs the fold or it is next read.
(: sk-rate-dirty! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-rate-dirty! $fold $member)
   (if (sk-rate-fold? $fold)
      (let $hash (index-hash $fold)
         (if (== (collapse (once (match &sk_rate_dirty ($hash $stored-fold $stored)
                    (if (=alpha $stored $member) (if (=alpha $stored-fold $fold) true (empty)) (empty)))))
                 ())
            (let $_row (add-atom &sk_rate_dirty ($hash $fold $member)) ())
            ()))
      ()))

;; A new member answer changes the value of every fold over its node; a group
;; fold additionally gains the answer's group as one of its own answers.
(= (sk-member-step $key $_acc $fold)
   (case $fold (
      ((CPU FoldAllCompiled $args $_res)
         (let* (($fold-key (sk-fold $args))
                ($_use (sk-add-use! $key $fold-key))
                ($_rate (sk-rate-dirty! $fold-key $key)))
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

;; A fold a forward join reads that no search has expanded, other than a base
;; rate, whose estimate the cache holds; the run searches it before evaluating.
(: &sk_forward_folds (SpaceOf (Number SkPattern)))
!(bind! &sk_forward_folds (new-space))

(: sk-forward-note-fold! (-[det]-> SkPattern Atom))
(= (sk-forward-note-fold! $premise)
   (case (copy_term $premise) (
      ((CPU $fun $args $res)
         (if (if (sk-expanded? (CPU $fun $args $res)) true
                (case (base-rate-aggregate-key $args) (
                   ((base-rate-aggregate-key-value $_kbid $_pattern $_mode) true)
                   (no-base-rate-aggregate-key false))))
            ()
            (let $_noted (add-atom &sk_forward_folds ((sk-node-hash (CPU $fun $args $res)) (CPU $fun $args $res))) ())))
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

(= (sk-advance! (sk-partial $owner $rule $concl $premises $remaining $keys))
   (case $remaining (
      (() (sk-complete-row! $owner $rule $concl $premises $keys))
      ((cons $premise $rest)
         (case $premise (
            ((CPU $fun $args $_res)
               (if (== $fun FoldAllCompiled)
                  (let $_child
                     (if (== (search-id-value sk_forward_run) 1) (sk-forward-note-fold! $premise)
                        (let $score (sk-fold-child-score $args (sk-join-score $owner $rule $remaining) (sk-rate-entries $args))
                           (if (> $score 0.0) (sk-add-child! $owner (copy_term $premise) $score) ())))
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
            ;; A forward run reads a premise from what exists, never waiting.
            ($_fact
               (if (== (search-id-value sk_forward_run) 1)
                  (fold-semidet (sk-extend-waiter-step (sk-partial $owner $rule $concl $premises $remaining $keys)) ()
                     (sk-forward-keys (copy_term $premise)))
                  (sk-wait-on! $owner $rule $premise
                     (sk-partial $owner $rule $concl $premises $remaining $keys))))))))))

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
          ($_noted
             (let* (($owner-ctx (node-context $owner)) ($premise-ctx (node-context $premise)))
                (if (== $owner-ctx $premise-ctx) ()
                   (let $_waiting (sk-note-context! $owner-ctx (ctx-wait $hash $premise $waiter))
                      ;; Only an Assuming query's root reads into its context
                      ;; from outside, and it leaves with the context.
                      (sk-note-context! $premise-ctx (ctx-root (sk-node-hash $owner) $owner))))))
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

;; A settled join (its rule reads one part of a compound, settling it; see
;; connective_settling.md) reads a part only when a certain stored fact fixes
;; its value, as it does for a ground key, and binds that value: the part's
;; formulas then run when the join is built, and a part that does not settle
;; builds no row. A derived value never settles (modus ponens leaves its
;; confidence below 1), so a settled join builds no row it does not need.
(: sk-settles-step (-[det]-> Bool SkPattern Bool))
(= (sk-settles-step $seen $premise)
   (if $seen true (case $premise (((CPU $fun $_args $_res) (== $fun SettlesFormula)) ($_fact false)))))

(: sk-certain-tv-step (-[det]-> (List TV) SkFact (List TV)))
(= (sk-certain-tv-step $tvs ($_type $_kbctx $_proof $tv))
   (case $tv (((STV $_s $c) (if (>= $c 1.0) (cons $tv $tvs) $tvs)) ($_other $tvs))))

(: sk-settled-read? (-[det]-> (List SkPattern) Statement KBContext TV Bool))
(= (sk-settled-read? $premises $type $kbctx $tv)
   (if (fold-flat sk-settles-step false $premises)
      (if (== (extract-vars $type) ())
         (case (fold-flat sk-certain-tv-step () (sk-leaf-facts $type $kbctx sk-any-filter)) (
            ((cons $certain $_more) (= $tv $certain))
            (() false)))
         false)
      true))

(: sk-extend-now! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(= (sk-extend-now! (sk-partial $owner $rule $concl $premises $remaining $keys) $key)
   (case $remaining (
      ((cons $premise $rest)
         (if (case $premise (
                ((CPU $_fun $args $_res) (= (sk-group $args) $key))
                (($type $kbctx $_proof $tv)
                   (if (= (sk-key $type $kbctx) $key)
                      (if (chainer-acyclic-term? $concl) (sk-settled-read? $premises $type $kbctx $tv) false)
                      false))))
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
      ;; Expansion applies no rule to a certain statement; a forward run's
      ;; upward joins skip it here, where their conclusion is first bound.
      (if (if (== (search-id-value sk_forward_run) 1) (sk-certain? $type (sk-leaf-facts $type $kbctx sk-any-filter)) false) ()
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
                                ($_touched (sk-touch-key! $khash $key))
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
                  ())))))))

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

(: sk-drop-stale-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-drop-stale-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_removed
             (collapse (match &sk_stale_reader ($hash $stored $khash $rhash)
                (if (=alpha $stored $key) (remove-atom &sk_stale_reader ($hash $stored $khash $rhash)) (empty))))))
      ()))

(: sk-remove-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-remove-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_removed
             (collapse (match &sk_reader ($hash $stored $khash $rhash)
                (if (=alpha $stored $key) (remove-atom &sk_reader ($hash $stored $khash $rhash)) (empty))))))
      ()))

;; A stale row moves from a key's readers to its stale readers (see
;; sk-unlink-reader!).
(: sk-stale-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-stale-reader! $khash $rhash $_acc $key)
   (let* (($_removed (sk-remove-reader! $khash $rhash () $key))
          ($hash (index-hash $key))
          ($_row (add-atom &sk_stale_reader ($hash $key $khash $rhash))))
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
;; A goal in a context that sees the world is also concluded by the rules
;; compiled for the main context (connective adapters among them), with the
;; goal's context: the world's rules hold there too. Rules whose conclusion
;; follows the goal's context are matched by sk-rule-match already.
(= (sk-world-rule-match $goal)
   (case (copy_term $goal) (
      (($type ($kbid $ctx $_vars) $proof $tv)
         (if (context-world? $ctx)
            (let $main (make-kb-context (brand KB $kbid) MAIN Nil)
               (match ccls_index (($type $rule-kbctx $proof $tv) $rule-id $args)
                  (if (== $rule-kbctx $main)
                     (if (= ($type $proof $tv) (sk-goal-parts $goal))
                        (sk-match $rule-id (contextualize-rule-args $goal $args) $goal)
                        (empty))
                     (empty))))
            (empty)))
      ($_cpu (empty)))))

(: sk-world-goal? (-[det]-> SkFact Bool))
(= (sk-world-goal? ($_type ($_kbid $ctx $_vars) $_proof $_tv)) (context-world? $ctx))

(: sk-goal-parts (-[det]-> SkFact Atom))
(= (sk-goal-parts ($type $_kbctx $proof $tv)) ($type $proof $tv))

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
;; goal's hypothetical context. In the context of an Assuming query, which sees
;; the world, a premise is read in the context when the assumptions can change
;; it, and in the main context otherwise, where its value is the same and its
;; work is shared (docs/metta/assumption_queries.md).
(: contextualize-rule-premise (-[det]-> SkFact SkPattern SkPattern))
(= (contextualize-rule-premise ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv) $premise)
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (let $fact-kb
               (if (context-world? $ctx)
                  (if (if (== $prem-ctx MAIN) true (== $prem-ctx $ctx))
                     (if (context-affected? $ctx $type)
                        (make-kb-context (brand KB $kbid) $ctx $vars)
                        (make-kb-context (brand KB $kbid) MAIN Nil))
                     (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars))
                  (if (if (== $prem-ctx MAIN)
                         (if (== $ctx MAIN) false (context-vars-in-type? $type $vars))
                         false)
                     (make-kb-context (brand KB $kbid) $ctx $vars)
                     (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars)))
               (assemble-stored-runtime-fact $type $fact-kb $prf $tv)))
         ;; A fold over members the assumptions can change folds them in the
         ;; context: its arguments name the context instead of the KB.
         ((CPU $fun $args $res)
            (if (if (== $fun FoldAllCompiled)
                   (if (context-world? $ctx)
                      (let $pattern (car-atom (cdr-atom $args)) (context-pattern-affected? $ctx $pattern))
                      false)
                   false)
               (CPU $fun (cons-atom (make-kb-context (brand KB $kbid) $ctx $vars) (cdr-atom $args)) $res)
               (CPU $fun $args $res)))))))

(: contextualize-rule-args (-[semidet]-> SkFact (List SkPattern) (List SkPattern)))
(= (contextualize-rule-args $goal $args)
   (map-semidet (contextualize-rule-premise $goal) $args))

;; An antecedent completion reads its consequence C as an observation of C.
;; C's predicate is observed when a statement of it is stored (a forward run's
;; copy of a derived value is not an observation), or when an
;; inverse rule (an inversion or a completion) concludes it from observations
;; of its consequences. A predicate only forward rules conclude is predicted,
;; from the completed conjunct through the rule itself or from other causes,
;; and tells nothing about the conjunct: the completion's first premise asks
;; this with the predicate's head and arity (-1 for a bare symbol), so the
;; rule start prunes it.
(: open-arguments (-[det]-> Number (List Atom)))
(= (open-arguments $arity)
   (if (<= $arity 0) () (cons $_argument (open-arguments (- $arity 1)))))

(: inverse-conclusion-proof? (-[det]-> Atom Bool))
(= (inverse-conclusion-proof? $proof)
   (case $proof (
      ((cons (inverted $_r $_w $_p $_t) $_obs) true)
      ((cons (antecedent-completion $_c $_i $_w2 $_p2 $_t2) $_known) true)
      ($_forward false))))

(: forward-copy? (-[det]-> Atom Atom Atom Atom Bool))
(= (forward-copy? $type $kbctx $proof $tv)
   (let $hash (index-hash (sk-key $type $kbctx))
      (not (== (collapse (once (match &sk_forward_stored ($hash $_key $copy $_ev $_deps)
                  (if (=alpha $copy ($type $kbctx $proof $tv)) true (empty)))))
               ()))))

(: observed-predicate? (-[det]-> Atom Atom Number Bool))
(= (observed-predicate? $kbid $head $arity)
   (let $type (if (< $arity 0) $head (cons-atom $head (open-arguments $arity)))
      (if (== (collapse (once (match &kb ($type ($kbid $ctx $vars) $proof $tv)
                  (if (forward-copy? $type ($kbid $ctx $vars) $proof $tv) (empty) true))))
             ())
         (not (== (collapse (once (match ccls_index (($type ($kbid $_rctx $_rvars) $rule-proof $_rtv) $_id $_args)
                  (if (inverse-conclusion-proof? $rule-proof) true (empty)))))
                  ()))
         true)))

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
;; A dormant rule is not started (docs/metta/dormant_rules.md).
;; Dormancy is judged in the main context; in a context that sees the world,
;; assumptions can support what the main context lacks, so every rule runs.
(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (if (if (sk-world-goal? $goal) false (rule-dormant? $rule)) false (= (copy_term $goal) (copy_term $owner)))
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
          ($shape (pattern-shape $pattern))
          ($compiled (sk-shape-members $kbid $shape))
          ($members (if (== $shape $pattern) $compiled (map-semidet (sk-narrow-member $pattern) $compiled))))
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
   (let* (($source (quote ($kbid $shape)))
          ($hash (index-hash $source)))
      (case (collapse (once (match &sk_fold_members ($hash $stored $member)
               (if (=alpha $stored $source) $member (empty))))) (
         ((cons $found $_rest) (cons $found ()))
         (()
            (case (collapse (once (mm2compileQuery (brand KB $kbid) (: $_h (brand Statement $shape) $_i)))) (
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
                ($leaf-facts (sk-leaf-facts $type $kbctx (sk-filter $proof $tv)))
                ($_leaves (fold-semidet (sk-leaf-answer-step $node) () $leaf-facts))
                ($owner (copy_term $node))
                (($rule-type $rule-kbctx $_node-proof $_node-tv) (copy_term $node)))
            ;; No rule is applied to a certain statement.
            (if (sk-certain? $type $leaf-facts) ()
               (let* (($goal (assemble-stored-runtime-fact $rule-type $rule-kbctx $_rule-proof $_rule-tv))
                      ($matches (append-flat (collapse (sk-rule-match $goal)) (collapse (sk-world-rule-match $goal)))))
                  (fold-semidet (sk-start-rule-step $owner) () $matches)))))))))

(: sk-fold-answer-step (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-fold-answer-step $fold $acc $key) (sk-member-step $key $acc $fold))

;; --- Activation of facts and rules added after expansion --------------------

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
      ((sk-key $type $kbctx)
         (fold-semidet (sk-activate-fact-on $key) ()
            (collapse (match &sk_node_terms ($type $kbctx $node) $node))))
      ($_fold ()))))

(: sk-activate-rule-row (-[semidet]-> Number Atom SkeletonRuleDef Atom))
(= (sk-activate-rule-row $id $_acc (sk-rule-def $conclusion $args))
   (let* ((($type $kbctx $_proof $_tv) $conclusion))
      (fold-semidet (sk-activate-rule-on $id $conclusion $args) ()
         (collapse (match &sk_node_terms ($type $kbctx $node) $node)))))

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

;; Breadth-first from the roots over child links. Expanding a new node costs
;; one step and walking an expanded node spends the walk allowance. Increasing
;; the budget extends the same deterministic order.
(: sk-children (-[det]-> SkPattern (List SkPattern)))
(= (sk-children $node)
   (let $hash (sk-node-hash $node)
      (collapse (match &sk_child ($hash $stored $child)
         (if (=alpha $stored $node) $child (empty))))))

;; Whether a node's search can still give it answers: it, or a node below it,
;; is unexpanded or has work waiting at it (parked deliveries, deferred joins
;; or rows). A node whose search is exhausted never answers without new
;; knowledge. Each node is visited once; the walk stops at the first such node.
(: SkeletonGrowth Type)
(: sk-growth (-[det]-> Bool (List Number) SkeletonGrowth))

(: sk-grows (-[semidet]-> SkeletonGrowth SkPattern SkeletonGrowth))
(= (sk-grows (sk-growth $found $seen) $node)
   (if $found (sk-growth $found $seen)
      (let $hash (sk-node-hash $node)
         (if (stored-list-member? $hash $seen) (sk-growth $found $seen)
            (if (if (sk-expanded? $node)
                   (not (== (collapse (once (superpose (
                              (match &sk_parked ($hash $_seq $_delivery) true)
                              (match &sk_deferred_joins ($hash $_jhash $_join) true)
                              (match &sk_deferred ($hash $_rhash $_deferred) true)))))
                            ()))
                   true)
               (sk-growth true $seen)
               (fold-semidet sk-grows (sk-growth false (cons $hash $seen)) (sk-children $node)))))))

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

;; The walk is best-first by score. Expanding a node costs a step, and the walk
;; ends at the first unexpanded node the budget cannot pay for. Passing through
;; an expanded node spends a separate walk allowance, so revisiting what is
;; already built never takes a step from new expansions; once the allowance is
;; spent, expanded nodes are passed over and the walk goes on to what is left.
;; Equal scores go shallowest first, then in insertion order.
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

;; A node no rule can conclude is expanded without a step when the walk
;; reaches it: its expansion only reads its stored facts. Implications and
;; inheritance links are not, since expanding them installs rules.
(: sk-extensional? (-[semidet]-> SkPattern Bool))
(= (sk-extensional? $node)
   (case $node (
      ((CPU $_fun $_args $_res) false)
      (($type $kbctx $_proof $_tv)
         (if (implication-type? $type) false
            (case $type (
               ((Inheritance $_subj $_concept) false)
               ($_other
                  (== (collapse (once (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $_rp $_rt)))) ())))))))))

(: sk-search-pop! (-[semidet]-> (Number SkeletonFrontier (Heap SkeletonFrontier)) Atom))
(= (sk-search-pop! ($_priority (sk-frontier $node $depth) $rest))
   (if (sk-seen! $node)
      (sk-search! $rest)
      (if (sk-expanded? $node)
         (if (sk-take! sk_walk_budget)
            (let $_resumed (sk-resume! $node) (sk-search! (sk-push-children $depth $node $rest)))
            (sk-search! $rest))
         (if (if (sk-extensional? $node) true (sk-take! sk_budget))
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

;; --- Query contexts -----------------------------------------------------------

;; An Assuming query's contexts leave with it: everything they created is
;; removed from the stores, with the links into them from outside, so nothing
;; a past query assumed is read, updated or walked by a later one
;; (docs/metta/assumption_queries.md). The stores keyed by a node's or key's
;; own hash lose that hash's rows.
(: sk-clear-contexts! (-[semidet]-> Atom))
(= (sk-clear-contexts!)
   (let* (($contexts (the (List Atom) (list_to_set (collapse (match &sk_ctx_items ($ctx $_item) $ctx)))))
          ($_dropped (collapse (match &sk_ctx_items ($_ctx $item) (sk-drop-context-item! $item))))
          ($_cleared (remove-data-rows! &sk_ctx_items (quote ($_ctx2 $_item2))))
          ($_queue
             (collapse (match &sk_answer_queue ($seq (sk-delivery $node $key))
                (if (let* (($node-ctx (node-context $node)) ($key-ctx (key-context $key)))
                       (if (context-world? $node-ctx) true (context-world? $key-ctx)))
                   (remove-atom &sk_answer_queue ($seq (sk-delivery $node $key)))
                   (empty))))))
      (fold-flat sk-forget-context-step () $contexts)))

(: sk-forget-context-step (-[det]-> Atom Atom Atom))
(= (sk-forget-context-step $_acc $ctx) (let $_forgot (context-forget! $ctx) ()))

(: sk-drop-context-item! (-[semidet]-> SkeletonContextItem Atom))
(= (sk-drop-context-item! $item)
   (case $item (
      ((ctx-node $h $node) (sk-drop-node-rows! $h $node))
      ((ctx-root $h $root) (sk-drop-root! $h $root))
      ((ctx-key $h $key) (sk-drop-key-rows! $h $key))
      ((ctx-wait $h $premise $waiter) (let $_r (remove-variant-row! &sk_wait (quote ($h $premise $waiter))) ()))
      ((ctx-answer $h $node $key) (let $_r (remove-variant-row! &sk_answer (quote ($h $node $key))) ()))
      ((ctx-child $h $owner $child) (let $_r (remove-variant-row! &sk_child (quote ($h $owner $child))) ()))
      ((ctx-use $h $key $parent) (let $_r (remove-variant-row! &sk_use (quote ($h $key $parent))) ()))
      ((ctx-link $digest) (let $_r (remove-atom &sk_link ($digest)) ())))))

;; The root's keys are its own key and the answers it registered: statements
;; of the query itself, which nothing else reads.
(: sk-drop-root! (-[semidet]-> Number SkPattern Atom))
(= (sk-drop-root! $h $root)
   (let* (($answers (collapse (match &sk_answer ($h $stored $key) (if (=alpha $stored $root) $key (empty)))))
          ($keys (case (copy_term $root) (
                    (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $answers))
                    ($_cpu $answers))))
          ($_keys (fold-semidet sk-drop-key-step () (list_to_set $keys)))
          ($_links (fold-semidet (sk-drop-answer-link-step $root) () $answers)))
      (sk-drop-node-rows! $h $root)))

(: sk-drop-answer-link-step (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-drop-answer-link-step $root $_acc $key)
   (let* (($digest (link-digest (sk-answer-link $root $key)))
          ($_link (remove-atom &sk_link ($digest))))
      ()))

(: sk-drop-key-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-drop-key-step $_acc $key) (sk-drop-key-rows! (index-hash $key) $key))

(: sk-drop-node-rows! (-[semidet]-> Number SkPattern Atom))
(= (sk-drop-node-rows! $h $node)
   (let $_rows
         (remove-hash-rows!
            (&sk_child &sk_score &sk_expanded &sk_wait &sk_temp_waits &sk_answer &sk_fold
             &sk_member_of &sk_deferred &sk_deferred_joins &sk_parked &sk_roots &sk_seen)
            $h)
      (case (copy_term $node) (
         ;; A fold node in a context takes its fold's key along.
         ((CPU FoldAllCompiled $args $_res) (let $fold-key (sk-fold $args) (sk-drop-key-rows! (index-hash $fold-key) $fold-key)))
         ((CPU $_fun $_args $_res) ())
         (($type $kbctx $_proof $_tv)
            (let* (($_terms (remove-data-rows! &sk_node_terms (quote ($type $kbctx $_n6))))
                   ($prefix
                      (case (statement-prefix-hashes $type) (
                         (() (index-hash (car-atom $type)))
                         ((cons $longest $_shorter) $longest)))))
               (let $_prefix (remove-data-rows! &sk_node_prefix (quote ($prefix $_t $_k $h $_n7))) ())))))))

(: sk-drop-key-rows! (-[semidet]-> Number SkeletonKey Atom))
(= (sk-drop-key-rows! $h $key)
   (let* (($rows (collapse (match &sk_row ($h $stored $rh (sk-row $ident $concl $premises $seq)) ($rh $premises))))
          ($_rows (fold-semidet (sk-drop-row-readers! $h) () $rows))
          ($_hashed
             (remove-hash-rows!
                (&sk_row &sk_stale &sk_support &sk_given_pending &sk_given_granted &sk_forced
                 &sk_forced_used &sk_refresh &sk_restale &sk_restaled &sk_temp_rows &sk_keys
                 &sk_key_epoch &sk_latest &sk_view &sk_reader &sk_stale_reader &sk_unifiers
                 &sk_use &sk_needed &sk_dirty &sk_group_of &sk_answered &sk_partial)
                $h))
          ($_merged (remove-data-rows! &sk_merged (quote (sk-merged $h $_k6 $_d $_v3)))))
      (case $key (
         ((sk-key $type $kbctx)
            (let* (($_terms (remove-data-rows! &sk_key_terms (quote ($type $kbctx $h))))
                   ($_open (remove-data-rows! &sk_key_open (quote ($type $kbctx $h))))
                   ($_reader-terms (remove-data-rows! &sk_reader_terms (quote ($type $kbctx $h $_k15)))))
               (fold-flat (sk-drop-key-prefix! $type $kbctx $h) () (statement-prefix-hashes $type))))
         ($_fold ())))))

(: sk-drop-key-prefix! (-[det]-> Statement KBContext Number Atom Number Atom))
(= (sk-drop-key-prefix! $type $kbctx $h $_acc $prefix)
   (let $_r (remove-data-rows! &sk_key_prefix (quote ($prefix $type $kbctx $h))) ()))

;; A row of a removed key leaves the reader lists of the keys it read, which may
;; lie outside its context.
(: sk-drop-row-readers! (-[semidet]-> Number Atom (Number (List SkPattern)) Atom))
(= (sk-drop-row-readers! $h $_acc ($rh $premises))
   (fold-semidet (sk-drop-reader-link! $h $rh) () (fold-semidet sk-direct-key-step () $premises)))

(: sk-drop-reader-link! (-[semidet]-> Number Number Atom SkeletonKey Atom))
(= (sk-drop-reader-link! $h $rh $_acc $premise-key)
   (let* (($ph (index-hash $premise-key))
          ($_reader (remove-data-rows! &sk_reader (quote ($ph $_k1 $h $rh))))
          ($_stale (remove-data-rows! &sk_stale_reader (quote ($ph $_k2 $h $rh)))))
      ()))

(: sk-dirty-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-dirty-step $_acc $key) (sk-mark-dirty! $key))
