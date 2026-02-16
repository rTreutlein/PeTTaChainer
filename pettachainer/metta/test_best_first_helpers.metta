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
    (premise-expected-confidence (CPU MpFormula ((STV 1.0 0.6) (STV 0.8 0.9)) $out))
    0.6)

!(test
    (premise-expected-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
    0.4)

!(test
    (premise-expected-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
    0.7)

!(test
    (premise-expected-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
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

;; Heap queue ordering and duplicate retention.
!(test
    (let* (($pq1 (add_to_heap (empty_heap) -0.5 (qitem 0.5 a goalA)))
           ($pq (add_to_heap $pq1 -0.8 (qitem 0.8 b goalB))))
      (let $_rest (get_from_heap $pq $_priority $item)
           $item))
    (qitem 0.8 b goalB))

!(test
    (let* (($pq1 (add_to_heap (empty_heap) -0.8 (qitem 0.8 b goalB)))
           ($pq (add_to_heap $pq1 -0.8 (qitem 0.8 b goalB))))
      (heap_size $pq))
    2)

;; Nil-proved items are resolved immediately outside the queue.
!(test
    (let (state $pq $goals)
         (state-enqueue-item (state (empty_heap) ())
            (qitem 0.9
                   (cand (Nil |- provedPrem) 0.9
                         (cons (frame $prem Nil resumedGoal 0.6) ()))
                   ignoredGoal))
         (cons (heap_size $pq) $goals))
    (cons 0 (resumedGoal)))

!(test
    (has-active-premise?
        ((: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) Nil)
        (: (kb MAIN ()) pGoal (CurrentGoal) (STV 1.0 1.0))
        (cons (frame premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
    true)

!(test
    (has-active-premise?
        ((: (kb MAIN ()) pPrem (OtherGoal) (STV 1.0 1.0)) Nil)
        (: (kb MAIN ()) pGoal (CurrentGoal) (STV 1.0 1.0))
        (cons (frame premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
    false)

!(test
    (let (state $pq $goals)
         (state-enqueue-item
            (state (empty_heap) ())
            (qitem 0.9
                   (cand (((: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) Nil)
                          |- (: (kb MAIN ()) pGoal (CurrentGoal) (STV 1.0 1.0)))
                         0.9
                         (cons (frame premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
                   ignoredGoal))
         (heap_size $pq))
    0)
