!(import! &self ../petta_chainer)

!(compileadd kb (: prfA (Score A 1) (STV 1.0 1.0)))
!(compileadd kb (: prfB (Score B 2) (STV 1.0 1.0)))
!(compileadd kb (: prfC (Score C 3) (STV 1.0 1.0)))

!(compileadd kb (: sampleA (XYZSample (Pair (XY 10.0 100.0) 20.0)) (STV 1.0 1.0)))
!(compileadd kb (: sampleB (XYZSample (Pair (XY 10.0 100.0) 21.0)) (STV 1.0 1.0)))
!(compileadd kb (: seed1 (Seed (Pair alpha 1)) (STV 1.0 1.0)))
!(compileadd kb (: seed2 (Seed (Pair beta 2)) (STV 1.0 1.0)))
!(compileadd kb
   (: seedRule
      (Implication
         (Seed $p)
         (PairFact $p))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let (: $proof (FoldAll $pattern $extractor $init $_fold-function -> $total) $tv)
      (car-atom
         (collapse
            (query 30 kb
               (: $prf
                  (FoldAll (Score $name $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $result)
                  $query-tv))))
      ($proof $pattern $extractor $init $total $tv))
   ((foldall-proof prfA prfB prfC)
      (Score $_name $_n) $_n 0 6 (STV 1.0 1.0)))

!(test
   (collapse
      (query 30 kb
         (: $prf
            (FoldAll (XYZSample (Pair $xy $z))
               (Pair $xy $z)
               (PairCounts ())
               DistValueCountAcc
               ->
               $counts)
            $tv)))
   ((: (foldall-proof sampleA sampleB)
       (FoldAll (XYZSample (Pair $_xy $_z)) (Pair $_xy $_z) (PairCounts ()) DistValueCountAcc -> (PairCounts (((Pair (XY 10.0 100.0) 20.0) 1.0) ((Pair (XY 10.0 100.0) 21.0) 1.0))))
       (STV 1.0 1.0))))

!(test
   (collapse
      (query 30 kb
         (: $prf
            (FoldAll (PairFact $p)
               $p
               (PairCounts ())
               DistValueCountAcc
               ->
               $counts)
            $tv)))
   ((: (foldall-proof (by seedRule seed1) (by seedRule seed2))
       (FoldAll (PairFact $_p) $_p (PairCounts ()) DistValueCountAcc -> (PairCounts (((Pair alpha 1) 1.0) ((Pair beta 2) 1.0))))
       (STV 1.0 1.0))))
