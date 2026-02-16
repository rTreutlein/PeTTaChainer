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
(= (normalize-expected-tv $tv)
   (if (= $tv (STV $s $c))
       (STV (if (is-var $s) 1.0 $s)
            (if (is-var $c) 1.0 $c))
       $tv))

(= (normalize-expected-args ($a $b))
   ((normalize-expected-tv $a) (normalize-expected-tv $b)))

(= (premise-expected-confidence $prem)
   (case $prem
     (
       ((CPU $fun $args $_out)
         (if (is-member $fun (() MpFormula AndFormula OrFormula LikelierThanFormula))
              (let* (($res (reduce (reduce (cons $fun (normalize-expected-args $args)))))
                     ($c (tv-confidence $res)))
                (if (is-var $c) 1.0 $c))
              1.0))
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
(= (premises-expected-confidence ($prem $rest))
   (min (premise-expected-confidence $prem) (premises-expected-confidence $rest)))

;; Build queue items from rule matches for a goal.
(= (rule-candidate-items $max-score $cont $goal)
   (match &kb (rules ($args |- $goal))
      (let* (($score (min $max-score (premises-expected-confidence $args))))
        (qitem $score (cand ($args |- $goal) $score $cont) $goal))))

(= (direct-goal-items $steps $max-score $cont $goal)
   (let* (($proof (if (= $goal (CPU $fun $args $_res))
                        (CPU $fun $args (cpu-call $steps $fun $args))
                        (match &kb $goal $goal)))
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


(= (premise-goal-keys $args)
   (case $args
     (
       (() ())
       (Nil ())
       (((: $_kb $_prf $type $_tv) $rest)
        (cons $type (premise-goal-keys $rest)))
       (($prem $rest)
        (premise-goal-keys $rest))
     )))

(= (list-overlaps? () $_ys) false)
(= (list-overlaps? (cons $x $xs) $ys)
   (if (is-member $x $ys)
       true
       (list-overlaps? $xs $ys)))

(= (has-active-premise? $args $goal $cont)
   (list-overlaps? (premise-goal-keys $args) (active-goal-keys $goal $cont)))

(= (state-enqueue-item (state $pq $goals) $item)
   (case $item
     (
       ((qitem $_prio (cand (Nil |- $proved-goal) $_score (cons $frame $rest-cont)) $_g)
        (state-resume-frame (state $pq $goals) $proved-goal $frame $rest-cont))
       ((qitem $_prio (cand (Nil |- $goal) $_score ()) $_g)
        (state $pq (append $goals (cons $goal ()))))
       ((qitem $prio (cand ($args |- $goal) $_score $cont) $_g)
        (if (has-active-premise? $args $goal $cont)
            (state $pq $goals)
            (state (add_to_heap $pq (- 0 $prio) $item) $goals)))
       ($other
        (state $pq $goals))
     )))

(= (state-resume-frame $state $proved-goal (frame $proved-goal $rest $goal $parent-score) $cont)
   (let* (($prem-score (min (proof-confidence $proved-goal) (premise-expected-confidence $proved-goal)))
          ($new-score (min $parent-score $prem-score)))
     (state-enqueue-item $state (qitem $new-score (cand ($rest |- $goal) $new-score $cont) $goal))))

(= (enqueue-goal-state $steps $state $max-score $cont $goal)
   (let* (($direct-items (collapse (direct-goal-items $steps $max-score $cont $goal)))
          ($rule-items (collapse (rule-candidate-items $max-score $cont $goal))))
     (fold-flat state-enqueue-item $state (append $direct-items $rule-items))))

;; Best-first over partially-applied rule candidates.
(= (search-rules $steps $heap)
   (if (or (== (heap_size $heap) 0) (<= $steps 0))
       ()
       (let* (($pq-rest (get_from_heap $heap $_priority $item))
               ((qitem $_prio (cand (($prem $rest) |- $goal) $score $cont) $_g) $item)
               ($frame (frame $prem $rest $goal $score))
               ((state $new-pq $ready-goals)
                (enqueue-goal-state $steps (state $pq-rest ()) $score (cons $frame $cont) $prem)))
          (if (or (== $ready-goals ()) (== $ready-goals Nil))
              (search-rules $steps $new-pq)
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
   (let (state $pq $ready-goals) (enqueue-goal-state $steps (state (empty_heap) ()) 1.0 () $goal)
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

(= (inject-compiled-adds $adds)
   (if (= $adds ())
       $_
       (let $sadds (superpose $adds)
            (add-atom &kb $sadds))))

;; Execute a precompiled query plan represented as (goal + adds).
(= (run-compiled-query $steps $compiled-query)
   (let* (((cons (goal $query) $adds) $compiled-query)
          ($_ (inject-compiled-adds $adds)))
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

(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb))
   (let* (($c (min $ca $cb)))
     (if (> $sa $sb)
         (STV $sa $c)
         (STV $sb $c))))


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
  (let $atoms (mm2compile $kb $stmt) (add-atom &kb $atoms)))

;; Compile query to goal+adds, inject adds, then run goal through chainer.
(= (query $steps $kb $stmt)
  (let* (((cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt)))
         ($_ (inject-compiled-adds $adds))
         ($res (chainer $steps $query)))
    (pretty (superpose $res))))
