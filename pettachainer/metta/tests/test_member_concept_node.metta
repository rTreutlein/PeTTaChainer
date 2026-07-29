!(import! &self ../petta_chainer)

;; A Member's class is a class we know about, so it must be registered as a
;; concept node -- even when it never appears in an Inheritance. The Member's
;; object must NOT be a concept node. (Regression guard: the recording used to
;; live only in a dead external-form kb-add-atom clause, so Member-only classes
;; were silently never registered.)

!(compileadd memberConceptKb (: m1 (Member tom Human) (STV 1.0 0.9)))

!(test (known-concept-node? memberConceptKb Human) true)
!(test (known-concept-node? memberConceptKb tom) false)
