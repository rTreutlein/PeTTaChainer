# Issue 183, part 3 — stored compound source reads

Historical first-round measurements. The [November 10 review fix](ISSUE183_LOOKUP_REVIEW_REPORT.md) supersedes this report’s conclusions about partial evidence and contains the final hand-back.

## Result and scope

Implemented candidate **(ii)** on `i183-lookup`, based on the requested master
`8538013b`. A compound key with a positive-confidence raw observation is no
longer admitted to an event graph. Its existing ordinary source/evidence merge
supplies its value to every consumer, including other inference rows and
Assuming overlays. One source retains its TV; independent parts' proofs and
independent reports combine through the existing merge. Projections cannot
revise their own source. The observation remains a likelihood in graphs for
parts and other compound keys.

This fixes cases 4–9 to confidence `.99` without changing the moment kernel,
variance bound, graph tariff, scheduling, public signatures or evidence model.
It introduces no helper, store or compatibility route. The runtime change is
one admission exclusion using the existing indexed, scoped source catalog.

**Correction to a premise of the brief:** `canon` removes leading negations,
and Member syntax normalizes, but **it does not reorder connective children**.
Consequently `(And A B C)` and `(And C A B)` are different canonical keys on
8538013b. This implementation deliberately uses the existing key identity;
it does **not** make reordered or arbitrarily equivalent Boolean expressions
read identically. The reordered probe still has the old graph answer. If
order-independent lookup is an acceptance requirement beyond “same canonical
key”, this branch is partial on that requirement. It must not be represented
as having implemented Boolean key normalization. Changing that identity also
affects open patterns, source identity and indexed matching; silently sorting
some ground query strings would be a spelling-specific shortcut.

The predecessor branch `i183-stored-not-and` was not changed. No main-checkout
edit, push, merge or GitHub write was made. The private venv's editable mapping
already pointed here; its petta shebang was corrected to this worktree too.
All runtime/test/benchmark jobs used capped admission, the 16,000,000 KB virtual
memory limit, DISPLAY unset, stdin from `/dev/null`, external timeouts and
captured-PID `kill -0` waiters. No benchmark runner, seed or frozen build was
improvised.

## Rule choice

Candidate (i), rejecting a graph only when all its models are empty roots and
all evidence is its own goal's sources, was measured through a process-local
admission ablation. It repairs cases 4–7 and the duplicate/report-only cases,
but leaves 8/9 at confidence `.0006247042`: A's independent observation makes
the graph eligible. It also leaves an assumed A or a supported rule concluding
A on the graph route. That does not implement the stated source-read decision.

Candidate (ii) needs no graph discovery to classify “additional information”.
It refuses the graph at a key with an own raw compound source, and lets the
ordinary merge enforce independence, provenance, filters and exclusions. It
returns the stored observation when only part of the compound has independent
evidence, and revises once a full independent proof is available. Atomic
posterior behavior and graphs for other compound keys retain their contracts.
Zero-confidence placeholders, forward copies and frozen summaries are not raw
positive-confidence observations in this lookup.

The ordinary merge has distinct existing treatments for reports versus forward
predictions and for ordinary independent proofs. This patch does not replace
those with a new universal numeric formula. In particular, the complete parts'
conjunction in the conflict below is ordinary independent evidence and revises.

## Cases, values and proofs

These use fresh engines and 400 steps. `R` abbreviates the proof name `report`,
`G(ps)` means exactly `(node (conjunction ps))`, and `N(p)` means
`(negated p)`. The symbolic A/B/C examples rename the original reporter's
Member/Agent/Ongoing parts. Full precision, source strings and expanded proofs
are in [the paired case ledger](i183_lookup/cases-before.jsonl) and
[after ledger](i183_lookup/cases-after.jsonl).

| Case | Stored / query | Before TV; proof | After TV; proof | Reason |
|---|---|---|---|---|
| 1 | A,B,C each (1,.99); Not A | (0,.99); N(a) | unchanged | Atomic control. |
| 2 | same; And A B C | (1,.970587514400); `(conjunction a b c)` | unchanged | Independent parts, no own compound report. |
| 3 | same; Not And A B C | (0,.970587514400); N(`conjunction a b c`) | unchanged | Complement of case 2. |
| 4 | Not And A B C (1,.99); same negation | (.999998196274,.004318274948); N(G(R)) | (1,.99); N(R) | Canonical source, complemented once. |
| 5 | same source; And A B C | (.000001803726,.004318274948); G(R) | (0,.99); R | Read the source. |
| 6 | And A B C (1,.99); same | (.999911625088,4.46e-16); G(R) | (1,.99); R | Same rule for positive sources. |
| 7 | same source; its negation | (.000088374912,4.46e-16); N(G(R)) | (0,.99); N(R) | Complement of case 6. |
| 8 | Not And A B (1,.99), A (1,.99); same negation | (.999987374375,.000624704196); N(G(a R)) | (1,.99); N(R) | A alone is not an independent proof of A and B. |
| 9 | same source; And A B | (.000012625625,.000624704196); G(a R) | (0,.99); R | Same stored key as case 8. |
| Conflict | Not And A B, A and B each (1,.99); And A B | (.333331930439,.002493804845); G(a b R) | (.333330527484,.993311008825); `(merge/revision report (conjunction a b))` | Independent compound proof revises with the report. |
| Part | And A B (1,.99); A | (.999974748750,3.66e-16); G(R) | unchanged | Graph still learns from the compound. |
| Other compound | same; And A C, C unknown | (.499987374375,0); G(R) | unchanged | Graph still serves a different key sharing A. |
| STV part rule | Not And A B (1,.99), X (1,.99), X→A (1,.99); And A B | (0,.99); R | unchanged | Unsupported STV graph already used ordinary merge. |
| CTV part rule | same, X→A branches (.9,.99)/(.1,.99) | (.000010329920,.001269381025); G(x R `(by r cpu)`) | (0,.99); R | Supported producer of one part still does not prove the compound independently. |
| Assuming X | Not And A B C (1,.99); Assuming X And A B C | (.000001803726,.004318274948); `(assuming G(R))` | (0,.99); `(assuming report)` | Scoped whole-source read. |
| Assuming A | Not And A B (1,.99); Assuming A And A B | (.000012625944,.000624633263); `(assuming G((ctx proof 1) R))` | (0,.99); `(assuming report)` | A alone does not independently prove B. |
| Two independent ids | negative triple R plus `second`; positive triple | (2.27740688799e-11,.995940258149); G(R second) | (0,.994974874372); `(merge/revision second report)` | Counts add once per source. |
| Same id restated | negative triple R twice; positive triple | (.000001803726,.004318274948); G(R) | (0,.99); R | Replay does not add evidence. |
| Reordered | negative triple R; And C A B | (.000001803726,.004318274948); G(R) | unchanged | Different key under actual canon; limitation above. |
| Reordered Or | Or A B (.8,.9); Or B A | (.923039948729,.002660470649); G(R) | unchanged | Same key-identity limitation. |
| Reordered nested | Or (And A B) C (.8,.9); Or C (And B A) | (.869506157933,.002084105255); G(R) | unchanged | Same key-identity limitation. |

The conflict is **not an overconfident endpoint**: neither the negative report
nor the positive parts win alone. At K=800 the negative source has n=79,200;
the independently propagated conjunction has n≈39,599.5. Their count-weighted
strength is `.333330527484` and total-count confidence `.993311008825`.
The implied SD is about `.00137`; the independent count-fusion reference 1/3
is well within two SD (as is the old graph's centre). High confidence here
means precision of the pooled frequency, not confidence that the event is
certainly false or true. It does not model unknown source unreliability or
promise that arbitrary contradictory reports are calibrated.

The new regression file also covers fractional source strengths 0/.2/.5/.8/1,
And/Or/nested/five-part compounds, positive and negative queries, zero/paid/warm
budgets, Member spelling, a late stored report replacing a previous graph
answer, and preservation after Assuming cleanup. No source proof is revised
with its own projections.

## Moved test values and KE coverage

All changed existing pins came from the former graph-precedence contract:

- `test_bridge_query_order`, `test_conditional_world_facts` and
  `test_double_negation_evidence`: the three-part identity at (1,.9) moves from
  strength `7201/7208=.999028856826` to 1. The identity alone moves from c=0
  to .9. Beside the independent conditional at (1,.9), ordinary variance
  propagation gives c=`.8181611546663349`; the overlapping bridge gives the
  same endpoint result while retaining the observation exactly once.
- The bridge with source confidence .5 moves from
  `(.991336633663,1e-6)` to `(1,.473621848543)`.
- `test_identity_worlds`: source strengths .8/.5/.2 move from
  `.363515901060/.125/.034500095767` to their stated .8/.5/.2; direct and
  certain-judgment reads retain .9 confidence. For the bridge, .8 and .5
  have c=`.899999639938` and `.899999909975`, respectively. Neutral reports
  on the bridge's consequent do not change these values.
- The MeTTa double-negation fixture's two pins move from
  `(.999028856826,0)` to `(1,.8181611546663349)`. Its comment derives the
  new value from independent conjunction variance, rather than output fitting.
- The source-plan invalidation test now queries a **different** compound,
  And(A,B), after observing Or(A,B), so it still verifies graph discovery and
  epoch invalidation. Its previous queried key is intentionally no longer
  eligible for a graph.
- The fuzzer's identity-subset oracle used an enumerated posterior as the
  maximum identity value. It now uses the one identity report's stated
  strength. The `identity-soft` fixture's source strength changes **1→.8**
  to keep the upper bound nontrivial; its confidence remains .9. The unit
  test still rejects an excess smaller than the ordinary strength tolerance.
  No new expected failure, known-failure exemption, budget increase or
  benchmark tolerance change was added.

The initial suite exposed 39 Python assertion failures and one MeTTa file;
after the source-read updates, the first complete verify exposed the obsolete
fuzzer subset reference. Both were resolved under the new semantic contract,
not hidden. The final targeted and complete suites pass.

The [KE ledger](i183_lookup/ke-moved-values.jsonl) lists **every** moved TV and
full proof: 64 of 92 cold/warm reads change; none loses an answer. The other 28
reads retain their TVs or remain unanswered as required by the assumptions.
Direct source and certain-judgment cases match the new analytic source reference
exactly. Bridge results retain the source bound and one copy of its evidence.
These are semantic fixtures, not independent real-world calibration samples;
comparing them against the superseded graph centre would test the old decision.

## Gates and benchmark calibration

- `scripts/verify.sh`: **PASS**, exit 0, 156 s, cache key `56e97c56002e`.
  MeTTa 164 passed / 0 failed; Python 1,151 tests in 88 files (95 scheduled
  units), 23 existing expected failures and four skips. Lint, import scaling,
  judgment scaling, ConceptNet and fuzzer pass; all available abort counts zero.
- [Quick comparison](i183_lookup/benchmark-details/quick.md): **PASS**, nine
  comparable cases, no accuracy changes; nine runs executed, ten of 19 results
  reused, 78 s. The earlier minimal runtime iteration also passed (66 s).
- [Full comparison](i183_lookup/benchmark-details/full.md): **PASS**, 22
  comparable / 23 configured cases, no accuracy changes. The final fuzzer
  update reran two jobs and reused 43 of 45 results; 441 s including the curves
  queue. The preceding full sweep of the same runtime ran 44 jobs in 162 s.
  Its two initial timing flags did not repeat: stage-3 untimed b25 s4
  7.931→9.245 s, paired rerun 8.468→7.406; conflict sources m spq4 s3
  15.47→17.58, paired rerun 13.31→13.08. No confirmed timing regression.
- [Anchor canary](i183_lookup/benchmark-details/anchor-canary.md): **PASS**,
  six cases, 103 s. Four workloads differ from the older anchor: live,
  stated conflict, reliable conflict and scale m. Those are historical master
  differences. Six metrics remain behind the anchor on master too.
  The explicit [master canary](i183_lookup/benchmark-details/master-canary.md)
  is **PASS**, all six cases and captured TVs unchanged.
- [Curves](i183_lookup/benchmark-details/curves.md): completed, exit 0,
  649 s including queue time. All **56 matched budget points in ten families**
  have identical errors. The timing curves are descriptive, with reused base
  runs; they are not a paired timing significance test.
- `git diff --check`: PASS. The [validation metadata](i183_lookup/benchmark-details/validation.json)
  names every standard result directory and tree. All final present case records
  have exit 0. Candidate runtime tree: `16e27adca7c2…`, the code commit's tree
  under the harness's runtime inputs.

All benchmark runs came from the standard harness and its stored results.
The executable runtime was unchanged after the admission edit; subsequent
snapshot differences came from contract documentation/comments and the fuzzer
fixture/reference update. Standard result reuse handles that distinction.
Each canary invocation attempted six dedicated timing-host runs (twelve
attempts total), returning exit 127 because this worktree's private venv was
absent there. The anchor invocation completed locally, and the explicit master
check reused successful local results. Final case records succeeded. These
are local, load-normalized measurements, not successful dedicated-host timings.

The [complete calibration summary](i183_lookup/benchmark-details/calibration.json)
covers 90 unique comparison pairs. **All 84 master/candidate pairs have
identical captured truth values and calibration summaries**, across full,
quick, canary and curves. The [moved-value ledger](i183_lookup/benchmark-details/moved-values.jsonl)
contains 1,015 changes, all from the historical anchor comparison: 50 live,
160 stated-conflict, 160 reliable-conflict and 645 scale rows. There are zero
new lost or changed captured answers against master.

On the full suite, 21 workloads supply 7,010 scored belief rows: outside two
displayed SD is **1,028/7,010 before and after (14.665%)**. MAE, Brier,
coverage and every displayed confidence are unchanged. Full details, including
K, centre errors and z distributions, remain in the linked JSON. Existing
large z scores must not be mistaken for newly calibrated answers.

| Full captured workload | Scored rows | Outside 2 SD, before→after | Largest z, both |
|---|---:|---:|---:|
| supplynet stage 1 b100 s3 | 227 | 0→0 | 1.83471 |
| supplynet stage 3 timed b25 s3 | 403 | 9→9 | 75.5926 |
| supplynet stage 3 timed b50 s3 | 403 | 6→6 | 82.6783 |
| supplynet stage 3 timed b100 s3 | 403 | 6→6 | 41.2064 |
| supplynet stage 3 untimed b25 s4 | 376 | 6→6 | 20.6839 |
| supplynet stage 3 untimed b100 s4 | 376 | 6→6 | 20.6839 |
| supplynet stage 3 timed soft0.9 b100 s3 | 402 | 12→12 | 394.272 |
| supplynet stage 3 untimed soft0.9 b100 s4 | 370 | 8→8 | 4.354 |
| scale l spq4 s1 | 1252 | 398→398 | 9.40102e+07 |
| scale l spq16 s1 | 1252 | 167→167 | 2.97938e+07 |
| scale s spq1 s1 | 136 | 84→84 | 5.92129e+07 |
| conflict pln-sources m spq4 s2 | 79 | 6→6 | 4.86026 |
| conflict pln-sources m spq4 s3 | 80 | 31→31 | 16.9524 |
| conflict pln-reliable l spq4 s1 | 160 | 2→2 | 8.05627 |
| learned stage 3 timed learned b50 r200 s1 | 202 | 19→19 | 7.02636 |
| supplynet stage 4 extend b50 s2 | 137 | 0→0 | 9.3905e-08 |
| learned stage 3 timed learned b50 r200 s2 | 207 | 15→15 | 7.02831 |
| learned stage 3 untimed learned mined b50 r50 h10 s3 | 54 | 19→19 | 17.512 |
| replay b25 s1 | 200 | 95→95 | 207237 |
| replay b25 s4 | 200 | 78→78 | 223598 |
| combinet n2 s1 | 91 | 61→61 | 128.466 |

The stage-1 b25 s2 quick capture likewise remains 0/218 outside two SD,
maximum z≈1.7532. This contrasts with part 2's 18/218 and 16/227 new misses
at stage-1 b25/b100. This patch introduces no confidence tightening on those
benchmark answers. ONA and fuzzer cases without belief captures are checked
by their standard accuracy/coverage gates; no unmeasured confidence claim is
made for them. These are reference-probability diagnostics, not binary-outcome
coverage or independent samples.

## Commits and draft reply

Code/tests/contracts commit: `0a1152648fafa0c5e79c9fcf701d02abaf511c55` —
`Read stored compound keys through their source merge (#183)`.

Report commit: `i183-lookup` at hand-back, titled
`Record #183 lookup measurements, gates and limits`, immediately after the code
commit. It contains this report, raw measurements, the extraction/probe scripts,
`STATE-i183.md` and the `rounds.md` entry. Both use the exact requested
Co-Authored-By and Claude-Session trailers. Nothing was posted.

Draft reply:

> A read of the stored compound now uses its existing source merge. The
> negative triple in cases 4/5 therefore returns confidence .99 at either
> polarity; the positive and partially known counterparts do too. Independent
> evidence for all the parts is retained and revises with the report, while
> queries about a part or another compound still use the event graph. Duplicate
> source ids count once. The standard benchmark captures have no changed TVs
> or added calibration failures.
>
> One scope correction: our current canonicalizer preserves connective child
> order. This patch applies to the same canonical key; differently ordered
> compounds still take their existing routes. It does not implement arbitrary
> Boolean-equivalent lookup.

## Limits

- Child-order equivalence is not canonical key identity today. Reordered
  direct reads remain unresolved, explicitly measured above.
- The graph variance bound remains very loose for some part/shared-compound
  questions; this is not the rejected part-2 variance tightening.
- Ordinary count revision's confidence has its existing meaning. No new
  source-reliability or disagreement model is introduced.
- Benchmark calibration already has serious misses. Unchanged rows prove no
  **new** miss on this measured corpus, not universal calibration.
- Existing unsupported graphs, joint-row arity limits, finite-budget
  approximations and ordinary report-versus-prediction semantics remain.
- All public API signatures and the predecessor branch remain intact.
