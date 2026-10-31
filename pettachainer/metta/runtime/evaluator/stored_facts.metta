;; A statement counts once, with its stored facts merged.
(: fa-seed-statement
   (-[det]-> KBContext (List (Statement KBContext Proof TV)) Statement (List (Statement KBContext Proof TV))))
(= (fa-seed-statement $kbctx $acc $statement)
   (case (stored-statement-candidate $statement $kbctx false) (
      ((forward-derived ($type $ctx $proof $tv) $ev)
         (cons (assemble-runtime-fact $type $ctx (fact-source $ev $proof) $tv) $acc))
      (no-forward-output-candidate $acc))))

;; A base rate a reader finds without an estimate is seeded: its aggregate
;; registers if it is new, and the facts already in the KB are counted as the
;; forward chainer counts them. Counting is per statement, so seeding an aggregate
;; the forward chainer already fed counts nothing twice. From then on forward
;; chaining keeps the estimate current as it processes facts. Only fold
;; premises with a forward subscription (at most one each) can be seeded.
(: forward-seed-fold! (-[semidet]-> (| Goal (Statement KBContext Proof TV)) Bool))
(= (forward-seed-fold! $premise)
   (case (fa-premise-subscriptions $premise) (
      ((cons (fa-subscription $identity (forward-base-rate-descriptor $kb $pattern) $triggers) $_none)
         (let* (($descriptor (forward-base-rate-descriptor $kb $pattern))
                ($_registered (fa-register! $identity $descriptor $triggers))
                ($kbctx (make-kb-context $kb MAIN Nil))
                ($type (copy_term $pattern))
                ($facts (fold-flat (fa-seed-statement $kbctx) ()
                   (list_to_set (collapse (match &kb ($type $kbctx $_proof $_tv) (brand Statement $type))))))
                ($_counted
                   (case (collapse (fa-id $identity)) (
                      ((cons $id $_rest) (collapse (let $fact (superpose $facts) (fa-update! $fact $id (copy_term $descriptor)))))
                      (() ())))))
            true))
      ($_other false))))


;; A statement's stored facts merged into one candidate: what the facts say
;; about the statement together. Materialized facts are not stored facts: the
;; skeleton derived them. A forward run's copy of a key's value is counted only
;; when asked for: a base rate counts stored facts and hears of copies from the
;; run that made them, while a membership read wants the latest value a run
;; reported. A copy is looked up under the key of the row matched, which an open
;; statement only finds once the match binds it.
(: stored-candidate-step
   (-[det]-> (| ForwardDerived NoForwardOutputCandidate) (Statement KBContext Proof TV) ForwardDerived))
(= (stored-candidate-step $acc ($type $kb $proof $tv))
   (let* (($fact (data $type $kb $proof $tv))
          ($ev (evidence-set (cons (fact-evidence-entry $kb $proof $type) ()))))
      (case $acc (
         (no-forward-output-candidate (forward-derived $fact $ev))
         ((forward-derived $current $current-ev)
            (case (collapse (once (sk-merge-facts false () $current $current-ev 0 $fact $ev 0))) (
               ((cons (sk-paired (sk-val $merged $merged-ev $_deps)) ()) (forward-derived $merged $merged-ev))
               ((cons (sk-overlap $_shared $_deps (sk-val $merged $merged-ev $_fdeps)) ()) (forward-derived $merged $merged-ev))
               ($_none (forward-derived $current $current-ev)))))))))
(: stored-statement-candidate
   (-[det]-> Statement KBContext Bool (| ForwardDerived NoForwardOutputCandidate)))
(= (stored-statement-candidate $type $kb $copies)
   (fold-flat stored-candidate-step no-forward-output-candidate
      (let $facts (kb-facts $type $kb)
         (collapse (let ($ftype $fkb $_proof $_tv) (superpose $facts)
            (let $fact (data $ftype $fkb $_proof $_tv)
               (if (materialized-forward-fact? $fact) (empty)
                  (if $copies $fact
                     (if (space-row-present? &sk_forward_stored ((index-hash (sk-key $ftype $fkb)) $_key $fact $_ev $_deps)) (empty) $fact)))))))))


;; --- Pending work -------------------------------------------------------------

;; --- Base rates -------------------------------------------------------------

;; A base rate's estimate: a user base rate, or a cached one that an earlier
;; fold computed or forward chaining keeps. A base rate without one is seeded
;; from the facts already known when forward chaining can maintain it.
(: sk-rate-entries (-[semidet]-> $args (List BaseRateEntry)))
(= (sk-rate-entries $args)
   (case (base-rate-aggregate-key $args) (
      ((base-rate-aggregate-key-value $kbid $pattern $mode)
         (let $entries (base-rate-cache-entries-for-mode $kbid $pattern $mode)
            (if (== $entries ())
               (if (forward-seed-fold! (CPU FoldAllCompiled $args $_result))
                  (base-rate-cache-entries-for-mode $kbid $pattern $mode)
                  ())
               $entries)))
      ($_none ()))))
