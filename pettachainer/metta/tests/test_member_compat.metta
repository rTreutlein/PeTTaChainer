!(import! &self petta_chainer)

!(compileadd memberCompatKb (: tomHuman (Member Tom Human) (STV 0.99 0.9)))

!(compileadd memberCompatKb (: humanMortal (Inheritance Human Mortal) (STV 0.8 0.9)))

!(test
   (collapse (query 20 memberCompatKb (: $prf (Member Tom Human) $tv)))
   ((: (merge/revision tomHuman ((member-observation-implication tomHuman) (member-self tomHuman)))
       (Member Tom Human)
       (STV 0.99 0.9473684188306843))))

!(test
   (collapse (query 40 memberCompatKb (: $prf (Member Tom Mortal) $tv)))
   ((: (merge/revision
          ((no_inverse (member-inheritance-implication humanMortal)) tomHuman)
          ((no_inverse (member-inheritance-implication humanMortal))
             (merge/revision tomHuman ((member-observation-implication tomHuman) (member-self tomHuman)))))
       (Member Tom Mortal)
       (STV 0.7920000000000001 0.9459323855588767))))
