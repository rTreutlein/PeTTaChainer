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
               ((inheritance-implication birdFlies)
                  ((inheritance-implication ravenBird)
                     ((inheritance-implication samRaven) (ctx proof 0))))
               (negated
                  (penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with (foldall-proof pinguPenguin)
                              (foldall-proof ravenBird penguinBird))
                        ((inheritance-implication ravenBird)
                           ((inheritance-implication samRaven) (ctx proof 0)))))))
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication ravenBird)
                     ((inheritance-implication samRaven) (ctx proof 1))))
               (negated
                  (penguinsDoNotFly
                     ((inverted (inheritance-implication penguinBird)
                         with (foldall-proof pinguPenguin)
                              (foldall-proof ravenBird penguinBird))
                        ((inheritance-implication ravenBird)
                           ((inheritance-implication samRaven) (ctx proof 1)))))))))
      (Inheritance Sam (IntSet flies))
      (STV 0.9636833710184354 0.902011854694304))))

!(test
   (collapse
      (query 60 flyingRavenKb
         (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication penguinBird)
                     ((inheritance-implication pinguPenguin) (ctx proof 2))))
               (negated
                  (penguinsDoNotFly
                     ((inheritance-implication pinguPenguin) (ctx proof 2)))))
            (merge/revision
               ((inheritance-implication birdFlies)
                  ((inheritance-implication penguinBird)
                     ((inheritance-implication pinguPenguin) (ctx proof 3))))
               (negated
                  (penguinsDoNotFly
                     ((inheritance-implication pinguPenguin) (ctx proof 3)))))))
      (Inheritance Pingu (IntSet flies))
      (STV 0.49640488254968673 0.9475028689003524))))

!(test
   (collapse
      (query 200 flyingRavenKb
         (: $prf (Inheritance Pingu (IntSet flies)) $tv)))
   ((:
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
      (STV 0.49640488254968673 0.9475028689003524))))
