;; Rule lookup, contextualization, premise filtering, and expansion.
(: RuleGoalMatch
   (Alias
      (Number
       (List (| Goal (Statement KBContext Proof TV)))
       (| Goal (Statement KBContext Proof TV))
       Number)))

(: RuleIndexMatch
   (Alias
      ((| Goal (Statement KBContext Proof TV))
       Number
       (List (| Goal (Statement KBContext Proof TV))))))
(: ccls-index-occurs-matches
   (-[det]-> Atom (List RuleIndexMatch)))
(: rule-lookup-needs-occurs-check
   (-[det]-> Atom Bool))
;; Preserve the complete conclusion shape during lookup. SWI's deep JIT index
;; can then discriminate connective children (And, Or, configured compounds)
;; and ordinary predicate arguments instead of enumerating every rule sharing
;; only the outer head. Linear goals unify through ccls_index directly,
;; including variable-headed rules. A goal that repeats a variable unifies
;; under an occurs check: an exists witness term embeds the variable it
;; witnesses for, so (Father $x (exists r 0 ($y $x))) against a projection
;; rule concluding (Father (exists r2 0 ($s $_)) $s) would otherwise build a
;; rational tree, and every later walk of the goal key diverges.
(: rule-goal-view
   (-[nondet]-> (| Goal (Statement KBContext Proof TV))
      Number RuleGoalMatch))
(= (rule-goal-view $goal $parent-gid)
   (case $goal (
      ((CPU $_fun $_args $_result)
         (empty))
      (($_type $_kbctx $_proof $_tv)
         (let $lookup-goal
            (copy_term
               (data $_type $_kbctx $_proof $_tv))
            (if (rule-lookup-needs-occurs-check $lookup-goal)
               ;; superpose takes a literal tuple, so bind the match list first.
               (let $matches (ccls-index-occurs-matches $lookup-goal)
                  (let ($matched-goal $rule-id $args) (superpose $matches)
                     (if (= $matched-goal $goal)
                        (data (stored-number $rule-id)
                           (contextualize-rule-args $goal
                              (the (List (| Goal (Statement KBContext Proof TV)))
                                 $args))
                           $goal
                           $parent-gid)
                        (empty))))
               (match ccls_index
                  ($lookup-goal $rule-id $args)
                  (if (= $lookup-goal $goal)
                     (data $rule-id
                        (contextualize-rule-args $goal $args)
                        $goal
                        $parent-gid)
                     (empty)))))))))

(: context-vars-in-type?
   ;; KBContext is an erased newtype, so its destructured variables field is a
   ;; raw wire value here: Nil or a variable list.
   (-[det]-> Atom Atom Bool))
(: any-context-var-in?
   (-[det]-> (List Variable) (List Variable) Bool))
(= (any-context-var-in? $_type-vars ()) false)
(= (any-context-var-in? $type-vars (cons $var $rest))
   (or (stored-list-member? $var $type-vars)
      (any-context-var-in? $type-vars $rest)))
(= (context-vars-in-type? $type $vars)
   (if (== $vars Nil) false
      (let $type-vars
         (extract-vars $type)
         (any-context-var-in?
            $type-vars
            (the (List Variable) $vars)))))

(: contextualize-rule-premise
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))
       (| Goal (Statement KBContext Proof TV))))
(= (contextualize-rule-premise $premise
      ($_goal-type ($kbid $ctx $vars) $_goal-prf $_goal-tv))
   (let $typed-kbid (brand KB $kbid)
      (once
         (case $premise (
            (($type ($kbid $prem-ctx $prem-vars) $prf $tv)
            (if
               (and (== $prem-ctx MAIN)
                  (and (not (== $ctx MAIN))
                     (context-vars-in-type? $type $vars)))
               (let $fact-kb
                  (make-kb-context
                     $typed-kbid $ctx $vars)
                  (assemble-stored-runtime-fact
                     $type $fact-kb $prf $tv))
               (let $fact-kb
                  (make-kb-context
                     $typed-kbid $prem-ctx $prem-vars)
                  (assemble-stored-runtime-fact
                     $type $fact-kb $prf $tv))))
            ((CPU $fun $args $res) (CPU $fun $args $res)))))))

(: contextualize-rule-args
   (-[det]-> (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       (List (| Goal (Statement KBContext Proof TV)))))
(= (contextualize-rule-args $_goal ()) ())
(= (contextualize-rule-args $goal (cons $premise $rest))
   (cons (contextualize-rule-premise $premise $goal)
      (contextualize-rule-args $goal $rest)))

(: expand-rule-goal-heap
   (-[semidet]-> (Heap AgendaEntry) Number
       (| Goal (Statement KBContext Proof TV))
       (Heap AgendaEntry)))
;; Generated reverse rules are pruned once per expansion, after the matches
;; are collected: the structural scan is free and the current-proof probe runs
;; only when one of them matched (see generated-reverse-rule-needed?).
(: generated-rule-match-present? (-[det]-> (List RuleGoalMatch) Bool))
(= (generated-rule-match-present? ()) false)
(= (generated-rule-match-present? (cons ($_rule-id $_premises ($_type $_kb $proof $_tv) $_gid) $rest))
   (if (generated-reverse-rule-proof? (brand Proof $proof)) true (generated-rule-match-present? $rest)))
(: needed-rule-matches (-[semidet]-> (List Evidence) (List RuleGoalMatch) (List RuleGoalMatch)))
(= (needed-rule-matches $_incumbent-evidence ()) ())
(= (needed-rule-matches $incumbent-evidence (cons $match $rest))
   (let ($_rule-id $premises ($_type $_kb $proof $_tv) $_gid) $match
      (if (if (generated-reverse-rule-proof? (brand Proof $proof))
             (reverse-rule-premises-current?
                (inverted-rule-proof? (brand Proof $proof)) $incumbent-evidence $premises)
             true)
         (cons $match (needed-rule-matches $incumbent-evidence $rest))
         (needed-rule-matches $incumbent-evidence $rest))))
(: prune-generated-rule-matches (-[semidet]-> Number (List RuleGoalMatch) (List RuleGoalMatch)))
(= (prune-generated-rule-matches $parent-gid $matches)
   (if (generated-rule-match-present? $matches)
      (let $pids (current-proof-ids-for-goal-key (proof-goal-key-by-goal-id $parent-gid))
         (if (proof-list-has-direct-leaf? $pids)
            (needed-rule-matches (proof-evidence $pids) $matches)
            $matches))
      $matches))
(= (expand-rule-goal-heap $agenda $parent-gid $goal)
   (proof-fold-flat-semidet expand-rule-goal-fold
      $agenda
      (prune-generated-rule-matches $parent-gid
         (collapse (rule-goal-view $goal $parent-gid)))))

;; Cached expected score, computed at rule-add time (store-rule-expected-score!).
;; The cache assumes the goal's TV slot is unbound (the value depends only on
;; premise structure and stored TVs then); a goal queried with a known TV falls
;; back to computing against the bound bundle, as before.
(: inheritance-lift-rule-goal?
   (-[det]-> (| Goal
          (Statement KBContext Proof TV))
       Bool))
(= (inheritance-lift-rule-goal? $goal)
   (case $goal (
      (($_type $_kb ((inheritance-rule-lift $_rule) $_source $_instance) $_tv)
         true)
      ($_other false))))

(: rule-expected-score
   (-[det]-> Number
       (| Goal (Statement KBContext Proof TV))
       (List (| Goal (Statement KBContext Proof TV)))
       Number))
(= (rule-expected-score $rule-id $goal $args)
   ;; A specialized lift is a completeness bridge for evidence that cannot
   ;; execute directly in the hypothetical context. Native implication views
   ;; must be allowed to finish before that bridge closes the parent goal.
   (if (inheritance-lift-rule-goal? $goal) 0.000001
      (if
         (case $goal (
            (($_gtype $_gkb $_gprf $gtv) (is-var $gtv))
            ($_other false)))
         (let $hits (collapse (match rule_expected ($rule-id $score) $score))
            (if (== $hits ())
               (premises-expected-confidence (copy_term $args))
               (the Number (car-atom $hits))))
         (premises-expected-confidence (copy_term $args)))))

;; Walk a copy of a candidate rule's premise list before any frontier state is
;; created. Ground deterministic CPU premises are evaluated eagerly (binding
;; e.g. computed step variables for later premises). A fully ground atom
;; premise prunes the rule when no fact matches it and no rule can conclude its
;; head. In KBs where every premise head is also some rule's conclusion the
;; filter never prunes, so search degrades to the unfiltered walk.

(: prefilter-head-concludable?
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (prefilter-head-concludable? $prem)
   (case $prem (
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (let $lookup-type (copy_term $type)
            (let $hits
               (collapse
                  (once
                     (match ccls_index
                        (($lookup-type
                           ($kbid $_stored-ctx $_stored-vars)
                           $_stored-proof $_stored-tv)
                         $_rule-id $_stored-args)
                        true)))
               (if (== $hits ()) false true))))
      ;; A malformed/non-fact premise must never make the prefilter prune a rule.
      ($_other true))))

(: prefilter-fact-missing?
   (-[det]-> (Statement KBContext Proof TV) Bool))
(= (prefilter-fact-missing? ($type ($kbid $_ctx $_vars) $_prf $_tv))
   (== (collapse (once (match &kb ($type ($kbid $_c2 $_v2) $_p2 $_t2) true))) ()))

;; CPU functions the filter must not run eagerly: aggregate folds have their own
;; search machinery and store-scanning formulas are too costly for a filter.
(: prefilter-cpu-opaque? (-[det]-> $function Bool))
(= (prefilter-cpu-opaque? $fun)
   (or (aggregate-fold-function? $fun)
       (== $fun ConceptNodePriorFormula)))

(: prefilter-premise-blocks?
   (-[det]-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (prefilter-premise-blocks? $premise)
   (once
      (case $premise (
         ((CPU $fun $args $res)
            (if (prefilter-cpu-opaque? $fun) false
               ;; Only run a CPU premise eagerly when its argument list is fully
               ;; ground. Building an ($fun ...) expression here would apply it
               ;; to unevaluated arguments.
               (if
                  (and (not (is-var $fun))
                     (== (extract-vars $args) ()))
                  (let $hits (collapse (cpu-call 0 $fun $args))
                     (if (== $hits ()) true
                        (if (= $res (car-atom $hits)) false true)))
                  false)))
         (($type ($kbid $ctx $vars) $prf $tv)
            (let*
               (($fact-kb
                   (make-kb-context
                      $kbid $ctx $vars))
                ($fact
                   (assemble-stored-runtime-fact
                      $type $fact-kb $prf $tv)))
               (if (== (extract-vars $type) ())
                  (if (prefilter-fact-missing? $fact)
                     (if (prefilter-head-concludable? $fact) false true)
                     false)
                  false)))))))

(: prefilter-prunes-walk
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Bool))
(= (prefilter-prunes-walk ()) false)
(= (prefilter-prunes-walk (cons $prem $rest))
   (if (prefilter-premise-blocks? $prem) true (prefilter-prunes-walk $rest)))

;; The walk runs on a copy (eager CPU evaluation binds variables) inside a
;; collapse so a premise shape neither clause covers makes the walk yield
;; nothing and the rule is kept, never dropped.
(: rule-premise-prefilter-prunes?
   (-[det]-> (List (| Goal (Statement KBContext Proof TV))) Bool))
(= (rule-premise-prefilter-prunes? $args)
   (let $hits (collapse (prefilter-prunes-walk (copy_term $args)))
      (if (== $hits ()) false (car-atom $hits))))

(: expand-rule-goal-fold
   (-[semidet]-> (Heap AgendaEntry) RuleGoalMatch
       (Heap AgendaEntry)))
(= (expand-rule-goal-fold $agenda ($rule-id $args $goal $parent-gid))
   (if (rule-premise-prefilter-prunes? $args) $agenda
      (let*
         (($expected-score
             (rule-expected-score $rule-id $goal $args))
          ($bundle (copy_term (and-bundle $goal $args))))
         (spawn-frontier-heap $agenda
            $parent-gid
            $bundle
            1.0
            ()
            ()
            0
            (frontier-value-spec
               $expected-score
               (list-len $args)
               (premises-proof-success-prior $args))))))
