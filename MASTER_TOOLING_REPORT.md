# Master tooling round (Nov 5)

Branch `master-tooling` from master `c43ecb01`, worktree
`.claude/worktrees/master-tooling`. Brief: `fresh-design/dp-tooling-brief.md`,
from `fresh-design/test-classification.md`. No `pettachainer/` or `third_party/`
change: no semantics or values move.

## Gates

- `scripts/verify.sh` (capped, 8 workers): **PASS**, 167 s (run beside a
  `compare.sh`); 147 s alone (that run's fuzzer gate failed on a report-table
  bug, fixed since). Master before: **346 s**, Python suite 265.9 s.
- `compare.sh master <worktree> --quick`: **PASS**, accuracy changed in 0 cases
  (10/10 results reused: the chainer tree is master's).
- Fuzzer gate alone: exit 0, 37.6 s, 3 known BLOCKERs, 0 new, 0 fixed.

## Verify time, before and after

| | before (master) | after |
|---|---:|---:|
| verify.sh wall | 346 s | 147-167 s |
| Python suite wall | 265.9 s | 92-107 s |
| Python units / unit CPU-s | 639 / 2,128 | 86-89 / 732-851 |
| tail gates | 57 s in series | about 40 s at once, fuzzer included |

**Root cause of most of the cost:** `scripts/test_python.py` split a file over
its share into one process per test. `test_tv_calibration.py` (528 tests) was
split, each process paid the library load (7-10 s each, 1,080 CPU-s for about
100 s of tests), and the inflated file total kept it split for good, a ratchet.
Now a split file runs as parts of about half a share, balanced by the recorded
test durations, so a part pays the load once. A part fails unless it ran every
test it selected.

## Changes

1. **Fuzzer gate.** `scripts/fuzz_vs_problog.py --gate` runs the quick seed-1
   campaign: 21 event cases and 3 ProbLog KBs. `tests/fuzz/run.py` gains `KNOWN`,
   master's 3 open BLOCKERs (`leaf-report-{And,Or,Not}-1` flip: the premise stays
   at its prior .4, the unsupported STV model in ke2-review-codex). The gate fails
   on any other BLOCKER, on a known one that no longer occurs, or on a ProbLog
   differential flag. Known flags are not shrunk. The test is in
   `test_fuzz_events.py`.
2. **verify.sh.** Import scaling, judgment scaling, ConceptNet and the fuzzer
   gate run at once after the Python suite. Status goes through files, and each
   gate's output is printed when all are done.
3. **Tests that checked nothing:**
   - `test.metta`, 5 `ccls_index` checks: rewritten to the real row shape
     `((Type Scope Proof TV) Id Premises)`. The four "ok" checks now require the
     compiled row (`ok`). The "bad" check requires that the fact-wrapped fold is
     absent (`()`).
   - `forward_incremental_base_rates`: the tautology is replaced by the exact
     ordered set of the three fold hashes. The `excludes-one?` helper is deleted.
   - `test_posterior_fixture_audit.py`: it now reads the pins from the cited
     .metta files. Strengths: all 64 present and equal to the oracle (pass).
     **Real failure found:** 43 of 63 confidence pins are outside a factor 2 of
     the oracle variance. That check is an `expectedFailure` with the reason.
   - `test_conditional_world_facts.py:79`: the vacuous `c >= 0` is deleted.
   - `examples/metta/existential_residual.metta`: it now asserts D ≤ E, and that
     D rises and U falls after felix.
   - Nested tests: the classification counted 31, but 16 of those were
     `test-main-facts`/`test-selected-facts` selectors. There are really **15
     forms, 21 asserts, 10 files**. Each is lifted so that a failed binding fails
     the test: `!(test (let* ...) Y)`, or `=alpha` where Y used let-bound
     variables, or `data`/tuple for the progn groups.
4. **Time cuts:**
   - The 110 s ingestion variable-head test is deleted. It duplicated
     `test_var_head.metta`, which gains its concrete-head control: the same pin
     .8642193246799066/.02243916988834716, ground, open and warm.
   - The 3 `repeated_queries` xfails run nightly (`PETTACHAINER_NIGHTLY`).
   - `context_overlay`: only the 3 world-write checks from 00a05e56 run at both
     thresholds; the rest run at 0 (27 test runs to 17).
   - `bridge_query_order`: confidence 0.5 dropped. 0.9 and certain 1.0 are kept.
5. **Docs.** `agent_workflow.md` and `fuzzing.md`.

## Moved test values

None. The new expectations are the stored rows, structural invariants and the
existing pin.

## Limits and risks

- Running the tail gates at once oversubscribes 8 slots by 3 for about 20 s.
  Import scaling is a wall-time ratio (it fails only on monotone growth), so
  there is a small flake risk.
- The gate needs ProbLog's interpreter (`ChainerGame-problog`).
- On a gate failure the repros live in verify's temporary directory. Rerun
  with `--gate --out` to get them.
- Part balancing uses per-test durations recorded when tests ran alone. These
  stop refreshing once a file runs in parts.
- Coverage given up: the 0.5 bridge confidence, threshold 1e-6 for 10 overlay
  tests, and the xfails' per-verify unexpected-pass check.
- No snapshot pins were converted. The fixture-audit confidence question is
  open.
