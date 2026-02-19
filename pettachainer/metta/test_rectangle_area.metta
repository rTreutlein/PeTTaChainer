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

(= (RectAreaDist $rect)
   (let (: $prfL (LengthDist $rect) $tvL)
        (query 80 kb (: $prfL (LengthDist $rect) $tvL))
        (let (: $prfW (WidthDist $rect) $tvW)
             (query 80 kb (: $prfW (WidthDist $rect) $tvW))
             (ParticleMap2 * $tvL $tvW))))

!(compileadd kb (: lenA (LengthDist rectA) (ParticleFromNormal 10.0 1.0)))
!(compileadd kb (: widA (WidthDist rectA) (ParticleFromNormal 5.0 0.5)))

!(compileadd kb (: lenB (LengthDist rectB) (PointMass 8.0)))
!(compileadd kb (: widB (WidthDist rectB) (PointMass 4.0)))

!(test
    (let $m (ParticleMean (RectAreaDist rectA))
         (and (> $m 49.9) (< $m 50.1)))
    true)

!(test
    (let (STV $s $c) (DistGreaterThanFormula (RectAreaDist rectA) 50.0)
         (and (> $s 0.1) (< $s 0.9)))
    true)

!(test
    (let (STV $s $c) (DistGreaterThanFormula (RectAreaDist rectB) 31.0)
         $s)
    1.0)
