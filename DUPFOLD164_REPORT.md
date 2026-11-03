# Issue #164: identical rule replay (round 2)

Branch: `dupfold164`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/dupfold164`.
Original base: `5041ce4bbc13319ba98feee84dbf78ae0a4731a1`.

## Root cause and replacement

Facts already pass through `kb-fact-present?`, but `kb-add-rule!` allocated a
permanent rule identity on every insertion. Replaying a refined rule therefore
installed multiple instance-fold producers. Their folded evidence then entered
revision repeatedly: the issue's positive branch moved from the correct
single-insertion STV `0.81651376146789 / 0.10802775024777006` to
`0.8425196850393701 / 0.12366114897760463` after three insertions.

The live installation boundary now selects candidates through the existing
`rule_name_index`, reads their installed rule by id, checks liveness, and
compares conclusion and premises together by nonbinding alpha identity.
It returns the existing id before performing installation effects. Comparing
both terms together preserves variable sharing. Different proof names and
different applications remain distinct. Temporary and backward installations
retain their original behavior.

The gated path similarly checks its existing scalar-keyed gate store before
registering a duplicate. Clearing a user rate withdraws its live installations;
restoring the rate installs them again. Named withdrawal removes both the
installed and gated rows, so exact re-addition can reinstall under fresh ids.
No second ingestion store, native admission predicates, or replay wrapper is
retained. The single-use name-registration helper was inlined into installation,
which already computes the name for lookup.

A newly published live fact returns `true` from `kb-add-expr`; an existing fact
returns the existing no-op result. `compileadd` uses these publication results
to run mining and gap closure only when a fact was added. This reuses the fact
path's existing presence check and preserves callback order. Source validation
and public signatures are unchanged; `compileadd` still returns compiler
products for accepted replays.

## Regressions

The retained round-1 tests cover rule/fact replay before observations, after
observations and after a warm query; positive and negative CTV branches;
repeated queries; later independent observations; distinct named reports; and
raw compiled replay. Added controls cover:

- Alpha-renamed source replay and variable-sharing distinctions.
- Distinct rule proof names retaining separate installations.
- Live and gated rule withdrawal/re-addition, including fresh ids, retired
  answer removal and restored answers.
- Gated replay both before and after a user rate, including clear/set cycles.
- Fact replay not advancing mining observations; another proof still does.
- Link replay not closing newly introduced gaps; a new named link still does.

The existing source-catalog normalization test now withdraws complete rule
installations before re-adding their raw products, rather than deleting only
catalog metadata while leaving the rules live. Its model/formula assertions
are unchanged. An identical live rule must not rebuild partially erased
metadata as an ingestion effect.

No existing expected test values were changed. The original positive-branch
oracle is the single-insertion result; the negative branch uses its analogous
eight samples. Later observations use prior count `800 * 0.1 / 0.9`, with each
sample counted once.

## Validation

- `scripts/verify.sh`: **PASS**, **595 s**, cache key `9d5c9475aaa0`.
  All six gates passed: lint, strict MeTTa (163 files), Python (1051 tests,
  601 units, 24 expected failures, 1 skip), import scaling, judgment scaling,
  and ConceptNet (2 answers). Python recorded 4592 query rows with 0 aborts;
  judgment scaling recorded 3 with 0 aborts.
- Final ingestion suite: **22 tests PASS**, **94.3 s**, within verification.
  Source-catalog suite: **7 tests PASS** in **2.553 s** separately, and also
  passed within final verification. Lifecycle/gap/variable-sharing controls
  passed separately in **12.218 s**.
- `compare.sh master <worktree> --quick`: **PASS**, accuracy identical in all
  **9 cases** (10 benchmark points); 9 runs executed, 10 results reused,
  303 s wall. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/5041ce4b_vs_cf345524-d8a7c29c4_quick/report.md`.
- `compare.sh master <worktree> --full`: **PASS**, accuracy identical in all
  **22 measured cases** (23 including the fuzzer); 48 runs executed, 9
  results reused, 1064 s wall. All six initial timing flags cleared in paired
  reruns, including scale l spq16 (normalized 138.2 s master / 137.5 s
  candidate). The 100-KB fuzzer retained the same 5 flagged KBs as master;
  none was introduced by this change. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/5041ce4b_vs_cf345524-d2387cd22_full/report.md`.
- `compare.sh anchor <worktree> --canary`: **PASS**, **6 cases**, **64 s**.
  Accuracy differs from the anchor in 4 cases; the harness found no regression
  beyond master, and reports the existing anchor gaps separately. Every final
  base/candidate record has exit 0. The harness retried the initial
  zero-duration exit-127 launches; 11 attempts executed, 6 results reused.
  Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_cf345524-dbc28820b_canary/report.md`.

All three comparisons used production runtime tree `1c97d2e7854f`; their build
labels differ because tests/report contents changed between freezes. The
harness identifies their executable tree as the same build.

All runtime commands used capped admission, `ulimit -v 16000000`, unset
`DISPLAY`, and stdin from `/dev/null`. `compare.sh` acquired its own per-run
capped admission. Final verification used `--slots 3` with `PETTA_JOBS=3`.
Logs are under `scratch/round2-*.log`.

### Memory and timing limits

Quick RSS increases were below 0.4%. Full scale RSS was 991.2 vs 990.6 MB
(spq4) and 1498 vs 1500 MB (spq16). Full reliable-conflict RSS was **315.6 vs
287.9 MB: +27.7 MB / +9.6%**, above the review's +5% target, though below the
standard comparison's regression threshold. The stored master accuracy run
for that same case peaked at 322.8 MB, so baseline RSS itself varies; the
current measurements do **not** establish a uniform +5% bound for every case.
No extra persistent ingestion store exists. No general speedup is claimed;
shared-machine timing varied enough to require the harness's paired reruns.

## Size

Production delta against the original base: **-9 tokens**, measured with
`o200k_base` over changed production files. This includes removal of the
single-use rule-name helper and the related installation cleanup (**-218 tokens**
relative to round 1); no unrelated code was deleted to offset the fix.
Tests add **2298 tokens** and API/runtime documentation adds **112**; total
excluding this report is **+2401 tokens**.
