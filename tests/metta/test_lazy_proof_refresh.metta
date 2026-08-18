!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd lazyRefreshKb
   (: lazy-refresh-a1 (LazyRefreshA one) (STV 1.0 0.7)))
!(compileadd lazyRefreshKb
   (: lazy-refresh-a2 (LazyRefreshA two) (STV 0.8 0.8)))
!(compileadd lazyRefreshKb
   (: lazy-refresh-rule
      (Implication (LazyRefreshA $x) (LazyRefreshRoot $x))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

(: lazy-refresh-answer-value
   (-[semidet]-> AnnotatedStatement Atom))
(= (lazy-refresh-answer-value
      (: $_proof (LazyRefreshRoot $value) $_tv))
   $value)

;; Both leaf candidates are committed by one open-goal expansion. Lazy proof
;; propagation must deliver both branches rather than dropping one behind a
;; coalesced refresh.
!(test
   (let*
      (($answers
          (collapse
             (query 100 lazyRefreshKb
                (: $proof (LazyRefreshRoot $x) $tv))))
       ($values (map-flat lazy-refresh-answer-value $answers)))
      ((length $answers)
       (stored-list-member? one $values)
       (stored-list-member? two $values)))
   (2 true true))
