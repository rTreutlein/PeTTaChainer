!(import! &self petta_chainer)

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))

!(compileadd kb (: rB (Rectangle rectB) (STV 1.0 1.0)))

!(compileadd kb (: lenA (LengthDist rectA (ParticleFromNormal 10.0 1.0)) (STV 1.0 1.0)))

!(compileadd kb (: widA (WidthDist rectA (ParticleFromNormal 5.0 0.5)) (STV 1.0 1.0)))

!(compileadd kb (: lenB (LengthDist rectB (PointMass 8.0)) (STV 1.0 1.0)))

!(compileadd kb (: widB (WidthDist rectB (PointMass 4.0)) (STV 1.0 1.0)))

!(compileadd kb
   (: areaDistRule
      (Implication
         (Premises (Rectangle $rect)
            (Map2Dist *
               (LengthDist $rect $lengthDist)
               $lengthDist
               (WidthDist $rect $widthDist)
               $widthDist
               ->
               $areaDist))
         (Conclusions (AreaDist $rect $areaDist)))
      (STV 1.0 1.0)))

!(test
   (let (: $prf (AreaDist rectA $areaDist) $tv)
      (query 20 kb (: $prf (AreaDist rectA $areaDist) $tv))
      (let (STV $s $c) (DistGreaterThanFormula $areaDist 50.0)
         (and (> $s 0.1) (< $s 0.9))))
   true)

!(test
   (let (: $prf (AreaDist rectB $areaDist) $tv)
      (query 20 kb (: $prf (AreaDist rectB $areaDist) $tv))
      (let (STV $s $c) (DistGreaterThanFormula $areaDist 31.0) $s))
   1.0)

!(test
   (let (: $prf (AreaDist rectA $areaDist) $tv)
      (query 20 kb (: $prf (AreaDist rectA $areaDist) $tv))
      (let (STV $s $c) (DistGreaterThanFormula $areaDist 10.0)
         (and (> $s 0.99) (> $c 0.0))))
   true)
