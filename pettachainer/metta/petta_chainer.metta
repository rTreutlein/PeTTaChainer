!(import! &self compile)

(= (chainer $depth $goal) (match &kb $goal $goal))

(= (chainer $depth (CPU $fun $args $res)) (let $res ($fun $args) (CPU $fun $args $res)))

(= (chainer (S $depth) $goal)
  (let $_ (match &kb (rules ($args |- $goal)) (rules ($args |- $goal)))
  (let $args (chain-rec $depth $args)
  $goal)))

(= (chain-rec $depth ($goal Nil))  ((chainer $depth $goal) Nil))
(= (chain-rec $depth ($goal $dep)) ((chainer $depth $goal) (chain-rec $depth $dep)))

(= (MpFormula ((STV $abs $abc) (STV $as $ac))) (STV (* $abs $as) $abc))
(= (AndFormula ((STV $si $ci) (STV $sa $ca))) (let $sb (min $si $sa)
                                              (let $cb (min $ci $ca) (STV $sb $cb))))

(= (OrFormula ((STV $si $ci) (STV $sa $ca))) (let $sb (min $si $sa)
                                             (let $cb (max $ci $ca) (STV $sb $cb))))

(= (LikelierThanFormula ((STV $sa $ca) (STV $sb $cb))) (let $c (min $ca $cb) (if (> $sa $sb) (STV $sa $c) (STV $sb $c))))


(= (AndProjection ((STV $s $c))) (STV $s $c))
(= (OrProjection ((STV $s $c))) (STV $s $c))

(= (NotFormula ((STV $s $c)) (STV (- 1 $s) $c)))

(= (InversionFormula ((STV $sa $ca) (STV $sb $cb) (Stv $sab $cab))) (STV (/ (* $sb $sab) $sa) (min-atom ($ca $cb $cab)))) 

(= (Equal ($a $b)) (== $a $b))
(= (NotEqual ($a $b)) (not (== $a $b)))


(= (compileadd $kb $stmt)
  (let $atoms (mm2compile $kb $stmt) (add-atom &kb $atoms)))


(= (query $depth $kb $stmt)
  (let (cons (goal $query) $adds) (collapse (mm2compileQuery $kb $stmt))
  (let $_ (if (= $adds ()) $_ (let $sadds (superpose $adds) (add-atom &kb $sadds)))
       (pretty (chainer $depth $query)))))
