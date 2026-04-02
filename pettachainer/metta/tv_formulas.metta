(= (MpFormula (STV $abs $abc) (STV $as $ac)) (STV (* $abs $as) (* 0.9 (min $abc $ac))))
(= (MpFormula (STV $abs $abc) (ParticleDist $pid $scale))
   (ParticleDist $pid (* $scale (tv-probability (STV $abs $abc)))))
(= (MpFormula (STV $abs $abc) (ParticleDist $pid))
   (MpFormula (STV $abs $abc) (ParticleDist $pid 1.0)))

(= (AndFormula (STV $si $ci) (STV $sa $ca))
   (let*
      (($sb (min $si $sa))
        ($cb (min $ci $ca)))
      (STV $sb $cb)))
(= (AndFormula (STV $s $c) (ParticleDist $pid $scale))
   (ParticleDist $pid (* $scale (tv-probability (STV $s $c)))))
(= (AndFormula (STV $s $c) (ParticleDist $pid))
   (AndFormula (STV $s $c) (ParticleDist $pid 1.0)))
(= (AndFormula (ParticleDist $pid $scale) (STV $s $c)) (STV $s $c))
(= (AndFormula (ParticleDist $pid) (STV $s $c))
   (AndFormula (ParticleDist $pid 1.0) (STV $s $c)))

(= (OrFormula (STV $si $ci) (STV $sa $ca))
   (let*
      (($sb (min $si $sa))
        ($cb (max $ci $ca)))
      (STV $sb $cb)))

(= (LikelierThanFormula (STV $sa $ca) (STV $sb $cb))
   (let*
      (($c (min $ca $cb)))
      (if (> $sa $sb) (STV $sa $c) (STV $sb $c))))

(= (AndProjection (STV $s $c)) (STV $s $c))

(= (OrProjection (STV $s $c)) (STV $s $c))

(= (DistGreaterThanFormula (ParticleDist $pid $scale) $threshold)
   (let $pairs (particle-fetch-pairs $pid)
      (STV (* $scale (dist-prob-gt $pairs $threshold))
         (particle-confidence-from-pairs $pairs))))
(= (DistGreaterThanFormula (ParticleDist $pid) $threshold)
   (DistGreaterThanFormula (ParticleDist $pid 1.0) $threshold))

(= (DistGreaterThanDistFormula $pda $pdb)
   (let*
      (($pida (particle-dist-id $pda))
        ($pidb (particle-dist-id $pdb))
        ($scalea (particle-dist-scale $pda))
        ($scaleb (particle-dist-scale $pdb))
        ($pairsa (particle-fetch-pairs $pida))
        ($pairsb (particle-fetch-pairs $pidb))
        ($ca (particle-confidence-from-pairs $pairsa))
        ($cb (particle-confidence-from-pairs $pairsb)))
      (STV (* (* $scalea $scaleb) (dist-prob-gt2 $pairsa $pairsb)) (min $ca $cb))))

(= (NotFormula (STV $s $c) (STV (- 1 $s) $c)))

(= (InversionFormula (STV $sa $ca) (STV $sb $cb) (STV $sab $cab))
   (STV (/ (* $sb $sab) $sa) (* (min-atom ($ca $cb $cab)) 0.9)))

(= (Equal $a $b) (== $a $b))
(= (NotEqual $a $b) (not (== $a $b)))
