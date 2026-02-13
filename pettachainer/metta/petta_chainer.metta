!(import! &self compile)
!(import! &self (library lib_import))
!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))

;;;;;;;;;;;;;;;;;;
;; Chainer Core ;;
;;;;;;;;;;;;;;;;;;

;; Normalize variable names out of a goal key so renamed variants are treated as same state.
(= (goal-key (: $kb $prf $type $tv)) $type)

;; Confidence helpers.
(= (tv-confidence $tv)
   (if (= $tv (STV $_s $c))
       (if (is-var $c) 1.0 $c)
       1.0))

;; Rule-native expected confidence extraction from compiled premises.
(= (premise-expected-confidence $prem)
   (case $prem
     (
       ((CPU MpFormula ((STV $_ms $mc) $_mrhs) $_mout)
        (if (is-var $mc) 1.0 $mc))
       ((CPU AndFormula ($aa $ab) $_aout)
        (min (tv-confidence $aa) (tv-confidence $ab)))
       ((CPU OrFormula ($oa $ob) $_oout)
        (max (tv-confidence $oa) (tv-confidence $ob)))
       ((CPU LikelierThanFormula ($la $lb) $_lout)
        (min (tv-confidence $la) (tv-confidence $lb)))
       ((: $_kb $_prf $_type $tv)
        (tv-confidence $tv))
       ($other 1.0)
     )))

;; Confidence from a concrete proved premise (deterministic).
(= (proof-confidence $proof)
   (case $proof
     (
       ((: $_kb $_prf $_type $tv)
        (tv-confidence $tv))
       ((CPU $_fun $_args $res)
        (tv-confidence $res))
       ($other 1.0)
     )))

(= (premises-expected-confidence Nil) 1.0)
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence ($prem $rest))
   (min (premise-expected-confidence $prem) (premises-expected-confidence $rest)))

;; Priority queue key used for deduplication.
(= (qitem-key (qitem $prio $args $goal))
   (qkey $goal $prio $args))

(= (is-inversion-proof $prf)
   (if (is-var $prf)
       false
       (if (= $prf ((inverted $_name with $_a $_b $_c $_d) $_ctx))
           true
           false)))

;; Build initial queue from all matching rule applications.
(= (candidate-from-match* $max-score $cont ($args |- $goal))
   (let (: $_kb $prf $_type $_tv) $goal
        (if (is-inversion-proof $prf)
            (empty)
            (let $score (min $max-score (premises-expected-confidence $args))
                 (qitem $score (cand ($args |- $goal) $score $cont) $goal)))))

(= (initial-candidate* $max-score $cont $goal)
   (let $_ (match &kb (rules ($args |- $goal)) (rules ($args |- $goal)))
        (candidate-from-match* $max-score $cont ($args |- $goal))))

(= (build-initial-pq* $pq $max-score $cont $goal)
   (let $items (collapse (initial-candidate* $max-score $cont $goal))
        (hpq-insert-all $pq $items)))

(= (direct-goal-items $steps $max-score $cont (CPU $fun $args $_res))
   (if (<= $steps 0)
       (empty)
       (let $res (cpu-call (- $steps 1) $fun $args)
            (let $proof (CPU $fun $args $res)
                 (let $score (min $max-score (proof-confidence $proof))
                      (qitem $score (cand (Nil |- $proof) $score $cont) $proof))))) )

(= (direct-goal-items $steps $max-score $cont $goal)
   (let $proof (match &kb $goal $goal)
        (let $score (min $max-score (proof-confidence $proof))
             (qitem $score (cand (Nil |- $proof) $score $cont) $proof))))

(= (enqueue-goal-items $steps $pq $max-score $cont $goal)
   (let $pq1 (hpq-insert-all $pq (collapse (direct-goal-items $steps $max-score $cont $goal)))
        (build-initial-pq* $pq1 $max-score $cont $goal)))

(= (qitem-priority-key (qitem $prio $_args $_goal))
   (- 0 $prio))

(= (hpq-empty)
   (hpq (empty_heap) ()))

(= (hpq-size (hpq $heap $_seen))
   (heap_size $heap))

(= (hpq-insert (hpq $heap $seen) $item)
   (let $key (qitem-key $item)
        (if (is-member $key $seen)
            (trace! (hpq skip $item (hpq-size (hpq $heap $seen))) (hpq $heap $seen))
            (trace! (hpq push $item (hpq-size (hpq $heap $seen)))
                 (hpq (add_to_heap $heap (qitem-priority-key $item) $item)
                      (cons $key $seen))))))

(= (hpq-insert-all $pq ()) $pq)
(= (hpq-insert-all $pq (cons $item $tail))
   (let $next-pq
        (case $item
          (
            ((qitem $_prio (cand (Nil |- $proved-goal) $_score (cons $frame $rest-cont)) $_g)
             (resume-frame $pq $proved-goal $frame $rest-cont))
            ($other
             (hpq-insert $pq $item))
          ))
        (hpq-insert-all $next-pq $tail)))

(= (hpq-pop (hpq $heap $seen))
   (if (== (heap_size $heap) 0)
       ()
       (let $rest-heap (get_from_heap $heap $_priority $item)
            (trace! (hpq pop $item (hpq-size (hpq $rest-heap $seen)))
                 ($item (hpq $rest-heap $seen))))))

(= (resume-frame $pq $proved-goal (frame $prem $rest $goal $parent-score) $cont)
   (let $prem $proved-goal
        (let $prem-score (min (proof-confidence $proved-goal) (premise-expected-confidence $prem))
             (let $new-score (min $parent-score $prem-score)
                  (hpq-insert-all $pq (cons (qitem $new-score (cand ($rest |- $goal) $new-score $cont) $goal) ()))))))

;; Best-first over partially-applied rule candidates.
(= (search-rules $steps $visited $pq)
   (if (and (== (hpq-size $pq) 0) (<= $steps 0))
       ()
       (let ($item $pq-rest) (hpq-pop $pq)
            (search-rules-step (- $steps 1) $visited $item $pq-rest))))

(= (search-rules-step $steps $visited (qitem $_prio (cand (Nil |- $goal) $_score ()) $_g) $pq-rest)
      (cons $goal (search-rules $steps $visited $pq-rest)))

(= (search-rules-step $steps $visited (qitem $_prio (cand (($prem $rest) |- $goal) $score $cont) $_g) $pq-rest)
       (let $frame (frame $prem $rest $goal $score)
            (let $new-pq (enqueue-goal-items $steps $pq-rest $score (cons $frame $cont) $prem)
                 (search-rules $steps $visited $new-pq))))

;; CPU functions that need the current step budget as first argument.
(= (cpu-needs-steps $fun) (== $fun FoldAllFormulaCompiled))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $steps $fun $args)
  (let $call
       (if (cpu-needs-steps $fun)
           (cons $fun (cons $steps $args))
           (cons $fun $args))
       (reduce (reduce $call))))

(= (chainer-v $steps $visited $pq $goal)
   (let $k (goal-key $goal)
       (if (or (<= $steps 0) (is-member $k $visited))
           (empty)
           (let $pq2 (enqueue-goal-items $steps $pq 1.0 () $goal)
                (search-rules $steps (cons $k $visited) $pq2)
))))

(= (chainer $steps $goal) (chainer-v $steps () (hpq-empty) $goal))

;;;;;;;;;;;;;;;;;;
;; CPU Formulas ;;
;;;;;;;;;;;;;;;;;;

;; Runtime fold helper.
(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
  (let $call (cons $fun (cons $acc (cons $elem ())))
  (let $nacc (reduce (reduce $call))
       (foldall-eval $fun $nacc $tail))))

;; Execute a precompiled query plan represented as (goal + adds).
(= (run-compiled-query $steps $compiled-query)
  (let (cons (goal $query) $adds) $compiled-query
  (let $_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))
       (chainer $steps $query))))

;; FoldAll runtime uses precompiled query, then extracts fold values via pattern match.
(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
  (let $matches (collapse (let (: $kbr $prf $pattern $tvin) (run-compiled-query $steps $compiled-query) $value))
       (foldall-eval $fun $init $matches)))

;;;;;;;;;;;;;;;;;;;;;
;; Truth Functions ;;
;;;;;;;;;;;;;;;;;;;;;

(= (MpFormula (STV $abs $abc) (STV $as $ac))
   (STV (* $abs $as) (min $abc $ac)))
(= (AndFormula (STV $si $ci) (STV $sa $ca)) (let $sb (min $si $sa)
                                              (let $cb (min $ci $ca) (STV $sb $cb))))

(= (OrFormula (STV $si $ci) (STV $sa $ca)) (let $sb (min $si $sa)
                                             (let $cb (max $ci $ca) (STV $sb $cb))))

(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb)) (let $c (min $ca $cb) (if (> $sa $sb) (STV $sa $c) (STV $sb $c))))


(= (AndProjection (STV $s $c)) (STV $s $c))
(= (OrProjection (STV $s $c)) (STV $s $c))

(= (NotFormula (STV $s $c) (STV (- 1 $s) $c)))

(= (InversionFormula (STV $sa $ca) (STV $sb $cb) (STV $sab $cab)) (STV (/ (* $sb $sab) $sa) (min-atom ($ca $cb $cab)))) 

(= (Equal $a $b) (== $a $b))
(= (NotEqual $a $b) (not (== $a $b)))

;;;;;;;;;;;
;; API   ;;
;;;;;;;;;;;

(= (compileadd $kb $stmt)
  (let $atoms (traceid (mm2compile $kb $stmt)) (add-atom &kb $atoms)))

;; Compile query to goal+adds, inject adds, then run goal through chainer.
(= (query $steps $kb $stmt)
  (let (cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt))
  (let $_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))
       (let $res (chainer $steps $query) (pretty (superpose $res))))))
