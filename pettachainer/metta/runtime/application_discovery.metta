;; Shared application discovery for backward expansion, forward triggers and
;; late activation. Plans retain conclusion/premise variable sharing; no value
;; is published or scheduled here. Ground CPU guards retain their binding policy.

!(import_prolog_function nth0)
(: nth0 (-[nondet]-> $index (List $item) $item (List $item)))

(datatype SkeletonRuleDef (sk-rule-def SkFact (List SkPattern)))
(datatype SkeletonMatch (sk-match Number (List SkPattern) SkFact))
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
(: sk-context-search? (-[det]-> SkFact Bool))
(= (sk-context-search? ($_type ($kbid $ctx $_vars) $_proof $_tv))
   (if (== $ctx MAIN) (context-searching? $kbid) true))
(: sk-rule-goal (-[det]-> SkPattern SkPattern))
(= (sk-rule-goal $pattern)
   (case $pattern (
      ((CPU $_fun $_args $_result) $pattern)
      (($type $ctx $proof $tv)
         (if (head-is? $proof derived-implication)
            (assemble-stored-runtime-fact $type $ctx (brand Proof (by $rule $premise)) $tv)
            $pattern)))))
(: sk-rule-match (-[nondet]-> SkFact SkeletonMatch))
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
(: sk-judgment-main-rule-match (-[nondet]-> SkFact SkeletonMatch))
(= (sk-judgment-main-rule-match ($type ($kbid $ctx $vars) $proof $tv))
   (if (judgment-world-premise? $type (make-kb-context (brand KB $kbid) $ctx $vars))
      (let $lookup (copy_term (data $type (data $kbid MAIN Nil) $proof $tv))
         (match ccls_index ($lookup $id $args)
            (match rules (runtime-rule-row $id ($_type ($_kb $stored-ctx $_vars) $_prf $_tv) $_args)
               (if (if (== $stored-ctx MAIN) (sk-node-row? $_prf) false)
                  (if (= $lookup (data $type (data $kbid MAIN Nil) $proof $tv))
                     (let* (($scope (make-kb-context (brand KB $kbid) $ctx $vars))
                            ($goal (assemble-stored-runtime-fact $type $scope $proof $tv))
                            ($scoped (map-flat (sk-judgment-main-premise $scope) $args)))
                        ;; Matching a fixed node row may specialize an open
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
                          (make-kb-context (brand KB $kbid) $prem-ctx $prem-vars))))
               (assemble-stored-runtime-fact $type $fact-kb $prf $tv)))
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
         ;; A premise from another KB keeps its explicit context.
         ($_other-kb $premise)))))
(: contextualize-rule-args (-[semidet]-> SkFact (List SkPattern) (List SkPattern)))
(= (contextualize-rule-args $goal $args) (map-semidet (contextualize-rule-premise $goal) $args))
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
(: sk-premise-rules-step (-[det]-> Statement KBContext Number (List SkeletonMatch) (List SkeletonMatch)))
(= (sk-premise-rules-step $type $kbctx $prefix $found)
   (append-flat
      (collapse
         (let* ((($_pattern $id $idx) (match &prem_prefix ($prefix $pattern $id $idx) ($pattern $id $idx)))
                ((runtime-rule-row $id $ccls $prems) (match rules (runtime-rule-row $id $ccls $prems) (runtime-rule-row $id $ccls $prems)))
                ($_rest (nth0 $idx $prems (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))))
            (sk-match $id $prems $ccls)))
      $found))

;; Late activation preserves its unconstrained proof/TV matching policy.
(: discover-application (-[semidet]-> Number SkFact (List SkPattern) SkPattern SkeletonMatch))
(= (discover-application $id $ccls $args $node)
   (let (sk-rule-def $conclusion $premises) (copy_term (sk-rule-def $ccls $args))
      (if (case (copy_term $node) (
             ((CPU $_fun $_args $_res) false)
             (($type $kbctx $_proof $_tv)
                (= $conclusion (assemble-stored-runtime-fact $type $kbctx $_rule-proof $_rule-tv)))))
         (if (chainer-acyclic-term? $conclusion)
            (sk-match $id (contextualize-rule-args $conclusion $premises) $conclusion)
            (empty))
         (empty))))


(: discover-triggered-applications (-[nondet]-> SkeletonKey Atom SkeletonMatch))
(= (discover-triggered-applications (sk-key $type $kbctx) $trigger)
   (let* ((($pattern $id $idx) (match prem_index ($trigger $pattern $id $idx) ($pattern $id $idx)))
                ((runtime-rule-row $id $ccls $prems)
                   (match rules (runtime-rule-row $id $ccls $prems) (runtime-rule-row $id $ccls $prems)))
                ($premise (rule-premise (stored-number $idx) $prems))
                ($_matched
                   (case $premise (
                      ((CPU $_function $_args $_result)
                         (let* (($source (existential-fold-source $premise))
                                ($outer-vars (extract-vars $_args))
                                (($_out-type $kbctx $_out-proof $_out-tv) $ccls))
                            (if (= $source (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))
                               (if (existential-outer-values? $outer-vars) true (empty))
                               (empty))))
                      ;; Match the contextualized premise. Its read policy
                      ;; separates judgment support from executable seeds.
                      ($_fact
                         (if (= (contextualize-rule-premise $ccls $premise)
                                (assemble-stored-runtime-fact $type $kbctx $_proof $_tv))
                            true (empty)))))))
      (if (if (if (sk-context-search? $ccls) false (rule-dormant? $id)) false (chainer-acyclic-term? $ccls))
         (sk-match $id $prems $ccls) (empty))))


(: aggregate-fold-function? (-[det]-> $function Bool))
(= (aggregate-fold-function? $function)
   (stored-list-member? $function (FoldAllCompiled GroupedFoldAllCompiled CompoundRate)))


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
