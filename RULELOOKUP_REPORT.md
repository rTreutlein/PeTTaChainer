# Rule lookup keyed by its real key (shared-profile proposal 3)

Branch `rulelookup` from master `cf0c57da`.

## Design maps (written before coding)

### Reference map

Every query answer and proof stays the same. The change replaces where a rule
row is read from, never what is read: `rules` rows and `ccls_index` rows hold
the same three fields (conclusion, id, premises), written together in
`kb-add-rule!`, in the same order and through the same backend (`assertz` with
clause references for temp rules), and removed together in
`remove-rule-row!`. So each reader gets the same rows in the same order from
`ccls_index`, and the dormancy budget, which depends on visit order, spends
alike. Checked by `compare.sh` (accuracy changed in 0 cases) and `verify.sh`.

### User-case map

- ConceptNet answers identical: the existing export `rules_dump.qlf` carries
  `ccls_index/3` with every rule, so the runtime reads it unchanged. Its
  `rules/4` rows are loaded and no longer read. The export is not regenerated.
- KE capability fixtures (`tests/test_conditional_world_facts.py` and the
  rest of the Python suite) are unchanged.
- Wildcard-head rules: a rule with a variable head stays one `ccls_index`
  row and unifies with every head lookup exactly as it did with `rules`;
  indexing never decides unification.
- Occurs checks: `rule-lookup-needs-occurs-check` and
  `ccls-index-occurs-matches` are untouched.
- Export ABI: `docs/metta/API.md` lists no rule-row shape; nothing in it
  changes. The cnet exporter's `rules` line exports nothing afterwards; the
  other four sections are the ones the runtime reads.

### Budget map

No new work. Every change is a lookup reading another store keyed for the
lookup; nothing is scheduled, cached or computed in addition. The deleted
store also removes one write and one removal per installed rule.

## Measurement (before coding)

ConceptNet Own/Pet query at budget 100, master code (worktree, own venv),
`rules_dump.qlf` consulted, four facts added, query alone timed.

rules/4 call census (wrapping `rules/4`, caller and bound arguments):

| Caller | Bound key | Calls | Solutions |
|---|---|---:|---:|
| `dormancy_supported/5` (application_support.pl) | conclusion head + KB | 80,794 | 143,399 |
| `dormancy_analysis/3` | rule id | 3,476 | 3,476 |
| `sk-store-wait!/5` (search_state.pl) | rule id | 2,289 | 2,289 |

Profile: `rules/4` 38.6% self (86,559 calls), `rule_expected/2` 4.9%.
SWI already builds JIT indexes for `rules/4`: a hash on argument 2 (id) and a
deep hash on argument 3's statement head. Timing those builds alone on the
export: id hash 0.24 s, deep head hash 0.67 s, `rule_expected` id hash 0.12 s;
afterwards a lookup costs microseconds (10,000 id or head lookups: under 3 ms).
So the self cost is index construction over the 1,043,688 exported rows, not
scanning. The head index duplicates `ccls_index`'s deep head index, which
`sk-rule-match` already builds.

All other `rules` readers, found by grep (none hot on ConceptNet), bind the
rule id: `kb-add-rule!` (named reuse), `remove-rule-row!`,
`sk-premise-rules-step`, the scaffold check in `skeleton.metta`,
`sk-activate-rule-step`, `sk-judgment-main-rule-match`,
`discover-triggered-applications`, `context-rule-rows`, `fresh-rule-id`.
`set-functional-predicate` binds head and KB, as dormancy does.

## Design

`rules` (`runtime-rule-row Id Conclusion Premises`, constant first column)
and `ccls_index` (`Conclusion Id Premises`) held the same rows. `rules` is
deleted with its datatype; `ccls_index` is the one rule store:

- head lookups (dormancy, functional declaration, rule matching) hit its
  first-argument deep index on the conclusion head, which rule matching
  already builds;
- id lookups bind its second column, where SWI's JIT hash serves them.

A separate id-first store was the alternative. It would duplicate every
rule again, and the existing ConceptNet export has no such rows, so the
ConceptNet gate could not read it without regenerating the 1.2 GB export.

## Results

Commit `cc6274de` on `rulelookup`.

- ConceptNet query, paired and interleaved (master frozen build
  `cf345524-d8a7c29c4`, same tree as `cf0c57da`, against this branch, 3 pairs,
  same export and facts): master 2.687 / 2.780 / 2.771 s, branch
  2.286 / 2.347 / 2.322 s. Mean 2.746 s goes to 2.318 s, **-15.6%**. Inferences
  are the same (23.05M) and the two answers are identical, proofs and STVs
  included. In `verify.sh` the gate's own query took 2.44 s.
- Profile after the change: `rules/4` is gone and `ccls_index/3` is 28.4% self
  (it was 38.6% + 1.0% for the two stores). What remains is mostly the one-time
  SWI JIT hash on its id column (0.53 s on the export, measured alone).
- Tokens (`scripts/core_count.py`): core 322,289 -> 322,097 (**-192**).
  All changed files including tests: -411. Diff +55/-78 lines.
- Gates: `verify.sh` PASS (lint, MeTTa 163/163, Python with 4,592 query rows
  and 0 aborts, import and judgment scaling, ConceptNet with 2 results).
- `compare.sh master <wt> --quick`: PASS, accuracy changed in 0 cases.
- `compare.sh master <wt> --full`: PASS, accuracy identical in all 22 cases,
  StationOps belief streams identical, fuzzer 5 -> 5 with none newly flagged.
  Suite seconds: supplynet -3%, scale -8%, conflict +1%, learned -0%,
  replay -14%, combinet -26%, fuzz -24%, with no flags. Outside ConceptNet
  these differences are noise: those workloads hold a few hundred rules.
  Report: `bench/results/compare/cf0c57da_vs_cf0c57da-d1c68bd12_full/report.md`.
- Canary `compare.sh anchor <wt> --canary`: PASS. The 4 accuracy changes
  against the anchor are master's own (for example, pln-reliable 0.05407 on
  both master and the branch).

Moved test values: none. Tests that read or planted `rules` rows now use
`ccls_index` rows. `test_source_catalog` used to reorder the premises of the
`rules` copy only; it now reorders the single store and restores it.

## Limits

- Lookups by id use SWI's JIT hash on `ccls_index`'s second column, not a first
  column. Building that hash over the 1M-rule export costs about 0.5 s once per
  process, against 0.2 s for an id-first store. A dedicated id-first store
  would save about 0.3 s more on ConceptNet, but it would duplicate every rule
  again, and the existing export has no such rows. It would need the cnet
  exporter changed and the export regenerated, which is outside this round.
- The existing export still loads its 1,043,688 `rules/4` rows (one of its
  five sections), and nothing reads them now. The cnet exporter
  (`cnet/pettachainer_tools.py`, the `rules` line) should drop that section
  the next time the export is regenerated. Until then that section comes out
  empty.
- `rule_expected/2` (4.9%) is again the one-time JIT build of its
  first-argument hash. It is not changed here.
- The remaining ConceptNet cost in `ccls_index/3` per call is clause copying
  for dormancy's head walk (80,794 calls, 143,399 solutions). That is the
  dormancy algorithm, not its lookup key.
