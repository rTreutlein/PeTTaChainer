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
(= (kb-add-atom live $space $expr) (add-space-atom! $space $expr))
(= (kb-add-atom backward $space $expr) (add-space-atom! $space $expr))
(= (kb-add-atom temp $space $expr)
   (let*
      (($term (Predicate (cons $space $expr)))
       ($_ (callPredicate (Predicate (assertz $term $ref)))))
      (add-atom &temp_query_ref (clause_ref $ref))))

;; The &kb_prefix and &kb_open rows of a fact (runtime/kb_index.metta).
(: kb-index-fact! (-[det]-> KbBackend Atom Atom))
(= (kb-index-fact! $backend ($type $kbctx $proof $tv))
   (let* (($fact (data $type $kbctx $proof $tv))
          ($_rows (map-flat (kb-index-row! $backend &kb_prefix $fact) (kb-fact-prefix-hashes $type))))
      (if (== (extract-vars $type) ()) ()
         (let $_open (kb-index-row! $backend &kb_open $fact (kb-fact-open-hash $type)) ()))))

(: kb-index-row! (-[det]-> KbBackend $space Atom Number Bool))
(= (kb-index-row! $backend $space $fact $hash)
   (kb-add-atom $backend $space (brand SpaceAtom (cons-atom $hash $fact))))

(: kb-unindex-fact! (-[det]-> Atom Atom))
(= (kb-unindex-fact! ($type $kbctx $proof $tv))
   (let $_rows (map-flat (kb-remove-prefix-row! (data $type $kbctx $proof $tv)) (kb-fact-prefix-hashes $type))
      (if (== (extract-vars $type) ()) ()
         (let* (($hash (kb-fact-open-hash $type))
                ($_open (remove-atom &kb_open ($hash $type $kbctx $proof $tv))))
            ()))))

(: kb-remove-prefix-row! (-[det]-> Atom Number Bool))
(= (kb-remove-prefix-row! ($type $kbctx $proof $tv) $hash)
   (remove-atom &kb_prefix ($hash $type $kbctx $proof $tv)))

;; A rule premise is indexed by its statement's head (prem_index, which a
;; forward run reads) and, unless its head is a variable, in &prem_prefix by the
;; longest ground prefix of its statement within its KB, so the rules a ground
;; key is a premise of are found by hashing the key's prefixes
;; (statement-prefix-keys) instead of walking every premise with its head.
(: &prem_prefix (SpaceOf (Number (| Goal (Statement KBContext Proof TV)) Number Number)))
!(bind! &prem_prefix (new-space))

;; The &prem_prefix keys of a statement's prefixes in a KB, its head alone first.
(: statement-prefix-keys (-[det]-> Atom Statement (List Number)))
(= (statement-prefix-keys $kbid $type)
   (map-flat (prefix-key $kbid)
      (cons (index-hash (if (is-expr $type) (car-atom $type) $type)) (statement-prefix-hashes $type))))

(: prefix-key (-[det]-> Atom Number Number))
(= (prefix-key $kbid $hash) (index-hash (quote ($kbid $hash))))

;; Fold sources wake forward rules without becoming extra evidential premises.
;; Slots are opened on a fresh local binder: matching a witness binds only the
;; outer variables shared with the fold and its rule conclusion.
(: existential-fold-source (-[nondet]-> Atom SkPattern))
(= (existential-fold-source $premise)
   (case $premise (
      ((CPU $fun $args $_res)
         (if (if (== $fun FoldAllCompiled) true (== $fun GroupedFoldAllCompiled))
            (let $pattern (car-atom (cdr-atom $args))
               (if (head-is? $pattern ExistentialAlternatives)
                  (let* (((ExistentialAlternatives $claim $_channel) $pattern)
                         ($scope (car-atom $args))
                         ((Exists $_binder $body) (existential-source $claim))
                         ($sources (cons $claim (implication-side-conjuncts (brand Statement $body))))
                         ($source (superpose $sources)))
                     (assemble-stored-runtime-fact $source $scope $_proof $_tv))
                  (empty)))
            (empty)))
      ($_other (empty)))))

(: kb-add-prem
   (-[det]-> KbBackend Number Number
       (| Goal (Statement KBContext Proof TV))
       Number))
(= (kb-add-prem $backend $id $idx $prem)
   (progn
      (case $prem (
         (($type ($kbid $_ctx $_vars) $_prf $_tv)
            (let $_head
               (once
                  (kb-add-atom $backend prem_index
                     (make-space-row4
                        (forward-type-trigger-key
                           (brand KB $kbid) (brand Statement $type))
                        $prem $id $idx)))
               (if (if (is-var $type) true (if (is-expr $type) (is-var (car-atom $type)) false)) ()
                  (let $key
                     (prefix-key $kbid
                        (case (statement-prefix-hashes $type) (
                           (() (index-hash (if (is-expr $type) (car-atom $type) $type)))
                           ((cons $longest $_shorter) $longest))))
                     (once (kb-add-atom $backend &prem_prefix (brand SpaceAtom (data $key $prem $id $idx))))))))
         ($_cpu
            (collapse (let ($fold-type ($fold-kb $fold-ctx $fold-vars) $fold-prf $fold-tv)
                  (existential-fold-source $prem)
               (kb-add-atom $backend prem_index
                  (make-space-row4
                     (forward-type-trigger-key (brand KB $fold-kb) (brand Statement $fold-type))
                     (data $fold-type ($fold-kb $fold-ctx $fold-vars) $fold-prf $fold-tv) $id $idx)))))))
      (+ $idx 1)))

;; Keep an empty fold live so later sample proofs can refine it, but do not let
;; its provisional no-evidence value become a public Inheritance proof.
(: MemberInheritanceEvidenceFormula (-[nondet]-> TV  TV))
(= (MemberInheritanceEvidenceFormula $tv)
   (if (== $tv no-evidence) (empty) $tv))

(: inheritance-subject-prior-tv (-[det]-> KB Statement TV))
(= (inheritance-subject-prior-tv $kbid $subj)
   (if (space-row-present? &inheritance_subject ($kbid $subj))
      (let $scale (fa-mass-scale $kbid)
         (if (== $scale 0.0) no-evidence (STV $scale 1.0)))
      no-evidence))

;; A rule's expected premise confidence is a pure function of its premise
;; structure and stored TVs, so it is computed once here instead of on every
;; rule-goal expansion. No entry (the computation can fail on exotic premise
;; shapes) scores the rule 1.0 (sk-rule-score).
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

(: register-truth-premise! (-[det]-> Number (| Goal (Statement KBContext Proof TV)) Atom))
(= (register-truth-premise! $id $premise)
   (case $premise (
      ((CPU $_fun $_args $_res) ())
      (($type $kbctx $_prf $_tv)
         (if (if (is-expr $type) (== (car-atom $type) RuleTruth) false)
            (let* (($hash (index-hash (sk-key $type $kbctx)))
                   ($_row (add-atom &sk_rule_truth ($id $hash $type $kbctx))))
               ())
            ())))))

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
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (if (if (head-is? $type Inheritance) (= $type (Inheritance $subj $concept)) false)
            (if (is-var $subj) ()
               (let* (($typed-kb (brand KB $kbid))
                      ($typed-subj (brand Statement $subj))
                      ($_subject (if $record-subject? (record-kb-node! &inheritance_subject subject-node $typed-kb $typed-subj) ())))
                  (record-inheritance-nodes! $typed-kb $typed-subj (brand Statement $concept))))
            ()))
      ($_other ()))))

;; A certain fact of a ground statement two or more forward rules conclude is
;; an outcome the combination modes learn from; it waits for the first merge
;; that needs its predicate's mode (docs/metta/combination_modes.md).
(: &combination_pending (SpaceOf (Number Atom Atom (Statement KBContext Proof TV))))
!(bind! &combination_pending (new-space))

(: note-combination-outcome! (-[det]-> (Statement KBContext Proof TV) Atom))
(= (note-combination-outcome! $fact)
   (case $fact (
      (($type ($kb MAIN Nil) $_proof (STV $_s $c))
         (if (if (>= $c 1.0) (if (is-expr $type) (== (extract-vars $type) ()) false) false)
            (case (list_to_set (collapse (match ccls_index (($type ($kb MAIN Nil) (by $rule $_premise) $_tv) $_id $_args) $rule))) (
               ((cons $_first (cons $_second $_more))
                  (let* (($head (car-atom $type))
                         ($hash (index-hash (quote ($kb $head))))
                         ($_row (add-atom &combination_pending ($hash $kb $head $fact))))
                     ()))
               ($_fewer ())))
            ()))
      ($_other ()))))

(: kb-add-expr
   (-[nondet]-> KbBackend RuntimeAddition  (| Bool (List $none))))
(= (kb-add-expr $backend $expr)
   (if (= $expr (rules ($args |- $ccls)))
      (let*
         (($typed-ccls (typed-runtime-fact $ccls))
          ($rule-args (context-rule-premises $typed-ccls (typed-runtime-premises $args)))
          ;; Temp (per-query) rule ids are offset so they can never collide
          ;; with live ones: both counters start at 0 and both backends'
          ;; rules/rule_expected/prem_index rows share the same spaces.
          ($id
             (if (== $backend temp)
                (+ 1000000000 (next-search-id bwd_tmp_ruleid))
                (next-search-id ruleid)))
           ($_context (context-note-rule! $id $typed-ccls))
           ($_functional (functional-rule! $typed-ccls))
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
           ;; A refined rule reads its truth goal first (rule-truth-premises); the
           ;; rule's search score follows that goal's value.
           ($_truth (case (copy_term $rule-args) (
              ((cons $truth-first $_truth-rest) (register-truth-premise! $id $truth-first))
              (() ()))))
           ($_name-idx
              (register-rule-name! $backend $id $typed-ccls))
           ($_journal (sk-note-rule! $id $typed-ccls))
           ($_aggregates
              (register-forward-aggregate-premises!
                 (== $backend live) $rule-args)))
         ())
      (let $fact
         (typed-runtime-fact $expr)
         (if (== $backend live)
            (if (kb-fact-present? $fact) ()
               (let*
                  ((($type $kb $_prf $_tv) $fact)
                   ($_functional (functional-fact! $fact))
                   ($_add (chainer-add-atom &kb $fact))
                   ($_index (kb-index-fact! live $fact))
                   ($_journal (sk-note-fact! $type $kb))
                   ($_nodes (record-fact-inheritance-nodes! $fact true))
                   ($_outcome (note-combination-outcome! $fact)))
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
      (rule-dormancy-forget-temp!)
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

;; A rule row and its index rows; returns the KB it belonged to.
(: remove-rule-row! (-[det]-> Number (List KB)))
(= (remove-rule-row! $id)
   (collapse
      (match rules
         (runtime-rule-row $id $ccls $args)
         (let*
            (($_retired (withdraw-rule! $id))
             ($_prems
                (remove-atom prem_index ($_pkey $_prem $id $_pidx)))
             ($_prefixes
                (remove-atom &prem_prefix ($_prefix $_pprem $id $_ppidx)))
             ($_ccls-idx
                (remove-atom ccls_index ($ccls $id $_prems2)))
             ($_expected
                (remove-atom rule_expected ($id $_score)))
             (($_type ($kbid $_ctx $_vars) $_prf $_tv) $ccls)
             ($_row
                (remove-atom rules
                   (runtime-rule-row $id $ccls $args))))
            (brand KB $kbid)))))

;; The rule rows registered under a statement name leave the rule indexes, so
;; their durable joins and views are retired by identity too. Returns
;; the KBs they belonged to.
(: withdraw-named-rules! (-[det]-> Proof (List KB)))
(= (withdraw-named-rules! $name)
   (let* (($ids (list_to_set (collapse (match rule_name_index ($name $id) (the Number $id)))))
          ($kbs (list_to_set (fold-flat (|-> ($acc $id) (append-flat $acc (remove-rule-row! $id))) () $ids)))
          ($_index (collapse (remove-atom rule_name_index ($name $_any))))
          ($_copies (foreach-flat sk-retire-store! (withdrawn-stores! $ids)))
          ($_inputs (foreach-flat sk-input-changed! $kbs)))
      $kbs))

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
       ($_rules (foreach-flat invalidate-computed-base-rates! (withdraw-named-rules! $name))))
      ()))
