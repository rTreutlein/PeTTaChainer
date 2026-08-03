!(import! &self ../petta_chainer)

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
                  (by (inheritance-implication smokesEdward) (ctx proof 0))
                  ((inheritance-rule-lift friendSmokingRule)
                     (conjunction friendAnnaEdward smokesAnna)
                     (ctx proof 0))))
            (by smokingCancerRule
               (merge/revision
                  ((inheritance-rule-lift friendSmokingRule)
                     (conjunction friendAnnaEdward smokesAnna)
                     (ctx proof 1))
                  (by (inheritance-implication smokesEdward) (ctx proof 1))))))
      (Inheritance Edward (IntSet cancerous))
      (STV 0.4200001198164605 0.9335532708383407)))
