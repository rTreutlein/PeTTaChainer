!(import! &self ../petta_chainer)

!(test (check-stmt (: s1 (Dog fido) (STV 1.0 1.0))) 1.0)
!(test (check-stmt (: s2 (HeightDist g1 alice) (PointMass 170.0))) 1.0)
!(test (check-stmt (: s3 (CountDist g1) (NatDist ((0 0.5) (1 0.5))))) 1.0)
!(test (check-stmt (: s3f (CountDist g1) (FloatDist ((0.0 0.5) (1.0 0.5))))) 1.0)
!(test (check-stmt (: s4r (CountDist g1) (ParticleDist 0))) 1.0)
!(test (check-stmt (: s4 (CountDist g1) (ParticleDist 0 1.0))) 1.0)
!(test (check-stmt (: s4n (CountDist g1) (ParticleFromNormal 0.0 1.0))) 1.0)
!(test (check-stmt (: s4p (CountDist g1) (ParticleFromPairs ((0.0 1.0))))) 1.0)
!(test
   (check-stmt
      (: r1
         (Implication (Dog $x) (Animal $x))
         (CTV (STV 0.9 0.8) (STV 0.1 0.7))))
   1.0)

!(test (check-stmt (: $prf (Dog fido) (STV 1.0 1.0))) 0.0)
!(test (check-stmt (: s5 (Dog fido) (CustomTV 0.9))) 0.0)
!(test (check-stmt (: r2 (Rule) (CTV (STV 0.9 0.8)))) 0.0)
!(test (check-stmt (: r3 (Rule) (CTV (STV 0.9 0.8) (CustomTV 0.1)))) 0.0)
!(test (check-stmt (: r4 (Rule) (CTV (PointMass 0.9) (STV 0.1 0.7)))) 0.0)
!(test (check-stmt (Dog fido)) 0.0)

!(test (check-query (: $prf (Dog fido) $tv)) 1.0)
!(test (check-query (: proof1 (Dog fido) $tv)) 0.0)
!(test (check-query (Dog fido)) 0.0)

!(compileadd validatorDynamicKb (: dynamicDog (Dog fido) (STV 1.0 1.0)))
!(test
   (let $runtime-query (sread "(: $proof (Dog fido) $tv)")
      (query-dynamic 20 validatorDynamicKb $runtime-query))
   (: dynamicDog (Dog fido) (STV 1.0 1.0)))
