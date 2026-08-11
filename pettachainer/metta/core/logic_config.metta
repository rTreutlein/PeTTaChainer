!(bind! &logic_config (new-space))

(: LogicName Type)
(: PLN LogicName)

(: CompoundPremiseMode Type)
(: All CompoundPremiseMode)
(: Any CompoundPremiseMode)

(: CompoundOutputMode Type)
(: ProjectAll CompoundOutputMode)
(: NoProjection CompoundOutputMode)

(: RuleForm Type)
(: BidirectionalImplication RuleForm)

(: LogicNameConfig Type)
(: logic-name (-[det]-> LogicName LogicNameConfig))
(: CompoundConnectiveConfig Type)
(: compound-connective (-[det]-> $head CompoundConnectiveConfig))
(: CompoundPremiseConfig Type)
(: compound-premise-mode
   (-[det]-> $head CompoundPremiseMode CompoundPremiseConfig))
(: CompoundOutputConfig Type)
(: compound-output-mode
   (-[det]-> $head CompoundOutputMode CompoundOutputConfig))
(: RuleFormConfig Type)
(: rule-form (-[det]-> $head RuleForm RuleFormConfig))

(: clear-logic-config (-[det]-> (List Bool)))
(= (clear-logic-config)
   (remove-all-atoms &logic_config))

(: set-logic-name (-[det]-> LogicName Bool))
(= (set-logic-name $logic)
   (add-atom &logic_config (logic-name $logic)))

(: set-compound-connective
   (-[det]-> $head CompoundPremiseMode CompoundOutputMode Bool))
(= (set-compound-connective $head $premise-mode $output-mode)
   (let*
      (($_connective (add-atom &logic_config (compound-connective $head)))
        ($_premise-mode (add-atom &logic_config (compound-premise-mode $head $premise-mode))))
      (add-atom &logic_config (compound-output-mode $head $output-mode))))

(: set-compound-mode (-[det]-> $head CompoundPremiseMode Bool))
(= (set-compound-mode $head $mode)
   (set-compound-connective $head $mode ProjectAll))

(: set-bidirectional-implication-form (-[det]-> $head Bool))
(= (set-bidirectional-implication-form $head)
   (add-atom &logic_config (rule-form $head BidirectionalImplication)))

(: current-logic (-[det]-> LogicName))
(= (current-logic)
   (let $matches (collapse (match &logic_config (logic-name $logic) $logic))
      (if (== $matches ()) PLN (car-atom $matches))))

(: compound-connective? (-[det]-> $head Bool))
(= (compound-connective? $head)
   (let $matches (collapse (match &logic_config (compound-connective $head) true))
      (not (== $matches ()))))

(: configured-compound-premise-mode
   (-[det]-> $head CompoundPremiseMode))
(= (configured-compound-premise-mode $head)
   (let $matches (collapse (match &logic_config (compound-premise-mode $head $mode) $mode))
      (if (== $matches ()) All (car-atom $matches))))

(: configured-compound-output-mode
   (-[det]-> $head CompoundOutputMode))
(= (configured-compound-output-mode $head)
   (let $matches (collapse (match &logic_config (compound-output-mode $head $mode) $mode))
      (if (== $matches ()) NoProjection (car-atom $matches))))

(: bidirectional-implication-form? (-[det]-> $head Bool))
(= (bidirectional-implication-form? $head)
   (let $matches (collapse (match &logic_config (rule-form $head BidirectionalImplication) true))
      (not (== $matches ()))))

(: mark-logic-rule (-[det]-> $name Bool))
(= (mark-logic-rule $name)
   (add-atom &logic_config (logic-rule $name)))

(: logic-rule? (-[det]-> $name Bool))
(= (logic-rule? $name)
   (let $matches (collapse (match &logic_config (logic-rule $name) true))
      (not (== $matches ()))))

;; A "specializing" predicate is one whose facts the compiler should resolve at
;; add-time: a rule premise headed by such a predicate (e.g. (Symmetric $r)) is
;; ground against the stored facts, emitting one concrete-headed rule instance
;; per matching fact instead of a single rule with a variable conclusion head.
(: set-specializing-predicate (-[det]-> $head Bool))
(= (set-specializing-predicate $head)
   (add-atom &logic_config (specializing-predicate $head)))

(: specializing-predicate? (-[det]-> $head Bool))
(= (specializing-predicate? $head)
   (let $matches (collapse (match &logic_config (specializing-predicate $head) true))
      (not (== $matches ()))))

!(clear-logic-config)
!(set-logic-name PLN)
!(set-compound-connective And All ProjectAll)
!(set-compound-connective Or All ProjectAll)
!(set-compound-connective LikelierThan All NoProjection)
!(set-bidirectional-implication-form BiImplication)
