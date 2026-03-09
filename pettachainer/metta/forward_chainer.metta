!(import_prolog_function nth0)

(= (forward-load-agenda $kb)
   (let $magenda (catch (get-state (atom_concat fwd_agenda_ $kb)))
      (if-error $magenda (empty_heap) $magenda)))

(= (forward-save-agenda $kb $agenda) (change-state! (atom_concat fwd_agenda_ $kb) $agenda))

(= (forward-register-added-expr $expr)
   (if (= $expr ($type ($kbid MAIN Nil) $prf $tv))
      (let*
         (($agenda (forward-load-agenda $kbid))
           ($nagenda (agenda-push-fact $agenda $expr))
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
                         ($nagenda (fold-flat agenda-push-fact-unique $agenda $matches))
                         ($_save (forward-save-agenda $kbid $nagenda)))
                       ())
                    ()))
              $args)))
      ()))

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

(= (agenda-has-fact? $agenda $fact)
   (if (== (heap_size $agenda) 0) false
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $_score $queued-fact) $item
            (or (=alpha $queued-fact $fact) (agenda-has-fact? $rest $fact))))))

(= (agenda-push-fact-unique $agenda $fact)
   (if (agenda-has-fact? $agenda $fact) $agenda (agenda-push-fact $agenda $fact)))

(= (forward-fact-upsert $agenda (@ $fact ($type ($kbid $_ctx $_vars) $prf $tv)))
   (let*
      (($kb ($kbid $_ctx $_vars))
        ($hits (collapse (match &kb ($type $kb $prfo $tvo) ($type $kb $prfo $tvo))))
        ($_ (foreach-flat (|-> ($old-fact) (remove-atom &kb $old-fact)) $hits))
        ($merged-fact (fold-flat merge-proof-atoms $fact $hits))
        ($_ (add-atom &kb $merged-fact)))
      (if (== $hits ()) (agenda-push-fact $agenda $merged-fact) $agenda)))

(= (forward-rule-results $steps $kb $fact)
   (collapse
      (let*
         (($id (match &prem_index ($fact $id $idx) $id))
           (($id $ccls $prems) (match &rules ($id $ccls $prems) ($id $ccls $prems)))
           ($rprems (nth0 $idx $prems $fact)))
         (forward-satisfy-premises $steps $rprems $ccls))))

(= (forward-loop $steps $kb $agenda)
   (if (or (== (heap_size $agenda) 0) (<= $steps 0)) $agenda
      (let $rest (get_from_heap $agenda $_priority $item)
         (let (qitem $_score $fact) $item
            (let*
               (($derived (forward-rule-results $steps $kb $fact))
                 ($nagenda (fold-flat forward-fact-upsert $rest $derived)))
               (forward-loop (- $steps 1) $kb $nagenda))))))

(= (forward-chain $steps $kb)
   (let*
      (($agenda (forward-load-agenda $kb))
        ($nagenda (forward-loop $steps $kb $agenda))
        ($_save (forward-save-agenda $kb $nagenda)))
      true))

(= (forward-has-derived? $kb $type) (not (== (collapse (match &kb ($type ($kb MAIN Nil) $prf $tv) $prf)) ())))
