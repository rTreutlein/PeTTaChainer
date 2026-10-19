!(import! &self ../../pettachainer/metta/petta_chainer)

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
   (:
      (by
         smokingCancerRule
         (factored-revision
            (by friendSmokingRule (conjunction friendAnnaEdward smokesAnna))
            (prior (STV 0.4 0.8999998799584694))
            (((reported with cpu (prior (STV 0.5 0.0))) smokesEdward))))
      (Cancerous Edward)
      (STV 0.6 0.8999998649689053)))

!(test
   (collapse
      (query 40 mergedSubgoalKb
         (: (merge/revision
               (by smokingCancerRule (by friendSmokingRule (conjunction friendAnnaEdward smokesAnna)))
               (by smokingCancerRule smokesEdward))
            (Cancerous Edward)
            $tv)))
   ())
