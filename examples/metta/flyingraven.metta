!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd flyingRavenKb (: samRaven (Inheritance Sam Raven) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: pinguPenguin (Inheritance Pingu Penguin) (STV 0.99 0.9)))

!(compileadd flyingRavenKb
   (: penguinsDoNotFly
      (Implication
         (Inheritance $x Penguin)
         (Not (Inheritance $x (IntSet flies))))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd flyingRavenKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: birdFlies (Inheritance Bird (IntSet flies)) (STV 0.99 0.9)))

;; Inheritance queries use one chainer execution.  These budgets preserve the
;; total search work that was previously split across two equal executions.
!(test
   (collapse
      (query 200 flyingRavenKb
         (: $prf (Inheritance Sam (IntSet flies)) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               (by (inheritance-implication birdFlies)
                  (shared 40 (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 0)))))
               (negated
                  (by penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with cpu (prior (STV 0.730917365761377 0.00022594893654011704)))
                        (shared 40)))))
            (merge/revision
               (negated
                  (by penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with cpu (prior (STV 0.730917365761377 0.00022594893654011704)))
                        (shared 44 (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 1)))))))
               (by (inheritance-implication birdFlies) (shared 44)))))
      (Inheritance Sam (IntSet flies))
      (STV 0.9786915594444334 0.6432516834702312))))

!(test
   (collapse
      (query 60 flyingRavenKb
         (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               (negated
                  (by penguinsDoNotFly
                     (by (inheritance-implication pinguPenguin) (ctx proof 2))))
               (by (inheritance-implication birdFlies) (by (inheritance-implication penguinBird) (by (inheritance-implication pinguPenguin) (ctx proof 2)))))
            (merge/revision
               (by (inheritance-implication birdFlies) (by (inheritance-implication penguinBird) (by (inheritance-implication pinguPenguin) (ctx proof 3))))
               (negated
                  (by penguinsDoNotFly
                     (by (inheritance-implication pinguPenguin) (ctx proof 3)))))))
      (Inheritance Pingu (IntSet flies))
      (STV 0.1716914028326094 0.9152685473572055))))

!(test
   (collapse
      (query 200 flyingRavenKb
         (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               (negated
                  (by penguinsDoNotFly
                     (by (inheritance-implication pinguPenguin) (ctx proof 4))))
               (by (inheritance-implication birdFlies) (by (inheritance-implication penguinBird) (by (inheritance-implication pinguPenguin) (ctx proof 4)))))
            (merge/revision
               (by (inheritance-implication birdFlies) (by (inheritance-implication penguinBird) (by (inheritance-implication pinguPenguin) (ctx proof 5))))
               (negated
                  (by penguinsDoNotFly
                     (by (inheritance-implication pinguPenguin) (ctx proof 5)))))))
      (Inheritance Pingu (IntSet flies))
      (STV 0.1716914028326094 0.9152685473572055))))
