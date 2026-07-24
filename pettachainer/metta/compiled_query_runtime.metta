(: KbBackend Type)
(: live KbBackend)
(: temp KbBackend)

;; The raw clause reference crosses the Prolog FFI and has no MeTTa-level
;; representation.  This is one of the intentionally dynamic boundaries.
(: assert-space-atom-ref (-> $space $expression $clause-ref))
(= (assert-space-atom-ref $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
        ($_ (callPredicate (Predicate (assertz $term $ref)))))
      $ref))

(: erase-clause-ref (-> $clause-ref $effect))
(= (erase-clause-ref $ref) (callPredicate (Predicate (erase $ref))))

(: track-temp-query-ref (-> $clause-ref Bool))
(= (track-temp-query-ref $ref) (add-atom &temp_query_ref (clause_ref $ref)))

(: kb-add-atom (-> KbBackend $space $expression Bool))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr) (track-temp-query-ref (assert-space-atom-ref $space $expr)))

(: kb-add-prem
   (-> KbBackend Number Number
       (| Goal (Statement KBContext Proof TV))
       Number))
(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn
         (if (== $key ()) ()
            (once
               (kb-add-atom $backend prem_index
                  ($key $prem $id $idx))))
         (+ $idx 1))))

(: kb-add-ccl-head-index
   (-> KbBackend Number
       (Statement KBContext Proof TV)
       (| Bool (List $none))))
(= (kb-add-ccl-head-index $backend $id $ccls)
   (let $key (forward-indexable-premise-key $ccls)
      (if (== $key ()) ()
         (once
            (kb-add-atom $backend ccls_head_index ($key $id))))))

(: kb-expr-kbid (-> Expression (| KB (List $none))))
(= (kb-expr-kbid $expr)
   (case $expr (
      (($_type ($kbid $_ctx $_vars) $_prf $_tv)
         (brand KB $kbid))
      ($_other ()))))

(: observed-inheritance-subject? (-> KB Statement Bool))
(= (observed-inheritance-subject? $kbid $subj)
   (not (== (collapse (once (match &inheritance_subject ($kbid $subj) true))) ())))

;; Keep an empty fold live so later sample proofs can refine it, but do not let
;; its provisional no-evidence value become a public Inheritance proof.
(: MemberInheritanceEvidenceFormula (-[nondet]-> TV  TV))
(= (MemberInheritanceEvidenceFormula $tv)
   (if (== $tv no-evidence) (empty) $tv))

(: inheritance-subject-prior-tv (-> KB Statement TV))
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
   (-> KbBackend Number (List Expression) (| Bool (List $none))))
(= (store-rule-expected-score! $backend $id $args)
   (let $hits
      (collapse
         (premises-expected-confidence
            (copy_term $args)))
      (if (== $hits ()) ()
         (once
            (kb-add-atom $backend rule_expected
               ($id (car-atom $hits)))))))

;; Temp (per-query) rule ids are offset so they can never collide with live
;; rule ids: both counters start at 0 and rules/rule_expected/prem_index rows
;; from both backends share the same spaces.
(: next-rule-id (-> KbBackend Number))
(= (next-rule-id $backend)
   (if (== $backend live)
      (next-search-id ruleid)
      (+ 1000000000 (next-search-id bwd_tmp_ruleid))))

;; Index rules by the statement name embedded in their conclusion proof so
;; remove-compiled-statement can find them without scanning the rules space.
;; Rules whose proof carries no extractable name (open query adapters,
;; negated outputs) are simply not indexed -- they cannot be removed by name.
(: register-rule-name!
   (-> KbBackend Number (Statement KBContext Proof TV)
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
                           ($name $id))))))))
      ($_other ()))))

(: typed-runtime-fact
   (-> Expression (Statement KBContext Proof TV)))
(= (typed-runtime-fact $fact)
   (case $fact
      ((($type $kb $proof $tv)
         (assemble-runtime-fact
            (brand Statement $type)
            (brand KBContext $kb)
            (brand Proof $proof)
            (the TV $tv))))))

(: kb-add-expr
   (-[nondet]-> KbBackend RuntimeAddition  (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($typed-ccls (typed-runtime-fact $ccls))
          ($rule-args (the (List Expression) $args))
          ($id (next-rule-id $backend))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $rule-args))
           ($_2 (kb-add-atom $backend ccls_index ($typed-ccls $id)))
           ($_3 (kb-add-ccl-head-index $backend $id $typed-ccls))
           ($_4
              (kb-add-atom $backend rules
                 (runtime-rule-row
                    $id $typed-ccls $rule-args)))
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
         (if (== $backend live)
            (let*
               ((($type $kb $prf $_tv) $expr)
                ($ev (cons (fact-ev $kb $prf $type) ()))
                ($_change
                   (forward-candidate-upsert!
                      (forward-derived $expr $ev))))
               ())
            (kb-add-atom $backend &kb $expr)))))

(: clear-temp-query-adds (-> (List $none)))
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
;; (prem_index, ccls_index, ccls_head_index, rule_expected). Computed base
;; rates of the affected kb are invalidated because removal is non-monotonic.
;; In contrast, kb-add-expr preserves computed snapshots: added proofs cannot
;; invalidate previous evidence and later chaining refines the cached estimate.

(: remove-rule-row! (-> Number (List $none)))
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
                ($_ccls-idx (remove-atom ccls_index ($ccls $id)))
                ($hkey (forward-indexable-premise-key $ccls))
                ($_head-idx (if (== $hkey ()) () (remove-atom ccls_head_index ($hkey $id))))
                ($_expected
                   (collapse
                      (match rule_expected ($id $score)
                         (remove-atom rule_expected ($id $score)))))
                ($_invalidate (invalidate-computed-base-rates! (kb-expr-kbid $ccls)))
                ($_row
                   (remove-atom rules
                      (runtime-rule-row $id $ccls $args))))
               ())))
      ()))

(: remove-kb-facts-named! (-> Proof (List $none)))
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
                      (kb-expr-kbid (quote ($type $kb $name $tv)))))
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

(: remove-compiled-statement (-> Proof (List $none)))
(= (remove-compiled-statement $name)
   (let*
      (($_specialization (remove-specialization-state! $name))
       ($_facts (remove-kb-facts-named! $name))
       ($ids (list_to_set (collapse (match rule_name_index ($name $id) $id))))
       ($_rules (foreach-flat remove-rule-row! $ids))
       ($_index
          (if (== $ids ()) ()
             (collapse
                (remove-atom rule_name_index ($name $_any))))))
      ()))
