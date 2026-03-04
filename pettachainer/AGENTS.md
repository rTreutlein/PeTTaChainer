To run metta code use the petta executable example: "petta test.metta"

When writing metta code take care not to introduce unintended non determinism.
Example:
(= (f  a) a)
(= (f $var) b)

!(f a)
=>
(a b)

