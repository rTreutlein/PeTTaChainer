!(import! &self petta_chainer)

!(compileadd flyingRavenKb (: samRaven (Inheritance Sam Raven) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: pinguPenguin (Inheritance Pingu Penguin) (STV 0.99 0.9)))

!(compileadd flyingRavenKb
   (: penguinsDoNotFly
      (Implication
         (Premises (Inheritance $x Penguin))
         (Conclusions (Not (Inheritance $x (IntSet flies)))))
      (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(compileadd flyingRavenKb (: ravenBird (Inheritance Raven Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: penguinBird (Inheritance Penguin Bird) (STV 0.99 0.9)))

!(compileadd flyingRavenKb (: birdFlies (Inheritance Bird (IntSet flies)) (STV 0.99 0.9)))

!(test
   (let $results
      (collapse
         (query 100 flyingRavenKb
            (: $prf (Inheritance Sam (IntSet flies)) $tv)))
      ((length $results) $results))
   (1 ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication ravenBird)
                     ((inheritance-implication samRaven) (ctx proof 0))))
               (negated
                  (penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird) with cpu cpu)
                        ((inheritance-implication ravenBird)
                           ((inheritance-implication samRaven) (ctx proof 0)))))))
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication ravenBird)
                     ((inheritance-implication samRaven) (ctx proof 1))))
               (negated
                  (penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird) with cpu cpu)
                        ((inheritance-implication ravenBird)
                           ((inheritance-implication samRaven) (ctx proof 1)))))))))
      (Inheritance Sam (IntSet flies))
      (STV 0.9636833710183946 0.9020118546940846)))))

!(test
   (let $results
      (collapse
         (query 30 flyingRavenKb
            (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
      ((length $results) $results))
   (1 ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication penguinBird)
                     ((inheritance-implication pinguPenguin) (ctx proof 2))))
               (negated
                  (penguinsDoNotFly
                     ((inheritance-implication pinguPenguin) (ctx proof 2)))))
            (negated
               (penguinsDoNotFly
                  ((inheritance-implication pinguPenguin) (ctx proof 3))))))
      (Inheritance Pingu (IntSet flies))
      (STV 0.49640488254907433 0.9475028689002895)))))

!(test
   (let $results
      (collapse
         (query 100 flyingRavenKb
            (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
      ((length $results) $results))
   (1 ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication penguinBird)
                     ((inheritance-implication pinguPenguin) (ctx proof 4))))
               (negated
                  (penguinsDoNotFly
                     ((inheritance-implication pinguPenguin) (ctx proof 4)))))
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication penguinBird)
                     ((inheritance-implication pinguPenguin) (ctx proof 5))))
               (negated
                  (penguinsDoNotFly
                     ((inheritance-implication pinguPenguin) (ctx proof 5)))))))
      (Inheritance Pingu (IntSet flies))
      (STV 0.49640488254907433 0.9475028689002895)))))
