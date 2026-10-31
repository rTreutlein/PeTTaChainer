!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

!(compileadd foldMergedKb (: directScore (Score a 1) (STV 0.8 0.5)))

!(compileadd foldMergedKb (: qFact (Q a) (STV 1.0 0.9)))

!(compileadd foldMergedKb
   (: qToScore
      (Implication
         (Q $x)
         (Score $x 1))
      (CTV (STV 0.4 0.9) (STV 0.0 1.0))))

!(test
   (let (: (node (conjunction qFact directScore (by qToScore cpu))) (Score a 1) (STV $posterior-s $posterior-c)) (query 100 foldMergedKb (: $prf (Score a 1) $tv)) (posterior-tv-near? 0.7263226058748102 0.8321481456356352 (STV $posterior-s $posterior-c)))
   true)

!(test
   (let (: $proof (FoldAll $pattern $extractor $init $_fold-function -> $total) $tv)
      (car-atom
         (collapse
            (query 100 foldMergedKb
               (: $prf
                  (FoldAll (Score $x $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $result)
                  $query-tv))))
      ($proof $pattern $extractor $init $total $tv))
   ((foldall-proof (factored-revision (by qToScore qFact) (prior (STV 0.4 0.8999999399792307)) (((reported with cpu (prior (STV 0.5 0.0))) directScore))))
      (Score $_x $_n) $_n 0 1 (STV 1.0 1.0)))
