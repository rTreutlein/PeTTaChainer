;; Stable public facade. Internal modules and their order are private.
!(import! &self bootstrap)

;; Re-export public signatures so consumers need only this module.
(: query
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(: query-materialize
   (-[nondet]-> Number KB AnnotatedStatement AnnotatedStatement))
(: query-many
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(: query-many-refs
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(: expand-proof (-[nondet]-> Proof Proof))
(: query-many-materialize
   (-[nondet]-> Number KB (List AnnotatedStatement) QueryBatchResult))
(: set-backward-query-metrics (-[det]-> Bool Bool))
(: backward-query-metrics (-[det]-> (List BackwardQueryMetric)))
(: chainer-many
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
(: chainer-many-materialize
   (-[nondet]-> Number
       (List (| Goal (Statement KBContext Proof TV)))
       (List (List RuntimeResult))))
