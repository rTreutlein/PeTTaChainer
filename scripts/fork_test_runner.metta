!(import! &self ../pettachainer/metta/petta_chainer)
!(callPredicate
   (Predicate (quote (consult ../../scripts/fork_test_runner.pl))))
!(callPredicate (Predicate (run_forked_tests)))
