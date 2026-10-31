;; Pure forward/search key shapes and their index hashes.

(datatype ForwardOutputKey (forward-output-key KBContext Statement))

(: forward-type-trigger-key (-[det]-> KB Statement ForwardTriggerKey))
(= (forward-type-trigger-key $kbid $type)
   (if (is-var $type) (fwd_trigger $kbid any)
      (if (is-expr $type)
         (let $head (car-atom $type) (if (is-var $head) (fwd_trigger $kbid any) (fwd_trigger $kbid $head)))
         (fwd_trigger $kbid $type))))

;; A fact premise is indexed under its type-head trigger and its kb-wide
;; wildcard trigger; a CPU premise only under the global wildcard.

(: forward-premise-keys
   (-[det]-> (| Goal (Statement KBContext Proof TV)) (ForwardTriggerKey ForwardTriggerKey)))
(= (forward-premise-keys $prem)
   (case $prem (
      (($type ($kbid $_ctx $_vars) $_prf $_tv)
         (data
            (forward-type-trigger-key (brand KB $kbid) (brand Statement $type))
            (fwd_trigger (brand KB $kbid) any)))
      ($_cpu (data fwd_trigger_any fwd_trigger_any)))))

(: forward-fact-key (-[det]-> (Statement KBContext Proof TV) ForwardOutputKey))
(= (forward-fact-key ($type ($kbid $ctx $vars) $_prf $_tv))
   (forward-output-key (brand KBContext (quote ($kbid $ctx $vars))) $type))

(: forward-output-index-hash (-[det]-> ForwardOutputKey Number))
(= (forward-output-index-hash (forward-output-key $kb $type)) (term_hash (quote ($kb $type))))

(: sk-fact-key (-[det]-> SkFact SkeletonKey))
(= (sk-fact-key ($type $kbctx $_proof $_tv)) (sk-key $type $kbctx))
