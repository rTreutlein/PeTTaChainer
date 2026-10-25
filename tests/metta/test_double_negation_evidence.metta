!(import! &self ../../pettachainer/metta/petta_chainer)

;; A negation is an involution for every evidence entry, including raw source
;; names and rule evidence, not just the structured fact-ev representation.
!(test (evidence-entries (evidence-negated (evidence-negated
   (evidence-set (src_event (fact-ev (ev68Kb MAIN Nil) src_event (Event))
      (not-fact-ev (ev68Kb MAIN Nil) other (Other)) (rule-ev ev68Kb src_bridge))))))
   (src_event (fact-ev (ev68Kb MAIN Nil) src_event (Event))
      (not-fact-ev (ev68Kb MAIN Nil) other (Other)) (rule-ev ev68Kb src_bridge)))

!(test (proof-output-evidence (negated (negated (by source premise)))
   (evidence-set ((fact-ev (ev68Kb MAIN Nil) premise (Event)) (rule-ev ev68Kb source))))
   (evidence-set ((fact-ev (ev68Kb MAIN Nil) premise (Event)) (rule-ev ev68Kb source))))

;; Projection positions identify proof structure, never an observation.
!(test (evidence-entries (proof-term-evidence proof-walk-in-kb
   (negated (negated (conjunction (marginal-proj 0 src_event)
      (marginal-proj 1 src_event) (marginal-proj 2 src_event))))))
   (src_event))

;; A live judgment view must keep the observed world fact and applied rule.
!(compileadd ev68Kb (: src_event (StockSplit Split1) (STV 1 0.9)))
!(compileadd ev68Kb (: src_bridge (Implication
   (And (StockSplit $e) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9)))
!(let* (((compiled-query $goal $adds) (mm2compileQuery ev68Kb
           (: $p (Implication (Implemented Split1) (Not (Dilutes Split1))) $tv)))
        ($_injected (collapse (once (inject-compiled-adds $adds))))
        ($_answers (chainer 300 (typed-runtime-premise $goal)))
        (($type $scope $_proof $_tv) $goal)
        ((sk-val ($_result-type $_result-scope (proof-ref $pid) $_result-tv) $ev $_deps) (sk-value (sk-key (brand Statement $type) (brand KBContext $scope)) sk-any-filter ()))
        ($entries (evidence-entries $ev))
        ($same-evidence (== $ev (proof-ref-evidence $pid)))
        ($_cleared (clear-temp-query-adds)))
   (test (data $same-evidence $entries) (true ((fact-ev (ev68Kb MAIN Nil) src_event (StockSplit Split1)) (rule-ev ev68Kb src_bridge)))))

;; The same bridge reads a projection of a compound world observation. Its
;; evidence is the observation, never marginal-proj positions 0, 1, or 2.
!(compileadd ev68CompoundKb (: src_event (And (AnnouncedBy Split1 Apple)
   (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 0.9)))
!(compileadd ev68CompoundKb (: src_bridge (Implication
   (And (Member $e StockSplit) (Implemented $e)) (Not (Dilutes $e))) (STV 1 0.9)))
!(let* (((compiled-query $goal $adds) (mm2compileQuery ev68CompoundKb
           (: $p (Implication (Implemented Split1) (Not (Dilutes Split1))) $tv)))
        ($_injected (collapse (once (inject-compiled-adds $adds))))
        ($_answers (chainer 300 (typed-runtime-premise $goal)))
        (($type $scope $_proof $_tv) $goal)
        ((sk-val ($_result-type $_result-scope (proof-ref $pid) $_result-tv) $ev $_deps) (sk-value (sk-key (brand Statement $type) (brand KBContext $scope)) sk-any-filter ()))
        ($entries (evidence-entries $ev))
        ($same-evidence (== $ev (proof-ref-evidence $pid)))
        ($_cleared (clear-temp-query-adds)))
   (test (data $same-evidence $entries) (true ((fact-ev (ev68CompoundKb MAIN Nil) src_event
      (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (StockSplit Split1)))
      (rule-ev ev68CompoundKb src_bridge)))))

;; A stated conditional and both double-negated applications are one source.
;; Revision with those applications used to inflate confidence to 0.870943.
!(compileadd ev68ExplicitKb (: src_event (And (AnnouncedBy Split1 Apple)
   (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 0.9)))
!(compileadd ev68ExplicitKb (: src_conditional
   (Implication (Implemented Split1) (Not (Dilutes Split1))) (STV 1 0.9)))
!(test (let (: $_proof $_statement $tv)
   (query 300 ev68ExplicitKb (: $p (Exists ($e) (And
      (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit)
      (Implication (Implemented $e) (Not (Dilutes $e))))) $value)) $tv)
   (STV 1 0.8181611546663349))
!(test (let (: $_proof $_statement $tv)
   (query 300 ev68ExplicitKb (: $p (Exists ($e) (And
      (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit)
      (Implication (Implemented $e) (Not (Dilutes $e))))) $value)) $tv)
   (STV 1 0.8181611546663349))
