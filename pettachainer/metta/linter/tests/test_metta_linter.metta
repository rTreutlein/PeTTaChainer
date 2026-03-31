!(import! &self ../metta_linter)

!(test
   (lint-file-warning-count "tests/fixtures/lint_sample.metta")
   7)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 1 singleton-superpose (lint-singleton-superpose) (superpose ((CPU SampleFormula () done))))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 4 nested-let (lint-nested-let) (let $x 1 (let $y 2 (+ $x $y))))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 9 superfluous-singleton-cons (lint-cons-cpu-singleton) (cons (CPU SampleFormula (a b) done) ()))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 12 superfluous-singleton-cons (lint-cons-generic-singleton) (cons (Something a b) ()))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 15 local-append-reimplementation lint-local-append (= (lint-local-append () $ys) $ys))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 21 manual-map-flat-recursion lint-manual-map-list (= (lint-manual-map-list (cons $x $xs)) (cons (Wrap $x) (lint-manual-map-list $xs))))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning 26 manual-fold-flat-append-recursion lint-manual-append-list (= (lint-manual-append-list (cons $x $xs)) (append (WarningsFor $x) (lint-manual-append-list $xs))))))
   true)

!(test
   (lint-file-has-warning
      "tests/fixtures/lint_sample.metta"
      (quote (warning $_line $_rule (lint-clean) $_expr)))
   false)
