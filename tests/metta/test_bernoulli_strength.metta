!(import! &self ../../pettachainer/metta/petta_chainer)
;; Confidence describes uncertainty about the mean, not event frequency.
!(test (ParticlePairs (ParticleAddBernoulliFromSTV (PointMass 0) (STV 0.8 0.25)))
   ((0 0.19999999999999996) (1 0.8)))
!(test (ParticlePairs (ParticleAddBernoulliFromSTV (PointMass 0) (STV 0.8 0)))
   ((0 0.19999999999999996) (1 0.8)))
!(test (ParticlePairs (ParticleAddBernoulliFromSTV (PointMass 0) (STV 0.8 1)))
   ((0 0.19999999999999996) (1 0.8)))
