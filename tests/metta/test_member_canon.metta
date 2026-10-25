!(import! &self ../../pettachainer/metta/petta_chainer)

;; (Member x P) is the unary statement (P x) (#96): a fact, rule premise or
;; conclusion in either form meets a query in the other, and an answer keeps
;; the written shape of its query.

;; k1: a Member fact answers the predicate query.
!(compileadd memberK1 (: f (Member rex Dog) (STV 1 0.9)))
!(test (query 300 memberK1 (: $p (Dog rex) $tv)) (: f (Dog rex) (STV 1 0.9)))

;; k2: a predicate fact answers the Member query, in the Member shape.
!(compileadd memberK2 (: f (Dog rex) (STV 1 0.9)))
!(test (query 300 memberK2 (: $p (Member rex Dog) $tv)) (: f (Member rex Dog) (STV 1 0.9)))

;; k3: a Member fact feeds a predicate rule premise.
!(compileadd memberK3 (: f (Member rex Dog) (STV 1 0.9)))
!(compileadd memberK3 (: r (Implication (Dog $x) (Barks $x)) (STV 0.8 0.9)))
!(test (query 300 memberK3 (: $p (Barks rex) $tv)) (: (by r f) (Barks rex) (STV 0.8 0.8999998087111694)))

;; k4: a predicate fact feeds a Member rule premise.
!(compileadd memberK4 (: f (Dog rex) (STV 1 0.9)))
!(compileadd memberK4 (: r (Implication (Member $x Dog) (Barks $x)) (STV 0.8 0.9)))
!(test (query 300 memberK4 (: $p (Barks rex) $tv)) (: (by r f) (Barks rex) (STV 0.8 0.8999998087111694)))

;; k5: two names in the two forms are two observations of one statement and
;; revise, read the same in either form. One name restated in the other form
;; is the same fact: a different value under it is rejected.
!(compileadd memberK5 (: f1 (Dog rex) (STV 1 0.9)))
!(compileadd memberK5 (: f2 (Member rex Dog) (STV 1 0.9)))
!(test (query 300 memberK5 (: $p (Dog rex) $tv)) (: (merge/revision f2 f1) (Dog rex) (STV 1.0 0.9473684210526316)))
!(test (query 300 memberK5 (: $p (Member rex Dog) $tv)) (: (merge/revision f2 f1) (Member rex Dog) (STV 1.0 0.9473684210526316)))
!(test (let (Error $error $_context) (catch (compileadd memberK5 (: f1 (Member rex Dog) (STV 0.5 0.9)))) (repr $error))
   "(permission_error restate proof f1)")

;; An open class reads every class of the object, answered in the query's form.
!(compileadd memberOpen (: a (Member rex Dog) (STV 1 0.9)))
!(compileadd memberOpen (: b (Pet rex) (STV 1 0.8)))
!(compileadd memberOpen (: r (Implication (Member $x Dog) (Barker $x)) (STV 0.9 0.9)))
!(test (collapse (query 300 memberOpen (: $p (Member rex $c) $tv)))
   ((: a (Member rex Dog) (STV 1 0.9))
    (: b (Member rex Pet) (STV 1 0.8))
    (: (by r a) (Member rex Barker) (STV 0.9 0.8999995899311523))))

;; A Member conclusion with a class variable concludes the predicate key.
!(compileadd memberConcl (: a (Adopts bob rex Dog) (STV 1 1)))
!(compileadd memberConcl (: r (Implication (Adopts $y $x $c) (Member $x $c)) (STV 0.9 0.9)))
!(test (query 300 memberConcl (: $p (Dog rex) $tv)) (: (by r a) (Dog rex) (STV 0.9 0.8999999996308867)))

;; A negated Member fact is stored on the class key; a Member written inside a
;; negation answers in its written shape.
!(compileadd memberNot (: f (Not (Member rex Dog)) (STV 0.8 0.9)))
!(test (query 100 memberNot (: $p (Dog rex) $tv)) (: f (Dog rex) (STV 0.19999999999999996 0.9)))
!(test (query 100 memberNot (: $p (Not (Member rex Dog)) $tv)) (: (negated f) (Not (Member rex Dog)) (STV 0.8 0.9)))

;; D6: a class is a symbol or a variable.
!(test (let (Error $error $_context) (catch (compileadd memberExprClass (: f (Member rex (Big Dog)) (STV 1 0.9)))) (repr $error))
   "(domain_error member_class (Member rex (Big Dog)))")

;; D4: one arity per head, a class included.
!(compileadd memberArity (: f (Member e TennisPlaying) (STV 1 0.9)))
!(test (let (Error $error $_context) (catch (compileadd memberArity (: g (TennisPlaying Bob d1) (STV 1 0.9)))) (repr $error))
   "(domain_error predicate_arity (TennisPlaying 2 1))")
!(test (let (Error $error $_context) (catch (compileadd memberArity2 (: r (Implication (P $x) (P $x $y)) (STV 1 0.9)))) (repr $error))
   "(domain_error predicate_arity (P 1 2))")

;; D5: declarations name a class, never Member.
!(test (let (Error $error $_context) (catch (set-positive-only-predicate memberDecl Member)) (repr $error))
   "(domain_error predicate_head Member)")

;; A Member anywhere in a statement is rewritten: a KnownExistential body,
;; the implication of a RuleTruth goal, and a statement quoted as a predicate
;; argument that a rule concludes.
!(compileadd memberKnown (: f (Member rex Dog) (STV 1 0.9)))
!(compileadd memberKnown (: r (Implication (KnownExistential ($y) (Member $y Dog)) (HasDog)) (STV 1 1)))
!(test (query 200 memberKnown (: $p (HasDog) $tv)) (: (by r (disjunction f)) (HasDog) (STV 1.0 0.9472821281194718)))
!(set-rule-refinement memberTruth true)
!(compileadd memberTruth (: r (Implication (Member $x Dog) (Barks $x)) (STV 0.9 0.9)))
!(compileadd memberTruth (: f1 (Dog rex) (STV 1 1)))
!(compileadd memberTruth (: f2 (Barks rex) (STV 1 1)))
!(test (let (: $_p $_s $tv) (query 200 memberTruth (: $p (RuleTruth (Implication (Dog $x) (Barks $x))) $tv)) $tv)
   (STV 0.9000138869601445 0.9000124984376953))
!(test (let (: $_p $_s $tv) (query 200 memberTruth (: $p (RuleTruth (Implication (Member $x Dog) (Barks $x))) $tv)) $tv)
   (STV 0.9000138869601445 0.9000124984376953))
!(compileadd memberClaims (: c (Claims bob (Member rex Dog)) (STV 1 1)))
!(compileadd memberClaims (: r (Implication (Claims $p $s) $s) (STV 0.9 0.9)))
!(test (query 200 memberClaims (: $p (Member rex Dog) $tv)) (: (by r c) (Member rex Dog) (STV 0.9 0.8999999996308867)))
!(test (query 200 memberClaims (: $p (Dog rex) $tv)) (: (by r c) (Dog rex) (STV 0.9 0.8999999996308867)))

;; A class naming a connective, computation or internal key is rejected, in a
;; fact and in a query.
!(test (let (Error $error $_context) (catch (compileadd memberReserved (: f (Member rex Not) (STV 1 0.9)))) (repr $error))
   "(domain_error member_class (Member rex Not))")
!(test (let (Error $error $_context) (catch (query 100 memberReserved (: $p (Member rex And) $tv))) (repr $error))
   "(domain_error member_class (Member rex And))")

;; A fully open class answers the classes and never an internal key.
!(compileadd memberOpenAll (: a (Member rex Dog) (STV 1 0.9)))
!(compileadd memberOpenAll (: e (Exists ($z) (Cat $z)) (STV 0.7 0.9)))
!(test (collapse (query 200 memberOpenAll (: $p (Member $x $c) $tv))) ((: a (Member rex Dog) (STV 1 0.9))))

;; A class named like a MeTTa function stays data.
!(compileadd memberFunctionName (: f (Member rex length) (STV 1 0.8)))
!(compileadd memberFunctionName (: r (Implication (Member $x length) (Barks $x)) (STV 0.9 0.9)))
!(test (query 200 memberFunctionName (: $p (Member rex length) $tv)) (: f (Member rex length) (STV 1 0.8)))
!(test (let (: $_p $_s $tv) (query 200 memberFunctionName (: $p (Barks rex) $tv)) $tv) (STV 0.9 0.89999907750575))
