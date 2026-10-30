;; Owns exposed KB facts, their statement indexes, source-catalog roles and
;; derived-copy provenance. Controllers choose which value to expose or retire;
;; this module owns the corresponding physical publication transaction.
;; Catalog roles are observation, prediction, materialized and summary.
;; The withdrawal ledger calls prediction copies `forward`.

(datatype KbBackend
   live
   temp
   ;; permanent rules only the backward chainer uses: no forward premise index
   backward)

;; The raw clause reference crosses the Prolog FFI and has no MeTTa-level
;; representation.  This is one of the intentionally dynamic boundaries.
(: ClauseRef (Newtype Atom))
(datatype TempQueryRef (clause_ref ClauseRef))

(: kb-add-atom (-[det]-> KbBackend $space SpaceAtom Bool))
(= (kb-add-atom live $space $expr) (add-space-atom! $space $expr))
(= (kb-add-atom backward $space $expr) (add-space-atom! $space $expr))
(= (kb-add-atom temp $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
       ($_ (callPredicate (Predicate (assertz $term $ref)))))
      (add-atom &temp_query_ref (clause_ref $ref))))


;; Temporary insertions keep exact clause references, including their fact
;; indexes. Remove that whole publication lifetime before dropping its catalog.
(: clear-temp-query-adds (-[det]-> (List $none)))
(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn
               (callPredicate (Predicate (erase $ref)))
               (remove-atom &temp_query_ref (clause_ref $ref)))))
      (collapse (match &installed_producers ($hash temp $add) (remove-atom &installed_producers ($hash temp $add))))
      (source-catalog-clear-temp!)
      (rule-dormancy-forget-temp!)
      ()))

;; The &kb_prefix and &kb_open rows of a fact (runtime/kb_index.metta).
(: kb-index-fact! (-[det]-> KbBackend Atom Atom Atom))
(= (kb-index-fact! $backend $role ($type $kbctx $proof $tv))
   (let* (($fact (data $type $kbctx $proof $tv))
          ($_catalog (source-catalog-fact! $backend $role $fact))
          ($_rows (map-flat (kb-index-row! $backend &kb_prefix $fact) (kb-fact-prefix-hashes $type))))
      (if (== (extract-vars $type) ()) ()
         (let $_open (kb-index-row! $backend &kb_open $fact (kb-fact-open-hash $type)) ()))))

(: kb-index-row! (-[det]-> KbBackend $space Atom Number Bool))
(= (kb-index-row! $backend $space $fact $hash)
   (kb-add-atom $backend $space (brand SpaceAtom (cons-atom $hash $fact))))

(: kb-unindex-fact! (-[det]-> Atom Atom))
(= (kb-unindex-fact! ($type $kbctx $proof $tv))
   (let* (($fact (data $type $kbctx $proof $tv))
          ($_catalog (source-catalog-unindex! $fact))
          ($_rows (map-flat (kb-remove-prefix-row! (data $type $kbctx $proof $tv)) (kb-fact-prefix-hashes $type))))
      (if (== (extract-vars $type) ()) ()
         (let* (($hash (kb-fact-open-hash $type))
                ($_open (remove-atom &kb_open ($hash $type $kbctx $proof $tv))))
            ()))))

(: kb-remove-prefix-row! (-[det]-> Atom Number Bool))
(= (kb-remove-prefix-row! ($type $kbctx $proof $tv) $hash)
   (remove-atom &kb_prefix ($hash $type $kbctx $proof $tv)))

(: kb-publish-fact! (-[semidet]-> KbBackend Atom SkFact (| Bool (List $none))))
(= (kb-publish-fact! $backend $role $fact)
   (if (== $backend live)
      (let* (($_fact (chainer-add-atom &kb $fact))
             ($_index (kb-index-fact! live $role $fact)))
         ())
      (let $_index (kb-index-fact! $backend $role $fact)
         (kb-add-atom $backend &kb (brand SpaceAtom $fact)))))

;; Re-materializing replaces only the previous materialization of this output.
(: materialized-rows (-[det]-> ForwardOutputKey (List MaterializedRow)))
(= (materialized-rows (forward-output-key $kb $type))
   (let $hash (forward-output-index-hash (forward-output-key $kb $type))
      (collapse (match &materialized_facts (materialized-row $hash $type $kb $fact $ev)
         (materialized-row $hash $type $kb $fact $ev)))))

(: remove-materialized! (-[det]-> MaterializedRow Atom))
(= (remove-materialized! (materialized-row $hash $type $kb ($type $kb $proof $tv) $ev))
   (let* (($_fact (remove-atom &kb ($type $kb $proof $tv)))
          ($_unindex (kb-unindex-fact! ($type $kb $proof $tv)))
          ($_rules (forget-stored-rules! materialized $hash (sk-key $type $kb)))
          ($_mark (remove-atom &materialized_facts (materialized-row $hash $type $kb ($type $kb $proof $tv) $ev))))
      ()))

;; A re-materialization of an output key replaces the key's earlier
;; materialized rows. Marked facts are never leaves of the backward search.
(: kb-publish-materialized! (-[semidet]-> SkFact EvidenceSet Proof Atom))
(= (kb-publish-materialized! ($type $kb $proof $tv) $ev $source)
   (let* (($fact (data $type $kb $proof $tv))
          ($hash (forward-output-index-hash (forward-output-key $kb $type)))
          ($row (materialized-row $hash $type $kb $fact $ev)))
      (if (space-row-present? &materialized_facts $row) ()
         (let* (($_remove (foreach-flat remove-materialized! (materialized-rows (forward-output-key $kb $type))))
                ($_add (chainer-add-atom &kb $fact))
                ($_index (kb-index-fact! live materialized $fact))
                ($_rules (record-stored-rules! materialized $hash (sk-key $type $kb) $source))
                ($_mark (add-atom &materialized_facts $row)))
            (sk-note-fact! $type $kb)))))

(: kb-remove-prediction! (-[det]-> Number SkeletonKey Atom))
(= (kb-remove-prediction! $hash $key)
   (let $_removed
      (collapse (match &sk_forward_stored ($hash $stored $old $old-ev $old-deps)
         (if (=alpha $stored $key)
            (let* (($_kb (remove-atom &kb $old))
                   ($_unindex (kb-unindex-fact! $old))
                   ($_rules (forget-stored-rules! forward $hash $key)))
               (remove-atom &sk_forward_stored ($hash $stored $old $old-ev $old-deps)))
            (empty))))
      ()))

;; A derived key the run built on has its value stored in &kb, like a fact, so a
;; later query reads it without searching for it again. It replaces the fact an
;; earlier run stored for the key and keeps the value's evidence and what it
;; was derived through, so no reader uses it to support itself. A value that is
;; one of the key's stored facts needs no copy: removing an identical copy
;; would remove the fact too.
(: kb-publish-prediction! (-[semidet]-> SkeletonKey SkeletonValue Atom))
(= (kb-publish-prediction! $key (sk-val ($type $kbctx $proof $tv) $ev $deps))
   (let* (($hash (index-hash $key))
          ($fact (assemble-runtime-fact $type $kbctx $proof $tv))
          ($_old (kb-remove-prediction! $hash $key))
          ($_copy
             (if (kb-fact-present? $fact) ()
                (let* (($_rules (record-stored-rules! forward $hash $key $proof))
                       ($_stored (add-atom &sk_forward_stored ($hash $key $fact $ev $deps)))
                       ($_kb (add-atom &kb $fact)))
                   (kb-index-fact! live prediction $fact)))))
      (sk-note-fact! $type $kbctx)))

(: kb-publish-summary! (-[semidet]-> Number SkeletonKey Number SkeletonValue Atom))
(= (kb-publish-summary! $hash $key $epoch (sk-val ($type $kbctx $proof $tv) $ev $deps))
   (let* (($summary (assemble-runtime-fact $type $kbctx (brand Proof (forgotten $hash $epoch)) $tv))
          ($_provenance (record-summary-rules! $hash $epoch $proof))
          ($_registered (record-stored-rules! summary $hash $key (brand Proof (forgotten $hash $epoch))))
          ($_stored (add-atom &sk_summary ($hash $key $summary $ev $deps)))
          ($_kb (add-atom &kb $summary)))
      (kb-index-fact! live summary $summary)))

;; Withdrawal has already found the affected copies through their source sets.
;; A summary's thaw/reconstruction policy belongs to forgetting, after removal.
(: kb-retire-copy! (-[det]-> Atom Number SkeletonKey Atom))
(= (kb-retire-copy! $kind $hash $key)
   (case $kind (
      (materialized
         (case $key (((sk-key $type $kbctx)
            (foreach-flat remove-materialized! (materialized-rows (forward-output-key $kbctx $type))))
                   ($_fold ()))))
      (forward (kb-remove-prediction! $hash $key))
      (summary
         (let $_removed
            (collapse (match &sk_summary ($hash $stored $fact $ev $deps)
               (if (=alpha $stored $key)
                  (let* (($_kb (remove-atom &kb $fact)) ($_index (kb-unindex-fact! $fact)))
                     (remove-atom &sk_summary ($hash $stored $fact $ev $deps)))
                  (empty))))
            ())))))
