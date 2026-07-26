; collapse always produces a bound, proper list.  union-atom is deterministic
; for that input, but the bound/proper-list fact is lost across collect-one.
;
; Passes:
;   run.sh det_collapse_union_bound_list.metta --strict
; Fails on PeTTa typecheck-v2 6222d50:
;   run.sh det_collapse_union_bound_list.metta --strict --strict-det
;   Determinism check failed for 'collect-and-extend': call('union-atom')

(: collect-one (-> Number (List Number)))
(= (collect-one $value)
   (collapse $value))

(: collect-and-extend (-> Number Number (List Number)))
(= (collect-and-extend $left $right)
   (union-atom
      (collect-one $left)
      ($right)))

!(test (collect-and-extend 1 2) (1 2))
