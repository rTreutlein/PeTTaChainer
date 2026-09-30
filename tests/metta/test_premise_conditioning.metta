!(import! &self ../../pettachainer/metta/petta_chainer)

;; A rule whose premise was derived from a fact the rule also reads is
;; evaluated conditioned on that fact's statement: once known true, once known
;; false, mixed by its value. The fact's evidence counts once.

(= (conditioning-tv (: $_proof $_type $tv)) $tv)

;; A, B, A & B -> C, A & C -> D: D follows, reusing A.
!(compileadd reuseKb (: a (A x) (STV 1.0 0.9)))
!(compileadd reuseKb (: b (B x) (STV 1.0 0.9)))
!(compileadd reuseKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (STV 0.9 0.9)))
!(compileadd reuseKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (STV 0.9 0.9)))

!(test (query 200 reuseKb (: $p (D x) $tv))
   (: (conditioned a (by r2 (conjunction (given true) (by r1 (conjunction (given true) b))))
         (by r2 (conjunction (given false) (by r1 (conjunction (given false) b)))))
      (D x) (STV 0.81 0.9047184791728005)))

;; With uncertain facts and both branches of each rule, the result is the
;; chain rule: P(C | A) = 0.5 * 0.9 + 0.5 * 0.3 = 0.6, P(A and C) = 0.48, and
;; P(D) = 0.48 * 0.8 + 0.52 * 0.1 = 0.436. Taking A and C as independent would
;; give 0.4024.
!(compileadd chainKb (: a (A x) (STV 0.8 0.9)))
!(compileadd chainKb (: b (B x) (STV 0.5 0.9)))
!(compileadd chainKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd chainKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test (map-flat conditioning-tv (collapse (query 200 chainKb (: $p (D x) $tv))))
   ((STV 0.43600000000000005 0.9446591724475807)))

;; A statement shared only inside two derived premises: A and B both follow
;; from X, so C is mixed over X.
!(compileadd hiddenKb (: x (X) (STV 0.7 0.9)))
!(compileadd hiddenKb (: ra (Implication (X) (A)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd hiddenKb (: rb (Implication (X) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd hiddenKb (: rc (Implication (And (A) (B)) (C)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 hiddenKb (: $p (C) $tv))
   (: (conditioned x (by rc (conjunction (by ra (given true)) (by rb (given true))))
         (by rc (conjunction (by ra (given false)) (by rb (given false)))))
      (C) (STV 0.7 0.899999998985212)))

;; A premise reading the very statement another premise read gains nothing,
;; P(K and K) being P(K), and is not conditioned.
!(compileadd pairKb (: p (P x) (STV 0.9 0.9)))
!(compileadd pairKb (: pairRule (Implication (And (P $u) (P $w)) (Pair $u $w)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 pairKb (: $p (Pair x x) $tv)) ())

;; Conditioning is paid for from the evaluation allowance. A query whose
;; allowance cannot pay leaves the row waiting; a later query that needs it
;; and can pay conditions it.
!(compileadd budgetKb (: a (A x) (STV 1.0 0.9)))
!(compileadd budgetKb (: b (B x) (STV 1.0 0.9)))
!(compileadd budgetKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(compileadd budgetKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))

!(test (query 3 budgetKb (: $p (D x) $tv)) ())
!(test (map-flat conditioning-tv (collapse (query 50 budgetKb (: $p (D x) $tv))))
   ((STV 0.81 0.9047610934410989)))

;; The forward chainer does not condition: it refuses a premise overlapping
;; what the rule already read, so it derives C but not D. A stored fact it
;; derived from a statement a later backward query conditions on is left out
;; under the condition, so that query still conditions D correctly.
(: fwd-selected (-[det]-> KB Statement (List (Statement KBContext Proof TV))))
(= (fwd-selected $kb $type)
   (collapse (once (match &kb ($type ($kb MAIN Nil) $prf $tv) (assemble-stored-runtime-fact $type ($kb MAIN Nil) $prf $tv)))))

!(compileadd forwardKb (: a (A x) (STV 0.8 0.9)))
!(compileadd forwardKb (: b (B x) (STV 0.5 0.9)))
!(compileadd forwardKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd forwardKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (let $_ (forward-chain 50 forwardKb (append-flat (fwd-selected forwardKb (A x)) (fwd-selected forwardKb (B x))))
      (collapse (match &kb (($statement x) (forwardKb MAIN Nil) $_prf $_tv) $statement)))
   (A B C))
!(test (map-flat conditioning-tv (collapse (query 200 forwardKb (: $p (D x) $tv))))
   ((STV 0.43600000000000005 0.9446591724475807)))

;; A certain fact is exact whether its evidence is shared or not, so reusing it
;; joins as usual, forward and backward, with no conditioning.
!(compileadd certainKb (: a (A x) (STV 1.0 1.0)))
!(compileadd certainKb (: b (B x) (STV 0.5 0.9)))
!(compileadd certainKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd certainKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (let $_ (forward-chain 50 certainKb (append-flat (fwd-selected certainKb (A x)) (fwd-selected certainKb (B x))))
      (collapse (match &kb ((D x) (certainKb MAIN Nil) $prf $_tv) $prf)))
   ((by r2 (conjunction a (by r1 (conjunction a b))))))
