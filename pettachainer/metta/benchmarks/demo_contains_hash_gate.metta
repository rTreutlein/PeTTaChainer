!(import! &self ../petta_chainer)

(= (DemoTermNoHash $n)
   (if (<= $n 0) (Edge A B)
      (Implication (Premises (DemoTermNoHash (- $n 1)) (Edge $n (+ $n 1)))
         (Conclusions (Path $n (+ $n 1))))))

(= (DemoTermWithHash $n)
   (if (<= $n 0) (Edge # B)
      (Implication (Premises (DemoTermWithHash (- $n 1)) (Edge $n (+ $n 1)))
         (Conclusions (Path $n (+ $n 1))))))

(= (RepeatAlwaysMap $n $term)
   (if (<= $n 0) () (let $_ (map-nested unwrap $term) (RepeatAlwaysMap (- $n 1) $term))))

(= (RepeatContainsHashGate $n $term)
   (if (<= $n 0) ()
      (let $_ (if (contains-hash? $term) (map-nested unwrap $term) $term)
         (RepeatContainsHashGate (- $n 1) $term))))

(= (TimeAlwaysMap $iters $term)
   (let*
      (($t1 (current-time))
        ($_ (RepeatAlwaysMap $iters $term))
        ($t2 (current-time)))
      (- $t2 $t1)))

(= (TimeContainsHashGate $iters $term)
   (let*
      (($t1 (current-time))
        ($_ (RepeatContainsHashGate $iters $term))
        ($t2 (current-time)))
      (- $t2 $t1)))

!(let*
   (($iters 3000)
     ($depth 12)
     ($term-no-hash (DemoTermNoHash $depth))
     ($term-with-hash (DemoTermWithHash $depth))
     ($always-no-hash (TimeAlwaysMap $iters $term-no-hash))
     ($gate-no-hash (TimeContainsHashGate $iters $term-no-hash))
     ($always-with-hash (TimeAlwaysMap $iters $term-with-hash))
     ($gate-with-hash (TimeContainsHashGate $iters $term-with-hash)))
   ((iterations $iters) (term-depth $depth)
      (no-hash-term (always-map-seconds $always-no-hash) (contains-hash-gate-seconds $gate-no-hash))
      (with-hash-term (always-map-seconds $always-with-hash) (contains-hash-gate-seconds $gate-with-hash))))
