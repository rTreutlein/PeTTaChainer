;; Ingestion notifications coordinate the catalog, dormancy and raw journals.
(: sk-input-changed! (-[det]-> KB Atom))
(= (sk-input-changed! $kb)
   (let* (($_catalog (source-catalog-changed! $kb))
          ($epoch (next-search-id sk_input_id))
          ($_old (context-remove! &sk_input_epoch ($kb $_epoch)))
          ($_new (context-add! &sk_input_epoch ($kb $epoch)))) ()))

;; --- Journal ------------------------------------------------------------------

;; Nothing has been expanded before the first query, so bulk loading journals
;; nothing. A new rule can also give a dormant rule's premise support, and a
;; new fact one whose search found no fact of its statement: those rules are
;; started again on the nodes already expanded (docs/metta/dormant_rules.md).
;; A forward run's copy of a derived value is no support and wakes nothing.
;; A query's own rule leaves with the query, so it wakes, as a fact does, only
;; the dormant rules whose search lacked its conclusion: dropping every
;; verdict would make each query judge every rule again.
(: sk-pend-rule! (-[det]-> Number Atom))
(= (sk-pend-rule! $id) (let $_row (add-atom &sk_pending_rules (sk-pending-rule $id)) ()))

(: sk-note-rule! (-[det]-> Number (Statement KBContext Proof TV) Atom))
(= (sk-note-rule! $id ($type $kbctx $_proof $_tv))
   (let* (($permanent (< $id 1000000000))
          ($_input (if $permanent (sk-input-changed! (brand KB (car-atom $kbctx))) ()))
          ($woken (if $permanent (rule-dormancy-reset!) (rule-dormancy-wake! $type))))
      (if (space-row-present? &sk_expanded (quote ($_hash $_pattern)))
         (foreach-flat sk-pend-rule! (cons $id $woken))
         ())))

(: sk-wake-dormant! (-[det]-> Statement Bool Atom))
(= (sk-wake-dormant! $type $expanded)
   (let $woken (rule-dormancy-wake! $type)
      (if $expanded (foreach-flat sk-pend-rule! (the (List Number) $woken)) ())))

(: sk-note-fact! (-[det]-> Statement KBContext Atom))
(= (sk-note-fact! $type $kbctx)
   (let* (($key (sk-key $type $kbctx))
          ($_input (sk-input-changed! (brand KB (car-atom $kbctx))))
          ($_cap-cleared (sk-clear-root-cap! (index-hash $key) $key))
          ($_retired (sk-retire-known! $type $kbctx))
          ($expanded (space-row-present? &sk_expanded (quote ($_hash $_pattern))))
          ($_pending
             (if $expanded
                (let $_pending-row (add-atom &sk_pending_facts (sk-pending-fact $key)) ())
                ()))
          ($_woken (if (== (search-id-value sk_forward_run) 1) () (sk-wake-dormant! $type $expanded)))
          ($_dirty
             ;; A root caches its merged value even when no row has ever
             ;; produced a version. Empty and fact-only merges need the same
             ;; dirty-key refresh as row readers; both existence probes stop
             ;; at their first entry, so ingestion stays constant cost.
             (if (if (space-row-present? &ctx_sk_latest (quote ($_hash $_key $_version))) true
                     (space-row-present? &ctx_sk_merged (quote ($_mhash $_mkey $_deps $_value $_root))))
                (sk-dirty! $key)
                ())))
      ()))


