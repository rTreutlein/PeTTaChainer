!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

;; The review counterexamples of the event-moment node (event-moment-node.md),
;; each at the value its formula gives.

;; An observed compound's endpoint is exact only at c = 1. And(A, B) at (1, .5)
;; with B certain reads A by the Pearl factor at the compound's mean m: the
;; message is lambda1 = m, lambda0 = 1 - m on the uniform prior, so A = m =
;; .99875 (k c/(1 - c) = 800 observations at strength 1, m = 801/802), at the
;; exact variance 1.4659e-5 (c .094975).
!(compileadd endpointKb (: k (And (A) (B)) (STV 1 0.5)))
!(compileadd endpointKb (: b (B) (STV 1 1)))
!(test
   (posterior-tv-near? 0.9987531172069826 0.000626947514199894 (let (: $_p (A) $tv) (query 300 endpointKb (: $p (A) $tv)) $tv))
   true)

;; Two observed compounds' messages act on A once, as one node: their
;; likelihoods multiply and the posterior is read once on the prior.
;; Or(A, B) and Or(A, C) at (.9, .9) with B and C false each give lambda1 = m,
;; lambda0 = 1 - m (m = .89989), so A = m^2/(m^2 + (1 - m)^2) = .98778. A
;; witness is its source evidence, not its position: the children in the other
;; order give the same value.
!(compileadd twoMessagesKb (: kab (Or (A) (B)) (STV 0.9 0.9)))
!(compileadd twoMessagesKb (: kac (Or (A) (C)) (STV 0.9 0.9)))
!(compileadd twoMessagesKb (: b (B) (STV 0 1)))
!(compileadd twoMessagesKb (: c (C) (STV 0 1)))
!(test
   (posterior-tv-near? 0.9877751209798359 0.0006477854325506413 (let (: $_p (A) $tv) (query 300 twoMessagesKb (: $p (A) $tv)) $tv))
   true)
!(compileadd twoMessagesReorderedKb (: kac (Or (C) (A)) (STV 0.9 0.9)))
!(compileadd twoMessagesReorderedKb (: kab (Or (B) (A)) (STV 0.9 0.9)))
!(compileadd twoMessagesReorderedKb (: b (B) (STV 0 1)))
!(compileadd twoMessagesReorderedKb (: c (C) (STV 0 1)))
!(test
   (posterior-tv-near? 0.9877751209798359 0.0006477854325506413 (let (: $_p (A) $tv) (query 300 twoMessagesReorderedKb (: $p (A) $tv)) $tv))
   true)

;; A part reads its messages on its population rate, here the rate set on it:
;; .01 at c .9, a stored count read once as its Laplace Beta (n = 7200, mean
;; 73/7202 = .010136). With Or(A, B) at (.9, .9) and B false,
;; A = .010136 m/(.010136 m + .989864 (1 - m)) = .0843.
!(set-base-rate ownRateKb (A $x) (STV 0.01 0.9))
!(compileadd ownRateKb (: k (Or (A a) (B a)) (STV 0.9 0.9)))
!(compileadd ownRateKb (: b (B a) (STV 0 1)))
!(test
   (posterior-tv-near? 0.08428696187255508 0.3832524998016349 (let (: $_p (A a) $tv) (query 300 ownRateKb (: $p (A a) $tv)) $tv))
   true)

;; Predictions sharing part of their evidence each move T by the share of
;; their uncertain evidence that is new: {rab, a, b}, {rbc, b, c} and
;; {rad, a, d} all apply, in an order fixed by what they carry. The
;; predictions read T's prior in a cycle, so the two orders reach the same
;; value to within the search's anytime convergence.
!(compileadd overlapOneKb (: a Pa (STV 0.9 0.9)))
!(compileadd overlapOneKb (: b Pb (STV 0.9 0.9)))
!(compileadd overlapOneKb (: c Pc (STV 0.9 0.9)))
!(compileadd overlapOneKb (: d Pd (STV 0.9 0.9)))
!(compileadd overlapOneKb (: u U (STV 0.5 0.9)))
!(compileadd overlapOneKb (: v V (STV 0.6 0.9)))
!(compileadd overlapOneKb (: w W (STV 0.7 0.9)))
!(compileadd overlapOneKb (: rab (Implication (And Pa Pb) (And T U)) (STV 0.8 0.5)))
!(compileadd overlapOneKb (: rbc (Implication (And Pb Pc) (And T V)) (STV 0.7 0.5)))
!(compileadd overlapOneKb (: rad (Implication (And Pa Pd) (And T W)) (STV 0.6 0.5)))
!(compileadd overlapTwoKb (: rad (Implication (And Pa Pd) (And T W)) (STV 0.6 0.5)))
!(compileadd overlapTwoKb (: rbc (Implication (And Pb Pc) (And T V)) (STV 0.7 0.5)))
!(compileadd overlapTwoKb (: rab (Implication (And Pa Pb) (And T U)) (STV 0.8 0.5)))
!(compileadd overlapTwoKb (: w W (STV 0.7 0.9)))
!(compileadd overlapTwoKb (: v V (STV 0.6 0.9)))
!(compileadd overlapTwoKb (: u U (STV 0.5 0.9)))
!(compileadd overlapTwoKb (: d Pd (STV 0.9 0.9)))
!(compileadd overlapTwoKb (: c Pc (STV 0.9 0.9)))
!(compileadd overlapTwoKb (: b Pb (STV 0.9 0.9)))
!(compileadd overlapTwoKb (: a Pa (STV 0.9 0.9)))
!(test (let* (((: (jeffrey-update (jeffrey-update $_u1 $_u2) $_u3) T (STV $s1 $_c1)) (query 300 overlapOneKb (: $p T $tv)))
              ((: (jeffrey-update (jeffrey-update $_v1 $_v2) $_v3) T (STV $s2 $_c2)) (query 300 overlapTwoKb (: $q T $tv2))))
         (< (abs-math (- $s1 $s2)) 0.001))
   true)

;; Inside a conditioning branch a compound's parts are read jointly from its
;; node: And(P, Q) at .9 (c .8) is one Pearl likelihood on the joint,
;; combined with the independent complement of R's stored Beta parameter.
!(compileadd poolKb (: bundle (And (P x) (Q x)) (STV 0.9 0.8)))
!(compileadd poolKb (: r (R x) (STV 0.3 0.9)))
!(test
   (let $posterior-s (let (: $_p $_t (STV $s $_c)) (query 300 poolKb (: $p (And (P x) (Q x) (Not (R x))) $tv)) $s) (< (abs-math (- $posterior-s 0.5245941698470277)) 1e-12))
   true)

;; A joint of a predicted compound's parts is the same in either order: K =
;; And(A, B, C) at .9 moves the uniform worlds to P* = .89956 (the prediction
;; revised with the parts' 1/8 at their exact count), so And(A, B) = P* +
;; (1 - P*)/7 = .91391 named either way.
!(compileadd jointOrderKb (: s S (STV 1.0 1.0)))
!(compileadd jointOrderKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))
!(test
   (posterior-tv-near? 0.9139069085402459 0.14919732113904566 (let (: $_p (And A B) $tv) (query 100 jointOrderKb (: $p (And A B) $tv)) $tv))
   true)
!(test
   (posterior-tv-near? 0.9139069085402459 0.14919732113904566 (let (: $_p (And B A) $tv) (query 100 jointOrderKb (: $p (And B A) $tv)) $tv))
   true)

;; A prediction at .5 is not neutral for a joint reader: K = And(A, B, C) at .5
;; gives And(A, B) = P* + (1 - P*)/7 = .57125 (P* = .49971).
!(compileadd halfKb (: s S (STV 1.0 1.0)))
!(compileadd halfKb (: r (Implication S (And A B C)) (STV 0.5 0.9)))
!(test (let (: $_p (And A B) $tv) (query 100 halfKb (: $p (And A B) $tv)) $tv)
   (STV 0.5712452783267684 0.02080511773903594))

;; At the variance bound s(1 - s) the confidence is 0: four observed
;; compounds' messages on A with uncertain siblings are five dimensions, past
;; the tensor rule, so A's variance is the bound.
!(compileadd boundKb (: k1 (And (A) (B1)) (STV 0.9 0.9)))
!(compileadd boundKb (: k2 (And (A) (B2)) (STV 0.9 0.9)))
!(compileadd boundKb (: k3 (And (A) (B3)) (STV 0.9 0.9)))
!(compileadd boundKb (: k4 (And (A) (B4)) (STV 0.9 0.9)))
!(compileadd boundKb (: b1 (B1) (STV 0.7 0.5)))
!(compileadd boundKb (: b2 (B2) (STV 0.7 0.5)))
!(compileadd boundKb (: b3 (B3) (STV 0.7 0.5)))
!(compileadd boundKb (: b4 (B4) (STV 0.7 0.5)))
!(test (posterior-tv-near? 0.9994694947927322 0.0006184187895021472 (let (: $_p (A) $tv) (query 300 boundKb (: $p (A) $tv)) $tv)) true)

;; A nested compound is one node over its atoms: And(A, Not(And(B, C))) at
;; (1, .9) is Pearl evidence m = 7201/7202 on the worlds A and not (B and C).
;; With B true and A uniform, C is true only where K fails: C = .5 (1 - m)/(.5
;; (1 - m) + .25) = .000278, and (B and C) the same, at the exact variance
;; 2.2e-6 (c .1354): the quadrature is refined until it settles against the
;; evidence boundary (129 nodes).
!(compileadd nestedKb (: k (And (A) (Not (And (B) (C)))) (STV 1 0.9)))
!(compileadd nestedKb (: b (B) (STV 1 1)))
!(test
   (posterior-tv-near? 0.0002776235424765082 0.0 (let (: $_p (And (B) (C)) $tv) (query 300 nestedKb (: $p (And (B) (C)) $tv)) $tv))
   true)
!(test
   (posterior-tv-near? 0.0002776235424765082 0.0 (let (: $_p (C) $tv) (query 300 nestedKb (: $p (C) $tv)) $tv))
   true)

;; A stored part is an input with its own Beta: A at (0, 1/801) is n = 1,
;; Beta(1, 2) with mean 1/3, not the point 0. With B false and Or(A, B) at
;; (.9, .9), A = (m/3)/(m/3 + 2 (1 - m)/3) = 6481/7923 = .8180.
!(compileadd storedPartKb (: a (A) (STV 0 0.0012484394506866417)))
!(compileadd storedPartKb (: b (B) (STV 0 1)))
!(compileadd storedPartKb (: k (Or (A) (B)) (STV 0.9 0.9)))
!(test
   (posterior-tv-near? 0.8179982329925534 0.0007868745546970322 (let (: $_p (A) $tv) (query 300 storedPartKb (: $p (A) $tv)) $tv))
   true)

;; Messages sharing an atom are one node over the union of their atoms:
;; Or(A, B) and Or(A, Not B) at (.9, .9) with A and B at (.5, .99). Where A
;; holds both hold (m^2); where it fails exactly one does (m (1 - m)), so
;; A = m^2/(m^2 + m (1 - m)) = m = .89989, whatever B is.
!(compileadd sharedAtomKb (: a (A) (STV 0.5 0.99)))
!(compileadd sharedAtomKb (: b (B) (STV 0.5 0.99)))
!(compileadd sharedAtomKb (: k1 (Or (A) (B)) (STV 0.9 0.9)))
!(compileadd sharedAtomKb (: k2 (Or (A) (Not (B))) (STV 0.9 0.9)))
!(test
   (posterior-tv-near? 0.8998889197445155 0.9821452875091857 (let (: $_p (A) $tv) (query 300 sharedAtomKb (: $p (A) $tv)) $tv))
   true)

;; A product of independent parts is a point only when every part is: And(A,
;; B, C) at (.9, .9), A at (.5, .99), B uniform, C at (1e-8, 1). B C keeps B's
;; spread, and A's variance is the exact 3.1564e-6 (c .990000250).
!(compileadd pointKb (: a (A) (STV 0.5 0.99)))
!(compileadd pointKb (: c (C) (STV 0.00000001 1)))
!(compileadd pointKb (: k (And (A) (B) (C)) (STV 0.9 0.9)))
!(test
   (posterior-tv-near? 0.5000000099861301 0.9900002178660449 (let (: $_p (A) $tv) (query 300 pointKb (: $p (A) $tv)) $tv))
   true)

;; At the bound the confidence is 0 against the strength itself: sixteen
;; observed And(A, B_i) at (.9, 1) with B_i at (.5, .5) put A at
;; 1 - 6.6e-12, past the tensor rule (17 dimensions), so its variance is
;; s(1 - s) and its confidence 0.
!(compileadd sixteenKb (: k0 (And (A) (B0)) (STV 0.9 1)))
!(compileadd sixteenKb (: b0 (B0) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k1 (And (A) (B1)) (STV 0.9 1)))
!(compileadd sixteenKb (: b1 (B1) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k2 (And (A) (B2)) (STV 0.9 1)))
!(compileadd sixteenKb (: b2 (B2) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k3 (And (A) (B3)) (STV 0.9 1)))
!(compileadd sixteenKb (: b3 (B3) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k4 (And (A) (B4)) (STV 0.9 1)))
!(compileadd sixteenKb (: b4 (B4) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k5 (And (A) (B5)) (STV 0.9 1)))
!(compileadd sixteenKb (: b5 (B5) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k6 (And (A) (B6)) (STV 0.9 1)))
!(compileadd sixteenKb (: b6 (B6) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k7 (And (A) (B7)) (STV 0.9 1)))
!(compileadd sixteenKb (: b7 (B7) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k8 (And (A) (B8)) (STV 0.9 1)))
!(compileadd sixteenKb (: b8 (B8) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k9 (And (A) (B9)) (STV 0.9 1)))
!(compileadd sixteenKb (: b9 (B9) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k10 (And (A) (B10)) (STV 0.9 1)))
!(compileadd sixteenKb (: b10 (B10) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k11 (And (A) (B11)) (STV 0.9 1)))
!(compileadd sixteenKb (: b11 (B11) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k12 (And (A) (B12)) (STV 0.9 1)))
!(compileadd sixteenKb (: b12 (B12) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k13 (And (A) (B13)) (STV 0.9 1)))
!(compileadd sixteenKb (: b13 (B13) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k14 (And (A) (B14)) (STV 0.9 1)))
!(compileadd sixteenKb (: b14 (B14) (STV 0.5 0.5)))
!(compileadd sixteenKb (: k15 (And (A) (B15)) (STV 0.9 1)))
!(compileadd sixteenKb (: b15 (B15) (STV 0.5 0.5)))
!(test (let (: $_p (A) $tv) (query 600 sixteenKb (: $p (A) $tv)) $tv)
   (STV 0.999999999993447 0.0))

;; Likelihood products run in log space: 22 messages for A and 22 against it
;; at m = 1 - 2^-52 cancel, leaving A's uniform prior.
!(compileadd opposedKb (: k0 (Or (A) (B0)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b0 (B0) (STV 0 1)))
!(compileadd opposedKb (: j0 (Or (Not (A)) (C0)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c0 (C0) (STV 0 1)))
!(compileadd opposedKb (: k1 (Or (A) (B1)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b1 (B1) (STV 0 1)))
!(compileadd opposedKb (: j1 (Or (Not (A)) (C1)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c1 (C1) (STV 0 1)))
!(compileadd opposedKb (: k2 (Or (A) (B2)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b2 (B2) (STV 0 1)))
!(compileadd opposedKb (: j2 (Or (Not (A)) (C2)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c2 (C2) (STV 0 1)))
!(compileadd opposedKb (: k3 (Or (A) (B3)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b3 (B3) (STV 0 1)))
!(compileadd opposedKb (: j3 (Or (Not (A)) (C3)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c3 (C3) (STV 0 1)))
!(compileadd opposedKb (: k4 (Or (A) (B4)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b4 (B4) (STV 0 1)))
!(compileadd opposedKb (: j4 (Or (Not (A)) (C4)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c4 (C4) (STV 0 1)))
!(compileadd opposedKb (: k5 (Or (A) (B5)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b5 (B5) (STV 0 1)))
!(compileadd opposedKb (: j5 (Or (Not (A)) (C5)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c5 (C5) (STV 0 1)))
!(compileadd opposedKb (: k6 (Or (A) (B6)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b6 (B6) (STV 0 1)))
!(compileadd opposedKb (: j6 (Or (Not (A)) (C6)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c6 (C6) (STV 0 1)))
!(compileadd opposedKb (: k7 (Or (A) (B7)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b7 (B7) (STV 0 1)))
!(compileadd opposedKb (: j7 (Or (Not (A)) (C7)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c7 (C7) (STV 0 1)))
!(compileadd opposedKb (: k8 (Or (A) (B8)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b8 (B8) (STV 0 1)))
!(compileadd opposedKb (: j8 (Or (Not (A)) (C8)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c8 (C8) (STV 0 1)))
!(compileadd opposedKb (: k9 (Or (A) (B9)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b9 (B9) (STV 0 1)))
!(compileadd opposedKb (: j9 (Or (Not (A)) (C9)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c9 (C9) (STV 0 1)))
!(compileadd opposedKb (: k10 (Or (A) (B10)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b10 (B10) (STV 0 1)))
!(compileadd opposedKb (: j10 (Or (Not (A)) (C10)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c10 (C10) (STV 0 1)))
!(compileadd opposedKb (: k11 (Or (A) (B11)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b11 (B11) (STV 0 1)))
!(compileadd opposedKb (: j11 (Or (Not (A)) (C11)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c11 (C11) (STV 0 1)))
!(compileadd opposedKb (: k12 (Or (A) (B12)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b12 (B12) (STV 0 1)))
!(compileadd opposedKb (: j12 (Or (Not (A)) (C12)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c12 (C12) (STV 0 1)))
!(compileadd opposedKb (: k13 (Or (A) (B13)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b13 (B13) (STV 0 1)))
!(compileadd opposedKb (: j13 (Or (Not (A)) (C13)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c13 (C13) (STV 0 1)))
!(compileadd opposedKb (: k14 (Or (A) (B14)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b14 (B14) (STV 0 1)))
!(compileadd opposedKb (: j14 (Or (Not (A)) (C14)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c14 (C14) (STV 0 1)))
!(compileadd opposedKb (: k15 (Or (A) (B15)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b15 (B15) (STV 0 1)))
!(compileadd opposedKb (: j15 (Or (Not (A)) (C15)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c15 (C15) (STV 0 1)))
!(compileadd opposedKb (: k16 (Or (A) (B16)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b16 (B16) (STV 0 1)))
!(compileadd opposedKb (: j16 (Or (Not (A)) (C16)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c16 (C16) (STV 0 1)))
!(compileadd opposedKb (: k17 (Or (A) (B17)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b17 (B17) (STV 0 1)))
!(compileadd opposedKb (: j17 (Or (Not (A)) (C17)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c17 (C17) (STV 0 1)))
!(compileadd opposedKb (: k18 (Or (A) (B18)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b18 (B18) (STV 0 1)))
!(compileadd opposedKb (: j18 (Or (Not (A)) (C18)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c18 (C18) (STV 0 1)))
!(compileadd opposedKb (: k19 (Or (A) (B19)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b19 (B19) (STV 0 1)))
!(compileadd opposedKb (: j19 (Or (Not (A)) (C19)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c19 (C19) (STV 0 1)))
!(compileadd opposedKb (: k20 (Or (A) (B20)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b20 (B20) (STV 0 1)))
!(compileadd opposedKb (: j20 (Or (Not (A)) (C20)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c20 (C20) (STV 0 1)))
!(compileadd opposedKb (: k21 (Or (A) (B21)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: b21 (B21) (STV 0 1)))
!(compileadd opposedKb (: j21 (Or (Not (A)) (C21)) (STV 0.9999999999999998 1)))
!(compileadd opposedKb (: c21 (C21) (STV 0 1)))
!(test (posterior-tv-near? 0.5000000000000275 0.002493765586036671 (let (: $_p (A) $tv) (query 900 opposedKb (: $p (A) $tv)) $tv)) true)

;; A compound that repeats an atom is one node over its distinct atoms:
;; (A or B) and (A or C) at (1, .99) with A, B, C at (.7, .9), (.6, .9), (.5,
;; .9) gives the event oracle's posterior (tests/tv_calibration_oracles.py, P5
;; X), A .8861, B .6456, C .5570, each at the oracle's confidence.
!(compileadd sharedLeafKb (: fA (A a) (STV 0.7 0.9)))
!(compileadd sharedLeafKb (: fB (B a) (STV 0.6 0.9)))
!(compileadd sharedLeafKb (: fC (C a) (STV 0.5 0.9)))
!(compileadd sharedLeafKb (: k0 (And (Or (A a) (B a)) (Or (A a) (C a))) (STV 1.0 0.99)))
!(test
   (posterior-tv-near? 0.8860509487947943 0.8475288093413195 (let (: $_p (A a) $tv) (query 1000 sharedLeafKb (: $p (A a) $tv)) $tv))
   true)
!(test
   (posterior-tv-near? 0.6455530963152154 0.8510264324080095 (let (: $_p (B a) $tv) (query 1000 sharedLeafKb (: $p (B a) $tv)) $tv))
   true)
!(test
   (posterior-tv-near? 0.5569721276747972 0.8540993689943807 (let (: $_p (C a) $tv) (query 1000 sharedLeafKb (: $p (C a) $tv)) $tv))
   true)

;; A part's population rate is read apart from the node: ninety-nine members
;; of A false and one true at c .9 give a rate of .01 at c .101 (n = 90),
;; Laplace mean 1.9/92 = .0207, so with Or(A, B) at (.9, .9) and B false
;; A = .0207 m/(.0207 m + .9793 (1 - m)) = .1593, not the uniform prior's .9.
!(compileadd rareKb (: f1 (A x1) (STV 0 0.9)))
!(compileadd rareKb (: f2 (A x2) (STV 0 0.9)))
!(compileadd rareKb (: f3 (A x3) (STV 0 0.9)))
!(compileadd rareKb (: f4 (A x4) (STV 0 0.9)))
!(compileadd rareKb (: f5 (A x5) (STV 0 0.9)))
!(compileadd rareKb (: f6 (A x6) (STV 0 0.9)))
!(compileadd rareKb (: f7 (A x7) (STV 0 0.9)))
!(compileadd rareKb (: f8 (A x8) (STV 0 0.9)))
!(compileadd rareKb (: f9 (A x9) (STV 0 0.9)))
!(compileadd rareKb (: f10 (A x10) (STV 0 0.9)))
!(compileadd rareKb (: f11 (A x11) (STV 0 0.9)))
!(compileadd rareKb (: f12 (A x12) (STV 0 0.9)))
!(compileadd rareKb (: f13 (A x13) (STV 0 0.9)))
!(compileadd rareKb (: f14 (A x14) (STV 0 0.9)))
!(compileadd rareKb (: f15 (A x15) (STV 0 0.9)))
!(compileadd rareKb (: f16 (A x16) (STV 0 0.9)))
!(compileadd rareKb (: f17 (A x17) (STV 0 0.9)))
!(compileadd rareKb (: f18 (A x18) (STV 0 0.9)))
!(compileadd rareKb (: f19 (A x19) (STV 0 0.9)))
!(compileadd rareKb (: f20 (A x20) (STV 0 0.9)))
!(compileadd rareKb (: f21 (A x21) (STV 0 0.9)))
!(compileadd rareKb (: f22 (A x22) (STV 0 0.9)))
!(compileadd rareKb (: f23 (A x23) (STV 0 0.9)))
!(compileadd rareKb (: f24 (A x24) (STV 0 0.9)))
!(compileadd rareKb (: f25 (A x25) (STV 0 0.9)))
!(compileadd rareKb (: f26 (A x26) (STV 0 0.9)))
!(compileadd rareKb (: f27 (A x27) (STV 0 0.9)))
!(compileadd rareKb (: f28 (A x28) (STV 0 0.9)))
!(compileadd rareKb (: f29 (A x29) (STV 0 0.9)))
!(compileadd rareKb (: f30 (A x30) (STV 0 0.9)))
!(compileadd rareKb (: f31 (A x31) (STV 0 0.9)))
!(compileadd rareKb (: f32 (A x32) (STV 0 0.9)))
!(compileadd rareKb (: f33 (A x33) (STV 0 0.9)))
!(compileadd rareKb (: f34 (A x34) (STV 0 0.9)))
!(compileadd rareKb (: f35 (A x35) (STV 0 0.9)))
!(compileadd rareKb (: f36 (A x36) (STV 0 0.9)))
!(compileadd rareKb (: f37 (A x37) (STV 0 0.9)))
!(compileadd rareKb (: f38 (A x38) (STV 0 0.9)))
!(compileadd rareKb (: f39 (A x39) (STV 0 0.9)))
!(compileadd rareKb (: f40 (A x40) (STV 0 0.9)))
!(compileadd rareKb (: f41 (A x41) (STV 0 0.9)))
!(compileadd rareKb (: f42 (A x42) (STV 0 0.9)))
!(compileadd rareKb (: f43 (A x43) (STV 0 0.9)))
!(compileadd rareKb (: f44 (A x44) (STV 0 0.9)))
!(compileadd rareKb (: f45 (A x45) (STV 0 0.9)))
!(compileadd rareKb (: f46 (A x46) (STV 0 0.9)))
!(compileadd rareKb (: f47 (A x47) (STV 0 0.9)))
!(compileadd rareKb (: f48 (A x48) (STV 0 0.9)))
!(compileadd rareKb (: f49 (A x49) (STV 0 0.9)))
!(compileadd rareKb (: f50 (A x50) (STV 0 0.9)))
!(compileadd rareKb (: f51 (A x51) (STV 0 0.9)))
!(compileadd rareKb (: f52 (A x52) (STV 0 0.9)))
!(compileadd rareKb (: f53 (A x53) (STV 0 0.9)))
!(compileadd rareKb (: f54 (A x54) (STV 0 0.9)))
!(compileadd rareKb (: f55 (A x55) (STV 0 0.9)))
!(compileadd rareKb (: f56 (A x56) (STV 0 0.9)))
!(compileadd rareKb (: f57 (A x57) (STV 0 0.9)))
!(compileadd rareKb (: f58 (A x58) (STV 0 0.9)))
!(compileadd rareKb (: f59 (A x59) (STV 0 0.9)))
!(compileadd rareKb (: f60 (A x60) (STV 0 0.9)))
!(compileadd rareKb (: f61 (A x61) (STV 0 0.9)))
!(compileadd rareKb (: f62 (A x62) (STV 0 0.9)))
!(compileadd rareKb (: f63 (A x63) (STV 0 0.9)))
!(compileadd rareKb (: f64 (A x64) (STV 0 0.9)))
!(compileadd rareKb (: f65 (A x65) (STV 0 0.9)))
!(compileadd rareKb (: f66 (A x66) (STV 0 0.9)))
!(compileadd rareKb (: f67 (A x67) (STV 0 0.9)))
!(compileadd rareKb (: f68 (A x68) (STV 0 0.9)))
!(compileadd rareKb (: f69 (A x69) (STV 0 0.9)))
!(compileadd rareKb (: f70 (A x70) (STV 0 0.9)))
!(compileadd rareKb (: f71 (A x71) (STV 0 0.9)))
!(compileadd rareKb (: f72 (A x72) (STV 0 0.9)))
!(compileadd rareKb (: f73 (A x73) (STV 0 0.9)))
!(compileadd rareKb (: f74 (A x74) (STV 0 0.9)))
!(compileadd rareKb (: f75 (A x75) (STV 0 0.9)))
!(compileadd rareKb (: f76 (A x76) (STV 0 0.9)))
!(compileadd rareKb (: f77 (A x77) (STV 0 0.9)))
!(compileadd rareKb (: f78 (A x78) (STV 0 0.9)))
!(compileadd rareKb (: f79 (A x79) (STV 0 0.9)))
!(compileadd rareKb (: f80 (A x80) (STV 0 0.9)))
!(compileadd rareKb (: f81 (A x81) (STV 0 0.9)))
!(compileadd rareKb (: f82 (A x82) (STV 0 0.9)))
!(compileadd rareKb (: f83 (A x83) (STV 0 0.9)))
!(compileadd rareKb (: f84 (A x84) (STV 0 0.9)))
!(compileadd rareKb (: f85 (A x85) (STV 0 0.9)))
!(compileadd rareKb (: f86 (A x86) (STV 0 0.9)))
!(compileadd rareKb (: f87 (A x87) (STV 0 0.9)))
!(compileadd rareKb (: f88 (A x88) (STV 0 0.9)))
!(compileadd rareKb (: f89 (A x89) (STV 0 0.9)))
!(compileadd rareKb (: f90 (A x90) (STV 0 0.9)))
!(compileadd rareKb (: f91 (A x91) (STV 0 0.9)))
!(compileadd rareKb (: f92 (A x92) (STV 0 0.9)))
!(compileadd rareKb (: f93 (A x93) (STV 0 0.9)))
!(compileadd rareKb (: f94 (A x94) (STV 0 0.9)))
!(compileadd rareKb (: f95 (A x95) (STV 0 0.9)))
!(compileadd rareKb (: f96 (A x96) (STV 0 0.9)))
!(compileadd rareKb (: f97 (A x97) (STV 0 0.9)))
!(compileadd rareKb (: f98 (A x98) (STV 0 0.9)))
!(compileadd rareKb (: f99 (A x99) (STV 0 0.9)))
!(compileadd rareKb (: f100 (A x100) (STV 1 0.9)))
!(compileadd rareKb (: k (Or (A a) (B a)) (STV 0.9 0.9)))
!(compileadd rareKb (: b (B a) (STV 0 1)))
!(test
   (posterior-tv-near? 0.15934960401677098 0.008068530748583989 (let (: $_p (A a) $tv) (query 300 rareKb (: $p (A a) $tv)) $tv))
   true)

;; Every moment path checks that its quadrature converged. A at a set rate
;; 1e-6, a hard Or(A, B) with B uniform and three near-neutral And(A, C_i) at
;; (.5000000001, 1): the And factors are constant to 1e-9 (their W a point),
;; and B's boundary layer, as thin as A's rate, is integrated on intervals
;; graded toward the endpoint. A = 1e-6/(1e-6 + (1 - 1e-6)/2) = 2e-6 at the
;; exact variance 2.3631e-11 (c .99064).
!(set-base-rate tinyRateKb (A $x) (STV 0.000001 1))
!(compileadd tinyRateKb (: k (Or (A a) (B a)) (STV 1 1)))
!(compileadd tinyRateKb (: k1 (And (A a) (C1 a)) (STV 0.5000000001 1)))
!(compileadd tinyRateKb (: k2 (And (A a) (C2 a)) (STV 0.5000000001 1)))
!(compileadd tinyRateKb (: k3 (And (A a) (C3 a)) (STV 0.5000000001 1)))
;; The shared node adds the certified error of integrating out the three
;; weak nuisance axes. The independent thin-boundary regression derives the
;; remaining variance in closed form (test_event_node.py).
!(test
   (posterior-tv-near? 1.9999980012019964e-06 0.00249377304868248
      (let (: $_p (A a) $tv) (query 300 tinyRateKb (: $p (A a) $tv)) $tv))
   true)

;; The bound is tested before any rounding: twenty-four observed And(A, B_i)
;; at (.9, 1) with B_i at (.5, .5) put A's odds at 5^24, so A rounds to 1, and
;; past the tensor rule its variance is the bound: confidence 0, not .9999.
!(compileadd roundedKb (: k0 (And (A) (B0)) (STV 0.9 1)))
!(compileadd roundedKb (: b0 (B0) (STV 0.5 0.5)))
!(compileadd roundedKb (: k1 (And (A) (B1)) (STV 0.9 1)))
!(compileadd roundedKb (: b1 (B1) (STV 0.5 0.5)))
!(compileadd roundedKb (: k2 (And (A) (B2)) (STV 0.9 1)))
!(compileadd roundedKb (: b2 (B2) (STV 0.5 0.5)))
!(compileadd roundedKb (: k3 (And (A) (B3)) (STV 0.9 1)))
!(compileadd roundedKb (: b3 (B3) (STV 0.5 0.5)))
!(compileadd roundedKb (: k4 (And (A) (B4)) (STV 0.9 1)))
!(compileadd roundedKb (: b4 (B4) (STV 0.5 0.5)))
!(compileadd roundedKb (: k5 (And (A) (B5)) (STV 0.9 1)))
!(compileadd roundedKb (: b5 (B5) (STV 0.5 0.5)))
!(compileadd roundedKb (: k6 (And (A) (B6)) (STV 0.9 1)))
!(compileadd roundedKb (: b6 (B6) (STV 0.5 0.5)))
!(compileadd roundedKb (: k7 (And (A) (B7)) (STV 0.9 1)))
!(compileadd roundedKb (: b7 (B7) (STV 0.5 0.5)))
!(compileadd roundedKb (: k8 (And (A) (B8)) (STV 0.9 1)))
!(compileadd roundedKb (: b8 (B8) (STV 0.5 0.5)))
!(compileadd roundedKb (: k9 (And (A) (B9)) (STV 0.9 1)))
!(compileadd roundedKb (: b9 (B9) (STV 0.5 0.5)))
!(compileadd roundedKb (: k10 (And (A) (B10)) (STV 0.9 1)))
!(compileadd roundedKb (: b10 (B10) (STV 0.5 0.5)))
!(compileadd roundedKb (: k11 (And (A) (B11)) (STV 0.9 1)))
!(compileadd roundedKb (: b11 (B11) (STV 0.5 0.5)))
!(compileadd roundedKb (: k12 (And (A) (B12)) (STV 0.9 1)))
!(compileadd roundedKb (: b12 (B12) (STV 0.5 0.5)))
!(compileadd roundedKb (: k13 (And (A) (B13)) (STV 0.9 1)))
!(compileadd roundedKb (: b13 (B13) (STV 0.5 0.5)))
!(compileadd roundedKb (: k14 (And (A) (B14)) (STV 0.9 1)))
!(compileadd roundedKb (: b14 (B14) (STV 0.5 0.5)))
!(compileadd roundedKb (: k15 (And (A) (B15)) (STV 0.9 1)))
!(compileadd roundedKb (: b15 (B15) (STV 0.5 0.5)))
!(compileadd roundedKb (: k16 (And (A) (B16)) (STV 0.9 1)))
!(compileadd roundedKb (: b16 (B16) (STV 0.5 0.5)))
!(compileadd roundedKb (: k17 (And (A) (B17)) (STV 0.9 1)))
!(compileadd roundedKb (: b17 (B17) (STV 0.5 0.5)))
!(compileadd roundedKb (: k18 (And (A) (B18)) (STV 0.9 1)))
!(compileadd roundedKb (: b18 (B18) (STV 0.5 0.5)))
!(compileadd roundedKb (: k19 (And (A) (B19)) (STV 0.9 1)))
!(compileadd roundedKb (: b19 (B19) (STV 0.5 0.5)))
!(compileadd roundedKb (: k20 (And (A) (B20)) (STV 0.9 1)))
!(compileadd roundedKb (: b20 (B20) (STV 0.5 0.5)))
!(compileadd roundedKb (: k21 (And (A) (B21)) (STV 0.9 1)))
!(compileadd roundedKb (: b21 (B21) (STV 0.5 0.5)))
!(compileadd roundedKb (: k22 (And (A) (B22)) (STV 0.9 1)))
!(compileadd roundedKb (: b22 (B22) (STV 0.5 0.5)))
!(compileadd roundedKb (: k23 (And (A) (B23)) (STV 0.9 1)))
!(compileadd roundedKb (: b23 (B23) (STV 0.5 0.5)))
!(test (let (: $_p (A) $tv) (query 900 roundedKb (: $p (A) $tv)) $tv)
   (STV 1.0 0.0))

;; A materialized row is no source of the population's rate: A(x), derived
;; from the compounds and materialized, leaves A(a)'s prior as in a fresh KB.
!(compileadd materializedKb (: k (Or (A a) (A x)) (STV 0.9 0.9)))
!(compileadd materializedKb (: kx (And (A x) (B x)) (STV 0.95 0.9)))
!(compileadd materializedKb (: bx (B x) (STV 1 1)))
!(test (let (: $_p (A x) $_tv) (query-materialize 300 materializedKb (: $p (A x) $tv)) true) true)
!(test
   (posterior-tv-near? 0.5113908867909669 0.0003136464033718647 (let (: $_p (A a) $tv) (query 300 materializedKb (: $p (A a) $tv)) $tv))
   true)

;; An update's new raw sources: one newly certain source makes it unbounded
;; (-1) even beside a source the value holds; a disjoint source whose truth
;; value cannot be read counts nothing (0); a readable one its count (.9 at
;; c .9: 7200).
!(compileadd sourceCountKb (: u (U) (STV 0.7 0.9)))
!(compileadd sourceCountKb (: t (T) (STV 1 1)))
!(test (evidence-unique-count 800.0 (evidence-set ((fact-ev (sourceCountKb MAIN Nil) u (U))))
          (evidence-set ((fact-ev (sourceCountKb MAIN Nil) u (U)) (fact-ev (sourceCountKb MAIN Nil) t (T)))))
   -1.0)
!(test (evidence-unique-count 800.0 (evidence-set ()) (evidence-set ((rule-ev sourceCountKb unknownRule))))
   0.0)
!(test (evidence-unique-count 800.0 (evidence-set ()) (evidence-set ((fact-ev (sourceCountKb MAIN Nil) u (U)))))
   7200.000000000002)

;; A connective is recognised by its head's identity: a variable predicate
;; heads an atom and stays unbound.
!(test (let ($formula $atoms) (node-formula (And ($p a) ($q b))) (data $formula (is-var $p) (is-var $q)))
   (data (And 0 1) true true))
