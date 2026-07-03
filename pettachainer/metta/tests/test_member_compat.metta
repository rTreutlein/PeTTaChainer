!(import! &self petta_chainer)

!(compileadd memberCompatKb (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd memberCompatKb (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(test
   (collapse (query 20 memberCompatKb (: $prf (Member Tom Human) $tv)))
   ((: tomHuman
       (Member Tom Human)
       (STV 0.99 0.9))))

!(test
   (collapse (query 40 memberCompatKb (: $prf (Member Tom Mortal) $tv)))
   ((: ((no_inverse (member-inheritance-implication humanMortal)) tomHuman)
       (Member Tom Mortal)
       (STV 0.792 0.9008662163590345))))

!(set-universe-size memberClosedKb 1.0)

!(compileadd memberClosedKb (: tomHumanClosed (Member Tom Human) (STV 1.0 1.0)))
!(compileadd memberClosedKb (: tomMortalClosed (Member Tom Mortal) (STV 0.8 1.0)))

!(test
   (query 40 memberClosedKb (: $prf (Inheritance Human Mortal) $tv))
   (: (member-inheritance-fold cpu) (Inheritance Human Mortal) (STV 0.8 1.0)))
