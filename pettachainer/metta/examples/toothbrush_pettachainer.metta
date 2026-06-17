!(import! &self petta_chainer)

!(compileadd toothbrushKb
   (: lighterHeatsPlastic
      (Implication
         (Premises (Inheritance $x madeOfPlastic) (Operation $x opLighter))
         (Conclusions (Inheritance $x heated)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb
   (: heatedMelts
      (Implication
         (Premises (Inheritance $x heated))
         (Conclusions (Inheritance $x melted)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb
   (: meltedPliable
      (Implication
         (Premises (Inheritance $x melted))
         (Conclusions (Inheritance $x pliable)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb
   (: reshapePliableScrewlike
      (Implication
         (Premises (Inheritance $x pliable) (Operation $x opReshape))
         (Conclusions (Inheritance $x screwlike)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb
   (: waitHardensScrewlike
      (Implication
         (Premises (Inheritance $x screwlike) (Operation $x opWait))
         (Conclusions (Inheritance $x hardened)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb
   (: unscrewRemovesHardened
      (Implication
         (Premises (Inheritance $x hardened) (Operation $x opUnscrew))
         (Conclusions (Inheritance $x removed)))
      (CTV (STV 0.99 0.99) (STV 0.0 1.0))))

!(compileadd toothbrushKb (: xPlastic (Inheritance X madeOfPlastic) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xWait (Operation X opWait) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

!(test
   (query 200 toothbrushKb (: $prf (Inheritance X removed) $tv))
   (: (unscrewRemovesHardened
         (conjunction
            (waitHardensScrewlike
               (conjunction
                  (reshapePliableScrewlike
                     (conjunction
                        (meltedPliable
                           (heatedMelts
                              (lighterHeatsPlastic
                                 (conjunction xPlastic xLighter))))
                        xReshape))
                  xWait))
            xUnscrew))
      (Inheritance X removed)
      (STV 0.8953382542587163 0.99)))
