!(import! &self ../../pettachainer/metta/petta_chainer)

;; Problem is definitionally equivalent to an OR of its two causes.  The
;; generated BiImplication directions are already explicit and must not create
;; another pair of Bayesian inversions.
!(compileadd orInversionConditionedMergeKb
   (: localPrior
      (LocalProblem current)
      (STV 0.4 0.9)))
!(compileadd orInversionConditionedMergeKb
   (: dependencyPrior
      (ProblemDependency current)
      (STV 0.2 0.9)))
!(compileadd orInversionConditionedMergeKb
   (: problemDefinition
      (BiImplication
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         (Problem current))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

;; Filtering out a completion driven by the current alarm legitimately
;; leaves the independent .4/.2 priors, each at confidence .9. Their OR is
;; .52 with OrFormula confidence .9140621947; #69 reads .5199995299.
;; A's former comparison with the self-supporting, alarm-updated local .6977
;; incorrectly discounted those correct priors. The exclusion-compatible
;; reference now leaves them unchanged, restoring the F/R values below.
;; Exact enumeration gives .52*.9/(.52*.9+.48*.1)=.9069767442 for Problem
;; and .4*.9/(.4*.9+.6*(.2*.9+.8*.1))=.6976744186 for LocalProblem.
;; Remaining strength offsets are the finite #69 prior, not conditioning error.
;;
;; The current alarm supplies independent evidence for Problem. Historical
;; cases provide the base rate of Problem, the prior this ordinary implication
;; is inverted over.
!(compileadd orInversionConditionedMergeKb
   (: problemRaisesAlarm
      (Implication
         (Problem $unit)
         (Alarm $unit))
      (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd orInversionConditionedMergeKb
   (: currentAlarm
      (Alarm current)
      (STV 1.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd orInversionConditionedMergeKb
   (: h2Problem (Problem h2) (STV 0.0 1.0)))

;; The OR follows from the Problem estimate. The alarm is independent of the
;; two priors given Problem, so its inversion's likelihood ratio moves the
;; definition's odds instead of the base rate's (prior_factored_merge.md): odds
;; 0.52 / 0.48 times the stated ratio 0.9 / 0.1 give 0.907. The base rate is
;; read from two historical cases, so the confidence falls with its variance.
;; The OR is read through its key (#142): its own view is the parts' prior,
;; and the certain bi-backward rule carries the inversion over Problem to it
;; as the same update, which factors onto that prior.
!(test
   (query 2000 orInversionConditionedMergeKb
      (: $proof
         (Or
            (LocalProblem current)
            (ProblemDependency current))
         $tv))
   (: (factored-revision (conjunction localPrior dependencyPrior) (prior (STV 0.5199995299237528 0.9140621948732192)) ((by (bi-backward problemDefinition) ((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm)))) (Or (LocalProblem current) (ProblemDependency current)) (STV 0.9069765852904983 0.969129085157964)))

;; The general Problem estimate can use both the definition and the alarm.
;; The base rates count the whole population, including the derived alarm.
!(test
   (query 5000 orInversionConditionedMergeKb
      (: $proof (Problem current) $tv))
   (: (factored-revision (by (bi-forward problemDefinition) (conjunction localPrior dependencyPrior)) (prior (STV 0.5199995299237518 0.9140621947055227)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm))) (Problem current) (STV 0.906976585290498 0.9691290859469237)))

;; LocalProblem cannot reuse evidence that depends on itself: the general
;; Problem estimate does. The completion of the definition onto it reads the
;; alarm's inversion over Problem's base rate, which does not, with the other
;; disjunct at its value. The completion updates the stored localPrior in
;; its population prior's place (#42): odds(.4)*odds(completion)/
;; odds(.4185934569) gives .6976600101. Revision formerly drowned out
;; this diagnostic update in the stored belief's evidence count.
!(test
   (query 20000 orInversionConditionedMergeKb
      (: $proof (LocalProblem current) $tv))
   (: (factored-revision localPrior (prior (STV 0.4000027777006194 0.9)) (((antecedent-completion (bi-forward problemDefinition) 0 with cpu (prior (STV 0.5 0.0))) (conjunction dependencyPrior ((inverted problemRaisesAlarm with cpu (prior (STV 0.5058705455289852 0.003629357526433342))) currentAlarm))))) (LocalProblem current) (STV 0.6976768597879697 0.9110388213710066)))

;; The same with an atom: Local is derived (0.52) and certainly equivalent to
;; Problem. The bi-backward application of the alarm's inversion over Problem
;; is the same update of Local, over the same prior, so it factors onto
;; Local's own 0.52 as it factors onto Problem's: exact 0.907 for both. Master
;; revised the two as independent views and kept 0.520.
!(compileadd atomEqKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd atomEqKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd atomEqKb (: problemDefinition (BiImplication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd atomEqKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd atomEqKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd atomEqKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd atomEqKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(test (query 2000 atomEqKb (: $proof (Local current) $tv))
   (: (factored-revision (by srcRule src) (prior (STV 0.5199999995 0.9999000099990001)) ((by (bi-backward problemDefinition) ((inverted problemRaisesAlarm with cpu (prior (STV 0.5062495703411769 0.003735865981753913))) currentAlarm)))) (Local current) (STV 0.9069767440170363 0.9998893381888581)))
!(test (query 2000 atomEqKb (: $proof (Problem current) $tv))
   (: (factored-revision (by (bi-forward problemDefinition) (by srcRule src)) (prior (STV 0.5199999994999991 0.9999000097983993)) (((inverted problemRaisesAlarm with cpu (prior (STV 0.5062495703411769 0.003735865981753913))) currentAlarm))) (Problem current) (STV 0.906976744017036 0.9998893390306737)))

;; The carry needs only a certain rule from Problem to Local, and an inversion
;; of Local's own leaves it as it is.
!(compileadd impEqKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd impEqKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd impEqKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd impEqKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd impEqKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd impEqKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd impEqKb (: f1 (Implication (Problem current) (Local current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (let (: $_p $_t $tv) (query 2000 impEqKb (: $proof (Local current) $tv)) $tv) (STV 0.9069767440170361 0.9998893381890228))
!(compileadd localAlarmKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd localAlarmKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd localAlarmKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd localAlarmKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd localAlarmKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd localAlarmKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd localAlarmKb (: pd (BiImplication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd localAlarmKb (: localAlarm (Implication (Local $u) (Alarm $u)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(test (let (: $_p $_t $tv) (query 2000 localAlarmKb (: $proof (Local current) $tv)) $tv) (STV 0.9069767440170363 0.999889338244343))

;; Implications both ways: each carries the other's inversion.
!(compileadd twoWayKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd twoWayKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd twoWayKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd twoWayKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd twoWayKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd twoWayKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd twoWayKb (: f1 (Implication (Problem current) (Local current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd twoWayKb (: f2 (Implication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (let (: $_p $_t $tv) (query 2000 twoWayKb (: $proof (Local current) $tv)) $tv) (STV 0.9029692616043835 0.9999528999802401))

;; Current behaviour, as on master: two certain equivalences between Local and
;; Problem, a second BiImplication or the reverse one, give Local two
;; applications of the one update, and the carry is lost (0.520).
!(compileadd dupEqKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd dupEqKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd dupEqKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd dupEqKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd dupEqKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd dupEqKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd dupEqKb (: pd (BiImplication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd dupEqKb (: pd2 (BiImplication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (let (: $_p $_t $tv) (query 2000 dupEqKb (: $proof (Local current) $tv)) $tv) (STV 0.5200009875095359 0.9999000102573048))
!(compileadd revEqKb (: src (Src current) (STV 1.0 1.0)))
!(compileadd revEqKb (: srcRule (Implication (Src current) (Local current)) (CTV (STV 0.52 1.0) (STV 0.52 1.0))))
!(compileadd revEqKb (: problemRaisesAlarm (Implication (Problem $unit) (Alarm $unit)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd revEqKb (: currentAlarm (Alarm current) (STV 1.0 1.0)))
!(compileadd revEqKb (: h1Problem (Problem h1) (STV 1.0 1.0)))
!(compileadd revEqKb (: h2Problem (Problem h2) (STV 0.0 1.0)))
!(compileadd revEqKb (: pd (BiImplication (Local current) (Problem current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd revEqKb (: pdr (BiImplication (Problem current) (Local current)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (let (: $_p $_t $tv) (query 2000 revEqKb (: $proof (Local current) $tv)) $tv) (STV 0.5200009875095359 0.9999000102573048))

;; A premise with a variable the conclusion lacks is one of many instances,
;; with a population prior of its own: (P $x $y) -> (Q $x) is no equivalence,
;; and Q's inversion keeps Q's prior (0.9878 under P's 0.5 when registered).
!(compileadd coverKb (: pa (Implication (P $x $y) (Al $x $y)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd coverKb (: qa (Implication (Q $x) (Alq $x)) (CTV (STV 0.9 1.0) (STV 0.1 1.0))))
!(compileadd coverKb (: pq (Implication (P $x $y) (Q $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test (collapse (match &equivalence_rules ($prf coverKb) $prf)) ())
!(compileadd coverKb (: h1 (P h1 a) (STV 1.0 1.0)))
!(compileadd coverKb (: h2 (P h2 b) (STV 0.0 1.0)))
!(compileadd coverKb (: g1 (Q h1) (STV 1.0 1.0)))
!(compileadd coverKb (: g2 (Q h4) (STV 0.0 1.0)))
!(compileadd coverKb (: g3 (Q h5) (STV 0.0 1.0)))
!(compileadd coverKb (: al1 (Al k y1) (STV 1.0 1.0)))
!(compileadd coverKb (: alq (Alq k) (STV 1.0 1.0)))
!(test (let (: $_p $_t $tv) (query 2000 coverKb (: $p (Q k) $tv)) $tv) (STV 0.9863685918674778 0.06974122484843895))

;; An assumed rule is compiled for its world only and registers no
;; equivalence, so worlds leave the registry as it was.
!(compileadd assumeEqKb (: a (A k) (STV 0.7 0.9)))
!(query 200 assumeEqKb (: $p (Assuming (: r (Implication (A $x) (B $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (B k)) $tv))
!(query 200 assumeEqKb (: $p (Assuming (: r (Implication (A $x) (B $x)) (CTV (STV 1.0 1.0) (STV 0.0 1.0))) (B k)) $tv))
!(test (collapse (match &equivalence_rules ($prf assumeEqKb) $prf)) ())
