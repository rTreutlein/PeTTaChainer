!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd invKb (: r (Implication (P $x) (Q $x)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(compileadd invKb (: qa (Q alice) (STV 0.9 0.8)))

!(compileadd invKb (: pb (P bob) (STV 0.7 0.8)))

; The rule states both branches, so inversion is Bayes' rule with the base
; rate of P as the prior, found as a FoldAll aggregate over all proofs of P
; (pb, one confidence-weighted piece of evidence with K=800): P(P | Q) =
; 0.8 * 0.7 / (0.8 * 0.7 + 0.1 * 0.3) = 0.949 and P(P | not Q) = 0.2 * 0.7 /
; (0.2 * 0.7 + 0.9 * 0.3) = 0.341. The inverted CTV is then applied to the
; witness qa via modus ponens: 0.9 * 0.949 + 0.1 * 0.341 = 0.888.
!(test
   (query 200 invKb (: $prf (P alice) $tv))
   (: ((inverted r with cpu (prior (STV 0.6599999999999998 0.0009990009990009992))) qa) (P alice) (STV 0.875684243726313 0.016392039082253194)))

; The consequent's own base rate is not read: here P(Late) = 0.1 contradicts
; P(Blocked) = 1/6 and the stated likelihoods, which give P(Late) = 0.1917.
; Recovering P(Late | not Blocked) from the two rates would give
; (0.1 - 0.9 / 6) / (5 / 6) < 0, so one late shipment would prove the route
; blocked; Bayes' rule with the stated likelihoods gives 0.9 / 6 /
; (0.9 / 6 + 0.05 * 5 / 6) = 0.7826.
!(compileadd lateKb (: late (Implication (Blocked $r) (Late $r)) (CTV (STV 0.9 1.0) (STV 0.05 1.0))))
!(set-base-rate lateKb (Blocked $r) (STV 0.16666666666666666 0.9))
!(set-base-rate lateKb (Late $r) (STV 0.1 0.9))
!(compileadd lateKb (: l1 (Late r1) (STV 1.0 1.0)))
!(test
   (query 100 lateKb (: $prf (Blocked r1) $tv))
   (: ((inverted late with cpu (prior (STV 0.1666759256687314 0.9))) l1) (Blocked r1) (STV 0.7826200370264366 0.8799531219767693)))

; A soft observation is read as a likelihood ratio over the base rate it was
; formed under. One late shipment makes the route blocked with
; 0.9 * 0.2 / (0.9 * 0.2 + 0.05 * 0.8) = 0.8182 over P(Blocked) = 0.2, a ratio
; of odds(0.8182) / odds(0.2) = 18 = 0.9 / 0.05. Inverting the block rule
; reads that ratio, so the storm is Bayes' rule over the whole chain, whatever
; P(Blocked) was: P(Late | Storm) = 0.8 * 0.9 + 0.2 * 0.05 = 0.73,
; P(Late | no storm) = 0.03 * 0.9 + 0.97 * 0.05 = 0.0755, odds 0.3 / 0.7 *
; 0.73 / 0.0755 = 4.1438, P = 0.805591. Read as a posterior under the prior
; the block rule implies for the route (0.261), it gave 0.7671.
!(compileadd softKb (: block (Implication (Storm $r) (Blocked $r)) (CTV (STV 0.8 1.0) (STV 0.03 1.0))))
!(compileadd softKb (: late (Implication (Blocked $r) (Late $r)) (CTV (STV 0.9 1.0) (STV 0.05 1.0))))
!(set-base-rate softKb (Storm $r) (STV 0.3 0.9))
!(set-base-rate softKb (Blocked $r) (STV 0.2 0.9))
!(compileadd softKb (: l1 (Late r1) (STV 1.0 1.0)))
!(test
   (query 100 softKb (: $prf (Storm r1) $tv))
   (: ((inverted block with cpu (prior (STV 0.30000555540123885 0.9))) ((inverted late with cpu (prior (STV 0.20000833310185828 0.9))) l1)) (Storm r1) (STV 0.8055954617975354 0.985846947644943)))

; A knowledge base storing only true instances has base rate 1 for every
; predicate it stores, which is no sample of how often a pair is a parent:
; inverting over it would make every ancestor pair a parent. Declared
; positive-only, Parent has no prior, and neither an STV nor a CTV rule is
; inverted onto it.
!(set-positive-only-predicate logicKb Parent)
!(set-positive-only-predicate ctvLogicKb Parent)
!(compileadd logicKb (: parentAncestor (Implication (Parent $x $y) (Ancestor $x $y)) (STV 1.0 1.0)))
!(compileadd logicKb (: pab (Parent a b) (STV 1.0 1.0)))
!(compileadd logicKb (: pbc (Parent b c) (STV 1.0 1.0)))
!(compileadd logicKb (: acd (Ancestor c d) (STV 1.0 1.0)))
!(test (collapse (query 100 logicKb (: $p (Parent c d) $tv))) ())
!(test (query 100 logicKb (: $p (Ancestor a b) $tv)) (: (by parentAncestor pab) (Ancestor a b) (STV 1.0 0.9999000099190012)))
!(compileadd ctvLogicKb (: parentAncestor (Implication (Parent $x $y) (Ancestor $x $y)) (CTV (STV 1.0 1.0) (STV 0.3 1.0))))
!(compileadd ctvLogicKb (: pab (Parent a b) (STV 1.0 1.0)))
!(compileadd ctvLogicKb (: acd (Ancestor c d) (STV 1.0 1.0)))
!(test (collapse (query 100 ctvLogicKb (: $p (Parent c d) $tv))) ())
