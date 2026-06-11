!(import! &self petta_chainer)

!(compileadd mergedSubgoalKb (: smokesAnna (Smokes Anna) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb (: smokesEdward (Smokes Edward) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb (: friendAnnaEdward (Friend Anna Edward) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb
   (: friendSmokingRule
      (Implication
         (Premises (Friend $x $y) (Smokes $x))
         (Conclusions (Smokes $y)))
      (CTV (STV 0.4 0.9) (STV 0.0 1.0))))

!(compileadd mergedSubgoalKb
   (: smokingCancerRule
      (Implication
         (Premises (Smokes $x))
         (Conclusions (Cancerous $x)))
      (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

!(test
   (query 40 mergedSubgoalKb (: $prf (Cancerous Edward) $tv))
   (: (smokingCancerRule
         (merge/revision smokesEdward (friendSmokingRule (conjunction friendAnnaEdward smokesAnna))))
      (Cancerous Edward)
      (STV 0.42000000000000004 0.9142105263157896)))

!(test
   (collapse
      (query 40 mergedSubgoalKb
         (: (merge/revision
               (smokingCancerRule (friendSmokingRule (conjunction friendAnnaEdward smokesAnna)))
               (smokingCancerRule smokesEdward))
            (Cancerous Edward)
            $tv)))
   ())
