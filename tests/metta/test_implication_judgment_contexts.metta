!(import! &self ../../pettachainer/metta/petta_chainer)

;; A legitimate hypothetical proof reads the fixed Recorded R fact while
;; Gate $x is assumed for an open individual. The advanced runtime rule
;; explicitly reads the fixed source in MAIN; its Gate premise follows the
;; hypothetical individual. No negated assumption is read.
;; Metadata and the hypothetical outcome share Recorded R; conditioning must
;; count its 0.6 strength once, giving 0.6 * 0.8 = 0.48, not 0.288.
!(compileadd hypoSharedKb (: source (Recorded R) (STV 0.6 0.9)))
!(compileadd hypoSharedKb (: (no_inverse meta)
   (Implication (Recorded R) (Meta R)) (CTV (STV 1 1) (STV 0 1))))
!(add-to-kb (rules
   ((((Gate $x) (hypoSharedKb MAIN Nil) $gate $gtv)
     ((Recorded R) (hypoSharedKb MAIN Nil) $source $stv)
     (CPU AndFormula ($gtv $stv) $atv)
     (CPU CTVModusPonensFormula ($atv (CTV (STV 0.8 1) (STV 0 1))) $tv))
    |- ((Outcome $x) (hypoSharedKb $ctx $vars) (by outcome (conjunction $gate $source)) $tv))))
!(test (collapse (let
   (: (conditioned source $when-true $when-false) $type $answer-tv)
   (query 300 hypoSharedKb (: $q (And (Meta R) (Implication (Gate $x) (Outcome $x))) $tv)) $answer-tv))
   ((STV 0.48 0.935982976832851)))
!(test (let (: $p $type (STV $s $c))
   (query 300 hypoSharedKb (: $q (And (Implication (Gate $x) (Outcome $x)) (Meta R)) $tv)) $s)
   0.48)


;; This legitimate negative-source variant also works without a special
;; missing-value fallback for conditional proof constructors.
;; Recorded R is independent of Gate $x, so reading its negation from the
;; main KB is legitimate: this is NOT the defective Not Gate assumption read.
;; Both proofs use Not Recorded R. Given Recorded=true they give 0; given
;; Recorded=false they give 1 * 0.8. Count its 0.4 absence probability once.
!(compileadd hypoNegSharedKb (: source (Recorded R) (STV 0.6 0.9)))
!(compileadd hypoNegSharedKb (: (no_inverse meta)
   (Implication (Not (Recorded R)) (Meta R)) (CTV (STV 1 1) (STV 0 1))))
!(compileadd hypoNegSharedKb (: (no_inverse outcome)
   (Implication (And (Gate $x) (Not (Recorded R))) (Outcome $x))
   (CTV (STV 0.8 1) (STV 0 1))))
!(test (let (: (conditioned source $when-true $when-false) $type (STV $s $c))
   (query 300 hypoNegSharedKb (: $q (And (Meta R) (Implication (Gate $x) (Outcome $x))) $tv)) $s)
   0.32000000000000006)
!(test (let (: (conditioned source $when-true $when-false) $type (STV $s $c))
   (query 300 hypoNegSharedKb (: $q (And (Implication (Gate $x) (Outcome $x)) (Meta R)) $tv)) $s)
   0.32000000000000006)

;; An explicitly STV-typed implication premise in an advanced runtime rule
;; reads the positive judgment at its ordinary key, even before a public
;; implication query has installed a scaffold. CTV premises stay full reads.
!(compileadd typedPremKb (: r (Implication (G) (Y))
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
!(add-to-kb (rules
   ((((Implication (G) (Y)) (typedPremKb MAIN Nil) $p (STV $s $c)))
    |- ((Result) (typedPremKb MAIN Nil) (typed-read $p) (STV $s $c)))))
!(test (let (: $p $type (STV $s $c))
   (query 300 typedPremKb (: $q (Result) $tv)) $s) 0.8)

;; Use explicit internal rule storage here: computing an unsupported negative
;; branch is a separate limitation, not part of this premise-routing check.
!(let $fact (quote ((Implication (G) (Y)) (storedCtvPremKb MAIN Nil) stored
   (CTV (STV 0.8 0.9) (STV 0.2 0.9))))
   (add-to-kb (brand RuntimeAddition $fact)))
!(add-to-kb (rules
   ((((Implication (G) (Y)) (storedCtvPremKb MAIN Nil) $p (CTV $_pos (STV $s $c))))
    |- ((NegativeRead) (storedCtvPremKb MAIN Nil) (ctv-read $p) (STV $s $c)))))
!(test (let (: $p $type (STV $s $c))
   (query 300 storedCtvPremKb (: $q (NegativeRead) $tv)) $s) 0.2)
!(add-to-kb (rules
   ((((Implication (G) (Y)) (missingTypedPremKb MAIN Nil) $p (STV $s $c)))
    |- ((Result) (missingTypedPremKb MAIN Nil) (typed-read $p) (STV $s $c)))))
!(test (collapse (query 300 missingTypedPremKb (: $p (Result) $tv))) ())

;; Already-compiled statements can enter through the public low-level API,
;; without source compilation. Their positive source is still available: an
;; STV directly and a CTV through its positive read policy.
!(add-to-kb (brand RuntimeAddition (quote
   ((Implication (DirectGate) (DirectResult)) (directCtvJudgmentKb MAIN Nil)
      direct-ctv (CTV (STV 0.8 0.9) (STV 0.2 0.9))))))
!(test (collapse (query 1 directCtvJudgmentKb
   (: $p (Implication (DirectGate) (DirectResult)) $tv)))
   ((: direct-ctv (Implication (DirectGate) (DirectResult)) (STV 0.8 0.9))))
!(add-to-kb (brand RuntimeAddition (quote
   ((Implication (DirectGate) (DirectResult)) (directStvJudgmentKb MAIN Nil)
      direct-stv (STV 0.6 0.7)))))
!(test (collapse (query 0 directStvJudgmentKb
   (: $p (Implication (DirectGate) (DirectResult)) $tv)))
   ((: direct-stv (Implication (DirectGate) (DirectResult)) (STV 0.6 0.7))))

;; Repeating the same CTV source preserves its immutable proof identity. The
;; positive branch is a read of that source, not a second stored source TV.
!(compileadd repeatedCtvJudgmentKb (: repeated (Implication (Gate) (Result))
   (CTV (STV 0.8 0.9) (STV 0.2 0.7))))
!(compileadd repeatedCtvJudgmentKb (: repeated (Implication (Gate) (Result))
   (CTV (STV 0.8 0.9) (STV 0.2 0.7))))
!(test (collapse (query 0 repeatedCtvJudgmentKb
   (: $p (Implication (Gate) (Result)) $tv)))
   ((: repeated (Implication (Gate) (Result)) (STV 0.8 0.9))))
!(test (collapse (query 0 repeatedCtvJudgmentKb
   (: $p (Implication (Not (Gate)) (Result)) $tv)))
   ((: repeated (Implication (Not (Gate)) (Result)) (STV 0.2 0.7))))
