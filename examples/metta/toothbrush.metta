!(import! &self ../../pettachainer/metta/petta_chainer)

!(set-base-rate toothbrushKb (Member $x madeOfPlastic) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x heated) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x melted) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x pliable) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x screwlike) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x hardened) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Member $x removed) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opLighter) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opReshape) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opWait) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (Operation $x opUnscrew) (STV 0.5 0.9))
!(set-base-rate toothbrushKb (And (Member $x madeOfPlastic) (Operation $x opLighter)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Member $x pliable) (Operation $x opReshape)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Member $x screwlike) (Operation $x opWait)) (STV 0.25 0.9))
!(set-base-rate toothbrushKb (And (Member $x hardened) (Operation $x opUnscrew)) (STV 0.25 0.9))

!(compileadd toothbrushKb
   (: lighterHeatsPlastic
      (Implication
         (And (Member $x madeOfPlastic) (Operation $x opLighter))
         (Member $x heated))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: heatedMelts
      (Implication
         (Member $x heated)
         (Member $x melted))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: meltedPliable
      (Implication
         (Member $x melted)
         (Member $x pliable))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: reshapePliableScrewlike
      (Implication
         (And (Member $x pliable) (Operation $x opReshape))
         (Member $x screwlike))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: waitHardensScrewlike
      (Implication
         (And (Member $x screwlike) (Operation $x opWait))
         (Member $x hardened))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb
   (: unscrewRemovesHardened
      (Implication
         (And (Member $x hardened) (Operation $x opUnscrew))
         (Member $x removed))
      (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xPlastic (Member X madeOfPlastic) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xWait (Operation X opWait) (STV 0.99 0.99)))

!(compileadd toothbrushKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

!(test
   (collapse (query 200 toothbrushKb (: $prf (Member X removed) $tv)))
   ((: (by unscrewRemovesHardened
          (conjunction
             (by waitHardensScrewlike
                (conjunction
                   (by reshapePliableScrewlike
                      (conjunction
                         (by meltedPliable (by heatedMelts (by lighterHeatsPlastic (conjunction xPlastic xLighter))))
                         xReshape))
                   xWait))
             xUnscrew))
       (Member X removed)
       (STV 0.9545435758820499 0.9199224359319048))))
