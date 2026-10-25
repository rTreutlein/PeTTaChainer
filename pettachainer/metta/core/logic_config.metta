!(bind! &logic_config (new-space))

(: LogicName Type)
(: PLN LogicName)

(: CompoundPremiseMode Type)
(: All CompoundPremiseMode)
(: Any CompoundPremiseMode)

(: CompoundOutputMode Type)
(: ProjectAll CompoundOutputMode)
(: NoProjection CompoundOutputMode)

(: CompoundSettlingConfig Type)
(: compound-settling (-[det]-> $head STVType CompoundSettlingConfig))

(: RuleForm Type)
(: BidirectionalImplication RuleForm)

(: LogicNameConfig Type)
(: logic-name (-[det]-> LogicName LogicNameConfig))
(: CompoundPremiseConfig Type)
(: compound-premise-mode (-[det]-> $head CompoundPremiseMode CompoundPremiseConfig))
(: CompoundOutputConfig Type)
(: compound-output-mode (-[det]-> $head CompoundOutputMode CompoundOutputConfig))
(: RuleFormConfig Type)
(: rule-form (-[det]-> $head RuleForm RuleFormConfig))

(: clear-logic-config (-[det]-> (List Bool)))
(= (clear-logic-config) (remove-all-atoms &logic_config))

(: set-logic-name (-[det]-> LogicName Bool))
(= (set-logic-name $logic) (add-atom &logic_config (logic-name $logic)))

(: set-compound-connective (-[det]-> $head CompoundPremiseMode CompoundOutputMode Bool))
(= (set-compound-connective $head $premise-mode $output-mode)
   (let $_premise-mode
      (add-atom &logic_config (compound-premise-mode $head $premise-mode))
      (add-atom &logic_config (compound-output-mode $head $output-mode))))

(: set-compound-mode (-[det]-> $head CompoundPremiseMode Bool))
(= (set-compound-mode $head $mode) (set-compound-connective $head $mode ProjectAll))

;; A part of an All-mode compound known with certainty at `$value` settles the
;; compound to `$value` without its other parts: (STV 1.0 1.0) for Or, whose
;; certain-true disjunct makes it true, (STV 0.0 1.0) for And.
(: set-compound-settling (-[det]-> $head STVType Bool))
(= (set-compound-settling $head $value) (add-atom &logic_config (compound-settling $head $value)))

(: set-bidirectional-implication-form (-[det]-> $head Bool))
(= (set-bidirectional-implication-form $head)
   (add-atom &logic_config (rule-form $head BidirectionalImplication)))

(: current-logic (-[det]-> LogicName))
(= (current-logic)
   (let $matches (collapse (match &logic_config (logic-name $logic) $logic))
      (if (== $matches ()) PLN (car-atom $matches))))

(: compound-connective? (-[det]-> $head Bool))
(= (compound-connective? $head)
   (not (== (collapse (match &logic_config (compound-premise-mode $head $_mode) true)) ())))

(: configured-compound-premise-mode (-[det]-> $head CompoundPremiseMode))
(= (configured-compound-premise-mode $head)
   (let $matches (collapse (match &logic_config (compound-premise-mode $head $mode) $mode))
      (if (== $matches ()) All (car-atom $matches))))

(: configured-compound-output-mode (-[det]-> $head CompoundOutputMode))
(= (configured-compound-output-mode $head)
   (let $matches (collapse (match &logic_config (compound-output-mode $head $mode) $mode))
      (if (== $matches ()) NoProjection (car-atom $matches))))

(: bidirectional-implication-form? (-[det]-> $head Bool))
(= (bidirectional-implication-form? $head)
   (not (== (collapse (match &logic_config (rule-form $head BidirectionalImplication) true)) ())))

(: mark-logic-rule (-[det]-> $name Bool))
(= (mark-logic-rule $name) (add-atom &logic_config (logic-rule $name)))

(: logic-rule? (-[det]-> $name Bool))
(= (logic-rule? $name) (not (== (collapse (match &logic_config (logic-rule $name) true)) ())))

;; A "specializing" predicate is one whose facts the compiler should resolve at
;; add-time: a rule premise headed by such a predicate (e.g. (Symmetric $r)) is
;; ground against the stored facts, emitting one concrete-headed rule instance
;; per matching fact instead of a single rule with a variable conclusion head.
(: set-specializing-predicate (-[det]-> $head Bool))
(= (set-specializing-predicate $head)
   (let $_declared (declared-head! $head) (add-atom &logic_config (specializing-predicate $head))))

(: specializing-predicate? (-[det]-> $head Bool))
(= (specializing-predicate? $head)
   (not (== (collapse (match &logic_config (specializing-predicate $head) true)) ())))

!(clear-logic-config)
!(set-logic-name PLN)
!(set-compound-connective And All ProjectAll)
!(set-compound-connective Or All ProjectAll)
!(set-compound-settling And (STV 0.0 1.0))
!(set-compound-settling Or (STV 1.0 1.0))
!(set-compound-connective LikelierThan All NoProjection)
!(set-bidirectional-implication-form BiImplication)
