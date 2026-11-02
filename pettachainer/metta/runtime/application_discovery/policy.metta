;; Pure application read policies. This owner selects no search, evaluation,
;; publication or scheduling operation. Result-proof roles stay live until read.
(: application-read-plan (-[det]-> Number SkFact (List SkPattern) ApplicationInputs))
(= (application-read-plan $id ($type $_scope $proof $_tv) $premises)
   ;; Compiler-marked joins whose premises intentionally share source evidence.
   (let $shared (head-is? $proof total-implication-frontier)
      (application-inputs (derivation-proof? $type $proof) $shared (sk-node-row? $proof)
         (if $shared no-input-entanglement (result-input-entanglement $proof))
         (rule-completion-inputs $id $premises))))
