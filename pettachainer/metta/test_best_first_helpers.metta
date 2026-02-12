!(import! &self petta_chainer)

;; Confidence extraction defaults and concrete values.
!(test
    (tv-confidence (STV 0.7 0.35))
    0.35)

!(test
    (tv-confidence maybeUnknown)
    1.0)

;; Premise confidence extraction from compiled CPU truth formulas.
!(test
    (premise-expected-confidence (CPU MpFormula ((STV 1.0 0.6) (STV 0.8 0.9)) (STV 0.8 0.6)))
    0.6)

!(test
    (premise-expected-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) (STV 0.8 0.4)))
    0.4)

!(test
    (premise-expected-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) (STV 0.9 0.7)))
    0.7)

!(test
    (premise-expected-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) (STV 0.9 0.4)))
    0.4)


!(test
    (premise-expected-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $res))
    0.4)

;; Nested premise list confidence (min over expected premise confidences).
!(test
    (premises-expected-confidence
        ((CPU MpFormula ((STV 1.0 0.2) (STV 1.0 1.0)) $tv1)
         ((CPU MpFormula ((STV 1.0 0.55) $tv1) $tv2) Nil)))
    0.2)

;; Priority queue ordering: larger score should be first.
!(test
    (pq-insert (cons (qitem 0.5 a goalA) ()) (qitem 0.8 b goalB))
    (cons (qitem 0.8 b goalB) (cons (qitem 0.5 a goalA) ())))

!(test
    (pq-insert (cons (qitem 0.8 b goalB) ()) (qitem 0.4 c goalC))
    (cons (qitem 0.8 b goalB) (cons (qitem 0.4 c goalC) ())))

;; Rule candidate score derives from compiled rule premises.
!(test
    (candidate-from-match
        (((CPU MpFormula ((STV 1.0 0.62) (STV 1.0 1.0)) $tv) Nil)
         |- (: (kb MAIN ()) demoPrf (DemoGoal) $tv)))
    (qitem 0.62
           ((CPU MpFormula ((STV 1.0 0.62) (STV 1.0 1.0)) $tv) Nil)
           (: (kb MAIN ()) demoPrf (DemoGoal) $tv)))
