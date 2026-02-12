!(import! &self compile)

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

(= (premises-expected-confidence Nil) 1.0)
(= (premises-expected-confidence ()) 1.0)
(= (premises-expected-confidence ($prem $rest))
   (min (premise-expected-confidence $prem) (premises-expected-confidence $rest)))

;; Priority queue sorted by descending expected confidence.
(= (pq-insert () $item) (cons $item ()))
(= (pq-insert (cons (qitem $p $args $goal) $rest) (qitem $np $nargs $ngoal))
   (if (> $np $p)
       (cons (qitem $np $nargs $ngoal) (cons (qitem $p $args $goal) $rest))
       (cons (qitem $p $args $goal) (pq-insert $rest (qitem $np $nargs $ngoal)))))

(= (pq-insert-all $pq ()) $pq)
(= (pq-insert-all $pq (cons $item $tail))
   (pq-insert-all (pq-insert $pq $item) $tail))

;; Build initial queue from all matching rule applications.
(= (candidate-from-match ($args |- $goal))
   (qitem (premises-expected-confidence $args) $args $goal))

(= (initial-candidate $goal)
   (let $_ (match &kb (rules ($args |- $goal)) (rules ($args |- $goal)))
        (candidate-from-match ($args |- $goal))))

(= (build-initial-pq $goal)
   (let $items (collapse (initial-candidate $goal))
        (pq-insert-all () $items)))

;; Try one prioritized rule; on failure continue with remaining queue.
(= (try-prioritized-rule $steps $visited (qitem $_prio $args $goal) $pq-rest)
   (let $_ (chain-rec-v $steps $visited $args)
        (cons $goal (search-rules $steps $visited $pq-rest))))
(= (try-prioritized-rule $steps $visited $item $pq-rest)
   (search-rules $steps $visited $pq-rest))

;; Best-first over rule applications.
(= (search-rules $steps $visited ()) ())
(= (search-rules $steps $visited (cons $item $pq-rest))
   (if (<= $steps 0)
       ()
       (try-prioritized-rule (- $steps 1) $visited $item $pq-rest)))

(= (first-result (cons $head $_tail)) $head)
(= (first-result ($head $_tail)) $head)
(= (first-result ()) (empty))

;; DFS fallback keeps legacy behavior if best-first cannot complete.
(= (search-rules-dfs-fallback $steps $visited $goal)
   (let $_ (match &kb (rules ($args |- $goal)) (rules ($args |- $goal)))
        (let $args (chain-rec-v $steps $visited $args)
             $goal)))

;; CPU functions that need the current step budget as first argument.
(= (cpu-needs-steps $fun) (== $fun FoldAllFormulaCompiled))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $steps $fun $args)
  (let $call
       (if (cpu-needs-steps $fun)
           (cons $fun (cons $steps $args))
           (cons $fun $args))
       (reduce (reduce $call))))

(= (chainer-v $steps $visited (CPU $fun $args $res))
  (if (<= $steps 0)
      (empty)
      (let $res (cpu-call (- $steps 1) $fun $args)
           (CPU $fun $args $res))))

(= (chainer-v $steps $visited $goal)
  (match &kb $goal $goal))

(= (chainer-v $steps $visited $goal)
   (let $k (goal-key $goal)
   (if (or (<= $steps 0) (is-member $k $visited))
       (empty)
       (let $pq (build-initial-pq $goal)
            (let $results (search-rules $steps (cons $k $visited) $pq)
                 (if (== $results ())
                     (search-rules-dfs-fallback $steps (cons $k $visited) $goal)
                     (superpose $results))))
       )))

(= (chain-rec-v $steps $visited ($goal $dep))
  (if (== $dep Nil)
    ((chainer-v $steps $visited $goal) Nil)
    ((chainer-v $steps $visited $goal) (chain-rec-v $steps $visited $dep))))

(= (chainer $steps $goal) (chainer-v $steps () $goal))

;; Keep first occurrence order while removing duplicate results.
(= (ordered-unique-acc () $seen) ())
(= (ordered-unique-acc (cons $head $tail) $seen)
   (if (is-member $head $seen)
       (ordered-unique-acc $tail $seen)
       (cons $head (ordered-unique-acc $tail (cons $head $seen)))))
(= (ordered-unique $lst) (ordered-unique-acc $lst ()))

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

(= (MpFormula (STV $abs $abc) (STV $as $ac)) (STV (* $abs $as) $abc))
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
       (let $results (collapse (pretty (chainer $steps $query)))
            (superpose (ordered-unique $results))))))
