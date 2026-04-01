(= (normalize-proof-output-atom-kind $term $pid)
   (if (= $term ($type ($kbid $_ctx $_vars) $_prf $tv))
      ($type ($kbid $_ctx $_vars) (proof-ref $pid) $tv)
      $term))
(= (proof-output-atom-kind (leaf $term) $pid)
   (normalize-proof-output-atom-kind $term $pid))
(= (proof-output-atom-kind (rule $_rule-id $term) $pid)
   (normalize-proof-output-atom-kind $term $pid))

(= (proof-output-atom $pid) (match &proof ($pid $_gid $output $_kind $_score $_ev $_children) $output))

(= (materialize-proof-refs $term)
   (if (= $term (proof-ref $pid)) (materialize-proof-refs (materialize-proof $pid))
      (if (is-expr $term)
         (cons (materialize-proof-refs (car-atom $term)) (map-flat materialize-proof-refs (cdr-atom $term)))
         $term)))

(= (materialize-result-atom $atom)
   (if (= $atom ($type $kb $prf $tv)) ($type $kb (materialize-proof-refs $prf) $tv) $atom))

(= (materialize-proof-kind (leaf $raw) $_pid)
   (if (= $raw (CPU $_fun $_args $_res)) cpu
      (if (= $raw ($_type ($_kbid $_ctx $_vars) $prf $_tv)) $prf $raw)))
(= (materialize-proof-kind (rule $_rule-id ($_type $_kb $prf $_tv)) $_pid)
   (cons rule-proof
      (cons (materialize-proof-refs (car-atom $prf))
         (map-flat materialize-proof-refs (cdr-atom $prf)))))
(= (materialize-proof-kind (rule $_rule-id $term) $_pid) $term)

(= (materialize-proof $pid)
   (match &proof ($pid $_gid $_output $kind $_score $_ev $_children)
      (materialize-proof-kind $kind $pid)))

(= (goal-results $gid)
   (let $pids (collapse (match &proof ($pid $gid $_output $_kind $_score $_ev $_children) $pid))
      (if (goal-has-type-vars? (goal-term-by-id $gid))
         (map-flat materialize-result-atom (map-flat proof-output-atom $pids))
         (case $pids (
              (() ())
              ((cons $pid $rest)
                 (let $merged
                    (fold-flat (|-> ($acc $next-pid) (merge-proof-atoms $acc (proof-output-atom $next-pid)))
                       (proof-output-atom $pid)
                       $rest)
                    (if (== $merged ()) () ((materialize-result-atom $merged))))))))))

(= (leaf-evidence-for-result $result)
   (if (= $result ($type ($kbid $_ctx $_vars) $prf $_tv))
      (if (contains-hash? $type) () ((fact-ev ($kbid $_ctx $_vars) $prf $type)))
      ()))

(= (proof-overlap-dominates-score? $old-ev $old-score $new-ev $new-score)
   (and (evidence-sets-overlap? $old-ev $new-ev)
      (or (> $old-score $new-score) (and (== $old-score $new-score) (evidence-subset? $new-ev $old-ev)))))

(= (goal-proof-candidate-step $ev $score false $_oldpid) false)
(= (goal-proof-candidate-step $ev $score true $oldpid)
   (let ($old-score $old-ev) (proof-stats-by-id $oldpid)
      (if (proof-overlap-dominates-score? $old-ev $old-score $ev $score) false true)))

(= (classify-goal-proof-candidate $gid $ev $score)
   (fold-flat (goal-proof-candidate-step $ev $score)
      true
      (collapse (match &proof ($oldpid $gid $_output $_kind $_score $_ev1 $_children) $oldpid))))

(= (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
   (let*
      (($pid (next-pid))
        ($output (proof-output-atom-kind $kind $pid))
        ($_1 (add-atom &proof ($pid $gid $output $kind $score $ev $children))))
      $pid))

(= (proof-atom-candidate ($type $kb $prf $tv) $ev)
   (proof-candidate (leaf ($type $kb $prf $tv))
      (term-confidence ($type $kb $prf $tv))
      $ev
      ()))

(= (leaf-result-candidate $result $ev)
   (if (= $result ($type $_kb $_prf $_tv)) (proof-atom-candidate $result $ev)
      (proof-candidate (leaf $result)
         (term-confidence $result)
         $ev
         ())))

(= (proof-depends-on-goal-seen? $pid $gid $seen-pids)
   (if (is-member $pid $seen-pids) false
      (or (== (match &proof ($pid $proof-gid $_output $_kind $_score $_ev $_children) $proof-gid) $gid)
         (fold-flat
            (|-> ($acc $child-pid)
               (or $acc (proof-depends-on-goal-seen? $child-pid $gid (cons $pid $seen-pids))))
            false
            (match &proof ($pid $_proof-gid $_output $_kind $_score $_ev $kids)
               $kids)))))

(= (candidate-is-cyclic? $gid ()) false)
(= (candidate-is-cyclic? $gid (cons $pid $pids))
   (or (proof-depends-on-goal-seen? $pid $gid ()) (candidate-is-cyclic? $gid $pids)))

(=
   (commit-proof-candidate-heap $agenda
      $gid
      $accepted
      (proof-candidate $kind
         $score
         $ev
         $children))
   (if (== $accepted false) $agenda
      (if (candidate-is-cyclic? $gid $children) $agenda
         (let $pid (store-proof-candidate $gid (proof-candidate $kind $score $ev $children))
            (fold-flat (|-> ($acc $waiter) (advance-frontier-waiter-heap $acc $waiter $pid))
               $agenda
               (collapse (match &goal_waiter ($gid $waiter) $waiter)))))))

(= (commit-proof-candidate $gid $accepted (proof-candidate $kind $score $ev $children))
   (if (== $accepted false) ()
      (let $_
         (commit-proof-candidate-heap (empty_heap)
            $gid
            $accepted
            (proof-candidate $kind
               $score
               $ev
               $children))
         ())))
