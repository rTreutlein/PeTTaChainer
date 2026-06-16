!(import! &self petta_chainer)

!(compileadd bwdOnlyKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd bwdOnlyKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 2 bwdOnlyKb (: $p (Goal) $tv)) ())

!(test (query 4 bwdOnlyKb (: $p (Goal) $tv))
   (: (r2 (r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(test
   (query 100 bwdOnlyKb
      (: $p (Implication (Premises (A)) (Conclusions (Goal)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(compileadd transitiveClosedKb
   (: ax-tr
      (Implication
         (Premises (Provable (→ $psi $chi)) (Provable (→ $phi $psi)))
         (Conclusions (Provable (→ $phi $chi))))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd transitiveClosedKb (: given-imp1 (Provable (→ (PropP) (PropQ))) (STV 1.0 1.0)))

!(compileadd transitiveClosedKb (: given-imp2 (Provable (→ (PropQ) (PropT))) (STV 1.0 1.0)))

!(test
   (query 20 transitiveClosedKb (: $p (Provable (→ (PropP) (PropT))) $tv))
   (: (ax-tr (conjunction given-imp2 given-imp1)) (Provable (→ (PropP) (PropT))) (STV 1.0 0.999700089898053)))

!(compileadd openImplicationKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 openImplicationKb
      (: $p (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(compileadd openVariablePatternImplicationKb
   (: featureRule (Implication (Premises (Feature a)) (Conclusions (Target))) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))

!(test
   (query 100 openVariablePatternImplicationKb
      (: $p (Implication (Premises (Feature $x)) (Conclusions (Target))) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))
   ())

!(compileadd openVariableConclusionImplicationKb (: tallAlice (Tall alice) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: femaleAlice (Female alice) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: tallMary (Tall mary) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: femaleMary (Female mary) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb
   (: copyPredicate
      (Implication
         (Premises (And ($p1 $x) ($p2 $x)) ($p1 $y))
         (Conclusions ($p2 $y)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $p
         (Implication (Premises (Tall $x)) (Conclusions (Female $x)))
         (CTV (STV 0.9639 0.5) (STV 0.5 0.0))))
   ())

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $p (Implication (Premises (Tall $x)) (Conclusions (Female $x))) $tv))
   ())

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $proof
         (Implication (Premises ($p $x)) (Conclusions ($p $x)))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   (: (total-implication (ctx proof 10) (ctx proof 11))
      (Implication (Premises ($_p $_x)) (Conclusions ($_p $_x)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $proof
         (Implication (Premises (Female $x)) (Conclusions (Tall $x)))
         (CTV (STV 0.9639 0.5) (STV 0.5 0.0))))
   ())

!(compileadd existentialDisjunctionKb (: pa (P a) (STV 0.8 0.5)))

!(compileadd existentialDisjunctionKb (: pb (P b) (STV 0.6 0.7)))

!(compileadd existentialDisjunctionKb
   (: pToT (Implication (Premises (P $x)) (Conclusions (T))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 existentialDisjunctionKb (: $prf (T) $tv))
   (: (pToT (disjunction pa pb)) (T) (STV 0.9199999999999999 0.7123799943249737)))

!(compileadd composeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKb (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd composeKb (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 1 composeKb) (query 2 composeKb (: $p (Goal) $tv)))
   (: (r2 (r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(compileadd composeKbShort (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r1 (Implication (Premises (A)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd composeKbShort (: r2 (Implication (Premises (B)) (Conclusions (Goal))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (let $_ (forward-chain 1 composeKbShort)
      (query 1 composeKbShort (: $p (Goal) $tv)))
   ())

!(compileadd noReuseKb (: x (X) (STV 1.0 1.0)))

!(compileadd noReuseKb (: ra (Implication (Premises (X)) (Conclusions (A))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd noReuseKb (: rb (Implication (Premises (X)) (Conclusions (B))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd noReuseKb (: rc (Implication (Premises (A) (B)) (Conclusions (C))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 noReuseKb (: $p (C) $tv)) ())

!(compileadd independentKb (: x (X) (STV 1.0 1.0)))

!(compileadd independentKb (: b (B) (STV 1.0 1.0)))

!(compileadd independentKb (: ra (Implication (Premises (X)) (Conclusions (A))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd independentKb (: rc (Implication (Premises (A) (B)) (Conclusions (C))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 independentKb (: $p (C) $tv))
   (: (rc (conjunction (ra x) b)) (C) (STV 1.0 0.9996001597861454)))

!(compileadd derivedAndRuleKb (: yearsRule (Implication (Premises (YearsExp $p 10)) (Conclusions (IndustryVeteran $p))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: expertRule (Implication (Premises (And (IndustryVeteran $p) (ManagedTeam $p))) (Conclusions (Expert $p))) (CTV (STV 1.0 0.95) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: seniorRule (Implication (Premises (And (Expert $p) (CertifiedEthical $p))) (Conclusions (SeniorExpert $p))) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: yearsFact (YearsExp kebede 10) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: mgmtFact (ManagedTeam kebede) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: ethicsFact (CertifiedEthical kebede) (STV 1.0 1.0)))

!(test
   (query 50 derivedAndRuleKb (: $p (Expert kebede) $tv))
   (: (expertRule (conjunction (yearsRule yearsFact) mgmtFact)) (Expert kebede) (STV 1.0 0.9497292914682098)))

!(test
   (query 50 derivedAndRuleKb (: $p (SeniorExpert kebede) $tv))
   (: (seniorRule (conjunction (expertRule (conjunction (yearsRule yearsFact) mgmtFact)) ethicsFact)) (SeniorExpert kebede) (STV 1.0 0.9495489046959086)))
