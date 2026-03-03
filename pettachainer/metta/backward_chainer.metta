;;;;;;;;;
;; Nat ;;
;;;;;;;;;
;; Define Nat
(: Nat Type)
(: Z Nat)
(: S (-> Nat Nat))
;; Define cast functions between Nat and Number
(: fromNumber (-> Number Nat))
(= (fromNumber $n) (if (<= $n 0) Z (S (fromNumber (- $n 1)))))

(: fromNat (-> Nat Number))
(= (fromNat Z) 0)
(= (fromNat (S $k)) (+ 1 (fromNat $k)))

;;;;;;;;;;;;;;;;;;
;; Chainer Core ;;
;;;;;;;;;;;;;;;;;;
(= (chainer $steps $goal)
   (let*
      (($_rclear (remove-all-atoms &resume_cache))
        ($_gclear (remove-all-atoms &goal_cache))
        ((state $pq $_rcache $_gcache)
           (enqueue-goal-state $steps
              (state (empty_heap) &resume_cache &goal_cache)
              1.0
              ()
              $goal))
        ($_ (search-rules $steps $pq &resume_cache &goal_cache)))
      (collapse (match &goal_cache (gmerge $result-goal) $result-goal))))

(= (enqueue-goal-state $steps $state $max-score $cont $goal)
   (let $state1
      (fold-flat state-enqueue-item $state (collapse (direct-goal-items $steps $max-score $cont $goal)))
      (fold-flat state-enqueue-item $state1 (collapse (rule-candidate-items $max-score $cont $goal)))))

(= (rule-candidate-items $max-score $cont $goal)
   (let $id (match &ccls_index ($goal $id) $id)
      (let ($_id $_goal $args) (match &rules ($id $goal $args) ($_id $_goal $args))
         (let $score (min $max-score (premises-expected-confidence $args))
            (candidate-item $score $args $goal $cont)))))

(= (unwrap $x) (if (== $x #) $any $x))

(= (contains-hash? $x) (if (== $x #) true (if (is-expr $x) (contains-hash-expr $x) false)))

(= (contains-hash-expr $expr) (or (== (car-atom $expr) #) (contains-hash-list (cdr-atom $expr))))

(= (contains-hash-list ()) false)
(= (contains-hash-list (cons $head $tail)) (or (contains-hash? $head) (contains-hash-list $tail)))

(= (direct-goal-items $steps $max-score $cont $goal)
   (let*
      (($proof
           (if (= $goal (CPU $fun $args $_res)) (CPU $fun $args (cpu-call $steps $fun $args))
              (let (: $kb $prf $type $tv) $goal
                 (let $utype
                    (if (and (is-expr $type) (contains-hash? $type)) (map-nested unwrap $type) $type)
                    (match &kb (: $kb $prf $utype $tv)
                       (: $kb $prf $type $tv))))))
        ($score (min $max-score (term-confidence $proof))))
      (candidate-item $score () $proof $cont)))

;; Best-first over partially-applied rule candidates.
(= (payload-cand $payload) (if (= $payload (resume-cand $_rid $_type $cand)) $cand $payload))

(= (payload-rid $payload) (if (= $payload (resume-cand $rid $_type $_cand)) $rid (nextctx)))

(= (payload-repack $payload $cand)
   (if (= $payload (resume-cand $rid $type $_old-cand)) (resume-cand $rid $type $cand) $cand))

(= (search-rules $steps $heap $rcache $gcache)
   (if (or (== (heap_size $heap) 0) (<= $steps 0)) ()
      (let*
         (($pq-rest (get_from_heap $heap $_priority (qitem $score $payload)))
           ((cand ((cons $prem $rest) |- $goal) $cont) (payload-cand $payload))
           ($rid (payload-rid $payload))
           ((resume-template $rprem $rrest $rgoal) (copy_term (resume-template $prem $rest $goal)))
           ((state $new-pq $_new-rcache $_new-gcache)
              (enqueue-goal-state $steps
                 (state $pq-rest $rcache $gcache)
                 $score
                 (cons (resume $rid $rprem $rrest $rgoal $score) $cont)
                 $rprem)))
         (search-rules (- $steps 1) $new-pq $rcache $gcache))))

(= (state-enqueue-cand (@ $state (state $pq $rcache $gcache)) $prio $payload $cand)
   (case $cand (
        ((cand (() |- $item-goal) ())
           (progn (goal-cache-upsert $gcache $item-goal) (state $pq $rcache $gcache)))
        ((cand (() |- $proved-goal) $cont)
           (resume-merge-enqueue-cont (state $pq $rcache $gcache) $proved-goal $cont))
        ((cand ((cons $arg $args) |- $item-goal) $cont)
           (if (has-active-premise? (cons $arg $args) $cont) (state $pq $rcache $gcache)
              (state
                 (add_to_heap $pq
                    (- 0 $prio)
                    (qitem $prio (payload-repack $payload (cand ((cons $arg $args) |- $item-goal) $cont))))
                 $rcache
                 $gcache))))))

(= (state-enqueue-item (state $pq $rcache $gcache) (qitem $prio $payload))
   (state-enqueue-cand (state $pq $rcache $gcache) $prio $payload (payload-cand $payload)))

(= (resume-cont-has-type? () $type) false)
(=
   (resume-cont-has-type? (cons (resume $_rid $_prem $_rest (: $_kb $_prf $goal-type $_tv) $_score) $tail)
      $type)
   (or (=alpha $goal-type $type) (resume-cont-has-type? $tail $type)))

(= (premises-have-active-type? () $cont) false)
(= (premises-have-active-type? (cons $prem $rest) $cont)
   (if (= $prem (: $_kb $_prf $type $_tv))
      (or (resume-cont-has-type? $cont $type) (premises-have-active-type? $rest $cont))
      (premises-have-active-type? $rest $cont)))

(= (has-active-premise? $args $cont) (if (== $cont ()) false (premises-have-active-type? $args $cont)))

;; CPU functions that need the current step budget as first argument.
(= (cpu-needs-steps $fun)
   (or (== $fun FoldAllFormulaCompiled)
      (or (== $fun FoldAllTVFormulaCompiled)
         (or (== $fun FoldAllTVPatternFormula)
            (or (== $fun FoldAllTVRuntimeFormula)
               (or (== $fun FoldAllValueFormulaCompiled)
                  (or (== $fun DistAverageFormula) (== $fun Map2DistRuntimeFormula))))))))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $steps $fun $args)
   (let $call (if (cpu-needs-steps $fun) (cons $fun (cons $steps $args)) (cons $fun $args))
      (reduce (reduce $call))))

;;;;;;;;;;;;;;;;;;
;; CPU Formulas ;;
;;;;;;;;;;;;;;;;;;
;; Runtime fold helper.
(= (foldall-eval $fun $acc ()) $acc)
(= (foldall-eval $fun $acc (cons $elem $tail))
   (let*
      (($call (cons $fun (cons $acc (cons $elem ()))))
        ($nacc (reduce (reduce $call))))
      (foldall-eval $fun $nacc $tail)))

(= (extract-proof-tvs ()) ())
(= (extract-proof-tvs (cons (: $_kb $_prf $_type $tv) $tail)) (cons $tv (extract-proof-tvs $tail)))
(= (extract-proof-tvs (cons $_head $tail)) (extract-proof-tvs $tail))

(= (inject-compiled-adds $adds) (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds))))

;; Execute a precompiled query plan represented as (goal + adds).
(= (run-compiled-query $steps $compiled-query)
   (let*
      (((cons (goal $query) $adds) $compiled-query)
        ($_ (inject-compiled-adds $adds)))
      (chainer $steps $query)))

;; FoldAll runtime uses precompiled query, then extracts fold values via pattern match.
(= (FoldAllFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (let $matches
      (collapse (let (: $kbr $prf $pattern $tvin) (run-compiled-query $steps $compiled-query) $value))
      (foldall-eval $fun $init $matches)))

;; Fold over the TV values of all matches in a precompiled query.
(= (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun)
   (let $matches (extract-proof-tvs (run-compiled-query $steps $compiled-query))
      (foldall-eval $fun $init $matches)))

;; Runtime-compiled TV fold preserving current variable bindings.
(= (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun)
   (let $kctx (fold-kbctx $kb)
      (let $matches (collapse (match &kb (: $kctx $prf $pattern $ptv) $ptv))
         (foldall-eval $fun $init $matches))))

;; Compute Map2Dist premise outputs from queried distribution TVs.
(= (Map2DistRuntimeFormula $steps $kb $fun $a $b)
   (let (: $prfa $a $tva) (query $steps $kb (: $prfa $a $tva))
      (let (: $prfb $b $tvb) (query $steps $kb (: $prfb $b $tvb))
         (reduce (DistMap2Formula $fun $tva $tvb)))))

;; Steps parameter kept for uniform CPU call shape.
(= (FoldAllTVRuntimeFormula $steps $kb $pattern $init $fun) (FoldAllTVRuntimeNoSteps $kb $pattern $init $fun))

(= (fold-kbctx $kb) (if (is-expr $kb) (let ($kbid $_ctx $_vars) $kb ($kbid MAIN Nil)) ($kb MAIN Nil)))

;; Fold over TV values by running the given pattern query under current substitutions.
(= (FoldAllTVPatternFormula $steps $kb $pattern $init $fun)
   (let $matches (collapse (let (: $prf $pattern $ptv) (query $steps $kb (: $prf $pattern $ptv)) $ptv))
      (foldall-eval $fun $init $matches)))

;; FoldAllValue runtime kept for compatibility with earlier compiled forms.
(= (FoldAllValueFormulaCompiled $steps $compiled-query $pattern $value $init $fun)
   (FoldAllTVFormulaCompiled $steps $compiled-query $init $fun))
