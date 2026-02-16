!(import! &self compile)
!(import! &self (library lib_import))
!(use-module! heaps)
!(import_prolog_function (superpose (empty_heap add_to_heap get_from_heap heap_size)))

;;;;;;;;;;;;;;;;;;
;; Chainer Core ;;
;;;;;;;;;;;;;;;;;;

;; Confidence helpers.
(= (or-1.0 $x)
   (if (is-var $x) 1.0 $x))

(= (tv-confidence $tv)
   (if (= $tv (STV $_s $c))
       (or-1.0 $c)
       1.0))

;; Rule-native expected confidence extraction from compiled premises.
(= (normalize-expected-tv $tv)
   (if (= $tv (STV $s $c))
       (STV (or-1.0 $s)
            (or-1.0 $c))
       $tv))

(= (cpu-expected-confidence $fun $args)
   (if (is-member $fun (() MpFormula AndFormula OrFormula LikelierThanFormula))
       (let* ((($a $b) $args)
              ($res (reduce (reduce (cons $fun ((normalize-expected-tv $a) (normalize-expected-tv $b)))))))
         (tv-confidence $res))
       1.0))

;; Unified confidence extraction for both expected and concrete terms.
(= (term-confidence $term)
   (case $term
     (
        ((CPU $fun $args $res)
         (if (is-var $res)
             (cpu-expected-confidence $fun $args)
             (tv-confidence $res)))
        ((: $_kb $_prf $_type $tv)
         (tv-confidence $tv))
        ($other 1.0)
      )))

(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence (cons $prem $rest))
   (min (term-confidence $prem) (premises-expected-confidence $rest)))

;; Build queue items from rule matches for a goal.
(= (candidate-item $score $args $goal $cont)
   (qitem $score (cand ($args |- $goal) $cont)))

(= (rule-candidate-items $max-score $cont $goal)
   (match &kb (rules ($args |- $goal))
       (let $score (min $max-score (premises-expected-confidence $args))
            (candidate-item $score $args $goal $cont))))

(= (direct-goal-items $steps $max-score $cont $goal)
   (let* (($proof (if (= $goal (CPU $fun $args $_res))
                          (CPU $fun $args (cpu-call $steps $fun $args))
                          (match &kb $goal $goal)))
           ($score (min $max-score (term-confidence $proof))))
     (candidate-item $score () $proof $cont)))

(= (premise-goal-keys ()) ())
(= (premise-goal-keys (cons $prem $rest))
       (if (= $prem (: $_kb $_prf $type $_tv))
           (cons $type (premise-goal-keys $rest))
           (premise-goal-keys $rest)
       ))

(= (has-active-premise? $args $cont)
   (let* (($prem-keys (premise-goal-keys $args))
          ($cont-keys (map-flat (|-> ((resume $_r (: $_kb $_prf $type $_tv) $_ps)) $type) $cont)))
       (not (== (/=a\ $prem-keys $cont-keys) ()))))

(= (state-enqueue-item (state $pq $goals) $item)
   (case $item
     (
       ((qitem $_prio (cand (() |- $proved-goal) (cons (resume $rest $goal $parent-score) $rest-cont)))
        (let $new-score (min $parent-score (term-confidence $proved-goal))
          (state-enqueue-item (state $pq $goals) (candidate-item $new-score $rest $goal $rest-cont))))
       ((qitem $_prio (cand (() |- $goal) ()))
        (state $pq (cons $goal $goals)))
       ((qitem $prio (cand ($args |- $goal) $cont))
        (if (has-active-premise? $args $cont)
            (state $pq $goals)
            (state (add_to_heap $pq (- 0 $prio) $item) $goals)))
       ($other
        (state $pq $goals))
     )))

(= (enqueue-goal-state $steps $state $max-score $cont $goal)
   (let $state1 (fold-flat state-enqueue-item $state (collapse (direct-goal-items $steps $max-score $cont $goal)))
      (fold-flat state-enqueue-item $state1 (collapse (rule-candidate-items $max-score $cont $goal)))))

;; Best-first over partially-applied rule candidates.
(= (search-rules $steps $heap)
   (if (or (== (heap_size $heap) 0) (<= $steps 0))
       ()
       (let* (($pq-rest (get_from_heap $heap $_priority $item))
               ((qitem $score (cand ((cons $prem $rest) |- $goal) $cont)) $item)
               ($resume (resume $rest $goal $score))
               ((state $new-pq $ready-goals)
                 (enqueue-goal-state $steps (state $pq-rest ()) $score (cons $resume $cont) $prem)))
              (append $ready-goals (search-rules (- $steps 1) $new-pq)))))

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
