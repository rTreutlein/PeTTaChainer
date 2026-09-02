(: KbBackend Type)
(: live KbBackend)
(: temp KbBackend)

;; The raw clause reference crosses the Prolog FFI and has no MeTTa-level
;; representation.  This is one of the intentionally dynamic boundaries.
(: ClauseRef (Newtype Atom))
(: TempQueryRef Type)
(: clause_ref (-[det]-> ClauseRef TempQueryRef))

(: kb-add-atom (-[det]-> KbBackend $space SpaceAtom Bool))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
       ($_ (callPredicate (Predicate (assertz $term $ref)))))
      (add-atom &temp_query_ref (clause_ref $ref))))

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
               (kb-add-atom $backend prem_index
                  (make-space-row4 $key $prem $id $idx))))
         (+ $idx 1))))

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

(: kb-add-expr
   (-[nondet]-> KbBackend RuntimeAddition  (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($typed-ccls (typed-runtime-fact $ccls))
          ($rule-args (typed-runtime-premises $args))
          ($id
             (if (== $backend live)
                (next-search-id ruleid)
                (+ 1000000000 (next-search-id bwd_tmp_ruleid))))
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
           ($_aggregates
              (register-forward-aggregate-premises!
                 (== $backend live) $rule-args)))
         ())
      (let $fact
         (typed-runtime-fact $expr)
         (if (== $backend live)
            (let*
               ((($type $kb $prf $_tv) $fact)
                ($ev (cons (fact-ev $kb $prf $type) ()))
                ($change
                   (forward-candidate-upsert!
                      (forward-derived $fact $ev) true))
                ($_member-cache
                   (forward-apply-unqueued-member-change! $change)))
               ())
            (kb-add-atom $backend &kb
               (brand SpaceAtom $fact))))))

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

(: remove-compiled-statement (-[det]-> Proof (List $none)))
;; Deprecated compatibility boundary. It removes current KB/compiler rows but
;; deliberately does not forget durable backward proof history.
(= (remove-compiled-statement $name)
   (let*
      (($_specialization (remove-specialization-state! $name))
       ($_facts
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
                    ($change
                       (forward-refresh-output-key!
                          (forward-output-key $kb $type)))
                    ($_forward-state
                       (forward-apply-unqueued-change! $change))
                    (($kbid $_ctx $_vars) $kb)
                    ($_base-rates
                       (invalidate-computed-base-rates! (brand KB $kbid)))
                    ($_member-inheritance
                       (forward-maintain-member-aggregates!
                          aggregate-remove
                          (assemble-runtime-fact
                             $type $kb $name (the TV $tv)))))
                   ()))))
       ($ids
          (list_to_set
             (collapse
                (match rule_name_index ($name $id)
                   (the Number $id)))))
       ($_rules (foreach-flat remove-rule-row! $ids))
       ($_index (collapse (remove-atom rule_name_index ($name $_any)))))
      ()))
