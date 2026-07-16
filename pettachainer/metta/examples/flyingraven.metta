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

(= (flying-raven-result-tv (: $_proof $_type $tv)) $tv)

!(test
   (let $results
      (collapse
         (query 100 flyingRavenKb
            (: $prf (Inheritance Sam (IntSet flies)) $tv)))
      ((length $results) (map-flat flying-raven-result-tv $results)))
   (1 ((STV 0.9718209275303599 0.948065079226267))))

!(test
   (let $results
      (collapse
         (query 5 flyingRavenKb
            (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
      ((length $results) (map-flat flying-raven-result-tv $results)))
   (1 ((STV 0.010000000000000009 0.8999910888461915))))

!(test
   (let $results
      (collapse
         (query 20 flyingRavenKb
            (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
      ((length $results) (map-flat flying-raven-result-tv $results)))
   (1 ((STV 0.500194491277127 0.9473834682774158))))
