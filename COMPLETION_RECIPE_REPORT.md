# Antecedent-completion recipe

Branch: `completion-recipe`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/completion-recipe`.
Base: `80ea56284ada130c87dc0f261f0aa0c826752fba`.

## Design as built

The compiler emits a leading contextual instruction carrying
`(completion-recipe target compound context consequence-index opening)`.
Positions count statement inputs, excluding CPU instructions. The observation is
at `consequence-index`; positions before it are sibling inputs, including a
refined rule's truth input. The recipe shares the original executable variables;
it contains no truth values or current answers. Keeping the recipe on the existing
`ReadLikelihoodContext` instruction lets the existing row builder retain it without
changing any reserved construction or journal files. Its context result is unused.
Ordinary likelihood-context reads retain their existing behavior.

Evaluation selects the recipe directly from the leading instruction. It obtains
the observation's registered key by position, preserving the open keys retained by
row construction. A positional cursor replaces per-statement key-shape
classification. The compound, target and opening polarity are compiler data.
Consequence reads retain their observation exclusions; sibling reads retain the
compound/consequence exclusions, known-false exception, closed pin and fallback
under the target's opening condition. Evidence and dependency handling remain in
the existing reader. Evidence-role selection also uses the recipe instead of the
completion proof head. Refined-rule score registration skips the metadata to reach
its original first executable input.

The public raw `add-to-kb` entry normalizes a completion lacking a recipe once,
at ingestion. One preparation fold extracts its static compound, input positions
and opening polarity. Source-compiled rows already have the recipe and bypass
this normalization. There is no evaluator fallback to rediscover roles.

Removed production functions:

- `sk-compound-evidence-step`
- `sk-last-statement-step`
- `sk-completed-given-step`

The role-discovery portion of `sk-completion-state` is gone. Its remaining work
implements the read policies. The existing `sk-inverted-proof?` replaces a duplicate
inline inversion classifier. `sk-completion-proof?` remains live in the reserved
skeleton's population-prior/waiter routing; evaluation no longer calls it.

The positional iterator and premise kernel remain separate. Combining them was
rejected by the pinned strict compiler with residual list type checks and an
unproved `fold-flat` call. This is a demonstrated specialization boundary, not a
convenience wrapper. A later attempted `foldr-flat` cleanup used the wrong callback
argument order, was reverted, and its runs were stopped. Final validation must be
read from the final-code records below, not the discarded `daa6e5530` build.

## Size and symbol audit

Counts use the supplied `scratch/core_count.py` and `o200k_base`; executable lines
exclude blank and comment-only lines. Python production code, Prolog and third-party
code are unchanged.

| Scope | Before | After | Delta |
|---|---:|---:|---:|
| Core tokens | 323,864 | 323,664 | -200 |
| Core plus third-party tokens | 341,549 | 341,349 | -200 |
| Touched production MeTTa tokens | 80,154 | 79,954 | -200 |
| Core executable lines | 16,088 | 16,122 | +34 |
| Touched production MeTTa executable lines | 3,939 | 3,973 | +34 |

The token count includes consolidating duplicated policy comments into concise
recipe documentation and references to the existing design documents. This is a
reduction in runtime role discovery, not a reduction in executable line count.
Four preparation/access/iteration functions replace three evaluator scanners, so
there is one more named production function overall.

Symbol audit: zero hits for all three deleted names across `pettachainer/`,
`third_party/`, `tests/` and `docs/`. No reserved files were edited.

## Tests and moved values

No existing expected truth value, proof, scheduling score or API signature changed.
The existing evidence-role unit probe now supplies the explicit completion recipe
instead of relying on its proof head; its expected values are unchanged.

New tests cover recipe/executable variable sharing, refined-truth registration,
raw-ingestion parity for And/Or and positive/negated targets, and positions after
ground CPU instructions are removed. Raw tests query the live process because
subprocess replay cannot include a raw Janus mutation. The final focused run passed
both tests (four raw-ingestion subcases).

Diagnostic queries of `(And (A $x) (C $x)) -> (C $x)` and the Or variant matched the
harness's frozen master build, with one report and with two independent reports of
C. Both versions returned the same population prior for A,
`(STV 0.30000555540123885 0.9)`.

## Gates and benchmarks

- `scripts/verify.sh`: **PASS**, all six gates. MeTTa: 162 passed, 0 failed.
  Python: 990 tests in 63 files / 590 units, 64 expected failures and 1 skip;
  4,493 query rows, 0 aborts. Import scaling, judgment scaling and ConceptNet
  passed. Total wall time 1,081 s with four workers. Cache PASS key
  `b958e0533451`. Log: `scratch/verify-final.log`.
- Focused recipe tests: PASS, 2 tests / 4 raw-ingestion subcases
  (`scratch/recipe-python-final.log`).
- `compare.sh master <worktree> --full`: **PASS**, accuracy changed in 0 cases;
  23 cases, including the standard n100/s22 fuzzer (22 cases have numeric
  accuracy summaries), 6 runs executed and 39 of 45 results reused. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/80ea5628_vs_80ea5628-d93cd3c16_full/report.md`.
  Fresh local job wall times: scale l/spq16/s1 151.25 -> 152.55 s;
  learned stage 3 untimed mined b50/r50/h10/s3 82.22 -> 82.41 s.
  The report's seconds metrics are 136.7 -> 137.8 and
  79.9 -> 80.15 respectively. Learned peak RSS rose from 607.0 to 788.7 MB
  (+181.7 MB), below the gate's regression threshold; scale peak RSS was
  essentially unchanged at 1,359 MB. No speedup or memory reduction is claimed.
- `compare.sh anchor <worktree> --canary --retime`: **PASS**, all 12 fresh
  dev-server runs exit 0. Accuracy changed in 4 of 6 cases versus the older
  anchor; those differences are on master too, not new answer changes here.
  The report lists 9 inherited anchor gaps and no blocking regression:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_80ea5628-d93cd3c16_canary-retime-20261030T001016/report.md`.
- Fresh paired dev-server `compare.sh master 202619a0 --canary --timing --retime`:
  **PASS**, accuracy changed in 0 cases; all 12 fresh runs exit 0.
  Report: `/nexus/Dev/OpenCog/bench/results/compare/80ea5628_vs_202619a0_canary-retime-20261030T002054/report.md`.
  Fresh job wall times (master -> candidate, dev-server load 1):
  live 10.40 -> 10.61 s; scale 35.42 -> 35.55 s; reliable conflict
  62.89 -> 63.31 s; stated conflict 25.97 -> 26.05 s; ONA conditioning
  10.52 -> 10.54 s; ONA identity matching 14.44 -> 14.41 s.
  This is the required direct paired retime of the canary's anchor timing gaps;
  it confirms no timing regression relative to master.

The final runtime tree is `eb830a1e6ace3b2b6ed787cce1d79e7579ed9c6c`.
The uncommitted benchmark label `80ea5628-d93cd3c16` and commit `202619a0`
contain exactly this same runtime code. The earlier quick comparison passed
with zero accuracy changes, before the final comment consolidation.

The first timing attempt failed with exit 127 because dev-server lacked this
worktree's interpreter path. Its summary PASS is not used as timing evidence.
An independent remote venv was copied from that host's matching pinned venv,
then repointed under this worktree's path; no shared venv was modified. The
successful anchor retime replaced all 12 failed/missing timing observations.
The full comparison uses its standard local timing policy.

Before investigating source-level timing differences, the documented SWI
module-table condition was checked with a read-only public-module/prefix probe.
On dev-server both frozen master and candidate have 3,965 procedure entries in
4,096 slots (96.8018% occupancy). Both load the same SWI 9.3.33 library,
SHA-256 `d39628926f34c1e47386b12c1f1ca042c4b62263fd58732e038ddaa83f849746`.
The local installed library is SHA-256
`8ae99d54a7773df741a2f66b95d8924b684118acc0ba67b571df4cf830d6eba5`,
with the same occupancy. Logs: `scratch/module-table-{local,dev}.log`.
This confirms the documented near-full-table condition; occupancy alone is not
proof of a causal timing difference. No table mutation, engine patch, padding,
stack reserve or runtime tuning was introduced.

All PeTTa, test and benchmark invocations used the pinned worktree environment,
`/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, unset `DISPLAY`, and
stdin from `/dev/null`. Final verify uses four workers and a declared 16,000 MB
peak. Earlier overlapping draft verification runs were canceled; they are not
claimed as final gates. The benchmark harness owns its frozen builds and seeds.

## Commits and limits

The unchanged suite still has 64 expected failures and one skipped nightly test;
this cleanup does not correct those numerical or coverage limitations.
ConceptNet passed by its abort-marker scan; its strict defect counter is
unavailable in that gate. Validation covers implementation commit `202619a0`;
the subsequent report-only commit changes no runtime or test code.

Implementation commit:

`202619a04aa6bf83eec44b5f4db8ce1058970afe Compile antecedent-completion input roles once`

The report is recorded in a subsequent documentation-only commit. Both commits
use the exact trailers from the brief. No push or merge was performed.

No master/main/other-worktree code, reserved files, shared venv, GitHub state,
remote branch or admission service was changed. Standard verify-cache, runtime-cache and benchmark-output writes occurred
through the approved runners. The independent remote venv and diagnostic scripts
were created only under the owned completion-recipe path.
