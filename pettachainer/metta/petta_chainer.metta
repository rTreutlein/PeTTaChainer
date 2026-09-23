;; Stable public facade. Internal modules and their order are private.
!(import! &self bootstrap)

;; Re-export public signatures so consumers need only this module.
(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(: query-many
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(: query-many-materialize
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(: chainer-many
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(: chainer-many-materialize
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
