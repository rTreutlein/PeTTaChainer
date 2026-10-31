!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

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
;; Not (Exists ...) is the complement of the existential judgment, answered
;; with its public statement.
!(test (query 100 existsKb (: $p (Not (Exists ($y) (Saw alice $y))) $tv))
   (: (negated seen) (Not (Exists ($_0) (Saw alice $_0))) (STV 0.30000000000000004 1)))

;; So is the negation of a quantified implication.
!(compileadd quantKb (: saw (Implication (Exists ($y) (Saw $x $y)) (Seen $x)) (STV 0.8 0.9)))
!(test (query 100 quantKb (: $p (Not (Implication (Exists ($y) (Saw $x $y)) (Seen $x))) $tv))
   (: (negated saw) (Not (Implication (Exists ($_0) (Saw $_1 $_0)) (Seen $_1))) (STV 0.19999999999999996 0.9)))

;; A negated CTV implication is its positive branch's complement: the value
;; of (Implication (G a) (Not (A a))).
!(compileadd ctvKb (: r (Implication (G a) (A a)) (CTV (STV 0.7 0.9) (STV 0.2 0.9))))
!(test (query 50 ctvKb (: $p (Not (Implication (G a) (A a))) $tv))
   (: (negated r) (Not (Implication (G a) (A a))) (STV 0.30000000000000004 0.9)))

;; A rule concluding a double negation concludes its statement.
!(compileadd notNotKb (: g (G a) (STV 0.74 1)))
!(compileadd notNotKb (: r (Implication (G $x) (Not (Not (A $x)))) (CTV (STV 0.66 1) (STV 0.33 1))))
!(test (query 100 notNotKb (: $p (A a) $tv))
   (: (by r g) (A a) (STV 0.5742 0.9999350619568963)))
!(test (query 100 notNotKb (: $p (Not (Not (A a))) $tv))
   (: (negated (negated (by r g))) (Not (Not (A a))) (STV 0.5742 0.9999350619568963)))

;; A compound's message to a negated child concludes the child's statement.
;; The certain (And (A a) (Not (B a))) at .6 is Pearl evidence (.6, .4) on its
;; worlds, A unknown: P(not B) = .25 / (.25 .6 + .75 .4) = 5/9, so B = 4/9.
;; Read on B's uniform prior with A's uniform Beta, the one soft observation
;; leaves nearly the prior's variance (n = 2, c = 2/802). The compound's atoms
;; are A and B, so the message reaches B's statement directly.
!(compileadd projKb (: both (And (A a) (Not (B a))) (STV 0.6 1)))
!(test
   (posterior-tv-near? 0.4444444444444445 0.0018959138091212229 (let (: $_proof (B a) $tv) (query 100 projKb (: $p (B a) $tv)) $tv))
   true)

;; A negated root reads its statement's stored value at budget zero, and its
;; written truth-value pattern constrains the complemented answer.
!(compileadd zeroKb (: fa (A a) (STV 0.3 1)))
!(test (query 0 zeroKb (: $p (Not (A a)) $tv)) (: (negated fa) (Not (A a)) (STV 0.7 1)))
!(test (collapse (query 0 zeroKb (: $p (Not (A a)) (STV 0.3 1)))) ())

;; A negated open statement has no answer: a computation row answers none.
!(test (collapse (query 10 zeroKb (: $p (Not $s) $tv))) ())

;; In a batch, a negated root's pattern filters only its own answers.
!(compileadd manyKb (: fa (A a) (STV 0.3 1)))
!(compileadd manyKb (: fb (A b) (STV 0.6 1)))
!(test (collapse (query-many 10 manyKb ((: $p (A $x) $tv) (: $q (Not (A $y)) (STV 0.7 1)))))
   ((query-result 0 (: fa (A a) (STV 0.3 1))) (query-result 0 (: fb (A b) (STV 0.6 1)))
    (query-result 1 (: (negated fa) (Not (A a)) (STV 0.7 1)))))
