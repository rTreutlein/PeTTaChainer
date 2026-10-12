!(import! &self ../../pettachainer/metta/petta_chainer)

;; Derived implications (docs/metta/derived_implications.md): an implication a
;; rule concludes is applied by modus ponens like a rule, and a rule
;; A → (B → C) holds as its exported form (A ∧ B) → C.

(: selected-facts (-[det]-> KB Statement (List (Statement KBContext Proof TV))))
(= (selected-facts $kb $type)
   (collapse
      (once
         (match &kb ($type ($kb MAIN Nil) $prf $tv)
            (assemble-stored-runtime-fact $type ($kb MAIN Nil) $prf $tv)))))

;; A forward run's stored values, without their proof references.
(: result-values (-[det]-> (List (Statement KBContext Proof TV)) (List Atom)))
(= (result-values ()) ())
(= (result-values (cons ($type $_kbctx $_proof $tv) $rest)) (cons ($type $tv) (result-values $rest)))

;; Certain antecedents: the nested rule gives the flat rule's answer.
!(compileadd nestedKb (: a (A x) (STV 1.0 1.0)))
!(compileadd nestedKb (: b (B x) (STV 1.0 1.0)))
!(compileadd nestedKb (: r (Implication (A $x) (Implication (B $x) (C $x))) (STV 0.9 1.0)))
!(compileadd flatKb (: a (A x) (STV 1.0 1.0)))
!(compileadd flatKb (: b (B x) (STV 1.0 1.0)))
!(compileadd flatKb (: r (Implication (And (A $x) (B $x)) (C $x)) (STV 0.9 1.0)))

!(test (query 20 nestedKb (: $p (C x) $tv))
   (: (by (by r a) b) (C x) (STV 0.9 0.9999000081993594)))
!(test (query 20 flatKb (: $p (C x) $tv))
   (: (by r (conjunction a b)) (C x) (STV 0.9 0.9999000081993594)))

;; The derived statement answers an implication query. Its negative branch is
;; the exported rule's, from the base rates of (And (A $x) (B $x)) and (C $x):
;; nothing is known of them here.
!(test (query 20 nestedKb (: $p (Implication (B x) (C x)) $tv))
   (: (by r a) (Implication (B x) (C x)) (CTV (STV 0.9 0.9999000090991798) (STV 0.0 0.0))))

;; Uncertain antecedents, with base rates from (A y), (B y), (C y): the same
;; strength as the flat rule, a b p + (1 - a b) n, for any a and b. The
;; confidence is not the flat rule's: the nested form propagates the variance
;; of the negative branch n through two modus ponens steps as if independent.
!(compileadd nestedRatesKb (: a (A x) (STV 0.8 0.9)))
!(compileadd nestedRatesKb (: b (B x) (STV 0.6 0.7)))
!(compileadd nestedRatesKb (: ay (A y) (STV 0.3 0.9)))
!(compileadd nestedRatesKb (: by (B y) (STV 0.5 0.9)))
!(compileadd nestedRatesKb (: cy (C y) (STV 0.4 0.9)))
!(compileadd nestedRatesKb (: r (Implication (A $x) (Implication (B $x) (C $x))) (STV 0.9 0.9)))
!(compileadd flatRatesKb (: a (A x) (STV 0.8 0.9)))
!(compileadd flatRatesKb (: b (B x) (STV 0.6 0.7)))
!(compileadd flatRatesKb (: ay (A y) (STV 0.3 0.9)))
!(compileadd flatRatesKb (: by (B y) (STV 0.5 0.9)))
!(compileadd flatRatesKb (: cy (C y) (STV 0.4 0.9)))
!(compileadd flatRatesKb (: r (Implication (And (A $x) (B $x)) (C $x)) (STV 0.9 0.9)))

!(test (query 20 nestedRatesKb (: $p (C x) $tv))
   (: (by (by r a) b) (C x) (STV 0.5289398930037215 0.012957435091911673)))
!(test (query 20 flatRatesKb (: $p (C x) $tv))
   (: (by r (conjunction a b)) (C x) (STV 0.5289398930037214 0.007970898072552928)))

;; A nested implication query is judged as its exported form: the contexts
;; assume (A x) and (B x) and prove (C x), so the answer is a CTV of STVs,
;; the exported query's value, under the nested statement. The positive
;; proof applies the nested rule step by step, (by (by r A) B).
!(test (query 20 nestedRatesKb (: $p (Implication (A x) (Implication (B x) (C x))) $tv))
   (: (merge/revision (total-implication (by (by r (ctx proof 2)) (ctx proof 2 1)) (by (by r (ctx proof 3)) (ctx proof 3 1))) (implication-instance-fold cpu)) (Implication (A x) (Implication (B x) (C x))) (CTV (STV 0.9 0.9000112453459356) (STV 0.18642287116100267 0.0002849808074353135))))
!(test (query 20 nestedRatesKb (: $p (Implication (And (A x) (B x)) (C x)) $tv))
   (: (merge/revision (total-implication (by (by r (ctx proof 4)) (ctx proof 4 1)) (by (by r (ctx proof 5)) (ctx proof 5 1))) (implication-instance-fold cpu)) (Implication (And (A x) (B x)) (C x)) (CTV (STV 0.9 0.9000112453459356) (STV 0.18642287116100267 0.0002849808074353135))))
!(test (query 20 nestedRatesKb (: $p (Implication (A x) (Implication (B x) (C x))) (STV $s $c)))
   (: (conditional-implication (by (by r (ctx proof 6)) (ctx proof 6 1))) (Implication (A x) (Implication (B x) (C x))) (STV 0.9 0.8999999988602204)))

;; Three levels, A → (B → (C → D)), against (A ∧ B ∧ C) → D: 0.8 · 0.6 · 0.7
;; · 0.9 = 0.3024, the negative branch 0 (no base rates).
!(compileadd nested3Kb (: a (A x) (STV 0.8 0.9)))
!(compileadd nested3Kb (: b (B x) (STV 0.6 0.9)))
!(compileadd nested3Kb (: c (C x) (STV 0.7 0.9)))
!(compileadd nested3Kb (: r (Implication (A $x) (Implication (B $x) (Implication (C $x) (D $x)))) (STV 0.9 1.0)))
!(compileadd flat3Kb (: a (A x) (STV 0.8 0.9)))
!(compileadd flat3Kb (: b (B x) (STV 0.6 0.9)))
!(compileadd flat3Kb (: c (C x) (STV 0.7 0.9)))
!(compileadd flat3Kb (: r (Implication (And (A $x) (B $x) (C $x)) (D $x)) (STV 0.9 1.0)))

!(test (query 30 nested3Kb (: $p (D x) $tv))
   (: (by (by (by r a) b) c) (D x) (STV 0.3024 0.9385581496409168)))
!(test (query 30 flat3Kb (: $p (D x) $tv))
   (: (by r (conjunction a b c)) (D x) (STV 0.3024 0.9376722270285538)))
;; The query of a three-level nested implication is the exported query's.
!(test (query 30 nested3Kb (: $p (Implication (A x) (Implication (B x) (Implication (C x) (D x)))) $tv))
   (: (total-implication (by (by (by r (ctx proof 7)) (ctx proof 7 1)) (ctx proof 7 2)) (by (by (by r (ctx proof 8)) (ctx proof 8 1)) (ctx proof 8 2))) (Implication (A x) (Implication (B x) (Implication (C x) (D x)))) (CTV (STV 0.9 0.9999000072995391) (STV 0.0 1.0e-06))))
!(test (query 30 nested3Kb (: $p (Implication (And (A x) (B x) (C x)) (D x)) $tv))
   (: (total-implication (by (by (by r (ctx proof 9)) (ctx proof 9 1)) (ctx proof 9 2)) (by (by (by r (ctx proof 10)) (ctx proof 10 1)) (ctx proof 10 2))) (Implication (And (A x) (B x) (C x)) (D x)) (CTV (STV 0.9 0.9999000072995391) (STV 0.0 1.0e-06))))

;; A CTV (p, n) on a nested rule is its exported rule's CTV:
;; a b p + (1 - a b) n = 0.48 · 0.9 + 0.52 · 0.2 = 0.536.
!(compileadd nestedCtvKb (: a (A x) (STV 0.8 0.9)))
!(compileadd nestedCtvKb (: b (B x) (STV 0.6 0.9)))
!(compileadd nestedCtvKb (: r (Implication (A $x) (Implication (B $x) (C $x))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd flatCtvKb (: a (A x) (STV 0.8 0.9)))
!(compileadd flatCtvKb (: b (B x) (STV 0.6 0.9)))
!(compileadd flatCtvKb (: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test (query 20 nestedCtvKb (: $p (C x) $tv))
   (: (by (by r a) b) (C x) (STV 0.536 0.9363589545658939)))
!(test (query 20 flatCtvKb (: $p (C x) $tv))
   (: (by r (conjunction a b)) (C x) (STV 0.536 0.9303813636151533)))

;; A stored implication is a rule, applied by modus ponens. With a derived
;; implication of the same statement, the two proofs share the fact b; the
;; lifting merge factors it out and revises the two implications, as it does
;; for the flat rule.
!(compileadd storedKb (: a (A x) (STV 1.0 1.0)))
!(compileadd storedKb (: b (B x) (STV 1.0 1.0)))
!(compileadd storedKb (: s (Implication (B x) (C x)) (CTV (STV 0.7 0.5) (STV 0.1 0.5))))

!(test (query 20 storedKb (: $p (C x) $tv))
   (: (by s b) (C x) (STV 0.7 0.499999999956991)))

!(compileadd storedKb (: r (Implication (A $x) (Implication (B $x) (C $x))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(compileadd storedFlatKb (: a (A x) (STV 1.0 1.0)))
!(compileadd storedFlatKb (: b (B x) (STV 1.0 1.0)))
!(compileadd storedFlatKb (: s (Implication (B x) (C x)) (CTV (STV 0.7 0.5) (STV 0.1 0.5))))
!(compileadd storedFlatKb (: r (Implication (And (A $x) (B $x)) (C $x)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test (query 20 storedKb (: $p (C x) $tv))
   (: (merge/revision (by s b) (by (by r a) b)) (C x) (STV 0.8799999998266353 0.9090909079875853)))
!(test (query 20 storedFlatKb (: $p (C x) $tv))
   (: (merge/revision (by s b) (by r (conjunction a b))) (C x) (STV 0.8799999998266352 0.9090909079875852)))

;; Forward chaining: taking a derives the statement, taking it joins b.
!(compileadd forwardKb (: a (A x) (STV 1.0 1.0)))
!(compileadd forwardKb (: b (B x) (STV 1.0 1.0)))
!(compileadd forwardKb (: r (Implication (A $x) (Implication (B $x) (C $x))) (STV 0.9 1.0)))
!(test (result-values (forward-chain 20 forwardKb (selected-facts forwardKb (A x))))
   (((Implication (B x) (C x)) (CTV (STV 0.9 0.9999000090991798) (STV 0.0 0.0)))
    ((C x) (STV 0.9 0.9999000081993594))))
!(test (query 0 forwardKb (: $p (C x) $tv))
   (: (by (by r a) b) (C x) (STV 0.9 0.9999000081993594)))

;; A knowledge base whose rules conclude no implication gets no statement rule.
!(compileadd plainKb (: a (A x) (STV 0.8 0.9)))
!(compileadd plainKb (: r (Implication (A $x) (C $x)) (STV 0.9 0.9)))
!(test (query 20 plainKb (: $p (C x) $tv))
   (: (by r a) (C x) (STV 0.7200000000000001 0.906344240230084)))
!(test (collapse (match &implication_statement_rules ($hash (plainKb $shape)) $shape))
   ())
;; A source gate stays a condition (the knowledge-extraction report): the
;; query's contexts assume the gate, and nothing accepts it in the main KB, so
;; neither the consequent nor the inner rule holds without it. An implication's
;; negation has no answer.
!(compileadd gateKb (: s1 (Supplier Supplier1) (STV 1.0 0.9)))
!(compileadd gateKb (: e1 (ExposedTo Supplier1 ClimateRisk) (STV 1.0 0.9)))
!(compileadd gateKb (: src_rule (Implication (AcceptSource Report1) (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk)) (LowerPrices $x))) (STV 1 0.9)))
!(test (query 100 gateKb (: $p (Implication (AcceptSource Report1) (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk)) (LowerPrices $x))) $tv))
   (: (total-implication (by (by src_rule (ctx proof 11)) (conjunction (ctx proof 11 1) (ctx proof 11 2))) (by (by src_rule (ctx proof 12)) (conjunction (ctx proof 12 1) (ctx proof 12 2)))) (Implication (AcceptSource Report1) (Implication (And (Supplier $_0) (ExposedTo $_0 ClimateRisk)) (LowerPrices $_0))) (CTV (STV 1.0 0.8997569978203288) (STV 0.0 1.0e-06))))
!(test (query 100 gateKb (: $p (Implication (AcceptSource Report1) (Implication (And (Supplier Supplier1) (ExposedTo Supplier1 ClimateRisk)) (LowerPrices Supplier1))) $tv))
   (: (total-implication (by (by src_rule (ctx proof 13)) (conjunction (ctx proof 13 1) (ctx proof 13 2))) (by (by src_rule (ctx proof 14)) (conjunction (ctx proof 14 1) (ctx proof 14 2)))) (Implication (AcceptSource Report1) (Implication (And (Supplier Supplier1) (ExposedTo Supplier1 ClimateRisk)) (LowerPrices Supplier1))) (CTV (STV 1.0 0.8997569978203288) (STV 0.0 1.0e-06))))
!(test (collapse (query 100 gateKb (: $p (Not (Implication (AcceptSource Report1) (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk)) (LowerPrices $x)))) $tv)))
   ())
!(test (collapse (query 100 gateKb (: $p (LowerPrices Supplier1) $tv)))
   ())
!(test (collapse (query 100 gateKb (: $p (Implication (And (Supplier $x) (ExposedTo $x ClimateRisk)) (LowerPrices $x)) $tv)))
   ())

;; An inner antecedent with a variable that neither the outer antecedent nor
;; the consequent binds, as $f here. The derived statement is an open key, a
;; statement for every $f; the statement rule's join binds $f through (F y)
;; and reads the open key, as the knowledge-extraction report's nested rule
;; (an announcement's firm and county) needs. The flat rule's value.
!(compileadd openKb (: g (G R) (STV 1.0 1.0)))
!(compileadd openKb (: a (A x) (STV 0.8 0.9)))
!(compileadd openKb (: f (F y) (STV 1.0 0.9)))
!(compileadd openKb (: fr (From x y) (STV 0.9 0.9)))
!(compileadd openKb (: r (Implication (G R) (Implication (And (A $a) (F $f) (From $a $f)) (C $a))) (STV 0.9 1.0)))
!(compileadd openFlatKb (: g (G R) (STV 1.0 1.0)))
!(compileadd openFlatKb (: a (A x) (STV 0.8 0.9)))
!(compileadd openFlatKb (: f (F y) (STV 1.0 0.9)))
!(compileadd openFlatKb (: fr (From x y) (STV 0.9 0.9)))
!(compileadd openFlatKb (: r (Implication (And (G R) (A $a) (F $f) (From $a $f)) (C $a)) (STV 0.9 1.0)))
!(test (query 30 openKb (: $p (C x) $tv))
   (: (by (by r g) (conjunction a f fr)) (C x) (STV 0.6480000000000001 0.9309628102246349)))
!(test (query 30 openFlatKb (: $p (C x) $tv))
   (: (by r (conjunction g a f fr)) (C x) (STV 0.6480000000000001 0.9309628102246349)))
;; Its nested query, the gate a condition as above.
!(compileadd openGateKb (: r (Implication (G R) (Implication (And (A $a) (F $f) (From $a $f)) (C $a))) (STV 1 0.9)))
!(test (query 100 openGateKb (: $p (Implication (G R) (Implication (And (A $a) (F $f) (From $a $f)) (C $a))) $tv))
   (: (total-implication (by (by r (ctx proof 19)) (conjunction (ctx proof 19 1) (ctx proof 19 2) (ctx proof 19 3))) (by (by r (ctx proof 20)) (conjunction (ctx proof 20 1) (ctx proof 20 2) (ctx proof 20 3)))) (Implication (G R) (Implication (And (A $_0) (F $_1) (From $_0 $_1)) (C $_0))) (CTV (STV 1.0 0.8996760262111828) (STV 0.0 1.0e-06))))
!(test (collapse (query 100 openGateKb (: $p (C x) $tv)))
   ())
