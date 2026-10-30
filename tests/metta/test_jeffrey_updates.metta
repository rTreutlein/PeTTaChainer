!(import! &self ../../pettachainer/metta/petta_chainer)

;; A predicted compound K moves its parts by probability kinematics to the
;; revision of its prediction with the parts' own estimate
;; (event-moment-node.md, Jeffrey): P* = (n_parts P_parts + n_rule s)/(n_parts +
;; n_rule), n_rule = k c/(1 - c), and a part's value p moves to
;; P* p f1/P_parts + (1 - P*) p (1 - f1)/(1 - P_parts), f1 = P(K | part), f0 =
;; P(K | not part).
;;
;; The worked example: K = And(B, C), B and C at .9 and .6 (c .9), so f1 = .9
;; (B's variance 1.25e-5) and f0 = 0, P_parts = .54 with n_parts about 7885.
;; A prediction of .8 at c .1 (n_rule 89) barely moves C; at c .99 (n_rule
;; 79200) it nearly adopts .8.
!(test (jeffrey-posterior 800.0 0.6 0.9 (STV 0.8 0.1) (conditionals (0.9 0.0000125) (0.0 0.0)))
   (STV 0.6025201298611803 0.9010392633166715))
!(test (jeffrey-posterior 800.0 0.6 0.9 (STV 0.8 0.99) (conditionals (0.9 0.0000125) (0.0 0.0)))
   (STV 0.8056149064756583 0.9855009344397969))
;; No confidence in the prediction leaves the part where it was.
!(test (let (STV $s $_c) (jeffrey-posterior 800.0 0.6 0.9 (STV 0.8 0.0) (conditionals (0.9 0.0000125) (0.0 0.0))) $s)
   0.6)
;; Near certain, it adopts the prediction: .8 P(C | K) + .2 P(C | not K) =
;; .8 + .2 (.6 .1/.46) = .8261.
!(test (let (STV $s $_c) (jeffrey-posterior 800.0 0.6 0.9 (STV 0.8 0.999999) (conditionals (0.9 0.0000125) (0.0 0.0)))
   (< (abs-math (- $s 0.8260869565)) 0.0002))
   true)

;; Two predicted compounds move one part, each update after the other, in an
;; order fixed by what they carry: the same value whatever order the atoms
;; arrived in. With no other view of C the first applies to the uniform prior.
!(compileadd orderOneKb (: s S (STV 1 1)))
!(compileadd orderOneKb (: b B (STV 0.9 0.9)))
!(compileadd orderOneKb (: d D (STV 0.5 0.9)))
!(compileadd orderOneKb (: r1 (Implication S (And B C)) (STV 0.8 0.6)))
!(compileadd orderOneKb (: r2 (Implication S (Or C D)) (STV 0.9 0.6)))

!(compileadd orderTwoKb (: r2 (Implication S (Or C D)) (STV 0.9 0.6)))
!(compileadd orderTwoKb (: r1 (Implication S (And B C)) (STV 0.8 0.6)))
!(compileadd orderTwoKb (: d D (STV 0.5 0.9)))
!(compileadd orderTwoKb (: b B (STV 0.9 0.9)))
!(compileadd orderTwoKb (: s S (STV 1 1)))

(= (jeffrey-at? $es $ec (: $_proof $_type (STV $s $c)))
   (if (< (abs-math (- $s $es)) 1e-9) (< (abs-math (- $c $ec)) 1e-9) false))
!(test (map-flat (jeffrey-at? 0.8124288815302391 0.41655546676650934) (collapse (query 300 orderOneKb (: $p C $tv))))
   (true))
!(test (map-flat (jeffrey-at? 0.8124288815302391 0.41655546676650934) (collapse (query 300 orderTwoKb (: $p C $tv))))
   (true))
;; The value is the two updates in turn: And(B, C)'s (prediction .8, P(K | C)
;; = B's .8999) on the uniform prior, then Or(C, D)'s (prediction .9, P(K | not
;; C) = D's .5) on that.
!(test (let* (((STV $s1 $c1) (jeffrey-posterior 800.0 0.5 0.0 (STV 0.7999999999994246 0.5999999999602145)
                                (conditionals (0.8998889197445155 1.2507129232952607e-05) (0.0 0.0))))
              ((STV $s2 $c2) (jeffrey-posterior 800.0 $s1 $c1 (STV 0.9000001109255314 0.5999999703223341)
                                (conditionals (1.0 0.0) (0.5 3.470776065522818e-05)))))
          (and (< (abs-math (- $s2 0.8124288815302391)) 1e-9) (< (abs-math (- $c2 0.41655546676650934)) 1e-9)))
   true)

;; An observation of the part merges first; the prediction then moves the
;; merged value, its observation's (.6, .9) the prior the update reads.
!(compileadd observedKb (: s S (STV 1 1)))
!(compileadd observedKb (: b B (STV 0.9 0.9)))
!(compileadd observedKb (: c C (STV 0.6 0.9)))
!(compileadd observedKb (: r1 (Implication S (And B C)) (STV 0.8 0.6)))
!(test (map-flat (jeffrey-at? 0.6298604820109766 0.9122139583637969) (collapse (query 300 observedKb (: $p C $tv))))
   (true))
!(test (let (STV $s $c) (jeffrey-posterior 800.0 0.6 0.9 (STV 0.7999999862197208 0.5999999834245703)
                           (conditionals (0.8998889197445155 1.2507129232952607e-05) (0.0 0.0)))
          (and (< (abs-math (- $s 0.6298604820109766)) 1e-9) (< (abs-math (- $c 0.9122139583637969)) 1e-9)))
   true)
