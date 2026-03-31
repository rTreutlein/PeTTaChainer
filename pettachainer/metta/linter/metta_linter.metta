!(import! &self (library lib_spaces))
!(import! &self ../../../../PeTTa/lib/lib_import)
!(import! &self ../../../../PeTTa/lib/lib_roman)
!(import_prolog_functions_from_file "./metta_linter_source.pl" (load_metta_source))

(= (lint-list-count ()) 0)
(= (lint-list-count (cons $_head $tail)) (+ 1 (lint-list-count $tail)))

(= (lint-third $items)
   (car-atom (cdr-atom (cdr-atom $items))))

(= (lint-warning $line $rule $head $expr)
   (warning $line $rule $head $expr))

(= (lint-skip-descend-head? $head)
   (is-member $head (|-> quote)))

(= (lint-singleton-superpose-exempt-head? $head)
   (and (is-expr $head) (== (car-atom $head) direct-goal-results)))

(= (lint-singleton-superpose-expr $line $head $expr)
   (if (or (== $expr ()) (not (is-expr $expr))) ()
      (let $args (cdr-atom $expr)
         (if (and
                (not (lint-singleton-superpose-exempt-head? $head))
                (== (car-atom $expr) superpose)
                (== (length $args) 1))
            (let $items (car-atom $args)
               (if (and (is-expr $items) (== (length $items) 1))
                  (cons (lint-warning $line singleton-superpose $head $expr) ())
                  ()))
            ()))))

(= (lint-local-append-reimplementation-pair-warning $line $head1 $body1 $head2 $body2)
   (if (and (is-expr $head1) (is-expr $head2) (is-expr $body2))
      (let*
         (($head1-args (cdr-atom $head1))
           ($head2-args (cdr-atom $head2))
           ($body2-args (cdr-atom $body2)))
         (if (and (== (length $head1-args) 2) (== (length $head2-args) 2) (== (car-atom $body2) cons)
                 (== (length $body2-args) 2))
            (let*
               (($name0 (car-atom $head1))
                 ($head1-first (car-atom $head1-args))
                 ($ys0 (car-atom (cdr-atom $head1-args)))
                 ($name1 (car-atom $head2))
                 ($head2-first (car-atom $head2-args))
                 ($ys1 (car-atom (cdr-atom $head2-args)))
                 ($x1 (car-atom $body2-args))
                 ($rec-call (car-atom (cdr-atom $body2-args))))
               (if (and (== $head1-first ()) (== $body1 $ys0) (is-expr $head2-first)
                       (== (car-atom $head2-first) cons)
                       (== (length (cdr-atom $head2-first)) 2)
                       (is-expr $rec-call)
                       (== (length (cdr-atom $rec-call)) 2))
                  (let*
                     (($x (car-atom (cdr-atom $head2-first)))
                       ($xs (car-atom (cdr-atom (cdr-atom $head2-first))))
                       ($name2 (car-atom $rec-call))
                       ($xs1 (car-atom (cdr-atom $rec-call)))
                       ($ys2 (car-atom (cdr-atom (cdr-atom $rec-call)))))
                     (if
                     (and
                           (== $name0 $name1)
                           (== $name1 $name2)
                           (== $x $x1)
                           (== $xs $xs1)
                           (== $ys1 $ys2)
                           (not (== $name0 append)))
                        (lint-warning $line local-append-reimplementation $name0
                           (quote (= ($name0 () $ys0) $ys0)))
                        (empty)))
                  (empty)))
            (empty)))
      (empty)))

(= (lint-local-append-reimplementation-warnings $source-space)
   (collapse
      (match $source-space
         (source-form $line function (= $head1 $body1))
         (match $source-space
            (source-form $_line2 function (= $head2 $body2))
            (lint-local-append-reimplementation-pair-warning $line $head1 $body1 $head2 $body2)))))

(= (lint-manual-map-flat-recursion-warnings $source-space)
   (collapse
      (match $source-space
         (source-form $line function (= ($name ()) ()))
         (match $source-space
            (source-form $_line2 function
               (= ($name (cons $x $xs))
                  (cons $mapped ($name $xs))))
            (lint-warning $line manual-map-flat-recursion $name
               (quote (= ($name (cons $x $xs)) (cons $mapped ($name $xs)))))))))

(= (lint-manual-fold-flat-append-recursion-warnings $source-space)
   (collapse
      (match $source-space
         (source-form $line function (= ($name ()) ()))
         (match $source-space
            (source-form $_line2 function
               (= ($name (cons $x $xs))
                  (append $mapped ($name $xs))))
            (lint-warning $line manual-fold-flat-append-recursion $name
               (quote (= ($name (cons $x $xs)) (append $mapped ($name $xs)))))))))

(= (lint-superfluous-singleton-cons-children-acc $line $head () $acc) $acc)
(= (lint-superfluous-singleton-cons-children-acc $line $head (cons $child $rest) $acc)
   (lint-superfluous-singleton-cons-children-acc
      $line
      $head
      $rest
      (lint-superfluous-singleton-cons-expr-acc $line $head $child $acc)))

(= (lint-superfluous-singleton-cons-expr-acc $line $head $expr $acc)
   (if (or (== $expr ()) (not (is-expr $expr))) $acc
      (let*
         (($args (cdr-atom $expr))
           ($expr-head (car-atom $expr))
           ($acc1
              (if (and (== $expr-head cons) (== (length $args) 2))
                 (let*
                    (($item (car-atom $args))
                      ($tail (car-atom (cdr-atom $args))))
                    (if (== $tail ())
                       (cons (lint-warning $line superfluous-singleton-cons $head $expr) $acc)
                       $acc))
                 $acc)))
         (if (lint-skip-descend-head? $expr-head) $acc1
            (lint-superfluous-singleton-cons-children-acc $line $head $args $acc1)))))

(= (lint-superfluous-singleton-cons-expr $line $head $expr)
   (reverse (lint-superfluous-singleton-cons-expr-acc $line $head $expr ())))

(= (lint-nested-let-children-acc $line $head () $acc) $acc)
(= (lint-nested-let-children-acc $line $head (cons $child $rest) $acc)
   (lint-nested-let-children-acc
      $line
      $head
      $rest
      (lint-nested-let-expr-acc $line $head $child $acc)))

(= (lint-nested-let-expr-acc $line $head $expr $acc)
   (if (or (== $expr ()) (not (is-expr $expr))) $acc
      (let*
         (($args (cdr-atom $expr))
           ($expr-head (car-atom $expr))
           ($acc1
              (if (and (== $expr-head let) (== (length $args) 3))
                 (let $body (lint-third $args)
                    (if (and (is-expr $body) (== (car-atom $body) let))
                       (cons (lint-warning $line nested-let $head $expr) $acc)
                       $acc))
                 $acc)))
         (if (lint-skip-descend-head? $expr-head) $acc1
            (lint-nested-let-children-acc $line $head $args $acc1)))))

(= (lint-nested-let-expr $line $head $expr)
   (reverse (lint-nested-let-expr-acc $line $head $expr ())))

(= (lint-form-warning-step $acc $warnings)
   (append $acc $warnings))

(= (lint-collect-warnings $source-space)
   (let $form-warnings
      (fold-flat lint-form-warning-step
         ()
         (collapse
            (match $source-space (source-form $line function (= $head $body))
               (let*
                  (($qhead (quote $head))
                    ($qbody (quote $body)))
                  (append
                     (lint-singleton-superpose-expr $line $qhead $qbody)
                     (append
                        (lint-superfluous-singleton-cons-expr $line $qhead $qbody)
                        (lint-nested-let-expr $line $qhead $qbody)))))))
      (append
         $form-warnings
         (append
            (lint-local-append-reimplementation-warnings $source-space)
            (append
               (lint-manual-map-flat-recursion-warnings $source-space)
               (lint-manual-fold-flat-append-recursion-warnings $source-space))))))

(= (lint-source-space-name) lint_source)

(= (lint-clear-source-space $space)
   (progn (remove-all-atoms $space) $space))

(= (lint-file-report $file)
   (let*
      (($source-space (lint-clear-source-space (lint-source-space-name)))
        ($_load (load_metta_source $file $source-space))
        ($warnings (lint-collect-warnings $source-space)))
      (lint-report $file (lint-list-count $warnings) $warnings)))

(= (lint-file-warning-count $file)
   (let (lint-report $_file $count $_warnings) (lint-file-report $file) $count))

(= (lint-file-warnings $file)
   (let (lint-report $_file $_count $warnings) (lint-file-report $file) $warnings))

(= (lint-warning-summary (warning $line $rule $head $_expr))
   (warning $line $rule $head))

(= (lint-file-summary-report $file)
   (let*
      (($report (lint-file-report $file))
        ($warnings (let (lint-report $_file $_count $warnings) $report $warnings))
        ($count (let (lint-report $_file $count $_warnings) $report $count)))
      (lint-report $file $count (map-flat lint-warning-summary $warnings))))

(= (lint-warning-list-has $warning ()) false)
(= (lint-warning-list-has $warning (cons $head $tail))
   (if (or (== $warning $head) (=alpha $warning $head)) true
      (lint-warning-list-has $warning $tail)))

(= (lint-file-has-warning $file $warning)
   (lint-warning-list-has $warning (lint-file-warnings $file)))
