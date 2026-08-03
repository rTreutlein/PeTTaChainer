!(import! &self ../petta_chainer)

!(compileadd kb (: prf (Count A 1) (STV 1.0 1.0)))

!(compileadd kb (: prf (Count B 2) (STV 1.0 1.0)))

!(compileadd kb (: prf (Count C 3) (STV 1.0 1.0)))

!(compileadd kb (: prf (Score A 1) (STV 1.0 1.0)))

!(compileadd kb (: prf (Score B 2) (STV 1.0 1.0)))

!(compileadd kb (: prf (Score C 3) (STV 1.0 1.0)))

!(compileadd kb (: prf1 (House house1) (STV 1.0 1.0)))

!(compileadd kb (: prf2 (Room room1) (STV 1.0 1.0)))

!(compileadd kb (: prf3 (Room room2) (STV 1.0 1.0)))

!(compileadd kb (: prf4 (PartOf room1 house1) (STV 1.0 1.0)))

!(compileadd kb (: prf5 (PartOf room2 house1) (STV 1.0 1.0)))

!(compileadd kb (: prf6 (Cardinality (RoomOf house1) 2) (STV 1.0 1.0)))

!(compileadd kb (: prf7 (Contains room1 dogs) (STV 1.0 1.0)))

!(compileadd kb (: prf8 (Cardinality (DogsIn room1) 2) (STV 1.0 1.0)))

!(compileadd kb (: prf9 (Contains room2 dogs) (STV 1.0 1.0)))

!(compileadd kb (: prf10 (Cardinality (DogsIn room2) 3) (STV 1.0 1.0)))

(: KeepAcc (-[det]-> $acc $elem $acc))
(= (KeepAcc $acc $_elem) $acc)

!(compileadd kb
   (: foldRule
      (Implication (FoldAll (Score $name $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total)
         (ScoreTotal $total))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let (cons $_only ())
      (collapse
         (mm2compile kb
            (: foldRule
               (Implication
                  (FoldAll (Score $name $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total)
                  (ScoreTotal $total))
               (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
      1)
   1)

!(test
   (match rules
      (runtime-rule-row $id $ccls $args)
      (if (= $ccls (: (kb $ctx $vars) (by foldRule cpu) (ScoreTotal $total) $tv))
         (if (= $args
                  ((CPU FoldAllCompiled $call $total)
                   (CPU CTVModusPonensFormula
                      ((STV 1.0 1.0)
                       (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
                      $tv)))
            ok
            (empty))
         (empty)))
   ())

!(test
   (match rules
      (runtime-rule-row $id $ccls $args)
      (if (= $ccls (: (kb $ctx $vars) (by foldRule $prem) (ScoreTotal $total) $tv))
         (if (= $args
                  ((: $_kb $_prf
                      (CPU FoldAllCompiled $call $total)
                      $_cpu-tv)
                   (CPU CTVModusPonensFormula
                      ($_cpu-tv
                       (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
                      $tv)))
            bad
            (empty))
         (empty)))
   ())

!(test (query 30 kb (: $prf (ScoreTotal $x) $tv))
   (: (by foldRule (foldall-proof prf prf prf)) (ScoreTotal 6) (STV 1.0 0.9998000399670116)))

!(compileadd kb
   (: foldZeroRule
      (Implication (FoldAll (NoFact $x) $x 42 KeepAcc -> $total)
         (Count MissingTotal $total))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 10 kb (: $prf (Count MissingTotal $x) $tv))
   (: (by foldZeroRule cpu) (Count MissingTotal 42) (STV 1.0 0.9998000399670116)))

!(compileadd kb
   (: foldValueShapeRule
      (Implication
         (FoldAllValue (Score $name $n)
               (ParticleFromPairs ((0 1.0)))
               ParticleAddBernoulliFromSTV
               ->
               $dist)
         (ScoreDist $dist))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (match rules
      (runtime-rule-row $id $ccls $args)
      (if (= $ccls
               (: (kb $ctx $vars)
                  (by foldValueShapeRule cpu)
                  (ScoreDist $dist)
                  $tv))
         (if (= $args
                  ((CPU FoldAllCompiled $call $dist)
                   (CPU CTVModusPonensFormula
                      ((STV 1.0 1.0)
                       (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
                      $tv)))
            ok
            (empty))
         (empty)))
   ())

!(compileadd kb
   (: avgShapeRule
      (Implication (AverageDist (ScoreDistSrc $name $srcDist) $srcDist -> $avgDist)
         (AvgScoreDist $avgDist))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (match rules
      (runtime-rule-row $id $ccls $args)
      (if (= $ccls
               (: (kb $ctx $vars)
                  (by avgShapeRule cpu)
                  (AvgScoreDist $avgDist)
                  $tv))
         (if (= $args
                  ((CPU FoldAllCompiled $call $avgDist)
                   (CPU CTVModusPonensFormula
                      ((STV 1.0 1.0)
                       (CTV (STV 1.0 1.0) (STV 0.0 1.0)))
                      $tv)))
            ok
            (empty))
         (empty)))
   ())

!(compileadd kb
   (: numFromCount
      (Implication (And (Count $name $n) (Compute NotEqual ($name MissingTotal) -> True))
         (Num $n))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (match rules
      (runtime-rule-row $id $ccls $args)
      (if (= $ccls
               (: (kb MAIN Nil)
                  (conjunction $fact-prf cpu)
                  (And (Count $name $n)
                       (CPU NotEqual ($name MissingTotal) true))
                  $tv))
         (if (= $args
                  ((: (kb MAIN Nil) $fact-prf
                      (Count $name $n) $count-tv)
                   (CPU NotEqual ($name MissingTotal) true)
                   (CPU AndFormula
                      ($count-tv (STV 1.0 1.0)) $tv)))
            ok
            (empty))
         (empty)))
   ())

!(compileadd kb
   (: foldDerivedRule
      (Implication (FoldAll (Num $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total)
         (DerivedTotal $total))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 kb (: $prf (DerivedTotal $x) $tv))
   (: (by foldDerivedRule (foldall-proof (by numFromCount (conjunction prf cpu)) (by numFromCount (conjunction prf cpu)) (by numFromCount (conjunction prf cpu)))) (DerivedTotal 6) (STV 1.0 0.9998000399670116)))

!(compileadd kb
   (: dogsInHouseRule
      (Implication
         (And (House $h)
            (FoldAll (And (PartOf $room $h) (Cardinality (DogsIn $room) $n))
               $n
               0
               (|-> ($acc $x) (+ $acc $x))
               ->
               $total))
         (Cardinality (DogsIn $h) $total))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 30 kb (: $prf (Cardinality (DogsIn house1) $x) $tv))
   (: (by dogsInHouseRule (conjunction prf1 (foldall-proof (conjunction prf5 prf10) (conjunction prf4 prf8)))) (Cardinality (DogsIn house1) 5) (STV 1.0 0.999700089898053)))

!(compileadd kb
   (: apbisc (Implication (And (Count A $a) (Count B $b) (Compute + ($a $b) -> $c)) (Count C $c)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 10 kb (: prf (Count C $x) $tv)) (: prf (Count C 3) (STV 1.0 1.0)))
