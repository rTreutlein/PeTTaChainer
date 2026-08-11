; Minimal prototype: derive TaskContext instead of hardcoding it.
;
; Goal:
;   Given a query like (Flies tweety), derive which local chart to use.
;
; Mechanism:
;   1. Entity metadata gives the most specific known type.
;   2. Context metadata says which type each chart is scoped to.
;   3. SubtypeOrEqual lets a Penguin use both Penguin and Bird charts.
;   4. TypeDepth encodes specificity. Deeper type = more specific chart.
;   5. Adequacy blocks contexts with invalid assumptions.
;   6. SelectFlyContext chooses the most specific adequate applicable chart.

(= (Between $x $lo $hi) (and (> $x $lo) (< $x $hi)))

; ----------------------------------------------------------------------
; Persistent facts and context metadata
; ----------------------------------------------------------------------

; EntityType stores the most specific known type for this small prototype.
(= (EntityType tweety) Penguin)
(= (EntityType robin) Sparrow)

; Type hierarchy. Equality is handled by SubtypeOrEqual.
(= (DirectSubtype Penguin Bird) true)
(= (DirectSubtype Sparrow Bird) true)

(= (SubtypeOrEqual $type $type) true)
(= (SubtypeOrEqual $type $super)
   (if (DirectSubtype $type $super)
      true
      false))
(= (SubtypeOrEqual Sparrow Penguin) false)

; Specificity is explicit metadata. More specific concepts have larger depth.
(= (TypeDepth Bird) 1)
(= (TypeDepth Sparrow) 2)
(= (TypeDepth Penguin) 2)

; Context scopes say which local chart is appropriate for which predicate/type.
(= (ContextScopedType bird-flight-context Flies) Bird)
(= (ContextScopedType penguin-flight-context Flies) Penguin)

; The persistent evidence remains context-indexed.
(= (PersistentEvidence Flies bird-flight-context) (EC 950.0 50.0))
(= (PersistentEvidence Flies penguin-flight-context) (EC 0.0 100.0))

; Priors and assumptions are chart metadata, not persistent belief.
(= (ContextPrior bird-flight-context Flies) (Prior 0.95 2.0))
(= (ContextPrior penguin-flight-context Flies) (Prior 0.95 2.0))

(= (ContextAssumptions bird-flight-context)
   (Assumptions temperate-aviary same-bird-boundary))

(= (ContextAssumptions penguin-flight-context)
   (Assumptions antarctic-penguin-study penguin-boundary))

; Adequacy is where assumption checks, reliability, budget, and provenance
; gates would go. Here we keep one boolean hook to make selection explicit.
(= (ContextAdequate? bird-flight-context) true)
(= (ContextAdequate? penguin-flight-context) true)

; ----------------------------------------------------------------------
; Applicability and specificity
; ----------------------------------------------------------------------

; A context applies when the query predicate matches and the entity's most
; specific type is a subtype of the context's scoped type.
(= (ContextApplies? ($predicate $entity) $ctx)
   (let* (($entity-type (EntityType $entity))
          ($scoped-type (ContextScopedType $ctx $predicate)))
      (SubtypeOrEqual $entity-type $scoped-type)))

; Chart specificity comes from the scoped type, not from evidence strength.
; This is the concrete encoding of "penguin chart is more specific than
; bird chart" in this prototype.
(= (ContextSpecificity $ctx $predicate)
   (let $scoped-type (ContextScopedType $ctx $predicate)
      (TypeDepth $scoped-type)))

(= (BetterContext? $ctx-a $ctx-b $predicate)
   (> (ContextSpecificity $ctx-a $predicate)
      (ContextSpecificity $ctx-b $predicate)))

; ----------------------------------------------------------------------
; Minimal deterministic selector
; ----------------------------------------------------------------------

; The candidate set is intentionally finite and explicit in this prototype.
; A real system would collect these by matching all ContextScopedType atoms.
(= (KnownFlyContexts) (bird-flight-context penguin-flight-context))

(= (SelectFlyContextFrom2 $query $ctx-a $ctx-b)
   (let* ((($predicate $_entity) $query)
          ($a-ok (and (ContextAdequate? $ctx-a) (ContextApplies? $query $ctx-a)))
          ($b-ok (and (ContextAdequate? $ctx-b) (ContextApplies? $query $ctx-b))))
      (if (and $a-ok $b-ok)
         (if (BetterContext? $ctx-b $ctx-a $predicate) $ctx-b $ctx-a)
         (if $b-ok $ctx-b $ctx-a))))

(= (SelectFlyContext $query)
   (let ($ctx-a $ctx-b) (KnownFlyContexts)
      (SelectFlyContextFrom2 $query $ctx-a $ctx-b)))

; ----------------------------------------------------------------------
; Derived TaskContext and chart construction
; ----------------------------------------------------------------------

(= (InferTaskContext ($predicate $entity))
   (let* (($ctx (SelectFlyContext ($predicate $entity)))
          ((Prior $p0 $k) (ContextPrior $ctx $predicate))
          ($assumptions (ContextAssumptions $ctx)))
      (QueryContext $ctx $p0 $k $assumptions)))

(= (BuildChartFromQuery ($predicate $entity))
   (let (QueryContext $ctx $p0 $k $assumptions) (InferTaskContext ($predicate $entity))
      (LocalChart ($predicate $entity)
         $ctx
         (PersistentEvidence $predicate $ctx)
         $p0
         $k
         $assumptions)))

(= (ECToSTV (EC $pos $neg) $p0 $k)
   (let* (($n (+ $pos $neg))
          ($den (+ $n $k))
          ($s (/ (+ $pos (* $k $p0)) $den))
          ($c (/ $n $den)))
      (STV $s $c)))

(= (RunChart (LocalChart $_query $_ctx $evidence $p0 $k $_assumptions))
   (ECToSTV $evidence $p0 $k))

(= (AnswerQuery $query)
   (RunChart (BuildChartFromQuery $query)))

; ----------------------------------------------------------------------
; Tests: specificity is derived, not hand-picked per entity.
; ----------------------------------------------------------------------

; Tweety is a Penguin. Both Bird and Penguin contexts apply, but Penguin
; has TypeDepth 2 and Bird has TypeDepth 1, so the selector chooses Penguin.
!(test (ContextApplies? (Flies tweety) bird-flight-context) true)
!(test (ContextApplies? (Flies tweety) penguin-flight-context) true)
!(test (BetterContext? penguin-flight-context bird-flight-context Flies) true)
!(test (SelectFlyContext (Flies tweety)) penguin-flight-context)

!(test
   (InferTaskContext (Flies tweety))
   (QueryContext penguin-flight-context
      0.95
      2.0
      (Assumptions antarctic-penguin-study penguin-boundary)))

!(test
   (BuildChartFromQuery (Flies tweety))
   (LocalChart (Flies tweety)
      penguin-flight-context
      (EC 0.0 100.0)
      0.95
      2.0
      (Assumptions antarctic-penguin-study penguin-boundary)))

!(test
   (let (STV $s $c) (AnswerQuery (Flies tweety))
      (and (Between $s 0.018 0.019) (Between $c 0.980 0.981)))
   true)

; Robin is a Sparrow. There is no Sparrow chart in KnownFlyContexts, but
; Sparrow is a subtype of Bird, so the Bird context is selected.
!(test (ContextApplies? (Flies robin) bird-flight-context) true)
!(test (ContextApplies? (Flies robin) penguin-flight-context) false)
!(test (SelectFlyContext (Flies robin)) bird-flight-context)

!(test
   (let (STV $s $c) (AnswerQuery (Flies robin))
      (and (Between $s 0.949 0.951) (Between $c 0.9980 0.9981)))
   true)
