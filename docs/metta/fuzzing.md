# Differential fuzzing against ProbLog

Status: built, October 2026. Code: `scripts/fuzz_vs_problog.py`,
`tests/fuzz/`. Results: `/nexus/Dev/OpenCog/bench/results/fuzz/`.

## Purpose

Benchmarks find chainer defects late and as aggregate error. The fuzzer finds
them as minimal repros in minutes. It generates small random knowledge bases,
answers every query exactly with ProbLog 2.3.0, answers the same queries with
PeTTaChainer, flags clear disagreements, and shrinks each flagged KB to the
fewest statements that still fail. Approximation is expected, so the fuzzer
looks for clear defects: an error above the threshold (0.05), no answer, an
answer that moves the wrong way from the prior, or an answer that gets worse
with more budget.

## Usage

```bash
.venv/bin/python scripts/fuzz_vs_problog.py --seed 1 --n 200 --out /nexus/Dev/OpenCog/bench/results/fuzz/run1
.venv/bin/python scripts/fuzz_vs_problog.py --seed 1 --n 200 --features all --out ...
.venv/bin/python scripts/fuzz_vs_problog.py --replay .../repros/seed1000004_error.json
```

| option | meaning |
|---|---|
| `--seed S --n N` | N KBs; KB i uses seed `S * 1000003 + i`. Results are deterministic per seed. |
| `--features a,b,...` | the features below, `default` or `all`. By default each KB takes a random subset of them (each with probability 0.6); `--no-mix` gives every KB all of them. |
| `--budgets 100,2000` | ascending query budgets. The last is judged, the first checks that more budget is no worse. |
| `--k 5` | the evidence confidence k, as SupplyNet runs the chainer. |
| `--threshold 0.05` | the absolute error that flags a query. |
| `--jobs 2` | chainer processes at once, for the runs and for the shrinks. |
| `--shrink 2` | flagged KBs shrunk per group (0: none). `--shrink-limit` caps the chainer runs of one shrink (120). |
| `--replay FILE` | run one repro (or KB) JSON and print the ProbLog program, both answers and every chainer proof. |

The script re-executes itself inside `bench.slice` and runs each KB's
chainer in a fresh process (`tests/fuzz/chainer_worker.py`) under
`ulimit -v 16000000` with `DISPLAY` unset, so a case never sees another
case's state. ProbLog runs in its own interpreter,
`/nexus/Dev/OpenCog/ChainerGame-problog/.venv-problog/bin/python`
(`PROBLOG_PYTHON` overrides it; `tests/fuzz/problog_worker.py`). A KB takes
about one second; 300 KBs take five minutes plus the shrinks.

`tests/test_fuzz_kb.py` checks the generator (deterministic, every KB valid)
and the translation (ProbLog's prior marginals equal exact enumeration of the
same model, and a learned rule's stated counts and history use the count law). It
runs no chainer. A fuzz run is not part of the test suite: it finds open
defects, so it cannot be a stable gate.

`tests/test_fuzz_outcomes.py` checks supported answers, unsupported features,
and crashes through the worker protocol and summary. A worker's terminal
`NotImplementedError` or `UnsupportedCompilation` is an `unsupported` outcome;
its message (including the backend's feature and stage label) is preserved in
`cases.jsonl` and counted under `kbs_unsupported` / `unsupported_reasons` in
`summary.json`. It is separate from crash and numerical-error counts. Workers
may also return `@@RESULT@@{"unsupported": "feature/stage label"}`. Other
worker failures and timeouts remain crashes. Unsupported and crashed KBs have
no query rows and are excluded from query clustering and shrinking; even a run
with zero supported KBs writes a complete summary with a null mean error.

## What a KB is

`tests/fuzz/kb.py` holds the abstract KB both translations are written from.

- Unary predicates `A`..`H` over one or two queried individuals `a`, `b`.
- **Root predicates** have a prior and no rule. The prior is either stated or
  estimated from a history (below).
- **Derived predicates** have exactly one CTV rule over one variable,
  `(Implication ANT (P $x)) (CTV (STV p 1) (STV q 1))`. `ANT` is a literal or
  an `And` / `Or` of literals, and a literal may be negated.
- **Observations** of the queried individuals have confidence 1. They are
  hard (strength 0 or 1, roots or derived) or soft (a strength in between,
  roots only).
- **Queries** ask for every unobserved atom of the queried individuals, at
  most 8.

| PeTTaChainer | ProbLog | why it is the same |
|---|---|---|
| CTV rule `ANT -> P` (p, q), confidence 1 | `ant_i(X) :- ind(X), ANT.` (one clause per `Or` part), `p::p(X) :- ind(X), ant_i(X).` and `q::p(X) :- ind(X), \+ant_i(X).` | the two bodies exclude each other, so P(P \| ANT) = p and P(P \| not ANT) = q (no noisy-OR, one rule per head). As in ChainerGame `docs/problog_backend.md`. |
| `And`, `Or`, `Not` | conjunction, one clause per disjunct, `\+` | stratified: no negation inside a loop |
| stated root prior r: `(set-base-rate kb (A $x) (STV r 1.0))` | `r::a(a).` per individual | a certain base rate keeps its value as the prior of every member |
| hard observation `(: obs-A-a (A a) (STV 1 1))` | `evidence(a(a), true).` | a certain fact is its own value; ProbLog conditions on it |
| soft observation `(STV s 1)` of a root | `s::a(a).` in place of its prior | the fact is the atom's value in both, *only* because nothing is observed below it (see exclusions) |
| `set-complete-predicate` on a loop | the same clauses, read at their least fixpoint | Clark completion, well-founded on loops (`complete_predicates.md`) |
| query `(: $prf (A a) $tv)` | `query(a(a)).` | the strength of the most confident STV answer against the marginal |

### Features

| feature | what it adds |
|---|---|
| `chain` | antecedents may read derived predicates |
| `shared` | a predicate may feed several rules (common causes, and correlated premises in one antecedent) |
| `and`, `or`, `not` | `And` / `Or` antecedents of two or three literals, negated literals |
| `cycle` | a positive loop: a chain X -> ... -> Y of derived predicates is closed by adding Y as a disjunct of X's antecedent; the loop's predicates are complete, their rules have q = 0 and no negation, and their p is kept or set to 1. Implies `chain`. |
| `soft` | soft observations of roots |
| `evidence` | hard observations of derived statements (explaining away, inversion) |
| `observe` | hard observations of roots |
| `latent` | root atoms may stay unobserved. Without it, every root atom of a queried individual is observed (hard or soft). |
| `derived_rates` | pins each derived predicate's base rate to its prior under the model (exact enumeration, `KB.model_prior`, with the estimated parameters when there is a history). Without it, a derived predicate's base rate is the rate of its stored facts: none without a history, so no inversion of a rule out of it, and with a history an empirical rate that differs from the model's by sampling noise (see false positives). |
| `learned` | rules (each with probability 0.7) are refined from a fully observed history (see below) |
| `history_rates` | root priors are estimated from a fully observed history |

`default` is `chain shared and or not evidence observe latent derived_rates`.
Observations are drawn from one sampled world per individual, so evidence is
always possible.

### History, learned rules and estimated rates

With `learned` or `history_rates` the KB holds 8 to 30 past individuals
`h0, h1, ...`, every atom of each observed as a hard fact drawn from the
model. ProbLog leaves them out: given the parameters they are independent of
the queried individuals. They enter only through the parameters, estimated
the way the chainer is specified to estimate them:

- **Learned rule.** PeTTaChainer gets the rule with
  `(CTV (STV 0.5 c) (STV 0.5 c))`, `c = 2 / (2 + k)`, two pseudo-observations
  at 0.5 per branch, and `set-rule-refinement`. These are stated evidence,
  not the uniform prior itself. With N history instances and S successes,
  revision has n=N+2 and ns=S+1. The stored-count law adds Beta(1,1) once,
  giving Beta(S+2,N-S+2), mean (S+2)/(N+4), which the oracle uses per branch.
  The former (S+1)/(N+2) reference mistook the axiom for the whole prior;
  benchmark seed 22000165 exposed it when the graph began reading refined
  counts (five negative samples: 2/9, not 1/7).
- **Estimated root prior.** The chainer reads a base rate over n stored facts
  as the prior of one more member, (s n + a/2) / (n + a) with the Bayes prior
  count a = 0.2 (`prior_factored_merge.md`). The oracle uses the same
  estimate over the same facts: the history's and the queried individuals'
  observations, soft ones at their strength.

## What is excluded, and why

Each exclusion is a place where the two readings differ by design.
`KB.problems()` rejects a KB that has one, and the shrinker never produces
one.

| excluded | reason |
|---|---|
| two rules into one consequent | PeTTaChainer combines several rules' views by a mode learnt from stored outcomes (`combination_modes.md`), revision until outcomes decide; ProbLog's two clauses are a noisy-OR. The fuzzer states a combination explicitly as one `Or` / `And` rule instead. |
| STV rules | an STV rule's negative branch is derived from base rates in PeTTaChainer; `p::b :- a` in ProbLog has P(b \| not a) = 0. Only CTV rules are generated. |
| soft observation with an observation below it, or of a derived atom | a fact of confidence 1 is its own value: no rule is applied to it, so evidence below it does not update it, where ProbLog conditions the prior. |
| a learned rule with a branch no history individual instantiates | the chainer derives an unsampled branch from the base rates of both sides; the symmetric count prior leaves it at 1/2. |
| a learned rule with an `Or` antecedent or a negated literal | the instance fold samples only plain predicate conjuncts; such a rule keeps its stated prior, where the oracle would learn it. |
| uncertain confidence below 1 (on facts or stated rules) | confidence is evidence weight, which ProbLog has no reading for. |
| negation inside a loop, an open predicate in a loop, a loop rule with q > 0 | ProbLog needs stratified negation; the chainer's well-founded reading is defined for complete predicates. |
| variables beyond the consequent's (joins), binary predicates | an ordinary antecedent variable is universal in PeTTaChainer (views revise) and existential in ProbLog; only `Exists` matches, and is not generated yet. |

Three answers differ by documented design. They are reported as
`gap_latent_premise`, `gap_root_prior` and `gap_derived_population_prior`
and are not failures:

- **An unobserved root premise with no observation below it has no value
  as a premise of a derivation.** A population prior answers a *root query*
  the search leaves without a value; it is "the population's value, not the
  statement's", so a rule reading such a premise concludes nothing. Only an
  antecedent completion reads it: the other parts of an `And` or `Or`
  antecedent, unobserved, are at their population prior in the likelihood
  of the consequence (`sk-start-prior!`), so an observation of a compound's
  consequence updates each part.
- **A root query has a population prior only when some rule reads its base
  rate** (an inversion or a completion onto it). A root read by no rule has
  none, even with a pinned base rate.
- **A derived atom whose premises are such roots is answered by its
  predicate's population prior**, the rate of its stored facts (another
  individual's observation, or a history), where ProbLog derives its prior
  from the model.

### False positives to expect

- **Empirical rates of derived predicates.** Without `derived_rates`, an
  inversion of a rule `D -> E` reads D's base rate from D's stored facts. In
  a history of 8 to 30 individuals that rate differs from the model's prior
  by sampling noise, often by more than 0.05, and in a KB without a history
  the observation of one other individual is the whole sample. Such repros
  show `(inverted ... (prior (STV r c)))` with r far from the model prior.
  Run history features with `derived_rates` to exclude them.
- **Learned rules that the instance fold does not sample** keep their stated
  prior. The generator learns only literal or `And` antecedents without
  negation, the shapes `LANGUAGE_SPEC.md` says are sampled.

## Judging

For each query, with s the chainer's strength at the largest budget, p the
ProbLog marginal and p0 the marginal without observations:

| category | condition |
|---|---|
| `crash` | the chainer process failed or timed out (300 s) |
| `no_answer` | no STV answer, and not one of the two gaps |
| `wrong_direction` | \|p − p0\| > threshold, s − p0 has the opposite sign and \|s − p0\| > 0.02 |
| `error` | \|s − p\| > threshold |
| `budget_regression` | the error at the largest budget exceeds the error at the smallest by more than the threshold |

A KB's category is its worst query's (in that order). A KB whose ProbLog
program fails (impossible evidence) is skipped; none have been.

## Shrinking

`tests/fuzz/shrink.py` reduces a flagged KB while the same category stays
flagged on the same atom: keep only that query, drop the other individual,
an observation, a rule (its head becomes a root at its prior under the
model, so its readers keep their meaning), an antecedent part, a negation, a
complete declaration, half the history (never below 8 individuals, the
generator's smallest), unused roots. It repeats until no
reduction applies, typically in 15 to 60 chainer runs.

## Reading a report

`<out>/` holds `cases.jsonl` (every KB with its rows: atom, exact, prior,
PeTTaChainer at both budgets, error, the judged proof), `log.txt`,
`summary.json`, `summary.md` and `repros/`. A repro is three files:
`seedN_category.metta` (standalone; run it with `.venv/bin/petta`; its
header describes the KB and the expected value), `.pl` (the ProbLog
program) and `.json` (the minimal KB, the failing row and the chainer's
answers with proofs, for `--replay`).

The summary groups flagged KBs by category, error direction and the proof
constructors of the judged answer (`inverted`, `antecedent-completion`,
`factored-revision`, `settled`, `proj`, `unfounded`, ...), shrinks up to
`--shrink` KBs per group, and counts each group under the cluster of its
first minimal repro (category, direction, the features the repro still uses,
its proof constructors). Clusters are listed by frequency with their
smallest repro. Two clusters can share a root cause; the proof in the repro
usually shows it.

## Event differential and metamorphic mode

The same entry point, generator, worker transport and shrinker now support
`--quick` (builder loop) and `--long` (nightly). The legacy feature/ProbLog
mode remains available. Quick/long also run the ProbLog subset. Both exit 1
while a defect remains. `--gate` runs the quick seed-1 campaign as a
`verify.sh` gate: master's open BLOCKERs are listed in `KNOWN`
(`tests/fuzz/run.py`), and the gate fails on any other BLOCKER, on a listed
one that no longer occurs, or on a failing ProbLog differential. Known
BLOCKERs are not shrunk in gate mode.

```bash
( unset DISPLAY; ulimit -v 16000000
  /nexus/Dev/OpenCog/bench/capped --slots 8 .venv/bin/python \
    scripts/fuzz_vs_problog.py --quick --jobs 8 --chainer /path/to/build \
    --out scratch/fuzz </dev/null )
# Replay a reduced event or legacy ProbLog KB:
.venv/bin/python scripts/fuzz_vs_problog.py --chainer /path/to/build \
  --replay scratch/fuzz/repros/CASE.json </dev/null
```

The entry point admits itself through `bench/capped` if necessary; it does
not fall back to uncapped execution. `--chainer` uses that repository's
`.venv/bin/python` and checks its actual imported package path. Without it,
`CHAINER_PYTHON` selects the interpreter. Every event case records the imported
package path. Workers start fresh per KB and budget and remove `DISPLAY`.
Quick uses seed 1 by default, budgets 100/500, k=800, strength tolerance .001,
a 45-second worker timeout, and up to 24 reduction trials per violation.
Long uses twenty consecutive seeds, more CTV shapes and 80 reduction trials.
Quick applies rename/reorder/repeat to origin families through three sources;
seven/eight-source cases check exact moments, joint bounds and budgets. Long
also applies the expensive syntactic mutations at those larger widths.
Admission waiting precedes the reported campaign time.

`EventKB` adds ground formulas over at most twelve atoms: stored facts,
STV/FTV certain-positive producer families through eight independent origins,
uncertain CTV branches, And/Or/Not reports including otherwise unused leaves,
neutral descendants, ground base rates, identity conjunctions with residual
judgments, and Member/Inheritance chains with active rule schemas. Seeded
variants change rates, confidence-sensitive shapes and connective structure.
Every `EventKB` root is emitted as an ordinary stored fact and must have the
`count` role: Beta(ns+1,n(1-s)+1), n=k*c/(1-c). This includes the origins
and base-STV/FTV controls. For example, a stored STV(.8,.5) at k=800 has
mean 641/802, not .8. The emitter rejects view-labeled roots; a genuine
propagated view would need its own emitting path before that role can be used.
Certain sources are points. Reports supply Pearl likelihoods using their
predictive probability. A certain-positive family is OR of its active
antecedents plus a separate fallback event per consequent. No arbitrary
multi-CTV combination law is invented.

`event_oracle.py` enumerates the Boolean worlds independently of the chainer.
Strength is E[N]/E[Z], exact at analytic parameter means for the multilinear
network. Shared atoms are one bit. With constant Z, two-node Beta integration
is a polynomial moment and gives exact variance. With observations, 12/24-node
Beta integration estimates Var(N/Z) under the Z-tilted parameter law, records
its discrepancy, and labels it **numerical**, not certified exact. A separate
analytic bound, E[(N-sZ)^2]/(E[Z]*max_world_likelihood), is a certified variance
lower bound. This bound uses only degree-two polynomial moments. Integration
is capped at 150,000 parameter cells; the exact mean and analytic variance
lower bound remain available beyond that cap.

Wrong strength, lost answers, impossible positive support, violated invariants,
error beyond two claimed standard deviations, or variance below 80% of the
certified lower bound are BLOCKERs. Numerical-only variance warnings are
FOLLOW-UPs, with the two-order discrepancy retained for review. Output confidence
is decoded using the public ideal-variance formula; the .001 strength tolerance
also absorbs rounding in the error-versus-sd check. Conditional-source and
judgment shapes without an unambiguous normalized interpretation use
metamorphic obligations or necessary subset bounds.

The soft KE identity-plus-judgment case checks Q = I and judgment against
an independently enumerated upper bound P(I). Its three unobserved identity
parts have uniform stored-count priors; the STV(1,.9) identity report gives
P(I)=7201/7208 at k=800. Every Q answer must be at most that value, allowing
1e-6 for rounding. This catches strength 1 with confidence about .818 even
though the gap is below the general .001 strength tolerance, without
inventing a probability for the residual judgment. The bound and its
enumeration metadata are retained under `exact.subset` in `cases.jsonl`.

Paired checks add a neutral descendant, flip a relevant report in the direction
predicted by a normalized control, add an impossible constraint, rename symbols,
reverse installation/connective order, and repeat source identities and query
atoms. A separate `redundant` mutation adds a distinct rule name with the
same antecedent, consequent and certain FTV(1,1): it must preserve strength,
confidence and answer availability. This exercises producer admission
separately from replaying the same source identity; its enumeration also has
the same law.
Inactive producers must preserve explicit bases; inactive class-link
rules must preserve existing classification. Origin scaling checks the Fréchet
bounds on marginals and joints; each reference case also checks error at the
larger budget. A deterministic Prolog inference-count probe detects repeated
superlinear catalog normalization when producer counts double; CPU times are
retained as diagnostics, not used as a flaky timing gate.

Every event violation has a JSON replay and standalone MeTTa repro. Paired
violations also have a `-variant.metta`; the JSON replay is authoritative for
the pair and for work-scaling measurements. The shrinker rebuilds mutations
and references after deletion and accepts only the same severity/invariant on
the same query. It removes statements, rules, reports, unused roots and base
pins, and halves cost-probe sizes. `one_minimal` means no permitted single
deletion preserves this failure; it is not a claim of global minimum. Trial
limits are reported explicitly. `cases.jsonl` retains original KBs, exact
means, variance labels, both budgets, variants and proofs; `summary.json` and
`summary.md` record runtime provenance and severity counts. Exit 1 means a
BLOCKER or a failing ProbLog differential; exit 0 means this bounded campaign
found none, not correctness for ungenerated shapes.

The corrected seed-1 quick campaign against KE2 `8ddce38d` removes all six
origin-2/3 false strength flags and passes both base-STV/FTV cases. The new
identity bound catches strength 1 at confidence .81804, and the distinct
redundant producer catches .6 changing to .7071122230. The one-origin cases
now expose the ordinary path's disagreement with stored-count enumeration;
their three strength flags remain evidence for that same producer-admission
defect. Campaigns still exit 1 while runtime defects remain.
