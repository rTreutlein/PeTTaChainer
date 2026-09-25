!(import! &self ../../pettachainer/metta/petta_chainer)

;; An instance disappears only within its proof group, regardless of where
;; the general answer occurs. Survivors retain their original order.
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair a a) ctx shared tv)
       ((Pair b c) ctx other tv)
       ((Pair $x $x) ctx shared tv)
       ((Pair d e) ctx shared tv))))
   (((Pair b c) ctx other tv)
    ((Pair $x $x) ctx shared tv)
    ((Pair d e) ctx shared tv)))
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair $x $x) ctx shared tv)
       ((Pair a a) ctx shared tv)
       ((Pair b c) ctx other tv))))
   (((Pair $x $x) ctx shared tv) ((Pair b c) ctx other tv)))

;; Variant answers are retained, including duplicates. A more constrained
;; variable-sharing pattern cannot subsume the unconstrained pattern.
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair $x $y) ctx shared tv)
       ((Pair $a $b) ctx shared tv)
       ((Pair $z $z) ctx shared tv))))
   (((Pair $x $y) ctx shared tv) ((Pair $a $b) ctx shared tv)))
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair a b) ctx shared tv) ((Pair a b) ctx shared tv))))
   (((Pair a b) ctx shared tv) ((Pair a b) ctx shared tv)))

;; Copied nonground proofs are not identical, even when their input variables
;; were shared. Do not bind the input. Each surviving answer is copied
;; independently, preserving sharing within it but not between answers.
!(test
   (let* (($answers (the (List RuntimeResult)
              (((Pair a a) ctx (proof $p) tv)
               ((Pair $x $x) ctx (proof $p) tv))))
          ($kept (prune_answer_instances $answers)))
      ((=alpha $kept (((Pair a a) ctx (proof $a) tv)
                      ((Pair $b $b) ctx (proof $c) tv)))
       (is-var $p) (is-var $x)))
   (true true true))
!(test
   (let* (($answers (the (List RuntimeResult)
              (((Pair $x $y) ctx shared tv)
               ((Pair $z $z) ctx shared tv))))
          ($kept (prune_answer_instances $answers)))
      ((=alpha $kept (((Pair $x $y) ctx shared tv)))
       (is-var $x) (is-var $y) (is-var $z) (== $x $y)))
   (true true true true false))
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair $x $x) ctx first tv) ((Pair $x $x) ctx second tv))))
   (((Pair $a $a) ctx first tv) ((Pair $b $b) ctx second tv)))

;; Preserve the existing result contract: context/TV affect the initial
;; variant check, but do not constrain statement subsumption afterwards.
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair a a) one shared (STV 1 0.8))
       ((Pair $x $x) two shared (STV 1 0.9)))))
   (((Pair $x $x) two shared (STV 1 0.9))))
!(test
   (prune_answer_instances (the (List RuntimeResult)
      (((Pair a b) ctx shared (STV 1 0.8))
       ((Pair a b) ctx shared (STV 1 0.9)))))
   ())

;; Non-fact goals also use RuntimeResult. Leave other shapes alone, and keep
;; the existing four-field CPU result behavior.
!(test (prune_answer_instances (the (List RuntimeResult) ())) ())
!(test
   (prune_answer_instances (the (List RuntimeResult)
      ((CPU f (args) value) (short goal) atom)))
   ((CPU f (args) value) (short goal) atom))
