!(import! &self petta_chainer)

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

(= (RectAreaDistFromKB $rect)
   (let (: $prfL (LengthDist $rect) $tvL)
        (query 80 kb (: $prfL (LengthDist $rect) $tvL))
        (let (: $prfW (WidthDist $rect) $tvW)
             (query 80 kb (: $prfW (WidthDist $rect) $tvW))
             (ParticleMap2 * $tvL $tvW))))

!(compileadd kb (: rA (Rectangle rectA) (STV 1.0 1.0)))
!(compileadd kb (: rB (Rectangle rectB) (STV 1.0 1.0)))

; Length and width are represented as distribution TVs.
!(compileadd kb (: lenA (LengthDist rectA) (ParticleFromNormal 10.0 1.0)))
!(compileadd kb (: widA (WidthDist rectA) (ParticleFromNormal 5.0 0.5)))

!(compileadd kb (: lenB (LengthDist rectB) (PointMass 8.0)))
!(compileadd kb (: widB (WidthDist rectB) (PointMass 4.0)))

!(compileadd kb (: areaDistRule
    (Implication
        (Premises
            (Rectangle $rect)
            (Compute RectAreaDistFromKB ($rect) -> $areaDist))
        (Conclusions
            (AreaDist $rect $areaDist)))
    (STV 1.0 1.0)))

!(test
    (let (: $prf (AreaDist rectA $areaDist) $tv)
         (query 120 kb (: $prf (AreaDist rectA $areaDist) $tv))
         (let $m (ParticleMean $areaDist)
              (and (> $m 49.9) (< $m 50.1))))
    true)

!(test
    (let (: $prf (AreaDist rectA $areaDist) $tv)
         (query 120 kb (: $prf (AreaDist rectA $areaDist) $tv))
         (let (STV $s $c) (DistGreaterThanFormula $areaDist 50.0)
              (and (> $s 0.1) (< $s 0.9))))
    true)

!(test
    (let (: $prf (AreaDist rectB $areaDist) $tv)
         (query 120 kb (: $prf (AreaDist rectB $areaDist) $tv))
         (let (STV $s $c) (DistGreaterThanFormula $areaDist 31.0)
              $s))
    1.0)

!(test
    (let (: $prf (AreaDist rectA $areaDist) $tv)
         (query 120 kb (: $prf (AreaDist rectA $areaDist) $tv))
         (let (STV $s $c) $tv (and (> $s 0.99) (> $c 0.99))))
    true)
