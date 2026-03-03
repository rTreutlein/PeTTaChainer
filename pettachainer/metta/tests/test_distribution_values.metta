!(import! &self petta_chainer)

!(test (NatDistAddBernoulliFromSTV (NatDist ((0 1.0))) (STV 0.5 1.0)) (NatDist ((0 0.5) (1 0.5))))

!(test (DistGreaterThanFormula (FloatDist ((0.1 0.25) (2.5 0.75))) 1.0) (STV 0.75 1.0))

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
               (NatDist ((0 1.0)))
               NatDistAddBernoulliFromSTV
               ->
               $dist))
         (Conclusions (CntKidIn $room)))
      (STV 1.0 0.8)))

!(compileadd kb
   (: playTogetherRule
      (Implication (Premises (Room $room) (GreaterThan (CntKidIn $room) 1))
         (Conclusions (PlayTogetherIn $room)))
      (STV 1.0 0.75)))

!(test
   (let (: $prf (CntKidIn room1) $tv) (query 40 kb (: $prf (CntKidIn room1) $tv))
      (let (NatDist (($k0 $v0) ($k1 $v1) ($k2 $v2))) $tv
         (and (== $k0 0)
            (and (== $k1 1)
               (and (== $k2 2)
                  (and (and (> $v0 0.1999) (< $v0 0.2001))
                     (and (and (> $v1 0.3999) (< $v1 0.4001)) (and (> $v2 0.1999) (< $v2 0.2001)))))))))
   true)

!(test
   (let (: $prf (CntKidIn room2) $tv) (query 40 kb (: $prf (CntKidIn room2) $tv))
      (let (NatDist (($k0 $v0) ($k1 $v1) ($k2 $v2))) $tv
         (and (== $k0 0) (and (== $k1 1) (and (== $k2 2) (and (> $v2 0.0479) (< $v2 0.0481)))))))
   true)

!(test
   (let (: $prf (CntKidIn room1) $cnt) (query 40 kb (: $prf (CntKidIn room1) $cnt))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (and (> $s 0.1999) (< $s 0.2001)) (and (> $c 0.7499) (< $c 0.7501)))))
   true)

!(test
   (let (: $prf (CntKidIn room2) $cnt) (query 40 kb (: $prf (CntKidIn room2) $cnt))
      (let (STV $s $c) (MpFormula (STV 1.0 0.75) (DistGreaterThanFormula $cnt 1))
         (and (and (> $s 0.0479) (< $s 0.0481)) (and (> $c 0.7499) (< $c 0.7501)))))
   true)
