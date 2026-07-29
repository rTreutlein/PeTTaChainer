!(import! &self petta_chainer)

!(compileadd directCompoundKb
   (: dog-fact (Dog max) (STV 1.0 1.0)))

!(test
   (query 10 directCompoundKb
      (: $proof (Dog max) $tv))
   (: dog-fact (Dog max) (STV 1.0 1.0)))
