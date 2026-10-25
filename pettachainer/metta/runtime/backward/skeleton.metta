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

(: sk-cons-step (-[semidet]-> (List $item) $item (List $item)))
(= (sk-cons-step $items $item) (cons $item $items))

(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (stored-list-member? $function (FoldAllCompiled GroupedFoldAllCompiled CompoundRate)))

(: contextual-cpu? (-[det]-> $formula Bool))
(= (contextual-cpu? $fun)
   (if (== $fun ContextRule) true (if (== $fun ReadRate) true (== $fun ReadLikelihoodContext))))

;; Signatures of the mutually recursive functions below.
(: sk-drop-branch! (-[det]-> Atom Number Atom))
(: sk-stale-branch! (-[det]-> Atom Number Atom))
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
   (let* (($_row (add-atom &sk_expanded ($hash $pattern))) ($_taken (sk-work! $hash $pattern -1)))
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
                  (let* (($_old
                            (collapse (match &sk_key_epoch ($hash $stored $was)
                               (if (=alpha $stored $key) (remove-atom &sk_key_epoch ($hash $stored $was)) (empty)))))
                         ($_new (add-atom &sk_key_epoch ($hash $key $epoch))))
                     ()))))
         ($_fold ())))))

;; Child links, answers, use edges and join extensions are recorded once by
;; a digest of the link. Overlay evaluation borrows these MAIN identities.
(: sk-link-new! (-[det]-> Number Bool))
(= (sk-link-new! $digest)
   (if (space-row-present? &sk_link ($digest)) false
      (let $_row (add-atom &sk_link ($digest)) true)))

(: sk-node-score (-[det]-> Number SkPattern Number))
(= (sk-node-score $hash $node)
   (chainer-first-or 0.0 (collapse (once (match &sk_score ($hash $stored $score) (if (=alpha $stored $node) $score (empty)))))))

(: sk-raise-score! (-[det]-> Number SkPattern Number Atom))
(= (sk-raise-score! $hash $node $score)
   (let* (($old (sk-node-score $hash $node)))
      (if (> $score $old)
         (let* (($_removed
                   (collapse (match &sk_score ($hash $stored $old-score)
                      (if (=alpha $stored $node) (remove-atom &sk_score ($hash $stored $old-score)) (empty)))))
                ($_added (add-atom &sk_score ($hash $node $score))))
            ())
         ())))

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

(: sk-set-truth-factor! (-[det]-> Number Number Atom))
(= (sk-set-truth-factor! $hash $factor)
   (let* (($_old (remove-data-rows! &sk_truth_factor (quote ($hash $_was))))
          ($_new (context-add! &sk_truth_factor ($hash $factor))))
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
   (if (if (is-var $want-proof) true
           (if (head-is? $want-proof derived-implication)
              (let $step (sk-step-proof $got-proof) (head-is? $step by))
              (= (sk-full-proof $got-proof) $want-proof)))
      (if (is-var $want-tv) true (= $got-tv $want-tv))
      false))

;; Every fact of a goal's statement and context that passes the filter, read
;; through the statement's prefix index (kb-facts); the probe for materialized
;; rows runs only when some materialization happened.
(: sk-leaf-facts (-[det]-> Statement KBContext SkeletonFilter (List SkFact)))
(= (sk-leaf-facts $type $kbctx $filter)
   (let* (($plain (== (collapse (once (match &materialized_facts (materialized-row $_hash $_type $_kb $_fact $_ev) true))) ()))
          ($local (foldr-flat (sk-leaf-fact-step $plain $filter) () (kb-facts $type $kbctx))))
      (case $kbctx (
            (($kbid $ctx $vars)
               (if (judgment-world-premise? $type $kbctx)
                  (let $_watch (sk-watch-world! $type $kbctx (brand KB $kbid))
                     (foldr-flat (sk-judgment-main-fact-step $kbctx $plain $filter) $local
                        (kb-facts $type (kbctx (brand KB $kbid)))))
                  $local))))))

;; Subscribe before looking for facts: a missing world premise is still a
;; live input of a durable judgment. Deduplicate by the private reader key.
(: sk-watch-world! (-[det]-> Statement KBContext KB Atom))
(= (sk-watch-world! $type $kbctx $kbid)
   (let* (($key (sk-key $type $kbctx)) ($hash (index-hash $key)))
      (if (== (collapse (once (match &sk_world_reader ($hash $stored)
                  (if (=alpha $stored $key) true (empty))))) ())
         (let* (($_reader (add-atom &sk_world_reader ($hash $key)))
                ($lookup (copy_term $type))
                ($prefixes (cons (statement-open-hash $type) (statement-open-probes $type)))
                ($_prefixes (collapse (let $prefix (superpose $prefixes)
                   (let $slot (index-hash (data $kbid $prefix))
                      (add-atom &sk_world_prefix ($slot $lookup $kbid $key))))))
                ($_open (if (== (extract-vars $type) ()) ()
                   (let $slot (index-hash (data $kbid (statement-open-hash $type)))
                      (add-atom &sk_world_open ($slot $lookup $kbid $key))))))
            ())
         ())))

;; As with fact lookup, probe the longest prefix and shorter open prefixes.
;; An open added fact can reach more-specific private readers as well.
(: sk-world-readers (-[det]-> Statement KB (List SkeletonKey)))
(= (sk-world-readers $type $kbid)
   (let* (($prefix (statement-open-hash $type))
          ($slot (index-hash (data $kbid $prefix)))
          ($shorter (statement-open-probes $type)))
      (append-flat
         (collapse (match &sk_world_prefix ($slot $type $kbid $key) $key))
         (collapse (let $open (superpose $shorter)
            (let $open-slot (index-hash (data $kbid $open))
               (match &sk_world_open ($open-slot $type $kbid $key) $key)))))))

;; Borrow only observations, never MAIN's derived/materialized values. A fixed
;; premise may use the world, but an assumed key overrides its world value and
;; a hypothetical individual must never be unified with a world individual.
(: sk-judgment-main-fact-step
   (-[det]-> KBContext Bool SkeletonFilter SkFact (List SkFact) (List SkFact)))
(= (sk-judgment-main-fact-step $kbctx $plain $filter ($type $main $proof $tv) $facts)
   (if (judgment-consequent? true $type $kbctx) $facts
   (if (judgment-assumed-key? $type $kbctx) $facts
      (if (== (sk-leaf-fact-step $plain $filter (data $type $main $proof $tv) ()) ()) $facts
         (let $hash (index-hash (sk-key $type $main))
            (if (space-row-present? &sk_forward_stored ($hash $_key ($type $main $proof $tv) $_ev $_deps)) $facts
               (cons (data $type $kbctx $proof $tv) $facts)))))))

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
;; could change its value. Borrowed world facts cannot retire private search:
;; the judgment may find an assumption-dependent alternative to select instead.
(: sk-certain-step (-[det]-> Bool SkFact Bool))
(= (sk-certain-step $seen ($_type ($_kb $ctx $_vars) $proof $tv))
   (if $seen true
      (if (if (== $ctx MAIN) true (assumption-proof? $proof))
         (case $tv (((STV $_s $c) (>= $c 1.0)) ($_other false))) false)))
(: sk-certain? (-[det]-> Statement (List SkFact) Bool))
(= (sk-certain? $type $facts)
   (if (== (extract-vars $type) ()) (fold-flat sk-certain-step false $facts) false))

;; A stored fact of strength 0 or 1 at confidence 1 makes its statement known:
;; every reader, a conditioned one included, reads it as that fact.
(: sk-known-leaf-step (-[det]-> Bool SkFact Bool))
(= (sk-known-leaf-step $known ($_type ($_kb $ctx $_vars) $proof $tv))
   (if $known true
      (if (if (== $ctx MAIN) true (assumption-proof? $proof)) (certain-tvs? (cons $tv ())) false)))

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
          ($_world
             (if (== (collapse (once (match &sk_world_reader ($h $stored)
                        (if (=alpha $stored (sk-key $type $kbctx)) true (empty))))) ()) ()
                (case $kbctx (
                   (($kbid $_ctx $_vars)
                      (let* (($kb (brand KB $kbid))
                             ($key (sk-key $type $kbctx))
                             ($lookup (copy_term $type))
                             ($_seen (remove-variant-row! &sk_world_reader (quote ($h $key))))
                             ($world-prefixes (cons $open (statement-open-probes $type)))
                             ($_world-prefixes (collapse (let $world-prefix (superpose $world-prefixes)
                                (let $prefix-slot (index-hash (data $kb $world-prefix))
                                   (remove-variant-row! &sk_world_prefix (quote ($prefix-slot $lookup $kb $key)))))))
                             ($open-slot (index-hash (data $kb $open))))
                         (remove-variant-row! &sk_world_open (quote ($open-slot $lookup $kb $key)))))))))
          ($_terms (remove-data-rows! &sk_key_terms (quote ($type $kbctx $h))))
          ($_open (remove-data-rows! &sk_key_open (quote ($open $type $kbctx $h))))
          ($_reader (remove-data-rows! &sk_reader_open (quote ($open $type $kbctx $h $_reader-key))))
          ($_prefixes
             (collapse (let $prefix (superpose $prefixes)
                (progn
                   (remove-data-rows! &sk_key_prefix (quote ($prefix $type $kbctx $h)))
                   (remove-data-rows! &sk_reader_prefix (quote ($prefix $type $kbctx $h $_prefix-key))))))))
      ()))

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
               (let* (($computed (hash-set (cons $khash (sk-unifying-key-hashes $type $kbctx))))
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

(: sk-add-use! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-add-use! $key $parent)
   (if (let $link (sk-use-link $key $parent) (sk-link-new! (link-digest $link)))
      (let* (($hash (index-hash $key)) ($_row (add-atom &sk_use ($hash $key $parent)))) ())
      ()))

;; Before anything was evaluated (no latest version of any key) there is no
;; reader to schedule.
(: sk-mark-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-mark-dirty! $key)
   (if (not (== (collapse (once (match &ctx_sk_latest ($_hash $_key $_version) true))) ()))
      (sk-dirty! $key)
      ()))

;; Base rates and implication instance folds follow their members
;; incrementally, as a tally of each member's contribution (see sk-fold-view).
(: sk-instance-fold? (-[det]-> Atom Bool))
(= (sk-instance-fold? ($_kb $_pattern $_extractor $_init $_function $finish $_mode))
   (stored-list-member? $finish (implication-instance implication-instance-ctv)))

(: sk-existential-fold? (-[det]-> Atom Bool))
(= (sk-existential-fold? $fold)
   (let* (($args (case $fold (
                    ((sk-fold $scalar) $scalar)
                    ((sk-group $grouped) $grouped)
                    ((CPU $_kind $spec $_result) $spec)
                    ($_other ()))))
          ($function (case $args (
                        (($_kb $_body $_extract $_initial $f $_finish $_mode) $f)
                        (($_kb2 $_body2 $_group $_extract2 $_initial2 $g $_finish2 $_mode2) $g)
                        ($_other-args none)))))
      (if (== $function OrFormula) true (== $function ExistentialFloor))))

(: sk-instance-fold-key? (-[det]-> SkeletonKey Bool))
(= (sk-instance-fold-key? $key)
   (case $key (((sk-fold $args) (sk-instance-fold? $args)) ($_other false))))

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
         (if (== (collapse (once (match &ctx_sk_rate_dirty ($hash $mhash $stored-fold $stored)
                    (if (=alpha $stored $member) (if (=alpha $stored-fold $fold) true (empty)) (empty)))))
                 ())
            (let* (($_row (context-add! &sk_rate_dirty ($hash $mhash $fold $member)))
                   ($_changed
                      (if (if (sk-instance-fold-key? $fold) (not (space-row-present? &ctx_sk_instance_changed ($hash $_stored))) false)
                         (context-add! &sk_instance_changed ($hash $fold))
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

;; A fold premise of a join is searched as a child of the join's owner, scored
;; by what the join is worth, and a compound's prior through the folds it
;; reads (#142); a forward run notes them instead.
(: sk-fold-child! (-[semidet]-> SkPattern Number SkFact (List SkPattern) Atom SkPattern Atom))
(= (sk-fold-child! $owner $rule $concl $remaining $_acc $premise)
   (case $premise (
      ((CPU CompoundRate $rate-args $_rate)
         (fold-semidet (sk-fold-child! $owner $rule $concl $remaining) () (compound-rate-goals $rate-args true $_inner)))
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
                     (if (if (contextual-cpu? $fun) false (== (extract-vars $args) ()))
                        (fold-semidet
                           (sk-cpu-step (sk-partial $owner $rule $concl $done $remaining $keys))
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
                      (let $premise-kbid (car-atom $scope)
                         (if (head-is? $premise-kbid implication-query)
                            (let $_installed (inject-special-subgoal-query-adds temp $type $scope $proof $tv)
                               (sk-activate-pending!))
                            ())))))))
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
      (let* (($_read (fold-semidet (sk-extend-waiter-step $waiter) ()
                (if (sk-completion-waiter? $waiter) (append-flat (sk-answers $premise)
                   (collapse (match &sk_prior_answer ($hash $pstored $pkey) (if (=alpha $pstored $premise) $pkey (empty))))) (sk-answers $premise))))
             ($_retired (sk-functional-delivered! $subscription)))
         ())))))

(: sk-extend-waiter-step (-[semidet]-> SkeletonWaiter Atom SkeletonKey Atom))
(= (sk-extend-waiter-step $waiter $_acc $key) (sk-extend-current! (copy_term $waiter) $key))

;; A join is extended by an answer once, however the answer reaches it (read
;; when the join starts waiting, or delivered later); a computation that
;; samples would otherwise draw again. Once the row allowance is spent, a join
;; an answer reaches stops there: the pair waits once with the join's owner, so
;; a recursive rule cannot keep extending joins whose rows could not be kept
;; anyway. Joins of the query's roots always proceed.
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
   (if (if (sk-root? $owner) true (> (search-id-value sk_row_budget) 0))
      (sk-extend-now! (sk-partial $owner $rule $concl $done $remaining $keys) $key)
      (let* (($hash (sk-node-hash $owner))
             ($join (sk-join (sk-partial $owner $rule $concl $done $remaining $keys) $key))
             ($jhash (index-hash $join)))
         (if (== (collapse (once (match &sk_deferred_joins ($hash $jhash $_join) true))) ())
            (let* (($_deferred (add-atom &sk_deferred_joins ($hash $jhash $join)))
                   ($_pending (sk-work! $hash $owner 1))
                   ($_counted (query_metric_increment joins-deferred)))
               ())
            ())))
      ()))

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
            (if (let $link (sk-join-link (sk-partial $owner $rule $concl $done $remaining $keys) $registered) (sk-store-join! (link-digest $link) $waiter $concl))
               (sk-advance!
                  (sk-partial $owner $rule $concl (cons $premise $done) $rest (cons $registered $keys)))
               ())
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
            ;; A row waits once, however often its join completes meanwhile.
            (let $hash (sk-node-hash $owner)
               (if (== (collapse (once (match &sk_deferred ($hash $rhash $_deferred) true))) ())
                  (let* (($_deferred
                            (add-atom &sk_deferred ($hash $rhash (sk-deferred $owner $rule $concl $premises $keys))))
                         ($_pending (sk-work! $hash $owner 1))
                         ($_counted (query_metric_increment rows-deferred)))
                     ())
                  ()))))))
      ()))

;; The keys a row reads directly: its fact premises, folds and groups.
(: sk-direct-key-step (-[det]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-direct-key-step $keys $premise)
   (case $premise (
      ((CPU ContextRule ($assumption $_ctx) $_res) (cons (the SkeletonKey $assumption) $keys))
      ((CPU FoldAllCompiled $fold-args $_fold-res) (cons (sk-fold $fold-args) $keys))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res) (cons (sk-group $group-args) $keys))
      ((CPU CompoundRate $rate-args $_rate-res) (cons (sk-rate $rate-args) $keys))
      ((CPU $_fun $_args $_res) $keys)
      (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $keys)))))

;; The keys a compound's prior reads directly.
(: sk-rate-inputs (-[det]-> (List SkPattern) (List SkeletonKey)))
(= (sk-rate-inputs $goals) (fold-flat sk-direct-key-step () $goals))
(: sk-use-step! (-[det]-> SkeletonKey Atom SkeletonKey Atom))
(= (sk-use-step! $parent $_acc $key) (sk-add-use! $key $parent))

(: sk-add-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-add-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key)) ($_row (context-add! &sk_reader ($hash $key $khash $rhash))))
      ()))

(: sk-drop-stale-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-drop-stale-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_removed
             (collapse (match &ctx_sk_stale_reader ($hash $stored $khash $rhash)
                (if (=alpha $stored $key) (context-remove! &sk_stale_reader ($hash $stored $khash $rhash)) (empty))))))
      ()))

(: sk-remove-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-remove-reader! $khash $rhash $_acc $key)
   (let* (($hash (index-hash $key))
          ($_removed
             (collapse (match &ctx_sk_reader ($hash $stored $khash $rhash)
                (if (=alpha $stored $key) (context-remove! &sk_reader ($hash $stored $khash $rhash)) (empty))))))
      ()))

;; A stale row moves from a key's readers to its stale readers (see
;; sk-unlink-reader!).
(: sk-stale-reader! (-[det]-> Number Number Atom SkeletonKey Atom))
(= (sk-stale-reader! $khash $rhash $_acc $key)
   (let* (($_removed (sk-remove-reader! $khash $rhash () $key))
          ($hash (index-hash $key))
          ($_row (context-add! &sk_stale_reader ($hash $key $khash $rhash))))
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
      (if (<= $left 0) false (progn (change-state! $counter (- $left $cost)) true))))

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
(: ccls-index-occurs-matches (-[det]-> Atom (List (SkFact Number (List SkPattern)))))

(: sk-context-search? (-[det]-> SkFact Bool))
(= (sk-context-search? ($_type ($kbid $ctx $_vars) $_proof $_tv))
   (if (== $ctx MAIN) (context-searching? $kbid) true))

;; A statement consumer selects rule applications, then binds their merged
;; proof as a value. Its selector is not a literal constraint on that value.
(: sk-rule-goal (-[det]-> SkPattern SkPattern))
(= (sk-rule-goal $pattern)
   (case $pattern (
      ((CPU $_fun $_args $_result) $pattern)
      (($type $ctx $proof $tv)
         (if (head-is? $proof derived-implication)
            (assemble-stored-runtime-fact $type $ctx (brand Proof (by $rule $premise)) $tv)
            $pattern)))))

(= (sk-rule-match $pattern)
   (let $goal (the SkFact (sk-rule-goal $pattern))
   (superpose (
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
                  (empty)))))
      (sk-judgment-main-rule-match $goal)))))

;; Fixed source-fact projections are compiled in MAIN. Reuse their logic in
;; the judgment, with contextual premises, rather than importing a MAIN view
;; that might depend on the overridden assumption. Polymorphic rules already
;; match the private goal normally and must not be started a second time.
(: sk-judgment-main-rule-match (-[nondet]-> SkFact SkeletonMatch))
(= (sk-judgment-main-rule-match ($type ($kbid $ctx $vars) $proof $tv))
   (if (judgment-world-premise? $type (make-kb-context (brand KB $kbid) $ctx $vars))
      (let $lookup (copy_term (data $type (data $kbid MAIN Nil) $proof $tv))
         (match ccls_index ($lookup $id $args)
            (match rules (runtime-rule-row $id ($_type ($_kb $stored-ctx $_vars) $_prf $_tv) $_args)
               (if (if (== $stored-ctx MAIN)
                        (case $_prf (
                           ((marginal-proj $_idx $_base) true)
                           (((proj $_idx $_base) $_siblings) true)
                           ((proj $_idx $_base) true)
                           ($_other-proof false))) false)
                  (if (= $lookup (data $type (data $kbid MAIN Nil) $proof $tv))
                     (let* (($scope (make-kb-context (brand KB $kbid) $ctx $vars))
                            ($goal (assemble-stored-runtime-fact $type $scope $proof $tv))
                            ($scoped (map-flat (sk-judgment-main-premise $scope) $args)))
                        ;; Matching a fixed projection may specialize an open
                        ;; reader to the target; do not import that instance.
                        (if (judgment-consequent? true $type $scope) (empty)
                           (sk-match $id (contextualize-rule-args $goal $scoped) $goal)))
                     (empty))
                  (empty)))))
      (empty)))

(: sk-judgment-main-premise (-[det]-> KBContext SkPattern SkPattern))
(= (sk-judgment-main-premise ($kbid $ctx $vars) $premise)
   (case $premise (
      (($type ($kbid MAIN Nil) $proof $tv)
         (let $scope (make-kb-context (brand KB $kbid) $ctx $vars)
            (assemble-stored-runtime-fact $type $scope $proof $tv)))
      ($_other $premise))))

;; Both arguments come from destructuring a premise and its erased KBContext,
;; so they arrive as raw terms: a statement and Nil or a variable list.
(: context-vars-in-type? (-[det]-> Atom Atom Bool))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false (sk-any-member? (extract-vars $type) $vars)))

(: sk-any-member? (-[det]-> (List Variable) Atom Bool))
(= (sk-any-member? $_type-vars ()) false)
(= (sk-any-member? $type-vars (cons $var $rest))
   (if (stored-list-member? $var $type-vars) true (sk-any-member? $type-vars $rest)))

;; MAIN's observation of B is not evidence of B under the assumed A. Match
;; query-local target metadata on copies, retaining the original reader shape:
;; a target's instances are excluded without hiding unrelated open bindings.
(: judgment-consequent? (-[det]-> Bool Atom KBContext Bool))
(= (judgment-consequent? $instances? $type ($kbid $ctx $vars))
   (let* ((($base $_negated) (canon (brand Statement $type)))
          ($scope (make-kb-context (brand KB (judgment-consequent $kbid)) $ctx $target-vars))
          ($targets (kb-facts $base $scope)))
      (not (== (collapse (once
         (let ($target ($_metadata-kb $_metadata-ctx $stored-vars) $_proof $_tv) (superpose $targets)
            (if (if $instances? (=alpha $base $target)
                    (=alpha (data $base $vars) (data $target $stored-vars))) true (empty))))) ()))))

;; A query's prototype variables must stay variables. A rule lookup may have
;; specialized a copy of its goal; that must not license world observations of
;; the specialized prototype. Auxiliary variables do not belong to this list.
(: judgment-world-premise? (-[det]-> Statement KBContext Bool))
(= (judgment-world-premise? $type ($kbid $ctx $vars))
   (if (== $ctx MAIN) false
      (if (judgment-consequent? true $type (make-kb-context (brand KB $kbid) $ctx $vars)) false
      (if (== $vars Nil) true
         (if (== (extract-vars $vars) $vars) (not (context-vars-in-type? $type $vars)) false)))))

;; Compare the whole key without binding its hypothetical individual to an
;; unrelated fixed world individual. Use the fact prefix index; type and
;; context must retain the same variable-sharing shape.
(: judgment-assumed-key? (-[det]-> Atom KBContext Bool))
(= (judgment-assumed-key? $type $kbctx)
   (if (judgment-assumption-fact? $type $kbctx) true
      (judgment-assumption-fact? (JudgmentPrior $type) $kbctx)))

(: judgment-assumption-fact? (-[det]-> Atom KBContext Bool))
(= (judgment-assumption-fact? $type $kbctx)
   (let* ((($probe-type $probe-ctx) (copy_term (data $type $kbctx)))
          ($facts (let ($lookup-type $lookup-ctx) (copy_term (data $probe-type $probe-ctx))
             (kb-facts (brand Statement $lookup-type) (brand KBContext $lookup-ctx)))))
      (not (== (collapse (once (let ($assumed $assumed-ctx $proof $_tv) (superpose $facts)
         (if (assumption-proof? (brand Proof $proof))
            (if (=alpha (data $probe-type $probe-ctx) (data $assumed $assumed-ctx)) true
               ;; An open reader can consume a ground assumption. Match a
               ;; copy so this test cannot bind the rule's premise variables;
               ;; non-ground hypothetical keys still require alpha identity.
               (if (== (extract-vars $assumed) ())
                  ;; Indexed unification can ground a hypothetical variable.
                  ;; Its context must still have the original sharing shape.
                  (if (=alpha $probe-ctx $assumed-ctx)
                     (if (= (copy_term $probe-type) $assumed) true (empty))
                     (empty))
                  (empty)))
            (empty))))) ()))))

;; Logical implication judgments keep their hypothetical individuals and exact
;; assumed keys private. Assuming queries use canonical MAIN keys throughout.
(: contextualize-rule-premise (-[det]-> SkFact SkPattern SkPattern))
(= (contextualize-rule-premise ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv) $premise)
   (once
      (case $premise (
         (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (let* (($fact-kb
                       (if (if (== $prem-ctx MAIN)
                              (if (== $ctx MAIN) false
                                 (if (context-vars-in-type? $type $vars) true
                                    (let $scope (make-kb-context (brand KB $kbid) $ctx $vars)
                                       (if (judgment-assumed-key? $type $scope) true
                                          (judgment-consequent? false $type $scope)))))
                              false)
                          (make-kb-context (brand KB $kbid) $ctx $vars)
                          (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars)))
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
         ;; Private implication judgments scope witness folds to their own
         ;; hypothetical individuals. Assuming uses MAIN identities and overlays
         ;; their values, so its folds keep their original MAIN scope.
         ((CPU $fun $args $res)
            (if (if (sk-existential-fold? $premise)
                   (let $pattern (car-atom (cdr-atom $args))
                      (if (== $ctx MAIN) false
                         ;; Ground judgments have no hypothetical individual
                         ;; to protect. Open ones must preserve its sharing.
                         (if (== $vars Nil) true
                            (if (context-vars-in-type? $pattern $vars) true
                               (case $pattern (
                                  ((ExistentialAlternatives $claim $_channel)
                                     (judgment-assumed-key? $claim
                                        (make-kb-context (brand KB $kbid) $ctx $vars)))
                                  ($_other-pattern false)))))))
                   false)
               (CPU $fun (cons-atom (make-kb-context (brand KB $kbid) $ctx $vars) (cdr-atom $args)) $res)
               (CPU $fun $args $res)))
         ;; A query judgment reads its explicit source context in another KB
         ;; namespace; that premise keeps its own context.
         ($_other-kb $premise)))))

(: contextualize-rule-args (-[semidet]-> SkFact (List SkPattern) (List SkPattern)))
(= (contextualize-rule-args $goal $args) (map-semidet (contextualize-rule-premise $goal) $args))

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

;; Only reject ground computations that cannot succeed. A missing fact is
;; pending input, so its join must wait for later additions.
(: prefilter-premise-blocks? (-[det]-> SkPattern Bool))
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (if (contextual-cpu? $fun) true (aggregate-fold-function? $fun)) false
               (if (if (is-var $fun) false (== (extract-vars $args) ()))
                  (case (collapse (cpu-call 0 $fun $args)) (
                     (() true)
                     ((cons $result $_rest) (if (= $res $result) false true))))
                  false)))
         ;; Missing facts can arrive after this node has been expanded. Keep
         ;; their ordinary join subscriptions instead of caching an empty search.
         ($_fact false)))))

(: prefilter-prunes-walk (-[det]-> (List SkPattern) Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

;; --- Complete predicates (docs/metta/complete_predicates.md) ----------------

;; A ground statement of a complete predicate in the main context or in an
;; Assuming query's context, which holds the world's facts and rules with its
;; assumptions; an implication query's hypothetical contexts are not complete.
(: complete-statement? (-[det]-> Atom Atom Bool))
(= (complete-statement? $type ($kbid $ctx $_vars))
   (if (== $ctx MAIN)
      (if (== (extract-vars $type) ())
         (let* (($kb (brand KB $kbid)) ($head (if (is-expr $type) (car-atom $type) $type)))
            (complete-predicate? $kb $head))
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
;; Assumptions can enable producers MAIN skipped as dormant. Assuming shares
;; structural rows without supplying assumed values; private implication
;; judgments start their own contextual rows, regardless of MAIN's verdict.
;; Missing fact premises keep their join subscriptions. Only failing ground
;; CPU premises trigger the prefilter.
(= (sk-start-rule-step $owner $_acc (sk-match $rule $premises $goal))
   (if (if (if (sk-context-search? $goal) false (rule-dormant? $rule)) false (= (copy_term $goal) (sk-rule-goal (copy_term $owner))))
      (if (if (case $goal (
                (($type $kbctx $proof $_tv)
                   (if (rule-application-proof? $proof) (complete-statement? $type $kbctx) false))))
             false
             (prefilter-prunes-walk (copy_term $premises)))
         ()
         (sk-advance! (sk-partial $owner $rule $goal () $premises ())))
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

;; The empirical Member producer of a concrete Inheritance link depends only on
;; the link, so it is installed once as permanent backward rules: its rows
;; survive the query, and a later zero-budget read still has them. Forward
;; chaining keeps member inheritance through its own aggregate.
(: install-member-inheritance-rules! (-[semidet]-> Statement KBContext Atom))
(= (install-member-inheritance-rules! $type $kbctx)
   (case $kbctx (
      (($kbid MAIN Nil)
         (if (head-is? $type Inheritance)
            (let (Inheritance $subj $concept) $type
               (if (concrete-inheritance-link? $subj $concept)
                  (let* (($link (quote ($kbid $subj $concept))) ($hash (index-hash $link)))
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
            ()))
      ($_other ()))))

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
                ($_member (install-member-inheritance-rules! $type $kbctx))
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
         (if (if (positive-only-pattern? $kbid $pattern) (user-base-rate? $kbid $pattern) true)
            (if (= (copy_term $pattern) (copy_term $type)) (sk-prior-fold $rule $args) (empty))
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
      (collapse (match rules (runtime-rule-row $id $ccls $args) (sk-rule-def $ccls $args)))))

;; nth0/4 removes the indexed element while unifying it with its third
;; argument. Its relational modes can branch, but every result preserves the
;; element type of the input list.
!(import_prolog_function nth0)
(: nth0 (-[nondet]-> $index (List $item) $item (List $item)))

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
(: sk-fact-watches (-[det]-> Number (List SkPattern)))
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
                      (fold-semidet sk-absorb-step () (foldr-flat (sk-premise-rules-step $type $kbctx) () (statement-prefix-keys $kbid $type)))
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

;; A node no rule can conclude is expanded without a step when the walk
;; reaches it: its expansion only reads its stored facts. Implications and
;; inheritance links are not, since expanding them installs rules.
(: sk-extensional? (-[semidet]-> SkPattern Bool))
(= (sk-extensional? $node)
   (case $node (
      ((CPU $_fun $_args $_res) false)
      (($type $kbctx $_proof $_tv)
         (if (implication-type? $type) false
            (if (head-is? $type Inheritance) false
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
         (if (if (sk-extensional? $node) true (sk-take! sk_budget (case $node (((CPU $_f $_a $_r) 1) (($type $_c $_p $_t) (term-cost $type))))))
            (let $_expand (sk-expand! $node $depth $hash) (sk-search! (sk-push-children $depth $hash $node $rest)))
            (sk-search! $rest)))))

;; A walk from its roots.
(: sk-walk! (-[semidet]-> (List SkPattern) Atom))
(= (sk-walk! $roots) (sk-search! (fold-semidet sk-push-root (empty_heap) $roots)))

(: sk-push-root (-[det]-> (Heap SkeletonFrontier) SkPattern (Heap SkeletonFrontier)))
(= (sk-push-root $heap $root) (sk-push 0 $heap (sk-node-at (sk-node-hash $root) $root)))

(: sk-branch-link! (-[det]-> Number Atom SkeletonKey Atom))
(: sk-branch-unlink! (-[det]-> Number Atom SkeletonKey Atom))
(: sk-invalidate-branches! (-[det]-> SkeletonKey Atom))
(= (sk-branch-link! $slot $_acc $input)
   (let $ihash (index-hash $input) (context-add! &sk_branch_reader ($ihash $input $slot))))

(= (sk-branch-unlink! $slot $_acc $input)
   (let $ihash (index-hash $input)
      (remove-variant-row! &sk_branch_reader (quote ($ihash $input $slot)))))

;; Erase before cascading, so cycles stop at the first already erased owner.
;; The ordinary views remain valid. Only their cached exclusion reads change.
(= (sk-drop-branch! $_acc $slot)
   (let* (($_wanted (remove-data-rows! &sk_branch_wanted (quote ($slot $_hash $_key $_rhash $_exclude))))
          ($_dropped
             (collapse (match &ctx_sk_branch_owner ($slot $hash $key $rhash $inputs)
                (let* (($_owner (remove-variant-row! &sk_branch_owner (quote ($slot $hash $key $rhash $inputs))))
                       ($_views (remove-data-rows! &sk_branch (quote ($slot $_key $_rhash $_cuts $_fresh $_view))))
                       ($_dirty (context-remove! &sk_branch_dirty ($slot)))
                       ($_inputs (fold-semidet (sk-branch-unlink! $slot) () $inputs)))
                   (sk-invalidate-branches! $key))))))
      ()))

(= (sk-stale-branch! $_acc $slot)
   (if (space-row-present? &ctx_sk_branch_dirty ($slot)) ()
      (let $_staled
         (collapse (match &ctx_sk_branch_owner ($slot $_hash $key $_rhash $inputs)
            (let* (($_dirty (context-add! &sk_branch_dirty ($slot)))
                   ($_unlinked (fold-semidet (sk-branch-unlink! $slot) () $inputs))
                   ($_wanted
                      (if (== (search-id-value sk_holding) 1)
                         (collapse (match &ctx_sk_branch_hold ($slot $hash $held $row $exclude)
                            (if (space-row-present? &ctx_sk_branch_wanted ($slot $hash $held $row $exclude)) ()
                               (context-add! &sk_branch_wanted ($slot $hash $held $row $exclude))))) ()))
                   ($_views
                      (collapse (match &ctx_sk_branch ($slot $stored $rhash $cuts true $view)
                         (let $_old (remove-variant-row! &sk_branch (quote ($slot $stored $rhash $cuts true $view)))
                            (context-add! &sk_branch ($slot $stored $rhash $cuts false $view)))))))
               (sk-invalidate-branches! $key))))
         ())))

(= (sk-invalidate-branches! $key)
   (let* (($hash (index-hash $key))
          ($_dropped (collapse (fold-semidet sk-stale-branch! ()
             (collapse (match &ctx_sk_branch_reader ($hash $stored $slot)
                (if (=alpha $stored $key) $slot (empty))))))))
      ()))

;; A row's latest view and the views it replaced.
(: sk-drop-row-views! (-[det]-> Number SkeletonKey Number Atom))
(= (sk-drop-row-views! $hash $key $rhash)
   (let* (($_root (sk-clear-root-cap! $hash $key))
          ($_branches (sk-drop-branch! () (index-hash ($hash $rhash))))
          ($_latest
             (collapse (match &ctx_sk_latest ($hash $stored (sk-version $seq $rhash $view))
                (if (=alpha $stored $key)
                   (let $_changed (if (== $view sk-none) () (sk-invalidate-branches! $key))
                      (context-remove! &sk_latest ($hash $stored (sk-version $seq $rhash $view))))
                   (empty)))))
          ($_older
             (collapse (match &ctx_sk_view ($hash $stored $rhash $view)
                (if (=alpha $stored $key) (context-remove! &sk_view ($hash $stored $rhash $view)) (empty)))))
          ($_representatives
             (collapse (match &ctx_sk_representative ($hash $rep-key $rhash $rep-given $rep-exclude $rep-value)
                (if (=alpha $rep-key $key)
                   (context-remove! &sk_representative ($hash $rep-key $rhash $rep-given $rep-exclude $rep-value)) (empty)))))
          ($_references
             (collapse (match &ctx_sk_summary_reference ($hash $rep-key $rhash $rep-given $rep-exclude $rep-filter $rep-value)
                (if (=alpha $rep-key $key)
                   (context-remove! &sk_summary_reference ($hash $rep-key $rhash $rep-given $rep-exclude $rep-filter $rep-value)) (empty)))))
          ($_support (remove-data-rows! &sk_support (quote ($hash $rhash $_deps)))))
      ()))

(: sk-drop-row! (-[semidet]-> Number SkeletonKey Number SkeletonRow Atom))
(= (sk-drop-row! $hash $key $rhash (sk-row $ident $concl $premises $seq))
   (let* (($_world-stale (remove-data-rows! &sk_world_stale (quote ($hash $rhash))))
          ($_world-done (remove-data-rows! &sk_world_done (quote ($hash $rhash))))
          ($keys (fold-semidet sk-direct-key-step () $premises))
          ($_row (remove-variant-row! &sk_row (quote ($hash $key $rhash (sk-row $ident $concl $premises $seq)))))
          ($_aggregate (remove-variant-row! &sk_aggregate_row (quote ($hash $key $rhash))))
          ($_readers (fold-semidet (sk-remove-reader! $hash $rhash) () $keys))
          ($_stale-readers (fold-semidet (sk-drop-stale-reader! $hash $rhash) () $keys))
          ($_stale (context-remove! &sk_stale ($hash $rhash))))
      (sk-drop-row-views! $hash $key $rhash)))

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
                (let* (($_temp (remove-atom &sk_temp_waits ($hash $pattern $waiter)))
                       ($_removed (remove-variant-row! &sk_wait (quote ($hash $pattern $waiter)))))
                   ()))))
          ($keys
             (collapse (match &sk_temp_rows ($khash $key $rhash $row)
                (let* (($_temp (remove-atom &sk_temp_rows ($khash $key $rhash $row)))
                       ($_row (sk-drop-row! $khash $key $rhash $row)))
                   $key)))))
      (foreach-flat sk-mark-dirty! $keys)))
