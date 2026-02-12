!(import! &self petta_chainer)

!(compileadd kb (: d1 (Dog fido) (STV 1.0 0.5)))
!(compileadd kb (: t1 (HasTail fido) (STV 1.0 0.5)))

!(match &kb $a $a)

!(test
    (match &kb (ind-impl-stats kb Dog HasTail $a $b) (ind-impl-stats kb Dog HasTail $a $b))
    (ind-impl-stats kb Dog HasTail 0.5 0.0))

!(test
    (match &kb (ind-impl-stats kb HasTail Dog $a $b) (ind-impl-stats kb HasTail Dog $a $b))
    (ind-impl-stats kb HasTail Dog 0.5 0.0))

!(test
    (match &kb
           (rules ($args |- (: (kb MAIN ()) ((mined_implication Dog HasTail) $p) (HasTail $x) $tv)))
           ok)
    ok)

!(test
    (match &kb
           (rules ($args |- (: (kb MAIN ()) ((mined_implication HasTail Dog) $p) (Dog $x) $tv)))
           ok)
    ok)

!(compileadd kb (: d2 (Dog spot) (STV 1.0 0.5)))
!(compileadd kb (: t2 (HasTail spot) (STV 0.0 0.5)))

!(test
    (match &kb (ind-impl-stats kb Dog HasTail $a $b) (ind-impl-stats kb Dog HasTail $a $b))
    (ind-impl-stats kb Dog HasTail 0.5 0.5))

!(test
    (match &kb (ind-impl-stats kb HasTail Dog $a $b) (ind-impl-stats kb HasTail Dog $a $b))
    (ind-impl-stats kb HasTail Dog 0.5 0.0))

!(compileadd kb (: p1 (Parent alice bob) (STV 1.0 0.5)))
!(compileadd kb (: l1 (Likes alice bob) (STV 1.0 0.5)))
!(compileadd kb (: p2 (Parent alice carol) (STV 1.0 0.5)))
!(compileadd kb (: l2 (Likes alice dave) (STV 0.0 0.5)))

!(test
    (match &kb (ind-impl-stats kb Parent Likes $a $b) (ind-impl-stats kb Parent Likes $a $b))
    (ind-impl-stats kb Parent Likes 0.5 0.0))

!(match &kb $a $a)
