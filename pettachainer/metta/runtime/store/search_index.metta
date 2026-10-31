(datatype SkeletonGrowth (sk-growth Bool (List Number)))

;; --- Node identity ----------------------------------------------------------

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

(: sk-set-truth-factor! (-[det]-> Number Number Atom))
(= (sk-set-truth-factor! $hash $factor)
   (let* (($_old (remove-data-rows! &sk_truth_factor (quote ($hash $_was))))
          ($_new (context-add! &sk_truth_factor ($hash $factor))))
      ()))

;; A node's index column: the hash of its statement's longest ground prefix,
;; or of its head when it has none.
(: sk-node-prefix (-[det]-> $statement Number))
(= (sk-node-prefix $type)
   (case (statement-prefix-hashes $type) (
      (() (index-hash (car-atom $type)))
      ((cons $longest $_shorter) $longest))))

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

(: sk-add-use! (-[det]-> SkeletonKey SkeletonKey Atom))
(= (sk-add-use! $key $parent)
   (if (let $link (sk-use-link $key $parent) (sk-link-new! (link-digest $link)))
      (let* (($hash (index-hash $key)) ($_row (add-atom &sk_use ($hash $key $parent)))) ())
      ()))

;; Before anything was evaluated (no latest version of any key) there is no
;; reader to schedule.
(: sk-mark-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-mark-dirty! $key)
   (if (space-row-present? &ctx_sk_latest (quote ($_hash $_key $_version)))
      (sk-dirty! $key)
      ()))

;; The keys a row reads directly: its fact premises, folds and groups.
(: sk-direct-key-step (-[det]-> (List SkeletonKey) SkPattern (List SkeletonKey)))
(= (sk-direct-key-step $keys $premise)
   (case $premise (
      ((CPU ContextRule ($assumption $_ctx) $_res) (cons (the SkeletonKey $assumption) $keys))
      ((CPU CompoundEvidence $evidence-args $_evidence) (cons (sk-evidence $evidence-args) $keys))
      ((CPU FoldAllCompiled $fold-args $_fold-res) (cons (sk-fold $fold-args) $keys))
      ((CPU GroupedFoldAllCompiled $group-args $_group-res) (cons (sk-group $group-args) $keys))
      ((CPU CompoundRate $rate-args $_rate-res) (cons (sk-prior $rate-args) $keys))
      ((CPU $_fun $_args $_res) $keys)
      (($type $kbctx $_proof $_tv) (cons (sk-key $type $kbctx) $keys)))))

;; The keys a compound's prior reads directly.
(: sk-prior-inputs (-[det]-> (List SkPattern) (List SkeletonKey)))
(= (sk-prior-inputs $goals) (fold-flat sk-direct-key-step () $goals))
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

;; --- Budgeted search walk ---------------------------------------------------

;; A node's children, each with its hash.
(: sk-children (-[det]-> Number SkPattern (List SkeletonNodeAt)))
(= (sk-children $hash $node)
   (collapse (match &sk_child ($hash $stored $child $child-hash)
      (if (=alpha $stored $node) (sk-node-at $child-hash $child) (empty)))))
