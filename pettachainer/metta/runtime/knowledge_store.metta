(: KbBackend Type)
(: live KbBackend)
(: temp KbBackend)
;; permanent rules only the backward chainer uses: no forward premise index
(: backward KbBackend)

;; The raw clause reference crosses the Prolog FFI and has no MeTTa-level
;; representation.  This is one of the intentionally dynamic boundaries.
(: ClauseRef (Newtype Atom))
(: TempQueryRef Type)
(: clause_ref (-[det]-> ClauseRef TempQueryRef))

(: kb-add-atom (-[det]-> KbBackend $space SpaceAtom Bool))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom backward $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
       ($_ (callPredicate (Predicate (assertz $term $ref)))))
      (add-atom &temp_query_ref (clause_ref $ref))))

;; SWI indexes &kb by a statement's head only, so a lookup by head and
;; arguments walked every fact with that head, across the whole history. Each
;; ground fact is therefore also stored in &kb_prefix under the hash of every
;; prefix of its statement (statement-prefix-hashes), and a fact whose statement
;; has variables in &kb_open, which every prefix lookup also reads (see
;; kb-facts). The rows follow &kb's: added with the same backend, removed with
;; the fact.
(: &kb_prefix (SpaceOf (Number Statement KBContext Proof TV)))
!(bind! &kb_prefix (new-space))
(: &kb_open (SpaceOf (Statement KBContext Proof TV)))
!(bind! &kb_open (new-space))

(: kb-index-fact! (-[det]-> KbBackend Atom Atom))
(= (kb-index-fact! $backend ($type $kbctx $proof $tv))
   (let $fact (data $type $kbctx $proof $tv)
      (if (== (extract-vars $type) ())
         (let $_rows (map-flat (kb-prefix-row! $backend $fact) (statement-prefix-hashes $type)) ())
         (let $_open (kb-add-atom $backend &kb_open (brand SpaceAtom $fact)) ()))))

(: kb-prefix-row! (-[det]-> KbBackend Atom Number Bool))
(= (kb-prefix-row! $backend $fact $hash)
   (kb-add-atom $backend &kb_prefix (brand SpaceAtom (cons-atom $hash $fact))))

(: kb-unindex-fact! (-[det]-> Atom Atom))
(= (kb-unindex-fact! ($type $kbctx $proof $tv))
   (if (== (extract-vars $type) ())
      (let $_rows (map-flat (kb-remove-prefix-row! (data $type $kbctx $proof $tv)) (statement-prefix-hashes $type)) ())
      (let $_open (remove-atom &kb_open ($type $kbctx $proof $tv)) ())))

(: kb-remove-prefix-row! (-[det]-> Atom Number Bool))
(= (kb-remove-prefix-row! ($type $kbctx $proof $tv) $hash)
   (remove-atom &kb_prefix ($hash $type $kbctx $proof $tv)))

;; The stored facts that unify with a statement pattern: through the longest
;; ground prefix of the pattern when it has one, otherwise through &kb.
(: kb-facts (-[det]-> Statement KBContext (List (Statement KBContext Proof TV))))
(= (kb-facts $type $kbctx)
   (case (statement-prefix-hashes $type) (
      (() (collapse (match &kb ($type $kbctx $proof $tv) (data $type $kbctx $proof $tv))))
      ((cons $hash $_shorter)
         (append-flat
            (collapse (match &kb_prefix ($hash $type $kbctx $proof $tv) (data $type $kbctx $proof $tv)))
            (collapse (match &kb_open ($type $kbctx $proof $tv) (data $type $kbctx $proof $tv))))))))

(: kb-add-prem
   (-[det]-> KbBackend Number Number
       (| Goal (Statement KBContext Proof TV))
       Number))
(= (kb-add-prem $backend $id $idx $prem)
   (progn
      (case $prem (
         (($type ($kbid $_ctx $_vars) $_prf $_tv)
            (once
               (kb-add-atom $backend prem_index
                  (make-space-row4
                     (forward-type-trigger-key
                        (brand KB $kbid) (brand Statement $type))
                     $prem $id $idx))))
         ($_cpu ())))
      (+ $idx 1)))

(: observed-inheritance-subject? (-[det]-> KB Statement Bool))
(= (observed-inheritance-subject? $kbid $subj)
   (space-row-present? &inheritance_subject ($kbid $subj)))

;; Keep an empty fold live so later sample proofs can refine it, but do not let
;; its provisional no-evidence value become a public Inheritance proof.
(: MemberInheritanceEvidenceFormula (-[nondet]-> TV  TV))
(= (MemberInheritanceEvidenceFormula $tv)
   (if (== $tv no-evidence) (empty) $tv))

(: inheritance-subject-prior-tv (-[det]-> KB Statement TV))
(= (inheritance-subject-prior-tv $kbid $subj)
   (if (observed-inheritance-subject? $kbid $subj)
      (let $scale (fa-mass-scale $kbid)
         (if (== $scale 0.0) no-evidence (STV $scale 1.0)))
      no-evidence))

;; A rule's expected premise confidence is a pure function of its premise
;; structure and stored TVs, so it is computed once here instead of on every
;; rule-goal expansion. No entry (the computation can fail on exotic premise
;; shapes) means the expansion falls back to computing it on the fly.
(: store-rule-expected-score!
   (-[det]-> KbBackend Number
       (List (| Goal (Statement KBContext Proof TV)))
       (| Bool (List $none))))
(= (store-rule-expected-score! $backend $id $args)
   (let $hits
      (collapse
         (premises-expected-confidence
            (copy_term $args)))
      (if (== $hits ()) ()
         (once
            (kb-add-atom $backend rule_expected
               (make-space-pair $id (car-atom $hits)))))))

;; Temp (per-query) rule ids are offset so they can never collide with live
;; rule ids: both counters start at 0 and rules/rule_expected/prem_index rows
;; from both backends share the same spaces.
;; Index rules by the statement name embedded in their conclusion proof so
;; remove-compiled-statement can find them without scanning the rules space.
;; Rules whose proof carries no extractable name (open query adapters,
;; negated outputs) are simply not indexed -- they cannot be removed by name.
(: register-rule-name!
   (-[det]-> KbBackend Number (Statement KBContext Proof TV)
       (| Bool (List $none))))
(= (register-rule-name! $backend $id $ccls)
   (case $ccls (
      (($_type $_kb $prf $_tv)
         (if (is-var $prf) ()
            (let $name (rule-evidence-head $prf)
               (if (is-var $name) ()
                  (if (is-expr $name) ()
                     (once
                        (kb-add-atom $backend rule_name_index
                           (make-space-pair $name $id))))))))
      ($_other ()))))

(: typed-runtime-fact
   (-[det]-> Atom (Statement KBContext Proof TV)))
(= (typed-runtime-fact $fact)
   (case $fact
      ((($type $kb $proof $tv)
         (assemble-runtime-fact
            (brand Statement $type)
            (brand KBContext $kb)
            (brand Proof $proof)
            (checked-stored-tv $tv))))))

(: typed-runtime-premise
   (-[semidet]-> Atom
       (| Goal (Statement KBContext Proof TV))))
(= (typed-runtime-premise $premise)
   (if (= $premise (CPU $formula $arguments $result))
      (CPU $formula $arguments $result)
      (typed-runtime-fact $premise)))

;; Compiler output crosses an erased-expression storage boundary here. Restore
;; each premise's nominal role while walking the list we already consume,
;; rather than reflectively checking the complete list with `(the ...)`.
(: typed-runtime-premises
   (-[semidet]-> Atom
       (List (| Goal (Statement KBContext Proof TV)))))
(= (typed-runtime-premises $premises)
   (case $premises (
      (() ())
      ((cons $premise $rest)
         (cons
            (typed-runtime-premise $premise)
            (typed-runtime-premises $rest))))))

;; An Inheritance fact records its concepts as nodes, and its subject too when
;; the fact is an observation rather than a materialized conclusion.
(: record-fact-inheritance-nodes! (-[det]-> (Statement KBContext Proof TV) Bool Atom))
(= (record-fact-inheritance-nodes! $fact $record-subject?)
   (case $fact (
      (((Inheritance $subj $concept) ($kbid $_ctx $_vars) $_prf $_tv)
         (if (is-var $subj) ()
            (let* (($typed-kb (brand KB $kbid))
                   ($typed-subj (brand Statement $subj))
                   ($_subject (if $record-subject? (record-inheritance-subject! $typed-kb $typed-subj) ())))
               (record-inheritance-nodes! $typed-kb $typed-subj (brand Statement $concept)))))
      ($_other ()))))

(: kb-add-expr
   (-[nondet]-> KbBackend RuntimeAddition  (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($typed-ccls (typed-runtime-fact $ccls))
          ($rule-args (typed-runtime-premises $args))
          ($id
             (if (== $backend temp)
                (+ 1000000000 (next-search-id bwd_tmp_ruleid))
                (next-search-id ruleid)))
           ($_1 (if (== $backend backward) 0 (fold-flat (kb-add-prem $backend $id) 0 $rule-args)))
           ($ccls-row
              (make-space-row3 $typed-ccls $id $rule-args))
           ($_2
              (kb-add-atom $backend ccls_index $ccls-row))
           ($_3
              (kb-add-atom $backend rules
                 (brand SpaceAtom
                    (runtime-rule-row
                       $id $typed-ccls $rule-args))))
           ($_expected (store-rule-expected-score! $backend $id $rule-args))
           ($_name-idx
              (register-rule-name! $backend $id $typed-ccls))
           ($_journal (sk-note-rule! $id))
           ($_aggregates
              (register-forward-aggregate-premises!
                 (== $backend live) $rule-args)))
         ())
      (let $fact
         (typed-runtime-fact $expr)
         (if (== $backend live)
            (if (space-row-present? &kb $fact) ()
               (let*
                  ((($type $kb $_prf $_tv) $fact)
                   ($_add (chainer-add-atom &kb $fact))
                   ($_index (kb-index-fact! live $fact))
                   ($_journal (sk-note-fact! $type $kb))
                   ($_nodes (record-fact-inheritance-nodes! $fact true)))
                  ;; The aggregates observing the statement count it at once,
                  ;; with its stored facts merged, as a removal recounts it:
                  ;; whether a forward run takes it is not theirs to decide.
                  (case (stored-statement-candidate $type $kb false) (
                     ((forward-derived $merged $_ev) (forward-maintain-aggregates! aggregate-update $merged))
                     (no-forward-output-candidate ())))))
            (let $_index (kb-index-fact! $backend $fact)
               (kb-add-atom $backend &kb (brand SpaceAtom $fact)))))))

(: clear-temp-query-adds (-[det]-> (List $none)))
(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn
               (callPredicate (Predicate (erase $ref)))
               (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(: inject-compiled-adds
   (-[nondet]-> (List RuntimeAddition)  (List $none)))
(= (inject-compiled-adds $adds)
   (foreach-flat (kb-add-expr temp) $adds))

;; --- Removal of compiled statements by name ---------------------------------
;; Inverse of compileadd for one named statement: retracts the &kb facts whose
;; proof is the name and every rule row registered under it in
;; rule_name_index, including the rows kb-add-expr created alongside
;; (prem_index, ccls_index, rule_expected). Computed base
;; rates of the affected kb are invalidated because removal is non-monotonic.
;; In contrast, kb-add-expr preserves computed snapshots: added proofs cannot
;; invalidate previous evidence and later chaining refines the cached estimate.

(: remove-rule-row! (-[det]-> Number (List $none)))
(= (remove-rule-row! $id)
   (let $_
      (collapse
         (match rules
            (runtime-rule-row $id $ccls $args)
            (let*
               (($_prems
                   (remove-atom prem_index ($_pkey $_prem $id $_pidx)))
                ($_ccls-idx
                   (remove-atom ccls_index ($ccls $id $_prems2)))
                ($_expected
                   (remove-atom rule_expected ($id $_score)))
                (($_type ($kbid $_ctx $_vars) $_prf $_tv) $ccls)
                ($_invalidate
                   (invalidate-computed-base-rates! (brand KB $kbid)))
                ($_row
                   (remove-atom rules
                      (runtime-rule-row $id $ccls $args))))
               ())))
      ()))

;; A removed fact's statement is observed by the aggregates as what its
;; remaining facts say, or not at all.
(: remove-named-fact! (-[det]-> Proof (Statement KBContext TV) (List $none)))
(= (remove-named-fact! $name ($type $kb $tv))
   (let* (($_remove (remove-atom &kb ($type $kb $name $tv)))
          ($_unindex (kb-unindex-fact! ($type $kb $name $tv)))
          ($_journal (sk-note-fact! $type $kb))
          ($_base-rates (invalidate-computed-base-rates! (brand KB (car-atom $kb)))))
      (case (stored-statement-candidate $type $kb false) (
         ((forward-derived $rest $_ev) (forward-maintain-aggregates! aggregate-update $rest))
         (no-forward-output-candidate
            (forward-maintain-aggregates! aggregate-remove (assemble-runtime-fact $type $kb $name $tv)))))))

(: remove-compiled-statement (-[det]-> Proof (List $none)))
;; Deprecated compatibility boundary. It removes current KB/compiler rows but
;; deliberately does not forget durable backward proof history.
(= (remove-compiled-statement $name)
   (let*
      (($_specialization (remove-specialization-state! $name))
       ($_facts
          (foreach-flat (remove-named-fact! $name)
             (collapse (match &kb ($type $kb $name $tv) (data $type $kb $tv)))))
       ($ids
          (list_to_set
             (collapse
                (match rule_name_index ($name $id)
                   (the Number $id)))))
       ($_rules (foreach-flat remove-rule-row! $ids))
       ($_index (collapse (remove-atom rule_name_index ($name $_any)))))
      ()))
