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
   (query 100 flyingRavenKb (: $prf (Inheritance Sam (IntSet flies)) $tv))
   ((:
       (inheritance-query
          (total-implication
             ((inheritance-implication birdFlies)
                ((inheritance-implication ravenBird)
                   ((inheritance-implication samRaven) (ctx proof 0))))
             (merge/revision
                ((inheritance-implication birdFlies)
                   ((inheritance-implication ravenBird)
                      ((inheritance-implication samRaven) (ctx proof 1))))
                (negated
                   (penguinsDoNotFly
                      ((inverted (inheritance-implication penguinBird) with
                         (foldall-proof pinguPenguin)
                         (foldall-proof ravenBird penguinBird))
                         ((inheritance-implication ravenBird)
                            ((inheritance-implication samRaven) (ctx proof 1)))))))))
       (Inheritance Sam (IntSet flies))
       (STV 0.9899962492728008 0.9000632064000252))
    (:
       (merge/revision
          ((inheritance-implication birdFlies)
             ((inheritance-implication ravenBird) samRaven))
          (negated
             (penguinsDoNotFly
                ((inverted (inheritance-implication penguinBird) with cpu cpu)
                   ((inheritance-implication ravenBird) samRaven)))))
       (Inheritance Sam (IntSet flies))
       (STV 0.9733353514140296 0.9015950434779885))))

!(test
   (query 5 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: (negated (penguinsDoNotFly pinguPenguin)) (Inheritance Pingu (IntSet flies)) (STV 0.010000000000000009 0.8999910888461915)))

!(test
   (query 20 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: (merge/revision
         ((inheritance-implication birdFlies)
            ((inheritance-implication penguinBird) pinguPenguin))
         (negated (penguinsDoNotFly pinguPenguin)))
      (Inheritance Pingu (IntSet flies))
      (STV 0.500194491277127 0.9473834682774158)))
