!(import! &self petta_chainer)

!(compileadd bwdOnlyKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test (not (== (collapse (query 2 bwdOnlyKb (: $p (Goal) $tv))) ())) false)

!(test (not (== (collapse (query 4 bwdOnlyKb (: $p (Goal) $tv))) ())) true)

!(test
   (let (: $prf (Implication (Premises (A)) (Conclusions (Goal))) (STV 1.0 0.81))
      (superpose (collapse
                  (query 100 bwdOnlyKb (: $p (Implication (Premises (A)) (Conclusions (Goal))) $tv))))
      true)
   true)

!(compileadd composeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd composeKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test (let $_ (forward-chain 1 composeKb) (not (== (collapse (query 2 composeKb (: $p (Goal) $tv))) ())))
   true)

!(compileadd composeKbShort (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r1 (Implication (Premises (A)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (STV 1.0 1.0)))

!(test
   (let $_ (forward-chain 1 composeKbShort)
      (not (== (collapse (query 1 composeKbShort (: $p (Goal) $tv))) ())))
   false)

!(compileadd noReuseKb (: x (X) (STV 1.0 1.0)))

!(compileadd noReuseKb (: ra (Implication (Premises (X)) (Conclusions (A))) (STV 1.0 1.0)))

!(compileadd noReuseKb (: rb (Implication (Premises (X)) (Conclusions (B))) (STV 1.0 1.0)))

!(compileadd noReuseKb (: rc (Implication (Premises (A) (B)) (Conclusions (C))) (STV 1.0 1.0)))

!(test (== (collapse (query 100 noReuseKb (: $p (C) $tv))) ()) true)

!(compileadd independentKb (: x (X) (STV 1.0 1.0)))

!(compileadd independentKb (: b (B) (STV 1.0 1.0)))

!(compileadd independentKb (: ra (Implication (Premises (X)) (Conclusions (A))) (STV 1.0 1.0)))

!(compileadd independentKb (: rc (Implication (Premises (A) (B)) (Conclusions (C))) (STV 1.0 1.0)))

!(test (not (== (collapse (query 100 independentKb (: $p (C) $tv))) ())) true)

!(compileadd derivedAndRuleKb (: yearsRule (Implication (Premises (YearsExp $p 10)) (Conclusions (IndustryVeteran $p))) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: expertRule (Implication (Premises (And (IndustryVeteran $p) (ManagedTeam $p))) (Conclusions (Expert $p))) (STV 1.0 0.95)))

!(compileadd derivedAndRuleKb (: seniorRule (Implication (Premises (And (Expert $p) (CertifiedEthical $p))) (Conclusions (SeniorExpert $p))) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: yearsFact (YearsExp kebede 10) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: mgmtFact (ManagedTeam kebede) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: ethicsFact (CertifiedEthical kebede) (STV 1.0 1.0)))

!(test
   (not (== (collapse (query 50 derivedAndRuleKb (: $p (Expert kebede) $tv))) ()))
   true)

!(test
   (not (== (collapse (query 50 derivedAndRuleKb (: $p (SeniorExpert kebede) $tv))) ()))
   true)
