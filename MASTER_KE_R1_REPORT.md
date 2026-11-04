# Master KE correctness R1

Design: `/nexus/Dev/OpenCog/bench/results/fresh-design/master-ke-correctness-design.md`,
R1 targets A + E and their maps. Prototype evidence: its adjacent
`master-ke-correctness-evidence/`, using the grouped post-speed-up implementation.

## Checkout and commits

- Branch: `master-ke-r1`.
- Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/master-ke-r1`.
- Base: master `202b93791f23a04c5ef7670625dc8a803ada09f6`.
- Implementation: `3b16e693` — Model certain producer families with consequent base fallback.
- Test pin: `7f7d2811` — Pin exact certain-family variance and owner proof.
- This report is committed separately on the same branch. No push or merge.
- The `/tmp` import check resolved `pettachainer.__file__` to this worktree's
  `pettachainer/__init__.py`; its own repointed `.venv` supplied the runtime.

Implementation history (`git log --oneline master..` before the report-only commit):

```text
7f7d2811 Pin exact certain-family variance and owner proof
3b16e693 Model certain producer families with consequent base fallback
```

## Diagnosis and design

Master's ordinary sibling revision gave #167's A strength
`.8700105117879617`, below the independent count-law reference
`.9598253431259756`. The joint took a different numerical route. Certain
positive producers had no graph template. Repeated compound children could
also lose their answer entirely: `And(X,X)` with `X=And(B,O)` should be `.324`.

R1 groups producers with one stable `keysort` and `group_pairs_by_key`, keeping
the first admitted application per rule name in installation order. A certain
family becomes one conditional node with the disjunction of its distinct
antecedents, positive branch 1, and its consequent's empty-root parameter as
fallback. That parameter uses the existing configured-rate/population/uniform
reader and retains its proof and dependencies. Every selected rule owner is
recorded in the graph proof. The single-CTV template keeps its previous meaning.
Certainty uses numeric comparisons, so integer and decimal 1 spellings agree
for both STV and FTV input rules.
Without observations, admission requires a sourced root, preserving empty-family
and Assuming isolation behavior. No compatibility path or new helper was added.

Both compound readings and recursive producer installation remove duplicate
children. Discovery also starts from the goal's formula atoms: otherwise a
repeated nested compound can hide its atoms' reports behind the existing skip
for unobserved compound neighbours. This uses the existing formula lowering
and keeps the discovery, atom and parameter caps.

The post-speed-up prototype was the starting point. Its per-name rescan was
not reintroduced. The broad uncertain-STV and graph-admission variants remain
outside R1 because they change separate negative-branch and reader contracts.

## Size and regression references

`scripts/round_metrics.py::tokens` with `o200k_base` measures master **324,967**
and R1 **325,166**: **+199 core tokens**. Per file: source catalog +115,
event graph +76, source lowering +8. Tests and documentation are excluded by
that script's core definition. This is net growth; deletions do not exceed additions.

Seven new regression methods pin independent references:

| Case | Reference strength |
|---|---:|
| #167 A and B marginals; repeated A; integer/decimal STV/FTV | .9598253431259756 |
| #167 A and B joint | .9397380146889633 |
| One origin A / joint | .8996259351620948 / .8494389027431422 |
| Eight origins A / joint | .9989943852221346 / .998491577833202 |
| Explicit base .2, before/after inactive producer | .8394014962593517 |
| Explicit base with CTV child and report, A / C | .9596712898313778 / .968105629056865 |
| Neutral descendant, O / C before and after | .8912891216043767 / .9347284013035543 |
| Distinct redundant rule, before and after | .7071122230164403 |
| Repeated compound under And and Or | .324 |
| Repeated negated atom | .4 |
| CTV nested repeat with negative report / neutral report | .4021098863865393 / .20381353495738336 |

For independent origins, q is the product of their false probabilities under
Beta(ns+1,n(1-s)+1). Uniform independent consequent fallbacks give
P(A)=1-q/2 and P(A and B)=1-3q/4. The remaining pins come from the design's
independent enumeration and the unchanged event oracle, not candidate output.

## Gates

All PeTTa, test and benchmark jobs used `/nexus/Dev/OpenCog/bench/capped`,
matching worker slots, `ulimit -v 16000000`, unset `DISPLAY`, and `</dev/null`.
`PETTACHAINER_REPO` selected this worktree for comparisons. Comparisons use
`--no-fail-fast` to retain every flag. No scheduling/budget change: no curves requested.

- Focused final run: **PASS**, 14 tests in 17.092 seconds,
  `scratch/focused-numeric.log`.
- Final verify: **PASS**, all six gates, **303 seconds**, cache key
  `c5d96983a272`, on `7f7d2811`. MeTTa: **163 passed, zero failed**.
  Python: **1,083 tests**, 77 files / 604 units, 232.7 seconds with eight
  workers; **24 expected failures, one skip** unchanged. Its 4,646 query
  records contain **zero aborts**. Lint, import scaling, judgment scaling
  and ConceptNet passed; ConceptNet checked its two-result summary and abort
  markers (the runtime counter is unavailable there).
  Log: `scratch/verify-pinned.log`.
- Final quick fuzzer: **exit 1: six pre-existing BLOCKERs remain**, down from
  master's 56. See the complete inventory below.
- Final quick comparison: **PASS**, `accuracy changed in 0 cases`; 79 seconds,
  nine runs executed, 10 of 19 results reused. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/202b9379_vs_3b16e693_quick/report.md`.
- Full comparison: **PASS**, `accuracy changed in 0 cases`; accuracy identical
  in all 22 measured cases. Profile: 23 cases, 36 runs executed, nine of 45
  results reused, 270 seconds wall / 1,592 CPU-seconds. No regression or false
  timing flag. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/202b9379_vs_7f7d2811_full/report.md`.
- Canary comparison: **PASS**, `accuracy changed in 4 cases` relative to the
  older anchor `b4065459`. Its automatic comparison with master found no new
  blocking regressions. Six cases; 83 seconds; 11 runs executed, six of twelve
  results reused. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_7f7d2811_canary/report.md`.
- All comparisons and the fuzzer use the same runtime tree `d56819cb2289`;
  `7f7d2811` changes only the test pin relative to implementation `3b16e693`.
  PeTTa runtime digest: `eec735bf4d1d3e31`.

## Iteration evidence

The first implementation, superseded commit `5428c6c1`, passed verify (all six
gates, key `3e5af38047fe`, 287 seconds; 163 MeTTa files, 1,082 Python tests,
24 expected failures and one skip) and quick comparison (PASS, zero changed
accuracy cases, 94 seconds). Its fuzzer reduced 56 flags to eight, revealing
that deduplication recovered two CTV answers with small strength discrepancies:
`.4021098863865393 -> .40263586148151775` and
`.2038135349573834 -> .2037155133251074`. A bounded direct discovery probe
showed that seeding goal atoms restores both independent references. That
correction and its regression test passed another complete verify at
superseded commit `165294c8` (key `768c8d66777b`, 328 seconds, 1,083 Python
tests, 24 expected failures and one skip). Its quick comparison also passed
with zero accuracy changes (107 seconds). A separate admission probe then
found that the prototype's structural comparison rejected decimal 1 spellings.
The final implementation uses numeric equality and tests both spellings.
The queued fuzzer and unfinished full comparison for `165294c8` were cancelled
and reaped before changing the runtime. Final gates validate `3b16e693`.
Initial logs remain under `scratch/`.

### Moved test value

`tests/metta/test_implication_inversion.metta`, `logicKb`'s `(Ancestor a b)`:
strength stays **1**; confidence changes **.9998666844365203 -> .9999**.
A certain Parent fact and a certain-positive rule force Ancestor in every
world, so its exact variance is zero regardless of the fallback base. The
event-node contract maps zero variance to `.9999`. The complete proof pin
changes from `(by parentAncestor pab)` to
`(node (conjunction pab (by parentAncestor cpu) (population-prior (Ancestor $_0 $_1))))`,
retaining both the fact and rule owner and recording the fallback prior.
This is a justified non-BLOCKER pin update, not a strength regression or
overconfidence. The focused strict-determinism MeTTa run passed after the update
(`scratch/inversion-pin.log`). No other existing expected value was changed.
The design's no-moved-pins prototype accidentally excluded decimal-valued
certain rules; numeric admission exposes this one correct confidence/proof move.

## Flag classification and limits

A flag is a BLOCKER only when an answer is wrong,
overconfident or lost, or work is unbounded. Bounded performance changes are
follow-ups, even when the benchmark's own verdict calls them regressions.

### Quick fuzzer: all 56 master flags accounted for

Final target/runtime commit: `3b16e693a51ae11e34e8c35ccd079b716a6f5074`, with
the runtime path inside this worktree. Seed **1**, budgets **100/500**, k **800**,
threshold **.001**, per-worker timeout **45 s**, eight workers. The campaign
took **44.73 s**, executed **65** worker programs over **21** event/cost cases,
and flagged **0/3** ProbLog differential cases. Fuzzer inputs were unchanged;
SHA256 `da62118f50206c58be5c0bfcd9bd8ff877b63204fff40e43348d505d38ef6ee4`
matches the design's master campaign.

| Invariant | Master | R1 | Classification |
|---|---:|---:|---|
| wrong_strength | 23 | 0 | resolved |
| overconfident_variance | 5 | 0 | resolved |
| overconfident_error | 5 | 0 | resolved |
| neutral | 2 | 0 | resolved |
| flip | 3 | 3 | BLOCKER: wrong response to evidence |
| inactive | 4 | 0 | resolved |
| repeat | 7 | 0 | resolved |
| frechet | 4 | 0 | resolved |
| identity-subset | 1 | 1 | BLOCKER: wrong and overconfident answer |
| false | 2 | 2 | BLOCKER: nonzero answer to a false conjunction |
| Total | 56 | 6 | 50 resolved; no new flags |

Every remaining flag is individually accounted for:

| Repro stem | Expected | Actual | Classification / scope |
|---|---|---|---|
| leaf-report-And-1-0-flip | flipping report lowers C | .4 -> .4 | BLOCKER; uncertain-STV template, design F |
| leaf-report-Or-1-0-flip | flipping report lowers C | .4 -> .4 | BLOCKER; design F |
| leaf-report-Not-1-0-flip | flipping report raises C | .4 -> .4 | BLOCKER; design F |
| identity-soft-1-0-identity-subset | Q <= .9990288568257487 | 1 | BLOCKER; R2 |
| identity-ground-1-0-false | 0 or no answer after hard Not(I) | .0562265722615577 | BLOCKER; R2 |
| identity-exists-1-0-false | 0 or no answer after hard Not(I) | .0562265722615577 | BLOCKER; R2 |

Summary: `scratch/fuzz-r1/summary.md`; complete results:
`scratch/fuzz-r1/cases.jsonl`; paired JSON/MeTTa repros:
`scratch/fuzz-r1/repros/<stem>.json` and `<stem>.metta` (flip variants include
`<stem>-variant.metta`). Every shrink reached its deletion fixed point;
identity cases took one trial each, flip cases zero; none hit the 24-trial cap.

The cost probe at 64/128/256/512 producers took
**4,472 / 6,726 / 13,382 / 26,694 inferences**. The last doubling ratios are
1.990 and 1.995; no bounded-work violation. This includes the numeric certainty
check and grouped selection, replacing the rejected quadratic prototype.

### Full-profile legacy differential flags

The full profile also runs its separate **100-KB seed-22** campaign with
budgets **100/2000**, k **5**, threshold **.05**. Master and R1 both have
**five flagged KBs / six wrong-strength queries**, identical mean error
`.004871245768143161`, **364** answers, zero crashes, zero unsupported cases,
zero lost answers outside documented gaps, and zero budget regressions.
These six wrong answers are **pre-existing BLOCKERs**, not R1 regressions:

| Seed / query | Independent exact | R1 (= master) |
|---|---:|---:|
| 22000086 / B a | .7771348705570272 | .8530220049943202 |
| 22000092 / B a | .816721953551839 | .5662251655629139 |
| 22000092 / C a | .42251885520669324 | .29292809840000006 |
| 22000131 / B a | .8247825480239992 | .7085714285714286 |
| 22000153 / A b | 1 | .6630434782608695 |
| 22000159 / A b | .7785063059010777 | .72 |

Artifacts: the full report's
`runs/candidate/fuzz/all_n100_s22.fuzz/{summary.md,cases.jsonl}`. This benchmark
campaign emits no shrink repros, so it supplies no deletion-fixed-point claim.
Its 34 latent-premise, 12 root-prior and 46 derived-population-prior gap labels
are documented differences between public open-world reads and ProbLog
(`docs/metta/fuzzing.md`), classified as FOLLOW-UP capability/contract differences,
not newly lost supported answers. The five error KBs remain real correctness debt.

### Canary and intermediate flags

The canary's five raw anchor flags are inherited on master. They are not
R1 regressions; its own final `regressions` list is empty. Classification under
the brief's correctness rule:

| Flag | Anchor -> R1 | Classification |
|---|---|---|
| live b50/5 shifts/s1 error | .0981271 -> .1050206 | BLOCKER: existing answer-accuracy debt, also on master |
| same case Brier | .02632 -> .03195 | BLOCKER: same existing accuracy debt |
| same case regret | 59.78 -> 72.78 | FOLLOW-UP: decision-quality metric, not by itself a wrong-answer proof |
| conflict pln-stated/l/spq4/s1 normalized seconds | 8.957 -> 14.43 | FOLLOW-UP: bounded time; raw master 25.74 -> R1 23.38 is progress |
| conflict pln-reliable/l/spq4/s1 normalized seconds | 8.769 -> 49.2 | FOLLOW-UP: bounded time, also behind on master |

Other anchor accuracy changes improve error: stated conflict
`.389515 -> .0318147`, reliable conflict `.107014 -> .0540739`, and scale
`.00303377 -> .00264726`. ONA errors are unchanged. All six candidate accuracy
runs complete; the live and conflict coverage is 1.

The dedicated timing host could not find this worktree's `.venv/bin/python`
and returned 127 for six timing attempts. The standard runner fell back to
successful local accuracy runs. This is a FOLLOW-UP infrastructure/timing
limitation, not a lost answer; no remote environment was changed. Several
local-versus-anchor timings are marked `load differs`, so those ratios are
not evidence of a new slowdown.

The initial quick replay/b50/s4 timing flag did not repeat on its paired
rerun and was not counted (FOLLOW-UP/no correctness blocker). The two initial
CTV repeat flags were real BLOCKERs resolved by goal-atom discovery. The
decimal-admission defect was a correctness BLOCKER resolved before hand-back.
The one stale MeTTa pin was a resolved non-BLOCKER, as justified above.

R1 retains the 24-statement discovery limit, twelve atoms and twelve parameters.
Over-cap/unsupported models retain the ordinary route and its existing limits.
Uncertain-STV flip handling, identity joint conditioning/posterior reuse (R2),
and refined CTV / wide-antecedent handling (R3) are outside this round.

The design's R1 table predicts four residual flags, but its scope leaves two
hard-false identity flags for R2 as well. The measured final inventory, rather
than that prediction, is authoritative.

All jobs started for the round completed or were explicitly cancelled and
reaped before hand-back. Final benchmark/verification artifacts are tied to
the implementation tree above; the last commit only adds this report.
