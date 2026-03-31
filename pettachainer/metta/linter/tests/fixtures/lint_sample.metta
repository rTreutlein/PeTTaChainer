(= (lint-singleton-superpose)
   (superpose ((CPU SampleFormula () done))))

(= (lint-nested-let)
   (let $x 1
      (let $y 2
         (+ $x $y))))

(= (lint-cons-cpu-singleton)
   (cons (CPU SampleFormula (a b) done) ()))

(= (lint-cons-generic-singleton)
   (cons (Something a b) ()))

(= (lint-local-append () $ys)
   $ys)

(= (lint-local-append (cons $x $xs) $ys)
   (cons $x (lint-local-append $xs $ys)))

(= (lint-manual-map-list ()) ())

(= (lint-manual-map-list (cons $x $xs))
   (cons (Wrap $x) (lint-manual-map-list $xs)))

(= (lint-manual-append-list ()) ())

(= (lint-manual-append-list (cons $x $xs))
   (append (WarningsFor $x) (lint-manual-append-list $xs)))

(= (lint-clean)
   (let* (($x 1)
          ($y 2))
      (+ $x $y)))
