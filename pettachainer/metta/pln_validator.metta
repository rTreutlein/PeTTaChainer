;; Pure structural checks for caller-provided PLN Light statements and queries.
;; Inspecting list heads keeps validation independent of constructor reduction
;; and lets it run inside the PeTTa process that imported the chainer.

(: pln-stv-shape? (-[det]-> $tv Bool))
(= (pln-stv-shape? $tv)
   (if (is-expr $tv)
      (if (== (car-atom $tv) STV)
         (== (expr-arity $tv) 3)
         false)
      false))

(: pln-tv-shape? (-[det]-> $tv Bool))
(= (pln-tv-shape? $tv)
   (if (is-expr $tv)
      (let* (($head (car-atom $tv))
             ($arity (expr-arity $tv)))
         (if (== $head STV) (== $arity 3)
         (if (== $head CTV)
            (if (== $arity 3)
               (let $args (cdr-atom $tv)
                  (and
                     (pln-stv-shape? (car-atom $args))
                     (pln-stv-shape? (car-atom (cdr-atom $args)))))
               false)
         (if (== $head NatDist) (== $arity 2)
         (if (== $head FloatDist) (== $arity 2)
         (if (== $head ParticleDist)
            (or (== $arity 2) (== $arity 3))
         (if (== $head PointMass) (== $arity 2)
         (if (== $head ParticleFromNormal) (== $arity 3)
         (if (== $head ParticleFromPairs) (== $arity 2)
            false)))))))))
      false))

(: check-stmt (-[det]-> Atom Number))
(= (check-stmt $expr)
   (if (is-expr $expr)
      (if (and
            (== (car-atom $expr) :)
            (== (expr-arity $expr) 4))
         (let* (($parts (cdr-atom $expr))
                ($prf (car-atom $parts))
                ($tv (car-atom (cdr-atom (cdr-atom $parts)))))
            (if (is-var $prf) 0.0
               (if (is-var $tv) 0.0
                  (if (pln-tv-shape? $tv) 1.0 0.0))))
         0.0)
      0.0))

(: check-query (-[det]-> Atom Number))
(= (check-query $expr)
   (if (is-expr $expr)
      (if (and
            (== (car-atom $expr) :)
            (== (expr-arity $expr) 4))
         (let $prf (car-atom (cdr-atom $expr))
            (if (is-var $prf) 1.0 0.0))
         0.0)
      0.0))
