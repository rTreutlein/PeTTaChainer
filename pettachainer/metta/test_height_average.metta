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

(= (AvgHeightDistFromKB $g)
   (AverageFromSumCount
      (FoldAllTVRuntimeFormula 80 kb
         (HeightDist $g $person)
         (SumCount (PointMass 0.0) 0)
         SumCountAcc)))

!(compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))
!(compileadd kb (: group2 (Group g2) (STV 1.0 1.0)))

; Crisp heights encoded as point-mass distribution TVs.
!(compileadd kb (: hd11 (HeightDist g1 alice) (PointMass 160.0)))
!(compileadd kb (: hd12 (HeightDist g1 bob) (PointMass 170.0)))
!(compileadd kb (: hd13 (HeightDist g1 carol) (PointMass 180.0)))

; Uncertain heights encoded as normal-like particle distribution TVs.
!(compileadd kb (: hd21 (HeightDist g2 dan) (ParticleFromNormal 150.0 2.0)))
!(compileadd kb (: hd22 (HeightDist g2 erin) (ParticleFromNormal 170.0 2.0)))
!(compileadd kb (: hd23 (HeightDist g2 frank) (ParticleFromNormal 175.0 1.0)))

!(compileadd kb (: avgHeightDistG1Rule
    (Implication
        (Premises
            (Group g1)
            (Compute AvgHeightDistFromKB (g1) -> $avgDist))
        (Conclusions
            (AvgHeightDist g1 $avgDist)))
    (STV 1.0 1.0)))

!(compileadd kb (: avgHeightDistG2Rule
    (Implication
        (Premises
            (Group g2)
            (Compute AvgHeightDistFromKB (g2) -> $avgDist))
        (Conclusions
            (AvgHeightDist g2 $avgDist)))
    (STV 1.0 1.0)))

!(test
    (let (: (avgHeightDistG1Rule (conjunction group1 cpu)) (AvgHeightDist g1 $avgDist) $tv)
         (query 10 kb (: (avgHeightDistG1Rule (conjunction group1 cpu)) (AvgHeightDist g1 $avgDist) $tv))
         (ParticleMean $avgDist))
    170.0)

!(test
    (let (: (avgHeightDistG2Rule (conjunction group2 cpu)) (AvgHeightDist g2 $avgDist) $tv)
         (query 10 kb (: (avgHeightDistG2Rule (conjunction group2 cpu)) (AvgHeightDist g2 $avgDist) $tv))
         (ParticleMean $avgDist))
    165.0)

!(test
    (let (: (avgHeightDistG2Rule (conjunction group2 cpu)) (AvgHeightDist g2 $avgDist) $tv)
         (query 10 kb (: (avgHeightDistG2Rule (conjunction group2 cpu)) (AvgHeightDist g2 $avgDist) $tv))
         (let (STV $s $c) (DistGreaterThanFormula $avgDist 165.0)
              (and (> $s 0.1) (< $s 0.9))))
    true)

!(test
    (let (: (avgHeightDistG1Rule (conjunction group1 cpu)) (AvgHeightDist g1 $avgDist) $tv)
         (query 10 kb (: (avgHeightDistG1Rule (conjunction group1 cpu)) (AvgHeightDist g1 $avgDist) $tv))
         (let (STV $s $c) $tv (and (> $s 0.99) (> $c 0.99))))
    true)
