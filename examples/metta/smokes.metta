!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd smokesKb
   (: friendSmokingRule
      (Implication
         (And (friend $x $y) (Member $x smokes))
         (Member $y smokes))
      (STV 0.4 0.9)))

!(compileadd smokesKb
   (: smokingCancerRule
      (Implication
         (Member $x smokes)
         (Member $x cancerous))
      (STV 0.6 0.9)))

!(compileadd smokesKb (: friendAnnaBob (friend Anna Bob) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendAnnaEdward (friend Anna Edward) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendAnnaFrank (friend Anna Frank) (STV 1.0 0.9)))

!(compileadd smokesKb
   (: friendEdwardFrank (friend Edward Frank) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendGaryHelen (friend Gary Helen) (STV 1.0 0.9)))

!(compileadd smokesKb
   (: notFriendGaryFrank (friend Gary Frank) (STV 0.0 0.9)))

!(compileadd smokesKb (: smokesAnna (Member Anna smokes) (STV 1.0 0.9)))

!(compileadd smokesKb (: smokesEdward (Member Edward smokes) (STV 1.0 0.9)))

;; Edward smokes, as observed and as Anna's friend: smoking gives cancer at .6.
!(test (query 500 smokesKb (: $prf (Member Edward cancerous) $tv))
   (: (by smokingCancerRule (conditioned smokesAnna (factored-revision (factored-revision (by friendSmokingRule (conjunction friendAnnaEdward (given true))) (prior (STV 0.4000027777017002 0.8999999649826753)) (((antecedent-completion friendSmokingRule 1 with cpu (prior (STV 0.9090909090909091 0.0011237357972281184))) (conjunction friendEdwardFrank (by friendSmokingRule (conjunction friendAnnaFrank (given true))))))) (prior (STV 0.4009072999622268 0.8999324303248188)) (((reported with cpu (prior (STV 0.5 0.0))) smokesEdward))) smokesEdward)) (Member Edward cancerous) (STV 0.6 0.8999999649826753)))
