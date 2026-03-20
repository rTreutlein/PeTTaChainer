!(import! &self petta_chainer)

!(compileadd kb (: group1 (Group g1) (STV 1.0 1.0)))

!(compileadd kb (: group2 (Group g2) (STV 1.0 1.0)))

!(compileadd kb (: hd11 (HeightDist g1 alice) (PointMass 160.0)))

!(compileadd kb (: hd12 (HeightDist g1 bob) (PointMass 170.0)))

!(compileadd kb (: hd13 (HeightDist g1 carol) (PointMass 180.0)))

!(compileadd kb (: hd21 (HeightDist g2 dan) (ParticleFromNormal 150.0 2.0)))

!(compileadd kb (: hd22 (HeightDist g2 erin) (ParticleFromNormal 170.0 2.0)))

!(compileadd kb (: hd23 (HeightDist g2 frank) (ParticleFromNormal 175.0 1.0)))

!(compileadd kb
   (: avgHeightDistRule
      (Implication
         (Premises (Group $g) (AverageDist (HeightDist $g $person) -> $avgDist))
         (Conclusions (AvgHeightDist $g)))
      (STV 1.0 1.0)))

!(test
   (let (: $prf (AvgHeightDist g1) $avgDist)
      (query 20 kb (: $prf (AvgHeightDist g1) $avgDist))
      (let (STV $s $c) (DistGreaterThanFormula $avgDist 170.0) $s))
   0.0)

!(test
   (let (: $prf (AvgHeightDist g1) $avgDist)
      (query 20 kb (: $prf (AvgHeightDist g1) $avgDist))
      (let (STV $s $c) (DistGreaterThanFormula $avgDist 169.0) $s))
   1.0)

!(test
   (let (: $prf (AvgHeightDist g2) $avgDist)
      (query 20 kb (: $prf (AvgHeightDist g2) $avgDist))
      (let (STV $s $c) (DistGreaterThanFormula $avgDist 165.0)
         (and (> $s 0.1) (< $s 0.9))))
   true)

!(test
   (let (: $prf (AvgHeightDist g1) $avgDist)
      (query 20 kb (: $prf (AvgHeightDist g1) $avgDist))
      (let (STV $s $c) (DistGreaterThanFormula $avgDist 169.0)
         (and (> $s 0.99) (> $c 0.0))))
   true)
