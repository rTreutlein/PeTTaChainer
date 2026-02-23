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
    (term-confidence (CPU MpFormula ((STV 1.0 0.6) (STV 0.8 0.9)) $out))
    0.6)

!(test
    (term-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
    0.4)

!(test
    (term-confidence (CPU OrFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
    0.7)

!(test
    (term-confidence (CPU LikelierThanFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $out))
    0.4)


!(test
    (term-confidence (CPU AndFormula ((STV 0.8 0.4) (STV 0.9 0.7)) $res))
    0.4)

;; Nested premise list confidence (min over expected premise confidences).
!(test
    (premises-expected-confidence
        (cons (CPU MpFormula ((STV 1.0 0.2) (STV 1.0 1.0)) $tv1)
              (cons (CPU MpFormula ((STV 1.0 0.55) $tv1) $tv2) ())))
    0.2)

;; Heap queue ordering and duplicate retention.
!(test
    (let* (($pq1 (add_to_heap (empty_heap) -0.5 (qitem 0.5 a)))
           ($pq (add_to_heap $pq1 -0.8 (qitem 0.8 b))))
      (let $_rest (get_from_heap $pq $_priority $item)
           $item))
    (qitem 0.8 b))

!(test
    (let* (($pq1 (add_to_heap (empty_heap) -0.8 (qitem 0.8 b)))
           ($pq (add_to_heap $pq1 -0.8 (qitem 0.8 b))))
      (heap_size $pq))
    2)

;; Empty-proved items are resolved immediately outside the queue.
!(test
    (let* (($_rclear (remove-all-atoms &resume_cache))
           ($_gclear (remove-all-atoms &goal_cache)))
      (let (state $pq $_rcache $gcache)
           (state-enqueue-item (state (empty_heap) &resume_cache &goal_cache)
              (qitem 0.9
                     (cand (() |- provedPrem)
                           (cons (resume ridX premX () resumedGoal 0.6) ()))))
           (cons (heap_size $pq) (collapse (match $gcache (gmerge $goal) $goal)))))
    (cons 0 (resumedGoal)))

!(test
    (has-active-premise?
        (cons (: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) ())
        (cons (resume ridX premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
    true)

!(test
    (has-active-premise?
        (cons (: (kb MAIN ()) pPrem (OtherGoal) (STV 1.0 1.0)) ())
        (cons (resume ridX premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
    false)

;; Alpha-equivalent goals should count as active overlap.
!(test
    (has-active-premise?
        (cons (: (kb MAIN ()) pPrem (LoopGoal $x) (STV 1.0 1.0)) ())
        (cons (resume ridX premX restX (: (kb MAIN ()) pCont (LoopGoal $y) (STV 1.0 1.0)) 1.0) ()))
    true)

;; Non-goal premises are ignored while typed goals are extracted.
!(test
    (premise-goal-keys
        (cons (CPU AndFormula ((STV 1.0 0.9) (STV 1.0 0.8)) $tmp)
              (cons (: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) ())))
    ((LoopGoal)))

!(test
    (has-active-premise?
        (cons (CPU AndFormula ((STV 1.0 0.9) (STV 1.0 0.8)) $tmp)
              (cons (: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) ()))
        (cons (resume ridX premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))
    true)

!(test
    (let* (($_rclear (remove-all-atoms &resume_cache))
           ($_gclear (remove-all-atoms &goal_cache)))
      (let (state $pq $_rcache $_gcache)
          (state-enqueue-item
            (state (empty_heap) &resume_cache &goal_cache)
            (qitem 0.9
                   (cand ((cons (: (kb MAIN ()) pPrem (LoopGoal) (STV 1.0 1.0)) ())
                           |- (: (kb MAIN ()) pGoal (CurrentGoal) (STV 1.0 1.0)))
                          (cons (resume ridX premX restX (: (kb MAIN ()) pCont (LoopGoal) (STV 1.0 1.0)) 1.0) ()))))
           (heap_size $pq)))
    0)
