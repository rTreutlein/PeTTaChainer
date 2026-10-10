!(import! &self ../../pettachainer/metta/petta_chainer)

;; A complete predicate's rules and facts are the only ways one of its
;; statements becomes true (docs/metta/complete_predicates.md). The loop:
;; (P t) holds by stock (S t) or by (M t), and (M t) holds when (P t) does and
;; (Deg t) does not.

;; No stock: nothing outside the loop makes either true, so both are false. P
;; reads M with P itself unfounded, and M reads P with M unfounded.
!(set-complete-predicate offKb P)
!(set-complete-predicate offKb M)
!(compileadd offKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd offKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd offKb (: s (S t) (STV 0 1)))
!(compileadd offKb (: d (Deg t) (STV 0 1)))

!(test (query 100 offKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.0 0.9996001597861454)))
!(test (query 100 offKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.0 0.9996001597861454)))

;; Undeclared, the same KB is open-world: the loop's only proof is circular,
;; and there is no answer.
!(compileadd openKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd openKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd openKb (: s (S t) (STV 0 1)))
!(compileadd openKb (: d (Deg t) (STV 0 1)))

!(test (query 100 openKb (: $p (P t) $tv)) ())
!(test (query 100 openKb (: $p (M t) $tv)) ())

;; Stock: both true. The stock settles the Or; P's complete row reads (M t)
;; closed, the mine's production with P pinned false, and M reads P's
;; settled value.
!(set-complete-predicate onKb P)
!(set-complete-predicate onKb M)
!(compileadd onKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd onKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd onKb (: s (S t) (STV 1 1)))
!(compileadd onKb (: d (Deg t) (STV 0 1)))

!(test (query 100 onKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 1.0 0.9998000399670116)))
!(test (query 100 onKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (settled s)) (negated d))) (M t) (STV 1.0 0.9996001597861454)))

;; Uncertain stock: P has the stock's strength, OrFormula(0.9, 0), and M the
;; same through P.
!(set-complete-predicate partKb P)
!(set-complete-predicate partKb M)
!(compileadd partKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd partKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd partKb (: s (S t) (STV 0.9 0.9)))
!(compileadd partKb (: d (Deg t) (STV 0 1)))

!(test (query 100 partKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.9 0.8999999992437459)))
!(test (query 100 partKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.9 0.8999999977853199)))

;; An uncertain degradation leaves P at the stock's strength and lowers M:
;; 0.9 times P(not degraded) = 0.9 * 0.7.
!(set-complete-predicate degKb P)
!(set-complete-predicate degKb M)
!(compileadd degKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd degKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd degKb (: s (S t) (STV 0.9 0.9)))
!(compileadd degKb (: d (Deg t) (STV 0.3 0.9)))

!(test (query 100 degKb (: $p (P t) $tv))
   (: (by rp (conjunction s (by rm (conjunction unfounded (negated d))))) (P t) (STV 0.9 0.8999999992437459)))
!(test (query 100 degKb (: $p (M t) $tv))
   (: (by rm (conjunction (by rp (conjunction s unfounded)) (negated d))) (M t) (STV 0.63 0.9073568643833784)))

;; An open predicate in the body stays open: with (S t) unknown, nothing is
;; concluded, false or otherwise.
!(set-complete-predicate unknownKb P)
!(set-complete-predicate unknownKb M)
!(compileadd unknownKb (: rp (Implication (Or (S $t) (M $t)) (P $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unknownKb (: rm (Implication (And (P $t) (Not (Deg $t))) (M $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd unknownKb (: d (Deg t) (STV 0 1)))

!(test (query 100 unknownKb (: $p (P t) $tv)) ())
!(test (query 100 unknownKb (: $p (M t) $tv)) ())

;; A complete statement no rule concludes and no fact states is false.
!(set-complete-predicate emptyKb Q)
!(compileadd emptyKb (: r (Implication (R $x) (Other $x)) (STV 0.9 0.9)))

!(test (query 10 emptyKb (: $p (Q a) $tv)) (: unfounded (Q a) (STV 0.0 1.0)))

;; A budget too small to reach a proof concludes nothing: (G t) reads the
;; complete (K t), which holds through a chain of open statements down to the
;; fact (B t). Until the search has examined (K t)'s rule application to the
;; end, (K t) is not settled, and (G t) has no answer rather than a false one.
!(set-complete-predicate deepKb G)
!(set-complete-predicate deepKb K)
!(compileadd deepKb (: rg (Implication (K $t) (G $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: rk (Implication (A1 $t) (K $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r1 (Implication (A2 $t) (A1 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r2 (Implication (A3 $t) (A2 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: r3 (Implication (B $t) (A3 $t)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd deepKb (: b (B t) (STV 1 1)))

!(test (query 1 deepKb (: $p (G t) $tv)) ())
!(test (query 2 deepKb (: $p (G t) $tv)) ())
!(test (query 3 deepKb (: $p (G t) $tv))
   (: (by rg (by rk (by r1 (by r2 (by r3 b))))) (G t) (STV 1 0.9994003594095785)))
