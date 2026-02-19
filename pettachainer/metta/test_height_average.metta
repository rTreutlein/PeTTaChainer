!(import! &self petta_chainer)

(= (SumCountAcc (SumCount $sumdist $count) $hdist)
   (SumCount (ParticleMap2 + $sumdist $hdist) (+ $count 1)))

(= (AverageFromSumCount (SumCount $sumdist $count))
   (ParticleMap (|-> ($x) (/ $x $count)) $sumdist))

(= (pair-mass ()) 0.0)
(= (pair-mass (cons ($_x $w) $tail))
   (+ $w (pair-mass $tail)))

(= (pair-weighted-sum ()) 0.0)
(= (pair-weighted-sum (cons ($x $w) $tail))
   (+ (* $x $w) (pair-weighted-sum $tail)))

(= (ParticleMean $pd)
   (let $pairs (ParticlePairs $pd)
      (/ (pair-weighted-sum $pairs)
         (pair-mass $pairs))))

!(compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))
!(compileadd kb (: group2 (Group g2) (STV 1.0 1.0)))

; Crisp heights encoded as point-mass distributions.
!(compileadd kb (: hd11 (HeightDist g1 alice) (PointMass 160.0)))
!(compileadd kb (: hd12 (HeightDist g1 bob) (PointMass 170.0)))
!(compileadd kb (: hd13 (HeightDist g1 carol) (PointMass 180.0)))

; Uncertain heights encoded as normal-like particle distributions.
!(compileadd kb (: hd21 (HeightDist g2 dan) (ParticleFromNormal 150.0 2.0)))
!(compileadd kb (: hd22 (HeightDist g2 erin) (ParticleFromNormal 170.0 2.0)))
!(compileadd kb (: hd23 (HeightDist g2 frank) (ParticleFromNormal 175.0 1.0)))

!(test
    (ParticleMean
        (AverageFromSumCount
            (FoldAllTVRuntimeFormula 80 kb
                (HeightDist g1 $person)
                (SumCount (PointMass 0.0) 0)
                SumCountAcc)))
    170.0)

!(test
    (ParticleMean
        (AverageFromSumCount
            (FoldAllTVRuntimeFormula 80 kb
                (HeightDist g2 $person)
                (SumCount (PointMass 0.0) 0)
                SumCountAcc)))
    165.0)

!(test
    (let (STV $s $c)
         (DistGreaterThanFormula
            (AverageFromSumCount
                (FoldAllTVRuntimeFormula 80 kb
                    (HeightDist g2 $person)
                    (SumCount (PointMass 0.0) 0)
                    SumCountAcc))
            165.0)
         (and (> $s 0.1) (< $s 0.9)))
    true)

!(test
    (let (STV $s $c)
         (DistGreaterThanFormula
            (AverageFromSumCount
                (FoldAllTVRuntimeFormula 80 kb
                    (HeightDist g1 $person)
                    (SumCount (PointMass 0.0) 0)
                    SumCountAcc))
            170.0)
         $s)
    0.0)
