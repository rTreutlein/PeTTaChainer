!(import! &self petta_chainer)

!(test (DistGreaterThanFormula (ParticleFromPairs ((0 0.25) (2 0.75))) 1)
   (STV 0.75 0.07407407407407407))

!(test
   (let*
      (($pd0 (ParticleFromPairs ((0 1.0))))
        ($pd1 (ParticleAddBernoulliFromSTV $pd0 (STV 0.5 1.0)))
        ($pd2 (ParticleAddBernoulliFromSTV $pd1 (STV 0.5 1.0))))
      (DistGreaterThanFormula $pd2 1))
   (STV 0.25 0.1176470588235294))

!(test (ParticlePairs (ParticleFromPairs ((170 0.5) (180 0.5)))) ((170 0.5) (180 0.5)))

!(test (ParticlePairs (ParticleFromPairs ((175 1.0)))) ((175 1.0)))

!(test
   (DistGreaterThanDistFormula (ParticleFromPairs ((170 0.5) (180 0.5)))
      (ParticleFromPairs ((175 1.0))))
   (STV 0.5 0.047619047619047616))

!(test
   (DistGreaterThanFormula
      (ParticleMap (|-> ($x) (+ $x 1)) (ParticleFromPairs ((0 0.25) (2 0.75))))
      2)
   (STV 0.75 0.07407407407407407))

!(test
   (DistGreaterThanFormula
      (ParticleMap2 +
         (ParticleFromPairs ((170 0.5) (180 0.5)))
         (ParticleFromPairs ((160 1.0))))
      335)
   (STV 0.5 0.09090909090909091))

!(test
   (DistGreaterThanFormula
      (ParticleMap2 (|-> ($a $b) (/ (+ $a $b) 2))
         (ParticleFromPairs ((180 1.0)))
         (ParticleFromPairs ((160 1.0))))
      169)
   (STV 1.0 0.047619047619047616))

!(compileadd kb
   (: countryHeightA
      (CountryHeightDist countryA (ParticleFromPairs ((170 0.5) (180 0.5))))
      (STV 1.0 1.0)))

!(compileadd kb
   (: countryHeightB (CountryHeightDist countryB (ParticleFromPairs ((175 1.0)))) (STV 1.0 1.0)))

!(compileadd kb
   (: compareHeightsRule
      (Implication
         (Premises
            (CountryHeightDist countryA $heightA)
            (CountryHeightDist countryB $heightB)
            (GreaterThan $heightA $heightB))
         (Conclusions (Taller countryA countryB)))
      (STV 1.0 1.0)))

!(test
   (let (: $prf (Taller countryA countryB) $tv)
      (query 40 kb (: $prf (Taller countryA countryB) $tv))
      (let (STV $s $c) $tv $s))
   0.5)

!(test
   (let (: $prf (Taller countryA countryB) $tv)
      (query 40 kb (: $prf (Taller countryA countryB) $tv))
      (let (STV $s $c) $tv $c))
   0.04285714285714286)

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
         (Premises (Room $room)
            (FoldAllValue (In $room $kid)
               $tvin
               (ParticleFromPairs ((0 1.0)))
               ParticleAddBernoulliFromSTV
               ->
               $dist))
         (Conclusions (CntKidInParticle $room $dist)))
      (STV 1.0 0.8)))

!(compileadd kb
   (: playTogetherParticleRule
      (Implication (Premises (Room $room) (CntKidInParticle $room $cnt) (GreaterThan $cnt 1))
         (Conclusions (PlayTogetherParticleIn $room)))
      (STV 1.0 0.75)))

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (DistGreaterThanFormula $cnt 1)
         (and (and (> $s 0.2499) (< $s 0.2501)) (and (> $c 0.11764) (< $c 0.11765)))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (DistGreaterThanFormula $cnt 1)
         (and (and (> $s 0.0599) (< $s 0.0601)) (and (> $c 0.0977) (< $c 0.0978)))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (and (> $s 0.2499) (< $s 0.2501)) (and (> $c 0.10587) (< $c 0.10589)))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (> $s 0.0599) (< $s 0.0601))))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp1 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp1 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (> $c 0.0)))
   true)

!(test
   (let (: $prf (CntKidInParticle roomp2 $cnt) $tv)
      (query 40 kb (: $prf (CntKidInParticle roomp2 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (> $c 0.0)))
   true)

!(test (progn (ParticleStoreClear) (ParticleStoreCount)) 0)

!(test (progn (ParticleSetBudget 128) (ParticleGetBudget)) 128)

!(test (progn (ParticleSetBudget 512) (ParticleGetBudget)) 512)

!(test
   (progn
      (ParticleFromPairs ((1 0.6) (2 0.4)))
      (ParticleFromPairs ((3 1.0)))
      (ParticleStoreCount))
   3)

!(test (progn (ParticleStorePruneKB) (ParticleStoreCount)) 0)

!(compileadd kb
   (: keptParticleFact
      (CountryHeightDist keepCountry (ParticleFromPairs ((170 0.7) (180 0.3))))
      (STV 1.0 1.0)))

!(test (progn (ParticleFromPairs ((999 1.0))) (ParticleStorePruneKB)) 0)
