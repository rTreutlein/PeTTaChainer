!(import! &self ../../pettachainer/metta/petta_chainer)

;; Tracker #79: the exact fact-only root reproducer. Neither the ground
;; answer nor an open query may retain the empty merge from the first read.
!(compileadd late79Kb (: other (C c) (STV 1 1)))
!(test (collapse (query 300 late79Kb (: $p (A a) $tv))) ())
!(compileadd late79Kb (: seed (A a) (STV 1 0.8)))
!(compileadd late79Kb (: seedc (A c) (STV 1 0.8)))
!(test (collapse (query 300 late79Kb (: $p (A a) $tv)))
       ((: seed (A a) (STV 1 0.8))))
!(test (collapse (query 300 late79Kb (: $p (A $x) $tv)))
       ((: seed (A a) (STV 1 0.8)) (: seedc (A c) (STV 1 0.8))))

;; A budget-zero pre-query also caches an empty root, even though the root
;; need not be expanded. A certain fact still has to replace that absence.
!(test (collapse (query 0 late79Kb (: $p (A b) $tv))) ())
!(compileadd late79Kb (: certain (A b) (STV 1 1)))
!(test (collapse (query 0 late79Kb (: $p (A b) $tv)))
       ((: certain (A b) (STV 1 1))))

;; Rule readers can see a late fact while the root's merge remains empty.
!(compileadd cycle79Kb (: (no_inverse ab) (Implication (A $x) (B $x)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd cycle79Kb (: (no_inverse ba) (Implication (B $x) (A $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (collapse (query 300 cycle79Kb (: $p (A a) $tv))) ())
!(compileadd cycle79Kb (: seed (A a) (STV 1 0.8)))
!(test (collapse (query 300 cycle79Kb (: $p (A a) $tv)))
       ((: seed (A a) (STV 1 0.8))))
!(test (collapse (query 300 cycle79Kb (: $p (B a) $tv)))
       ((: (by (no_inverse ab) seed) (B a) (STV 1 0.7999359651197002))))
