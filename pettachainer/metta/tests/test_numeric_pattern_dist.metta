!(import! &self petta_chainer)

!(compileadd kb (: fx1 (AtTime (FeatureX 10.0) 1) (STV 1.0 0.9)))
!(compileadd kb (: fy1 (AtTime (FeatureY 100.0) 1) (STV 1.0 0.9)))
!(compileadd kb (: fz2 (AtTime (FeatureZ 20.0) 2) (STV 1.0 0.9)))

!(compileadd kb (: fx3 (AtTime (FeatureX 10.0) 3) (STV 1.0 0.9)))
!(compileadd kb (: fy3 (AtTime (FeatureY 100.0) 3) (STV 1.0 0.9)))
!(compileadd kb (: fz4 (AtTime (FeatureZ 21.0) 4) (STV 1.0 0.9)))

!(compileadd kb (: fx5 (AtTime (FeatureX 10.0) 5) (STV 1.0 0.9)))
!(compileadd kb (: fy5 (AtTime (FeatureY 100.0) 5) (STV 1.0 0.9)))
!(compileadd kb (: fz6 (AtTime (FeatureZ 19.0) 6) (STV 1.0 0.9)))

!(compileadd kb (: fx7 (AtTime (FeatureX 10.0) 7) (STV 1.0 0.9)))
!(compileadd kb (: fy7 (AtTime (FeatureY 2.0) 7) (STV 1.0 0.9)))
!(compileadd kb (: fz8 (AtTime (FeatureZ 49.0) 8) (STV 1.0 0.9)))

!(compileadd kb
   (: sampleRule
      (Implication
         (Premises
            (AtTime (FeatureX $xv) $t)
            (AtTime (FeatureY $yv) $t)
            (Compute + ($t 1) -> $t1)
            (AtTime (FeatureZ $zv) $t1))
         (Conclusions (XYZSample (Pair (XY $xv $yv) $zv))))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 kb (: $prf (XYZSample $sample) $tv))
   ((: (sampleRule (conjunction fx7 fy7 cpu fz8))
       (XYZSample (Pair (XY 10.0 2.0) 49.0))
       (STV 1.0 0.9))
    (: (sampleRule (conjunction fx5 fy5 cpu fz6))
       (XYZSample (Pair (XY 10.0 100.0) 19.0))
       (STV 1.0 0.9))
    (: (sampleRule (conjunction fx3 fy3 cpu fz4))
       (XYZSample (Pair (XY 10.0 100.0) 21.0))
       (STV 1.0 0.9))
    (: (sampleRule (conjunction fx1 fy1 cpu fz2))
       (XYZSample (Pair (XY 10.0 100.0) 20.0))
       (STV 1.0 0.9))))

!(test (struct-distance2 (XY 10.0 100.0) (XY 10.0 100.0)) 0.0)

!(test (car-atom (collapse (struct-distance2 (XY 10.0 100.0) (XY 10.0 2.0)))) 9604.0)

!(test
   (ParticlePairs (DistMap2Formula XY (PointMass 10.0) (PointMass 2.0)))
   (((XY 10.0 2.0) 1.0)))

!(test
   (joint-cond-add-sample (XY 10.0 100.0) 1.0 (Pair (XY 10.0 100.0) 20.0) 1.0 5.0 ())
   ((20.0 1.0)))
