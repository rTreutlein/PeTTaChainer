!(import! &self compile)
!(import! &self mining)

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

;; Normalize variable names out of a goal key so renamed variants are treated as same state.
(= (goal-key (: $kb $prf $type $tv)) $type)

;; CPU functions that need the current chain depth as their first argument.
(= (cpu-needs-depth $fun) (== $fun FoldAllFormulaCompiled))

;; Generic CPU dispatcher used by chainer.
(= (cpu-call $depth $fun $args)
  (let $call
       (if (cpu-needs-depth $fun)
           (cons $fun (cons $depth $args))
           (cons $fun $args))
       (reduce (reduce $call))))

(= (chainer-v $depth $visited (CPU $fun $args $res))
  (let $res (cpu-call $depth $fun $args)
       (CPU $fun $args $res)))

(= (chainer-v $depth $visited $goal)
  (match &kb $goal $goal))

(= (chainer-v (S $depth) $visited $goal)
   (let $k (goal-key $goal)
   (if (is-member $k $visited)
       (empty)
       (let $_ (match &kb (rules ($args |- $goal)) (rules ($args |- $goal)))
         (let $args (chain-rec-v $depth (cons $k $visited) $args)
         $goal))
       )))

(= (chain-rec-v $depth $visited ($goal $dep))
  (if (== $dep Nil)
    ((chainer-v $depth $visited $goal) Nil)
    ((chainer-v $depth $visited $goal) (chain-rec-v $depth $visited $dep))))

(= (chainer $depth $goal) (chainer-v $depth () $goal))

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
(= (run-compiled-query $depth $compiled-query)
  (let (cons (goal $query) $adds) $compiled-query
  (let $_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))
       (chainer $depth $query))))

;; FoldAll runtime uses precompiled query, then extracts fold values via pattern match.
(= (FoldAllFormulaCompiled $depth $compiled-query $pattern $value $init $fun)
  (let $matches (collapse (let (: $kbr $prf $pattern $tvin) (run-compiled-query $depth $compiled-query) $value))
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



;; Compile query to goal+adds, inject adds, then run goal through chainer.
(= (query $depth $kb $stmt)
  (let (cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt))
  (let $_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))
       (pretty (chainer $depth $query)))))
