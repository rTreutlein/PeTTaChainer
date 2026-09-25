!(import! &self ../../pettachainer/metta/petta_chainer)

;; Keep first occurrence order, distinguish sharing, and do not bind inputs.
;; Pair($x,$x) and Pair($a,$b) share the coarse index-hash, but are not variants.
!(test
   (let* (($keys (the (List SkeletonKey) ((sk-key (Pair $x $x) (keyKb MAIN Nil))
                 (sk-key (Pair $y $y) (keyKb MAIN Nil))
                 (sk-key (Pair $a $b) (keyKb MAIN Nil))
                 (sk-key (Pair one one) (keyKb MAIN Nil))
                 (sk-key (Pair one one) (keyKb MAIN Nil))
                 (sk-key (Pair $z $z) (otherKb MAIN Nil)))))
          ($unique (alpha_unique_keys $keys)))
      ((== $unique ((sk-key (Pair $x $x) (keyKb MAIN Nil))
                    (sk-key (Pair $a $b) (keyKb MAIN Nil))
                    (sk-key (Pair one one) (keyKb MAIN Nil))
                    (sk-key (Pair $z $z) (otherKb MAIN Nil))))
       (is-var $x) (is-var $y) (is-var $a) (is-var $b)))
   (true true true true true))

;; An open root sees both a general fact and its distinct concrete instance.
;; Duplicate keys arriving from different constrained skeleton nodes must not
;; duplicate a public result or change the first-answer order.
!(compileadd keyKb (: generalKey (Pair $x $x) (STV 1.0 0.8)))
!(compileadd keyKb (: concreteKey (Pair one two) (STV 1.0 0.9)))
!(test
   (length (collapse (query 10 keyKb (: generalKey (Pair $x $y) $tv))))
   1)
!(test
   (collapse (query 10 keyKb (: $proof (Pair $x $y) $tv)))
   ((: generalKey (Pair $x $x) (STV 1.0 0.8))
    (: concreteKey (Pair one two) (STV 1.0 0.9))))
!(test
   (collapse (query 0 keyKb (: $proof (Pair $x $y) $tv)))
   ((: generalKey (Pair $x $x) (STV 1.0 0.8))
    (: concreteKey (Pair one two) (STV 1.0 0.9))))

;; A key answered after an open reader cached its unifying keys joins that
;; reader's set, and the reader stays open.
!(test
   (let* (($reader (the SkeletonKey (sk-key (Late $x) (lateKb MAIN Nil))))
          ($rhash (index-hash $reader))
          ($before (sk-unifier-hashes $rhash $reader))
          ($late (the SkeletonKey (sk-key (Late bob) (lateKb MAIN Nil))))
          ($_registered (sk-register-key! $late))
          ($after (sk-unifier-hashes $rhash $reader)))
      ((== $before (cons $rhash ()))
       (== $after (deps-set (cons $rhash (cons (index-hash $late) ()))))
       (is-var $x)))
   (true true true))
