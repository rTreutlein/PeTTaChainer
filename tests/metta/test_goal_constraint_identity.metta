!(import! &self ../../pettachainer/metta/petta_chainer)

!(compileadd constraintKb (: accepted (ConstraintA) (STV 1.0 0.8)))
!(test (query 5 constraintKb (: $proof (ConstraintA) $tv))
   (: accepted (ConstraintA) (STV 1.0 0.8)))

;; Each root must retain its own proof and TV conditions, in either order.
!(test
   (collapse (query-many 0 constraintKb
      ((: accepted (ConstraintA) $tv)
       (: rejected (ConstraintA) $tv))))
   ((query-result 0 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: rejected (ConstraintA) $tv)
       (: accepted (ConstraintA) $tv))))
   ((query-result 1 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: $proof (ConstraintA) (STV 1.0 0.8))
       (: $proof (ConstraintA) (STV 1.0 0.7)))))
   ((query-result 0 (: accepted (ConstraintA) (STV 1.0 0.8)))))
!(test
   (collapse (query-many 0 constraintKb
      ((: $proof (ConstraintA) (STV 1.0 0.7))
       (: $proof (ConstraintA) (STV 1.0 0.8)))))
   ((query-result 1 (: accepted (ConstraintA) (STV 1.0 0.8)))))

;; Variable relationships across statement and proof are constraints too.
!(compileadd constraintKb
   (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))
!(test (query 5 constraintKb (: $proof (ConstraintBinding $x) $tv))
   (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))
!(test
   (collapse (query-many 0 constraintKb
      ((: (origin $x) (ConstraintBinding $x) $tv)
       (: (origin $p) (ConstraintBinding $x) $tv))))
   ((query-result 1 (: (origin a) (ConstraintBinding b) (STV 1.0 0.8)))))



;; Same proposition, different proof requests: both parents must receive the
;; shared source publication. The second attempt to store the same A proof is
;; a duplicate, so waking only the producing goal variant would strand Right.
!(compileadd variantKb (: variant-source (VariantSource) (STV 1.0 1.0)))
!(compileadd variantKb
   (: (no_inverse variant-a-rule)
      (Implication (VariantSource) (VariantA))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd variantKb
   (: (no_inverse variant-left-rule)
      (Implication (VariantA) (VariantLeft))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd variantKb
   (: (no_inverse variant-right-rule)
      (Implication (VariantA) (VariantRight))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(test
   (collapse
      (let (query-result $index (: $proof $type $_tv))
         (query-many 20 variantKb
            ((: (by (no_inverse variant-left-rule)
                   (by (no_inverse variant-a-rule) $source))
                (VariantLeft) $tv)
             (: $proof (VariantRight) $tv)))
         ($index $proof $type)))
   ((0 (by (no_inverse variant-left-rule)
          (by (no_inverse variant-a-rule) variant-source)) (VariantLeft))
    (1 (by (no_inverse variant-right-rule)
          (by (no_inverse variant-a-rule) variant-source)) (VariantRight))))



;; An open proof constructor is a query pattern, not a compiler marker. Testing
;; for a marker must not bind that head, including its shared statement use.
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement
                   (Implication (MarkerInput $head) (MarkerOutput $head)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote ($head $payload)))
                (the TV $tv)))
          ($after (nextctx)))
      ((is-var $head) (is-var $payload) (- $after $before)))
   (true true 3))

;; The exact marker skips its already-installed scaffold without inspecting
;; or instantiating its payload, even when nested variables are shared.
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement
                   (Implication (MarkerInput $shared) (MarkerOutput $shared)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof
                   (total-implication-frontier (quote ($shared $shared))))
                (the TV $tv)))
          ($after (nextctx)))
      ((is-var $shared) (- $after $before)))
   (true 1))

;; Empty and atomic proofs, or an incorrect marker arity, remain ordinary
;; constraints. Each compiles its scaffold; none may call car-atom on ().
!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote ())) (the TV $tv)))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote total-implication-frontier)) (the TV $tv)))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote (total-implication-frontier))) (the TV $tv)))
          ($after (nextctx)))
      (- $after $before))
   3)

!(test
   (let* (($before (nextctx))
          ($_adds (inject-special-subgoal-query-adds
             (brand Statement (Implication (MarkerInput) (MarkerOutput)))
                (brand KBContext (markerKb MAIN Nil))
                (brand Proof (quote (total-implication-frontier one two))) (the TV $tv)))
          ($after (nextctx)))
      (- $after $before))
   3)
