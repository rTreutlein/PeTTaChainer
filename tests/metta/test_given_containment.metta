!(import! &self ../../pettachainer/metta/petta_chainer)

;; A pinned report carries no evidence. Its diagnostic update still carries
;; information absent from a prediction whose evidence strictly contains it.
;; Isolate containment with the two views of this small KB: the diagnostic
;; reads Other and the pin, the prediction reads Other and More.
!(compileadd containmentKb (: other (Other a) (STV 0.4 0.8)))
!(compileadd containmentKb (: more (More a) (STV 0.6 0.8)))
!(compileadd containmentKb (: report (Report a) (STV 0.7 0.9)))

(: containment-pair (-[semidet]-> (List Number) SkeletonPairing))
(= (containment-pair $ignore)
   (let* (($scope (kbctx containmentKb))
          ($report (sk-key (Report a) $scope))
          ($hash (index-hash $report))
          ($pin-deps (deps-key $hash))
          ($pin-ev (ev-set 0))
          ($pin-proof (given true))
          ($other (evidence-set (other)))
          ($both (evidence-set (other more)))
          ($diagnostic (data (Hidden a) $scope ((inverted diagnostic with cpu (prior (STV 0.4 0.9))) (conjunction other $pin-proof)) (STV 0.8 0.7)))
          ($prediction (data (Hidden a) $scope (by predictive (conjunction other more)) (STV 0.3 0.8))))
      (sk-merge-facts false $ignore
         $diagnostic (evidence-union $other $pin-ev) $pin-deps
         $prediction $both 0)))

;; No pin context: evidence containment keeps the prediction.
!(test (case (containment-pair ())
   (((sk-paired (sk-val ($_t $_c $proof $_tv) $_ev $_deps)) $proof)))
   (by predictive (conjunction other more)))
;; With the pin, Bayes factoring retains the diagnostic likelihood ratio.
;; #89 reads the prior before Bayes factoring, giving 0.7200119989500919.
!(test (case (containment-pair (cons (index-hash (sk-key (Report a) (kbctx containmentKb))) ()))
   (((sk-paired (sk-val ($_t $_c $_proof (STV $strength $_confidence)) $_ev $_deps)) $strength))) 0.7200119989500919)
