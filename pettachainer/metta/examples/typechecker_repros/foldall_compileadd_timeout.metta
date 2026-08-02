; Regression test for the Expression-to-Atom evaluation-contract migration.
; Run from pettachainer/metta:
;   timeout 30 sh /path/to/PeTTa/run.sh \
;      examples/typechecker_repros/foldall_compileadd_timeout.metta \
;      --strict-det --silent
;
; Expected on PeTTa e7938dc after migrating PeTTaChainer declarations: exits
; successfully, adding only about 0.15 seconds over import-only startup.
; Before the migration this did not finish within 30 seconds.

!(import! &self ../../petta_chainer)

!(compileadd reproKb
   (: foldRule
      (Implication
         (Premises
            (FoldAll
               (Score $n)
               $n
               0
               (|-> ($acc $elem) (+ $acc $elem))
               ->
               $total))
         (Conclusions (ScoreTotal $total)))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
