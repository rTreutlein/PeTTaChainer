!(import! &self ../../pettachainer/metta/petta_chainer)

;; Issue #43: project a consequent conjunct before exporting its nested
;; implication. The first query is cold; repeat it at the same 300-step budget.
!(compileadd projectedKb (: rule
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 1 1)))
!(test (let (: (conditional-implication
      (marginal-proj 1 (by
         (consequent-projection $source $child rule) (conjunction $gate $a)))) $type $tv)
   (query 300 projectedKb (: $p
      (Implication (AcceptSource S) (Implication (A $x) (C $x))) $value))
   $tv)
   (STV 1.0 0.9998000399670116))
!(test (let (: (conditional-implication
      (marginal-proj 1 (by
         (consequent-projection $source $child rule) (conjunction $gate $a)))) $type $tv)
   (query 300 projectedKb (: $p
      (Implication (AcceptSource S) (Implication (A $x) (C $x))) $value))
   $tv)
   (STV 1.0 0.9998000399670116))
;; A bound instance also works; $x remains the inner rule's variable.
!(test (let (: (conditional-implication $proof) $type $tv)
   (query 300 projectedKb (: $p
      (Implication (AcceptSource S) (Implication (A a) (C a))) $value)) $tv)
   (STV 1.0 0.9998000399670116))

;; Both controls from the report still compose with ordinary And elimination.
!(compileadd unwrappedKb (: rule
   (Implication (AcceptSource S) (Implication (A $x) (And (B $x) (C $x))))
   (STV 1 1)))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 unwrappedKb (: $p
      (Implication (AcceptSource S) (Implication (A $x) (C $x))) $value)) $s) 1.0)
!(compileadd plainProjectionKb (: rule
   (Implication (A $x) (And (B $x) (C $x))) (STV 1 1)))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 plainProjectionKb (: $p (Implication (A $x) (C $x)) $value)) $s) 1.0)

;; The gate cannot be replaced, or dropped from the requested implication.
!(test (collapse (query 300 projectedKb (: $p
   (Implication (AcceptSource T) (Implication (A $x) (C $x))) $tv))) ())
!(test (collapse (query 300 projectedKb (: $p (Implication (A $x) (C $x)) $tv))) ())
!(test (collapse (query 300 projectedKb (: $p (C a) $tv))) ())
!(test (collapse (query 300 projectedKb (: $p (AcceptSource S) $tv))) ())
!(test (kb-facts (brand Statement (C a)) (kbctx projectedKb)) ())
!(test (kb-facts (brand Statement (AcceptSource S)) (kbctx projectedKb)) ())

;; More than one conjunct layer, including a conjunction inside a derived
;; statement, exercises projection/export composition at both boundaries.
!(compileadd deeperProjectionKb (: deep
   (Implication (AcceptSource S)
      (And (Metadata S)
         (And (Reviewed S)
            (Implication (A $x)
               (And (Details $x) (Implication (D $x) (And (B $x) (C $x))))))))
   (STV 1 1)))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 deeperProjectionKb (: $p
      (Implication (AcceptSource S)
         (Implication (A $x) (Implication (D $x) (C $x)))) $value)) $s) 1.0)
!(test (collapse (query 300 deeperProjectionKb (: $p (C a) $tv))) ())

;; Two paths through the same uncertain rule must carry the same evidence,
;; rather than revising two projected rule axioms as independent observations.
!(compileadd overlapProjectionKb (: shared
   (Implication (AcceptSource S)
      (And
         (Implication (A $x) (And (B $x) (C $x)))
         (And (Metadata S) (Implication (A $x) (And (B $x) (C $x))))))
   (STV 0.8 0.6)))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 overlapProjectionKb (: $p
      (Implication (AcceptSource S) (Implication (A $x) (C $x))) $tv))
   (data $s (< $c 0.6))) (0.8 true))
;; A variable an implication conjunct binds is universal, never a Skolem
;; witness, even with no outer variable to depend on (#142): the projected
;; conditional answers at the rule's strength. Skolemised, its key held an
;; empty witness argument list, which crashed the proof walkers.
!(compileadd boundConjunctKb (: r2 (Implication (G) (And (Implication (A $x) (B $x)) (M))) (STV 0.9 0.9)))
!(compileadd boundConjunctKb (: g (G) (STV 1 1)))
!(test (let (: (conditional-implication $_proof) $_type $tv)
   (query 300 boundConjunctKb (: $p (Implication (A $x) (B $x)) $tv)) $tv)
   (STV 0.9 0.8901098893877744))

;; A sibling of a conclusion's implication part is read apart from that part:
;; judged from the same rule, it would divide P(X and M) by itself and make M
;; certain. Only P(X and M) = 0.9 is known, so M keeps the marginal 0.9, as a
;; plain And conclusion does (#142).
!(compileadd projectionSelfKb (: r (Implication (G $x) (And (Implication (A $x) (B $x)) (M $x))) (STV 0.9 0.9)))
!(compileadd projectionSelfKb (: g (G c) (STV 1 1)))
!(test (let (: $_proof $_type $tv) (query 300 projectionSelfKb (: $p (M c) $tv)) $tv) (STV 0.9 0.8901098897087285))
!(compileadd projectionSelfGroundKb (: r (Implication (G) (And (Implication (A) (B)) (M))) (STV 0.9 0.9)))
!(compileadd projectionSelfGroundKb (: g (G) (STV 1 1)))
!(test (let (: $_proof $_type $tv) (query 300 projectionSelfGroundKb (: $p (M) $tv)) $tv) (STV 0.9 0.8901098897087285))
!(compileadd projectionPlainKb (: r (Implication (G) (And (X) (M))) (STV 0.9 0.9)))
!(compileadd projectionPlainKb (: g (G) (STV 1 1)))
!(test (let (: $_proof $_type $tv) (query 300 projectionPlainKb (: $p (M) $tv)) $tv) (STV 0.9 0.8901098897087285))
;; Inspect the live judgment before the ordinary query bracket removes its
;; temporary context, so this checks semantic evidence rather than proof leaves.
!(let* (((compilation-plan (: $ctx $proof $type $tv) $adds)
            (compileQuery overlapProjectionKb (: $p
               (Implication (AcceptSource S) (Implication (A $x) (C $x))) $value)))
         ($_injected (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
         ($_answers (chainer 300 (internalize-proof-structure (: $ctx $proof $type $tv))))
         ((sk-val ($_type $_context $_proof $_tv) $ev $_deps)
            (sk-value (sk-key $type $ctx) sk-any-filter ()))
         ($entries (evidence-entries $ev))
         ($_cleared (clear-temp-query-adds))
         ($_contexts (sk-clear-contexts!)))
   (test $entries ((rule-ev overlapProjectionKb shared))))

;; An explicit CTV projects both branches; the negative source judgment keeps
;; its stated branch instead of inventing an STV complement from populations.
!(compileadd ctvProjectionKb (: ctv-source
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (CTV (STV 0.8 0.6) (STV 0.2 0.5))))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 ctvProjectionKb (: $p
      (Implication (AcceptSource S) (Implication (A $x) (C $x))) $tv))
   (data $s (< $c 0.6))) (0.8 true))
!(test (let (: (conditional-implication $proof) $type (STV $s $c))
   (query 300 ctvProjectionKb (: $p
      (Implication (Not (AcceptSource S)) (Implication (A $x) (C $x))) $tv))
   (data $s (< $c 0.5))) (0.2 true))

;; Withdrawing the actual source retires projected support even after warm reads.
!(withdraw-named-rules! rule)
!(test (collapse (query 300 projectedKb (: $p
   (Implication (AcceptSource S) (Implication (A $x) (C $x))) $tv))) ())

;; Permanent MAIN views must retire too: source truth alone is not enough
;; once a projected application has been cached or materialized.
!(compileadd withdrawnProjectionKb (: g (AcceptSource S) (STV 1 1)))
!(compileadd withdrawnProjectionKb (: a (A a) (STV 1 1)))
!(compileadd withdrawnProjectionKb (: main-projection
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 0.8 0.6)))
!(test (let (: $proof $type (STV $s $c))
   (query-materialize 300 withdrawnProjectionKb (: $p (C a) $tv)) $s) 0.8)
!(withdraw-named-rules! main-projection)
!(test (collapse (query 300 withdrawnProjectionKb (: $p (C a) $tv))) ())
!(test (kb-facts (brand Statement (C a)) (kbctx withdrawnProjectionKb)) ())

;; The same owner survives repeated projection layers before export.
!(compileadd withdrawnDeepKb (: g (AcceptSource S) (STV 1 1)))
!(compileadd withdrawnDeepKb (: a (A a) (STV 1 1)))
!(compileadd withdrawnDeepKb (: deep-projection
   (Implication (AcceptSource S)
      (And (Metadata S)
         (And (Reviewed S) (Implication (A $x) (And (B $x) (C $x))))))
   (STV 0.8 0.6)))
!(test (let (: $proof $type (STV $s $c))
   (query-materialize 300 withdrawnDeepKb (: $p (C a) $tv)) $s) 0.8)
!(withdraw-named-rules! deep-projection)
!(test (collapse (query 300 withdrawnDeepKb (: $p (C a) $tv))) ())
!(test (kb-facts (brand Statement (C a)) (kbctx withdrawnDeepKb)) ())
