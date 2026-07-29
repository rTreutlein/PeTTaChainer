(: KbBackend Type)
(: live KbBackend)
(: temp KbBackend)

;; The raw clause reference crosses the Prolog FFI and has no MeTTa-level
;; representation.  This is one of the intentionally dynamic boundaries.
(: ClauseRef (Newtype Expression))
(: TempQueryRef Type)
(: clause_ref (-[det]-> ClauseRef TempQueryRef))

(: assert-space-atom-ref (-[det]-> $space SpaceAtom ClauseRef))
(= (assert-space-atom-ref $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
        ($_ (callPredicate (Predicate (assertz $term $ref)))))
      (brand ClauseRef $ref)))

(: erase-clause-ref (-[det]-> ClauseRef Bool))
(= (erase-clause-ref $ref)
   (let $_erased
      (callPredicate (Predicate (erase $ref)))
      true))

(: track-temp-query-ref (-[det]-> ClauseRef Bool))
(= (track-temp-query-ref $ref) (add-atom &temp_query_ref (clause_ref $ref)))

(: kb-add-atom (-[det]-> KbBackend $space SpaceAtom Bool))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr)
   (let $ref
      (assert-space-atom-ref $space $expr)
      (track-temp-query-ref $ref)))

(: kb-add-prem
   (-[det]-> KbBackend Number Number
       (| Goal (Statement KBContext Proof TV))
       Number))
(= (kb-add-prem $backend $id $idx $prem)
   (let $key
      (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) ()
            (once
               (let $row
                  (make-space-row4 $key $prem $id $idx)
                  (kb-add-atom $backend prem_index $row))))
         (+ $idx 1))))

(: kb-context-kbid (-[det]-> KBContext KB))
(= (kb-context-kbid ($kbid $_ctx $_vars))
   (brand KB $kbid))

(: observed-inheritance-subject? (-[det]-> KB Statement Bool))
(= (observed-inheritance-subject? $kbid $subj)
   (not (== (collapse (once (match &inheritance_subject ($kbid $subj) true))) ())))

;; Keep an empty fold live so later sample proofs can refine it, but do not let
;; its provisional no-evidence value become a public Inheritance proof.
(: MemberInheritanceEvidenceFormula (-[nondet]-> TV  TV))
(= (MemberInheritanceEvidenceFormula $tv)
   (if (== $tv no-evidence) (empty) $tv))

(: inheritance-subject-prior-tv (-[det]-> KB Statement TV))
(= (inheritance-subject-prior-tv $kbid $subj)
   (if (observed-inheritance-subject? $kbid $subj)
      (let $universe-size (kb-universe-size $kbid)
         (if (== $universe-size no-universe-size)
            (let $n (list-len (inheritance-subjects $kbid))
               (if (<= $n 0) no-evidence (STV (/ 1.0 $n) 1.0)))
            (let $size (the Number $universe-size)
               (if (<= $size 0.0) no-evidence
                  (STV (/ 1.0 $size) 1.0)))))
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
            (let*
               (($expected (car-atom $hits))
                ($row (make-space-pair $id $expected)))
               (kb-add-atom $backend rule_expected $row))))))

;; Temp (per-query) rule ids are offset so they can never collide with live
;; rule ids: both counters start at 0 and rules/rule_expected/prem_index rows
;; from both backends share the same spaces.
(: next-rule-id (-[det]-> KbBackend Number))
(= (next-rule-id $backend)
   (if (== $backend live)
      (next-search-id ruleid)
      (+ 1000000000 (next-search-id bwd_tmp_ruleid))))

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
                        (let $row
                           (make-space-pair $name $id)
                           (kb-add-atom
                              $backend rule_name_index $row))))))))
      ($_other ()))))

(: typed-runtime-fact
   (-[det]-> Expression (Statement KBContext Proof TV)))
(= (typed-runtime-fact $fact)
   (case $fact
      ((($type $kb $proof $tv)
         (assemble-runtime-fact
            (brand Statement $type)
            (brand KBContext $kb)
            (brand Proof $proof)
            (checked-stored-tv $tv))))))

(: typed-runtime-premise
   (-[semidet]-> Expression
       (| Goal (Statement KBContext Proof TV))))
(= (typed-runtime-premise $premise)
   (if (= $premise (CPU $formula $arguments $result))
      (CPU $formula $arguments $result)
      (typed-runtime-fact $premise)))

;; Compiler output crosses an erased-expression storage boundary here. Restore
;; each premise's nominal role while walking the list we already consume,
;; rather than reflectively checking the complete list with `(the ...)`.
(: typed-runtime-premises
   (-[semidet]-> Expression
       (List (| Goal (Statement KBContext Proof TV)))))
(= (typed-runtime-premises $premises)
   (case $premises (
      (() ())
      ((cons $premise $rest)
         (cons
            (typed-runtime-premise $premise)
            (typed-runtime-premises $rest))))))

(: kb-add-expr
   (-[nondet]-> KbBackend RuntimeAddition  (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($typed-ccls (typed-runtime-fact $ccls))
          ($rule-args (typed-runtime-premises $args))
          ($id (next-rule-id $backend))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $rule-args))
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
           ($_base-rates
              (if (== $backend live)
                 (register-forward-base-rate-premises! $rule-args)
                 ()))
           ($_member-inheritance
              (register-forward-member-inheritance-premises! $rule-args)))
         ())
      (progn
         (let $fact
            (typed-runtime-fact $expr)
            (if (== $backend live)
               (let*
                  ((($type $kb $prf $_tv) $fact)
                   ($ev (cons (fact-ev $kb $prf $type) ()))
                   ($_change
                      (forward-candidate-upsert!
                         (forward-derived $fact $ev))))
                  ())
               (kb-add-atom $backend &kb
                  (brand SpaceAtom $fact)))))))

(: clear-temp-query-adds (-[det]-> (List $none)))
(= (clear-temp-query-adds)
   (progn
      (collapse
         (match &temp_query_ref (clause_ref $ref)
            (progn (erase-clause-ref $ref) (remove-atom &temp_query_ref (clause_ref $ref)))))
      ()))

(: inject-compiled-adds
   (-[nondet]-> (List RuntimeAddition)  (List $none)))
(= (inject-compiled-adds ()) ())
(= (inject-compiled-adds (cons $add $rest))
   (progn
      (kb-add-expr temp $add)
      (inject-compiled-adds $rest)))

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
                   (collapse
                      (match prem_index ($pkey $prem $id $pidx)
                         (remove-atom prem_index ($pkey $prem $id $pidx)))))
                ($_ccls-idx
                   (remove-atom ccls_index ($ccls $id $prems)))
                ($_expected
                   (collapse
                      (match rule_expected ($id $score)
                         (remove-atom rule_expected ($id $score)))))
                ($_invalidate
                   (let ($_type $kbctx $_prf $_tv) $ccls
                      (invalidate-computed-base-rates!
                         (kb-context-kbid $kbctx))))
                ($_row
                   (remove-atom rules
                      (runtime-rule-row $id $ccls $args))))
               ())))
      ()))

(: remove-kb-facts-named! (-[det]-> Proof (List $none)))
(= (remove-kb-facts-named! $name)
   (let $_
      (collapse
         (match &forward_frontier
            (forward-frontier-row
               $hash $type $kb ($type $kb $name $tv) $ev)
            (let*
               (($_remove
                   (remove-atom &forward_frontier
                      (forward-frontier-row
                         $hash $type $kb
                         ($type $kb $name $tv) $ev)))
                ($key (forward-output-key $kb $type))
                ($change (forward-refresh-output-key! $key))
                ($_forward-state
                   (forward-apply-unqueued-change! $change))
                ($_base-rates
                   (invalidate-computed-base-rates!
                      (kb-context-kbid $kb)))
                ($_member-inheritance
                   (case (quote ($type $kb $name $tv)) (
                         (((Member $obj $class)
                           ($kbid MAIN Nil) $_prf $_tv)
                         (forward-remove-member-inheritances-for-key
                            (brand KB $kbid)
                            (brand Term $obj)
                            (brand Term $class)))
                      ($_other ())))))
               ())))
      ()))

;; Rule indexes are erased spaces. Validate their scalar id at this infrequent
;; removal boundary rather than checking the complete collected list.
(: stored-rule-id (-[det]-> Atom Number))
(= (stored-rule-id $id)
   (the Number $id))

(: remove-compiled-statement (-[det]-> Proof (List $none)))
(= (remove-compiled-statement $name)
   (let*
      (($_specialization (remove-specialization-state! $name))
       ($_facts (remove-kb-facts-named! $name))
       ($ids
          (list_to_set
             (collapse
                (match rule_name_index ($name $id)
                   (stored-rule-id $id)))))
       ($_rules (foreach-flat remove-rule-row! $ids))
       ($_index
          (if (== $ids ()) ()
             (collapse
                (remove-atom rule_name_index ($name $_any))))))
      ()))
