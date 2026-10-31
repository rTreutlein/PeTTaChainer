;; Raw input generations, dirty keys and root-cap cache entries.
(: sk-input-epoch (-[det]-> SkeletonKey Number))
(= (sk-input-epoch $key)
   (let $kb (case $key (
           ((sk-key $_type ($kbid $_ctx $_vars)) $kbid)
           (($_aggregate $args) (brand KB (car-atom $args)))))
      (chainer-first-or 0 (collapse (once (match &ctx_sk_input_epoch ($kb $epoch) $epoch))))))

(: sk-clear-root-cap! (-[det]-> Number SkeletonKey Atom))
(= (sk-clear-root-cap! $hash $key)
   (let $_cleared (collapse (match &ctx_sk_root_exhausted ($hash $stored $cap)
            (if (=alpha $stored $key)
               (context-remove! &sk_root_exhausted ($hash $stored $cap)) (empty))))
      ()))

;; Claim state: -1 outside a claim, 0/1 prepaid row credits, -2 exhausted.
;; The pass's cutset depth is 64 outside a paid pass; sk_claim_cut is 1 once
;; a nested conditioning used its approximation (see sk-deepen).
!(change-state! sk_claim_state -1)
!(change-state! sk_claim_depth 64)
!(change-state! sk_claim_cut 0)

;; A key changed again before the evaluation took it is recorded once: each
;; record schedules every reader of the key.
(: sk-dirty! (-[det]-> SkeletonKey Atom))
(= (sk-dirty! $key)
   (let $hash (index-hash $key)
      (if (== (collapse (once (match &ctx_sk_dirty ($hash $stored) (if (=alpha $stored $key) true (empty))))) ())
         (let $_row (context-add! &sk_dirty ($hash $key)) ())
         ())))

;; A deferred branch read holds its consumer only until that exact read is
;; settled. Keep ordinary stale-input debt separate: branch settlement cannot
;; discharge it.
(datatype SkeletonHold sk-stale-input (sk-branch-hold Number SkeletonKey Number (List Number)))

