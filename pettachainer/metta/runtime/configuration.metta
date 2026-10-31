(: set-rule-change-hazard (-[det]-> KB Number Bool))
(= (set-rule-change-hazard $kb $hazard)
   (let* (($_old (remove-data-rows! &rule_change_hazard (quote ($kb $_stored))))
          ($_new (add-atom &rule_change_hazard ($kb $hazard)))
          ($_changed (hazards-changed!)))
      (> $hazard 0.0)))

;; --- Base-rate API ----------------------------------------------------------

;; Setting or clearing a user base rate changes the folds over its pattern,
;; which recompute with their readers at the next evaluation, and adds or
;; withdraws the positive-only rows reading it. A rate is set on its
;; pattern's canonical key: one on (Not X) is the complement's on X.
(: set-base-rate (-[det]-> KB Statement TV (List $none)))
(= (set-base-rate $kbid $statement $rate)
   (let* ((($pattern $odd) (canon (brand Statement (member-canon $statement))))
          ($_valid (validate-base-rate! $statement (conjunct-parts (rate-children $pattern)) $rate))
          ($tv (case (data $odd $rate) (((true (STV $s $c)) (STV (- 1.0 $s) $c)) ($_even $rate))))
          ($_input (sk-input-changed! $kbid))
          ($_new (ledger-set-base-rate! $kbid $pattern $tv))
          ($_gated (prior-gated-rate-changed! $kbid $pattern)))
      (base-rate-readers-changed! $kbid $pattern)))

(: clear-base-rate (-[det]-> KB Statement (List $none)))
(= (clear-base-rate $kbid $statement)
   (let* ((($pattern $_odd) (canon (brand Statement (member-canon $statement))))
          ($_old (base-rate-cache-remove! $kbid $pattern))
          ($_input (sk-input-changed! $kbid))
          ($_gated (prior-gated-rate-changed! $kbid $pattern)))
      (base-rate-readers-changed! $kbid $pattern)))
