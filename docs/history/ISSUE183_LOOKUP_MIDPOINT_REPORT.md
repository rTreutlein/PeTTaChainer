# Issue 183 lookup: midpoint review fix, November 10

This is the final hand-back for the second review fix, superseding the
[previous review report](ISSUE183_LOOKUP_REVIEW_REPORT.md). Worktree
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer-i183`, branch `i183-lookup`,
base `8538013b`. The final history retains two commits: code/tests/contracts,
then reports and their measurement archives. Both use the requested trailers.

## Change and derivation

The partial bound reader now returns
**((L+U)/2, (1-(U-L)) × min(cL,cU))**. Its strength is the interval centre:
start at L and add half the width U-L. Confidence uses the smaller propagated
endpoint confidence, discounted linearly by the unresolved width. Thus width
zero preserves the endpoint, while width one supplies no proof. The previous
strength calculation was removed; there is no compatibility path.

Known inputs retain their STV at both bounds; unknown inputs span [0,1].
The existing connective formulas propagate both endpoint lists and their
variance, including negation. All-known inputs still use the complete producer.
The report remains excluded from the part reads, and proof identity, producer
installation, subscriptions, merge policy and public API are unchanged.

For A=(.5,.99) and unknown B, And spans [0,.5]. Its centre is .25, its width
is .5, and its confidence is .5×.99=.495. Confidence converts to evidence
count n=800c/(1-c), about 784.158 here. Those counts now have strength .25;
they are no longer all observations of falsity. The interval reading is an
estimate within the bounds, not a hard constraint imposed on an independent,
possibly conflicting report. Ordinary revision pools both sources:

    nr = cr/(1-cr), ne = ce/(1-ce)
    revised strength = (nr*sr + ne*se)/(nr+ne)
    revised confidence = (nr+ne)/(nr+ne+1)

The common K=800 cancels in this form. No new calibration claim is made for
the width-to-confidence heuristic.

## Five graded rows

B is unknown throughout; each A has confidence .99. Before values are the
reviewer's branch4/branch5 measurements on `adcd18f0 + 9f794665`.
After values are live results from the pinned runtime, checked against the
count derivation to 1e-12 in `test_review_graded_reports_revise_with_midpoints`.

| Report (s,c) | A strength | Partial evidence after | Before (s,c) | After (s,c) | Why reasonable |
|---|---:|---|---|---|---|
| (.5,.1) | .5 | (.25,.495) | (.050907258065,.521830615466) | (.275453629032,.521830615466) | The part has more evidence than the weak report, pulling the result toward the interval centre .25 without asserting false. |
| (.4,.9) | .5 | (.25,.495) | (.360714285714,.908926961226) | (.385267857143,.908926961226) | The report's normalized count 9 outweighs the part's .980198; the result moves modestly toward .25. |
| (1,.99) | .5 | (.25,.495) | (.990196078431,.990097068340) | (.992647058824,.990097068340) | The report's count 99 dominates .980198; the conflicting partial estimate still pulls downward. Revision does not clamp the independent report to the part's interval. |
| (.1,.9) | .2 | (.1,.792) | (.070270270270,.927576601671) | (.100000000000,.927576601671) | The report agrees with the [0,.2] midpoint: strength stays .1 and independent evidence raises confidence. |
| (1,.1) | .9 | (.45,.099) | (.502790178571,.180991819008) | (.726534598214,.180991819008) | The broad [0,.9] interval gives little confidence; nearly equal small counts average 1 and .45 and leave confidence low. |

Full precision, proofs and the other re-review fixtures are in
[graded-after.jsonl](i183_lookup/midpoint/graded-after.jsonl), with the
[fixtures](i183_lookup/midpoint/fixtures.json) and original reviewer
[branch4](i183_lookup/midpoint/reviewer-before4.log) /
[branch5](i183_lookup/midpoint/reviewer-before5.log) captures.

## Unchanged controls and additional changes

All **58 prior review outputs match exactly, including proofs**, against
[the prior ledger](i183_lookup/review/after.jsonl). The new complete ledger is
[review-after.jsonl](i183_lookup/midpoint/review-after.jsonl), covering every
fixture in the reviewer's rerun plus the existing extra controls.

| Decisive fixture | Before and after |
|---|---|
| And report (1,.5), A=(0,.99) | (.010000000000000009,.9900990099009901) |
| And report (1,.99), A=(0,.99) | (.5,.9949748743718593) |
| Or report (0,.99), A=(1,.99) | (.5,.9949748743718593) |
| And report (1,.5); query; add A=(0,.99); query | (1,.5) → (.010000000000000009,.9900990099009901) |

Cases 4–9 retain confidence .99 and their original polarity. The complete-parts
conflict remains (.33333052748398234,.9933110088252738).
The [21-case ledger](i183_lookup/midpoint/cases-after.jsonl) differs only in
`rule-part-ctv`: strength 0 → .0004988913132181221, confidence unchanged at
.990010975730573. Its independently derived graded A now contributes the
[0,.9] midpoint .45; it cannot prove the compound false.

Beyond the five requested rows, `nine_strong` changes
.9988913525498891 → .999390243902439 at unchanged confidence
.9900109757314383, for the same [0,.9] midpoint. The `sh_graph` reads change
.2999750263533766 → .2999910361271947 (c=.9000074921563559) and
.1999796373607267 → .20000084942507035 (c=.9000091632809674).
Each reads graded evidence derived from the *other* report with its own
report excluded, so the new midpoint changes that tiny independent contribution.
[Every supplementary moved value](i183_lookup/midpoint/graded-changes.jsonl)
is recorded at full precision. The shared atom read, self-report projection controls, decisive/nested/negative
controls and duplicate-report controls are unchanged. No proof shape changes.

## Tests and contracts

- Updated the native formula and the language specification, runtime assumptions
  and event-node contract, with the centre/width derivation. The previous review
  report's formula is updated and its measurements marked historical.
- Added direct native midpoint and And/Or dual checks, multiple-unknown
  semideterminism, and no proof at width one. Added the five count-derived
  revision pins at paid, zero and repeated budgets.
- Updated `test_graded_bound_and_late_full_parts`: And .224 → .296 and
  Or .776 → .704, both at unchanged c=.78125. Partial midpoints .1/.9
  replace 0/1; late complete-part expectations remain unchanged.
- Updated `test_derived_graded_part_revises_the_report`: MAIN and Assuming X
  strength 0 → .0004988913132181221 at unchanged c=.990010975730573;
  Assuming A remains (0,.99). Its A=.9 produces midpoint .45, not falsity.
- No existing MeTTa expectation or deterministic KE confidence pin moves.
  Focused suite: 17 tests PASS.

## Gates

All runtime jobs used the repository-pinned venv, `/nexus/Dev/OpenCog/bench/capped`,
`ulimit -v 16000000`, DISPLAY unset, stdin `/dev/null`, and outer timeouts.
The comparator used its standard freezes, seeds, stored runs and queue.
Runtime tree **78b6248a80d8**, PeTTa runtime **18c99706738d76f4**; benchmark labels
retain pre-rewrite HEAD plus the working diff, which is the same executable tree
as final code commit **dcdc890646dccfe6add7d57e327de416dafc9f84**.

| Gate | Result |
|---|---|
| `scripts/verify.sh` | PASS, 193 s: 164 MeTTa files; 1160 Python tests in 88 files, 23 expected failures and 4 skips; lint, import scaling, judgment scaling, ConceptNet and fuzzer PASS. Cache key `bed18c2748fe`. [Log](i183_lookup/midpoint/verify.log). |
| `compare.sh master <worktree> --quick` | PASS, accuracy identical in all 9 scored cases; 76 s measured comparison wall time. [Report](i183_lookup/midpoint/benchmarks/quick.md). |
| `compare.sh master <worktree> --full` | PASS, accuracy identical in all 22 scored cases; 150 s measured comparison wall time. [Report](i183_lookup/midpoint/benchmarks/full.md). |
| `compare.sh anchor <worktree> --canary` | PASS, four of six cases differ from anchor, inherited from master; no new blocking regression. 79 s measured comparison wall time. [Report](i183_lookup/midpoint/benchmarks/anchor-canary.md). |
| `compare.sh master <worktree> --curves` | Completed successfully: 10 families, 56 paired budget points, 0 changed errors, 0 missing or unsupported points; 612 s including queueing. [Report](i183_lookup/midpoint/benchmarks/curves.md). |

Reported comparison times exclude source archive preparation. The canary had
initial exit-127 launch attempts followed by successful runs; its final records
are successful and its verdict is PASS. No result was manually accepted or
replaced. The fuzzer used quick seed 1, budgets 100/500, 21 cases/62 workers,
38.12 s, and retained precisely the three known leaf-report flip failures;
no new or fixed blocker. Available query abort counters are zero.

The capture audit covers **85 distinct comparison pairs**. Every captured TV
against master is unchanged, including confidence and calibration. The **1,015**
changed captured rows are all relative to the older anchor, and their before/after
TVs and calibration scores exactly match the previous review round. See
[all moved captures](i183_lookup/midpoint/benchmarks/moved-values.jsonl) and
[the calibration summary](i183_lookup/midpoint/benchmarks/calibration.json).
Curves compare measured timing as well as error; equal budget errors do not
promise identical wall-clock times. Full has no timing flags or regressions.

The final executable diff from `adcd18f0` is the single strength expression
and its explanatory comment. Tests/contracts add the midpoint coverage and
derivation. `git diff --check` passes. All launched jobs completed and their
execution sessions were reaped; the admission pool has no remaining task job.

## Commits

- `dcdc890646dccfe6add7d57e327de416dafc9f84`: code, tests and contracts,
  **Read stored compound sources and midpoint partial proofs (#183)**.
- Its sole successor on `i183-lookup`: **Record #183 midpoint review, graded
  rows and final gates**, containing this report, previous rounds, measurement
  archives and the rounds/state entries. The hand-back supplies its final hash.

## Updated draft reply (not posted)

> Stored compounds read their ordinary source merge. Independent partial parts
> now contribute the midpoint of their probability interval, with confidence
> scaled by one minus its width: ((L+U)/2, (1-width)×min(cL,cU)). Thus A=(.5,.99)
> with B unknown contributes (.25,.495), avoiding a false endpoint claim.
> Revised with reports (.5,.1), (.4,.9), and (1,.99), the result is respectively
> (.275454,.521831), (.385268,.908927), and (.992647,.990097). The other graded
> rows give (.1,.927577) and (.726535,.180992). Decisive partial evidence is
> unchanged: the weak-report conflict is (.01,.990099), equal-confidence
> conflicts are (.5,.994975), and late evidence updates correctly. Cases 4–9
> retain .99, the complete-parts conflict retains (.333331,.993311), and all
> 58 previous review outputs and proofs are unchanged. Report-derived parts
> remain excluded from their own compound's evidence. Verification, quick/full
> comparisons and canary pass; all 56 curve errors match master. Child-order normalization
> and the previously documented shared-evidence limits remain outside this fix.

## Limits

The interval-to-confidence reading is a stated approximation, not a general
calibration theorem. Independent reports can conflict with the partial interval;
revision averages their evidence rather than imposing a hard interval constraint.
Partial producers remain scoped to stored compounds. Child order remains part
of key identity. The pre-existing part-read/shared-evidence weaknesses listed in
the previous report are unchanged. No master/main-checkout edit, push, merge or
GitHub write was performed.
