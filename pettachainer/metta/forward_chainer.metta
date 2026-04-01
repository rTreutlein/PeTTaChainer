!(import_prolog_function nth0)

(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type)
            (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

(= (forward-indexable-premise-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv))
      (forward-type-trigger-key $kbid $_type)
      ()))

(= (forward-premise-index-key $prem)
   (let $key (forward-indexable-premise-key $prem)
      (if (== $key ()) fwd_trigger_any $key)))

(= (forward-premise-wildcard-key $prem)
   (if (= $prem ($_type ($kbid $_ctx $_vars) $_prf $_tv)) (fwd_trigger $kbid any)
      fwd_trigger_any))

(= (forward-load-agenda $kb)
   (let $magenda (catch (get-state (atom_concat fwd_agenda_ $kb)))
      (if-error $magenda (empty_heap) $magenda)))

(= (forward-save-agenda $kb $agenda)
   (change-state! (atom_concat fwd_agenda_ $kb) $agenda))

(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv)) (($kbid $ctx $vars) $type))

(= (forward-pending-state-key $fact)
   (atom_concat fwd_pending_ (term_hash (forward-fact-key $fact))))

(= (forward-pending-score-of $fact)
   (let*
      (($state-key (forward-pending-state-key $fact))
        ($entry (catch (get-state $state-key))))
      (if-error $entry
         0.0
         (if (= $entry (pending $stored-key $score))
            (if (== $stored-key (forward-fact-key $fact)) $score 0.0)
            0.0))))

(= (clear-forward-pending-score $fact)
   (change-state! (forward-pending-state-key $fact) (pending () 0.0)))

(= (set-forward-pending-score $fact $score)
   (change-state! (forward-pending-state-key $fact)
      (pending (forward-fact-key $fact) $score)))

(= (forward-register-added-expr $expr)
   (if (= $expr ($type ($kbid MAIN Nil) $prf $tv))
      (let*
         (($agenda (forward-load-agenda $kbid))
           ($nagenda (agenda-push-fact-best $agenda $expr))
           ($_save (forward-save-agenda $kbid $nagenda)))
         ())
      ()))

(= (forward-register-added-rule $args $_ccls)
   (let*
      (($_
           (foreach-flat
              (|-> ($prem)
                 (if (= $prem ($ptype ($kbid MAIN Nil) $_prf $_ptv))
                    (let*
                       (($agenda (forward-load-agenda $kbid))
                         ($matches
                            (collapse
                               (match &kb ($ptype ($kbid MAIN Nil) $prf $tv)
                                  ($ptype ($kbid MAIN Nil) $prf $tv))))
                         ($nagenda (fold-flat agenda-push-fact-best $agenda $matches))
                         ($_save (forward-save-agenda $kbid $nagenda)))
                       ())
                    ()))
              $args)))
      ()))

(= (forward-satisfy-premises $steps () $goal) $goal)
(= (forward-satisfy-premises $steps (cons $prem $rest) $goal)
   (if (= $prem (CPU $fun $args $res))
      (let $res (reduce (cpu-call $steps $fun $args))
         (forward-satisfy-premises $steps $rest $goal))
      (if (= $prem ($_type ($_kbid $_ctx $_vars) $_prf $_tv))
         (match &kb $prem
            (forward-satisfy-premises $steps $rest $goal))
         (empty))))

(= (agenda-push-fact $agenda $fact)
   (let $score (term-confidence $fact)
      (add_to_heap $agenda (- 0 $score) (qitem $score $fact))))

(= (agenda-push-fact-best $agenda $fact)
   (let*
      (($score (term-confidence $fact))
        ($current (forward-pending-score-of $fact)))
      (if (>= $current $score) $agenda
         (let*
            (($nagenda (agenda-push-fact $agenda $fact))
              ($_set (set-forward-pending-score $fact $score)))
            $nagenda))))

(= (forward-fact-upsert $agenda (@ $fact ($type ($kbid $_ctx $_vars) $prf $tv)))
   (let*
      (($kb ($kbid $_ctx $_vars))
        ($hits (collapse (match &kb ($type $kb $prfo $tvo) ($type $kb $prfo $tvo))))
        ($_ (foreach-flat (|-> ($old-fact) (remove-atom &kb $old-fact)) $hits))
        ($merged-fact (fold-flat merge-proof-atoms $fact $hits))
        ($_ (add-atom &kb $merged-fact)))
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
           (if (== $key $wildcard-key) (empty)
              (forward-rule-results-for-key $steps $kb $fact $wildcard-key))))
      (union-atom $direct $wildcard)))

(= (forward-loop $steps $kb $agenda)
   (if (or (== (heap_size $agenda) 0) (<= $steps 0)) $agenda
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $score $fact) $item
            (if (== (forward-pending-score-of $fact) $score)
               (let*
                  (($_clear (clear-forward-pending-score $fact))
                    ($derived (forward-rule-results $steps $kb $fact))
                    ($nagenda (fold-flat forward-fact-upsert $rest $derived)))
                  (forward-loop (- $steps 1) $kb $nagenda))
               (forward-loop $steps $kb $rest))))))

(= (forward-chain $steps $kb)
   (let*
      (($agenda (forward-load-agenda $kb))
        ($nagenda (forward-loop $steps $kb $agenda))
        ($_save (forward-save-agenda $kb $nagenda)))
      true))

(= (forward-has-derived? $kb $type)
   (not (== (collapse (match &kb ($type ($kb MAIN Nil) $prf $tv) $prf)) ())))
