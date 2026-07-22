(: KbBackend Type)
(: live KbBackend)
(: temp KbBackend)

(: ConceptPriorConfidence Type)
(: concept-prior-confidence (-> $kb Number ConceptPriorConfidence))

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

(: record-concept-node! (-> $kb $node (| Bool (List $none))))
(= (record-concept-node! $kbid $node)
   (if (is-var $node) ()
      (add-atom &concept_node ($kbid $node))))

(: record-inheritance-nodes!
   (-> $kb $subject $concept (| Bool (List $none))))
(= (record-inheritance-nodes! $kbid $subj $concept)
   (progn
      (record-concept-node! $kbid $subj)
      (record-concept-node! $kbid $concept)))

(: kb-add-atom (-> KbBackend $space $expression Bool))
(= (kb-add-atom live $space $expr) (add-atom $space $expr))
(= (kb-add-atom temp $space $expr) (track-temp-query-ref (assert-space-atom-ref $space $expr)))

(: kb-add-prem (-> KbBackend Number Number $premise Number))
(= (kb-add-prem $backend $id $idx $prem)
   (let $key (forward-indexable-premise-key $prem)
      (progn (if (== $key ()) () (kb-add-atom $backend prem_index ($key $prem $id $idx))) (+ $idx 1))))

(: kb-add-ccl-head-index
   (-> KbBackend Number $conclusion (| Bool (List $none))))
(= (kb-add-ccl-head-index $backend $id $ccls)
   (let $key (forward-indexable-premise-key $ccls)
      (if (== $key ()) () (kb-add-atom $backend ccls_head_index ($key $id)))))

(: default-concept-prior-confidence (-> Number))
(= (default-concept-prior-confidence) 0.000001)

(: concept-prior-confidence-entries
   (-> $kb (List ConceptPriorConfidence)))
(= (concept-prior-confidence-entries $kbid)
   (collapse
      (match &concept_prior_confidence (concept-prior-confidence $kbid $c)
         (concept-prior-confidence $kbid $c))))

(: concept-prior-confidence-remove-entry!
   (-> ConceptPriorConfidence Bool))
(= (concept-prior-confidence-remove-entry! $entry) (remove-atom &concept_prior_confidence $entry))

(: clear-concept-prior-confidence (-> $kb (List $none)))
(= (clear-concept-prior-confidence $kbid)
   (let*
      (($_remove (foreach-flat concept-prior-confidence-remove-entry! (concept-prior-confidence-entries $kbid)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: set-concept-prior-confidence (-> $kb Number (List $none)))
(= (set-concept-prior-confidence $kbid $c)
   (let*
      (($_old (clear-concept-prior-confidence $kbid))
       ($_new (add-atom &concept_prior_confidence (concept-prior-confidence $kbid $c)))
       ($_invalidate (invalidate-computed-base-rates! $kbid)))
      ()))

(: kb-concept-prior-confidence (-> $kb Number))
(= (kb-concept-prior-confidence $kbid)
   (let $entries (concept-prior-confidence-entries $kbid)
      (if (== $entries ()) (default-concept-prior-confidence)
         (let (concept-prior-confidence $_kbid $c) (car-atom $entries) $c))))

(: kb-expr-kbid (-> $expression (| $kb (List $none))))
(= (kb-expr-kbid $expr)
   (if (= $expr ($_type ($kbid $_ctx $_vars) $_prf $_tv)) $kbid ()))

(: observed-inheritance-subject? (-> $kb $subject Bool))
(= (observed-inheritance-subject? $kbid $subj)
   (not (== (collapse (once (match &inheritance_subject ($kbid $subj) true))) ())))

(: known-concept-node? (-> $kb $node Bool))
(= (known-concept-node? $kbid $node)
   (not (== (collapse (once (match &concept_node ($kbid $node) true))) ())))

(: concept-nodes ($kb -[det]-> (List $node)))
(= (concept-nodes $kbid)
   (list_to_set (collapse (match &concept_node ($kbid $node) $node))))

(: concept-node-prior-tv (-> $kb $node TV))
(= (concept-node-prior-tv $kbid $node)
   (if (known-concept-node? $kbid $node)
      (let $n (list-len (concept-nodes $kbid))
         (if (<= $n 0) no-evidence (STV (/ 1.0 $n) (kb-concept-prior-confidence $kbid))))
      no-evidence))

(: ConceptNodePriorFormula ($kb $node -[det]-> TV))
(= (ConceptNodePriorFormula $kbid $node) (concept-node-prior-tv $kbid $node))

(: resolve-base-rate-prior (-> $prior TV))
(= (resolve-base-rate-prior (ConceptNodePriorRuntime $kbid $node))
   (concept-node-prior-tv $kbid $node))
(= (resolve-base-rate-prior (STV $s $c)) (STV $s $c))
(= (resolve-base-rate-prior no-evidence) no-evidence)

(: WeightedBaseRateWithPriorTv (-> BaseRateEvidenceWithPriorState TV))
(= (WeightedBaseRateWithPriorTv (BaseRateEvidenceWithPrior $prior $ev))
   (BaseRateWithPriorFormula
      (resolve-base-rate-prior $prior)
      (WeightedBaseRateTv $ev)))

(: member-inheritance-tv (-> $kb BaseRateEvidenceState TV))
(= (member-inheritance-tv $kbid $ev)
   (let $universe-size (kb-universe-size $kbid)
      (if (== $universe-size no-universe-size)
         (WeightedCountBaseRateTv $ev)
         (WeightedUniverseBaseRateTv
            (the Number $universe-size) $ev))))

;; Keep an empty fold live so later sample proofs can refine it, but do not let
;; its provisional no-evidence value become a public Inheritance proof.
(: MemberInheritanceEvidenceFormula (-> TV TV))
(= (MemberInheritanceEvidenceFormula $tv)
   (if (== $tv no-evidence) (empty) $tv))

(: inheritance-subject-prior-tv (-> $kb $subject TV))
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
   (let $hits (collapse (premises-expected-confidence (copy_term $args)))
      (if (== $hits ()) ()
         (kb-add-atom $backend rule_expected ($id (car-atom $hits))))))

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
   (-> KbBackend Number $conclusion (| Bool (List $none))))
(= (register-rule-name! $backend $id $ccls)
   (if (= $ccls ($_type $_kb $prf $_tv))
      (if (is-var $prf) ()
         (let $name (rule-evidence-head $prf)
            (if (is-var $name) ()
               (if (is-expr $name) ()
                  (kb-add-atom $backend rule_name_index ($name $id))))))
      ()))

(: kb-add-expr
   (KbBackend $compiled-expression -[nondet]-> (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($rule-args (the (List Expression) $args))
          ($id (next-rule-id $backend))
           ($_1 (fold-flat (kb-add-prem $backend $id) 0 $rule-args))
           ($_2 (kb-add-atom $backend ccls_index ($ccls $id)))
           ($_3 (kb-add-ccl-head-index $backend $id $ccls))
           ($_4 (kb-add-atom $backend rules ($id $ccls $rule-args)))
           ($_expected (store-rule-expected-score! $backend $id $rule-args))
           ($_name-idx (register-rule-name! $backend $id $ccls))
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

(: inject-compiled-adds ((List $compiled-add) -[nondet]-> (List $none)))
(= (inject-compiled-adds $adds) (if (= $adds ()) () (foreach-flat (kb-add-expr temp) $adds)))

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
         (match rules ($id $ccls $args)
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
                ($_row (remove-atom rules ($id $ccls $args))))
               ())))
      ()))

(: remove-kb-facts-named! (-> $statement-name (List $none)))
(= (remove-kb-facts-named! $name)
   (let $_
      (collapse
         (match &forward_frontier
            ($hash $type $kb ($type $kb $name $tv) $ev)
            (let*
               (($_remove
                   (remove-atom &forward_frontier
                      ($hash $type $kb ($type $kb $name $tv) $ev)))
                ($key ($kb $type))
                ($change (forward-refresh-output-key! $key))
                ($_forward-state
                   (forward-apply-unqueued-change! $change))
                ($_base-rates
                   (invalidate-computed-base-rates!
                      (kb-expr-kbid ($type $kb $name $tv))))
                ($_member-inheritance
                   (if (= ($type $kb $name $tv)
                          ((Member $obj $class) ($kbid MAIN Nil) $_prf $_tv))
                      (forward-remove-member-inheritances-for-key
                         $kbid $obj $class)
                      ())))
               ())))
      ()))

(: remove-compiled-statement (-> $statement-name (List $none)))
(= (remove-compiled-statement $name)
   (let*
      (($_specialization (remove-specialization-state! $name))
       ($_facts (remove-kb-facts-named! $name))
       ($ids (list_to_set (collapse (match rule_name_index ($name $id) $id))))
       ($_rules (foreach-flat remove-rule-row! $ids))
       ($_index (if (== $ids ()) () (remove-atom rule_name_index ($name $_any)))))
      ()))
