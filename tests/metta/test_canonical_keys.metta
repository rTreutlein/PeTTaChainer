!(import! &self ../../pettachainer/metta/petta_chainer)

;; A statement is stored, assumed and concluded at its canonical key: under its
;; negations, the statement they negate (complemented for an odd count), and
;; an existential at its claim. A query of (Not s) reads s's key.

;; A stored existential fact is its claim, read by an existential query; a
;; stored negated existential is the claim at the complement.
!(compileadd existsKb (: seen (Exists ($y) (Saw alice $y)) (STV 0.7 1)))
!(compileadd existsKb (: none (Not (Exists ($y) (Met alice $y))) (STV 0.8 1)))
!(test (let (: $proof $_statement $tv) (query 100 existsKb (: $p (Exists ($y) (Saw alice $y)) $tv)) (data $proof $tv))
   (data seen (STV 0.7 1)))
!(test (let (: $proof $_statement $tv) (query 100 existsKb (: $p (Exists ($y) (Met alice $y)) $tv)) (data $proof $tv))
   (data none (STV 0.19999999999999996 1)))
;; Not (Exists ...) is the complement of the existential judgment.
!(test (let (: $proof $_statement $tv) (query 100 existsKb (: $p (Not (Exists ($y) (Saw alice $y))) $tv)) (data $proof $tv))
   (data (negated seen) (STV 0.30000000000000004 1)))

;; A rule concluding a double negation concludes its statement.
!(compileadd notNotKb (: g (G a) (STV 0.74 1)))
!(compileadd notNotKb (: r (Implication (G $x) (Not (Not (A $x)))) (CTV (STV 0.66 1) (STV 0.33 1))))
!(test (query 100 notNotKb (: $p (A a) $tv))
   (: (by r g) (A a) (STV 0.5742 0.9999350619568963)))
!(test (query 100 notNotKb (: $p (Not (Not (A a))) $tv))
   (: (negated (negated (by r g))) (Not (Not (A a))) (STV 0.5742 0.9999350619568963)))

;; A projection onto a negated child concludes the child's statement.
!(compileadd projKb (: both (And (A a) (Not (B a))) (STV 0.6 1)))
!(test (query 100 projKb (: $p (B a) $tv))
   (: (negated (marginal-proj 1 both)) (B a) (STV 0.4 0.9998333611064822)))

;; A negated root reads its statement's stored value at budget zero, and its
;; written truth-value pattern constrains the complemented answer.
!(compileadd zeroKb (: fa (A a) (STV 0.3 1)))
!(test (query 0 zeroKb (: $p (Not (A a)) $tv)) (: (negated fa) (Not (A a)) (STV 0.7 1)))
!(test (collapse (query 0 zeroKb (: $p (Not (A a)) (STV 0.3 1)))) ())
