!(import! &self petta_chainer)

!(test
   (ParticlePairs (ParticleAddBernoulliFromSTV (ParticleFromPairs ((0 1.0))) (STV 0.5 1.0)))
   ((0 0.5) (1 0.5)))

!(test
   (DistGreaterThanFormula (ParticleFromPairs ((0.1 0.25) (2.5 0.75))) 1.0)
   (STV 0.75 0.07407407407407407))

!(compileadd kb (: kid1 (Kid kid1) (STV 1.0 1.0)))

!(compileadd kb (: kid2 (Kid kid2) (STV 1.0 1.0)))

!(compileadd kb (: room1 (Room room1) (STV 1.0 1.0)))

!(compileadd kb (: room2 (Room room2) (STV 1.0 1.0)))

!(compileadd kb (: in11 (In room1 kid1) (STV 0.5 1.0)))

!(compileadd kb (: in12 (In room1 kid2) (STV 0.5 1.0)))

!(compileadd kb (: in21 (In room2 kid1) (STV 0.2 1.0)))

!(compileadd kb (: in22 (In room2 kid2) (STV 0.3 1.0)))

!(compileadd kb
   (: cntKidInRule
      (Implication
         (Premises (Room $room)
            (FoldAllValue (In $room $kid)
               $tvin
               (ParticleFromPairs ((0 1.0)))
               ParticleAddBernoulliFromSTV
               ->
               $dist))
         (Conclusions (CntKidIn $room $dist)))
      (STV 1.0 0.8)))

!(compileadd kb
   (: playTogetherRule
      (Implication (Premises (Room $room) (CntKidIn $room $cnt) (GreaterThan $cnt 1))
         (Conclusions (PlayTogetherIn $room)))
      (STV 1.0 0.75)))

!(test
   (let (: $prf (CntKidIn room1 $cnt) $tv) (query 40 kb (: $prf (CntKidIn room1 $cnt) $tv))
      (let (($k0 $v0) ($k1 $v1) ($k2 $v2)) (ParticlePairs $cnt)
         (and (== $k0 0)
            (and (== $k1 1)
               (and (== $k2 2)
                  (and (and (> $v0 0.2499) (< $v0 0.2501))
                     (and (and (> $v1 0.4999) (< $v1 0.5001)) (and (> $v2 0.2499) (< $v2 0.2501)))))))))
   true)

!(test
   (let (: $prf (CntKidIn room2 $cnt) $tv) (query 40 kb (: $prf (CntKidIn room2 $cnt) $tv))
      (let (($k0 $v0) ($k1 $v1) ($k2 $v2)) (ParticlePairs $cnt)
         (and (== $k0 0)
            (and (== $k1 1)
               (and (== $k2 2)
                  (and (and (> $v0 0.5599) (< $v0 0.5601))
                     (and (and (> $v1 0.3799) (< $v1 0.3801)) (and (> $v2 0.0599) (< $v2 0.0601)))))))))
   true)

!(test
   (let (: $prf (CntKidIn room1 $cnt) $tv) (query 40 kb (: $prf (CntKidIn room1 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (and (> $s 0.2499) (< $s 0.2501)) (and (> $c 0.10587) (< $c 0.10589)))))
   true)

!(test
   (let (: $prf (CntKidIn room2 $cnt) $tv) (query 40 kb (: $prf (CntKidIn room2 $cnt) $tv))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (and (> $s 0.0599) (< $s 0.0601)) (and (> $c 0.08795) (< $c 0.08797)))))
   true)
