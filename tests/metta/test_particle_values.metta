!(import! &self ../../pettachainer/metta/petta_chainer)

(: TestCoefficientVector Type)
(: TestCoefficients
   (-[det]-> Number Number TestCoefficientVector))

!(test (DistGreaterThanFormula (ParticleFromPairs ((0 0.25) (2 0.75))) 1)
   (STV 0.75 1.0))

!(test (DistGreaterThanFormula (PointMass 180) 170)
   (STV 1.0 1.0))

!(test
   (let*
      (($pd0 (ParticleFromPairs ((0 1.0))))
        ($pd1 (ParticleAddBernoulliFromSTV $pd0 (STV 0.5 1.0)))
        ($pd2 (ParticleAddBernoulliFromSTV $pd1 (STV 0.5 1.0))))
      (DistGreaterThanFormula $pd2 1))
   (STV 0.25 1.0))

!(test (ParticlePairs (ParticleFromPairs ((170 0.5) (180 0.5)))) ((170 0.5) (180 0.5)))

!(test (ParticlePairs (ParticleFromPairs ((175 1.0)))) ((175 1.0)))

!(test (DistGreaterThanDistFormula (ParticleFromPairs ((170 0.5) (180 0.5))) (ParticleFromPairs ((175 1.0))))
   (STV 0.5 1.0))

!(test (DistGreaterThanFormula (ParticleMap (|-> ($x) (+ $x 1)) (ParticleFromPairs ((0 0.25) (2 0.75)))) 2)
   (STV 0.75 1.0))

!(test
   (DistGreaterThanFormula
      (ParticleMap2 + (ParticleFromPairs ((170 0.5) (180 0.5))) (ParticleFromPairs ((160 1.0))))
      335)
   (STV 0.5 1.0))

!(test
   (DistGreaterThanFormula
      (ParticleMap2 (|-> ($a $b) (/ (+ $a $b) 2))
         (ParticleFromPairs ((180 1.0)))
         (ParticleFromPairs ((160 1.0))))
      169)
   (STV 1.0 1.0))

!(compileadd kb
   (: countryHeightA (CountryHeightDist countryA (ParticleFromPairs ((170 0.5) (180 0.5)))) (STV 1.0 1.0)))

!(compileadd kb
   (: countryHeightB (CountryHeightDist countryB (ParticleFromPairs ((175 1.0)))) (STV 1.0 1.0)))

!(compileadd kb
   (: compareHeightsRule
      (Implication
         (And (CountryHeightDist countryA $heightA)
            (CountryHeightDist countryB $heightB)
            (GreaterThan $heightA $heightB))
         (Taller countryA countryB))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let (: $prf (Taller countryA countryB) $tv) (query 40 kb (: $prf (Taller countryA countryB) $tv))
      (let (STV $s $c) $tv $s))
   0.5)

!(test
   (let (: $prf (Taller countryA countryB) $tv) (query 40 kb (: $prf (Taller countryA countryB) $tv))
      (let (STV $s $c) $tv $c))
   0.9998999998010201)

!(compileadd kb (: kidp1 (Kid kidp1) (STV 1.0 1.0)))

!(compileadd kb (: kidp2 (Kid kidp2) (STV 1.0 1.0)))

!(compileadd kb (: roomp1 (Room roomp1) (STV 1.0 1.0)))

!(compileadd kb (: roomp2 (Room roomp2) (STV 1.0 1.0)))

!(compileadd kb (: inp11 (In roomp1 kidp1) (STV 0.5 1.0)))

!(compileadd kb (: inp12 (In roomp1 kidp2) (STV 0.5 1.0)))

!(compileadd kb (: inp21 (In roomp2 kidp1) (STV 0.2 1.0)))

!(compileadd kb (: inp22 (In roomp2 kidp2) (STV 0.3 1.0)))

!(compileadd kb
   (: cntKidInParticleRule
      (Implication
         (And (Room $room)
            (FoldAllValue (In $room $kid)
               (ParticleFromPairs ((0 1.0)))
               ParticleAddBernoulliFromSTV
               ->
               $dist))
         (CntKidInParticle $room $dist))
      (CTV (STV 1.0 0.8) (STV 0.0 1.0))))

!(compileadd kb
   (: playTogetherParticleRule
      (Implication (And (Room $room) (CntKidInParticle $room $cnt) (GreaterThan $cnt 1))
         (PlayTogetherParticleIn $room))
      (CTV (STV 1.0 0.75) (STV 0.0 1.0))))

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (DistGreaterThanFormula (the Distribution $cnt) 1)
         (and (and (> $s 0.2499) (< $s 0.2501)) (== $c 1.0))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (DistGreaterThanFormula (the Distribution $cnt) 1)
         (and (and (> $s 0.0599) (< $s 0.0601)) (== $c 1.0))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (CTVModusPonensFormula (DistGreaterThanFormula (the Distribution $cnt) 1) (CTV (STV 1.0 0.75) (STV 0.0 1.0)))
	         (and (and (> $s 0.2499) (< $s 0.2501)) (== $c 0.9998998986564899))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (CTVModusPonensFormula (DistGreaterThanFormula (the Distribution $cnt) 1) (CTV (STV 1.0 0.75) (STV 0.0 1.0)))
         (and (and (> $s 0.0599) (< $s 0.0601)) (== $c 0.9998999871691416))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (CTVModusPonensFormula (DistGreaterThanFormula (the Distribution $cnt) 1) (CTV (STV 1.0 0.75) (STV 0.0 1.0))) (> $c 0.0)))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv) (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (CTVModusPonensFormula (DistGreaterThanFormula (the Distribution $cnt) 1) (CTV (STV 1.0 0.75) (STV 0.0 1.0))) (> $c 0.0)))
   true)

!(test (progn (ParticleStoreClear) (ParticleStoreCount)) 0)

!(test (progn (ParticleSetBudget 128) (ParticleGetBudget)) 128)

!(test (progn (ParticleSetBudget 512) (ParticleGetBudget)) 512)

;; An over-budget vector is absorbed by the compatible retained mode with the
;; least weighted second-moment loss. The whole coefficient vector moves to
;; one weighted centroid, so its coordinates remain correlated.
!(test
   (let $pairs
      (progn
         (ParticleSetBudget 2)
         (ParticlePairs
            (ParticleFromPairs
               (((TestCoefficients 0.8 -0.2) 0.25)
                ((TestCoefficients 0.6 -0.1) 0.25)
                ((TestCoefficients 4.0 5.0) 0.5)))))
      (progn (ParticleSetBudget 512) (ParticleStoreClear) $pairs))
   (((TestCoefficients 0.7 -0.15000000000000002) 0.5)
    ((TestCoefficients 4.0 5.0) 0.5)))

;; More than one overflow vector is absorbed independently into its closest
;; retained mode, rather than flattening the coordinates into marginals.
!(test
   (let $pairs
      (progn
         (ParticleSetBudget 2)
         (ParticlePairs
            (ParticleFromPairs
               (((TestCoefficients 0.0 0.0) 0.25)
                ((TestCoefficients 10.0 10.0) 0.25)
                ((TestCoefficients 2.0 0.0) 0.25)
                ((TestCoefficients 8.0 10.0) 0.25)))))
      (progn (ParticleSetBudget 512) (ParticleStoreClear) $pairs))
   (((TestCoefficients 1.0 0.0) 0.5)
    ((TestCoefficients 9.0 10.0) 0.5)))

;; Categorical samples have no centroid. They retain the deterministic
;; systematic fallback when their support exceeds the same budget.
!(test
   (let $pairs
      (progn
         (ParticleSetBudget 2)
         (ParticlePairs
            (ParticleFromPairs
               ((red 0.2) (green 0.3) (blue 0.5)))))
      (progn (ParticleSetBudget 512) (ParticleStoreClear) $pairs))
   ((green 0.5) (blue 0.5)))

;; Bare numbers may denote discrete states, such as a Bernoulli count, so they
;; also retain systematic resampling. A structured term explicitly supplies
;; the geometry needed for coefficient coalescing.
!(test
   (let $pairs
      (progn
         (ParticleSetBudget 2)
         (ParticlePairs
            (ParticleFromPairs
               ((0.0 0.25) (1.0 0.25) (10.0 0.5)))))
      (progn (ParticleSetBudget 512) (ParticleStoreClear) $pairs))
   ((0.0 0.5) (10.0 0.5)))

!(test (progn (ParticleFromPairs ((1 0.6) (2 0.4))) (ParticleFromPairs ((3 1.0))) (ParticleStoreCount))
   3)

!(test (progn (ParticleStorePruneKB) (ParticleStoreCount)) 0)

!(compileadd kb
   (: keptParticleFact (CountryHeightDist keepCountry (ParticleFromPairs ((170 0.7) (180 0.3)))) (STV 1.0 1.0)))

;; Pruning keeps the two samples referenced by keptParticleFact and removes
;; only the unreferenced point mass.
!(test (progn (ParticleFromPairs ((999 1.0))) (ParticleStorePruneKB)) 2)
