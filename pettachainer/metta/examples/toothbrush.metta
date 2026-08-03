!(import! &self ../petta_chainer)

!(set-base-rate toothbrushKb (Inheritance $x madeOfPlastic) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x heated) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x melted) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x pliable) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x screwlike) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x hardened) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Inheritance $x removed) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opLighter) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opReshape) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opWait) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opUnscrew) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (And (Inheritance $x madeOfPlastic) (Operation $x opLighter)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Inheritance $x pliable) (Operation $x opReshape)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Inheritance $x screwlike) (Operation $x opWait)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Inheritance $x hardened) (Operation $x opUnscrew)) (STV 0.25 0.9))

!(compileadd toothbrushKb
   (: lighterHeatsPlastic
      (Implication
         (And (Inheritance $x madeOfPlastic) (Operation $x opLighter))
         (Inheritance $x heated))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: heatedMelts
      (Implication
         (Inheritance $x heated)
         (Inheritance $x melted))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: meltedPliable
      (Implication
         (Inheritance $x melted)
         (Inheritance $x pliable))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: reshapePliableScrewlike
      (Implication
         (And (Inheritance $x pliable) (Operation $x opReshape))
         (Inheritance $x screwlike))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: waitHardensScrewlike
      (Implication
         (And (Inheritance $x screwlike) (Operation $x opWait))
         (Inheritance $x hardened))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: unscrewRemovesHardened
      (Implication
         (And (Inheritance $x hardened) (Operation $x opUnscrew))
         (Inheritance $x removed))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xPlastic (Inheritance X madeOfPlastic) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xWait (Operation X opWait) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

!(test
   (collapse (query 200 toothbrushKb (: $prf (Inheritance X removed) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            ((inheritance-rule-lift unscrewRemovesHardened)
               xUnscrew
               ((inheritance-rule-lift waitHardensScrewlike)
                  xWait
                  ((inheritance-rule-lift reshapePliableScrewlike)
                     xReshape
                     (meltedPliable
                        (heatedMelts
                           ((inheritance-rule-lift lighterHeatsPlastic)
                              xLighter
                              ((inheritance-implication xPlastic)
                                 (ctx proof 0))))))))
            ((inheritance-rule-lift unscrewRemovesHardened)
               xUnscrew
               ((inheritance-rule-lift waitHardensScrewlike)
                  xWait
                  ((inheritance-rule-lift reshapePliableScrewlike)
                     xReshape
                     (meltedPliable
                        (heatedMelts
                           ((inheritance-rule-lift lighterHeatsPlastic)
                              xLighter
                              ((inheritance-implication xPlastic)
                                 (ctx proof 1))))))))))
      (Inheritance X removed)
      (STV 0.8959832714414285 0.9897979854412593))))
