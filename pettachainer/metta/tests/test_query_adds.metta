!(import! &self petta_chainer)

!(compileadd queryAddsKb (: pa (A) (STV 1.0 1.0)))

!(compileadd queryAddsKb (: pb (B) (STV 1.0 1.0)))

!(test (not (== (collapse (query 10 queryAddsKb (: $p (A) $tv))) ())) true)

!(test (not (== (collapse (query 10 queryAddsKb (: $p (B) $tv))) ())) true)

!(test (not (== (collapse (query 10 queryAddsKb (: $p (And (A) (B)) $tv))) ())) true)
