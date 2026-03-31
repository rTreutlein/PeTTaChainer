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

(= (lint-child-warning-fold $rule $line $head $acc $child)
   (append $acc ($rule $line $head $child)))

(= (lint-children-warnings $rule $line $head $expr)
   (if (or (== $expr ()) (not (is-expr $expr))) ()
      (fold-flat (lint-child-warning-fold $rule $line $head) () (cdr-atom $expr))))

(= (lint-singleton-superpose-expr $line $head $expr)
   (if (== $expr ()) ()
      (if (is-expr $expr)
         (let $child-warnings (lint-children-warnings lint-singleton-superpose-expr $line $head $expr)
            (if (and (== (car-atom $expr) superpose) (== (length (cdr-atom $expr)) 1))
               (cons (lint-warning $line singleton-superpose $head $expr) $child-warnings)
               $child-warnings))
         ()))
      )

(= (lint-superfluous-singleton-cons-expr $line $head $expr)
   (if (== $expr ()) ()
      (if (is-expr $expr)
         (let*
            (($args (cdr-atom $expr))
              ($child-warnings (lint-children-warnings lint-superfluous-singleton-cons-expr $line $head $expr)))
            (if (and (== (car-atom $expr) cons) (== (length $args) 2))
               (let*
                  (($item (car-atom $args))
                    ($tail (car-atom (cdr-atom $args))))
                  (if (== $tail ())
                     (cons (lint-warning $line superfluous-singleton-cons $head $expr) $child-warnings)
                     $child-warnings))
               $child-warnings))
         ()))
      )

(= (lint-nested-let-expr $line $head $expr)
   (if (== $expr ()) ()
      (if (is-expr $expr)
         (let*
            (($args (cdr-atom $expr))
              ($child-warnings (lint-children-warnings lint-nested-let-expr $line $head $expr)))
            (if (and (== (car-atom $expr) let) (== (length $args) 3))
               (let $body (lint-third $args)
                  (if (and (is-expr $body) (== (car-atom $body) let))
                     (cons (lint-warning $line nested-let $head $expr) $child-warnings)
                     $child-warnings))
               $child-warnings))
         ()))
      )

(= (lint-local-append-reimplementation-warnings $source-space)
   (collapse
      (match $source-space
         (source-form $line function (= ($name () $ys) $ys))
         (match $source-space
            (source-form $_line2 function
               (= ($name (cons $x $xs) $ys2)
                  (cons $x ($name $xs $ys2))))
            (lint-warning $line local-append-reimplementation $name
               (quote (= ($name () $ys) $ys)))))))

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

(= (lint-warning-list-has $warning ()) false)
(= (lint-warning-list-has $warning (cons $head $tail))
   (if (or (== $warning $head) (=alpha $warning $head)) true
      (lint-warning-list-has $warning $tail)))

(= (lint-file-has-warning $file $warning)
   (lint-warning-list-has $warning (lint-file-warnings $file)))
