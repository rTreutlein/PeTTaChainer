!(import! &self ../../pettachainer/metta/petta_chainer)

(: descriptor-fact
   (-[det]-> Statement (| Atom Expression) $tv
      (Statement KBContext Proof TV)))
(= (descriptor-fact $statement $proof $tv)
   (assemble-runtime-fact $statement
      (brand KBContext (descriptorAudit MAIN Nil))
      (brand Proof $proof) (the TV $tv)))

;; A replaced premise keeps derivation identity across alpha-renaming, CPU
;; evaluations, and adjacent repeated output keys. Evidence remains a separate
;; supersession condition; variable sharing must survive every memo copy.
!(test
   (let*
      (($_reset (clear-backward-query-state!))
       ($input-key (brand ProofGoalKey
          (goal-key (descriptor-fact (DescriptorInput) input (STV 1.0 0.8)))))
       ($key (brand ProofGoalKey
          (goal-key (descriptor-fact (DescriptorTarget) target (STV 1.0 0.8)))))
       ($old-input (once (store-proof-record! $input-key
          (proof-candidate (leaf (descriptor-fact (DescriptorInput) old (STV 1.0 0.8)))
             0.8 () ()))))
       ($new-input (once (store-proof-record! $input-key
          (proof-candidate (leaf (descriptor-fact (DescriptorInput) new (STV 1.0 0.9)))
             0.9 () ()))))
       ($cpu (once (store-proof-record! $input-key
          (proof-candidate (leaf (CPU NotFormula ((STV 0.0 0.8)) (STV 1.0 0.8)))
             0.8 () ()))))
       ($evidence (cons (rule-ev descriptorAudit shared) ()))
       ($old (once (store-proof-record! $key
          (proof-candidate
             (rule (descriptor-fact (DescriptorTarget)
                (by (descriptor $x $x) (proof-ref $old-input)) (STV 1.0 0.8)))
             0.8 $evidence (cons $old-input ())))))
       ($new-children (cons $new-input (cons $cpu (cons $old-input ()))))
       ($new (once (store-proof-record! $key
          (proof-candidate
             (rule (descriptor-fact (DescriptorTarget)
                (by (descriptor $y $y) (proof-ref $new-input)) (STV 1.0 0.9)))
             0.9 $evidence $new-children))))
       ($different-sharing (once (store-proof-record! $key
          (proof-candidate
             (rule (descriptor-fact (DescriptorTarget)
                (by (descriptor $u $v) (proof-ref $new-input)) (STV 1.0 0.9)))
             0.9 $evidence $new-children))))
       ($disjoint (once (store-proof-record! $key
          (proof-candidate
             (rule (descriptor-fact (DescriptorTarget)
                (by (descriptor $z $z) (proof-ref $new-input)) (STV 1.0 0.9)))
             0.9 (cons (rule-ev descriptorAudit other) ()) $new-children))))
       ($replaced (== (prefer-compatible-derivation-step $key (cons $old ()) $new)
          (cons $new ())))
       ($independent (== (prefer-compatible-derivation-step $key (cons $old ()) $disjoint)
          (cons $old (cons $disjoint ()))))
       ($hash (proof-derivation-hash $key $old))
       ($_different-hash (proof-derivation-hash $key $different-sharing))
       ;; Force the equal-hash branch using the old hash as the argument,
       ;; without mutating stored proofs or redefining the actual hasher.
       ($collision-safe (==
          (retain-compatible-derivation-step $key $hash $different-sharing
             $evidence $new-children () $old)
          (cons $old ())))
       ($_bind-copy (once (match &proof_derivation_descriptor
          ($old (by (descriptor bound bound) ref) $_keys) ())))
       ($copy-safe (once (match &proof_derivation_descriptor
          ($old $shape $_keys2)
          (=alpha $shape (by (descriptor $q $q) ref)))))
       ($_clear-again (clear-backward-query-state!))
       ($empty-after-reset (== (collapse (get-atoms &proof_derivation_descriptor)) ()))
       ($hash-empty-after-reset (== (collapse (get-atoms &proof_derivation_hash)) ()))
       ($late-history (==
          (prefer-compatible-derivation-step $key (cons $old ()) $new)
          (cons $new ())))
       ($same-hash (== $hash (proof-derivation-hash $key $old))))
      ($replaced $independent $collision-safe $copy-safe
       (is-var $x) (is-var $y) (is-var $u) (is-var $v)
       $empty-after-reset $hash-empty-after-reset $late-history $same-hash))
   (true true true true true true true true true true true true))
