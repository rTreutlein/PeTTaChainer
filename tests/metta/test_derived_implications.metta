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
