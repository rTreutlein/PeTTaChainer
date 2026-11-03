# Ingestion validation report

## Design maps

- **Reference map:** preserve existing answers. Baseline is master `49ca6f37`;
  require zero changed comparison accuracy numbers and green `verify.sh`.
- **User-case map:** KE capability scenarios (`test_conditional_world_facts.py`),
  quoted KE reference content (`test_ingestion.py`), and source ingestion through
  `compileadd`, Python `add_atom`, and `add_atoms_no_check`. Raw `add-to-kb`
  accepts compiled forms; reject the same bad structural heads and STV/CTV
  fields in its facts and rule fact premises/conclusions.
- **Budget map:** input validation only, proportional to the submitted term;
  no inference, search, KB scans, or new runtime state.
- **Numeric standard:** n/a (domain validation, no inference formula changes).
- **Token budget:** core 322,097 before, 322,386 after: **+289**, within +400.
  Measured with `.venv/bin/python scripts/core_count.py .` (`o200k_base`).

## Scope and commits

Branch `ingestcheck`, worktree
`/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer/.claude/worktrees/ingestcheck`.
The private `.venv` editable mapping points at this worktree. No push or merge.
Implementation log (`git log --oneline master..`, before the report-only commit):

```text
4763bb91 Use executable implication syntax in the import scaling gate
a6896d78 Reject legacy rule wrappers and out-of-domain source truth values
```

The first code commit adds validation, API documentation and the contract
tests. The second migrates the stale scaling generator; its measured sizes
and threshold are unchanged. A final report-only commit records this evidence.

## Causes and measurements before editing core

The existing validator checked source size, negation shape/value kind, and
free statement variables. It never inspected epistemic TV ranges. The ordinary
predicate compiler treated retired `Premises`/`Conclusions` wrappers as opaque
predicate heads, producing a rule over those literal predicates.

The supplied `run_case.py` probes were run through `capped`, under the required
virtual-memory limit, with DISPLAY unset and stdin closed:

- `premises_impl raw`: all three inputs accepted. Its positive answer came
  from native inheritance (`conditional-implication`, `f1`, `f2`), masking the
  unusable legacy rule rather than validating it.
- `stv_range raw`: all three invalid values were accepted and returned unchanged:
  `(STV 1.0 1.5)`, `(STV -0.5 0.9)`, `(STV 2.0 0.5)`.
- `canary_inh_trans adapted`: passed, with proof `(by cg cf)`.
- The initial new contract run failed 51 rejection assertions. Its publication
  query also needed underscore-prefixed local Prolog variables for Janus;
  that test bookkeeping error was corrected before final validation.

The supplied disjoint scaling probe, unchanged, measured:

| Facts | Load seconds | Positive proofs | Positive median/max seconds | Negative max seconds | Peak MB |
|---|---:|---:|---:|---:|---:|
| 30 | 0.04 | 6/9 | 0.223 / 0.490 | 0.558 | 267 |
| 60 | 0.06 | 9/9 | 0.299 / 0.374 | 0.552 | 255 |

Both had zero negative false positives. The 30-fact run missed three
Inheritance judgments at budget 30; these are recorded baseline limitations,
not converted into new expectations. Large sizes remain external probes.
Raw evidence is in ignored `scratch/baseline.log`, `scratch/scale-before.log`,
and `scratch/contracts-before.log`.

## Fix and design

`validate-ingestion!` now invokes shared structural and value validation before
compilation/publication. Structural validation reuses `source_atom`'s existing
statement-position traversal, so it cannot mistake opaque predicate arguments
for executable syntax. Unsupported `Premises` and `Conclusions` heads raise
`domain_error(rule_syntax, ...)` with the supported implication/And syntax.
Unknown user predicates remain legal: an unknown name alone cannot establish
that a predicate is structural. No legacy compiler path was added.

STV concrete numeric fields must be in `[0,1]`; both CTV branches use the same
validator. PTV/FTV are already canonicalized to STV before this boundary.
Evaluated arithmetic is checked, while computed rule outputs remain schematic.
The raw compiled-addition boundary calls the same validation before source
normalization/installation, covering rule fact premises and conclusions and
leaving CPU goals to their existing execution semantics.

The TV audit confirmed the pinned compiler's union is STV, CTV, and the internal
`no-evidence` marker, which has no numeric fields. Historical distribution TV
annotations accepted syntactically by Python fail the compiler's type check;
no second domain or distribution ingestion implementation was introduced.
Distributions as predicate arguments retain arbitrary value/weight semantics.
The API documents both new domain errors and the raw/source distinction.

**Brief conflict:** the requested confidence `[0,1)` excludes the repository's
documented confidence-1 certainty endpoint (LANGUAGE_SPEC and runtime design
assumptions), used throughout the reference fixtures. The implementation keeps
1 valid and rejects confidence outside `[0,1]`, preserving the requested
no-existing-answer-change contract. This discrepancy was raised with the user;
no response had been received when the implementation proceeded.

## Tests added

`tests/test_ingestion_contracts.py` contains eight tests:

1. Legacy single/multiple-conclusion and nested/wrong-position wrappers reject
   through every ingress, without fact/rule publication or Python replay entry.
2. Strength/confidence lower and upper violations, evaluated arithmetic, and
   either bad CTV branch reject through every ingress.
3. Explicit PTV/FTV reject after their existing kind canonicalization.
4. Raw compiled rules reject invalid fact premises/conclusions; validation
   leaves unbound computed branches/fields uninstantiated.
5. Valid boundaries, computed rule TVs, supported multiple conclusions, quoted
   legacy-looking content, and ordinary unknown predicates remain accepted.
6. Distribution arguments retain their semantics; historical distribution TV
   annotations continue to fail their existing compiler type check.
7. Member-through-Inheritance canary with all three current-syntax wmtm rules;
   negative control requires no supporting proof. A population-prior estimate
   is explicitly not treated as a derivation; the positive proof names both
   canary observations.
8. Small disjoint chains (4 versus 8; 12 versus 24 facts), alternating class
   and Implies chains. Every selected positive goal must have a supporting
   proof, and deterministic Prolog inference work must grow by less than 2.75x
   when size doubles. Wall time is not an assertion.

Focused run: **8 tests PASS**, 5.082 seconds on the recorded run.
The exact small-fixture work probe measured **11,159,667** versus
**24,293,088** Prolog inferences, a **2.1769x** ratio. It also confirmed direct
ingestion and budget-zero reading of the numeric-field-free `no-evidence`
marker. Evidence: `scratch/work-probe.log`.
No existing expected test values were changed.

## Gates and benchmark evidence

The first `verify.sh` run passed the suites, judgment scaling and ConceptNet
but correctly rejected the import-scaling generator's own retired rule syntax.
That fixture had been installing literal Premises/Conclusions rules, masking
the intended executable-rule workload. It now generates
`(Implication (ImportScalingSourceN $x) (ImportScalingTargetN $x))` with the
same CTV, 8,000 statements, four 2,000-statement chunks, and 1.5 growth limit.
Focused import scaling passed: 3.107, 3.663, 4.196, 3.270 seconds;
late/early ratio **1.103**. Evidence: `scratch/import-fixed.log` and
`scratch/verify-before-fixture-fix.log`.

Final `scripts/verify.sh`: **PASS**, exit 0, **303 seconds**. The suite ran
163 MeTTa files (0 failures) and 1,059 Python tests in 75 files / 602 units
(24 existing expected failures, 1 skip, 233.5 seconds). MeTTa lint, import
scaling, judgment scaling and ConceptNet all passed. Query metrics recorded
4,607 Python rows and 3 judgment-scaling rows with **zero aborts**.
Import scaling's final chunk times were 2.931, 2.868, 2.800, 2.851 seconds;
late/early ratio **0.974** against the unchanged 1.5 limit. The gate recorded
PASS under verify-cache key prefix `746c39ae87f6`.
Evidence: `scratch/verify.log`; the report-only commit does not change gate inputs.

All PeTTa/test processes used `capped` (eight slots and `PETTA_JOBS=8` for
verify), `ulimit -v 16000000`, DISPLAY unset, and stdin `/dev/null`.
Comparisons used the prescribed `compare.sh` with
`PETTACHAINER_REPO` pointing at this worktree; the runner caps its own jobs.

| Comparison | Verdict | Accuracy summary | Cases / fresh runs / reused | Wall seconds |
|---|---|---|---|---:|
| master quick | PASS | accuracy changed in 0 cases; identical in all 9 comparable cases | 10 / 9 / 10 | 97 |
| master full | PASS | accuracy changed in 0 cases; identical in all 22 comparable cases | 23 / 38 / 9 | 235 |
| anchor canary | PASS | accuracy changed in 4 of 6 cases, inherited from master | 6 / 11 / 6 | 85 |

Reports:

- `/nexus/Dev/OpenCog/bench/results/compare/49ca6f37_vs_49ca6f37-d739f9a0f_quick/report.md`
- `/nexus/Dev/OpenCog/bench/results/compare/49ca6f37_vs_49ca6f37-d9ee1eddf_full/report.md`
- `/nexus/Dev/OpenCog/bench/results/compare/anchor-b4065459_vs_a6896d78_canary/report.md`

All candidate benchmark runs exited zero. The full fuzzer retained 5 flagged
KBs on each side, with no newly flagged KBs, unsupported KBs or crashes.
The two replay streams (200 beliefs each) were identical to master.
The full comparison's initial learned-s2 timing flag (21.4 to 24.05 seconds)
did not recur in its required paired rerun (21.29 to 21.21), so it was not
counted as a regression. Other representative paired times were scale-l
spq16 193.34 to 194.39 seconds and the mined-learning case 105.34 to 105.09.
The larger scale-l spq4 table difference (42.76 to 67.26 seconds) reuses
unequally loaded runs and is not comparable timing evidence.

Canary accuracy changes from anchor to candidate, all present on master too:

| Case | Anchor error | Candidate error |
|---|---:|---:|
| live b50 5 shifts s1 | 0.09813 | 0.105 |
| conflict pln-stated l spq4 s1 | 0.3895 | 0.03181 |
| conflict pln-reliable l spq4 s1 | 0.107 | 0.05407 |
| scale m spq4 r10 s1 | 0.003034 | 0.002647 |

The live canary's Brier moved 0.02632 to 0.03195 and regret 59.78 to 72.78
versus anchor; these are inherited master deficits, not claimed improvements.
The canary report lists seven inherited anchor flags, zero blocking regressions
and zero cases improved over master. Its master/reference comparison found
no changed accuracy numbers. Benchmarks share candidate runtime tree
`892ef302350f`; the later commit changes only the verification fixture, outside
that core tree. No scheduling/budget/anytime change requires curves.

## Limits

- Validation covers executable statement positions, not quoted application data.
- Arbitrary unknown predicate heads are legal; the check reserves the identified
  retired structural wrappers instead of trying to infer application vocabulary.
- Unbound formula outputs cannot be numerically validated without running
  inference. Their existing runtime behavior is unchanged.
- The small scaling test bounds work on its fixtures; it does not establish an
  asymptotic guarantee or solve the large wmtm workload's memory/time limits.
- Confidence 1 is deliberately retained for the documented certainty semantics.
