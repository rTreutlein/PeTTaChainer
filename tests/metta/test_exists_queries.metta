!(import! &self ../../pettachainer/metta/petta_chainer)

;; Tracker #48, stage 1. These semantic expectations are shared with the
;; design acceptance probes: source IDs and full answers are additionally
;; checked by bench/results/exists/check-probes.py.
(: exists-answer-matches
   (-[det]-> Atom Number Number Bool AnnotatedStatement Bool))
(= (exists-answer-matches $expected $strength $confidence $ok $answer)
   (if $ok
      (case $answer (
         ((: $_proof $statement (STV $s $c))
            (if (if (== $expected any-group) true (=alpha $expected $statement))
               (if (if (< $strength 0) true
                      (if (>= $s (- $strength 0.000001)) (<= $s (+ $strength 0.000001)) false))
                  (if (< $confidence 0) true
                     (if (>= $c (- $confidence 0.000001)) (<= $c (+ $confidence 0.000001)) false))
                  false)
               false))
         ($_other false)))
      false))


;; saved_rule_exact
!(compileadd saved_rule_exact (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd saved_rule_exact (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(test
   (let $answers (collapse (query 0 saved_rule_exact (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 saved_rule_exact (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) 1 1) true $answers)
         false))
   true)

;; saved_rule_alpha
!(compileadd saved_rule_alpha (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd saved_rule_alpha (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(test
   (let $answers (collapse (query 0 saved_rule_alpha (: $prf (Implication (Exists ($event) (And (Member $site Facility) (Member $event Flood) (RecordedFlood $site $event) (During $event S1))) (RequiresInspectionDuring $site S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($event) (And (Member $site Facility) (Member $event Flood) (RecordedFlood $site $event) (During $event S1))) (RequiresInspectionDuring $site S1)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 saved_rule_alpha (: $prf (Implication (Exists ($event) (And (Member $site Facility) (Member $event Flood) (RecordedFlood $site $event) (During $event S1))) (RequiresInspectionDuring $site S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($event) (And (Member $site Facility) (Member $event Flood) (RecordedFlood $site $event) (During $event S1))) (RequiresInspectionDuring $site S1)) 1 1) true $answers)
         false))
   true)

;; simple_exists_witness
!(compileadd simple_exists_witness (: src_pa (P a) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 simple_exists_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 simple_exists_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)

;; claim_from_witness
!(compileadd claim_from_witness (: src_pa (P a) (STV 1 1)))
!(test (collapse (query 1000 claim_from_witness (: $p (ExistentialClaim (P (exists-slot 0))) $tv))) ())
!(test (collapse (query 1000 claim_from_witness (: $p (ExistentialClaim (P (exists-slot 0))) $tv))) ())

;; direct_claim
!(compileadd direct_claim (: src_seed (Seed Alice) (STV 1 1)))
!(compileadd direct_claim (: src_gen (Implication (Seed $x) (Exists ($y) (GeneratedBy $x $y))) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 direct_claim (: $p (ExistentialClaim (GeneratedBy Alice (exists-slot 0))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (GeneratedBy Alice (exists-slot 0))) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 direct_claim (: $p (ExistentialClaim (GeneratedBy Alice (exists-slot 0))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (GeneratedBy Alice (exists-slot 0))) 1 -1) true $answers)
         false))
   true)

;; exists_from_direct_claim
!(compileadd exists_from_direct_claim (: src_seed (Seed Alice) (STV 1 1)))
!(compileadd exists_from_direct_claim (: src_gen (Implication (Seed $x) (Exists ($y) (GeneratedBy $x $y))) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 exists_from_direct_claim (: $p (Exists ($y) (GeneratedBy Alice $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy Alice $y)) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 exists_from_direct_claim (: $p (Exists ($y) (GeneratedBy Alice $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy Alice $y)) 1 -1) true $answers)
         false))
   true)

;; no_concrete_witness
!(compileadd no_concrete_witness (: src_seed (Seed Alice) (STV 1 1)))
!(compileadd no_concrete_witness (: src_gen (Implication (Seed $x) (Exists ($y) (GeneratedBy $x $y))) (STV 1 1)))
!(test (collapse (query 1000 no_concrete_witness (: $p (GeneratedBy Alice $witness) $tv))) ())
!(test (collapse (query 1000 no_concrete_witness (: $p (GeneratedBy Alice $witness) $tv))) ())

;; saved_flood_to_claim
!(compileadd saved_flood_to_claim (: src_floodS1RequiresInspectionS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (HasRecordedEvent $facility $flood) (DuringShift $flood S1))) (Exists ($inspection) (And (Member $inspection Inspection) (Requires $facility $inspection) (DuringShift $inspection S1)))) (STV 1.0 1.0)))
!(compileadd saved_flood_to_claim (: src_fac (Member Alder Facility) (STV 1 1)))
!(compileadd saved_flood_to_claim (: src_flood (Member Flood1 Flood) (STV 1 1)))
!(compileadd saved_flood_to_claim (: src_event (HasRecordedEvent Alder Flood1) (STV 1 1)))
!(compileadd saved_flood_to_claim (: src_time (DuringShift Flood1 S1) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 saved_flood_to_claim (: $p (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 saved_flood_to_claim (: $p (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) 1 -1) true $answers)
         false))
   true)

;; saved_flood_to_exists
!(compileadd saved_flood_to_exists (: src_floodS1RequiresInspectionS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (HasRecordedEvent $facility $flood) (DuringShift $flood S1))) (Exists ($inspection) (And (Member $inspection Inspection) (Requires $facility $inspection) (DuringShift $inspection S1)))) (STV 1.0 1.0)))
!(compileadd saved_flood_to_exists (: src_fac (Member Alder Facility) (STV 1 1)))
!(compileadd saved_flood_to_exists (: src_flood (Member Flood1 Flood) (STV 1 1)))
!(compileadd saved_flood_to_exists (: src_event (HasRecordedEvent Alder Flood1) (STV 1 1)))
!(compileadd saved_flood_to_exists (: src_time (DuringShift Flood1 S1) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 saved_flood_to_exists (: $p (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 saved_flood_to_exists (: $p (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) 1 -1) true $answers)
         false))
   true)

;; saved_flood_free_lookup
!(compileadd saved_flood_free_lookup (: src_floodS1RequiresInspectionS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (HasRecordedEvent $facility $flood) (DuringShift $flood S1))) (Exists ($inspection) (And (Member $inspection Inspection) (Requires $facility $inspection) (DuringShift $inspection S1)))) (STV 1.0 1.0)))
!(compileadd saved_flood_free_lookup (: src_fac (Member Alder Facility) (STV 1 1)))
!(compileadd saved_flood_free_lookup (: src_flood (Member Flood1 Flood) (STV 1 1)))
!(compileadd saved_flood_free_lookup (: src_event (HasRecordedEvent Alder Flood1) (STV 1 1)))
!(compileadd saved_flood_free_lookup (: src_time (DuringShift Flood1 S1) (STV 1 1)))
!(test (collapse (query 1000 saved_flood_free_lookup (: $prf (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1)) $tv))) ())
!(test (collapse (query 1000 saved_flood_free_lookup (: $prf (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1)) $tv))) ())

;; rule_missing
!(test (collapse (query 1000 rule_missing (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv))) ())
!(test (collapse (query 1000 rule_missing (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv))) ())

;; exists_empty
!(test (collapse (query 1000 exists_empty (: $p (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) $tv))) ())
!(test (collapse (query 1000 exists_empty (: $p (Exists ($inspection) (And (Member $inspection Inspection) (Requires Alder $inspection) (DuringShift $inspection S1))) $tv))) ())

;; claim_empty
!(test (collapse (query 1000 claim_empty (: $p (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) $tv))) ())
!(test (collapse (query 1000 claim_empty (: $p (ExistentialClaim (And (Member (exists-slot 0) Inspection) (Requires Alder (exists-slot 0)) (DuringShift (exists-slot 0) S1))) $tv))) ())

;; inspection
!(compileadd inspection (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd inspection (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd inspection (: src_f0 (Member Alder Facility) (STV 1 1)))
!(compileadd inspection (: src_f1 (Member Flood1 Flood) (STV 1 1)))
!(compileadd inspection (: src_f2 (RecordedFlood Alder Flood1) (STV 1 1)))
!(compileadd inspection (: src_f3 (During Flood1 S1) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 inspection (: $p (RequiresInspectionDuring Alder S1) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (RequiresInspectionDuring Alder S1) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 inspection (: $p (RequiresInspectionDuring Alder S1) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (RequiresInspectionDuring Alder S1) 1 -1) true $answers)
         false))
   true)

;; pause
!(compileadd pause (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd pause (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd pause (: src_f0 (Member Alder Facility) (STV 1 1)))
!(compileadd pause (: src_f1 (Member Flood1 Flood) (STV 1 1)))
!(compileadd pause (: src_f2 (RecordedFlood Alder Flood1) (STV 1 1)))
!(compileadd pause (: src_f3 (During Flood1 S1) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 pause (: $p (MustPauseProductionDuring Alder S1) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (MustPauseProductionDuring Alder S1) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 pause (: $p (MustPauseProductionDuring Alder S1) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (MustPauseProductionDuring Alder S1) 1 -1) true $answers)
         false))
   true)

;; missing_flood
!(compileadd missing_flood (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd missing_flood (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd missing_flood (: src_f0 (Member Alder Facility) (STV 1 1)))
!(test (collapse (query 1000 missing_flood (: $p (RequiresInspectionDuring Alder S1) $tv))) ())
!(test (collapse (query 1000 missing_flood (: $p (RequiresInspectionDuring Alder S1) $tv))) ())

;; wrong_shift
!(compileadd wrong_shift (: src_facilityInspectionPausePolicyS1 (Implication (And (Member $facility Facility) (RequiresInspectionDuring $facility S1)) (MustPauseProductionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd wrong_shift (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd wrong_shift (: src_f0 (Member Alder Facility) (STV 1 1)))
!(compileadd wrong_shift (: src_f1 (Member Flood1 Flood) (STV 1 1)))
!(compileadd wrong_shift (: src_f2 (RecordedFlood Alder Flood1) (STV 1 1)))
!(compileadd wrong_shift (: src_f3 (During Flood1 S1) (STV 1 1)))
!(test (collapse (query 1000 wrong_shift (: $p (RequiresInspectionDuring Alder S2) $tv))) ())
!(test (collapse (query 1000 wrong_shift (: $p (RequiresInspectionDuring Alder S2) $tv))) ())

;; independent_witnesses
!(compileadd independent_witnesses (: pa (P a) (STV 0.8 0.5)))
!(compileadd independent_witnesses (: pb (P b) (STV 0.6 0.7)))
!(test
   (let $answers (collapse (query 1000 independent_witnesses (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.92 0.7123799949180818) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 independent_witnesses (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.92 0.7123799949180818) true $answers)
         false))
   true)

;; duplicate_proof
!(compileadd duplicate_proof (: source (Source) (STV 0.8 0.5)))
!(compileadd duplicate_proof (: path1 (Implication (Source) (P a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd duplicate_proof (: path2 (Implication (Source) (P a)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 duplicate_proof (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 duplicate_proof (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; all_known_false_open
!(compileadd all_known_false_open (: no_a (P a) (STV 0 1)))
!(test (collapse (query 1000 all_known_false_open (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 1000 all_known_false_open (: $p (Exists ($x) (P $x)) $tv))) ())

;; closed_empty
!(set-complete-predicate closed_empty P)
!(test (collapse (query 1000 closed_empty (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 1000 closed_empty (: $p (Exists ($x) (P $x)) $tv))) ())

;; closed_open_dependency
!(set-complete-predicate closed_open_dependency P)
!(compileadd closed_open_dependency (: r (Implication (Q $x) (P $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (collapse (query 1000 closed_open_dependency (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 1000 closed_open_dependency (: $p (Exists ($x) (P $x)) $tv))) ())

;; closed_budget_cut
!(set-complete-predicate closed_budget_cut P)
!(compileadd closed_budget_cut (: r (Implication (Q $x) (P $x)) (CTV (STV 1 1) (STV 0 1))))
!(test (collapse (query 0 closed_budget_cut (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 0 closed_budget_cut (: $p (Exists ($x) (P $x)) $tv))) ())

;; multi_slots
!(compileadd multi_slots (: seed (Seed a) (STV 1 1)))
!(compileadd multi_slots (: gen (Implication (Seed $s) (Exists ($x $y) (And (Pair $s $x $y) (Left $x) (Right $y) (SameLeft $x $x)))) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 multi_slots (: $p (ExistentialClaim (And (Pair a (exists-slot 0) (exists-slot 1)) (Left (exists-slot 0)) (Right (exists-slot 1)) (SameLeft (exists-slot 0) (exists-slot 0)))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (And (Pair a (exists-slot 0) (exists-slot 1)) (Left (exists-slot 0)) (Right (exists-slot 1)) (SameLeft (exists-slot 0) (exists-slot 0)))) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 multi_slots (: $p (ExistentialClaim (And (Pair a (exists-slot 0) (exists-slot 1)) (Left (exists-slot 0)) (Right (exists-slot 1)) (SameLeft (exists-slot 0) (exists-slot 0)))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (ExistentialClaim (And (Pair a (exists-slot 0) (exists-slot 1)) (Left (exists-slot 0)) (Right (exists-slot 1)) (SameLeft (exists-slot 0) (exists-slot 0)))) 1 -1) true $answers)
         false))
   true)

;; multi_exists
!(test
   (let $answers (collapse (query 1000 multi_slots (: $p (Exists ($u $v) (And (Pair a $u $v) (Left $u) (Right $v) (SameLeft $u $u))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($u $v) (And (Pair a $u $v) (Left $u) (Right $v) (SameLeft $u $u))) 1 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 multi_slots (: $p (Exists ($u $v) (And (Pair a $u $v) (Left $u) (Right $v) (SameLeft $u $u))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($u $v) (And (Pair a $u $v) (Left $u) (Right $v) (SameLeft $u $u))) 1 -1) true $answers)
         false))
   true)

;; co_reference_wrong
!(test (collapse (query 1000 multi_slots (: $p (Exists ($u) (And (Pair a $u $u) (Left $u) (Right $u) (SameLeft $u $u))) $tv))) ())
!(test (collapse (query 1000 multi_slots (: $p (Exists ($u) (And (Pair a $u $u) (Left $u) (Right $u) (SameLeft $u $u))) $tv))) ())

;; no_slot_witness
!(test (collapse (query 1000 multi_slots (: $p (Pair a $x $y) $tv))) ())
!(test (collapse (query 1000 multi_slots (: $p (Pair a $x $y) $tv))) ())

;; distinct_vars_may_alias
!(compileadd distinct_vars_may_alias (: pair (Pair a a) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 distinct_vars_may_alias (: $p (Exists ($x $y) (Pair $x $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x $y) (Pair $x $y)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 distinct_vars_may_alias (: $p (Exists ($x $y) (Pair $x $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x $y) (Pair $x $y)) 1 1) true $answers)
         false))
   true)

;; joined_body_mismatch
!(compileadd joined_body_mismatch (: ab (Parent a b) (STV 1 1)))
!(compileadd joined_body_mismatch (: dc (Doctor c) (STV 1 1)))
!(test (collapse (query 1000 joined_body_mismatch (: $p (Exists ($x) (And (Parent a $x) (Doctor $x))) $tv))) ())
!(test (collapse (query 1000 joined_body_mismatch (: $p (Exists ($x) (And (Parent a $x) (Doctor $x))) $tv))) ())

;; stated_zero
!(compileadd stated_zero (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(test
   (let $answers (collapse (query 0 stated_zero (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 stated_zero (: $prf (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) 1 1) true $answers)
         false))
   true)

;; stated_no_ground_leak
!(test (collapse (query 1000 stated_zero (: $p (RequiresInspectionDuring Alder S1) $tv))) ())
!(test (collapse (query 1000 stated_zero (: $p (RequiresInspectionDuring Alder S1) $tv))) ())

;; stated_no_witness_leak
!(test (collapse (query 1000 stated_zero (: $p (RecordedFlood $facility $flood) $tv))) ())
!(test (collapse (query 1000 stated_zero (: $p (RecordedFlood $facility $flood) $tv))) ())

;; derived_rule
!(compileadd derived_rule (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(compileadd derived_rule (: next (Implication (RequiresInspectionDuring $s S1) (Notify $s)) (CTV (STV 1 1) (STV 0 1))))
!(test (exists-answer-matches (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (Notify $s)) 1 0.9997500624375273 true (query 1000 derived_rule (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (Notify $s)) $tv))) true)
!(test (exists-answer-matches (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (Notify $s)) 1 0.9997500624375273 true (query 1000 derived_rule (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (Notify $s)) $tv))) true)

;; universal_sharing_wrong
!(compileadd universal_sharing_wrong (: src_facilityRecordedFloodInspectionPolicyS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (RecordedFlood $facility $flood) (During $flood S1))) (RequiresInspectionDuring $facility S1)) (STV 1.0 1.0)))
!(test (collapse (query 1000 universal_sharing_wrong (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (RequiresInspectionDuring Other S1)) $tv))) ())
!(test (collapse (query 1000 universal_sharing_wrong (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (RecordedFlood $s $f) (During $f S1))) (RequiresInspectionDuring Other S1)) $tv))) ())

;; consequent_rule
!(compileadd consequent_rule (: gen (Implication (Seed $s) (Exists ($y) (GeneratedBy $s $y))) (STV 1 1)))
!(test
   (let $answers (collapse (query 0 consequent_rule (: $p (Implication (Seed $s) (Exists ($event) (GeneratedBy $s $event))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Seed $s) (Exists ($event) (GeneratedBy $s $event))) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 consequent_rule (: $p (Implication (Seed $s) (Exists ($event) (GeneratedBy $s $event))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Seed $s) (Exists ($event) (GeneratedBy $s $event))) 1 1) true $answers)
         false))
   true)

;; both_sides_rule
!(compileadd both_sides_rule (: src_floodS1RequiresInspectionS1 (Implication (Exists ($flood) (And (Member $facility Facility) (Member $flood Flood) (HasRecordedEvent $facility $flood) (DuringShift $flood S1))) (Exists ($inspection) (And (Member $inspection Inspection) (Requires $facility $inspection) (DuringShift $inspection S1)))) (STV 1.0 1.0)))
!(test
   (let $answers (collapse (query 0 both_sides_rule (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (HasRecordedEvent $s $f) (DuringShift $f S1))) (Exists ($i) (And (Member $i Inspection) (Requires $s $i) (DuringShift $i S1)))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (HasRecordedEvent $s $f) (DuringShift $f S1))) (Exists ($i) (And (Member $i Inspection) (Requires $s $i) (DuringShift $i S1)))) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 both_sides_rule (: $p (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (HasRecordedEvent $s $f) (DuringShift $f S1))) (Exists ($i) (And (Member $i Inspection) (Requires $s $i) (DuringShift $i S1)))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($f) (And (Member $s Facility) (Member $f Flood) (HasRecordedEvent $s $f) (DuringShift $f S1))) (Exists ($i) (And (Member $i Inspection) (Requires $s $i) (DuringShift $i S1)))) 1 1) true $answers)
         false))
   true)

;; assuming_exists
!(test (exists-answer-matches (Assuming (Exists ($x) (P $x)) (Exists ($z) (P $z))) 1 1 true (query 1000 assuming_exists (: $p (Assuming (Exists ($x) (P $x)) (Exists ($z) (P $z))) $tv))) true)
!(test (exists-answer-matches (Assuming (Exists ($x) (P $x)) (Exists ($z) (P $z))) 1 1 true (query 1000 assuming_exists (: $p (Assuming (Exists ($x) (P $x)) (Exists ($z) (P $z))) $tv))) true)

;; assuming_no_leak
!(test (collapse (query 1000 assuming_exists (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 1000 assuming_exists (: $p (Exists ($x) (P $x)) $tv))) ())

;; assuming_no_witness
!(test (collapse (query 1000 assuming_exists (: $p (P $x) $tv))) ())
!(test (collapse (query 1000 assuming_exists (: $p (P $x) $tv))) ())

;; witness_late_before
!(test (collapse (query 1000 late (: $p (Exists ($x) (P $x)) $tv))) ())
!(test (collapse (query 1000 late (: $p (Exists ($x) (P $x)) $tv))) ())

;; witness_late_after
!(compileadd late (: later (P a) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 late (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 late (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)

;; open_population_negative
!(test (collapse (query 1000 open_population_negative (: $p (Not (Exists ($x) (P $x))) $tv))) ())
!(test (collapse (query 1000 open_population_negative (: $p (Not (Exists ($x) (P $x))) $tv))) ())

;; wrong_entity
!(compileadd wrong_entity (: src_seed (Seed Alice) (STV 1 1)))
!(compileadd wrong_entity (: src_gen (Implication (Seed $x) (Exists ($y) (GeneratedBy $x $y))) (STV 1 1)))
!(test (collapse (query 1000 wrong_entity (: $p (Exists ($x) (GeneratedBy Bob $x)) $tv))) ())
!(test (collapse (query 1000 wrong_entity (: $p (Exists ($x) (GeneratedBy Bob $x)) $tv))) ())

;; shared_seed_direct
!(compileadd shared (: seed (Seed a) (STV 0.6 0.8)))
!(compileadd shared (: gen (Implication (Seed $s) (Exists ($y) (GeneratedBy $s $y))) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 shared (: $p (Exists ($y) (GeneratedBy a $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy a $y)) 0.6 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 shared (: $p (Exists ($y) (GeneratedBy a $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy a $y)) 0.6 -1) true $answers)
         false))
   true)

;; shared_seed_later
!(compileadd shared (: concrete (Implication (Seed $s) (GeneratedBy $s concrete)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 shared (: $p (Exists ($y) (GeneratedBy a $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy a $y)) 0.6 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 shared (: $p (Exists ($y) (GeneratedBy a $y)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($y) (GeneratedBy a $y)) 0.6 -1) true $answers)
         false))
   true)

;; shared_witnesses
!(compileadd shared_witnesses (: common (Common) (STV 0.5 0.8)))
!(compileadd shared_witnesses (: r1 (Implication (Common) (P a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd shared_witnesses (: r2 (Implication (Common) (P b)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 shared_witnesses (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.5 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 shared_witnesses (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.5 -1) true $answers)
         false))
   true)

;; existing_shared_fold
!(compileadd existing_shared_fold (: common (Common) (STV 0.5 0.8)))
!(compileadd existing_shared_fold (: r1 (Implication (Common) (P a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd existing_shared_fold (: r2 (Implication (Common) (P b)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd existing_shared_fold (: expose (Implication (KnownExistential ($x) (P $x)) (Seen)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 existing_shared_fold (: $p (Seen) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Seen) 0.5 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 existing_shared_fold (: $p (Seen) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Seen) 0.5 -1) true $answers)
         false))
   true)

;; existing_empty_fold
!(compileadd existing_empty_fold (: expose (Implication (Exists ($x) (P $x)) (Seen)) (CTV (STV 1 1) (STV 0 1))))
!(test (collapse (query 1000 existing_empty_fold (: $p (Seen) $tv))) ())
!(test (collapse (query 1000 existing_empty_fold (: $p (Seen) $tv))) ())

;; direct_plus_partial
!(compileadd direct_plus_partial (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.9 0.5)))
!(compileadd direct_plus_partial (: pa (P a) (STV 0.8 0.5)))
!(compileadd direct_plus_partial (: pb (P b) (STV 0.6 0.7)))
!(test
   (let $answers (collapse (query 1000 direct_plus_partial (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.92 0.7123799949180818) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 direct_plus_partial (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.92 0.7123799949180818) true $answers)
         false))
   true)

;; independent_direct_claims
!(compileadd independent_direct_claims (: d1 (ExistentialClaim (P (exists-slot 0))) (STV 0.8 0.5)))
!(compileadd independent_direct_claims (: d2 (ExistentialClaim (P (exists-slot 0))) (STV 0.6 0.5)))
!(test
   (let $answers (collapse (query 1000 independent_direct_claims (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.7 0.6666666666666666) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 independent_direct_claims (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.7 0.6666666666666666) true $answers)
         false))
   true)

;; stated_ctv
!(compileadd stated_ctv (: r (Implication (Exists ($x) (P $x)) (T)) (CTV (STV 0.8 0.7) (STV 0.2 0.6))))
!(test
   (let $answers (collapse (query 0 stated_ctv (: $p (Implication (Exists ($y) (P $y)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($y) (P $y)) (T)) 0.8 0.7) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 stated_ctv (: $p (Implication (Exists ($y) (P $y)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($y) (P $y)) (T)) 0.8 0.7) true $answers)
         false))
   true)

;; derived_witness
!(compileadd derived_witness (: src (Q a) (STV 0.8 0.5)))
!(compileadd derived_witness (: derive (Implication (Q $x) (P $x)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 derived_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 derived_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; shared_rule
!(compileadd shared_rule (: a (Bird a) (STV 1 1)))
!(compileadd shared_rule (: b (Bird b) (STV 1 1)))
!(compileadd shared_rule (: flies (Implication (Bird $x) (Flies $x)) (CTV (STV 0.9 0.9) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 shared_rule (: $p (Exists ($x) (Flies $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (Flies $x)) 0.99 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 shared_rule (: $p (Exists ($x) (Flies $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (Flies $x)) 0.99 -1) true $answers)
         false))
   true)

;; shared_rule_and
!(test
   (let $answers (collapse (query 1000 shared_rule (: $p (And (Flies a) (Flies b)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (And (Flies a) (Flies b)) 0.81 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 shared_rule (: $p (And (Flies a) (Flies b)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (And (Flies a) (Flies b)) 0.81 -1) true $answers)
         false))
   true)

;; coref_rule
!(compileadd coref_rule (: r (Implication (Exists ($x) (P $x $x)) (T)) (STV 1 1)))
!(test (collapse (query 0 coref_rule (: $p (Implication (Exists ($f) (P $f $s)) (T)) $tv))) ())
!(test (collapse (query 0 coref_rule (: $p (Implication (Exists ($f) (P $f $s)) (T)) $tv))) ())

;; coref_rule_alpha
!(test
   (let $answers (collapse (query 0 coref_rule (: $p (Implication (Exists ($f) (P $f $f)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($f) (P $f $f)) (T)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 coref_rule (: $p (Implication (Exists ($f) (P $f $f)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($f) (P $f $f)) (T)) 1 1) true $answers)
         false))
   true)

;; coref_claim
!(compileadd coref_claim (: direct (ExistentialClaim (P (exists-slot 0) (exists-slot 0))) (STV 1 1)))
!(test (collapse (query 1000 coref_claim (: $p (Exists ($f) (P $f $s)) $tv))) ())
!(test (collapse (query 1000 coref_claim (: $p (Exists ($f) (P $f $s)) $tv))) ())

;; outer_groups
!(compileadd outer_groups (: ga (GeneratedBy a one) (STV 0.8 0.5)))
!(compileadd outer_groups (: gb (GeneratedBy b two) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 1000 outer_groups (: $p (Exists ($y) (GeneratedBy $s $y)) $tv)))
      (if (== (list-count $answers) 2)
         (fold-flat (exists-answer-matches any-group 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 outer_groups (: $p (Exists ($y) (GeneratedBy $s $y)) $tv)))
      (if (== (list-count $answers) 2)
         (fold-flat (exists-answer-matches any-group 0.8 0.5) true $answers)
         false))
   true)

;; direct_stronger
!(compileadd direct_stronger (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.9 0.1)))
!(compileadd direct_stronger (: w (P a) (STV 0.8 0.99)))
!(test
   (let $answers (collapse (query 1000 direct_stronger (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.9 0.1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 direct_stronger (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.9 0.1) true $answers)
         false))
   true)

;; certain_witness
!(compileadd certain_witness (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.9 0.99)))
!(compileadd certain_witness (: w (P a) (STV 1 1)))
!(test
   (let $answers (collapse (query 1000 certain_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 certain_witness (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 1 1) true $answers)
         false))
   true)

;; premise_floor
!(compileadd premise_floor (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.9 0.5)))
!(compileadd premise_floor (: pa (P a) (STV 0.8 0.5)))
!(compileadd premise_floor (: pb (P b) (STV 0.6 0.7)))
!(compileadd premise_floor (: use (Implication (Exists ($x) (P $x)) (T)) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 premise_floor (: $p (T) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (T) 0.92 0.7123799943249737) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 premise_floor (: $p (T) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (T) 0.92 0.7123799943249737) true $answers)
         false))
   true)

;; stated_two
!(compileadd stated_two (: r1 (Implication (Exists ($x) (P $x)) (T)) (STV 0.8 0.5)))
!(compileadd stated_two (: r2 (Implication (Exists ($y) (P $y)) (T)) (STV 0.6 0.5)))
!(test
   (let $answers (collapse (query 0 stated_two (: $p (Implication (Exists ($z) (P $z)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($z) (P $z)) (T)) 0.7 0.6666666666666666) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 stated_two (: $p (Implication (Exists ($z) (P $z)) (T)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($z) (P $z)) (T)) 0.7 0.6666666666666666) true $answers)
         false))
   true)

;; binder_order
!(compileadd binder_order (: r (Implication (Exists ($x $y) (Pair $x $y)) (T)) (STV 1 1)))
!(test (collapse (query 0 binder_order (: $p (Implication (Exists ($f $s) (Pair $s $f)) (T)) $tv))) ())
!(test (collapse (query 0 binder_order (: $p (Implication (Exists ($f $s) (Pair $s $f)) (T)) $tv))) ())

;; and_order
!(compileadd and_order (: r (Implication (Exists ($x) (And (P $x) (Q $x))) (T)) (STV 1 1)))
!(test (collapse (query 0 and_order (: $p (Implication (Exists ($y) (And (Q $y) (P $y))) (T)) $tv))) ())
!(test (collapse (query 0 and_order (: $p (Implication (Exists ($y) (And (Q $y) (P $y))) (T)) $tv))) ())

;; local_binders
!(compileadd local_binders (: r (Implication (Exists ($x) (P $x)) (Exists ($x) (Q $x))) (STV 1 1)))
!(test
   (let $answers (collapse (query 0 local_binders (: $p (Implication (Exists ($a) (P $a)) (Exists ($b) (Q $b))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($a) (P $a)) (Exists ($b) (Q $b))) 1 1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 local_binders (: $p (Implication (Exists ($a) (P $a)) (Exists ($b) (Q $b))) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Implication (Exists ($a) (P $a)) (Exists ($b) (Q $b))) 1 1) true $answers)
         false))
   true)

;; overlap_strength
!(compileadd overlap_strength (: source (S) (STV 0.8 0.9)))
!(compileadd overlap_strength (: a (Implication (S) (P a)) (CTV (STV 0.5 0.99) (STV 0 1))))
!(compileadd overlap_strength (: b (Implication (S) (P b)) (CTV (STV 1 0.1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 overlap_strength (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 -1) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 overlap_strength (: $p (Exists ($x) (P $x)) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 -1) true $answers)
         false))
   true)

;; group_claim
!(compileadd group_claim (: sa (Seed a) (STV 0.7 0.6)))
!(compileadd group_claim (: sb (Seed b) (STV 0.7 0.6)))
!(compileadd group_claim (: g (Implication (Seed $s) (Exists ($y) (GeneratedBy $s $y))) (CTV (STV 1 1) (STV 0 1))))
!(test
   (let $answers (collapse (query 1000 group_claim (: $p (Exists ($y) (GeneratedBy $s $y)) $tv)))
      (if (== (list-count $answers) 2)
         (fold-flat (exists-answer-matches any-group 0.7 0.6) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1000 group_claim (: $p (Exists ($y) (GeneratedBy $s $y)) $tv)))
      (if (== (list-count $answers) 2)
         (fold-flat (exists-answer-matches any-group 0.7 0.6) true $answers)
         false))
   true)

;; budget_0
!(compileadd budget_0 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 0 budget_0 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 0 budget_0 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_1
!(compileadd budget_1 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 1 budget_1 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 1 budget_1 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_2
!(compileadd budget_2 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 2 budget_2 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 2 budget_2 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_3
!(compileadd budget_3 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 3 budget_3 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 3 budget_3 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_4
!(compileadd budget_4 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 4 budget_4 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 4 budget_4 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_5
!(compileadd budget_5 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 5 budget_5 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 5 budget_5 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_6
!(compileadd budget_6 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 6 budget_6 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 6 budget_6 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_7
!(compileadd budget_7 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 7 budget_7 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 7 budget_7 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_8
!(compileadd budget_8 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 8 budget_8 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 8 budget_8 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_9
!(compileadd budget_9 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 9 budget_9 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 9 budget_9 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_10
!(compileadd budget_10 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 10 budget_10 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 10 budget_10 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_11
!(compileadd budget_11 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 11 budget_11 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 11 budget_11 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; budget_12
!(compileadd budget_12 (: w (P a) (STV 0.8 0.5)))
!(test
   (let $answers (collapse (query 12 budget_12 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)
!(test
   (let $answers (collapse (query 12 budget_12 (: $p (Exists ($x) (P $x)) $tv)))
      (if (<= (list-count $answers) 1)
         (fold-flat (exists-answer-matches (Exists ($x) (P $x)) 0.8 0.5) true $answers)
         false))
   true)

;; Forward triggers wake the same floor; the trigger is not another piece of
;; evidence. These assertions read at budget zero after the forward run.
!(compileadd existsForwardKb (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.9 0.5)))
!(compileadd existsForwardKb (: pa (P a) (STV 0.8 0.5)))
!(compileadd existsForwardKb (: pb (P b) (STV 0.6 0.7)))
!(compileadd existsForwardKb (: r (Implication (Exists ($x) (P $x)) (T)) (CTV (STV 1 1) (STV 0 1))))
!(forward-chain 100 existsForwardKb
   (collapse (match &kb ($t (existsForwardKb MAIN Nil) $p $v)
      (assemble-stored-runtime-fact $t (existsForwardKb MAIN Nil) $p $v))))
!(test
   (let $answers (collapse (query 0 existsForwardKb (: $p (T) $tv)))
      (if (== (list-count $answers) 1)
         (fold-flat (exists-answer-matches (T) 0.92 0.7123799943294165) true $answers)
         false))
   true)

!(compileadd existsForwardGroupKb (: ga (GeneratedBy a one) (STV 0.8 0.5)))
!(compileadd existsForwardGroupKb (: gb (GeneratedBy b two) (STV 0.8 0.5)))
!(compileadd existsForwardGroupKb (: r (Implication (Exists ($y) (GeneratedBy $s $y)) (Generated $s)) (CTV (STV 1 1) (STV 0 1))))
!(forward-chain 100 existsForwardGroupKb
   (collapse (match &kb ($t (existsForwardGroupKb MAIN Nil) $p $v)
      (assemble-stored-runtime-fact $t (existsForwardGroupKb MAIN Nil) $p $v))))
!(test
   (list-count (collapse (query 0 existsForwardGroupKb (: $p (Generated $s) $tv))))
   2)
!(test
   (exists-answer-matches (Generated a) 0.8 0.5 true
      (query 0 existsForwardGroupKb (: $p (Generated a) $tv)))
   true)
!(test
   (exists-answer-matches (Generated b) 0.8 0.5 true
      (query 0 existsForwardGroupKb (: $p (Generated b) $tv)))
   true)

;; Materializing the answer must not assert a witness or an internal adapter.
!(compileadd existsMaterializeKb (: direct (ExistentialClaim (P (exists-slot 0))) (STV 0.8 0.5)))
!(test (query-materialize 100 existsMaterializeKb (: $p (Exists ($x) (P $x)) $tv))
   (: direct (Exists ($y) (P $y)) (STV 0.8 0.5)))
!(test (collapse (query 100 existsMaterializeKb (: $p (P $x) $tv))) ())
!(test (collapse (match &kb ($t (existsMaterializeKb MAIN Nil) $p $tv) $t))
   ((ExistentialClaim (P (exists-slot 0)))))
!(test
   (let (query-result 0 (: $proof $_statement $_tv))
      (query-many-refs 100 existsMaterializeKb ((: $p (Exists ($x) (P $x)) $tv)))
      (expand-proof $proof))
   direct)

;; Canonical slots need actual bound positions; an unused binder is rejected.
!(test
   (collapse (compileadd unusedExistsKb
      (: r (Implication (Exists ($x) (P a)) (T)) (STV 1 1))))
   ())

;; Forward matching cannot fill an outer argument with a private binder slot.
!(compileadd existsForwardScopeKb
   (: direct (ExistentialClaim (P (exists-slot 0) (exists-slot 0))) (STV 1 1)))
!(compileadd existsForwardScopeKb
   (: r (Implication (Exists ($f) (P $f $s)) (T $s)) (CTV (STV 1 1) (STV 0 1))))
!(forward-chain 100 existsForwardScopeKb
   (collapse (match &kb ($t (existsForwardScopeKb MAIN Nil) $p $v)
      (assemble-stored-runtime-fact $t (existsForwardScopeKb MAIN Nil) $p $v))))
!(test (collapse (query 0 existsForwardScopeKb (: $p (T $s) $tv))) ())

;; Review regressions for f71e3d67.

;; A residual with no known witnesses keeps the direct existential mass.
!(compileadd residualEmpty (: direct (ExistentialClaim (Cat (exists-slot 0))) (STV 0.9 0.9)))
!(compileadd residualEmpty (: residual (Implication (ExistentialResidual ($x) (Cat $x)) (Other)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd residualEmpty (: known (Implication (KnownExistential ($x) (Cat $x)) (Known)) (CTV (STV 1 1) (STV 0 1))))
!(test (exists-answer-matches (Other) 0.9 0.9 true (query 100 residualEmpty (: $p (Other) $tv))) true)
!(test (exists-answer-matches (Other) 0.9 0.9 true (query 0 residualEmpty (: $p (Other) $tv))) true)
!(test (collapse (query 100 residualEmpty (: $p (Known) $tv))) ())
!(compileadd residualEmpty (: cat (Cat felix) (STV 0.3 0.9)))
!(test (exists-answer-matches (Other) 0.8571428571428572 -1 true (query 100 residualEmpty (: $p (Other) $tv))) true)
!(test (exists-answer-matches (Known) 0.3 0.9 true (query 100 residualEmpty (: $p (Known) $tv))) true)
!(test (collapse (query 100 residualMissing (: $p (Other) $tv))) ())

;; The direct claim supplies outer groups even if none has a known witness.
!(compileadd residualGroups (: da (ExistentialClaim (GeneratedBy a (exists-slot 0))) (STV 0.9 0.9)))
!(compileadd residualGroups (: db (ExistentialClaim (GeneratedBy b (exists-slot 0))) (STV 0.9 0.9)))
!(compileadd residualGroups (: residual (Implication (ExistentialResidual ($y) (GeneratedBy $s $y)) (Other $s)) (CTV (STV 1 1) (STV 0 1))))
!(test (list-count (collapse (query 100 residualGroups (: $p (Other $s) $tv)))) 2)
!(test (exists-answer-matches (Other a) 0.9 0.9 true (query 100 residualGroups (: $p (Other a) $tv))) true)
!(compileadd residualGroups (: ga (GeneratedBy a one) (STV 0.3 0.9)))
!(test (exists-answer-matches (Other a) 0.8571428571428572 -1 true (query 100 residualGroups (: $p (Other a) $tv))) true)
!(test (exists-answer-matches (Other b) 0.9 0.9 true (query 100 residualGroups (: $p (Other b) $tv))) true)

;; Exact strength ties use evidence confidence, in either ingestion order,
;; including a warm claim-only query and equal strengths written as 1/1.0.
!(compileadd tieDirectFirst (: direct (ExistentialClaim (P (exists-slot 0))) (STV 1 0.5)))
!(test (exists-answer-matches (Exists ($x) (P $x)) 1 0.5 true (query 100 tieDirectFirst (: $p (Exists ($x) (P $x)) $tv))) true)
!(compileadd tieDirectFirst (: witness (P a) (STV 1 0.9)))
!(test (exists-answer-matches (Exists ($x) (P $x)) 1 0.9 true (query 100 tieDirectFirst (: $p (Exists ($x) (P $x)) $tv))) true)
!(compileadd tieWitnessFirst (: witness (P a) (STV 1.0 0.9)))
!(compileadd tieWitnessFirst (: direct (ExistentialClaim (P (exists-slot 0))) (STV 1 0.5)))
!(test (exists-answer-matches (Exists ($x) (P $x)) 1 0.9 true (query 100 tieWitnessFirst (: $p (Exists ($x) (P $x)) $tv))) true)
!(compileadd tieEqual (: witness (P a) (STV 1 0.9)))
!(compileadd tieEqual (: direct (ExistentialClaim (P (exists-slot 0))) (STV 1 0.9)))
!(test (query 100 tieEqual (: $p (Exists ($x) (P $x)) $tv))
   (: direct (Exists ($x) (P $x)) (STV 1 0.9)))

;; One overlap collapses the whole witness population. The independent .4
;; witness is not ORed with the correlated .5 component in stage 1.
!(compileadd overlapReview (: source (S) (STV 0.5 0.8)))
!(compileadd overlapReview (: rb (Implication (S) (P b)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd overlapReview (: ra (Implication (S) (P a)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd overlapReview (: pc (P c) (STV 0.4 0.9)))
!(test (exists-answer-matches (Exists ($x) (P $x)) 0.5 0.8 true (query 100 overlapReview (: $p (Exists ($x) (P $x)) $tv))) true)
!(test
   (let (query-result 0 (: $proof $_statement $_tv))
      (query-many-refs 100 overlapReview ((: $p (Exists ($x) (P $x)) $tv)))
      (expand-proof $proof))
   (by ra source))
;; Inspect the actual cached fold evidence, not evidence reconstructed from
;; its public proof. It must exactly equal that of the selected witness.
!(test
   (let* (($key (sk-fold ((overlapReview MAIN Nil) (P $x) extract-tv (STV 0 0) OrFormula identity result-tv)))
          ((sk-goal-val $_goal $_proof $ev $_deps) (sk-latest-view (index-hash $key) $key 0))
          ((sk-val $_fact $chosen-ev $_chosen-deps) (sk-key-value (sk-key (P a) (overlapReview MAIN Nil)))))
      (if (evidence-subset? $ev $chosen-ev) (evidence-subset? $chosen-ev $ev) false))
   true)
;; A stronger later independent witness must still wake the whole fold.
!(compileadd overlapReview (: pd (P d) (STV 0.7 0.9)))
!(test (exists-answer-matches (Exists ($x) (P $x)) 0.7 0.9 true (query 100 overlapReview (: $p (Exists ($x) (P $x)) $tv))) true)
!(test
   (let (query-result 0 (: $proof $_statement $_tv))
      (query-many-refs 100 overlapReview ((: $p (Exists ($x) (P $x)) $tv)))
      (expand-proof $proof))
   pd)
