!(import! &self ../../pettachainer/metta/petta_chainer)

;; The Member folds over one subject/concept pair the skeleton has expanded.
(: member-fold-node-count (-[det]-> KB Term Term Number))
(= (member-fold-node-count $kb $subj $concept)
   (list-count
      (collapse
         (match &sk_expanded
            ($_hash
               (CPU FoldAllCompiled
                  ($kb (MemberInheritanceSample $_obj $subj $concept $_atv $_btv)
                     $_extractor $_init $_fun (member-inheritance $kb) $_tv-mode)
                  $_result))
            true))))

;; An interrupted search answers nothing.
!(test
   (query 1 boundedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

;; An empty Member population answers nothing and invents no estimate.
!(test
   (query 80 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (cached-base-rate cachedEmptyMemberKb
      (MemberInheritanceSample
         $obj EmptyClass MissingClass $atv $btv))
   ())

!(test (member-fold-node-count cachedEmptyMemberKb EmptyClass MissingClass) 1)

;; Unrelated knowledge and warm queries, with any budget, reuse the expanded
;; fold instead of building it again.
!(compileadd cachedEmptyMemberKb
   (: unrelatedMember (Member unrelated OtherClass) (STV 1.0 1.0)))

!(test
   (query 80 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (query 81 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test (member-fold-node-count cachedEmptyMemberKb EmptyClass MissingClass) 1)

;; Matching monotonic additions refine the registered subscription directly:
;; the second side produces a real cached estimate.
!(compileadd cachedEmptyMemberKb
   (: firstEmpty (Member first EmptyClass) (STV 1.0 1.0)))
!(compileadd cachedEmptyMemberKb
   (: firstMissing (Member first MissingClass) (STV 0.6 1.0)))

!(test
   (cached-base-rate cachedEmptyMemberKb
      (MemberInheritanceSample
         $obj EmptyClass MissingClass $atv $btv))
   ((STV 0.6 0.0012484394506866417)))

;; Direct Inheritance evidence is always available beside the Member fold.
!(compileadd directEmptyMemberKb
   (: directInheritance
      (Inheritance EmptyClass DirectTarget)
      (STV 0.7 0.9)))

!(test
   (let (: $_proof
            (Inheritance EmptyClass DirectTarget)
            (STV $strength $confidence))
      (query 80 directEmptyMemberKb
         (: $_proof (Inheritance EmptyClass DirectTarget)
            (STV $strength $confidence)))
      (and
         (and (> $strength 0.699) (< $strength 0.701))
         (> $confidence 0.89)))
   true)
