!(import! &self petta_chainer)

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))

!(compileadd kb (: rB (Rectangle rectB) (STV 1.0 1.0)))

!(compileadd kb (: lenA (LengthDist rectA) (ParticleFromNormal 10.0 1.0)))

!(compileadd kb (: widA (WidthDist rectA) (ParticleFromNormal 5.0 0.5)))

!(compileadd kb (: lenB (LengthDist rectB) (PointMass 8.0)))

!(compileadd kb (: widB (WidthDist rectB) (PointMass 4.0)))

!(compileadd kb
   (: areaDistRule
      (Implication
         (Premises (Rectangle $rect)
            (Map2Dist * (LengthDist $rect) (WidthDist $rect) -> $areaDist))
         (Conclusions (AreaDist $rect)))
      (STV 1.0 1.0)))

!(test (collapse (query 20 kb (: $prf (AreaDist rectA) $areaDist))) ())

!(test (collapse (query 20 kb (: $prf (AreaDist rectB) $areaDist))) ())

!(test (collapse (query 20 kb (: $prf (AreaDist rectA) $areaDist))) ())
