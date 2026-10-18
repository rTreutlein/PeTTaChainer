!(import! &self ../../pettachainer/metta/petta_chainer)

;; A refined rule applied to an instance reads its truth without the samples
;; that depend on that instance (leave one out), and an instance sample reads
;; no value another refined rule estimates (docs/metta/hypothesis_rules.md,
;; "Cross-feeding"). So what a refined rule applies does not depend on when
;; its truth was reviewed.

;; Two hypotheses with co-extensive antecedents (ChainerGame
;; benchmarks/ona/repros/stale_after_early_review.py), reviewed while each
;; one's only sample was the other's derivation. Before, that review froze
;; both: B new was applied at the prior (0.5, 0.02) for ever after.
!(set-evidence-confidence-k 1)
!(set-rule-refinement earlyKb true)
!(set-positive-only-predicate earlyKb A)
!(set-positive-only-predicate earlyKb C)
!(compileadd earlyKb (: hA (Implication (A $x) (B $x)) (STV 0.5 0.01)))
!(compileadd earlyKb (: hC (Implication (C $x) (B $x)) (STV 0.5 0.01)))
!(compileadd earlyKb (: a0 (A e0) (STV 1 1)))
!(compileadd earlyKb (: c0 (C e0) (STV 1 1)))
;; The other hypothesis's view of B e0 is no sample: the review reads the axiom.
!(test (let (: $p $t $tv) (query 200 earlyKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) ($p $tv))
   ((rule-axiom hA) (STV 0.5 0.01)))
!(compileadd earlyKb (: a1 (A i1) (STV 1 1)))
!(compileadd earlyKb (: c1 (C i1) (STV 1 1)))
!(compileadd earlyKb (: b1 (B i1) (STV 0 1)))
!(compileadd earlyKb (: a2 (A i2) (STV 1 1)))
!(compileadd earlyKb (: c2 (C i2) (STV 1 1)))
!(compileadd earlyKb (: b2 (B i2) (STV 0 1)))
!(compileadd earlyKb (: a3 (A i3) (STV 1 1)))
!(compileadd earlyKb (: c3 (C i3) (STV 1 1)))
!(compileadd earlyKb (: b3 (B i3) (STV 0 1)))
!(compileadd earlyKb (: a4 (A i4) (STV 1 1)))
!(compileadd earlyKb (: c4 (C i4) (STV 1 1)))
!(compileadd earlyKb (: b4 (B i4) (STV 0 1)))
!(test (let (: $p $t $tv) (query 200 earlyKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.0012594458438287151 0.8004032258064516))
!(compileadd earlyKb (: anew (A new) (STV 1 1)))
!(compileadd earlyKb (: cnew (C new) (STV 1 1)))
;; Their samples are the same observations, so applied to one case they are
;; one sample, with both rule proofs retained and confidence capped by the
;; smaller input (docs/metta/overlap_conditioning.md, "Sample twins").
!(test (query 200 earlyKb (: $p (B new) $tv))
   (: (combination revision (prior no-evidence) ((by hA anew) (by hC cnew))) (B new) (STV 0.0012594458438287151 0.8004031861404352)))

;; An observed but uncertain consequent is a sample of the rule, and the rule
;; still applies to it: B new's own sample is left out of the truth hA applies
;; there, three samples, revised with the stored 0.6 (one observation).
;; Before, the truth depended on B new, so B new read the prior.
!(set-rule-refinement softKb true)
!(set-positive-only-predicate softKb A)
!(compileadd softKb (: hA (Implication (A $x) (B $x)) (STV 0.5 0.01)))
!(compileadd softKb (: a1 (A i1) (STV 1 1)))
!(compileadd softKb (: b1 (B i1) (STV 0 1)))
!(compileadd softKb (: a2 (A i2) (STV 1 1)))
!(compileadd softKb (: b2 (B i2) (STV 0 1)))
!(compileadd softKb (: a3 (A i3) (STV 1 1)))
!(compileadd softKb (: b3 (B i3) (STV 0 1)))
!(compileadd softKb (: anew (A new) (STV 1 1)))
!(compileadd softKb (: bnew (B new) (STV 0.6 0.5)))
!(test (query 200 softKb (: $p (B new) $tv))
   (: (merge/revision (by hA anew) bnew) (B new) (STV 0.15088162990393558 0.8004032067331504)))
;; The truth itself counts every sample.
!(test (let (: $p $t $tv) (query 200 softKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)) $tv)
   (STV 0.08697206540828625 0.7782566475768755))
!(test (query 200 softKb (: $p (B new) $tv))
   (: (merge/revision (by hA anew) bnew) (B new) (STV 0.15088162990393558 0.8004032067331504)))

;; A rule's truth is a parameter: a value through the rule depends on its
;; truth's key, not on the instances it was learned from. Learned storm
;; persistence, blocking and lateness (SupplyNet learned rules, in small, see
;; bench/results/supplynet-learned/probes): Storm t2 by persistence reads the
;; storm history through the persistence and blocking truths, and the t2
;; blocking report inverts the blocking rule, whose samples are that history
;; too. Before, the two views shared the history's keys, counted as
;; observations both read, and the report was dropped (0.212).
!(set-evidence-confidence-k 5)
!(set-rule-refinement stormKb true)
!(compileadd stormKb (: persist (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(compileadd stormKb (: block (Implication (Storm $p) (Blocked r1 $p)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(compileadd stormKb (: late (Implication (Blocked r1 $p) (Late s1 $p)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(compileadd stormKb (: storm-h1 (Storm h1) (STV 1 1)))
!(compileadd stormKb (: blocked-h1 (Blocked r1 h1) (STV 1 1)))
!(compileadd stormKb (: late-h1 (Late s1 h1) (STV 1 1)))
!(compileadd stormKb (: next-h2 (NextPeriod h1 h2) (STV 1 1)))
!(compileadd stormKb (: storm-h2 (Storm h2) (STV 1 1)))
!(compileadd stormKb (: blocked-h2 (Blocked r1 h2) (STV 1 1)))
!(compileadd stormKb (: late-h2 (Late s1 h2) (STV 1 1)))
!(compileadd stormKb (: next-h3 (NextPeriod h2 h3) (STV 1 1)))
!(compileadd stormKb (: storm-h3 (Storm h3) (STV 0 1)))
!(compileadd stormKb (: blocked-h3 (Blocked r1 h3) (STV 0 1)))
!(compileadd stormKb (: late-h3 (Late s1 h3) (STV 0 1)))
!(compileadd stormKb (: next-h4 (NextPeriod h3 h4) (STV 1 1)))
!(compileadd stormKb (: storm-h4 (Storm h4) (STV 1 1)))
!(compileadd stormKb (: blocked-h4 (Blocked r1 h4) (STV 1 1)))
!(compileadd stormKb (: late-h4 (Late s1 h4) (STV 1 1)))
!(compileadd stormKb (: next-h5 (NextPeriod h4 h5) (STV 1 1)))
!(compileadd stormKb (: storm-h5 (Storm h5) (STV 1 1)))
!(compileadd stormKb (: blocked-h5 (Blocked r1 h5) (STV 1 1)))
!(compileadd stormKb (: late-h5 (Late s1 h5) (STV 1 1)))
!(compileadd stormKb (: next-h6 (NextPeriod h5 h6) (STV 1 1)))
!(compileadd stormKb (: storm-h6 (Storm h6) (STV 0 1)))
!(compileadd stormKb (: blocked-h6 (Blocked r1 h6) (STV 0 1)))
!(compileadd stormKb (: late-h6 (Late s1 h6) (STV 0 1)))
!(compileadd stormKb (: next-h7 (NextPeriod h6 h7) (STV 1 1)))
!(compileadd stormKb (: storm-h7 (Storm h7) (STV 0 1)))
!(compileadd stormKb (: blocked-h7 (Blocked r1 h7) (STV 0 1)))
!(compileadd stormKb (: late-h7 (Late s1 h7) (STV 0 1)))
!(compileadd stormKb (: next-h8 (NextPeriod h7 h8) (STV 1 1)))
!(compileadd stormKb (: storm-h8 (Storm h8) (STV 0 1)))
!(compileadd stormKb (: blocked-h8 (Blocked r1 h8) (STV 0 1)))
!(compileadd stormKb (: late-h8 (Late s1 h8) (STV 0 1)))
!(compileadd stormKb (: next-h9 (NextPeriod h8 h9) (STV 1 1)))
!(compileadd stormKb (: storm-h9 (Storm h9) (STV 0 1)))
!(compileadd stormKb (: blocked-h9 (Blocked r1 h9) (STV 0 1)))
!(compileadd stormKb (: late-h9 (Late s1 h9) (STV 0 1)))
!(compileadd stormKb (: next-h10 (NextPeriod h9 h10) (STV 1 1)))
!(compileadd stormKb (: storm-h10 (Storm h10) (STV 0 1)))
!(compileadd stormKb (: blocked-h10 (Blocked r1 h10) (STV 0 1)))
!(compileadd stormKb (: late-h10 (Late s1 h10) (STV 0 1)))
!(test
   (let
      (: $prf $t $tv)
      (query
         200
         stormKb
         (: $prf (RuleTruth (Implication (And (NextPeriod $p $t) (Storm $p)) (Storm $t))) $tv))
      $tv)
   (STV 0.4999350008580249 0.450600230398338))
!(test
   (let
      (: $prf $t $tv)
      (query 200 stormKb (: $prf (RuleTruth (Implication (Storm $p) (Blocked r1 $p))) $tv))
      $tv)
   (STV 0.9875621890547264 0.4506726457399103))
!(test
   (let
      (: $prf $t $tv)
      (query 200 stormKb (: $prf (RuleTruth (Implication (Blocked r1 $p) (Late s1 $p))) $tv))
      $tv)
   (STV 0.9875621890547264 0.4506726457399103))
!(compileadd stormKb (: next-t1 (NextPeriod h10 t1) (STV 1 1)))
!(compileadd stormKb (: late-t1 (Late s1 t1) (STV 0 1)))
!(compileadd stormKb (: next-t2 (NextPeriod t1 t2) (STV 1 1)))
!(compileadd stormKb (: blocked-t2 (Blocked r1 t2) (STV 1 1)))
!(test (let (: $prf $t $tv) (query 100 stormKb (: $prf (Storm t2) $tv)) $tv)
   (STV 0.9198799673024876 0.17247015984665653))

;; Read the full internal CTV after scheduling a public STV query below.
;; These pins protect learned negative branches used by modus ponens.
;; A rule whose antecedent never held in the history still learns its
;; negative branch from the cases where it failed (SupplyNet learned rules,
;; stage 1 seed 3: late-s10 rules stayed at their prior); its positive branch
;; has no evidence and keeps the prior.
!(set-rule-refinement negKb true)
!(compileadd negKb (: r (Implication (A $x) (B $x)) (CTV (STV 0.5 0.02) (STV 0.5 0.02))))
!(compileadd negKb (: a1 (A i1) (STV 0 1)))
!(compileadd negKb (: b1 (B i1) (STV 1 1)))
!(compileadd negKb (: a2 (A i2) (STV 0 1)))
!(compileadd negKb (: b2 (B i2) (STV 0 1)))
!(compileadd negKb (: a3 (A i3) (STV 0 1)))
!(compileadd negKb (: b3 (B i3) (STV 0 1)))
!(compileadd negKb (: a4 (A i4) (STV 0 1)))
!(compileadd negKb (: b4 (B i4) (STV 0 1)))
!(test
   (let*
      (((: $_public-proof $type (STV $_s $_c))
          (query 50 negKb (: $p (RuleTruth (Implication (A $x) (B $x))) $tv)))
       ((sk-val ($_type $_ctx $_proof $stored-tv) $_ev $_deps)
          (sk-value (sk-key (brand Statement $type) (kbctx negKb)) sk-any-filter ())))
      $stored-tv)
   (CTV (STV 0.5 0.02) (STV 0.25612202882009555 0.4506485110763119)))
