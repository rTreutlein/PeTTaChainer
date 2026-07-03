!(import! &self petta_chainer)

!(compileadd smokesKb
   (: friendSmokingRule
      (Implication
         (Premises (Inheritance (Product $x $y) friend) (Inheritance $x (IntSet smokes)))
         (Conclusions (Inheritance $y (IntSet smokes))))
      (STV 0.4 0.9)))

!(compileadd smokesKb
   (: smokingCancerRule
      (Implication
         (Premises (Inheritance $x (IntSet smokes)))
         (Conclusions (Inheritance $x (IntSet cancerous))))
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

!(test (query 120 smokesKb (: $prf (Inheritance Edward (IntSet cancerous)) $tv))
   ((:
       (inheritance-query
          (total-implication
             (smokingCancerRule ((inheritance-implication smokesEdward) (ctx proof 0)))
             (smokingCancerRule ((inheritance-implication smokesEdward) (ctx proof 1)))))
       (Inheritance Edward (IntSet cancerous))
       (STV 0.6 0.8999998649685298))
    (:
       (smokingCancerRule
          (merge/revision smokesEdward (friendSmokingRule (conjunction friendAnnaEdward smokesAnna))))
       (Inheritance Edward (IntSet cancerous))
       (STV 0.420000270059802 0.9335532386144167))))
