!(import! &self (library lib_spaces))
!(import! &self (library lib_import))
!(import! &self (library lib_roman))

!(import_prolog_functions_from_file "./metta_linter_source.pl" (load_metta_source lint_thaw))

; The source space holds every top-level form of the linted file with its
; variables frozen into (lint-source-var Name) markers, so the patterns below
; match only the structure that is written in the file.
(= (lint-load $file)
   (let* (($_cleared (remove-all-atoms lint_source))
          ($_loaded (load_metta_source $file lint_source)))
      lint_source))

;; Shapes that a function body should not contain anywhere outside quoted data.
(lint-node-rule singleton-superpose (superpose ($_)))
(lint-node-rule superfluous-singleton-cons (cons $_ ()))
(lint-node-rule nested-let (let $_ $_ (let $_ $_ $_)))

(= (lint-expr-warnings $line $head $acc $expr)
   (if (or (not (is-expr $expr)) (== $expr ())) $acc
      (let $acc1 (append $acc (collapse (match &self (lint-node-rule $rule $expr) (warning $line $rule $head $expr))))
         (if (== (car-atom $expr) quote) $acc1
            (fold-flat (lint-expr-warnings $line $head) $acc1 (cdr-atom $expr))))))

(= (lint-body-warnings $source-space)
   (fold-flat append
      ()
      (collapse
         (match $source-space (source-form $line function (= $head $body))
            (lint-expr-warnings $line $head () $body)))))

(= (lint-recursion-warnings $source-space)
   (collapse
      (superpose
         ((match $source-space (source-form $line function (= ($name () $ys) $ys))
             (match $source-space
                (source-form $_line2 function (= ($name (cons $x $xs) $ys2) (cons $x ($name $xs $ys2))))
                (if (== $name append) (empty)
                   (quote (warning $line local-append-reimplementation $name (= ($name () $ys) $ys))))))
          (match $source-space (source-form $line function (= ($name ()) ()))
             (match $source-space
                (source-form $_line2 function (= ($name (cons $x $xs)) (cons $mapped ($name $xs))))
                (quote
                   (warning $line
                      manual-map-flat-recursion
                      $name
                      (= ($name (cons $x $xs)) (cons $mapped ($name $xs)))))))
          (match $source-space (source-form $line function (= ($name ()) ()))
             (match $source-space
                (source-form $_line2 function (= ($name (cons $x $xs)) (append $mapped ($name $xs))))
                (quote
                   (warning $line
                      manual-fold-flat-append-recursion
                      $name
                      (= ($name (cons $x $xs)) (append $mapped ($name $xs)))))))
          (match $source-space
             (source-form $line
                function
                (= ($name $x) (if (== $x $needle) true (if (is-expr $x) ($expr-name $x) false))))
             (match $source-space
                (source-form $_line2
                   function
                   (= ($expr-name $expr) (or (== (car-atom $expr) $needle) ($list-name (cdr-atom $expr)))))
                (match $source-space (source-form $_line3 function (= ($list-name ()) false))
                   (match $source-space
                      (source-form $_line4
                         function
                         (= ($list-name (cons $head $tail)) (or ($name $head) ($list-name $tail))))
                      (quote
                         (warning $line
                            manual-fold-nested-recursion
                            $name
                            (= ($name $x) (if (== $x $needle) true (if (is-expr $x) ($expr-name $x) false)))))))))))))

; A function whose only clause passes its parameters unchanged to another
; function.
(= (lint-forwarding-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head $body))
         (if (or (not (is-expr $body)) (== $body ())) (empty)
            (let* ((($name $args) (decons-atom $head))
                   (($body-name $body-args) (decons-atom $body)))
               (if (or (== $name $body-name) (not (== $args $body-args))) (empty)
                  (if (== (collapse
                            (match $source-space (source-form $line2 function (= $head2 $_))
                               (if (== (car-atom $head2) $name) $line2 (empty))))
                         ($line))
                     (quote (warning $line trivial-forwarding-wrapper $name (= $head $body)))
                     (empty))))))))

; Case expressions that a let or an if states directly. Each fix also stands
; for its warning.
(= (lint-case-fixes $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head (case $target $branches)))
         (case $branches
            (((($pattern $result))
              (quote (fix $line singleton-case-option $head (case $target $branches) (let $pattern $target $result))))
             ((((lint-source-var $_) $_) ((lint-source-var $_) $_)) (empty))
             ((($pattern $result) ((lint-source-var $default) $else))
              (quote
                 (fix $line
                    default-case-option
                    $head
                    (case $target $branches)
                    (if (= $target $pattern)
                       (let $pattern $target $result)
                       (let (lint-source-var $default) $target $else)))))
             ((((lint-source-var $default) $else) ($pattern $result))
              (quote
                 (fix $line
                    default-case-option
                    $head
                    (case $target $branches)
                    (if (= $target $pattern)
                       (let $pattern $target $result)
                       (let (lint-source-var $default) $target $else)))))
             ($_ (empty)))))))

(= (lint-file-report $file)
   (let* (($source-space (lint-load $file))
          ($warnings
             (map-flat lint_thaw
                (append (lint-body-warnings $source-space)
                   (append (lint-recursion-warnings $source-space)
                      (append (lint-forwarding-warnings $source-space)
                         (map-flat lint-fix-warning (lint-case-fixes $source-space))))))))
      (lint-report $file (length $warnings) $warnings)))

(= (lint-fix-warning (fix $line $rule $head $expr $_replacement)) (warning $line $rule $head $expr))

(= (lint-file-fix-report $file)
   (let $fixes (map-flat lint_thaw (lint-case-fixes (lint-load $file)))
      (lint-fix-report $file (length $fixes) $fixes)))

(= (lint-file-warning-count $file) (let (lint-report $_file $count $_warnings) (lint-file-report $file) $count))

(= (lint-file-has-warning $file $warning)
   (let (lint-report $_file $_count $warnings) (lint-file-report $file) (is-alpha-member $warning $warnings)))

(= (lint-file-has-fix $file $fix)
   (let (lint-fix-report $_file $_count $fixes) (lint-file-fix-report $file) (is-alpha-member $fix $fixes)))
