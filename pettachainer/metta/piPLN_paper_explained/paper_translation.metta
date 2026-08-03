!(import! &self ../petta_chainer)

; piPLN: Paraconsistent-PLN Without a Global Probability Space
; ----------------------------------------------------------------------
; This file is a runnable translation of the paper's core math into MeTTa.
; The comments paraphrase the paper. The code below each comment replaces
; the displayed formula with executable terms and tests.

(= (Between $x $lo $hi) (and (> $x $lo) (< $x $hi)))
(= (ApproxEq $x $target $eps) (and (> $x (- $target $eps)) (< $x (+ $target $eps))))

; ----------------------------------------------------------------------
; Sections 7.1-7.4: persistent state, contexts, local charts, projection
; ----------------------------------------------------------------------
; The paper says the durable state is not one probability distribution.
; It is a context-indexed evidence metagraph. The simple cached aggregate
; used by old PLN-style formulas is a p-bit:
;
;   evidence(statement, context) = (positive-count, negative-count)
;
; Provenance packets are primary in the paper. Here we keep the runnable
; core as an aggregate evidence count and model provenance later in the
; product control quantale.

(= (ECUnit) (EC 0.0 0.0))
(= (ECPositive (EC $pos $_neg)) $pos)
(= (ECNegative (EC $_pos $neg)) $neg)
(= (ECTotal (EC $pos $neg)) (+ $pos $neg))

; A local chart can project raw evidence to a legacy PLN STV.
; The prior p0 and prior weight k belong to the context, not to storage.
;
;   s = (n+ + k p0) / (n+ + n- + k)
;   c = (n+ + n-) / (n+ + n- + k)

(= (ECToSTV (EC $pos $neg) $p0 $k)
   (let* (($n (+ $pos $neg))
          ($den (+ $n $k))
          ($s (if (== $den 0.0) $p0 (/ (+ $pos (* $k $p0)) $den)))
          ($c (if (== $den 0.0) 0.0 (/ $n $den))))
      (STV $s $c)))

!(test
   (let (STV $s $c) (ECToSTV (EC 950.0 50.0) 0.95 2.0)
      (and (Between $s 0.9499 0.9501) (Between $c 0.9980 0.9981)))
   true)

!(test
   (let (STV $s $c) (ECToSTV (EC 0.0 100.0) 0.95 2.0)
      (and (Between $s 0.018 0.019) (Between $c 0.980 0.981)))
   true)

; Section 7.4 also says that if a Bayesian chart exported a prior-smeared
; STV, the prior must be unwound before storing durable evidence.
;
;   empirical-positive = (N + k) s - k p0
;   empirical-negative = N - empirical-positive
;
; rho is a relevance or reliability multiplier for the exported packet.

(= (UnwindPriorSTV $s $N $p0 $k $rho)
   (let* (($raw-pos (- (* (+ $N $k) $s) (* $k $p0)))
          ($raw-neg (- $N $raw-pos)))
      (EC (* $rho $raw-pos) (* $rho $raw-neg))))

!(test (UnwindPriorSTV 0.95 1000.0 0.95 2.0 1.0) (EC 950.0 50.0))

; ----------------------------------------------------------------------
; Section 8.1: evidence-count quantale
; ----------------------------------------------------------------------
; The paper's primary operational evidence quantale is:
;
;   Q_cnt = ([0, infinity]^2, <=, join, tensor, e)
;   (n+, n-) <= (m+, m-) iff n+ <= m+ and n- <= m-
;   join((n+, n-), (m+, m-)) = (max(n+, m+), max(n-, m-))
;   tensor((n+, n-), (m+, m-)) = (n+ + m+, n- + m-)
;   e = (0, 0)
;
; join combines alternative evidence bounds. tensor composes independent
; or provenance-disjoint evidence.

(= (ECOrder? (EC $p1 $n1) (EC $p2 $n2))
   (and (<= $p1 $p2) (<= $n1 $n2)))

(= (ECJoin (EC $p1 $n1) (EC $p2 $n2))
   (EC (max $p1 $p2) (max $n1 $n2)))

(= (ECTensor (EC $p1 $n1) (EC $p2 $n2))
   (EC (+ $p1 $p2) (+ $n1 $n2)))

!(test (ECOrder? (EC 1.0 2.0) (EC 1.0 3.0)) true)
!(test (ECJoin (EC 2.0 10.0) (EC 5.0 1.0)) (EC 5.0 10.0))
!(test (ECTensor (EC 2.0 10.0) (EC 5.0 1.0)) (EC 7.0 11.0))
!(test (ECTensor (ECUnit) (EC 3.0 4.0)) (EC 3.0 4.0))

; ----------------------------------------------------------------------
; Section 8.3: projection to beta posteriors
; ----------------------------------------------------------------------
; The beta posterior is another local projection of the same evidence.
;
;   alpha0 = k p0
;   beta0  = k (1 - p0)
;   BetaProjection(n+, n-) = Beta(alpha0 + n+, beta0 + n-)
;
; Its mean equals the STV strength above.

(= (ECToBeta (EC $pos $neg) $p0 $k)
   (Beta (+ (* $k $p0) $pos)
         (+ (* $k (- 1.0 $p0)) $neg)))

(= (BetaMean (Beta $alpha $beta)) (/ $alpha (+ $alpha $beta)))

!(test (ECToBeta (EC 0.0 100.0) 0.95 2.0) (Beta 1.9 100.1))

!(test
   (let* (((STV $s $_c) (ECToSTV (EC 0.0 100.0) 0.95 2.0))
          ($mean (BetaMean (ECToBeta (EC 0.0 100.0) 0.95 2.0))))
      (ApproxEq $s $mean 0.000001))
   true)

; ----------------------------------------------------------------------
; Section 8.4: count addition as Bayesian likelihood multiplication
; ----------------------------------------------------------------------
; For Bernoulli theta, evidence (n+, n-) corresponds to:
;
;   L(theta) = theta^n+ (1 - theta)^n-
;
; Multiplying independent likelihoods adds the exponents. So ECTensor is
; Bayesian likelihood multiplication in sufficient-statistic coordinates.

(= (BernoulliLikelihoodShape (EC $pos $neg))
   (LikelihoodExponents theta $pos one-minus-theta $neg))

!(test
   (BernoulliLikelihoodShape (ECTensor (EC 2.0 3.0) (EC 5.0 7.0)))
   (LikelihoodExponents theta 7.0 one-minus-theta 10.0))

; ----------------------------------------------------------------------
; Section 8.5: bounded p-bit propagation quantale
; ----------------------------------------------------------------------
; Bounded propagation uses values in [0,1]^2. Tensor is componentwise
; probabilistic sum:
;
;   a tensor b = a + b - ab
;
; This accumulates independent bounded support instead of diluting it.

(= (ProbSum $a $b) (- (+ $a $b) (* $a $b)))

(= (BPUnit) (BP 0.0 0.0))

(= (BPJoin (BP $p1 $n1) (BP $p2 $n2))
   (BP (max $p1 $p2) (max $n1 $n2)))

(= (BPTensor (BP $p1 $n1) (BP $p2 $n2))
   (BP (ProbSum $p1 $p2) (ProbSum $n1 $n2)))

!(test (BPTensor (BP 0.2 0.8) (BP 0.5 0.5)) (BP 0.6 0.9))
!(test (BPTensor (BPUnit) (BP 0.7 0.1)) (BP 0.7 0.1))

; The paper's change-of-base map from raw counts to bounded values is:
;
;   rho_lambda(n+, n-) = (1 - exp(-n+/lambda), 1 - exp(-n-/lambda))
;
; MeTTa's small executable example below uses a lambda=1 lookup for the
; counts needed by the test. It demonstrates the homomorphism:
;
;   rho(a tensor_count b) = rho(a) tensor_bounded rho(b)

(= (Rho1Coord 0.0) 0.0)
(= (Rho1Coord 1.0) 0.6321205588285577)
(= (Rho1Coord 2.0) 0.8646647167633873)
(= (Rho1Coord 3.0) 0.950212931632136)

(= (Rho1 (EC $pos $neg)) (BP (Rho1Coord $pos) (Rho1Coord $neg)))

!(test
   (let* (((BP $left-pos $left-neg) (Rho1 (ECTensor (EC 1.0 0.0) (EC 2.0 0.0))))
          ((BP $right-pos $right-neg) (BPTensor (Rho1 (EC 1.0 0.0)) (Rho1 (EC 2.0 0.0)))))
      (and (ApproxEq $left-pos $right-pos 0.000001)
           (ApproxEq $left-neg $right-neg 0.000001)))
   true)

; ----------------------------------------------------------------------
; Section 8.6: evidence order versus truth order
; ----------------------------------------------------------------------
; Evidence order: more positive and more negative evidence both mean more
; information.
;
;   (x+, x-) <=K (y+, y-) iff x+ <= y+ and x- <= y-
;
; Truth order: more positive evidence means truer, but more negative
; evidence means less true.
;
;   (x, x') <=T (y, y') iff x <= y and y' <= x'

(= (BPEvidenceOrder? (BP $p1 $n1) (BP $p2 $n2))
   (and (<= $p1 $p2) (<= $n1 $n2)))

(= (BPTruthOrder? (BP $p1 $n1) (BP $p2 $n2))
   (and (<= $p1 $p2) (<= $n2 $n1)))

!(test (BPEvidenceOrder? (BP 0.2 0.8) (BP 0.3 0.9)) true)
!(test (BPTruthOrder? (BP 0.2 0.8) (BP 0.3 0.7)) true)
!(test (BPTruthOrder? (BP 0.2 0.8) (BP 0.3 0.9)) false)

; ----------------------------------------------------------------------
; Section 8.7: CD logic quantale
; ----------------------------------------------------------------------
; CD-style paraconsistent logic uses H x H^op. With numeric [0,1] as H:
;
;   join_T((x,x'),(y,y')) = (max(x,y), min(x',y'))
;   tensor_T((x,x'),(y,y')) = (min(x,y), max(x',y'))
;   unit = (1,0)
;
; This is useful for proof/disproof logic. It is not the same as the
; evidence-count quantale used for durable storage.

(= (CDUnit) (CD 1.0 0.0))

(= (CDJoin (CD $p1 $n1) (CD $p2 $n2))
   (CD (max $p1 $p2) (min $n1 $n2)))

(= (CDTensor (CD $p1 $n1) (CD $p2 $n2))
   (CD (min $p1 $p2) (max $n1 $n2)))

!(test (CDJoin (CD 0.2 0.8) (CD 0.7 0.4)) (CD 0.7 0.4))
!(test (CDTensor (CD 0.9 0.1) (CD 0.6 0.8)) (CD 0.6 0.8))
!(test (CDTensor (CDUnit) (CD 0.3 0.9)) (CD 0.3 0.9))

; ----------------------------------------------------------------------
; Section 8.8: local event quantale
; ----------------------------------------------------------------------
; Inside a finite local chart, events form a Boolean algebra:
;
;   Q_event = (events, subset, union, intersection, whole-chart)
;
; Here an event is a four-bit set of worlds:
;
;   Event ab a-not-b not-a-b not-a-not-b
;
; The probability valuation is not generally a quantale homomorphism from
; intersection to multiplication. P(A and B) = P(A)P(B) only under local
; independence assumptions.

(= (EventUnit) (Event 1.0 1.0 1.0 1.0))
(= (EventBottom) (Event 0.0 0.0 0.0 0.0))
(= (EventA) (Event 1.0 1.0 0.0 0.0))
(= (EventB) (Event 1.0 0.0 1.0 0.0))

(= (EventJoin (Event $a1 $b1 $c1 $d1) (Event $a2 $b2 $c2 $d2))
   (Event (max $a1 $a2) (max $b1 $b2) (max $c1 $c2) (max $d1 $d2)))

(= (EventMeet (Event $a1 $b1 $c1 $d1) (Event $a2 $b2 $c2 $d2))
   (Event (min $a1 $a2) (min $b1 $b2) (min $c1 $c2) (min $d1 $d2)))

(= (EventProbUniform (Event $a $b $c $d)) (/ (+ (+ $a $b) (+ $c $d)) 4.0))
(= (EventProbProduct $event-a $event-b)
   (* (EventProbUniform $event-a) (EventProbUniform $event-b)))

!(test (EventMeet (EventA) (EventB)) (Event 1.0 0.0 0.0 0.0))
!(test (EventProbUniform (EventMeet (EventA) (EventB))) 0.25)
!(test (EventProbProduct (EventA) (EventB)) 0.25)

; Same event twice is not independent: P(A and A) = 0.5, but P(A)P(A)=0.25.
!(test (EventProbUniform (EventMeet (EventA) (EventA))) 0.5)
!(test (EventProbProduct (EventA) (EventA)) 0.25)

; ----------------------------------------------------------------------
; Section 8.9: product control quantale
; ----------------------------------------------------------------------
; Practical inference control carries more than a truth value:
;
;   Q_piPLN = Q_assump x Q_cnt x Q_weak x Q_cost x Q_prov
;
; This example uses two-bit assumption/provenance sets so it is fully
; executable without a general set library.
;
; Sequential composition:
;   assumptions union, evidence tensor, weakness multiply, cost add,
;   provenance union.
;
; Alternative derivations:
;   assumptions union, evidence join, weakness max, cost min,
;   provenance union.

(= (BitUnion2 (Bits $a1 $b1) (Bits $a2 $b2))
   (Bits (max $a1 $a2) (max $b1 $b2)))

(= (PiTensor
      (PiLabel $assump-a $evidence-a $weak-a $cost-a $prov-a)
      (PiLabel $assump-b $evidence-b $weak-b $cost-b $prov-b))
   (PiLabel
      (BitUnion2 $assump-a $assump-b)
      (ECTensor $evidence-a $evidence-b)
      (* $weak-a $weak-b)
      (+ $cost-a $cost-b)
      (BitUnion2 $prov-a $prov-b)))

(= (PiJoin
      (PiLabel $assump-a $evidence-a $weak-a $cost-a $prov-a)
      (PiLabel $assump-b $evidence-b $weak-b $cost-b $prov-b))
   (PiLabel
      (BitUnion2 $assump-a $assump-b)
      (ECJoin $evidence-a $evidence-b)
      (max $weak-a $weak-b)
      (min $cost-a $cost-b)
      (BitUnion2 $prov-a $prov-b)))

!(test
   (PiTensor
      (PiLabel (Bits 1.0 0.0) (EC 2.0 0.0) 0.8 3.0 (Bits 1.0 0.0))
      (PiLabel (Bits 0.0 1.0) (EC 0.0 1.0) 0.5 4.0 (Bits 0.0 1.0)))
   (PiLabel (Bits 1.0 1.0) (EC 2.0 1.0) 0.4 7.0 (Bits 1.0 1.0)))

!(test
   (PiJoin
      (PiLabel (Bits 1.0 0.0) (EC 2.0 9.0) 0.8 10.0 (Bits 1.0 0.0))
      (PiLabel (Bits 0.0 1.0) (EC 5.0 1.0) 0.5 4.0 (Bits 0.0 1.0)))
   (PiLabel (Bits 1.0 1.0) (EC 5.0 9.0) 0.8 4.0 (Bits 1.0 1.0)))

; ----------------------------------------------------------------------
; Sections 7.2-7.3 and 9.3: what a local chart is operationally
; ----------------------------------------------------------------------
; A chart is a temporary inference object. It is not the persistent
; knowledge state. It is constructed for a task/query from:
;
;   - selected evidence context
;   - local prior and virtual count
;   - assumption package
;   - selected evidence projection
;
; In the paper's notation:
;
;   ChartConstructor(K_t, T_C) = (Omega_C, F_C, pi_C, M_C, D_C, iota_C)
;
; The small executable version below does not build a full probability
; space. It shows the PeTTaChainer-facing interface: choose a local evidence
; packet, attach the local chart assumptions, and project to an STV only
; inside that chart.

(= (PersistentEvidence flies bird-flight-context) (EC 950.0 50.0))
(= (PersistentEvidence flies penguin-flight-context) (EC 0.0 100.0))

; A task context tells the chart constructor what evidence context and
; assumptions are relevant for this query.
(= (TaskContext robin-fly-query)
   (QueryContext bird-flight-context 0.95 2.0
      (Assumptions temperate-aviary same-bird-boundary)))

(= (TaskContext tweety-fly-query)
   (QueryContext penguin-flight-context 0.95 2.0
      (Assumptions antarctic-penguin-study penguin-boundary)))

(= (BuildFlyChart $task)
   (let (QueryContext $evidence-ctx $p0 $k $assumptions) (TaskContext $task)
      (LocalChart $task
         $evidence-ctx
         (PersistentEvidence flies $evidence-ctx)
         $p0
         $k
         $assumptions)))

(= (ChartEvidenceOf
      (LocalChart $_task $_evidence-ctx $evidence $_p0 $_k $_assumptions))
   $evidence)

(= (ChartAssumptionsOf
      (LocalChart $_task $_evidence-ctx $_evidence $_p0 $_k $assumptions))
   $assumptions)

(= (ChartProjectSTV
      (LocalChart $_task $_evidence-ctx $evidence $p0 $k $_assumptions))
   (ECToSTV $evidence $p0 $k))

(= (RunFlyChart $task) (ChartProjectSTV (BuildFlyChart $task)))

!(test
   (BuildFlyChart robin-fly-query)
   (LocalChart robin-fly-query
      bird-flight-context
      (EC 950.0 50.0)
      0.95
      2.0
      (Assumptions temperate-aviary same-bird-boundary)))

!(test
   (ChartAssumptionsOf (BuildFlyChart tweety-fly-query))
   (Assumptions antarctic-penguin-study penguin-boundary))

!(test
   (let (STV $s $c) (RunFlyChart robin-fly-query)
      (and (Between $s 0.949 0.951) (> $c 0.997)))
   true)

!(test
   (let (STV $s $c) (RunFlyChart tweety-fly-query)
      (and (Between $s 0.018 0.019) (> $c 0.980)))
   true)

; The key point: chart projection does not rewrite persistent evidence.
; The raw penguin packet is still (0, 100) after the Tweety chart runs.
!(test
   (let $_projection (RunFlyChart tweety-fly-query)
      (PersistentEvidence flies penguin-flight-context))
   (EC 0.0 100.0))

; ----------------------------------------------------------------------
; Section 9 and 16.1: no-global-distribution principle, bird example
; ----------------------------------------------------------------------
; The paper's bird/penguin example shows why context-indexed charts matter.
; Bird evidence and penguin evidence have different scopes. A query about
; Robin uses the bird chart. A query about Tweety the penguin uses the
; penguin chart. Naively merging the evidence gives a sample-mix-dependent
; number, not a conceptually correct global truth.

(= (ChartEvidence bird-flight-chart) (EC 950.0 50.0))
(= (ChartEvidence penguin-flight-chart) (EC 0.0 100.0))

(= (FlyChart bird) bird-flight-chart)
(= (FlyChart penguin) penguin-flight-chart)

(= (FlyProjection $kind)
   (ECToSTV (ChartEvidence (FlyChart $kind)) 0.95 2.0))

(= (NaiveMergedFlyProjection)
   (ECToSTV
      (ECTensor (ChartEvidence bird-flight-chart) (ChartEvidence penguin-flight-chart))
      0.95
      2.0))

!(test
   (let (STV $s $c) (FlyProjection bird)
      (and (Between $s 0.949 0.951) (> $c 0.997)))
   true)

!(test
   (let (STV $s $c) (FlyProjection penguin)
      (and (Between $s 0.018 0.019) (> $c 0.980)))
   true)

!(test
   (let (STV $s $_c) (NaiveMergedFlyProjection)
      (Between $s 0.863 0.865))
   true)

; ----------------------------------------------------------------------
; Section 12.5 plus PeTTaChainer: distributional truth values
; ----------------------------------------------------------------------
; Distributional uncertainty is not the same as truth uncertainty.
; PeTTaChainer already encodes this distinction:
;
;   proposition term carries ParticleDist/NatDist/FloatDist
;   TV slot remains an STV about whether the proposition is asserted
;
; The local chart below asks P(distance > 10) using a ParticleDist.

!(compileadd piplndistkb
   (: everydayDistance
      (ChartDistanceDist everyday-route (ParticleFromPairs ((9 0.2) (10 0.6) (11 0.2))))
      (STV 1.0 1.0)))

!(compileadd piplndistkb
   (: longTripRule
      (Implication
         (And
            (ChartDistanceDist everyday-route $distance)
            (GreaterThan $distance 10))
         (LongTrip everyday-route))
      (STV 1.0 1.0)))

!(test
   (let (: $prf (LongTrip everyday-route) $tv)
      (query 40 piplndistkb (: $prf (LongTrip everyday-route) $tv))
      (let (STV $s $_c) $tv
         (Between $s 0.199 0.201)))
   true)

!(test
   (let (: $prf (ChartDistanceDist everyday-route $distance) $tv)
      (query 20 piplndistkb (: $prf (ChartDistanceDist everyday-route $distance) $tv))
      (ParticlePairs $distance))
   ((9 0.2) (10 0.6) (11 0.2)))
