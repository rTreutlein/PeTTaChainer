; Flow-sensitive nonemptiness works for a declared list parameter, but the
; same proof is lost when the variable is introduced by let from collapse.
; collapse already certifies that its output is a bound proper list.
;
; Passes:
;   run.sh det_nonempty_collapse_binding.metta --strict
; Fails on PeTTa typecheck-v2 72175b7:
;   run.sh det_nonempty_collapse_binding.metta --strict --strict-det
;   Determinism check failed for 'collect-first-or-empty': call('first-list')

(: first-list (-[semidet]-> (List (List Number)) (List Number)))
(= (first-list (cons $head $_tail)) $head)

(: collect-first-or-empty (-> Number (List Number)))
(= (collect-first-or-empty $value)
   (let $values
      (collapse (collapse $value))
      (if (== $values ())
         ()
         (first-list $values))))

!(test (collect-first-or-empty 7) (7))
