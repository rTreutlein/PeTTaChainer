!(bind! &logic_config (new-space))

(= (clear-logic-config)
   (remove-all-atoms &logic_config))

(= (set-logic-name $logic)
   (add-atom &logic_config (logic-name $logic)))

(= (set-compound-connective $head $premise-mode $output-mode)
   (let*
      (($_connective (add-atom &logic_config (compound-connective $head)))
        ($_premise-mode (add-atom &logic_config (compound-premise-mode $head $premise-mode))))
      (add-atom &logic_config (compound-output-mode $head $output-mode))))

(= (set-compound-mode $head $mode)
   (set-compound-connective $head $mode ProjectAll))

(= (set-bidirectional-implication-form $head)
   (add-atom &logic_config (rule-form $head BidirectionalImplication)))

(= (current-logic)
   (let $matches (collapse (match &logic_config (logic-name $logic) $logic))
      (if (== $matches ()) PLN (car-atom $matches))))

(= (compound-connective? $head)
   (let $matches (collapse (match &logic_config (compound-connective $head) true))
      (not (== $matches ()))))

(= (configured-compound-premise-mode $head)
   (let $matches (collapse (match &logic_config (compound-premise-mode $head $mode) $mode))
      (if (== $matches ()) All (car-atom $matches))))

(= (configured-compound-output-mode $head)
   (let $matches (collapse (match &logic_config (compound-output-mode $head $mode) $mode))
      (if (== $matches ()) NoProjection (car-atom $matches))))

(= (bidirectional-implication-form? $head)
   (let $matches (collapse (match &logic_config (rule-form $head BidirectionalImplication) true))
      (not (== $matches ()))))

(= (mark-logic-rule $name)
   (add-atom &logic_config (logic-rule $name)))

(= (logic-rule? $name)
   (let $matches (collapse (match &logic_config (logic-rule $name) true))
      (not (== $matches ()))))

!(clear-logic-config)
!(set-logic-name PLN)
!(set-compound-connective And All ProjectAll)
!(set-compound-connective Or All ProjectAll)
!(set-compound-connective LikelierThan All NoProjection)
!(set-bidirectional-implication-form BiImplication)
