!(import! &self ../../pettachainer/metta/petta_chainer)

;; #63: mixed world/assumption join. Both the STV and the full evidence-bearing
;; proof are checked; ctx proof is a local assumption, not an observation.
!(compileadd ke63Kb (: src_split (StockSplit Split1) (STV 1 0.9)))
!(compileadd ke63Kb (: src_bridge (Implication (And (StockSplit $e) (Implemented $e)) (PreservesOwnership $e)) (STV 1 0.9)))
!(test (collapse (let (: (conditional-implication (by src_bridge (conjunction src_split (ctx proof $ctx)))) $_statement $tv)
   (query 300 ke63Kb (: $p (Implication (Implemented Split1) (PreservesOwnership Split1)) $value)) $tv))
   ((STV 1.0 0.8570976055283451)))
!(test (collapse (let (: (conditional-implication (by src_bridge (conjunction src_split (ctx proof $ctx)))) $_statement $tv)
   (query 300 ke63Kb (: $p (Implication (Implemented Split1) (PreservesOwnership Split1)) $value)) $tv))
   ((STV 1.0 0.8570976055283451)))
!(test (collapse (query 300 ke63Kb (: $p (Implemented Split1) $tv))) ())
!(test (collapse (query 300 ke63Kb (: $p (PreservesOwnership Split1) $tv))) ())

;; Borrowed observations keep MAIN's evidence identity across the private key.
!(test (let* (($facts (sk-leaf-facts (StockSplit Split1) (ke63Kb 987 Nil) sk-any-filter))
             ((cons $fact ()) $facts))
           (evidence-entries (leaf-evidence-for-result $fact)))
   ((fact-ev (ke63Kb MAIN Nil) src_split (StockSplit Split1))))

;; A derived implication and its application to its assumed antecedent are
;; one source, including certain rules whose evidence set is empty.
!(test (proof-dominates? (by rule source) (conditional-implication (by (by rule source) (ctx proof C)))) true)
!(test (proof-dominates? (by other source) (conditional-implication (by (by rule source) (ctx proof C)))) false)
!(test (proof-dominates? (by rule source) (conditional-implication (by (by rule source) observed))) false)

;; Inspect the live calculated view before query cleanup. Its semantic
;; evidence is exactly the MAIN observation and the source rule; the private
;; assumption occurs in the proof but is not empirical evidence. The MAIN
;; observation's dependency must survive borrowing for conditioning.
!(let* (((compiled-query $goal $adds) (mm2compileQuery ke63Kb (: $p (Implication (Implemented Split1) (PreservesOwnership Split1)) $tv)))
        ($_injected (collapse (once (inject-compiled-adds $adds))))
        ($_answers (chainer 300 (typed-runtime-premise $goal)))
        (($type $scope $_proof $_tv) $goal)
        ((sk-val $_fact $ev $deps) (sk-value (sk-key (brand Statement $type) (brand KBContext $scope)) sk-any-filter ()))
        ($valid (and (== $ev (evidence-set ((fact-ev (ke63Kb MAIN Nil) src_split (StockSplit Split1)) (rule-ev ke63Kb src_bridge))))
                     (deps-has? $deps (index-hash (sk-key (StockSplit Split1) (ke63Kb MAIN Nil))))))
        ($_cleared (clear-temp-query-adds)))
   (test $valid true))

;; A condition in a different knowledge base cannot pin a private leaf.
!(test (sk-pinned-step (sk-key (StockSplit Split1) (otherKe63Kb 987 Nil)) ()
   (sk-given 42 (sk-key (StockSplit Split1) (ke63Kb MAIN Nil)) true)) ())

;; A ground target does not hide other bindings of an auxiliary open reader.
;; Its own observation and negation remain unavailable even below another row.
!(compileadd ke63Targets (: own_target (Target Split1) (STV 0.1 0.9)))
!(compileadd ke63Targets (: other_target (Target Split2) (STV 0.7 0.9)))
!(let* ((($scope $_read $adds)
           (judgment-query-side ke63Targets Nil false (brand Statement (Gate)) (brand Statement (Target Split1))))
        ($_injected (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
        ($own (sk-leaf-facts (Target Split1) (the KBContext $scope) sk-any-filter))
        ($negative (sk-leaf-facts (Not (Target Split1)) (the KBContext $scope) sk-any-filter))
        ($others (sk-leaf-facts (Target $event) (the KBContext $scope) sk-any-filter))
        ((($other-type $_other-scope $_other-proof $_other-tv)) $others)
        ($_cleared (clear-temp-query-adds)))
   (test (data $own $negative $other-type) (() () (Target Split2))))

;; An open target excludes all its ground instances without binding the query.
!(let* (($target (brand Statement (Target $event)))
        (($scope $_read $adds)
           (judgment-query-side ke63Targets Nil false (brand Statement (Gate)) $target))
        ($_injected (collapse (once (inject-compiled-adds (map-flat mm2stmt $adds)))))
        ($facts (sk-leaf-facts (Target Split1) (the KBContext $scope) sk-any-filter))
        ($unbound (is-var $event))
        ($_cleared (clear-temp-query-adds)))
   (test (data $facts $unbound) (() true)))
