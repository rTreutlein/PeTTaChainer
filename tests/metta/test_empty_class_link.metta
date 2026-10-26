!(import! &self ../../pettachainer/metta/petta_chainer)

;; The instance folds of one class link the skeleton has expanded.
(: link-fold-node-count (-[det]-> KB Term Term Number))
(= (link-fold-node-count $kb $subj $concept)
   (list-count
      (collapse
         (match &sk_expanded
            ($_hash
               (CPU FoldAllCompiled
                  ($kb (ImplicationInstanceSample $a $b $_atv $_btv)
                     $_extractor $_init $_fun $_finish $_tv-mode)
                  $_result))
            (if (== (car-atom $a) $subj) (if (== (car-atom $b) $concept) true (empty)) (empty))))))

;; An interrupted search answers nothing.
!(test
   (query 1 boundedEmptyLinkKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

;; An empty population answers nothing and invents no estimate.
!(test
   (query 80 emptyLinkKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test (link-fold-node-count emptyLinkKb EmptyClass MissingClass) 1)

;; Unrelated knowledge and warm queries, with any budget, answer nothing.
!(compileadd emptyLinkKb
   (: unrelatedMember (Member unrelated OtherClass) (STV 1.0 1.0)))

!(test
   (query 80 emptyLinkKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (query 81 emptyLinkKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test (link-fold-node-count emptyLinkKb EmptyClass MissingClass) 1)

;; A matching sample is taken by the next read, at any budget.
!(compileadd emptyLinkKb
   (: firstEmpty (Member first EmptyClass) (STV 1.0 1.0)))
!(compileadd emptyLinkKb
   (: firstMissing (Member first MissingClass) (STV 0.6 1.0)))

!(test
   (query 0 emptyLinkKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   (: (implication-instance-fold cpu) (Inheritance EmptyClass MissingClass) (STV 0.6 0.0012484394506866417)))

;; A stated link answers beside the instance fold.
!(compileadd directLinkKb
   (: directInheritance
      (Inheritance EmptyClass DirectTarget)
      (STV 0.7 0.9)))

!(test
   (query 80 directLinkKb
      (: $_proof (Inheritance EmptyClass DirectTarget) $_tv))
   (: directInheritance (Inheritance EmptyClass DirectTarget) (STV 0.7 0.9)))
