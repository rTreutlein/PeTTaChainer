; Bound-Bool output certification now lets a det user-function call feed a
; boolean builtin directly.  The guarantee is not propagated recursively when
; that result first passes through another contextual boolean builtin.
;
; Fails on PeTTa typecheck-v2 e513a09 in both modes:
;   run.sh det_nested_bool_operand.metta --strict
;   run.sh det_nested_bool_operand.metta --strict --strict-det
;   Determinism check failed for 'left-only-empty': call(and)

(: is-empty (-[det]-> (List Number) Bool))
(= (is-empty $values)
   (== $values ()))

(: left-only-empty (-[det]-> (List Number) (List Number) Bool))
(= (left-only-empty $left $right)
   (and (is-empty $left)
        (not (is-empty $right))))

!(test (left-only-empty () (1)) true)
!(test (left-only-empty () ()) false)
