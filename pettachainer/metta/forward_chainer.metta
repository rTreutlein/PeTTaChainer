!(import_prolog_function nth0)

(= (forward-agenda-dirty-key $kb) (atom_concat fwd_agenda_dirty_ $kb))
(= (forward-agenda-gen-key $kb) (atom_concat fwd_agenda_gen_ $kb))
(= (forward-agenda-scope-key $kb) (atom_concat fwd_agenda_scope_ $kb))
(= (forward-query-run-gen-key $kb) (atom_concat fwd_query_run_gen_ $kb))

(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

(= (forward-indexable-premise-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (forward-type-trigger-key $kbid $_type) ()))

(= (forward-premise-index-key $prem)
   (let $key (forward-indexable-premise-key $prem) (if (== $key ()) fwd_trigger_any $key)))

(= (forward-premise-wildcard-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (fwd_trigger $kbid any) fwd_trigger_any))

(= (forward-load-agenda $kb)
   (let $magenda (catch (get-state (atom_concat fwd_agenda_ $kb)))
      (if-error $magenda (empty_heap) $magenda)))

(= (forward-save-agenda $kb $agenda) (change-state! (atom_concat fwd_agenda_ $kb) $agenda))
(= (forward-set-agenda-dirty $kb $dirty) (change-state! (forward-agenda-dirty-key $kb) $dirty))

(= (forward-agenda-dirty? $kb)
   (let $mdirty (catch (get-state (forward-agenda-dirty-key $kb)))
      (if-error $mdirty true $mdirty)))

(= (forward-current-agenda-gen $kb)
   (let $mgen (catch (get-state (forward-agenda-gen-key $kb)))
      (if-error $mgen 0 $mgen)))

(= (forward-current-query-run-gen $kb)
   (let $mgen (catch (get-state (forward-query-run-gen-key $kb)))
      (if-error $mgen 0 $mgen)))

(= (forward-next-agenda-gen $kb)
   (let*
      (($gen (+ 1 (forward-current-agenda-gen $kb)))
        ($_ (change-state! (forward-agenda-gen-key $kb) $gen)))
      $gen))

(= (forward-next-query-run-gen $kb)
   (let*
      (($gen (+ 1 (forward-current-query-run-gen $kb)))
        ($_ (change-state! (forward-query-run-gen-key $kb) $gen)))
      $gen))

(= (forward-current-agenda-scope $kb)
   (let $mscope (catch (get-state (forward-agenda-scope-key $kb)))
      (if-error $mscope (kb $kb) $mscope)))

(= (forward-set-agenda-scope $kb $scope) (change-state! (forward-agenda-scope-key $kb) $scope))

(= (forward-new-query-scope $kb) (fwd_query_scope $kb (forward-next-query-run-gen $kb)))

(= (mark-forward-agenda-dirty $expr)
   (if (= $expr ($_type ($kbid MAIN Nil) $_prf $_tv))
      (forward-set-agenda-dirty $kbid true)
      ()))

(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))
(= (forward-fact-kb ($type ($kbid $_ctx $_vars) $_prf $_tv)) $kbid)

(= (forward-pending-state-key $fact)
   (let $kb (forward-fact-kb $fact)
      (atom_concat fwd_pending_ (term_hash ((forward-current-agenda-scope $kb) (forward-fact-key $fact))))))

(= (forward-pending-score-of $fact)
   (let*
      (($state-key (forward-pending-state-key $fact))
        ($gen (forward-current-agenda-gen (forward-fact-kb $fact)))
        ($entry (catch (get-state $state-key))))
      (if-error $entry
         0.0
         (if (= $entry (pending $stored-key $stored-gen $score))
            (if (and (== $stored-key (forward-fact-key $fact)) (== $stored-gen $gen)) $score 0.0)
            0.0))))

(= (clear-forward-pending-score $fact)
   (change-state!
      (forward-pending-state-key $fact)
      (pending () (forward-current-agenda-gen (forward-fact-kb $fact)) 0.0)))

(= (set-forward-pending-score $fact $score)
   (change-state!
      (forward-pending-state-key $fact)
      (pending (forward-fact-key $fact) (forward-current-agenda-gen (forward-fact-kb $fact)) $score)))

(= (forward-build-agenda $kb)
   (fold-flat
      agenda-push-fact-best
      (empty_heap)
      (collapse
         (match &kb ($type ($kb MAIN Nil) $prf $tv)
            ($type ($kb MAIN Nil) $prf $tv)))))

(= (forward-refresh-agenda $kb)
   (if (forward-agenda-dirty? $kb)
      (let*
         (($_gen (forward-next-agenda-gen $kb))
           ($agenda (forward-build-agenda $kb))
           ($_save (forward-save-agenda $kb $agenda))
           ($_clear-dirty (forward-set-agenda-dirty $kb false)))
         $agenda)
      (forward-load-agenda $kb)))

(= (forward-satisfy-premises $steps () $goal) $goal)
(= (forward-satisfy-premises $steps (cons $prem $rest) $goal)
   (if (= $prem (CPU $fun $args $res))
      (let $res (reduce (cpu-call $steps $fun $args)) (forward-satisfy-premises $steps $rest $goal))
      (if (= $prem ($_type ($_kbid $_ctx $_vars) $_prf $_tv))
         (match &kb $prem
            (forward-satisfy-premises $steps $rest $goal))
         (empty))))

(= (agenda-push-fact $agenda $fact)
   (let $score (term-confidence $fact) (add_to_heap $agenda (- 0 $score) (qitem $score $fact))))

(= (agenda-push-fact-best $agenda $fact)
   (let*
      (($score (term-confidence $fact))
        ($current (forward-pending-score-of $fact)))
      (if (>= $current $score) $agenda
         (let*
            (($nagenda (agenda-push-fact $agenda $fact))
              ($_set (set-forward-pending-score $fact $score)))
            $nagenda))))

(= (forward-build-agenda-from-facts $facts)
   (fold-flat agenda-push-fact-best (empty_heap) $facts))

(= (forward-fact-upsert $agenda (@ $fact ($type ($kbid $_ctx $_vars) $prf $tv)))
   (let*
      (($kb ($kbid $_ctx $_vars))
        ($hits (collapse (match &kb ($type $kb $prfo $tvo) ($type $kb $prfo $tvo))))
        ($_ (foreach-flat (|-> ($old-fact) (remove-atom &kb $old-fact)) $hits))
        ($merged-fact (fold-flat merge-proof-atoms $fact $hits))
        ($_ (chainer-add-atom &kb $merged-fact)))
      (if (== $hits ()) (agenda-push-fact-best $agenda $merged-fact) $agenda)))

(= (forward-rule-results-for-key $steps $kb $fact $key)
   (collapse
      (let*
         ((($id $idx) (match prem_index ($key $fact $id $idx) ($id $idx)))
           (($id $ccls $prems) (match rules ($id $ccls $prems) ($id $ccls $prems)))
           ($rprems (nth0 $idx $prems $fact)))
         (forward-satisfy-premises $steps $rprems $ccls))))

(= (forward-rule-results $steps $kb $fact)
   (let*
      (($key (forward-premise-index-key $fact))
        ($wildcard-key (forward-premise-wildcard-key $fact))
        ($direct (forward-rule-results-for-key $steps $kb $fact $key))
        ($wildcard
           (if (== $key $wildcard-key) (empty) (forward-rule-results-for-key $steps $kb $fact $wildcard-key))))
      (union-atom $direct $wildcard)))

(= (forward-step-fact $steps $kb $agenda $fact)
   (let*
      (($_clear (clear-forward-pending-score $fact))
        ($derived (forward-rule-results $steps $kb $fact))
        ($nagenda (fold-flat forward-fact-upsert $agenda $derived)))
      $nagenda))

(= (forward-loop $steps $kb $agenda)
   (if (or (== (heap_size $agenda) 0) (<= $steps 0)) $agenda
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $score $fact) $item
            (if (== (forward-pending-score-of $fact) $score)
               (let*
                  (($next-steps (- $steps 1))
                   ($nagenda (bounded-agenda-prune $next-steps (forward-step-fact $steps $kb $rest $fact))))
                  (forward-loop $next-steps $kb $nagenda))
               (forward-loop $steps $kb $rest))))))

(= (forward-target-type $target)
   (if (= $target (: $_name $type $_tv)) $type
      (if (= $target ($fact-type ($_kbid $_ctx $_vars) $_prf $_fact-tv)) $fact-type
         $target)))

(= (forward-select-fact $kb $target)
   (let*
      (($type (forward-target-type $target))
        ($matches
           (collapse
              (once
                 (match &kb ($type ($kb MAIN Nil) $prf $tv)
                    ($type ($kb MAIN Nil) $prf $tv))))))
      (if (== $matches ()) () (car-atom $matches))))

(= (forward-chain-from-facts $steps $kb $facts)
   (let*
      (($old-scope (forward-current-agenda-scope $kb))
        ($scope (forward-new-query-scope $kb))
        ($_scope (forward-set-agenda-scope $kb $scope))
        ($agenda (forward-build-agenda-from-facts $facts))
        ($_run (forward-loop $steps $kb $agenda))
        ($_dirty (forward-set-agenda-dirty $kb true))
        ($_restore (forward-set-agenda-scope $kb $old-scope)))
      true))

(= (forward-chain-from-fact $steps $kb $fact)
   (let*
      (($old-scope (forward-current-agenda-scope $kb))
        ($scope (forward-new-query-scope $kb))
        ($_scope (forward-set-agenda-scope $kb $scope))
        ($agenda (agenda-push-fact-best (empty_heap) $fact))
        ($_run (forward-loop $steps $kb $agenda))
        ($_dirty (forward-set-agenda-dirty $kb true))
        ($_restore (forward-set-agenda-scope $kb $old-scope)))
      true))

(= (forward-chain $steps $kb)
   (let*
      (($_scope (forward-set-agenda-scope $kb (kb $kb)))
        ($agenda (forward-refresh-agenda $kb))
        ($nagenda (forward-loop $steps $kb $agenda))
        ($_save (forward-save-agenda $kb $nagenda)))
      true))

(= (forward-chain-from $steps $kb $target)
   (let $fact (forward-select-fact $kb $target)
      (if (== $fact ()) false (forward-chain-from-fact $steps $kb $fact))))

(= (forward-has-derived? $kb $type) (not (== (collapse (match &kb ($type ($kb MAIN Nil) $prf $tv) $prf)) ())))
