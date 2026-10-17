!(import! &self ../../pettachainer/metta/petta_chainer)

;; A default with an exception (ONA penguin.nal; ChainerGame
;; benchmarks/ona/nal_pln/penguin.metta): birds fly, penguins do not. The bird
;; rule reads (Member pingu Bird), derived from (Member pingu Penguin), the
;; very fact the penguin rule reads: its antecedent is a generalization of the
;; penguin rule's, so the bird rate is only the prior the penguin rate is read
;; under. Revised, the two gave 0.33; NAL answers 0.0.
!(compileadd penguinKb (: f1 (Member pingu Penguin) (STV 1.0 0.9)))
!(compileadd penguinKb (: f2 (Member sam Raven) (STV 1.0 0.9)))
!(compileadd penguinKb (: r1 (Implication (Member $x Penguin) (Fly $x)) (STV 0.0 0.9)))
!(compileadd penguinKb (: f3 (Inheritance Raven Bird) (STV 1.0 0.9)))
!(compileadd penguinKb (: f4 (Inheritance Penguin Bird) (STV 1.0 0.9)))
!(compileadd penguinKb (: r2 (Implication (Member $x Bird) (Fly $x)) (STV 1.0 0.9)))
!(test (query 100 penguinKb (: $p (Fly sam) $tv))
   (: (by r2 (by (no_inverse (member-inheritance-implication f3)) f2)) (Fly sam) (STV 1.0 0.818161154650831)))
!(test (query 100 penguinKb (: $p (Fly pingu) $tv))
   (: (specializes (by r1 f1) (by r2 (by (no_inverse (member-inheritance-implication f4)) f1)) (STV 0.0 0.8571343532227984) (STV 1.0 0.818161154650831)) (Fly pingu) (STV 4.158453126045601e-05 0.8571343532227984)))
