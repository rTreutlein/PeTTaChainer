!(import! &self ../../pettachainer/metta/petta_chainer)
!(import! &self ./posterior_assertions)

;; An implication query proves its consequent under the positive assumption
;; of its antecedent, returning an STV. For a rule S -> (A and B and C), the
;; consequent K is a prediction at 0.9 (confidence 0.9 through MP), which
;; moves its parts from their uniform priors by probability kinematics
;; (event-moment-node.md, Jeffrey), K revised with the parts' own estimate
;; to P* = .8996. (And A B) is K's node joint row: P* + (1 - P*) P(AB | not K)
;; = .8996 + .1004 (.125/.875) = .9139, its confidence the uniform priors'. The
;; negative branch remains in internal rule storage for modus ponens.

!(compileadd ctvKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (let (: (conditional-implication ((node-joint (And 0 1) (by r (ctx proof 0))) (conjunction cpu cpu cpu))) (Implication S (And A B)) (STV $posterior-s $posterior-c)) (query 100 ctvKb (: $prf (Implication S (And A B)) $tv)) (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (STV $posterior-s $posterior-c)))
   true)

;; The query's truth-value pattern gives the same value. A single part is its
;; Jeffrey update: P* + (1 - P*) P(A | not K) = .8996 + .1004 (.375/.875) =
;; .9426 (P* = .8996, the parts' 1/8 at their exact count 4.1). The parts in
;; another order are the same joint row (a connective is commutative): .9139.
!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And A B)) $pos)) $tv))
   true)

!(test
   (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S A) $tv)) $tv)
   (STV 0.9426046056947345 0.07193756506090739))

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And B A)) $tv)) $tv))
   true)

;; An STV query asks for the positive side, which equals the Assuming query.
!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Implication S (And A B)) (STV $s $c))) $tv))
   true)

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 ctvKb (: $prf (Assuming S (And A B)) $tv)) $tv))
   true)

;; An STV rule over a variable. Its negative branch comes from the base rates
;; of both sides, which no fact here observes, so the refuting side has no
;; evidence. The ground query and the open one, over a hypothetical
;; individual, agree.
!(compileadd stvKb (: r (Implication (S $x) (And (A $x) (B $x) (C $x))) (STV 0.9 0.9)))

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 stvKb (: $prf (Implication (S x) (And (A x) (B x))) $tv)) $tv))
   true)

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 stvKb (: $prf (Implication (S $y) (And (A $y) (B $y))) $tv)) $tv))
   true)

;; A nested conclusion, S -> (A and (B and C)), is one node over its atoms A,
;; B and C, the same worlds as (And A B C): (B and C) and (A and B) are its
;; joint rows, each P* + (1 - P*) (1/8)/(7/8) = .8996 + .1004/7 = .9139 (the
;; exact .9 + .1/7 = .9143 at P* = .9; P* is the prediction revised with the
;; atoms' 1/8).
!(compileadd nestedKb (: r (Implication S (And A (And B C))) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And B C)) $tv)) $tv))
   true)

!(test
   (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (let (: $_prf $_type $tv) (query 100 nestedKb (: $prf (Implication S (And A B)) $tv)) $tv))
   true)

;; A part's update reads the other parts apart from the compound: their own
;; views off the same source would be no evidence apart from it, so with no
;; other views they are at their uniform priors, and A and (And A B) take the
;; values above. A certain fact S shares no evidence, so the shared-evidence
;; check does not stop them either.
!(compileadd mainKb (: s S (STV 1.0 1.0)))
!(compileadd mainKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (query 100 mainKb (: $prf A $tv))
   (: ((node-jeffrey 0 (by r s) (prediction (STV 0.9 0.9)) (conditionals (0.25 0.04861111111111111) (0.0 0.0))) (conjunction cpu cpu))
      A (STV 0.9426046056947345 0.07193756506090739)))

!(test
   (let (: ((node-joint (And 0 1) (by r s)) (conjunction cpu cpu cpu)) (And A B) (STV $posterior-s $posterior-c)) (query 100 mainKb (: $prf (And A B) $tv)) (posterior-tv-near? 0.9139069085421017 0.1491973211523703 (STV $posterior-s $posterior-c)))
   true)

;; Other parts known apart from the source are evidence: with B and C stored,
;; P(K | A) = .9023 (their predictive strengths' product), and A moves from its
;; uniform prior to .8999 + .1 P(A | not K) = .8999 + .1 (.5 .0977/.5489) = .9088.
!(compileadd evidenceKb (: s S (STV 1.0 1.0)))
!(compileadd evidenceKb (: b B (STV 0.95 0.9)))
!(compileadd evidenceKb (: c C (STV 0.95 0.9)))
!(compileadd evidenceKb (: r (Implication S (And A B C)) (CTV (STV 0.9 0.9) (STV 0.2 0.9))))

!(test
   (let (: ((node-jeffrey 0 (by r s) (prediction (STV 0.9 0.9))
               (conditionals ($sibling-mean $sibling-variance) (0.0 0.0)))
            (conjunction b c)) A (STV $answer-s $answer-c))
      (query 100 evidenceKb (: $prf A $tv))
      (and (posterior-tv-near? 0.9087531046647177 0.5094337286104271 (STV $answer-s $answer-c))
           (and (< (abs-math (- (the Number $sibling-mean) 0.9022625815702248)) 1e-12)
                (< (abs-math (- (the Number $sibling-variance) 1.192811113370773e-05)) 1e-12))))
   true)
