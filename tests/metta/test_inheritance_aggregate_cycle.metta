!(import! &self ../../pettachainer/metta/petta_chainer)

;; The Raven -> Penguin query derives Bird for its hypothetical raven through
;; ravenBird and inverts penguinBird over the Bird and Penguin base rates. The
;; Bird rate must not count the query's own hypothetical member, so the query
;; answers once. No raven is known to be or not to be a penguin, so the
;; answer carries no evidence.
!(compileadd inheritanceAggregateCycleKb
   (: ravenBird (Inheritance Raven Bird) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb
   (: penguinBird (Inheritance Penguin Bird) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb (: rRaven (Member r Raven) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb (: rBird (Member r Bird) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb (: pPenguin (Member p Penguin) (STV 1.0 0.9)))
!(compileadd inheritanceAggregateCycleKb (: pBird (Member p Bird) (STV 1.0 0.9)))

!(test
   (collapse
      (query 100 inheritanceAggregateCycleKb
         (: $proof (Inheritance Raven Penguin) $tv)))
   ((: (conditional-implication ((inverted penguinBird with cpu (prior (STV 0.9090909090909091 0.0011237357972281184))) (by ravenBird (ctx proof 0)))) (Inheritance Raven Penguin) (STV 0.5 0.0))))
