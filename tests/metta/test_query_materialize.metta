!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd materializeKb (: a0 (A) (STV 1.0 1.0)))

!(compileadd materializeKb (: r1 (Implication (A) (B)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(compileadd materializeKb (: r2 (Implication (B) (Goal)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(test
   (query 4 materializeKb (: $p (Goal) $tv))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(test
   (collapse (match &kb ((B) (materializeKb MAIN Nil) $_prf $_tv) true))
   ())

!(test
   (collapse (match &kb ((Goal) (materializeKb MAIN Nil) $_prf $_tv) true))
   ())

!(test
   (query-materialize 4 materializeKb (: $p (Goal) $tv))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

!(test
   (not (== (collapse (match &kb ((B) (materializeKb MAIN Nil) $_prf $_tv) true)) ()))
   true)

!(test
   (not (== (collapse (match &kb ((Goal) (materializeKb MAIN Nil) $_prf $_tv) true)) ()))
   true)

!(test
   (query 1 materializeKb (: $p (B) $tv))
   (: (by r1 a0) (B) (STV 1.0 0.9998000399670116)))

!(test
   (query 1 materializeKb (: $p (Goal) $tv))
   (: (by r2 (by r1 a0)) (Goal) (STV 1.0 0.999700089898053)))

;; Positive implication judgments live in a private query context. Even an
;; explicit materialization request must not persist one as a world fact.
!(compileadd implicationMaterializeKb (: r (Implication (G) (Y))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(test (let (: $p $type (STV $s $c))
   (query-materialize 300 implicationMaterializeKb (: $q (Implication (G) (Y)) $tv)) $s) 0.8)
!(test (collapse (match &kb
   ($_type ((implication-query implicationMaterializeKb) MAIN Nil) $_proof $_tv) true)) ())
!(test (collapse (match &materialized_facts
   (materialized-row $_hash $_type ((implication-query implicationMaterializeKb) MAIN Nil) $_fact $_ev) true)) ())
!(test (collapse (query 0 implicationMaterializeKb (: $p (Implication (G) (Y)) $tv))) ())
