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
(: sk-activate-rules! (-[semidet]-> Atom))
(: sk-activate-facts! (-[semidet]-> Atom))
(: sk-expand! (-[semidet]-> SkPattern Number Number Atom))
(: sk-rule-match (-[nondet]-> SkFact SkeletonMatch))
(: sk-world-rule-match (-[nondet]-> SkFact SkeletonMatch))
;; node, depth, node hash
(: SkeletonFrontier Type)
(: sk-frontier (-[det]-> SkPattern Number Number SkeletonFrontier))
;; a node with its hash
(: SkeletonNodeAt Type)
(: sk-node-at (-[det]-> Number SkPattern SkeletonNodeAt))
(: sk-search! (-[semidet]-> (Heap SkeletonFrontier) Atom))
(: term-cost (-[det]-> $term Number))
(: grows-from? (-[det]-> SkPattern SkPattern Bool))
(: link-open-variables (-[det]-> SkeletonKey SkeletonKey Bool))

;; --- Node identity ----------------------------------------------------------

(: sk-node-hash (-[det]-> SkPattern Number))
(= (sk-node-hash $pattern)
   (case $pattern (
      ((CPU $_fun $args $_res) (index-hash $args))
      (($type $kbctx $_proof $_tv) (index-hash (sk-key $type $kbctx))))))

(: sk-expanded? (-[det]-> Number SkPattern Bool))
(= (sk-expanded? $hash $pattern)
   (not (== (collapse (once (match &sk_expanded ($hash $stored)
               (if (=alpha $stored $pattern) true (empty)))))
            ())))

(: sk-mark-expanded! (-[det]-> Number SkPattern Atom))
(= (sk-mark-expanded! $hash $pattern)
   (let* (($_row (add-atom &sk_expanded ($hash $pattern)))
          ($_taken (sk-work! $hash $pattern -1)))
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
                      ((sk-join-link (sk-partial $join-owner $_rule $_concl $_done $_remaining $_keys) $answer)
                         (let $join-ctx (node-context $join-owner)
                            (if (context-world? $join-ctx) $join-ctx (key-context $answer)))))))
                ($_noted (sk-note-context! $ctx (ctx-link $digest))))
            true))))

(: sk-node-score (-[det]-> Number SkPattern Number))
(= (sk-node-score $hash $node)
   (case (collapse (once (match &sk_score ($hash $stored $score)
            (if (=alpha $stored $node) $score (empty))))) (
      ((cons $score $_rest) $score)
      (() 0.0))))

(: sk-raise-score! (-[det]-> Number SkPattern Number Atom))
(= (sk-raise-score! $hash $node $score)
   (let* (($old (sk-node-score $hash $node)))
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
         (let* (($factor
                   (case (collapse (once (match &kb ($type $kbctx (rule-axiom $_name) $tv) $tv))) (
                      ((cons $tv $_rest) (rule-truth-factor $tv))
                      (() 1.0))))
                ($_set (sk-set-truth-factor! $hash $factor)))
            $factor)))))

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
   (/ (* (sk-node-score (sk-node-hash $owner) $owner) (sk-rule-score $rule))
      (max 1 (fold-semidet sk-open-premise-step 0 $remaining))))

;; A node's index column: the hash of its statement's longest ground prefix,
;; or of its head when it has none.
(: sk-node-prefix (-[det]-> $statement Number))
(= (sk-node-prefix $type)
   (case (statement-prefix-hashes $type) (
      (() (index-hash (car-atom $type)))
      ((cons $longest $_shorter) $longest))))

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
   (let $child-hash (sk-node-hash $child)
      (if (let $_scored (sk-raise-score! $child-hash $child $score) (sk-link-new! (sk-child-link $owner $child)))
         (let* (($hash (sk-node-hash $owner))
                ($_row (add-atom &sk_child ($hash $owner $child $child-hash)))
                ($_pending (sk-link-pending! $hash $owner $child-hash $child))
                ($child-ctx (node-context $child))
                ($_node (sk-note-context! $child-ctx (ctx-node $child-hash $child)))
                ($_link
                   (if (== $child-ctx (node-context $owner)) ()
                      (sk-note-context! $child-ctx (ctx-child $hash $owner $child $child-hash))))
                ($_fresh (add-atom &sk_fresh ($child-hash $child))))
            (sk-index-node! $child))
         ())))

;; --- Pending work -------------------------------------------------------------

;; A walk enters only nodes whose search may still have work: the node or one
;; below it is unexpanded, or holds parked deliveries, deferred joins or
;; deferred rows. Every node of a cycle reaches what the others reach, so the
;; nodes are kept as the components of their cycles, an acyclic graph whose
;; components count their work items and their pending child components; a
;; change of state moves the parents' counts. Whether a node is pending is
;; then one lookup, exact at any time (runtime_helpers.pl, "Pending work").
;; Work items: being unexpanded, each parked delivery, deferred join and
;; deferred row; sk-work! adds or takes them.
(: sk-link-pending! (-[det]-> Number SkPattern Number SkPattern Atom))
(: sk-work! (-[det]-> Number SkPattern Number Atom))
(: sk-pending? (-[det]-> Number SkPattern Bool))
(: sk-pending-children (-[det]-> Number SkPattern (List SkeletonNodeAt)))
(: sk-drop-pending! (-[det]-> Number SkPattern Atom))
;; Parked deliveries, deferred joins or deferred rows at a node's hash.
(: sk-holds-work? (-[det]-> Number Bool))

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

;; A stored fact of strength 0 or 1 at confidence 1 makes its statement known:
;; every reader, a conditioned one included, reads it as that fact.
(: sk-known-leaf-step (-[det]-> Bool SkFact Bool))
(= (sk-known-leaf-step $known ($_type $_kbctx $_proof $tv)) (if $known true (certain-tvs? (cons $tv ()))))

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

;; The hashes of the registered keys whose term unifies with a pattern: through
;; the longest ground prefix of the pattern when it has one (see kb-facts).
(: sk-unifying-key-hashes (-[det]-> Statement KBContext (List Number)))
(= (sk-unifying-key-hashes $type $kbctx)
   (case (statement-prefix-hashes $type) (
      (() (collapse (match &sk_key_terms ($type $kbctx $hash) $hash)))
      ((cons $prefix $_shorter)
         (let $shorter (statement-open-probes $type)
            (append-flat
               (collapse (match &sk_key_prefix ($prefix $type $kbctx $hash) $hash))
               (collapse (let $open (superpose $shorter) (match &sk_key_open ($open $type $kbctx $hash) $hash)))))))))

;; The reading keys with a cached set that unify with a key, each as its hash
;; and the reader, found as sk-unifying-key-hashes finds keys.
(: sk-unifying-readers (-[det]-> Statement KBContext (List Atom)))
(= (sk-unifying-readers $type $kbctx)
   (case (statement-prefix-hashes $type) (
      (() (collapse (match &sk_reader_open ($_any $type $kbctx $rhash $reader) ($rhash $reader))))
      ((cons $prefix $_shorter)
         (let $shorter (statement-open-probes $type)
            (append-flat
               (collapse (match &sk_reader_prefix ($prefix $type $kbctx $rhash $reader) ($rhash $reader)))
               (collapse (let $open (superpose $shorter)
                  (match &sk_reader_open ($open $type $kbctx $rhash $reader) ($rhash $reader))))))))))

;; A dropped key leaves the indexes by term.
(: sk-unindex-key! (-[det]-> Statement KBContext Number Atom))
(= (sk-unindex-key! $type $kbctx $h)
   (let* (($prefixes (statement-prefix-hashes $type))
          ($open (statement-open-hash $type))
          ($_terms (remove-data-rows! &sk_key_terms (quote ($type $kbctx $h))))
          ($_open (remove-data-rows! &sk_key_open (quote ($open $type $kbctx $h))))
          ($_reader (remove-data-rows! &sk_reader_open (quote ($open $type $kbctx $h $_reader-key))))
          ($_prefixes
             (collapse (let $prefix (superpose $prefixes)
                (progn
                   (remove-data-rows! &sk_key_prefix (quote ($prefix $type $kbctx $h)))
                   (remove-data-rows! &sk_reader_prefix (quote ($prefix $type $kbctx $h $_prefix-key))))))))
      ()))

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
                                   (let* (($prefixes (statement-prefix-hashes $type))
                                          ($open (statement-open-hash $type))
                                          ($_prefixes
                                             (collapse (let $prefix (superpose $prefixes)
                                                (add-atom &sk_reader_prefix ($prefix $type $kbctx $khash $key))))))
                                      (add-atom &sk_reader_open ($open $type $kbctx $khash $key))))))
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

;; Base rates and implication instance folds follow their members
;; incrementally, as a tally of each member's contribution (see sk-fold-view).
(: sk-instance-fold? (-[det]-> Atom Bool))
(= (sk-instance-fold? ($_kb $_pattern $_extractor $_init $_function $finish $_mode))
   (stored-list-member? $finish (implication-instance implication-instance-ctv)))

(: sk-instance-fold-key? (-[det]-> SkeletonKey Bool))
(= (sk-instance-fold-key? $key)
   (case $key (
      ((sk-fold $args) (sk-instance-fold? $args))
      ($_other false))))

(: sk-rate-fold? (-[det]-> SkeletonKey Bool))
(= (sk-rate-fold? $key)
   (if (sk-instance-fold-key? $key) true
      (case $key (
         ((sk-fold ($_kb $_pattern $_extractor $_init $_function $finish $_mode)) (base-rate-finish? $finish))
         ($_other false)))))

;; A member that joined a tally fold, or whose value changed, is taken into it
;; when a query next needs the fold or it is next read; an implication
;; instance fold is also brought current by the evaluation (see
;; sk-instance-checks!).
(: sk-rate-dirty! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-rate-dirty! $fold $member)
   (if (sk-rate-fold? $fold)
      (let* (($hash (index-hash $fold)) ($mhash (index-hash $member)))
         (if (== (collapse (once (match &sk_rate_dirty ($hash $mhash $stored-fold $stored)
                    (if (=alpha $stored $member) (if (=alpha $stored-fold $fold) true (empty)) (empty)))))
                 ())
            (let* (($_row (add-atom &sk_rate_dirty ($hash $mhash $fold $member)))
                   ($_changed
                      (if (if (sk-instance-fold-key? $fold) (not (space-row-present? &sk_instance_changed ($hash $_stored))) false)
                         (add-atom &sk_instance_changed ($hash $fold))
                         ())))
               ())
            ()))
      ()))

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

;; A root's population prior, `(population-prior pattern)` (sk-start-prior!).
(: population-prior-proof? (-[det]-> Atom Bool))
(= (population-prior-proof? $proof)
   (if (if (is-expr $proof) (not (== $proof ())) false) (== (car-atom $proof) population-prior) false))

;; An antecedent completion, `((antecedent-completion rule index with cpu
;; prior) premises)`.
(: sk-completion-proof? (-[det]-> Atom Bool))
(= (sk-completion-proof? $proof)
   (if (if (is-expr $proof) (not (== $proof ())) false)
      (let $head (car-atom $proof)
         (if (is-var $head) false
            (case (copy_term $head) (((antecedent-completion $_rule $_idx with $_prior $_tv) true) ($_other false)))))
      false))

(: sk-completion-waiter? (-[det]-> SkeletonWaiter Bool))
(= (sk-completion-waiter? $waiter)
   (case $waiter (
      ((sk-partial $_owner $_rule ($_type $_kbctx $proof $_tv) $_done $_remaining $_keys) (sk-completion-proof? $proof))
      ($_other false))))

(: sk-prior-answers (-[det]-> SkPattern (List SkeletonKey)))
(= (sk-prior-answers $node)
   (let $hash (sk-node-hash $node)
      (collapse (match &sk_prior_answer ($hash $stored $key) (if (=alpha $stored $node) $key (empty))))))

;; --- Partial joins and rows -------------------------------------------------

;; A fold a forward join reads that no search has expanded, other than a base
;; rate, whose estimate the cache holds; the run searches it before evaluating.
(: &sk_forward_folds (SpaceOf (Number SkPattern)))
!(bind! &sk_forward_folds (new-space))

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
(: SkeletonReading Type)
(: sk-reading (-[det]-> (List SkeletonKey) (List SkPattern) SkeletonReading))
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

(= (sk-advance! (sk-partial $owner $rule $concl $done $remaining $keys))
   (case $remaining (
      (()
         (let (sk-reading $_none $premises) (fold-semidet sk-read-step (sk-reading $keys ()) $done)
            (sk-complete-row! $owner $rule $concl $premises $keys)))
      ((cons $premise $rest)
         (case $premise (
            ((CPU $fun $args $_res)
               (if (== $fun FoldAllCompiled)
                  (let $_child
                     (if (== (search-id-value sk_forward_run) 1) (sk-forward-note-fold! $premise)
                        (let $score (sk-fold-child-score $args (sk-join-score $owner $rule $remaining) (sk-rate-entries $args))
                           (if (> $score 0.0) (sk-add-child! $owner (copy_term $premise) $score) ())))
                     (sk-advance!
                        (sk-partial $owner $rule $concl (cons $premise $done) $rest
                           (cons (sk-fold $args) $keys))))
                  (if (== $fun GroupedFoldAllCompiled)
                     (sk-wait-on! $owner $rule $premise
                        (sk-partial $owner $rule $concl $done $remaining $keys))
                     (if (== (extract-vars $args) ())
                        (fold-semidet
                           (sk-cpu-step
                              (sk-partial $owner $rule $concl $done $remaining $keys))
                           ()
                           (collapse (cpu-call 0 $fun $args)))
                        ;; Truth-value formulas run during evaluation.
                        (sk-advance!
                           (sk-partial $owner $rule $concl (cons $premise $done) $rest $keys))))))
            ;; A forward run reads a premise from what exists, never waiting.
            ($_fact
               (if (== (search-id-value sk_forward_run) 1)
                  (fold-semidet (sk-extend-waiter-step (sk-partial $owner $rule $concl $done $remaining $keys)) ()
                     (sk-forward-keys (copy_term $premise)))
                  (sk-wait-on! $owner $rule $premise
                     (sk-partial $owner $rule $concl $done $remaining $keys))))))))))

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
             (if (sk-expanded? $hash $premise) ()
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
                ((sk-partial $_owner $_rule $_concl $_done $remaining $_keys)
                   (sk-add-child! $owner (copy_term $premise) (sk-join-score $owner $rule $remaining)))))))
      (fold-semidet (sk-extend-waiter-step $waiter) ()
         (if (sk-completion-waiter? $waiter) (append-flat (sk-answers $premise) (sk-prior-answers $premise)) (sk-answers $premise)))))

(: sk-extend-waiter-step (-[semidet]-> SkeletonWaiter Atom SkeletonKey Atom))
(= (sk-extend-waiter-step $waiter $_acc $key) (sk-extend! (copy_term $waiter) $key))

;; A join is extended by an answer once, however the answer reaches it (read
;; when the join starts waiting, or delivered later); a computation that
;; samples would otherwise draw again. Once the row allowance is spent, a join
;; an answer reaches stops there: the pair waits once with the join's owner, so
;; a recursive rule cannot keep extending joins whose rows could not be kept
;; anyway. Joins of the query's roots always proceed.
(= (sk-extend! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
   (if (if (sk-root? $owner) true (> (search-id-value sk_row_budget) 0))
      (if (sk-link-new! (sk-join-link (sk-partial $owner $rule $concl $done $remaining $keys) $key))
         (sk-extend-now! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
         ())
      (let* (($hash (sk-node-hash $owner))
             ($join (sk-join (sk-partial $owner $rule $concl $done $remaining $keys) $key))
             ($jhash (index-hash $join)))
         (if (== (collapse (once (match &sk_deferred_joins ($hash $jhash $_join) true))) ())
            (let* (($_deferred (add-atom &sk_deferred_joins ($hash $jhash $join)))
                   ($_pending (sk-work! $hash $owner 1))
                   ($_counted (query_metric_increment joins-deferred)))
               ())
            ()))))

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
            (() false)))
         false)
      true))

(: sk-extend-now! (-[semidet]-> SkeletonWaiter SkeletonKey Atom))
(= (sk-extend-now! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
   (case $remaining (
      ((cons $premise $rest)
         ;; The key as registered, before later premises bind it (sk-read-step).
         (let $registered (copy_term $key)
         (if (case $premise (
                ((CPU $_fun $args $_res) (= (sk-group $args) $key))
                (($type $kbctx $_proof $tv)
                   (if (= (sk-key $type $kbctx) $key)
                      (if (chainer-acyclic-term? $concl) (sk-settled-read? $done $remaining $type $kbctx $tv) false)
                      false))))
            (sk-advance!
               (sk-partial $owner $rule $concl (cons $premise $done) $rest (cons $registered $keys)))
            ())))
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
   (if (population-prior-proof? $proof) (sk-prior-answer! (sk-node-hash $owner) $owner $key) (sk-add-answer! $owner $key)))

(: sk-prior-answer! (-[semidet]-> Number SkPattern SkeletonKey Atom))
(= (sk-prior-answer! $hash $owner $key)
   (if (space-row-present? &sk_prior_answer ($hash $owner $key)) ()
      (let* (($_row (add-atom &sk_prior_answer ($hash $owner $key)))
             ($waiters
                (collapse (match &sk_wait ($hash $stored $waiter)
                   (if (=alpha $stored $owner) (if (sk-completion-waiter? $waiter) $waiter (empty)) (empty))))))
         (fold-semidet (sk-extend-step $key) () $waiters))))

(= (sk-complete-row! $owner $rule $concl $premises $keys)
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
      ;; (HasLeg Dog 4) from (Member Dog Dog) and (HasLeg Dog 4) itself, is no
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
         ;; The rows of the query's roots are its compiled scaffold and always
         ;; fit; every other row spends the allowance.
         (if (if (sk-root? $owner) true (sk-take! sk_row_budget (term-cost $type)))
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
               (sk-row-answer! $owner $key $proof))
            ;; A row waits once, however often its join completes meanwhile.
            (let $hash (sk-node-hash $owner)
               (if (== (collapse (once (match &sk_deferred ($hash $rhash $_deferred) true))) ())
                  (let* (($_deferred
                            (add-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys))))
                         ($_pending (sk-work! $hash $owner 1))
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
;; after the allowance is spent waits in &sk_deferred for a later walk. A row
;; costs more the larger its statement, as expanding a fact node does
;; (term-cost, runtime_helpers.pl), so a step costs the same however large the
;; terms a recursive rule builds, such as (Num (succ (succ ...))) from
;; (Num $x) → (Num (succ $x)). A fold's arguments do not grow that way.
(: sk-root? (-[det]-> SkPattern Bool))
(= (sk-root? $node)
   (let $hash (sk-node-hash $node)
      (not (== (collapse (once (match &sk_roots ($hash $root) (if (=alpha $root $node) true (empty))))) ()))))

(: sk-take! (-[det]-> CounterKey Number Bool))
(= (sk-take! $counter $cost)
   (let $left (search-id-value $counter)
      (if (<= $left 0) false
         (progn (change-state! $counter (- $left $cost)) true))))

;; Work left over by an earlier query waits with its node and resumes when a
;; later walk reaches that node, so it never spends an unrelated query's
;; budget: parked deliveries are queued again, and while rows are allowed,
;; deferred joins are extended and deferred rows completed.
(: sk-deferred-step (-[semidet]-> Atom SkeletonDeferred Atom))
(= (sk-deferred-step $_acc (sk-deferred $owner $rule $concl $premises $keys))
   (sk-complete-row! $owner $rule $concl $premises $keys))

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
                   (collapse (match &sk_deferred_joins ($hash $jhash (sk-join $waiter $key))
                      (if (=alpha (sk-waiter-owner $waiter) $node)
                         (let $_removed (remove-atom &sk_deferred_joins ($hash $jhash (sk-join $waiter $key)))
                            (sk-join $waiter $key))
                         (empty)))))
                ($_taken (sk-work! $hash $node (- 0 (length $joins))))
                ($_joined (fold-semidet sk-deferred-join-step () $joins))
                ($deferred
                   (collapse (match &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys))
                      (if (=alpha $owner $node)
                         (let $_removed
                            (remove-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys)))
                            (sk-deferred $owner $rule $concl $premises $keys))
                         (empty)))))
                ($_completed (sk-work! $hash $node (- 0 (length $deferred)))))
            (fold-semidet sk-deferred-step () $deferred)))))

(: sk-waiter-owner (-[det]-> SkeletonWaiter SkPattern))
(= (sk-waiter-owner (sk-partial $owner $_rule $_concl $_done $_remaining $_keys)) $owner)

(: sk-deferred-join-step (-[semidet]-> Atom SkeletonJoin Atom))
(= (sk-deferred-join-step $_acc (sk-join $waiter $key)) (sk-extend! (copy_term $waiter) $key))

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

;; Compare the whole key without binding its hypothetical individual to an
;; unrelated fixed world individual. A contextual assumption is indexed by its
;; context; type and context must retain the same variable-sharing shape.
(: judgment-assumed-key? (-[det]-> Atom KBContext Bool))
(= (judgment-assumed-key? $type $kbctx)
   (let ($probe-type $probe-ctx) (copy_term (data $type $kbctx))
      (not (== (collapse (once (match &kb ($assumed $probe-ctx $proof $_tv)
         (if (assumption-proof? (brand Proof $proof))
            (if (=alpha (data $probe-type $probe-ctx) (data $assumed $probe-ctx)) true
               ;; An open reader can consume a ground assumption. Match a
               ;; copy so this test cannot bind the rule's premise variables;
               ;; non-ground hypothetical keys still require alpha identity.
               (if (== (extract-vars $assumed) ())
                  (if (= (copy_term $probe-type) $assumed) true (empty))
                  (empty)))
            (empty))))) ()))))

;; A MAIN premise mentioning the goal's context variables or reading an exact
;; assumed key is read in the goal's hypothetical context. In the context of
;; an Assuming query, which sees the world, a premise is read in the context when the assumptions can change
;; it, and in the main context otherwise, where its value is the same and its
;; work is shared (docs/metta/assumption_queries.md).
(: contextualize-rule-premise (-[det]-> SkFact SkPattern SkPattern))
(= (contextualize-rule-premise ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv) $premise)
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (let*
               (($fact-kb
                  (if (context-world? $ctx)
                     (if (if (== $prem-ctx MAIN) true (== $prem-ctx $ctx))
                        (if (context-affected? $ctx $type)
                           (make-kb-context (brand KB $kbid) $ctx $vars)
                           (make-kb-context (brand KB $kbid) MAIN Nil))
                        (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars))
                     (if (if (== $prem-ctx MAIN)
                            (if (== $ctx MAIN) false
                               (if (context-vars-in-type? $type $vars) true
                                  ;; Exact assumed keys belong to this judgment
                                  ;; for every reader, including a lowered Not.
                                  (judgment-assumed-key? $type
                                     (make-kb-context (brand KB $kbid) $ctx $vars))))
                            false)
                        (make-kb-context (brand KB $kbid) $ctx $vars)
                        (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars))))
                ;; An explicitly STV-typed implication premise requests its
                ;; positive judgment. Keep full CTV rule reads in their source
                ;; context and route only main-context STV reads privately.
                ($read-kb
                   (if (if (head-is? $tv STV) (implication-type? (brand Statement $type)) false)
                      (case $fact-kb (
                         (($source-kb $source-ctx $source-vars)
                            (if (if (== $source-ctx MAIN) (== $source-vars Nil) false)
                               (let* (($source (statement-query-kb (brand KB $source-kb)))
                                      ($query-kb (brand KB (implication-query $source))))
                                  (make-kb-context $query-kb MAIN Nil))
                               $fact-kb))
                         ($_other $fact-kb)))
                      $fact-kb)))
               (assemble-stored-runtime-fact $type $read-kb $prf $tv)))
         ;; A fold over members the assumptions can change folds them in the
         ;; context: its arguments name the context instead of the KB.
         ((CPU $fun $args $res)
            (if (if (== $fun FoldAllCompiled)
                   (if (context-world? $ctx)
                      (let $pattern (car-atom (cdr-atom $args)) (context-pattern-affected? $ctx $pattern))
                      false)
                   false)
               (CPU $fun (cons-atom (make-kb-context (brand KB $kbid) $ctx $vars) (cdr-atom $args)) $res)
               (CPU $fun $args $res)))
         ;; A query judgment reads its explicit source context in another KB
         ;; namespace; that premise keeps its own context.
         ($_other-kb $premise)))))

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
   ;; Private implication judgments get their scaffold when expanded. An
   ;; explicit STV premise may reach one before that scaffold is installed.
   (if (head-is? $kbid implication-query) (implication-type? $type)
   (let $lookup-type (copy_term $type)
      (not (== (collapse (once (match ccls_index
                  (($lookup-type ($kbid $_stored-ctx $_stored-vars) $_stored-proof $_stored-tv)
                   $_rule-id $_stored-args)
                  true)))
               ())))))

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
               (if (== (kb-facts (brand Statement $type) (brand KBContext (data $kbid $_c2 $_v2))) ())
                  (not (prefilter-head-concludable? $type $kbid))
                  false)
               false))))))

(: prefilter-prunes-walk (-[det]-> (List SkPattern) Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

;; --- Complete predicates (docs/metta/complete_predicates.md) ----------------

;; A KB may declare that a predicate's rules and facts are the only ways one of
;; its statements becomes true. Declared before knowledge is added.
(: &complete_predicates (SpaceOf (KB Atom)))
!(bind! &complete_predicates (new-space))

(: set-complete-predicate (-[det]-> KB Atom Bool))
(= (set-complete-predicate $kb $head)
   (if (space-row-present? &complete_predicates ($kb $head)) true
      (let $_row (add-atom &complete_predicates ($kb $head)) true)))

;; A ground statement of a complete predicate in the main context or in an
;; Assuming query's context, which holds the world's facts and rules with its
;; assumptions; an implication query's hypothetical contexts are not complete.
(: complete-statement? (-[det]-> Atom Atom Bool))
(= (complete-statement? $type ($kbid $ctx $_vars))
   (if (if (== $ctx MAIN) true (context-world? $ctx))
      (if (== (extract-vars $type) ())
         (let* (($kb (brand KB $kbid)) ($head (if (is-expr $type) (car-atom $type) $type)))
            (space-row-present? &complete_predicates ($kb $head)))
         false)
      false))

;; A rule applied forward, `(by rule premises)`, negated or not: one of the
;; ways its conclusion becomes true, unlike inversions, completions and
;; projections, which are evidence.
(: rule-application-proof? (-[det]-> Atom Bool))
(= (rule-application-proof? $proof)
   (if (is-expr $proof)
      (let $head (car-atom $proof)
         (if (is-var $head) false
            (if (== $head by) true
               (if (== $head negated) (rule-application-proof? (car-atom (cdr-atom $proof))) false))))
      false))

;; A rule applies to a node when its conclusion fits the whole node pattern;
;; its row is built from the statement and context alone, since a row belongs
;; to its key and each reader applies its own proof and truth-value pattern.
;; A dormant rule is not started (docs/metta/dormant_rules.md).
;; Dormancy is judged in the main context; in a context that sees the world,
;; assumptions can support what the main context lacks, so every rule runs.
;; A rule application concluding a complete statement is never pruned before
;; it starts: a premise with no fact and no rule is false or unknown, and the
;; closed read tells which from the join waiting on it (sk-settled?).
(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (if (if (sk-world-goal? $goal) false (rule-dormant? $rule)) false (= (copy_term $goal) (copy_term $owner)))
      (if (if (case $goal (
                (($type $kbctx $proof $_tv)
                   (if (rule-application-proof? $proof) (complete-statement? $type $kbctx) false))))
             false
             (prefilter-prunes-walk (copy_term $premises)))
         ()
         (sk-advance! (sk-partial $owner $rule $goal () $premises ())))
      ()))

;; The compiled scaffold of a nested implication subgoal that is not itself a
;; compiled total-implication source; its assumption contexts are the query's.
;; A subgoal asking for a rule application's proof, as a statement rule's
;; premise does (docs/metta/derived_implications.md), reads only rules
;; concluding the implication, and gets no scaffold.
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
                      (let $head (car-atom $prf)
                         (if (== $head by) true
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
                     (if (head-is? $kbid implication-query)
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
                           (match rules (runtime-rule-row $scaffold-id
                                 ($scaffold-type $_ctx $_proof $_tv) $_premises)
                              (if (=alpha $scaffold-type $type)
                                 (if (= $lookup-tv $scaffold-tv)
                                    (if (= $lookup-proof (cons $scaffold-head (cons $inner ())))
                                       true (empty))
                                    (empty))
                                 (empty)))
                           (empty))))) ())
                     (foreach-flat inject-compiled-query-adds
                        (collapse
                           (if (if (head-is? $kbid implication-query) false
                                   (if (is-var $tv) true (head-is? $tv CTV)))
                              (let (compilation-plan $goal $adds)
                                 (compile-implication-subgoal-query (brand KB $kbid)
                                    (: $prf $type (if (is-var $tv) (CTV $positive-tv $negative-tv) $tv)))
                                 (compiled-query (brand CompiledQueryGoal (internalize-proof-structure $goal))
                                    (map-flat mm2stmt $adds)))
                              (let* (($stored-kbid (brand KB $kbid))
                                     ($source-kbid (statement-query-kb $stored-kbid)))
                                 (mm2compileQuery $source-kbid (: $prf $type $tv))))))
                     ())))
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
                         ($_child (sk-add-child! $node $member (sk-node-score $hash $node))))
                     (fold-semidet (sk-fold-answer-step $node) () (sk-answers $member))))))))
      (($type $kbctx $proof $tv)
         (let* (($_special
                   (if (> $depth 0) (inject-special-subgoal-query-adds $type $kbctx $proof $tv) ()))
                ($_member (install-member-inheritance-rules! $type $kbctx))
                ($_activate (sk-activate-pending!))
                ($_mark (sk-mark-expanded! $hash $node))
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
                            ($_child (sk-add-child! $owner $general (sk-node-score $hash $owner))))
                        (fold-semidet (sk-unifying-answer! $owner) () (sk-answers $general))))
                  (()
                     (let* (($goal (assemble-stored-runtime-fact $rule-type $rule-kbctx $_rule-proof $_rule-tv))
                            ($matches (append-flat (collapse (sk-rule-match $goal)) (collapse (sk-world-rule-match $goal))))
                            ($_rules (fold-semidet (sk-start-rule-step $owner) () $matches))
                            ($_open
                               (if (== (extract-vars $type) ()) ()
                                  (let $prefix (sk-node-prefix $type) (add-atom &sk_open_node ($prefix $hash $owner))))))
                        (if (== $leaf-facts ()) (sk-start-prior! $owner $type $kbctx $matches) ()))))))))))))

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
;; one lookup per prefix finds it. Implications and inheritance links are
;; expanded on their own, since their expansion installs rules. A root of the
;; current query subsumes nothing: its rows always fit the allowance, so a
;; recursive rule answering it through an instance would never stop.
(: sk-subsumers (-[det]-> Number SkPattern (List SkPattern)))
(= (sk-subsumers $depth $node)
   (case $node (
      ((CPU $_fun $_args $_res) ())
      (($type $_kbctx $_proof $_tv)
         (if (if (== $depth 0) true
                (if (== (extract-vars $type) ()) true
                   (if (implication-type? $type) true (== (car-atom $type) Inheritance))))
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
(: SkeletonPriorFold Type)
(: sk-prior-fold (-[det]-> Number Atom SkeletonPriorFold))
(: sk-prior-folds (-[semidet]-> Statement (List SkeletonMatch) (List SkeletonPriorFold)))
(= (sk-prior-folds $type $matches)
   (collapse
      (let* (((sk-match $rule $premises $_goal) (superpose $matches))
             ((CPU FoldAllCompiled $args $_result) (superpose $premises))
             ((base-rate-aggregate-key-value $kbid $pattern $_mode) (base-rate-aggregate-key $args)))
         (if (= (copy_term $pattern) (copy_term $type))
            (if (positive-only-pattern? (brand KB $kbid) (brand Statement $pattern)) (empty) (sk-prior-fold $rule $args))
            (empty)))))

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
            (let $pattern (copy_term (car-atom (cdr-atom $args)))
               (sk-advance!
                  (sk-partial $owner $rule
                     (assemble-stored-runtime-fact $type $kbctx (brand Proof (population-prior $pattern)) $tv)
                     ()
                     (quote ((CPU FoldAllCompiled $args $rate) (CPU population-prior-tv ($rate) $tv)))
                     ()))))
         (() ())))
      ()))

(: sk-fold-answer-step (-[semidet]-> SkPattern Atom SkeletonKey Atom))
(= (sk-fold-answer-step $fold $acc $key) (sk-member-step $key $acc $fold))

;; --- Activation of facts and rules added after expansion --------------------

(= (sk-activate-pending!) (let $_rules (sk-activate-rules!) (sk-activate-facts!)))

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
      (collapse (match rules (runtime-rule-row $id $ccls $args) (sk-rule-def $ccls $args)))))

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
!(import_prolog_function nth0)
(: nth0
   (-[nondet]-> $index (List $item) $item (List $item)))

;; The rules with a premise a ground key matches, that premise bound to it.
(: sk-premise-rules-step (-[det]-> Statement KBContext Number (List SkeletonMatch) (List SkeletonMatch)))
(= (sk-premise-rules-step $type $kbctx $prefix $found)
   (append-flat
      (collapse
         (let* ((($_pattern $id $idx) (match &prem_prefix ($prefix $pattern $id $idx) ($pattern $id $idx)))
                ((runtime-rule-row $id $ccls $prems) (match rules (runtime-rule-row $id $ccls $prems) (runtime-rule-row $id $ccls $prems)))
                ($_rest (nth0 $idx $prems (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))))
            (sk-match $id $prems $ccls)))
      $found))

(: sk-absorb-step (-[semidet]-> Atom SkeletonMatch Atom))
(= (sk-absorb-step $_acc (sk-match $id $prems $ccls))
   (let* ((($type $kbctx $_proof $_tv) $ccls)
          ($key (sk-key $type $kbctx)))
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
(: sk-activate-fact-step (-[semidet]-> Atom SkeletonKey Atom))
(= (sk-activate-fact-step $_acc $key)
   (case $key (
      ((sk-key $type $kbctx)
         (let* ((($kbid $_ctx $_vars) $kbctx)
                ($hash (index-hash $key))
                ($_read
                   (fold-semidet (sk-activate-fact-on $key) ()
                      (alpha_unique_keys
                         (append-flat (collapse (match &sk_node_terms ($type $kbctx $node) $node))
                            (collapse (match &sk_wait ($hash $premise $_waiter) $premise)))))))
            (if (== (extract-vars $type) ())
               (fold-semidet sk-absorb-step () (foldr-flat (sk-premise-rules-step $type $kbctx) () (statement-prefix-keys $kbid $type)))
               ())))
      ($_fold ()))))

(: sk-activate-rule-row (-[semidet]-> Number Atom SkeletonRuleDef Atom))
(= (sk-activate-rule-row $id $_acc (sk-rule-def $conclusion $args))
   (let* ((($type $kbctx $_proof $_tv) $conclusion))
      (fold-semidet (sk-activate-rule-on $id $conclusion $args) ()
         (collapse (match &sk_node_terms ($type $kbctx $node)
            (let ($node-type $_c $_p $_t) $node
               ;; A subsumed node reads the rule's conclusions from its general node.
               (if (== (extract-vars $node-type) ()) $node
                  (if (let $prefix (sk-node-prefix $node-type)
                         (== (collapse (once (match &sk_open_node ($prefix $_h $stored)
                                (if (=alpha $stored $node) true (empty))))) ()))
                     (empty) $node))))))))

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

;; A node's children, each with its hash.
(: sk-children (-[det]-> Number SkPattern (List SkeletonNodeAt)))
(= (sk-children $hash $node)
   (collapse (match &sk_child ($hash $stored $child $child-hash)
      (if (=alpha $stored $node) (sk-node-at $child-hash $child) (empty)))))

;; Whether a node's search can still give it answers: it, or a node below it,
;; is unexpanded or has work waiting at it (parked deliveries, deferred joins
;; or rows). A node whose search is exhausted never answers without new
;; knowledge. Each node is visited once; the walk stops at the first such node.
(: SkeletonGrowth Type)
(: sk-growth (-[det]-> Bool (List Number) SkeletonGrowth))

(: sk-grows (-[semidet]-> SkeletonGrowth SkeletonNodeAt SkeletonGrowth))
(= (sk-grows (sk-growth $found $seen) (sk-node-at $hash $node))
   (if $found (sk-growth $found $seen)
      (if (stored-list-member? $hash $seen) (sk-growth $found $seen)
         (if (if (sk-expanded? $hash $node) (sk-holds-work? $hash) true)
            (sk-growth true $seen)
            (fold-semidet sk-grows (sk-growth false (cons $hash $seen)) (sk-children $hash $node))))))

(: sk-seen? (-[det]-> Number SkPattern Bool))
(= (sk-seen? $hash $node)
   (not (== (collapse (once (match &sk_seen ($hash $stored) (if (=alpha $stored $node) true (empty))))) ())))

(: sk-seen! (-[det]-> Number SkPattern Bool))
(= (sk-seen! $hash $node)
   (if (sk-seen? $hash $node) true (let $_row (add-atom &sk_seen ($hash $node)) false)))

;; Joins extended after their owner was walked link new children to it; the
;; walk picks those up from &sk_fresh at the next level.
(: sk-take-fresh! (-[det]-> (List SkeletonNodeAt)))
(= (sk-take-fresh!)
   (let $fresh (collapse (match &sk_fresh ($hash $node) (sk-node-at $hash $node)))
      (let $_taken (remove-data-rows! &sk_fresh (quote ($fresh-hash $fresh-node))) $fresh)))

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
         (if (if (sk-extensional? $node) true (sk-take! sk_budget (case $node (((CPU $_f $_a $_r) 1) (($type $_c $_p $_t) (term-cost $type))))))
            (let $_expand (sk-expand! $node $depth $hash) (sk-search! (sk-push-children $depth $hash $node $rest)))
            (sk-search! $rest)))))

;; A walk from its roots.
(: sk-walk! (-[semidet]-> (List SkPattern) Atom))
(= (sk-walk! $roots) (sk-search! (fold-semidet sk-push-root (empty_heap) $roots)))

(: sk-push-root (-[det]-> (Heap SkeletonFrontier) SkPattern (Heap SkeletonFrontier)))
(= (sk-push-root $heap $root) (sk-push 0 $heap (sk-node-at (sk-node-hash $root) $root)))

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
                   (let $_taken (sk-work! (sk-node-hash $o) $o -1)
                      (remove-atom &sk_deferred ($h $rh (sk-deferred $o $rule $c $p $k))))
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
      ((ctx-child $h $owner $child $ch) (let $_r (remove-variant-row! &sk_child (quote ($h $owner $child $ch))) ()))
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
   (let* (($_pending (sk-drop-pending! $h $node))
          ($_rows
             (remove-hash-rows!
                (&sk_child &sk_score &sk_expanded &sk_wait &sk_temp_waits &sk_answer &sk_subsumed &sk_fold
                 &sk_member_of &sk_deferred &sk_deferred_joins &sk_parked &sk_roots &sk_seen)
                $h)))
      (case (copy_term $node) (
         ;; A fold node in a context takes its fold's key along.
         ((CPU FoldAllCompiled $args $_res) (let $fold-key (sk-fold $args) (sk-drop-key-rows! (index-hash $fold-key) $fold-key)))
         ((CPU $_fun $_args $_res) ())
         (($type $kbctx $_proof $_tv)
            (let* (($_terms (remove-data-rows! &sk_node_terms (quote ($type $kbctx $_n6))))
                   ($prefix (sk-node-prefix $type))
                   ($_open (remove-data-rows! &sk_open_node (quote ($prefix $h $_n8)))))
               (let $_prefix (remove-data-rows! &sk_node_prefix (quote ($prefix $_t $_k $h $_n7))) ())))))))

(: sk-drop-key-rows! (-[semidet]-> Number SkeletonKey Atom))
(= (sk-drop-key-rows! $h $key)
   (let* (($rows (collapse (match &sk_row ($h $stored $rh (sk-row $ident $concl $premises $seq)) ($rh $premises))))
          ($_rows (fold-semidet (sk-drop-row-readers! $h) () $rows))
          ($_hashed
             (remove-hash-rows!
                (&sk_row &sk_stale &sk_support &sk_given_pending &sk_given_granted &sk_cond_level &sk_forced
                 &sk_forced_used &sk_refresh &sk_restale &sk_held &sk_temp_rows &sk_keys
                 &sk_key_epoch &sk_latest &sk_view &sk_reader &sk_stale_reader &sk_unifiers
                 &sk_use &sk_needed &sk_dirty &sk_group_of &sk_answered &sk_partial &sk_merged)
                $h)))
      (case $key (
         ((sk-key $type $kbctx) (sk-unindex-key! $type $kbctx $h))
         ($_fold ())))))

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
