!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd smokesKb
   (: friendSmokingRule
      (Implication
         (And (Inheritance (Product $x $y) friend) (Inheritance $x (IntSet smokes)))
         (Inheritance $y (IntSet smokes)))
      (STV 0.4 0.9)))

!(compileadd smokesKb
   (: smokingCancerRule
      (Implication
         (Inheritance $x (IntSet smokes))
         (Inheritance $x (IntSet cancerous)))
      (STV 0.6 0.9)))

!(compileadd smokesKb (: friendAnnaBob (Inheritance (Product Anna Bob) friend) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendAnnaEdward (Inheritance (Product Anna Edward) friend) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendAnnaFrank (Inheritance (Product Anna Frank) friend) (STV 1.0 0.9)))

!(compileadd smokesKb
   (: friendEdwardFrank (Inheritance (Product Edward Frank) friend) (STV 1.0 0.9)))

!(compileadd smokesKb (: friendGaryHelen (Inheritance (Product Gary Helen) friend) (STV 1.0 0.9)))

!(compileadd smokesKb
   (: notFriendGaryFrank (Inheritance (Product Gary Frank) friend) (STV 0.0 0.9)))

!(compileadd smokesKb (: smokesAnna (Inheritance Anna (IntSet smokes)) (STV 1.0 0.9)))

!(compileadd smokesKb (: smokesEdward (Inheritance Edward (IntSet smokes)) (STV 1.0 0.9)))

!(test (query 500 smokesKb (: $prf (Inheritance Edward (IntSet cancerous)) $tv))
   (:
      (inheritance-implication-fold
         (total-implication
            (by smokingCancerRule
               (merge/revision
                  ((inheritance-rule-lift friendSmokingRule)
                     (conjunction friendAnnaEdward
                        (factored-revision smokesAnna (prior (STV 0.999986111496903 0.9))
                           ((shared 352
                              ((antecedent-completion friendSmokingRule 1 with cpu
                                  (prior (STV 0.49840637291471407 1.0e-06)))
                                 (conjunction friendAnnaFrank
                                    (by friendSmokingRule (conjunction friendEdwardFrank smokesEdward))))))))
                     (ctx proof 0))
                  (by (inheritance-implication smokesEdward) (ctx proof 0))))
            (by smokingCancerRule
               (merge/revision
                  ((inheritance-rule-lift friendSmokingRule)
                     (conjunction friendAnnaEdward
                        (factored-revision smokesAnna (prior (STV 0.999986111496903 0.9)) ((shared 352))))
                     (ctx proof 1))
                  (by (inheritance-implication smokesEdward) (ctx proof 1))))))
      (Inheritance Edward (IntSet cancerous))
      (STV 0.5699927878862528 0.012197409811813702)))
