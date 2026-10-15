!(import! &self ../../pettachainer/metta/petta_chainer)

;; #51: conditional judgments assume a scoped claim, never its body.
;; A successful answer must preserve the entire variable-sharing shape and
;; both source rules in one expanded proof. Context IDs are query-local.
(: quantified-answer? (-[det]-> KB Statement Proof Number Bool))
(= (quantified-answer? $kb $statement $expected-proof $strength)
   (case (collapse (query 500 $kb (: $p $statement $tv))) (
      (((: $proof $answer (STV $s $c)))
         (if (=alpha $statement $answer)
            (if (= $expected-proof $proof)
               (if (>= $s (- $strength 0.000001))
                  (if (<= $s (+ $strength 0.000001)) (> $c 0.01) false) false)
               false)
            false))
      ($_other false))))

!(compileadd quantifiedKb (: src_flood_inspection (Implication (Exists ($event) (And (Member $site Facility) (RecordedFlood $site $event) (During $event S1))) (RequiresInspectionDuring $site S1)) (STV 1 1)))
!(compileadd quantifiedKb (: src_inspection_pause (Implication (RequiresInspectionDuring $site S1) (MustPauseProductionDuring $site S1)) (STV 1 1)))
!(test (collapse (query 500 quantifiedKb (: $p (RecordedFlood $site $event) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (During $event S1) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Member $event Flood) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Member $site Facility) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (MustPauseProductionDuring $site S1) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) $tv))) ())

;; Cold, warm, alpha-renamed, and grounded queries; no composed rule is stored.
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) (conditional-implication (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) (conditional-implication (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? quantifiedKb (Implication (Exists ($event) (And (Member $site Facility) (RecordedFlood $site $event) (During $event S1))) (MustPauseProductionDuring $site S1)) (conditional-implication (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (MustPauseProductionDuring F1 S1)) (conditional-implication (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)

;; The statement and every body predicate remain unknown in the same warm worker.
!(test (collapse (query 500 quantifiedKb (: $p (RecordedFlood $site $event) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (During $event S1) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Member $event Flood) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Member $site Facility) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (MustPauseProductionDuring $site S1) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) $tv))) ())

;; Neither a different shift nor a different facility may supply the premise.
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S2))) (MustPauseProductionDuring $site S2)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (MustPauseProductionDuring F2 S1)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring F2 S1)) $tv))) ())

;; A two-rule path needs both rules, even after a previous negative read.
!(compileadd missingFirst (: missing_pause (Implication (RequiresInspectionDuring $site S1) (MustPauseProductionDuring $site S1)) (STV 1 1)))
!(test (collapse (query 500 missingFirst (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv))) ())
!(compileadd missingSecond (: missing_flood (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (RequiresInspectionDuring $site S1)) (STV 1 1)))
!(test (collapse (query 500 missingSecond (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv))) ())
!(compileadd missingSecond (: late_pause (Implication (RequiresInspectionDuring $site S1) (MustPauseProductionDuring $site S1)) (STV 1 1)))
!(test (quantified-answer? missingSecond (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) (conditional-implication (by late_pause (by missing_flood (ctx proof $ctx)))) 1) true)

;; Every rung may be unknown or positive, never false from unfinished folds.
!(test (let $answers (collapse (query 0 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 1 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 2 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 3 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 4 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 5 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 6 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 7 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 8 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 9 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 10 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 11 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 12 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 13 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 14 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)
!(test (let $answers (collapse (query 15 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv)))
   (fold-flat (|-> ($valid $answer)
      (let (: $_p $_statement (STV $s $_c)) $answer (and $valid (> $s 0)))) true $answers)) true)

;; Assuming installs the same claim, including in an And of assumptions.
!(test (quantified-answer? quantifiedKb (Assuming (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (MustPauseProductionDuring F1 S1)) (assuming (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? quantifiedKb (Assuming (And (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (Permit F1)) (MustPauseProductionDuring F1 S1)) (assuming (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (collapse (query 500 quantifiedKb (: $p (Assuming (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (MustPauseProductionDuring F2 S1)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (Assuming (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (RecordedFlood F1 $event)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (MustPauseProductionDuring $site S1) $tv))) ())

;; Existential consequents retain shared outer variables and local slots.
!(compileadd quantifiedKb (: src_inspection_event (Implication (RequiresInspectionDuring $site S1) (Exists ($i) (And (Member $i Inspection) (For $i $site)))) (STV 1 1)))
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (Exists ($i) (And (Member $i Inspection) (For $i $site)))) (conditional-implication (by src_inspection_event (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (Exists ($i) (And (Member $i Inspection) (For $i F1)))) (conditional-implication (by src_inspection_event (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (let (: $_proof $answer $_tv)
   (query 500 quantifiedKb (: $p
      (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1)))
         (Exists ($flood) (And (Member $flood Inspection) (For $flood $site)))) $tv))
   (=alpha $answer
      (Implication (Exists ($event) (And (Member $facility Facility) (RecordedFlood $facility $event) (During $event S1)))
         (Exists ($inspection) (And (Member $inspection Inspection) (For $inspection $facility)))))) true)
!(test (quantified-answer? quantifiedKb (Assuming (Exists ($flood) (And (Member F1 Facility) (RecordedFlood F1 $flood) (During $flood S1))) (Exists ($i) (And (Member $i Inspection) (For $i F1)))) (assuming (by src_inspection_event (by src_flood_inspection (ctx proof $ctx)))) 1) true)
!(test (collapse (query 500 quantifiedKb (: $p (Exists ($i) (And (Member $i Inspection) (For $i $site))) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p (For $inspection $site) $tv))) ())

;; Co-reference is structural: slots never unify with a free variable or a different slot.
!(compileadd corefKb (: coref_source (Implication (Exists ($x) (P $site $x $x)) (Ready $site)) (STV 1 1)))
!(compileadd corefKb (: coref_end (Implication (Ready $site) (Done $site)) (STV 1 1)))
!(test (quantified-answer? corefKb (Implication (Exists ($event) (P $site $event $event)) (Done $site)) (conditional-implication (by coref_end (by coref_source (ctx proof $ctx)))) 1) true)
!(test (collapse (query 500 corefKb (: $p (Implication (Exists ($event) (P $site $event $site)) (Done $site)) $tv))) ())
!(test (collapse (query 500 corefKb (: $p (Implication (Exists ($x $y) (P $site $x $y)) (Done $site)) $tv))) ())
!(test (collapse (query 500 corefKb (: $p (Assuming (Exists ($x $y) (P F1 $x $y)) (Done F1)) $tv))) ())
!(compileadd slotsKb (: slots_source (Implication (Seed $site) (Exists ($x $y) (Rel $site $x $y $x))) (STV 1 1)))
!(compileadd slotsKb (: slots_begin (Implication (Start $site) (Seed $site)) (STV 1 1)))
!(test (quantified-answer? slotsKb (Implication (Start $site) (Exists ($a $b) (Rel $site $a $b $a))) (conditional-implication (by slots_source (by slots_begin (ctx proof $ctx)))) 1) true)
!(test (collapse (query 500 slotsKb (: $p (Implication (Start $site) (Exists ($a) (Rel $site $a $a $a))) $tv))) ())

;; Free goal variables cannot ground a same-spelled binder in an Assuming answer.
!(compileadd localKb (: local_source (Implication (Exists ($x) (P $x)) (Named F1)) (STV 1 1)))
!(test (quantified-answer? localKb (Assuming (Exists ($x) (P $x)) (Named F1)) (assuming (by local_source (ctx proof $ctx))) 1) true)
!(test (let (: $_proof (Assuming (Exists ($bound) (P $body)) (Named $name)) $_tv)
   (query 500 localKb (: $p (Assuming (Exists ($x) (P $x)) (Named $x)) $tv))
   (and (is-var $bound) (and (== $bound $body) (== $name F1)))) true)

;; Syntactic body order is significant; no quantifier distribution is inferred.
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (RecordedFlood $site $flood) (Member $site Facility) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv))) ())

;; Retirement and re-addition cannot retain the warm conditional answer.
!(withdraw-named-rules! src_flood_inspection)
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv))) ())
!(compileadd quantifiedKb (: src_flood_inspection (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (RequiresInspectionDuring $site S1)) (CTV (STV 0.8 0.9) (STV 0 1))))
!(test (quantified-answer? quantifiedKb (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) (conditional-implication (by src_inspection_pause (by src_flood_inspection (ctx proof $ctx)))) 0.8) true)
!(withdraw-named-rules! src_inspection_pause)
!(test (collapse (query 500 quantifiedKb (: $p (Implication (Exists ($flood) (And (Member $site Facility) (RecordedFlood $site $flood) (During $flood S1))) (MustPauseProductionDuring $site S1)) $tv))) ())

;; A cycle cannot create its own existential evidence.
!(compileadd cycleKb (: cycle1 (Implication (Exists ($x) (P $site $x)) (Exists ($y) (Q $site $y))) (CTV (STV 0.8 0.9) (STV 0 1))))
!(compileadd cycleKb (: cycle2 (Implication (Exists ($y) (Q $site $y)) (Exists ($x) (P $site $x))) (CTV (STV 0.9 0.9) (STV 0 1))))
!(test (collapse (query 500 cycleKb (: $p (Exists ($x) (P F1 $x)) $tv))) ())
!(test (quantified-answer? cycleKb (Implication (Exists ($x) (P $site $x)) (Exists ($y) (Q $site $y))) (brand Proof $proof) 0.8) true)
!(test (collapse (query 500 cycleKb (: $p (Exists ($x) (P F1 $x)) $tv))) ())

;; Statistical evidence contains both uncertain source rules exactly once.
!(compileadd evidenceKb (: uncertain_first (Implication (Exists ($x) (P $site $x)) (Mid $site))
   (CTV (STV 0.8 0.9) (STV 0 1))))
!(compileadd evidenceKb (: uncertain_second (Implication (Mid $site) (Done $site))
   (CTV (STV 0.7 0.8) (STV 0 1))))
!(test (quantified-answer? evidenceKb
   (Implication (Exists ($x) (P $site $x)) (Done $site))
   (conditional-implication (by uncertain_second (by uncertain_first (ctx proof $ctx)))) 0.56) true)
;; Read the actual evaluated view: &proof caches fact leaves for overlap
;; checks, while the view also carries rule evidence. Keep the usual query
;; cleanup bracket after taking the evidence snapshot.
(: quantified-evidence (-[nondet]-> KB Statement (EvidenceSet TV)))
(= (quantified-evidence $kb $statement)
   (let* (((compiled-query $goal $adds) (mm2compileQuery $kb (: $p $statement $tv)))
          ($_inject (once (inject-compiled-adds $adds)))
          ($root (typed-runtime-premise $goal))
          ((($type $scope $_proof $_tv)) (chainer 500 $root))
          ((sk-val $_fact $ev $_deps)
             (sk-root-key-value $root (sk-key $type $scope)))
          ($_clear (clear-temp-query-adds))
          ($_contexts (sk-clear-contexts!)))
      (data $ev (the TV $_tv))))
!(test (let ($ev $_tv) (quantified-evidence evidenceKb
   (Implication (Exists ($x) (P $site $x)) (Done $site))) $ev)
   (evidence-set ((rule-ev evidenceKb uncertain_first) (rule-ev evidenceKb uncertain_second))))

;; A diamond shares its uncertain source: And must not multiply .8 by .8.
!(compileadd sharedKb (: shared_source (Implication (Exists ($x) (P $site $x)) (Mid $site))
   (CTV (STV 0.8 0.9) (STV 0 1))))
!(compileadd sharedKb (: left_source (Implication (Mid $site) (Left $site)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd sharedKb (: right_source (Implication (Mid $site) (Right $site)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd sharedKb (: join_source (Implication (And (Left $site) (Right $site)) (Done $site)) (CTV (STV 1 1) (STV 0 1))))
!(test (quantified-answer? sharedKb
   (Implication (Exists ($x) (P $site $x)) (Done $site)) (brand Proof $proof) 0.8) true)
!(test (let ($ev (STV $_s $c)) (quantified-evidence sharedKb
   (Implication (Exists ($x) (P $site $x)) (Done $site)))
   (data $ev (<= $c 0.9)))
   (data (evidence-set ((rule-ev sharedKb shared_source))) true))

;; A stated quantified axiom and its own application are the same evidence.
!(compileadd exactKb (: exact_source (Implication (Exists ($x) (P $s $x)) (Done $s))
   (CTV (STV 0.8 0.9) (STV 0 1))))
!(test (let (: $proof $_statement $tv)
   (query 0 exactKb (: $p (Implication (Exists ($y) (P $s $y)) (Done $s)) $tv))
   (data $proof $tv)) (exact_source (STV 0.8 0.9)))
!(test (let (: $proof $_statement $tv)
   (query 500 exactKb (: $p (Implication (Exists ($y) (P $s $y)) (Done $s)) $tv))
   (data $proof $tv)) (exact_source (STV 0.8 0.9)))

;; A witness may be derived privately; a compound body gets scoped adapters.
!(compileadd witnessKb (: gen (Implication (Seed $s) (GeneratedBy $s a)) (STV 1 1)))
!(compileadd witnessKb (: mark (Implication (Seed $s) (Good $s a)) (STV 1 1)))
!(test (quantified-answer? witnessKb
   (Implication (Seed $s) (Exists ($y) (GeneratedBy $s $y)))
   (conditional-implication (disjunction (by gen (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? witnessKb
   (Implication (Seed F1) (Exists ($y) (GeneratedBy F1 $y)))
   (conditional-implication (disjunction (by gen (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? witnessKb
   (Implication (Seed $s) (Exists ($y) (And (GeneratedBy $s $y) (Good $s $y))))
   (conditional-implication (disjunction (conjunction (by gen (ctx proof $ctx)) (by mark (ctx proof $ctx))))) 1) true)
!(test (quantified-answer? witnessKb
   (Implication (Seed F1) (Exists ($y) (And (GeneratedBy F1 $y) (Good F1 $y))))
   (conditional-implication (disjunction (conjunction (by gen (ctx proof $ctx)) (by mark (ctx proof $ctx))))) 1) true)
!(test (collapse (query 500 witnessKb (: $p (GeneratedBy $s $y) $tv))) ())
!(test (collapse (query 500 witnessKb (: $p (Exists ($y) (GeneratedBy F1 $y)) $tv))) ())

;; Ground intermediate claims must stay in the same private judgment too.
!(compileadd chainKb (: chain1 (Implication (Exists ($x) (P $site $x)) (Exists ($y) (Q $site $y))) (STV 1 1)))
!(compileadd chainKb (: chain2 (Implication (Exists ($z) (Q $site $z)) (Done $site)) (STV 1 1)))
!(test (quantified-answer? chainKb
   (Implication (Exists ($x) (P $site $x)) (Done $site))
   (conditional-implication (by chain2 (by chain1 (ctx proof $ctx)))) 1) true)
!(test (quantified-answer? chainKb
   (Implication (Exists ($x) (P F1 $x)) (Done F1))
   (conditional-implication (by chain2 (by chain1 (ctx proof $ctx)))) 1) true)
!(test (collapse (query 500 chainKb (: $p (Exists ($y) (Q F1 $y)) $tv))) ())

;; Unsupported quantified forms fail cleanly, rather than becoming predicates.
!(test (collapse (query 500 quantifiedKb (: $p
   (Implication (Exists ($x) (Exists ($y) (P $x $y))) (Done F1)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p
   (Implication (And (Exists ($x) (P $x)) (Ready)) (Done F1)) $tv))) ())
!(test (collapse (query 500 quantifiedKb (: $p
   (Assuming (Implication (Exists ($x) (P $x)) (Ready)) (Ready)) $tv))) ())
