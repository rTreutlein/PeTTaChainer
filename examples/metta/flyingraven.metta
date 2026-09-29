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
               (by (inheritance-implication birdFlies) (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 0))))
               (negated
                  (by penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with cpu cpu)
                        (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 0)))))))
            (merge/revision
               (by (inheritance-implication birdFlies) (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 1))))
               (negated
                  (by penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with cpu cpu)
                        (by (inheritance-implication ravenBird) (by (inheritance-implication samRaven) (ctx proof 1)))))))))
      (Inheritance Sam (IntSet flies))
      (STV 0.9786608129080705 0.6432519142192561))))

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
      (STV 0.2159496314302387 0.9195300688996186))))

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
      (STV 0.21808909147712674 0.919737117859771))))
