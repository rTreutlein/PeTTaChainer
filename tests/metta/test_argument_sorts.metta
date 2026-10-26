!(import! &self ../../pettachainer/metta/petta_chainer)

;; Sorts per argument position (set-argument-sorts, set-constant-sort). A
;; constant at a declared Stage or Time position is a stage-making constant,
;; and every statement with one is a stage: its inversions and completions
;; get evidence from below only (#122).

;; G10: an event's role fact makes its properties stages. The collider
;; R -> W <- S over events: R ev1 predicts W, which is no evidence about the
;; stage S ev1, so it keeps its prior 0.4 (exact). Undeclared, S ev1 is an
;; aggregate and abduces 0.628 from the prediction.
!(set-bayes-prior-count 0)
!(set-argument-sorts sortEvent Time (Stage Time))
!(set-base-rate sortEvent (S $e) (STV 0.4 1))
!(set-base-rate sortEvent (R $e) (STV 0.3 1))
!(compileadd sortEvent (: t1 (Time ev1 d1) (STV 1 1)))
!(compileadd sortEvent (: r1 (R ev1) (STV 1 1)))
!(compileadd sortEvent (: rw (Implication (R $e) (W $e)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortEvent (: sw (Implication (S $e) (W $e)) (CTV (STV 0.8 1) (STV 0.25 1))))
!(test (query 2000 sortEvent (: $p (S ev1) $tv)) (: (population-prior (S $_0)) (S ev1) (STV 0.4 1)))
!(set-base-rate sortUndeclared (S $e) (STV 0.4 1))
!(set-base-rate sortUndeclared (R $e) (STV 0.3 1))
!(compileadd sortUndeclared (: t1 (Time ev1 d1) (STV 1 1)))
!(compileadd sortUndeclared (: r1 (R ev1) (STV 1 1)))
!(compileadd sortUndeclared (: rw (Implication (R $e) (W $e)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortUndeclared (: sw (Implication (S $e) (W $e)) (CTV (STV 0.8 1) (STV 0.25 1))))
!(test (query 2000 sortUndeclared (: $p (S ev1) $tv))
   (: ((inverted sw with cpu (prior (STV 0.4 1))) (by rw r1)) (S ev1) (STV 0.62786029706945 0.9998672046805047)))

;; Only ingested facts and rules sort constants, never a query: asking about
;; a role, or assuming one, leaves the event an aggregate, and its later
;; answers are the ones it has without the question.
!(compileadd sortEvent (: r6 (R ev6) (STV 1 1)))
!(collapse (query 200 sortEvent (: $p (Time ev6 d6) $tv)))
!(collapse (query 200 sortEvent (: $p (Assuming (Time ev6 d6) (R ev6)) $tv)))
!(test (query 2000 sortEvent (: $p (S ev6) $tv))
   (: ((inverted sw with cpu (prior (STV 0.4 1))) (by rw r6)) (S ev6) (STV 0.62786029706945 0.9998672046805047)))

;; D1: a kind is read when a row is computed. S ev2, queried before its role
;; fact, stays an aggregate; state an event's roles before querying it.
!(compileadd sortEvent (: r2 (R ev2) (STV 1 1)))
!(test (query 2000 sortEvent (: $p (S ev2) $tv))
   (: ((inverted sw with cpu (prior (STV 0.4 1))) (by rw r2)) (S ev2) (STV 0.62786029706945 0.9998672046805047)))
!(compileadd sortEvent (: t2 (Time ev2 d2) (STV 1 1)))
!(test (query 2000 sortEvent (: $p (S ev2) $tv))
   (: ((inverted sw with cpu (prior (STV 0.4 1))) (by rw r2)) (S ev2) (STV 0.62786029706945 0.9998672046805047)))

;; The kind: a declared Stage or Time position, a stage-making constant, or a
;; variable the rule's sorts make one; a compound with a stage part (#139).
;; A Value position sorts nothing.
!(set-argument-sorts sortEvent About (Stage Value))
!(compileadd sortEvent (: c3 (About c3 d9) (STV 1 1)))
!(test (stage-statement? sortEvent (S ev1) ()) true)
!(test (stage-statement? sortEvent (Time $e $t) ()) true)
!(test (stage-statement? sortEvent (S $e) ()) false)
!(test (stage-statement? sortEvent (S $e) ((Time $e d1))) true)
!(test (stage-statement? sortEvent (Or (S ev1) (Q x)) ()) true)
!(test (stage-statement? sortEvent (Or (S x) (Q x)) ()) false)
!(test (stage-statement? sortEvent (Seen c3) ()) true)
!(test (stage-statement? sortEvent (Seen d9) ()) false)

;; A target the rule's own sorts make a stage is one at compile time: the
;; completion of aw onto (S $e), with $e at Agent's Stage position, reads no
;; forward prediction of W. Undeclared, it abduces 0.628.
!(set-argument-sorts sortRule Agent (Stage Object))
!(set-base-rate sortRule (S $e) (STV 0.4 1))
!(set-base-rate sortRule (R $e) (STV 0.3 1))
!(compileadd sortRule (: a1 (Agent e1 Bob) (STV 1 1)))
!(compileadd sortRule (: r1 (R e1) (STV 1 1)))
!(compileadd sortRule (: rw (Implication (R $e) (W $e)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortRule (: aw (Implication (And (Agent $e $x) (S $e)) (W $e)) (CTV (STV 0.8 1) (STV 0.25 1))))
!(test (query 2000 sortRule (: $p (S e1) $tv)) (: (population-prior (S $_0)) (S e1) (STV 0.4 1)))
!(set-base-rate sortRuleUndeclared (S $e) (STV 0.4 1))
!(set-base-rate sortRuleUndeclared (R $e) (STV 0.3 1))
!(compileadd sortRuleUndeclared (: a1 (Agent e1 Bob) (STV 1 1)))
!(compileadd sortRuleUndeclared (: r1 (R e1) (STV 1 1)))
!(compileadd sortRuleUndeclared (: rw (Implication (R $e) (W $e)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortRuleUndeclared (: aw (Implication (And (Agent $e $x) (S $e)) (W $e)) (CTV (STV 0.8 1) (STV 0.25 1))))
!(test (query 2000 sortRuleUndeclared (: $p (S e1) $tv))
   (: ((antecedent-completion aw 1 with cpu (prior (STV 0.4 1))) (conjunction a1 (by rw r1))) (S e1) (STV 0.62786029706945 0.9998672046805047)))

;; #139: a compound of stages is a stage. Q t1 predicts W, which is no
;; evidence about (Or (R t1) (S t1)): no answer, where the aggregate abduced
;; 0.846. An observed W t2 updates its prior 1 - 0.7 * 0.6 = 0.58 to
;; 0.9 * 0.58 / (0.9 * 0.58 + 0.1 * 0.42) = 0.9255 (exact).
!(set-predicate-time sortCompound S 1 0)
!(set-predicate-time sortCompound R 1 0)
!(set-base-rate sortCompound (R $t) (STV 0.3 1))
!(set-base-rate sortCompound (S $t) (STV 0.4 1))
!(set-base-rate sortCompound (Q $t) (STV 0.5 1))
!(compileadd sortCompound (: qw (Implication (Q $t) (W $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortCompound (: rsw (Implication (Or (R $t) (S $t)) (W $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd sortCompound (: q1 (Q t1) (STV 1 1)))
!(compileadd sortCompound (: w2 (W t2) (STV 1 1)))
!(test (collapse (query 2000 sortCompound (: $p (Or (R t1) (S t1)) $tv))) ())
!(test (query 2000 sortCompound (: $p (Or (R t2) (S t2)) $tv))
   (: ((inverted rsw with cpu (prior (STV 0.58 0.9999206959442694))) w2) (Or (R t2) (S t2)) (STV 0.925531914893617 0.9999147706674222)))
!(set-predicate-time sortConj C 1 0)
!(set-predicate-time sortConj O 1 0)
!(set-base-rate sortConj (C $x) (STV 0.5 1))
!(set-base-rate sortConj (O $x) (STV 0.5 1))
!(compileadd sortConj (: a (A q) (STV 1 1)))
!(compileadd sortConj (: ab (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0.2 1))))
!(compileadd sortConj (: cb (Implication (And (O $x) (C $x)) (B $x)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(test (collapse (query 2000 sortConj (: $p (And (O q) (C q)) $tv))) ())

;; set-predicate-time declares its position Time, so the constants stated
;; there are time points and every statement mentioning one is a stage (D3).
;; Storm's facts make t1 and t2 time points: Q t1 predicts W, which is no
;; evidence about L t1, which keeps its prior 0.4 (the aggregate abduced
;; 0.778); an observed W t2 updates it to 0.9 * 0.4 / (0.9 * 0.4 + 0.1 *
;; 0.6) = 0.857 (exact). t3 is no time point, and L t3 stays an aggregate.
!(set-predicate-time sortTime Storm 2 0)
!(set-base-rate sortTime (L $t) (STV 0.4 1))
!(set-base-rate sortTime (Q $t) (STV 0.5 1))
!(compileadd sortTime (: qw (Implication (Q $t) (W $t)) (CTV (STV 0.9 1) (STV 0.2 1))))
!(compileadd sortTime (: lw (Implication (L $t) (W $t)) (CTV (STV 0.9 1) (STV 0.1 1))))
!(compileadd sortTime (: s1 (Storm north t1) (STV 1 1)))
!(compileadd sortTime (: s2 (Storm north t2) (STV 1 1)))
!(compileadd sortTime (: q1 (Q t1) (STV 1 1)))
!(compileadd sortTime (: q3 (Q t3) (STV 1 1)))
!(compileadd sortTime (: w2 (W t2) (STV 1 1)))
!(test (query 2000 sortTime (: $p (L t1) $tv))
   (: (population-prior (L $_0)) (L t1) (STV 0.4 1)))
!(test (query 2000 sortTime (: $p (L t2) $tv))
   (: ((inverted lw with cpu (prior (STV 0.4 1))) w2) (L t2) (STV 0.8571428571428572 0.9998374408757003)))
!(test (query 2000 sortTime (: $p (L t3) $tv))
   (: ((inverted lw with cpu (prior (STV 0.4 1))) (by qw q3)) (L t3) (STV 0.7783251231527094 0.9998738296388164)))
!(set-bayes-prior-count 0.2)

;; D2: a constant is never both a stage or time and an object or concept.
;; Swapped role arguments are rejected before anything of them is stored or
;; recorded, its heads' arities included; Object with Concept (punning) and
;; Stage with Time are allowed. A rule variable at both kinds of position is
;; rejected.
!(set-argument-sorts sortRoles Agent (Stage Object))
!(compileadd sortRoles (: a1 (Agent e1 Bob) (STV 1 1)))
!(test (let (Error $error $_context) (catch (compileadd sortRoles (: a2 (Agent Bob e1) (STV 1 1)))) (repr $error))
   "(domain_error sort_conflict (Bob Object Stage))")
!(test (collapse (query 100 sortRoles (: $p (Agent $e $x) $tv))) ((: a1 (Agent e1 Bob) (STV 1 1))))
!(test (stage-statement? sortRoles (Happy Bob) ()) false)
!(test (let (Error $error $_context) (catch (compileadd sortRoles (: a3 (And (Agent Bob e1) (Foo a)) (STV 1 1)))) (repr $error))
   "(domain_error sort_conflict (Bob Object Stage))")
!(test (compileadd sortRoles (: foo (Foo a b) (STV 1 1))) (: (sortRoles MAIN Nil) foo (Foo a b) (STV 1 1)))
!(test (let (Error $error $_context) (catch (set-constant-sort sortRoles e1 Concept)) (repr $error))
   "(domain_error sort_conflict (e1 Stage Concept))")
!(test (set-constant-sort sortRoles Bob Concept) true)
!(test (set-constant-sort sortRoles e1 Time) true)
!(test (let (Error $error $_context)
          (catch (compileadd sortRoles (: chain (Implication (Agent $e $x) (Agent $x $e)) (STV 1 1))))
          (repr $error))
   "(domain_error sort_conflict ($_0 Object Stage))")

;; Declaration errors.
!(test (let (Error $error $_context) (catch (set-argument-sorts sortRoles Seen (Stage Event))) (repr $error))
   "(domain_error argument_sorts (Seen (Stage Event)))")
!(test (let (Error $error $_context) (catch (set-argument-sorts sortRoles Seen Stage)) (repr $error))
   "(domain_error argument_sorts (Seen Stage))")
!(test (let (Error $error $_context) (catch (set-argument-sorts sortRoles Agent (Stage))) (repr $error))
   "(domain_error predicate_arity (Agent 1 2))")
!(test (let (Error $error $_context) (catch (set-argument-sorts sortRoles Member (Object Concept))) (repr $error))
   "(domain_error predicate_head Member)")
!(test (let (Error $error $_context) (catch (set-constant-sort sortRoles (f x) Stage)) (repr $error))
   "(domain_error constant_sort ((f x) Stage))")
!(test (let (Error $error $_context) (catch (set-constant-sort sortRoles x Value)) (repr $error))
   "(domain_error constant_sort (x Value))")
