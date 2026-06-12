!(import! &self petta_chainer)

!(compileadd queryAddsKb (: pa (A) (STV 1.0 1.0)))

!(compileadd queryAddsKb (: pb (B) (STV 1.0 1.0)))

!(test (query 10 queryAddsKb (: $p (A) $tv))
   (: pa (A) (STV 1.0 1.0)))

!(test (query 10 queryAddsKb (: $p (B) $tv))
   (: pb (B) (STV 1.0 1.0)))

!(test (query 10 queryAddsKb (: $p (And (A) (B)) $tv))
   (: (conjunction pa pb) (And (A) (B)) (STV 1.0 1.0)))

!(compileadd queryAddsKb2 (: pa2 (A) (STV 1.0 1.0)))

!(compileadd queryAddsKb2 (: pb2 (B) (STV 1.0 1.0)))

!(compileadd queryAddsKb2 (: pc2 (And (C) (D)) (STV 1.0 1.0)))

!(test (query 10 queryAddsKb2 (: $p (And (A) (B)) $tv))
   (: (conjunction pa2 pb2) (And (A) (B)) (STV 1.0 1.0)))

!(compileadd queryAddsKb3 (: pa3 (A) (STV 1.0 1.0)))

!(compileadd queryAddsKb3 (: pb3 (B) (STV 1.0 1.0)))

!(compileadd queryAddsKb3 (: pc3 (And (A) (D)) (STV 1.0 1.0)))

!(test (query 10 queryAddsKb3 (: $p (And (A) (B)) $tv))
   (: (conjunction pa3 pb3) (And (A) (B)) (STV 1.0 1.0)))
