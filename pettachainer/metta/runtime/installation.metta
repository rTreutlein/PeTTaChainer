;; Compiled knowledge installation and ingestion policy.

(: kb-add-prem (-[det]-> KbBackend Number Number (| Goal (Statement KBContext Proof TV)) Number))
(= (kb-add-prem $backend $id $idx $prem)
   (progn
      (case $prem (
         (($type ($kbid $_ctx $_vars) $_prf $_tv)
            (let $_head
               (once
                  (kb-add-atom $backend prem_index
                     (make-space-row4
                        (forward-type-trigger-key (brand KB $kbid) (brand Statement $type))
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

(: note-combination-outcome! (-[det]-> (Statement KBContext Proof TV) Atom))
(= (note-combination-outcome! $fact)
   (case $fact (
      (($type ($kb MAIN Nil) $_proof (STV $_s $c))
         (if (if (>= $c 1.0) (if (is-expr $type) (== (extract-vars $type) ()) false) false)
            (let* (($scope (data $kb MAIN Nil))
                   ($applications (application-values $type $scope)))
               (case (list_to_set (collapse
                      (let (application-value $_type $_ctx $rule $_premise $_tv $_args) (superpose $applications) $rule))) (
               ((cons $_first (cons $_second $_more))
                  (let* (($head (car-atom $type))
                         ($hash (index-hash (quote ($kb $head))))
                         ($_row (add-atom &combination_pending ($hash $kb $head $fact))))
                     ()))
               ($_fewer ()))))
            ()))
      ($_other ()))))

;; The positive-only population priors a rule's premises read.
(: positive-only-prior-read (-[det]-> (List Atom) Atom (List Atom)))
(= (positive-only-prior-read $reads $premise)
   (case $premise (
      ((CPU ReadRate ($kb $pattern $_raw $_plan true) $_read)
         (if (positive-only-pattern? (brand KB $kb) (brand Statement $pattern)) (cons (data $kb $pattern) $reads) $reads))
      ($_other $reads))))

(: kb-add-expr (-[nondet]-> KbBackend RuntimeAddition (| Bool (List $none))))
(= (kb-add-expr $backend $addition)
   (let* ((($info $expr) (prepare-source-addition $addition))
          ((source-info $_source $role $_priors $_parents $_recipe) $info))
   (if (= $expr (rules ($args |- $ccls)))
      (case (fold-flat positive-only-prior-read () (the (List Atom) $args)) (
         (() (let $_id (once (kb-add-rule! $backend $info $args $ccls)) ()))
         ((cons ($gated-kb $gated-pattern) $_more)
            (kb-add-gated-rule! $backend $info (brand KB $gated-kb) (brand Statement $gated-pattern) $args $ccls))))
      (let $fact
         (typed-runtime-fact $expr)
         (if (== $backend live)
            (if (kb-fact-present? $fact) ()
               (let*
                  ((($type $kb $_prf $_tv) $fact)
                   ($_functional (functional-fact! $fact))
                   ($_published (kb-publish-fact! live $role $fact))
                   ($_journal (sk-note-fact! $type $kb))
                   ($_outcome (note-combination-outcome! $fact))
                   ;; Count the stored statement immediately, independently of forward runs.
                   ($_aggregates (case (stored-statement-candidate $type $kb false) (
                     ((forward-derived $merged $_ev) (forward-maintain-aggregates! aggregate-update $merged))
                     (no-forward-output-candidate ())))))
                  true))
            (kb-publish-fact! $backend $role $fact))))))

(: kb-add-rule! (-[nondet]-> KbBackend Atom Atom Atom Number))
(= (kb-add-rule! $backend $info $args $ccls)
   (let*
      (($typed-ccls (typed-runtime-fact $ccls))
       ((source-info $_source $_role $_priors $_parents $recipe) $info)
       ($rule-args (context-rule-premises $typed-ccls (typed-runtime-premises $args)))
       (($_type $_scope $prf $_tv) $typed-ccls)
       ($name (rule-evidence-head $prf))
       ($named (if (is-var $name) false (rule-name? $name))))
      (case (if (== $backend live)
               (if $named
                  (collapse (once (match rule_name_index ($name $existing)
                     (match rules (runtime-rule-row $existing $stored-ccls $stored-args)
                        (if (rule-live? (the Number $existing))
                           (if (=alpha (quote ($stored-ccls $stored-args)) (quote ($typed-ccls $rule-args)))
                              (the Number $existing) (empty)) (empty)))))) ()) ()) (
         ((cons $found $_rest) (the Number $found))
         (() (let*
               (($id
                  (if (== $backend temp)
                      (+ 1000000000 (next-search-id bwd_tmp_ruleid))
                      (let $fresh (fresh-rule-id (search-id-value ruleid))
                         (progn (change-state! ruleid (+ $fresh 1)) $fresh))))
                ($_proof (proof-template! $id $typed-ccls $rule-args))
                ($_catalog (source-catalog-rule! $backend $id $info $typed-ccls))
                ($_recipe (if (== $recipe no-completion) true
                   (kb-add-atom $backend &completion_recipe (brand SpaceAtom (data $id $recipe)))))
                ($_context (context-note-rule! $id $typed-ccls))
                ($_functional (functional-rule! $typed-ccls))
                ($_1 (if (== $backend backward) 0 (fold-flat (kb-add-prem $backend $id) 0 $rule-args)))
                ($_2 (kb-add-atom $backend ccls_index (make-space-row3 $typed-ccls $id $rule-args)))
                ($_3
                   (kb-add-atom $backend rules
                      (brand SpaceAtom (runtime-rule-row $id $typed-ccls $rule-args))))
                ;; Expected premise confidence is fixed per compiled rule.
                ($_expected (let $hits (collapse (premises-expected-confidence (copy_term $rule-args)))
                   (if (== $hits ()) () (once (kb-add-atom $backend rule_expected (make-space-pair $id (car-atom $hits)))))))
                ($_truth (case (copy_term $rule-args) (
                   ((cons (CPU $_fun $_args $_res) $_cpu-rest) ())
                   ((cons ($truth-type $truth-ctx $_truth-proof $_truth-tv) $_truth-rest)
                      (if (head-is? $truth-type RuleTruth)
                         (let $hash (index-hash (sk-key $truth-type $truth-ctx))
                            (add-atom &sk_rule_truth ($id $hash $truth-type $truth-ctx))) ()))
                   ($_no-truth ()))))
                ($_name-idx (if $named (once (kb-add-atom $backend rule_name_index (make-space-pair $name $id))) ()))
                ($_journal (sk-note-rule! $id $typed-ccls))
                ($_aggregates (register-forward-aggregate-premises! (== $backend live) $rule-args)))
               $id))))))

(: kb-add-gated-rule! (-[semidet]-> KbBackend Atom KB Statement Atom Atom (List $none)))
(= (kb-add-gated-rule! $backend $info $kb $pattern $args $ccls)
   (let $user (user-base-rate? $kb $pattern)
      (if (== $backend temp)
         (if $user (let $_id (once (kb-add-rule! temp $info $args $ccls)) ()) ())
         (let* ((($_type $_kbctx $prf $_tv) (typed-runtime-fact $ccls))
                ($hash (base-rate-cache-hash $kb $pattern))
                ($name (rule-evidence-head $prf)))
            (if (== (collapse (once (match &prior_gated_rules
                     ($hash $kb $_pattern $name $backend $_info $stored-args $stored-ccls)
                     (if (=alpha (quote ($stored-ccls $stored-args)) (quote ($ccls $args))) true (empty))))) ())
               (let $_row (add-atom &prior_gated_rules ($hash $kb $pattern $name $backend $info $args $ccls))
                  (if $user (prior-gated-add! $hash $kb $pattern $name $backend $info $args $ccls) ())) ())))))

(: prior-gated-add! (-[semidet]-> Number KB Statement Proof KbBackend Atom Atom Atom (List $none)))
(= (prior-gated-add! $hash $kb $pattern $name $backend $info $args $ccls)
   (let* (($id (once (kb-add-rule! $backend $info $args $ccls)))
          ($_live (add-atom &prior_gated_live ($hash $kb $pattern $name $id))))
      ()))

;; Adds the rows reading a newly set rate, or withdraws those of a cleared one.
(: prior-gated-rate-changed! (-[det]-> KB Statement (List $none)))
(= (prior-gated-rate-changed! $kb $pattern)
   (let $hash (base-rate-cache-hash $kb $pattern)
      (if (user-base-rate? $kb $pattern)
         (if (== (collapse (once (match &prior_gated_live ($hash $kb $stored $name $id)
                   (if (=alpha $stored $pattern) true (empty))))) ())
            (let $_added (collapse (match &prior_gated_rules ($hash $kb $stored $name $backend $info $args $ccls)
                  (if (=alpha $stored $pattern) (prior-gated-add! $hash $kb $stored $name $backend $info $args $ccls) (empty))))
               ())
            ())
         (let $_withdrawn
               (withdraw-rule-ids! (collapse (match &prior_gated_live ($hash $kb $stored $name $id)
                  (if (=alpha $stored $pattern)
                     (let $_row (remove-variant-row! &prior_gated_live (quote ($hash $kb $stored $name $id))) $id)
                     (empty)))))
            ()))))

(: inject-compiled-adds (-[nondet]-> (List RuntimeAddition) (List $none)))
(= (inject-compiled-adds $adds) (foreach-flat (kb-add-expr temp) $adds))

;; --- Rule withdrawal by name -----------------------------------------------
;; A rule row and its index rows; returns the KB it belonged to.
(: remove-rule-row! (-[det]-> Number (List KB)))
(= (remove-rule-row! $id)
   (collapse
      (match rules
         (runtime-rule-row $id $ccls $args)
         (let*
            (($_catalog (source-catalog-remove! $id))
             ($_retired (withdraw-rule! $id))
             ($_prems (remove-atom prem_index ($_pkey $_prem $id $_pidx)))
             ($_prefixes (remove-atom &prem_prefix ($_prefix $_pprem $id $_ppidx)))
             ($_ccls-idx (remove-atom ccls_index ($ccls $id $_prems2)))
             ($_expected (remove-atom rule_expected ($id $_score)))
             ($_recipe (remove-atom &completion_recipe ($id $_plan)))
             (($_type ($kbid $_ctx $_vars) $_prf $_tv) $ccls)
             ($_row (remove-atom rules (runtime-rule-row $id $ccls $args))))
            (brand KB $kbid)))))

;; Rule rows leave the rule indexes, their durable joins and views are
;; retired by identity too, and their KBs' inputs change. Returns those KBs.
(: withdraw-rule-ids! (-[det]-> (List Number) (List KB)))
(= (withdraw-rule-ids! $ids)
   (let* (($kbs (list_to_set (fold-flat (|-> ($acc $id) (append-flat $acc (remove-rule-row! $id))) () $ids)))
          ($_copies (foreach-flat sk-retire-store! (withdrawn-stores! $ids)))
          ($_inputs (foreach-flat sk-input-changed! $kbs)))
      $kbs))

;; The rule rows registered under a statement name, with its gated rows and its
;; specialization state (#114): its templates, so no later fact grounds it, and
;; its grounded markers.
;; Re-adding the withdrawn rule exactly as it was installs it again, so it
;; derives once more; another value under its name is rejected (#113).
(: withdraw-named-rules! (-[det]-> Proof (List KB)))
(= (withdraw-named-rules! $name)
   (let* (($kbs (withdraw-rule-ids! (list_to_set (collapse (match rule_name_index ($name $id) (the Number $id))))))
          ($_index (collapse (remove-atom rule_name_index ($name $_any))))
          ($_gated (remove-data-rows! &prior_gated_rules (quote ($_h $_k $_p $name $_b $_info $_a $_c))))
          ($_live (remove-data-rows! &prior_gated_live (quote ($_lh $_lk $_lp $name $_lid))))
          ($_rule-templates (remove-data-rows! &spec_template
             (quote ($_rh (specialization-template-row $_rk $_rhead $_rtriggers (compile-specialization $_rparams $_rprior (: $name $_rtype $_rtv)))))))
          ($_done (remove-data-rows! &spec_done (quote ($_dh (specialization-done-row $_dk (compile-specialization $_dparams $_dprior (: $name $_dtype $_dtv))))))))
      $kbs))
