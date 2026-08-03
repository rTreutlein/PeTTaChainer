!(import! &self ../petta_chainer)

!(compileadd foldMergedKb (: directScore (Score a 1) (STV 0.8 0.5)))

!(compileadd foldMergedKb (: qFact (Q a) (STV 1.0 0.9)))

!(compileadd foldMergedKb
   (: qToScore
      (Implication
         (Q $x)
         (Score $x 1))
      (CTV (STV 0.4 0.9) (STV 0.0 1.0))))

!(test
   (query 100 foldMergedKb (: $prf (Score a 1) $tv))
   (: (merge/revision (qToScore qFact) directScore) (Score a 1) (STV 0.44000002400830773 0.9090908594869702)))

!(test
   (let (: $proof (FoldAll $pattern $extractor $init $_fold-function -> $total) $tv)
      (car-atom
         (collapse
            (query 100 foldMergedKb
               (: $prf
                  (FoldAll (Score $x $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $result)
                  $query-tv))))
      ($proof $pattern $extractor $init $total $tv))
   ((foldall-proof (merge/revision (qToScore qFact) directScore))
      (Score $_x $_n) $_n 0 1 (STV 1.0 1.0)))
