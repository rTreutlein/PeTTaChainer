# Merge 2: compound outputs from the event node

Status: **stopped at the largest green state; implementation scope not achieved**.
Both deletion experiments were restored. This branch changes documentation only;
`pettachainer/`, `third_party/`, `tests/` and the public API are byte-identical to
`2ad70bdf`. No compiler/evaluator replacement, deleted runtime mechanism, token
saving, or speed improvement is claimed. Do not treat this as a completed output
merge.

Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge2-outputs`.
Branch: `merge2-outputs`. Starting master: `2ad70bdf`.

## Commits

- `bdea57a5` — initial design, full producer/consumer audit and baseline footprint
  in `docs/metta/node_outputs.md`.
- Final report commit — this report and measured design outcome. No runtime change.

All commits use the brief's Co-Authored-By and Claude-Session trailers. No push,
merge, GitHub write, edits to master, main-checkout code, or other worktrees.
The mandated verification and benchmark tools retain their own shared cache and
result bookkeeping.

## Diagnosis and design

At this baseline, the old output dispatcher already installs EventNodeMessage,
EventNodeJeffrey and EventNodeJoint rows. There is no parallel legacy numerical
implementation inside it: it selects ProjectAll and emits those node rows for
facts, conclusions and eligible inversion outputs. Removing the installer would
remove these behaviors. Renaming it would not establish redundancy or satisfy
the requested mechanism deletion.

The remaining conditional-export path has a different job. It descends a rule's
conjunctive consequent, projects its conditional TV (both branches for a CTV),
and exports a nested implication over universally scoped variables. The source
rule owns the exported application, including evidence identity and withdrawal.
The event-node design's section 6 explicitly reserves that rule-level FTV path
from ground-event replacement. The experiments below confirm that the current
node rows alone do not provide its answers.

The remaining conditional quotient reads a KB-derived joint P(B and D) and the
written event D's population-rate key. Its zero-denominator behavior is failure,
its strength is min(1, joint/rate), and its confidence is min(c_joint,c_rate).
A local event marginal over independent leaf inputs cannot simply substitute
for that general KB-derived joint and denominator. This is a source audit, not
an executed quotient-replacement experiment. `query_lowering.metta` was never
edited; merge 1's files and worktree were left alone.

The design is in `docs/metta/node_outputs.md`. The brief's stopping rule was
applied rather than changing expected answers, inventing a renamed installer,
or claiming a numerical correction without a D0 derivation.

## Experiment 1: remove the 0.99 open-proof priority factor

Change: replace the open/bound proof score branch of term-confidence with
plain tv-confidence. Nothing else in production or tests changed.

Immediate strict MeTTa suite: **160 passed, 1 failed**. Failure:
`tests/metta/test_hypothesis_rules.metta:79` (scheduler scores, not STV answers):

```text
expected ((A 0.0099) (A 0.0099) (A 0.009000000000000001)
          (C 0.0099) (C 0.0099) (C 0.009000000000000001))
actual   ((A 0.009999000099989962) (A 0.01) (A 0.009000000000000001)
          (C 0.009999000099989962) (C 0.01) (C 0.009000000000000001))
```

The test stops at that assertion, so later assertions in that file were not
validated by this experiment. All other 160 files passed.
Log: `scratch/metta-no-discount.log`.

The standard quick comparison of this frozen experiment completed:

```text
PASS
accuracy changed in 1 cases
report: /nexus/Dev/OpenCog/bench/results/compare/2ad70bdf_vs_bdea57a5-d0e7ed832_quick/report.md
```

This threshold PASS does **not** satisfy the brief's stronger no-answer-movement
gate. `supplynet stage 3 timed b100 s3` changed:

| Metric | Baseline | No discount |
| --- | ---: | ---: |
| mean posterior error | 0.001985701064877706 | 0.0019856998213202003 |
| Brier | 0.17123147388436308 | 0.17123147558118973 |
| degraded error | 0.008598546648212992 | 0.008598538265364782 |
| producing error | 0.0020647004812875346 | 0.0020646995091489102 |
| coverage | 1.0 | 1.0 |

No D0 oracle derivation proves the moved answers more correct. A lower aggregate
error alone supplies no such proof. The report's timing rows say `load differs`;
its apparent speedups are not equal-load performance evidence. The experiment
was rejected and the factor restored. Full/curves/canary runs of this rejected
scheduler were not pursued after its failing immediate gate and changed quick
accuracy; there is no surviving scheduling change requiring curves.

Frozen experiment: `bdea57a5-d0e7ed832`, runtime tree
`f88145100d7e65fb5a4cf1b35f3d3a8482fde087`.
Log: `scratch/compare-no-discount-quick.log`.

## Experiment 2: delete conditional export, retaining node output rows

With scheduling restored, delete compile-consequent-implications,
consequent-projection-tv, their source call, the consequent-projection evidence
unwrapping, and the now-unused AndMarginalProjection formula. Leave the
observed-message, predicted-update and joint node paths intact.

Immediate strict MeTTa suite: **158 passed, 3 failed**:

- `tests/metta/test_nested_consequent_projection.metta:19`: expected
  `(STV 0.9999997023811048 0.999686126673656)`, actual `()`.
- `tests/metta/test_source_gate_judgment.metta:13`: expected
  `((STV 0.8655786350145539 0.03980772466060817))`, actual `()`.
- `tests/metta/test_warm_and_projection.metta:84`: the wrapped failed-query/late-input
  scenario no longer satisfies warm-stale-matches?; expected true, actual `()`.

The first two tests constrain their proof shape. To distinguish an unavailable
proof pattern from actual answer loss, run an independent probe with a completely
open proof and TV, at the same 300-step budget, cold then warm:

```metta
!(compileadd projectedKb (: rule
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 1 1)))
!(collapse (query 300 projectedKb (: $p
   (Implication (AcceptSource S) (Implication (A $x) (C $x))) $tv)))

!(compileadd wrappedGate45 (: accepted (AcceptSource S) (STV 1 1)))
!(compileadd wrappedGate45 (: rule
   (Implication (AcceptSource S)
      (And (Metadata S) (Implication (A $x) (And (B $x) (C $x)))))
   (STV 0.8 0.6)))
!(collapse (query 300 wrappedGate45 (: $p (Implication (A $x) (C $x)) $tv)))
```

Both queries return **no rows**, cold and warm, with export removed. After
restoring it, both return their exact baseline STVs above, cold and warm.
This is real answer loss. No expected values were changed to accommodate it.

Logs and reversible patch: `scratch/metta-no-conditional-export.log`,
`scratch/conditional-export-probe.metta`,
`scratch/probe-no-conditional-export.log`,
`scratch/probe-restored-conditional-export.log`,
`scratch/no-conditional-export.patch`.

## Validation of the restored runtime

Before experiments: `scripts/verify.sh` **PASS**, 351 seconds after admission.
Strict MeTTa **161/0**; Python **967 tests, 125 expected failures, 1 skip**;
all six gates passed; Python **4,430 query rows, zero aborts**; judgment scaling
**3 query rows, zero aborts**. Log: `scratch/verify-baseline.log`.

Final `scripts/verify.sh`: **PASS**, 420 seconds after admission. Strict MeTTa
**161/0**; Python **967 tests in 59 files (587 units), 125 expected failures,
1 skip**; all six gates passed. Python **4,430 query rows, zero aborts**;
judgment scaling **3 query rows, zero aborts**. Verification recorded PASS
under key `f6db8cbded38`. Log: `scratch/verify-final.log`.

Final standard full comparison against master:

```text
PASS
accuracy changed in 0 cases
23 cases; 0 runs to do; 23 of 23 results reused
report: /nexus/Dev/OpenCog/bench/results/compare/2ad70bdf_vs_bdea57a5_full/report.md
```

Final standard anchor canary:

```text
PASS
accuracy changed in 4 cases
report: /nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_bdea57a5_canary/report.md
```

Those four differences are existing anchor-to-master differences, not new
merge-2 changes: live b50 5 shifts s1, both conflict cases, and scale m spq4
r10 s1. The anchor report lists nine nonblocking flags as also present on
master, and zero progress toward the anchor. Its main error comparisons are:

| Case | Anchor error | Retained baseline error |
| --- | ---: | ---: |
| ONA conditioning s1 | 0 | 0 |
| ONA identitymatching s8 | 0.4375 | 0.4375 |
| live b50 5 shifts s1 | 0.09813 | 0.105 |
| conflict pln-stated l spq4 s1 | 0.3895 | 0.03181 |
| conflict pln-reliable l spq4 s1 | 0.107 | 0.05407 |
| scale m spq4 r10 s1 | 0.003034 | 0.002647 |

**Fresh timing limitation:** the default remote timing attempts all exited
127 because that host lacks this worktree's interpreter:

```text
/usr/bin/time: cannot run /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/merge2-outputs/.venv/bin/python: No such file or directory
```

The standard report nevertheless reports PASS using stored successful results
for the identical runtime tree; its compare.json candidate records have exit 0,
and use older successful timing records. Preserve the distinction between these
stored successes and the six failed fresh timing attempts. Evidence:
`scratch/compare-final-canary.log`, `scratch/canary-remote-report.md`, and
`scratch/canary-remote-compare.json`; one failed timing stderr is
`/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_bdea57a5_canary/runs/candidate/ona/conditioning_s1_roman@dev-server.err`.

A second standard invocation with the documented `BENCH_TIMING_HOST=` local
setting also returned PASS, but reused verdict `50c4473597ea` of
`2026-10-29T10:05:11` instead of executing cases. Therefore it does not supply
fresh local timings either. Log: `scratch/compare-final-canary-local.log`.
No benchmark harness or external-host configuration was modified to hide this
limitation.

Reusing identical runtime-tree results is expected: the restored runtime has
exactly the baseline tree. These comparisons validate the retained state, not
the rejected deletions or an implemented node replacement. Speed is unchanged
by identity; no runtime performance improvement is claimed.

Every PeTTa, test and benchmark invocation used `/nexus/Dev/OpenCog/bench/capped`,
`ulimit -v 16000000`, DISPLAY unset, stdin from `/dev/null`, and a bounded
`timeout`. Suites used `scripts/test_metta.sh` / `scripts/verify.sh` and the
worktree's pinned executable. Probes used that same `.venv/bin/petta` from
`pettachainer/metta` to retain runtime import resolution. No polling shell
wait loop or `pgrep -f` was used. All tool sessions are collected before hand-back.

## Moved values and API

Accepted moved test/answer values: **none**. `tests/` and EXPECTED_FAILURES are
unchanged (122 calibration entries, checked by parsing the source dictionary). The experimental moved scores/benchmark numbers and lost answers are
listed above, and all their production changes were restored. API.md and every
public signature are unchanged. No D0 oracle correction is claimed.

## Token footprint

Counter: `scratch/core_count.py`, `tiktoken` / `o200k_base`, same definition as
the brief. Core **327,208 -> 327,208**; third party **17,685 -> 17,685**;
combined **344,893 -> 344,893**. Net runtime saving **0**.
Comments/declarations are included; docs, tests and benchmark/simulation files
are outside the core definition. Every counted file follows.

| File | Before | After | Saved |
| --- | ---: | ---: | ---: |
| `pettachainer/metta/bootstrap.metta` | 1,522 | 1,522 | 0 |
| `pettachainer/metta/compiler/compiler.metta` | 295 | 295 | 0 |
| `pettachainer/metta/compiler/query_lowering.metta` | 7,746 | 7,746 | 0 |
| `pettachainer/metta/compiler/rules.metta` | 19,542 | 19,542 | 0 |
| `pettachainer/metta/compiler/runtime_encoding.metta` | 1,058 | 1,058 | 0 |
| `pettachainer/metta/compiler/source_lowering.metta` | 14,538 | 14,538 | 0 |
| `pettachainer/metta/core/logic_config.metta` | 1,203 | 1,203 | 0 |
| `pettachainer/metta/core/logic_configs/pln.metta` | 102 | 102 | 0 |
| `pettachainer/metta/core/logic_configs/predicate_logic.metta` | 75 | 75 | 0 |
| `pettachainer/metta/core/types.metta` | 4,220 | 4,220 | 0 |
| `pettachainer/metta/petta_chainer.metta` | 243 | 243 | 0 |
| `pettachainer/metta/prolog/context_overlay.pl` | 4,488 | 4,488 | 0 |
| `pettachainer/metta/prolog/event_node.pl` | 6,991 | 6,991 | 0 |
| `pettachainer/metta/prolog/ingestion.pl` | 4,559 | 4,559 | 0 |
| `pettachainer/metta/prolog/runtime_helpers.pl` | 55,976 | 55,976 | 0 |
| `pettachainer/metta/prolog/sorts.pl` | 2,518 | 2,518 | 0 |
| `pettachainer/metta/runtime/backward/diagnostics.metta` | 1,494 | 1,494 | 0 |
| `pettachainer/metta/runtime/backward/evaluation.metta` | 100,831 | 100,831 | 0 |
| `pettachainer/metta/runtime/backward/forgetting.metta` | 3,732 | 3,732 | 0 |
| `pettachainer/metta/runtime/backward/skeleton.metta` | 32,542 | 32,542 | 0 |
| `pettachainer/metta/runtime/backward/upward.metta` | 5,701 | 5,701 | 0 |
| `pettachainer/metta/runtime/base_rates.metta` | 1,804 | 1,804 | 0 |
| `pettachainer/metta/runtime/evidence.metta` | 7,074 | 7,074 | 0 |
| `pettachainer/metta/runtime/forward/aggregates.metta` | 6,012 | 6,012 | 0 |
| `pettachainer/metta/runtime/forward/schema.metta` | 1,926 | 1,926 | 0 |
| `pettachainer/metta/runtime/hypothesis_mining.metta` | 4,792 | 4,792 | 0 |
| `pettachainer/metta/runtime/hypothesis_review.metta` | 2,875 | 2,875 | 0 |
| `pettachainer/metta/runtime/ingest.metta` | 530 | 530 | 0 |
| `pettachainer/metta/runtime/kb_index.metta` | 608 | 608 | 0 |
| `pettachainer/metta/runtime/knowledge_store.metta` | 5,238 | 5,238 | 0 |
| `pettachainer/metta/runtime/observed_predicates.metta` | 486 | 486 | 0 |
| `pettachainer/metta/runtime/query.metta` | 3,477 | 3,477 | 0 |
| `pettachainer/metta/runtime/scheduling.metta` | 1,118 | 1,118 | 0 |
| `pettachainer/metta/runtime/skeleton_journal.metta` | 8,514 | 8,514 | 0 |
| `pettachainer/metta/runtime/values.metta` | 2,857 | 2,857 | 0 |
| `pettachainer/__init__.py` | 131 | 131 | 0 |
| `pettachainer/pettachainer.py` | 8,149 | 8,149 | 0 |
| `pettachainer/pln_validator.py` | 758 | 758 | 0 |
| `pettachainer/query_diagnostics.py` | 1,483 | 1,483 | 0 |
| `third_party/pln_formulas/metta/compute_inverse.metta` | 515 | 515 | 0 |
| `third_party/pln_formulas/metta/distributions.metta` | 5,693 | 5,693 | 0 |
| `third_party/pln_formulas/metta/truth_values.metta` | 11,477 | 11,477 | 0 |

## Symbol audit

Deleted symbols in the final branch: **none**. A zero-hit deletion audit cannot
be claimed: the mechanisms remain live in the largest green state. The following
`rg -n -F NAME pettachainer/ third_party/ tests/ docs/` audit gives matching-line
counts by directory (substrings included), explicitly showing the retained path.

| Retained symbol | pettachainer/ | third_party/ | tests/ | docs/ |
| --- | ---: | ---: | ---: | ---: |
| `compile-outputs` | 6 | 0 | 0 | 4 |
| `compile-node-rows` | 5 | 0 | 0 | 1 |
| `compile-node-joints` | 4 | 0 | 0 | 2 |
| `compile-consequent-implications` | 5 | 0 | 0 | 1 |
| `consequent-projection-tv` | 3 | 0 | 0 | 1 |
| `consequent-projection` | 7 | 0 | 4 | 3 |
| `AndProjection` | 2 | 2 | 0 | 2 |
| `AndMarginalProjection` | 2 | 2 | 0 | 1 |

The scheduling factor also remains at runtime/scheduling.metta:40. Raw token
snapshots and audit tables are in `scratch/tokens-before.json`,
`scratch/tokens-before.txt`, `scratch/tokens-after.txt`,
`scratch/token-table.md`, and `scratch/symbol-audit.md`.

## Limits and next work

The requested complete deletion is **not done**. In particular, output dispatch,
node-row installers, conditional export, the conditional quotient and the
priority factor all remain. No unified replacement was built after the
explicit stopping condition was reached. Deleting the entire output installer
or substituting a local marginal for the joint quotient was not executed;
their obligations above are source-derived, not runtime proof of impossibility.

A future implementation would need to represent/export open-variable conditional
consequences with the same source ownership, CTV branches and universal scope,
and provide the existing KB-derived joint conditional with the same denominator
and confidence contract. That work must coexist with merge 1's implication
lowering. The present result only establishes that the currently available node
rows are insufficient for these deletion-only experiments. It does not prove
that an answer-preserving redesign is impossible.

No master or other worktree edits, no merges, no pushes, no GitHub writes.
