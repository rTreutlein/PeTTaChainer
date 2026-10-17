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
      (D x) (STV 0.8600000000000001 0.055342791051553444)))

;; With uncertain facts and both branches of each rule, the result is the
;; chain rule: P(C | A) = 0.5 * 0.9 + 0.5 * 0.3 = 0.6, P(A and C) = 0.48, and
;; P(D) = 0.48 * 0.8 + 0.52 * 0.1 = 0.436. Taking A and C as independent would
;; give 0.4024.
!(compileadd chainKb (: a (A x) (STV 0.8 0.9)))
!(compileadd chainKb (: b (B x) (STV 0.5 0.9)))
!(compileadd chainKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd chainKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test (map-flat conditioning-tv (collapse (query 200 chainKb (: $p (D x) $tv))))
   ((STV 0.43600000000000005 0.9446591724475808)))

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

;; A premise reading the very statement another premise read reads it as known
;; under the condition: P(K and K) is P(K) (before: no answer).
!(compileadd pairKb (: p (P x) (STV 0.9 0.9)))
!(compileadd pairKb (: pairRule (Implication (And (P $u) (P $w)) (Pair $u $w)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test (query 100 pairKb (: $p (Pair x x) $tv))
   (: (conditioned p (by pairRule (conjunction (given true) (given true))) (by pairRule (conjunction (given false) (given false)))) (Pair x x) (STV 0.9 0.8999999977943337)))

;; #74: the remaining allowance pays for the actual conditioned rows, even
;; when it cannot prepay the dependency estimate. The small query now gets
;; the same conditioned answer as a later query with a large allowance.
!(compileadd budgetKb (: a (A x) (STV 1.0 0.9)))
!(compileadd budgetKb (: b (B x) (STV 1.0 0.9)))
!(compileadd budgetKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(compileadd budgetKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))

!(test (map-flat conditioning-tv (collapse (query 3 budgetKb (: $p (D x) $tv))))
   ((STV 0.81 0.9047610934410989)))
!(test (map-flat conditioning-tv (collapse (query 50 budgetKb (: $p (D x) $tv))))
   ((STV 0.81 0.9047610934410989)))

;; A forward run evaluates the rows it builds as a query does, so it conditions
;; too, and derives D with the value a backward query reads.
(: fwd-selected (-[det]-> KB Statement (List (Statement KBContext Proof TV))))
(= (fwd-selected $kb $type)
   (collapse (once (match &kb ($type ($kb MAIN Nil) $prf $tv) (assemble-stored-runtime-fact $type ($kb MAIN Nil) $prf $tv)))))

(: forward-value-of (-[det]-> Atom (List (Statement KBContext Proof TV)) (List Atom)))
(= (forward-value-of $_type ()) ())
(= (forward-value-of $type (cons ($statement $_kbctx $proof $tv) $rest))
   (if (== $statement $type) (cons ((sk-full-proof $proof) $tv) ()) (forward-value-of $type $rest)))

!(compileadd forwardKb (: a (A x) (STV 0.8 0.9)))
!(compileadd forwardKb (: b (B x) (STV 0.5 0.9)))
!(compileadd forwardKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd forwardKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (forward-value-of (D x)
      (forward-chain 50 forwardKb (append-flat (fwd-selected forwardKb (A x)) (fwd-selected forwardKb (B x)))))
   (((conditioned a (by r2 (conjunction (given true) (by r1 (conjunction (given true) b))))
        (by r2 (conjunction (given false) (by r1 (conjunction (given false) b)))))
     (STV 0.43600000000000005 0.9446591724475808))))
!(test (map-flat conditioning-tv (collapse (query 200 forwardKb (: $p (D x) $tv))))
   ((STV 0.43600000000000005 0.9446591724475808)))

;; A certain fact is exact whether its evidence is shared or not, so reusing it
;; joins as usual, with no conditioning.
!(compileadd certainKb (: a (A x) (STV 1.0 1.0)))
!(compileadd certainKb (: b (B x) (STV 0.5 0.9)))
!(compileadd certainKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.3 0.9))))
!(compileadd certainKb (: r2 (Implication (And (A $v) (C $v)) (D $v)) (CTV (STV 0.8 0.9) (STV 0.1 0.9))))

!(test
   (case (forward-value-of (D x)
            (forward-chain 50 certainKb (append-flat (fwd-selected certainKb (A x)) (fwd-selected certainKb (B x))))) (
      ((cons ($proof $_tv) ()) $proof)
      ($_other $_other)))
   (by r2 (conjunction a (by r1 (conjunction a b)))))

;; A view read again under a condition is admitted as a stored view is: not
;; when it depends on what the reading rows exclude. Read for a row that
;; excludes A, C's view under B known still used A's fact, so it is left out;
;; otherwise A could support itself through it.
!(compileadd givenKb (: a (A x) (STV 1.0 0.9)))
!(compileadd givenKb (: b (B x) (STV 1.0 0.9)))
!(compileadd givenKb (: r1 (Implication (And (A $v) (B $v)) (C $v)) (CTV (STV 0.9 0.9) (STV 0.0 1.0))))
!(collapse (query 50 givenKb (: $p (C x) $tv)))
!(test
   (let* (($a (sk-key (A x) (givenKb MAIN Nil)))
          ($b (sk-key (B x) (givenKb MAIN Nil)))
          ($c (sk-key (C x) (givenKb MAIN Nil)))
          ($ch (index-hash $c)))
      (map-semidet (sk-given-view (cons (sk-given (index-hash $b) $b true) ()) (cons (index-hash $a) ()) $ch $c)
         (sk-admitted-versions $ch $c sk-any-filter ())))
   (sk-none))
