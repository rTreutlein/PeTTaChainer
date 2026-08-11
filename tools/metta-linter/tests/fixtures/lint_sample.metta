(= (lint-singleton-superpose) (superpose ((CPU SampleFormula () done))))

(= (lint-nested-let) (let $x 1 (let $y 2 (+ $x $y))))

(= (lint-cons-cpu-singleton) (cons (CPU SampleFormula (a b) done) ()))

(= (lint-cons-generic-singleton) (cons (Something a b) ()))

(= (lint-local-append () $ys) $ys)
(= (lint-local-append (cons $x $xs) $ys) (cons $x (lint-local-append $xs $ys)))

(= (lint-manual-map-list ()) ())
(= (lint-manual-map-list (cons $x $xs)) (cons (Wrap $x) (lint-manual-map-list $xs)))

(= (lint-manual-append-list ()) ())
(= (lint-manual-append-list (cons $x $xs)) (append (WarningsFor $x) (lint-manual-append-list $xs)))

(= (lint-contains-mark? $x) (if (== $x mark) true (if (is-expr $x) (lint-contains-mark-expr $x) false)))

(= (lint-contains-mark-expr $expr) (or (== (car-atom $expr) mark) (lint-contains-mark-list (cdr-atom $expr))))

(= (lint-contains-mark-list ()) false)
(= (lint-contains-mark-list (cons $head $tail))
   (or (lint-contains-mark? $head) (lint-contains-mark-list $tail)))

(= (test $x) (what $x))

(= (lint-single-case $x) (case $x (((Value $y) (Wrap $y)))))

(= (lint-default-case $x) (case $x (((Value $y) (Wrap $y)) ($other $other))))

(= (lint-clean) (let* (($x 1) ($y 2)) (+ $x $y)))
