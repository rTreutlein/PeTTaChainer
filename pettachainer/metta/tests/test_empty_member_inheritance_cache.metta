!(import! &self ../petta_chainer)

(: member-snapshot-current?
   (-[det]-> KB Term Term Bool))
(= (member-snapshot-current? $kb $subj $concept)
   (forward-member-inheritance-snapshot-current?
      $kb $subj $concept 80))

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

;; An interrupted search is not an authoritative empty snapshot.
!(test
   (query 1 boundedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-snapshot-current?
      boundedEmptyMemberKb EmptyClass MissingClass)
   false)

;; A settled empty fold records a bounded snapshot without inventing an STV.
!(set-universe-size cachedEmptyMemberKb 1.0)

!(test
   (query 80 cachedEmptyMemberKb
      (: $_proof (Inheritance EmptyClass MissingClass) $_tv))
   ())

!(test
   (member-snapshot-current?
      cachedEmptyMemberKb EmptyClass MissingClass)
   true)

!(test
   (cached-base-rate cachedEmptyMemberKb
      (MemberInheritanceSample
         $obj EmptyClass MissingClass $atv $btv))
   ())

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

;; Monotonic additions advance the KB revision. The old empty observation stays
;; stored but is no longer current, so the next query discovers the new sample.
!(compileadd cachedEmptyMemberKb
   (: firstEmpty (Member first EmptyClass) (STV 1.0 1.0)))
!(compileadd cachedEmptyMemberKb
   (: firstMissing (Member first MissingClass) (STV 0.6 1.0)))

!(test
   (member-snapshot-current?
      cachedEmptyMemberKb EmptyClass MissingClass)
   false)

!(test
   (query 80 cachedEmptyMemberKb
      (: $proof (Inheritance EmptyClass MissingClass) $tv))
   (: (member-inheritance-fold
          (foldall-proof
             (member-inheritance-sample firstEmpty firstMissing)))
      (Inheritance EmptyClass MissingClass)
      (STV 0.6 1.0)))

!(test
   (member-snapshot-current?
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
   (member-snapshot-current?
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
