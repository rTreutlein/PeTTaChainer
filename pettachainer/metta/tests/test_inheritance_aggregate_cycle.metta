!(import! &self ../petta_chainer)

;; The Raven -> Penguin query recursively derives another Raven -> Bird proof
;; through the query itself.  Bird's base-rate fold must reject that cyclic raw
;; proof before merging outputs, while retaining the independent ravenBird fact.
!(set-concept-prior-confidence inheritanceAggregateCycleKb 0.5)
!(compileadd inheritanceAggregateCycleKb
   (: ravenBird (Inheritance Raven Bird) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb
   (: penguinBird (Inheritance Penguin Bird) (STV 1.0 0.9)))

!(test
   (collapse
      (query 100 inheritanceAggregateCycleKb
         (: $proof (Inheritance Raven Penguin) $tv)))
   ((:
      (inheritance-implication-fold
         (total-implication
            ((inverted (inheritance-implication penguinBird)
                with cpu (foldall-proof ravenBird penguinBird))
             ((inheritance-implication ravenBird) (ctx proof 0)))
            ((inverted (inheritance-implication penguinBird)
                with cpu (foldall-proof ravenBird penguinBird))
             ((inheritance-implication ravenBird) (ctx proof 1)))))
      (Inheritance Raven Penguin)
      (STV 0.3571428571428571 0.4727586120223953))))
