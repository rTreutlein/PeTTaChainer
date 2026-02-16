!(import! &self compile)
!(import! &self (library lib_import))
!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))

;;;;;;;;;;;;;;;;;;
;; Chainer Core ;;
;;;;;;;;;;;;;;;;;;

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

;; Build initial queue from all matching rule applications.
(= (candidate-from-match* $max-score $cont ($args |- $goal))
   (let* (($score (min $max-score (premises-expected-confidence $args))))
     (qitem $score (cand ($args |- $goal) $score $cont) $goal)))

(= (initial-candidate* $max-score $cont $goal)
   (match &kb (rules ($args |- $goal))
      (candidate-from-match* $max-score $cont ($args |- $goal))))

(= (direct-goal-items $steps $max-score $cont (CPU $fun $args $_res))
   (let* (($res (cpu-call $steps $fun $args))
          ($proof (CPU $fun $args $res))
          ($score (min $max-score (proof-confidence $proof))))
     (qitem $score (cand (Nil |- $proof) $score $cont) $proof)))

(= (direct-goal-items $steps $max-score $cont $goal)
   (let* (($proof (match &kb $goal $goal))
          ($score (min $max-score (proof-confidence $proof))))
     (qitem $score (cand (Nil |- $proof) $score $cont) $proof)))

(= (cont-goal-keys $cont)
   (case $cont
     (
       (() ())
       (Nil ())
       ((cons (frame $_prem $_rest (: $_kb $_prf $type $_tv) $_parent-score) $tail)
        (cons $type (cont-goal-keys $tail)))
     )))

(= (active-goal-keys (: $_kb $_prf $type $_tv) $cont)
   (cons $type (cont-goal-keys $cont)))


(= (premise-goal-keys-one $prem)
   (case $prem
     (
       ((: $_kb $_prf $type $_tv)
        (cons $type ()))
       ($other
        ())
     )))

(= (premise-goal-keys $args)
   (case $args
     (
       (() ())
       (Nil ())
       (($prem $rest)
        (append (premise-goal-keys-one $prem) (premise-goal-keys $rest)))
     )))

(= (has-any-member () $_active) false)
(= (has-any-member (cons $k $ks) $active)
   (if (is-member $k $active)
       true
       (has-any-member $ks $active)))

(= (has-active-premise? $args $goal $cont)
   (has-any-member (premise-goal-keys $args) (active-goal-keys $goal $cont)))

(= (state-enqueue-item (state $pq $goals) $item)
   (case $item
     (
       ((qitem $_prio (cand (Nil |- $proved-goal) $_score (cons $frame $rest-cont)) $_g)
        (state-resume-frame (state $pq $goals) $proved-goal $frame $rest-cont))
       ((qitem $_prio (cand (Nil |- $goal) $_score ()) $_g)
        (state $pq (append $goals (cons $goal ()))))
       ((qitem $_prio (cand ($args |- $goal) $_score $cont) $_g)
        (if (has-active-premise? $args $goal $cont)
            (trace! (hpq loop-skip $goal $args) (state $pq $goals))
            (state (hpq-insert $pq $item) $goals)))
       ($other
        (state (hpq-insert $pq $item) $goals))
     )))

(= (state-enqueue-items $state ()) $state)
(= (state-enqueue-items $state (cons $item $tail))
   (state-enqueue-items (state-enqueue-item $state $item) $tail))

(= (state-resume-frame $state $proved-goal (frame $prem $rest $goal $parent-score) $cont)
   (let* (($prem $proved-goal)
          ($prem-score (min (proof-confidence $proved-goal) (premise-expected-confidence $prem)))
          ($new-score (min $parent-score $prem-score)))
     (state-enqueue-item $state (qitem $new-score (cand ($rest |- $goal) $new-score $cont) $goal))))

(= (enqueue-goal-state $steps $state $max-score $cont $goal)
   (let* (($direct-items (collapse (direct-goal-items $steps $max-score $cont $goal)))
          ($state1 (state-enqueue-items $state $direct-items))
          ($rule-items (collapse (initial-candidate* $max-score $cont $goal))))
     (state-enqueue-items $state1 $rule-items)))

(= (hpq-insert (hpq $heap) $item)
   (trace! (hpq push $item (heap_size $heap))
        (let (qitem $prio $_args $_goal) $item
             (hpq (add_to_heap $heap (- 0 $prio) $item)))))

(= (hpq-insert-all $pq ()) $pq)
(= (hpq-insert-all $pq (cons $item $tail))
   (hpq-insert-all (hpq-insert $pq $item) $tail))

(= (hpq-pop (hpq $heap))
   (if (== (heap_size $heap) 0)
       ()
       (let $rest-heap (get_from_heap $heap $_priority $item)
            (trace! (hpq pop $item (heap_size $rest-heap))
                 ($item (hpq $rest-heap))))))

;; Best-first over partially-applied rule candidates.
(= (search-rules $steps (hpq $heap))
   (if (or (== (heap_size $heap) 0) (<= $steps 0))
       ()
       (let* ((($item $pq-rest) (hpq-pop (hpq $heap)))
              ((qitem $_prio (cand (($prem $rest) |- $goal) $score $cont) $_g) $item)
              ($frame (frame $prem $rest $goal $score))
              ((state $new-pq $ready-goals)
               (enqueue-goal-state $steps (state $pq-rest ()) $score (cons $frame $cont) $prem)))
         (if (== $ready-goals ())
             (search-rules (- $steps 1) $new-pq)
             (append $ready-goals (search-rules (- $steps 1) $new-pq))))))

;; CPU functions that need the current step budget as first argument.
(= (cpu-needs-steps $fun) (== $fun FoldAllFormulaCompiled))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $steps $fun $args)
  (let $call
       (if (cpu-needs-steps $fun)
           (cons $fun (cons $steps $args))
           (cons $fun $args))
       (reduce (reduce $call))))

(= (chainer $steps $goal)
   (let (state $pq $ready-goals) (enqueue-goal-state $steps (state (hpq (empty_heap)) ()) 1.0 () $goal)
        (append $ready-goals (search-rules $steps $pq))))

;;;;;;;;;;;;;;;;;;
;; CPU Formulas ;;
;;;;;;;;;;;;;;;;;;

;; Runtime fold helper.
(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (let* (($call (cons $fun (cons $acc (cons $elem ()))))
          ($nacc (reduce (reduce $call))))
     (foldall-eval $fun $nacc $tail)))

;; Execute a precompiled query plan represented as (goal + adds).
(= (run-compiled-query $steps $compiled-query)
   (let* (((cons (goal $query) $adds) $compiled-query)
          ($_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))))
     (chainer $steps $query)))

;; FoldAll runtime uses precompiled query, then extracts fold values via pattern match.
(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
  (let $matches (collapse (let (: $kbr $prf $pattern $tvin) (run-compiled-query $steps $compiled-query) $value))
       (foldall-eval $fun $init $matches)))

;;;;;;;;;;;;;;;;;;;;;
;; Truth Functions ;;
;;;;;;;;;;;;;;;;;;;;;

(= (MpFormula (STV $abs $abc) (STV $as $ac))
   (STV (* $abs $as) (min $abc $ac)))
(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (let* (($sb (min $si $sa))
          ($cb (min $ci $ca)))
     (STV $sb $cb)))

(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (let* (($sb (min $si $sa))
          ($cb (max $ci $ca)))
     (STV $sb $cb)))

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
  (let* (((cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt)))
         ($_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds))))
         ($res (chainer $steps $query)))
    (pretty (superpose $res))))
