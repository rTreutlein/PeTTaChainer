!(import! &self petta_chainer)

!(add-atom &kb (: kb prf (Count A 1) (STV 1.0 1.0)))
!(add-atom &kb (: kb prf (Count B 2) (STV 1.0 1.0)))
!(add-atom &kb (: kb prf (Count C 3) (STV 1.0 1.0)))

(= (AddCount $acc (Count $name $n)) (+ $acc $n))
(= (KeepAcc $acc $elem) $acc)

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
    (> (size-atom (collapse (query (fromNumber 10) kb (: $prf (Count C 3) $tv)))) 0)
    True)

!(compileadd kb (: foldRule
    (Implication
        (Premises
            (FoldAll (Count $name $n) 0 AddCount -> $total))
        (Conclusions
            (Count Total $total)))
    (STV 1.0 1.0)))

!(test
    (> (size-atom (collapse (query (fromNumber 10) kb (: $prf (Count Total 6) $tv)))) 0)
    True)

!(compileadd kb (: foldZeroRule
    (Implication
        (Premises
            (FoldAll (NoFact $x) 42 KeepAcc -> $total))
        (Conclusions
            (Count MissingTotal $total)))
    (STV 1.0 1.0)))

!(test
    (> (size-atom (collapse (query (fromNumber 10) kb (: $prf (Count MissingTotal 42) $tv)))) 0)
    True)
