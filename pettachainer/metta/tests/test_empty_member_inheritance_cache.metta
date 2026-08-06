!(import! &self ../petta_chainer)

(: member-empty-cache-hit?
   (-[det]-> KB Term Term Bool))
(= (member-empty-cache-hit? $kb $subj $concept)
   (forward-member-inheritance-empty-cache-hit?
      $kb $subj $concept 80))

(: member-empty-cache-budgets
   (-[det]-> KB Term Term (List Number)))
(= (member-empty-cache-budgets $kb $subj $concept)
   (collapse
      (match &forward_member_inheritance_identity
         (forward-member-inheritance-identity-row
            (fwd_member_identity $kb $subj $concept) $id)
         (match &forward_member_inheritance_empty_cache
            (forward-member-inheritance-empty-cache-row $id $budget)
            $budget))))

(: member-aggregate-count (-[det]-> KB Term Term Number))
(= (member-aggregate-count $kb $subj $concept)
   (list-count
      (collapse
         (match &aggregate
            (stored-aggregate-row
               $_agg-gid $_child
               ($kb
                  (MemberInheritanceSample
                     $_obj $subj $concept $_atv $_btv)
                  $_extractor $_init $_fun
                  (member-inheritance $kb) $_tv-mode)
               $_base $_pending $_current-pid)
            true))))

;; An interrupted search is not an authoritative empty cache entry.
!(test
   (query 1 boundedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-empty-cache-hit?
      boundedEmptyMemberKb EmptyClass MissingClass)
   false)

;; A settled empty fold records its best exhausted budget without inventing an
;; STV or adding logical evidence.
!(set-universe-size cachedEmptyMemberKb 1.0)

!(test
   (query 80 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-empty-cache-hit?
      cachedEmptyMemberKb EmptyClass MissingClass)
   true)

!(test
   (member-empty-cache-budgets
      cachedEmptyMemberKb EmptyClass MissingClass)
   (80))

!(test
   (cached-base-rate cachedEmptyMemberKb
      (MemberInheritanceSample
         $obj EmptyClass MissingClass $atv $btv))
   ())

;; Unrelated monotonic knowledge leaves the approximation usable.
!(compileadd cachedEmptyMemberKb
   (: unrelatedMember (Member unrelated OtherClass) (STV 1.0 1.0)))

!(test
   (member-empty-cache-hit?
      cachedEmptyMemberKb EmptyClass MissingClass)
   true)

!(test
   (member-empty-cache-budgets
      cachedEmptyMemberKb EmptyClass MissingClass)
   (80))

;; A warm query skips construction of the Member aggregate altogether.
!(test
   (query 80 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-aggregate-count
      cachedEmptyMemberKb EmptyClass MissingClass)
   0)

;; A larger budget is not subsumed by the earlier bounded observation.
!(test
   (query 81 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-aggregate-count
      cachedEmptyMemberKb EmptyClass MissingClass)
   1)

;; The mutable optimization row retains only the best exhausted budget.
!(test
   (member-empty-cache-budgets
      cachedEmptyMemberKb EmptyClass MissingClass)
   (81))

;; Matching monotonic additions refine the registered subscription directly.
;; The second side produces a real cached estimate and replaces the empty
;; optimization marker; unrelated knowledge needs no cache invalidation.
!(compileadd cachedEmptyMemberKb
   (: firstEmpty (Member first EmptyClass) (STV 1.0 1.0)))
!(compileadd cachedEmptyMemberKb
   (: firstMissing (Member first MissingClass) (STV 0.6 1.0)))

!(test
   (member-empty-cache-hit?
      cachedEmptyMemberKb EmptyClass MissingClass)
   false)

!(test
   (cached-base-rate cachedEmptyMemberKb
      (MemberInheritanceSample
         $obj EmptyClass MissingClass $atv $btv))
   ((STV 0.6 1.0)))

!(test
   (query 80 cachedEmptyMemberKb
      (: $proof (Inheritance EmptyClass MissingClass) $tv))
   (: (member-inheritance-fold cpu)
      (Inheritance EmptyClass MissingClass)
      (STV 0.6 1.0)))

!(test
   (member-empty-cache-hit?
      cachedEmptyMemberKb EmptyClass MissingClass)
   false)

;; A cached empty Member population suppresses only that fold. Direct
;; Inheritance evidence remains available on every warm query.
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

!(test
   (member-empty-cache-hit?
      directEmptyMemberKb EmptyClass DirectTarget)
   true)

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

!(test
   (member-aggregate-count
      directEmptyMemberKb EmptyClass DirectTarget)
   0)
