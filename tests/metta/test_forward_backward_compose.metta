!(import! &self ../../pettachainer/metta/petta_chainer)

(: test-selected-facts
   (-[det]-> KB Statement
      (List (Statement KBContext Proof TV))))
(= (test-selected-facts $kb $type)
   (collapse
      (once
         (match &kb
            ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact
               $type ($kb MAIN Nil) $prf $tv)))))

!(compileadd bwdOnlyKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd bwdOnlyKb (: r1 (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd bwdOnlyKb (: r2 (Implication (B) (Goal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Stored facts reach a waiting join without an expansion, so two steps expand
;; Goal and B and read A.
!(test (query 2 bwdOnlyKb (: $p (Goal) $tv))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(test (query 4 bwdOnlyKb (: $p (Goal) $tv))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(test
   (query 100 bwdOnlyKb
      (: $p (Implication (A) (Goal))
         (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(set-positive-only-predicate transitiveClosedKb Provable)
!(compileadd transitiveClosedKb
   (: ax-tr
      (Implication
         (And (Provable (→ $psi $chi)) (Provable (→ $phi $psi)))
         (Provable (→ $phi $chi)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd transitiveClosedKb (: given-imp1 (Provable (→ (PropP) (PropQ))) (STV 1.0 1.0)))

!(compileadd transitiveClosedKb (: given-imp2 (Provable (→ (PropQ) (PropT))) (STV 1.0 1.0)))

!(test
   (query 20 transitiveClosedKb (: $p (Provable (→ (PropP) (PropT))) $tv))
   (: (by ax-tr (conjunction given-imp2 given-imp1)) (Provable (→ (PropP) (PropT))) (STV 1.0 0.999700089898053)))

!(compileadd openImplicationKb (: r1 (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 openImplicationKb
      (: $p (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
   ())

!(compileadd openVariablePatternImplicationKb
   (: featureRule (Implication (Feature a) (Target)) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))

!(test
   (query 100 openVariablePatternImplicationKb
      (: $p (Implication (Feature $x) (Target)) (CTV (STV 1.0 0.5) (STV 0.0 1.0))))
   ())

!(compileadd openVariableConclusionImplicationKb (: tallAlice (Tall alice) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: femaleAlice (Female alice) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: tallMary (Tall mary) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb (: femaleMary (Female mary) (STV 0.9 0.5)))

!(compileadd openVariableConclusionImplicationKb
   (: copyPredicate
      (Implication
         (And (And ($p1 $x) ($p2 $x)) ($p1 $y))
         ($p2 $y))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $p
         (Implication (Tall $x) (Female $x))
         (CTV (STV 0.9639 0.5) (STV 0.5 0.0))))
   ())

;; The stored instances support the implication empirically, and copying a
;; tall female's predicates to a hypothetical individual derives it through
;; copyPredicate's completion; the two revise. copyPredicate states
;; P(($p2 $y) | not ...) = 0, so given Tall of the individual the antecedent
;; holds, Female included, whatever Alice's and Mary's predicates: 1. Given
;; not Tall, their predicates (0.81 together) make P(Tall | Female) 0.81, and
;; Bayes over the base rate 0.9 of ($p1 $y) gives
;; 0.19 * 0.9 / (0.19 * 0.9 + 0.1) = 0.631, revised with the instance fold.
;; The two completions read the same hypothetical observation, so they revise
;; rather than multiply.
!(test
   (query 100 openVariableConclusionImplicationKb
      (: $p (Implication (Tall $x) (Female $x)) $tv))
   (: (merge/revision (total-implication (merge/revision ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleAlice tallAlice (ctx proof 8))) ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleMary tallMary (ctx proof 8)))) (merge/revision ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleAlice tallAlice (ctx proof 9))) ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleMary tallMary (ctx proof 9))))) (implication-instance-fold (foldall-proof (implication-instance-sample tallAlice femaleAlice) (implication-instance-sample tallMary femaleMary)))) (Implication (Tall $_838880) (Female $_838880)) (CTV (STV 0.9999999988245056 0.9999791027594874) (STV 0.589723560454245 0.0011965404087683272))))

;; The open identity holds. Its instance fold also samples each stored
;; statement against its other proofs, the completions copying the other
;; individual's predicates; the certain total implication keeps (1, 1) and
;; (0, 1), and each ground instance answers with it.
!(test
   (collapse
      (query 100 openVariableConclusionImplicationKb
         (: $proof
            (Implication ($p $x) ($p $x))
            (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))
   ((: (merge/revision (total-implication (ctx proof 10) (ctx proof 11)) (implication-instance-fold (foldall-proof (implication-instance-sample tallAlice ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction tallMary femaleMary femaleAlice))) (implication-instance-sample femaleAlice ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleMary tallMary tallAlice))) (implication-instance-sample tallMary ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction tallAlice femaleAlice femaleMary))) (implication-instance-sample femaleMary ((antecedent-completion copyPredicate 1 with cpu (prior (STV 0.8636363636363636 0.0024937655860349127))) (conjunction femaleAlice tallAlice tallMary)))))) (Implication ($_1082206 $_1082212) ($_1082206 $_1082212)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (: (total-implication (ctx proof 10) (ctx proof 11)) (Implication (Tall alice) (Tall alice)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (: (total-implication (ctx proof 10) (ctx proof 11)) (Implication (Female alice) (Female alice)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (: (total-implication (ctx proof 10) (ctx proof 11)) (Implication (Tall mary) (Tall mary)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (: (total-implication (ctx proof 10) (ctx proof 11)) (Implication (Female mary) (Female mary)) (CTV (STV 1.0 1.0) (STV 0.0 1.0)))))

!(test
   (query 100 openVariableConclusionImplicationKb
      (: $proof
         (Implication (Female $x) (Tall $x))
         (CTV (STV 0.9639 0.5) (STV 0.5 0.0))))
   ())

!(compileadd existentialDisjunctionKb (: pa (P a) (STV 0.8 0.5)))

!(compileadd existentialDisjunctionKb (: pb (P b) (STV 0.6 0.7)))

!(compileadd existentialDisjunctionKb
   (: pToT
      (Implication
         (Exists ($x) (P $x))
         (T))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 100 existentialDisjunctionKb (: $prf (T) $tv))
   (: (by pToT (disjunction pa pb)) (T) (STV 0.9199999999999999 0.7123799943249737)))

!(compileadd composeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKb (: r1 (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd composeKb (: r2 (Implication (B) (Goal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (let $_ (forward-chain 1 composeKb (test-selected-facts composeKb (A))) (query 2 composeKb (: $p (Goal) $tv)))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(compileadd composeKbShort (: a0 (A) (STV 1.0 1.0)))

!(compileadd composeKbShort (: r1 (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd composeKbShort (: r2 (Implication (B) (Goal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; The one forward step materializes B. Durable pure-CPU modus-ponens results
;; from the equivalent earlier search complete this rule within one query step.
!(test
   (let $_ (forward-chain 1 composeKbShort (test-selected-facts composeKbShort (A)))
      (query 1 composeKbShort (: $p (Goal) $tv)))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(compileadd independentKb (: x (X) (STV 1.0 1.0)))

!(compileadd independentKb (: b (B) (STV 1.0 1.0)))

!(compileadd independentKb (: ra (Implication (X) (A)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd independentKb (: rc (Implication (And (A) (B)) (C)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 independentKb (: $p (C) $tv))
   (: (by rc (conjunction (by ra x) b)) (C) (STV 1.0 0.9996001597861454)))

!(compileadd derivedAndRuleKb (: yearsRule (Implication (YearsExp $p 10) (IndustryVeteran $p)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: expertRule (Implication (And (IndustryVeteran $p) (ManagedTeam $p)) (Expert $p)) (CTV (STV 1.0 0.95) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: seniorRule (Implication (And (Expert $p) (CertifiedEthical $p)) (SeniorExpert $p)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd derivedAndRuleKb (: yearsFact (YearsExp kebede 10) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: mgmtFact (ManagedTeam kebede) (STV 1.0 1.0)))

!(compileadd derivedAndRuleKb (: ethicsFact (CertifiedEthical kebede) (STV 1.0 1.0)))

!(test
   (query 50 derivedAndRuleKb (: $p (Expert kebede) $tv))
   (: (by expertRule (conjunction (by yearsRule yearsFact) mgmtFact)) (Expert kebede) (STV 1.0 0.9497292914682098)))

!(test
   (query 50 derivedAndRuleKb (: $p (SeniorExpert kebede) $tv))
   (: (by seniorRule (conjunction (by expertRule (conjunction (by yearsRule yearsFact) mgmtFact)) ethicsFact)) (SeniorExpert kebede) (STV 1.0 0.9495489046959086)))
