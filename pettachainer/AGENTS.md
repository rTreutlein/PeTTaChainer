To run metta code use the petta executable example: "petta test.metta"

When writing metta code take care not to introduce unintended non determinism.
Example:
(= (f  a) a)
(= (f $var) b)

!(f a)
=>
(a b)

If you change something never leave any old code around for backwards compatibility.
Always delete all old code. If the old code was good we would't have needed the new one.

If you have to choose between 2 ways to do something always pick the one that is cleaner and better in the long term.
Don't take any shortcuts. Hard things are worth doing right. And the best solution is usually the simplest but getting there takes effort.
