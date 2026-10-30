# Antecedent-completion recipe: final follow-up

Branch: `completion-recipe`.
Worktree: `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/completion-recipe`.
Base/master: `80ea56284ada130c87dc0f261f0aa0c826752fba`.

The first implementation (`202619a0`, documented in `c6c6891e`) compiled
completion roles but retained the recipe on executable inputs. Its learned
mined b50 peak RSS rose from 607.0 to 788.7 MB. This report records the
once-per-rule follow-up and supersedes that implementation and its measurements.

The resumed audit confirmed that `6c0a9d2c` already completed the requested
storage and classifier cleanup. No further production or test edits were needed.
The full comparison's learned mined b50 peak is **608.4 -> 605.7 MB (-0.44%)**;
a fresh paired dev-server run confirms **610.3 -> 607.6 MB (-0.44%)**. Both
meet the requested +5% limit. Core tokens and executable lines both decrease.

## Storage diagnosis and final design

The leading `ReadLikelihoodContext` instruction retained the full variable-sharing
recipe in the executable inputs. Rule indexes, partial joins, retained rows and
fresh evaluation copies therefore carried the target, compound and context again.
The recipe was input data, not a proof-DAG node. Its unused context result did not
justify retaining that instruction.

Registration now consumes the compiler marker before constructing any rule index.
`&completion_recipe`, indexed first by the existing rule id, holds three ground
scalars once per compiled completion: observation statement ordinal, compound
contextual-instruction ordinal and opening polarity. Rows retain their existing
owner id and executable inputs; no recipe instruction, extra row field or recipe
copy enters a row or proof. Raw `add-to-kb` rules prepare the same scalar metadata
once at registration. Temporary metadata follows the backend's existing clause
references, and rule withdrawal removes permanent metadata.

The contextual ordinal addresses instructions that survive ground-CPU removal;
the observation ordinal counts statement inputs only. The native projection borrows
the original input terms, including their open registered keys and TV/proof
variables, and splits the sibling/observation/tail reads by those positions.
Evaluation preserves the original instruction and evidence order. No numerical
read, exclusion, closed-pin, opening-condition or evidence policy changed.

Two implementation constraints are now explicit. A synthetic population-prior row
borrows its requesting completion's owner id but is not that compiled template:
its missing contextual instruction naturally selects ordinary evaluation. Also,
projecting executable inputs through `collapse` would copy their variables away
from the row's conclusion. The native boundary selects the indexed metadata and
projects directly, without a `findall` of row data. Regression tests cover both
conditions, shared output-variable identity, cold answers, raw And/Or and polarity
parity, refined-truth registration, and multiple rows sharing one ground recipe.

## Deletion and size

The follow-up deletes these production MeTTa functions:
`completion-recipe-of`, `statement-input-step`, `sk-completion-state`,
`sk-completion-position-step`, `sk-completion-premise-step`,
`sk-completion-proof?`, `sk-condition-evidence`,
`store-rule-expected-score!`, and `register-truth-premise!`.
The initial implementation also deleted `sk-compound-evidence-step`,
`sk-last-statement-step` and `sk-completed-given-step`.
There are zero references to these names in `pettachainer/`, `third_party/`,
`tests/` or `docs/`. Positional sibling reading replaces the consequence/sibling
shape classifier; waiter and evidence routing no longer classify completion proof
heads. `sk-leaf-premise-step` and `sk-without-hash-step` remain live typed fold
boundaries required by strict specialization, rather than test scaffolding.

The compiler marker, raw preparation and policy readers remain MeTTa. The native
code only selects the indexed descriptor and projects the existing instruction
list while preserving variable identity. No inference policy moved to Prolog.
The skeleton changes are limited to the requested completion-classifier deletion
and sharing the contextual-instruction predicate with registration.

| Core scope | Original base 80ea5628 | Previous c6c6891e | Follow-up | Change from original |
|---|---:|---:|---:|---:|
| o200k tokens | 323,864 | 323,664 | 323,166 | -698 |
| Executable lines | 16,088 | 16,122 | 16,087 | -1 |
| Named-function change | 0 | +1 | -3 | -3 |

The follow-up itself removes 498 tokens, 35 executable lines and four named
functions. Core plus unchanged third-party tokens: 340,851, down 698 from the
original 341,549. Counts use the supplied scripts and include production MeTTa,
Prolog and Python; Python and third-party code are unchanged. Logs:
`scratch/followup-counts.log`, `scratch/followup-symbols.log`.

Fresh counts reproduce these totals (`scratch/resume-counts.log`,
`scratch/resume-core-count.log`). A fresh audit also finds zero hits for all
twelve names deleted across the initial implementation and follow-up
(`scratch/resume-symbol-audit.log`, empty on success). Counts follow the supplied
counter's benchmark/simulation exclusions. Raw registration still recognizes an
unmarked compiled completion once, as required by public `add-to-kb`; evaluator,
waiter and evidence routing use the indexed metadata.

## Validation and measurements

- Strict MeTTa suite: PASS, 162 passed, 0 failed
  (`scratch/followup-metta-gate.log`).
- Focused recipe tests: PASS, 3 tests including four raw-ingestion subcases
  (`scratch/followup-python-confirmed.log`).
- Evidence-role tests: PASS, 4 tests, unchanged expected values
  (`scratch/followup-evidence-gate.log`). The collector test now exercises the
  actual row-result path instead of a deleted internal helper.
- Required verify with 16 admission slots: **PASS**, exit 0, all six gates,
  358 s wall. MeTTa: 162 passed, 0 failed. Python: 991 tests in 63 files /
  591 units, 64 expected failures and 1 skip; 4,495 query rows, 0 aborts.
  Import scaling, judgment scaling (3 query rows, 0 aborts) and ConceptNet
  passed. Log: `scratch/resume-verify.log`. The runner did not record a cache
  entry because this report was edited during the run; production and test
  files remained at `6c0a9d2c` throughout. ConceptNet's strict defect counter
  is unavailable; that gate checks the result-row count and abort markers.
- Required full comparison with master: **PASS**, 23 cases, identical numeric
  accuracy in all 22 summarized cases; fuzzer flags unchanged (6 -> 6), no crashes.
  All 45/45 results reused for the identical production runtime tree. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/80ea5628_vs_6c0a9d2c-daa2f2ec0_full/report.md`.
  Learned stage 3 untimed mined b50/r50/h10/s3 peak RSS: **608.4 -> 605.7 MB
  (-0.44%)**, below +5% (638.82 MB). Compared with the original 607.0 MB master
  observation, 605.7 MB is -0.21%; the previous candidate consumed 788.7 MB.
  These are process peaks, not live-heap measurements.
- Required anchor canary: **PASS**, trusted identical-tree verdict reused
  (key `9e30fbc2f699`, original 2026-10-30T01:51:40), no new runs. Four of six
  cases differ in accuracy from the older anchor; those differences are present
  on master too. Nine inherited anchor gaps, no blocking regression. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_6c0a9d2c-daa2f2ec0_canary/report.md`.
- Paired dev-server full-case retimes: **PASS** for all four cases. The full
  report has no confirmed flag,
  but four apparent slowdowns were excluded because load differs: timed b50/s3,
  untimed soft0.9, reliable conflict l, and learned untimed mined b50. Each is
  retimed with `BENCH_TIMING_FULL=1 ... --full --only <case> --timing --retime`.
  All eight fresh host runs exited 0 at load 1, with identical accuracy and
  no timing flags. The matched learned host run also confirms peak RSS
  **610.3 -> 607.6 MB (-0.44%)**. Logs:
  `scratch/resume-paired-retimes.log`, `scratch/resume-canary-paired.log`.
- Fresh paired canary against master: **PASS**. The standard
  `master <worktree> --canary --timing --retime` checks all six canary cases
  behind the inherited anchor flags. All 12 fresh host runs exited 0 at load 1,
  with identical accuracy and no confirmed timing flags. Report:
  `/nexus/Dev/OpenCog/bench/results/compare/80ea5628_vs_6c0a9d2c-dea2921dc_canary-retime-20261030T020300/report.md`.

Fresh paired dev-server job wall seconds (master -> candidate):

| Full-case retime | Master | Candidate |
|---|---:|---:|
| Stage 3 timed b50/s3 | 13.17 | 13.02 |
| Stage 3 untimed soft0.9 b100/s4 | 45.94 | 44.97 |
| Reliable conflict l/spq4/s1 | 62.96 | 62.61 |
| Learned stage 3 untimed mined b50/r50/h10/s3 | 88.55 | 88.43 |

| Canary retime | Master | Candidate |
|---|---:|---:|
| Live b50, 5 shifts, s1 | 10.36 | 10.36 |
| Reliable conflict l/spq4/s1 | 62.79 | 62.61 |
| Scale m/spq4/r10/s1 | 35.43 | 35.23 |
| Stated conflict l/spq4/s1 | 25.95 | 25.85 |
| ONA conditioning s1 | 10.53 | 10.55 |
| ONA identity matching s8 | 14.43 | 14.37 |

Reports (under `/nexus/Dev/OpenCog/bench/results/compare/`):

- `80ea5628_vs_6c0a9d2c-daa2f2ec0_full-stage_3_timed_b50_s3-retime-20261030T020055/report.md`
- `80ea5628_vs_6c0a9d2c-dea2921dc_full-stage_3_untimed_soft0.9-retime-20261030T020251/report.md`
- `80ea5628_vs_6c0a9d2c-d1d548c94_full-pln-reliable_l-retime-20261030T020545/report.md`
- `80ea5628_vs_6c0a9d2c-d1d548c94_full-stage_3_untimed_learned_mined-retime-20261030T021057/report.md`

No existing expected truth value, proof, scheduler score or public signature was
changed. The `EXPECTED_FAILURES` set was not edited. Earlier failed development
runs are not final gate evidence. In
particular, the original HEAD was rechecked in this worktree and passed its two
recipe tests before the candidate was restored. No master, other-worktree,
shared-venv, remote-branch, GitHub or admission-service changes were made.

Implementation commit: `6c0a9d2cae8343b98f98895e35e30e9d2ad4c0d2`.
The benchmark runtime identity is `35cb9f15a090`. The harness reused runs labeled
`c6c6891e-d3a0287b4`, explicitly recording their identical runtime tree in the
full report. A subsequent documentation-only commit records these final results.

## Execution rules and limits

All resumed PeTTa, test and benchmark commands used the pinned worktree
environment, `/nexus/Dev/OpenCog/bench/capped`, `ulimit -v 16000000`, unset
`DISPLAY`, and stdin from `/dev/null`. Verify used 16 admission slots and
`PETTA_JOBS=16`. The harness owns benchmark profiles, builds, cases and seeds;
no custom runner or frozen build was introduced.

The existing numerical expected failures and skipped nightly test remain suite
limitations. Earlier failed development runs are not final gate evidence.
No master/main/other-worktree code, shared venv, remote branch, GitHub state or
admission service was changed. Standard verify-cache, runtime-cache and
benchmark-output writes are runner-owned. No push or merge was performed.
Commits use the exact trailers from the brief.
