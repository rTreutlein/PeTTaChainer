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
         (And (Member $x madeOfPlastic) (Operation $x opLighter))
         (Member $x heated))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: heatedMelts
      (Implication
         (Member $x heated)
         (Member $x melted))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: meltedPliable
      (Implication
         (Member $x melted)
         (Member $x pliable))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: reshapePliableScrewlike
      (Implication
         (And (Member $x pliable) (Operation $x opReshape))
         (Member $x screwlike))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: waitHardensScrewlike
      (Implication
         (And (Member $x screwlike) (Operation $x opWait))
         (Member $x hardened))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb
   (: unscrewRemovesHardened
      (Implication
         (And (Member $x hardened) (Operation $x opUnscrew))
         (Member $x removed))
      (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xPlastic (Member X madeOfPlastic) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xLighter (Operation X opLighter) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xReshape (Operation X opReshape) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xWait (Operation X opWait) (STV 0.99 0.99)))

!(compileadd toothbrushMemberKb (: xUnscrew (Operation X opUnscrew) (STV 0.99 0.99)))

!(test
   (collapse (query 200 toothbrushMemberKb (: $prf (Member X removed) $tv)))
   ((:
      (by unscrewRemovesHardened
         (conjunction
            (by waitHardensScrewlike
               (conjunction
                  (by reshapePliableScrewlike
                     (conjunction
                        (by meltedPliable
                           (by heatedMelts
                              (by lighterHeatsPlastic
                                 (conjunction xPlastic xLighter))))
                        xReshape))
                  xWait))
            xUnscrew))
      (Member X removed)
      (STV 0.9545210821747951 0.9198975829739933))))
