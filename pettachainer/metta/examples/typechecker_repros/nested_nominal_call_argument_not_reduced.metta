;; A nested function call returning a nominal type must be evaluated before
;; its value is passed to another function accepting that nominal type.

(: Role (Newtype Expression))
(: role (-> Number Role))

(: Holder (Newtype Expression))
(: holder (-> Role Holder))

(: holder-role (-[det]-> Holder Role))
(= (holder-role (holder $role)) $role)

(: expected-role? (-[det]-> Role Bool))
(= (expected-role? $role)
   (== $role (role 1)))

(: holder-has-expected-role? (-[det]-> Holder Bool))
(= (holder-has-expected-role? $holder)
   (expected-role? (holder-role $holder)))

!(test
   (holder-has-expected-role?
      (holder (role 1)))
   true)
