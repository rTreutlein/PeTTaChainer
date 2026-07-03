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
   (: (merge/revision
         ((inheritance-implication birdFlies)
            ((inheritance-implication ravenBird) samRaven))
         (negated
            (penguinsDoNotFly
               ((inverted (inheritance-implication penguinBird) with cpu cpu)
                  ((inheritance-implication ravenBird) samRaven)))))
      (Inheritance Sam (IntSet flies))
      (STV 0.9496184978505904 0.9028789486161776)))

!(test
   (query 5 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: (negated (penguinsDoNotFly pinguPenguin)) (Inheritance Pingu (IntSet flies)) (STV 0.010000000000000009 0.8999910888461915)))

!(test
   (query 20 flyingRavenKb (: $prf (Inheritance Pingu (IntSet flies)) $tv))
   (: (merge/revision
         (negated (penguinsDoNotFly pinguPenguin))
         ((inheritance-implication birdFlies)
            ((inheritance-implication penguinBird) pinguPenguin)))
      (Inheritance Pingu (IntSet flies))
      (STV 0.4853151661782535 0.9464291541578685)))
