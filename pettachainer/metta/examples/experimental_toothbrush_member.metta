!(import! &self ../petta_chainer)

!(set-base-rate toothbrushMemberKb (Member $x madeOfPlastic) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x heated) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x melted) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x pliable) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x screwlike) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x hardened) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Member $x removed) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Operation $x opLighter) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Operation $x opReshape) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Operation $x opWait) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (Operation $x opUnscrew) (STV 0.5 0.9))
!(set-base-rate toothbrushMemberKb (And (Member $x madeOfPlastic) (Operation $x opLighter)) (STV 0.25 0.9))
!(set-base-rate toothbrushMemberKb (And (Member $x pliable) (Operation $x opReshape)) (STV 0.25 0.9))
!(set-base-rate toothbrushMemberKb (And (Member $x screwlike) (Operation $x opWait)) (STV 0.25 0.9))
!(set-base-rate toothbrushMemberKb (And (Member $x hardened) (Operation $x opUnscrew)) (STV 0.25 0.9))

!(compileadd toothbrushMemberKb
   (: lighterHeatsPlastic
      (Implication
         (Premises (Member $x madeOfPlastic) (Operation $x opLighter))
         (Conclusions (Member $x heated)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: heatedMelts
      (Implication
         (Premises (Member $x heated))
         (Conclusions (Member $x melted)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: meltedPliable
      (Implication
         (Premises (Member $x melted))
         (Conclusions (Member $x pliable)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: reshapePliableScrewlike
      (Implication
         (Premises (Member $x pliable) (Operation $x opReshape))
         (Conclusions (Member $x screwlike)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: waitHardensScrewlike
      (Implication
         (Premises (Member $x screwlike) (Operation $x opWait))
         (Conclusions (Member $x hardened)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: unscrewRemovesHardened
      (Implication
         (Premises (Member $x hardened) (Operation $x opUnscrew))
         (Conclusions (Member $x removed)))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xPlastic (Member X madeOfPlastic) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xWait (Operation X opWait) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

!(test
   (collapse (query 200 toothbrushMemberKb (: $prf (Member X removed) $tv)))
   ((:
      (unscrewRemovesHardened
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
      (Member X removed)
      (STV 0.8959832714414285 0.9896761643809187))))
