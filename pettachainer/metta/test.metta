!(import! &self petta_chainer)

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

(= (KeepAcc $acc $elem) $acc)

!(compileadd kb (: foldRule
    (Implication
        (Premises
            (FoldAll (Score $name $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total))
        (Conclusions
            (ScoreTotal $total)))
    (STV 1.0 1.0)))

!(test
    (not (==
           (is-member (: (foldRule cpu) (ScoreTotal 6) (STV 1.0 1.0))
                      (collapse (query 10 kb (: $prf (ScoreTotal $x) $tv))))
           ()))
    true)

!(compileadd kb (: foldZeroRule
    (Implication
        (Premises
            (FoldAll (NoFact $x) $x 42 KeepAcc -> $total))
        (Conclusions
            (Count MissingTotal $total)))
    (STV 1.0 1.0)))

!(test
    (not (==
           (is-member (: (foldZeroRule cpu) (Count MissingTotal 42) (STV 1.0 1.0))
                      (collapse (query 10 kb (: $prf (Count MissingTotal $x) $tv))))
           ()))
    true)

!(compileadd kb (: numFromCount
    (Implication
        (Premises
            (Count $name $n)
            (Compute NotEqual ($name MissingTotal) -> True))
        (Conclusions
            (Num $n)))
    (STV 1.0 1.0)))

!(compileadd kb (: foldDerivedRule
    (Implication
        (Premises
            (FoldAll (Num $n) $n 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total))
        (Conclusions
            (DerivedTotal $total)))
    (STV 1.0 1.0)))

!(test
    (not (==
           (is-member (: (foldDerivedRule cpu) (DerivedTotal 6) (STV 1.0 1.0))
                      (collapse (query 10 kb (: $prf (DerivedTotal $x) $tv))))
           ()))
    true)

!(compileadd kb (: dogsInHouseRule
    (Implication
        (Premises
            (House $h)
            (FoldAll (And (PartOf $room $h) (Cardinality (DogsIn $room) $n)) $n 0 (|-> ($acc $x) (+ $acc $x)) -> $total))
        (Conclusions
            (Cardinality (DogsIn $h) $total)))
    (STV 1.0 1.0)))

!(test
    (not (==
           (is-member (: (dogsInHouseRule (conjunction prf1 cpu)) (Cardinality (DogsIn house1) 5) (STV 1.0 1.0))
                      (collapse (query 20 kb (: $prf (Cardinality (DogsIn house1) 5) $tv))))
           ()))
    true)

!(compileadd kb (: apbisc
    (Implication
        (Premises
            (Count A $a)
            (Count B $b)
            (Compute + ($a $b) -> $c))
        (Conclusions
            (Count C $c)))
    (STV 1.0 1.0)))

!(test
    (not (==
           (is-member (: prf (Count C 3) (STV 1.0 1.0))
                      (collapse (query 10 kb (: prf (Count C $x) $tv))))
           ()))
    true)
