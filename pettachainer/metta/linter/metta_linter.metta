!(import! &self (library lib_spaces))
!(import! &self (library lib_import))
!(import! &self (library lib_roman))

!(import_prolog_functions_from_file "./metta_linter_source.pl" (load_metta_source))

(= (lint-list-count ()) 0)
(= (lint-list-count (cons $_head $tail)) (+ 1 (lint-list-count $tail)))

(= (lint-third $items) (car-atom (cdr-atom (cdr-atom $items))))

(= (lint-second $items) (car-atom (cdr-atom $items)))

(= (lint-warning $line $rule $head $expr) (warning $line $rule $head $expr))

(= (lint-fix $line $rule $head $expr $replacement) (fix $line $rule $head $expr $replacement))

(= (lint-skip-descend-head? $head) (is-member $head (|-> quote)))

(= (lint-singleton-superpose-exempt-head? $head)
   (and (is-expr $head) (== (car-atom $head) direct-goal-results)))

(= (lint-singleton-superpose-expr $line $head $expr)
   (if (or (== $expr ()) (not (is-expr $expr))) ()
      (let $args (cdr-atom $expr)
         (if
            (and (not (lint-singleton-superpose-exempt-head? $head))
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
         (if
            (and (== (length $head1-args) 2)
               (== (length $head2-args) 2)
               (== (car-atom $body2) cons)
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
               (if
                  (and (== $head1-first ())
                     (== $body1 $ys0)
                     (is-expr $head2-first)
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
                        (and (== $name0 $name1)
                           (== $name1 $name2)
                           (== $x $x1)
                           (== $xs $xs1)
                           (== $ys1 $ys2)
                           (not (== $name0 append)))
                        (lint-warning $line
                           local-append-reimplementation
                           $name0
                           (quote (= ($name0 () $ys0) $ys0)))
                        (empty)))
                  (empty)))
            (empty)))
      (empty)))

(= (lint-local-append-reimplementation-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head1 $body1))
         (match $source-space (source-form $_line2 function (= $head2 $body2))
            (lint-local-append-reimplementation-pair-warning $line
               $head1
               $body1
               $head2
               $body2)))))

(= (lint-manual-map-flat-recursion-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= ($name ()) ()))
         (match $source-space
            (source-form $_line2 function (= ($name (cons $x $xs)) (cons $mapped ($name $xs))))
            (lint-warning $line
               manual-map-flat-recursion
               $name
               (quote (= ($name (cons $x $xs)) (cons $mapped ($name $xs)))))))))

(= (lint-manual-fold-flat-append-recursion-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= ($name ()) ()))
         (match $source-space
            (source-form $_line2 function (= ($name (cons $x $xs)) (append $mapped ($name $xs))))
            (lint-warning $line
               manual-fold-flat-append-recursion
               $name
               (quote (= ($name (cons $x $xs)) (append $mapped ($name $xs)))))))))

(= (lint-manual-fold-nested-recursion-warnings $source-space)
   (collapse
      (match $source-space
         (source-form $line
            function
            (= ($name $x) (if (== $x $needle) true (if (is-expr $x) ($expr-name $x) false))))
         (match $source-space
            (source-form $_line2
               function
               (= ($expr-name $expr) (or (== (car-atom $expr) $needle2) ($list-name (cdr-atom $expr)))))
            (match $source-space (source-form $_line3 function (= ($list-name ()) false))
               (match $source-space
                  (source-form $_line4
                     function
                     (= ($list-name (cons $head $tail)) (or ($name $head) ($list-name $tail))))
                  (if (== $needle $needle2)
                     (lint-warning $line
                        manual-fold-nested-recursion
                        $name
                        (quote
                           (= ($name $x) (if (== $x $needle) true (if (is-expr $x) ($expr-name $x) false)))))
                     (empty))))))))

(= (lint-trivial-forwarding-wrapper-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head $body))
         (if (and (is-expr $head) (is-expr $body))
            (let*
               (($name (car-atom $head))
                 ($args (cdr-atom $head))
                 ($body-name (car-atom $body))
                 ($body-args (cdr-atom $body))
                 ($other-clauses
                    (collapse
                       (match $source-space (source-form $line2 function (= $other-head $_other-body))
                          (if (not (== $line2 $line))
                             (if (is-expr $other-head) (if (== (car-atom $other-head) $name) $line2 (empty))
                                (empty))
                             (empty))))))
               (if (not (== $name $body-name))
                  (if (=alpha $args $body-args)
                     (if (== $other-clauses ())
                        (lint-warning $line trivial-forwarding-wrapper $name (quote (= $head $body)))
                        (empty))
                     (empty))
                  (empty)))
            (empty)))))

(= (lint-superfluous-singleton-cons-children-acc $line $head () $acc) $acc)
(= (lint-superfluous-singleton-cons-children-acc $line $head (cons $child $rest) $acc)
   (lint-superfluous-singleton-cons-children-acc $line
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
                    (if (== $tail ()) (cons (lint-warning $line superfluous-singleton-cons $head $expr) $acc)
                       $acc))
                 $acc)))
         (if (lint-skip-descend-head? $expr-head) $acc1
            (lint-superfluous-singleton-cons-children-acc $line $head $args $acc1)))))

(= (lint-superfluous-singleton-cons-expr $line $head $expr)
   (reverse (lint-superfluous-singleton-cons-expr-acc $line $head $expr ())))

(= (lint-nested-let-children-acc $line $head () $acc) $acc)
(= (lint-nested-let-children-acc $line $head (cons $child $rest) $acc)
   (lint-nested-let-children-acc $line $head $rest (lint-nested-let-expr-acc $line $head $child $acc)))

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

(= (lint-nested-let-expr $line $head $expr) (reverse (lint-nested-let-expr-acc $line $head $expr ())))

(= (lint-case-fix-singleton $target $branch)
   (let*
      (($pattern (car-atom $branch))
        ($body (lint-second $branch)))
      (quote (let $pattern $target $body))))

(= (lint-case-fix-default-if $target $specific-branch $default-branch)
   (let*
      (($pattern (car-atom $specific-branch))
        ($then-body (lint-second $specific-branch))
        ($default-pattern (car-atom $default-branch))
        ($else-body (lint-second $default-branch)))
      (quote
         (if (= $target $pattern) (let $pattern $target $then-body) (let $default-pattern $target $else-body)))))

(= (lint-case-branch-pair $branch)
   (if (is-expr $branch) (if (== (length $branch) 1) (car-atom $branch) $branch) (empty)))

(= (lint-singleton-case-option-warning $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 1)
                  (let $branch (lint-case-branch-pair (car-atom $branches))
                     (if (is-expr $branch)
                        (if (== (length $branch) 2) (lint-warning $line singleton-case-option $head $body)
                           (empty))
                        (empty)))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-singleton-case-option-fix $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 1)
                  (let $branch (lint-case-branch-pair (car-atom $branches))
                     (if (is-expr $branch)
                        (if (== (length $branch) 2)
                           (lint-fix $line
                              singleton-case-option
                              $head
                              $body
                              (lint-case-fix-singleton $target $branch))
                           (empty))
                        (empty)))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-warning-ordered $line $head $body $target $specific-branch $default-branch)
   (let*
      (($specific-pair (lint-case-branch-pair $specific-branch))
        ($default-pair (lint-case-branch-pair $default-branch)))
      (if (is-expr $specific-pair)
         (if (is-expr $default-pair)
            (if (== (length $specific-pair) 2)
               (if (== (length $default-pair) 2)
                  (let*
                     (($pattern1 (car-atom $specific-pair))
                       ($pattern2 (car-atom $default-pair)))
                     (if (not (is-var $pattern1))
                        (if (is-var $pattern2) (lint-warning $line default-case-option $head $body) (empty))
                        (empty)))
                  (empty))
               (empty))
            (empty))
         (empty))))

(= (lint-default-case-option-fix-ordered $line $head $body $target $specific-branch $default-branch)
   (let*
      (($specific-pair (lint-case-branch-pair $specific-branch))
        ($default-pair (lint-case-branch-pair $default-branch)))
      (if (is-expr $specific-pair)
         (if (is-expr $default-pair)
            (if (== (length $specific-pair) 2)
               (if (== (length $default-pair) 2)
                  (let*
                     (($pattern1 (car-atom $specific-pair))
                       ($pattern2 (car-atom $default-pair)))
                     (if (not (is-var $pattern1))
                        (if (is-var $pattern2)
                           (lint-fix $line
                              default-case-option
                              $head
                              $body
                              (lint-case-fix-default-if $target $specific-pair $default-pair))
                           (empty))
                        (empty)))
                  (empty))
               (empty))
            (empty))
         (empty))))

(= (lint-default-case-option-warning $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (let*
                     (($branch1 (car-atom $branches))
                       ($branch2 (lint-second $branches)))
                     (lint-first-nonempty
                        (lint-default-case-option-warning-ordered $line
                           $head
                           $body
                           $target
                           $branch1
                           $branch2)
                        (lint-default-case-option-warning-ordered $line
                           $head
                           $body
                           $target
                           $branch2
                           $branch1)))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-fix $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (let*
                     (($branch1 (car-atom $branches))
                       ($branch2 (lint-second $branches)))
                     (lint-first-nonempty
                        (lint-default-case-option-fix-ordered $line
                           $head
                           $body
                           $target
                           $branch1
                           $branch2)
                        (lint-default-case-option-fix-ordered $line
                           $head
                           $body
                           $target
                           $branch2
                           $branch1)))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-warning-forward $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (lint-default-case-option-warning-ordered $line
                     $head
                     $body
                     $target
                     (car-atom $branches)
                     (lint-second $branches))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-warning-reversed $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (lint-default-case-option-warning-ordered $line
                     $head
                     $body
                     $target
                     (lint-second $branches)
                     (car-atom $branches))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-fix-forward $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (lint-default-case-option-fix-ordered $line
                     $head
                     $body
                     $target
                     (car-atom $branches)
                     (lint-second $branches))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-default-case-option-fix-reversed $line $head $body)
   (if (is-expr $body)
      (if (== (car-atom $body) case)
         (let*
            (($args (cdr-atom $body))
              ($target (car-atom $args))
              ($branches (lint-second $args)))
            (if (is-expr $branches)
               (if (== (length $branches) 2)
                  (lint-default-case-option-fix-ordered $line
                     $head
                     $body
                     $target
                     (lint-second $branches)
                     (car-atom $branches))
                  (empty))
               (empty)))
         (empty))
      (empty)))

(= (lint-form-warning-step $acc $warnings) (append $acc $warnings))

(= (lint-form-fix-step $acc $fixes) (append $acc $fixes))

(= (lint-first-nonempty () $fallback) $fallback)
(= (lint-first-nonempty $value $_fallback) $value)

(= (lint-singleton-case-option-warnings $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head $body))
         (lint-singleton-case-option-warning $line $head $body))))

(= (lint-singleton-case-option-fixes $source-space)
   (collapse
      (match $source-space (source-form $line function (= $head $body))
         (lint-singleton-case-option-fix $line $head $body))))

(= (lint-default-case-option-warnings $source-space)
   (append
      (collapse
         (match $source-space (source-form $line function (= $head $body))
            (lint-default-case-option-warning-forward $line $head $body)))
      (collapse
         (match $source-space (source-form $line function (= $head $body))
            (lint-default-case-option-warning-reversed $line $head $body)))))

(= (lint-default-case-option-fixes $source-space)
   (append
      (collapse
         (match $source-space (source-form $line function (= $head $body))
            (lint-default-case-option-fix-forward $line $head $body)))
      (collapse
         (match $source-space (source-form $line function (= $head $body))
            (lint-default-case-option-fix-reversed $line $head $body)))))

(= (lint-collect-warnings $source-space)
   (let $form-warnings
      (fold-flat lint-form-warning-step
         ()
         (collapse
            (match $source-space (source-form $line function (= $head $body))
               (let*
                  (($qhead (quote $head))
                    ($qbody (quote $body)))
                  (append (lint-singleton-superpose-expr $line $qhead $qbody)
                     (append (lint-superfluous-singleton-cons-expr $line $qhead $qbody)
                        (lint-nested-let-expr $line $qhead $qbody)))))))
      (append $form-warnings
         (append (lint-local-append-reimplementation-warnings $source-space)
            (append (lint-manual-map-flat-recursion-warnings $source-space)
               (append (lint-manual-fold-flat-append-recursion-warnings $source-space)
                  (append (lint-manual-fold-nested-recursion-warnings $source-space)
                     (append (lint-trivial-forwarding-wrapper-warnings $source-space)
                        (append (lint-singleton-case-option-warnings $source-space)
                           (lint-default-case-option-warnings $source-space))))))))))

(= (lint-collect-fixes $source-space)
   (append (lint-singleton-case-option-fixes $source-space)
      (lint-default-case-option-fixes $source-space)))

(= (lint-source-space-name) lint_source)

(= (lint-clear-source-space $space) (progn (remove-all-atoms $space) $space))

(= (lint-file-report $file)
   (let*
      (($source-space (lint-clear-source-space (lint-source-space-name)))
        ($_load (load_metta_source $file $source-space))
        ($warnings (lint-collect-warnings $source-space)))
      (lint-report $file (lint-list-count $warnings) $warnings)))

(= (lint-file-warning-count $file)
   (let (lint-report $_file $count $_warnings) (lint-file-report $file) $count))

(= (lint-file-warnings $file) (let (lint-report $_file $_count $warnings) (lint-file-report $file) $warnings))

(= (lint-file-fix-report $file)
   (let*
      (($source-space (lint-clear-source-space (lint-source-space-name)))
        ($_load (load_metta_source $file $source-space))
        ($fixes (lint-collect-fixes $source-space)))
      (lint-fix-report $file (lint-list-count $fixes) $fixes)))

(= (lint-file-fixes $file) (let (lint-fix-report $_file $_count $fixes) (lint-file-fix-report $file) $fixes))

(= (lint-warning-summary (warning $line $rule $head $_expr)) (warning $line $rule $head))

(= (lint-fix-summary (fix $line $rule $head $_expr $replacement)) (fix $line $rule $head $replacement))

(= (lint-file-summary-report $file)
   (let*
      (($report (lint-file-report $file))
        ($warnings (let (lint-report $_file $_count $warnings) $report $warnings))
        ($count (let (lint-report $_file $count $_warnings) $report $count))
        ($fix-report (lint-file-fix-report $file))
        ($fixes (let (lint-fix-report $_file $_count $fixes) $fix-report $fixes))
        ($fix-count (let (lint-fix-report $_file $count $_fixes) $fix-report $count)))
      (lint-summary-report $file
         $count
         (map-flat lint-warning-summary $warnings)
         $fix-count
         (map-flat lint-fix-summary $fixes))))

(= (lint-warning-list-has $warning ()) false)
(= (lint-warning-list-has $warning (cons $head $tail))
   (if (or (== $warning $head) (=alpha $warning $head)) true (lint-warning-list-has $warning $tail)))

(= (lint-file-has-warning $file $warning) (lint-warning-list-has $warning (lint-file-warnings $file)))

(= (lint-fix-list-has $fix ()) false)
(= (lint-fix-list-has $fix (cons $head $tail))
   (if (or (== $fix $head) (=alpha $fix $head)) true (lint-fix-list-has $fix $tail)))

(= (lint-file-has-fix $file $fix) (lint-fix-list-has $fix (lint-file-fixes $file)))
