!(import! &self ../petta_chainer)

!(compileadd mergedSubgoalKb (: smokesAnna (Smokes Anna) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb (: smokesEdward (Smokes Edward) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb (: friendAnnaEdward (Friend Anna Edward) (STV 1.0 0.9)))

!(compileadd mergedSubgoalKb
   (: friendSmokingRule
      (Implication
         (And (Friend $x $y) (Smokes $x))
         (Smokes $y))
      (CTV (STV 0.4 0.9) (STV 0.0 1.0))))

!(compileadd mergedSubgoalKb
   (: smokingCancerRule
      (Implication
         (Smokes $x)
         (Cancerous $x))
      (CTV (STV 0.6 0.9) (STV 0.0 1.0))))

!(test
   (query 40 mergedSubgoalKb (: $prf (Cancerous Edward) $tv))
   (: (smokingCancerRule (merge/revision smokesEdward (friendSmokingRule (conjunction friendAnnaEdward smokesAnna)))) (Cancerous Edward) (STV 0.4200001200414666 0.9338110214376288)))

!(test
   (collapse
      (query 40 mergedSubgoalKb
         (: (merge/revision
               (smokingCancerRule (friendSmokingRule (conjunction friendAnnaEdward smokesAnna)))
               (smokingCancerRule smokesEdward))
            (Cancerous Edward)
            $tv)))
   ())
